import '../model/widget_scene_node.dart';

class InspectorTreeParser {
  List<WidgetSceneNode> parseRoot(
    Map<String, Object?> rootJson, {
    required bool userCodeOnly,
  }) {
    final nodes = <WidgetSceneNode>[];
    final root = _parseNode(
      rootJson,
      parentId: null,
      depth: 0,
      nodes: nodes,
      userCodeOnly: userCodeOnly,
    );
    if (root == null) {
      throw StateError('Inspector tree did not contain a root node.');
    }
    return nodes;
  }

  WidgetSceneNode? _parseNode(
    Map<String, Object?> json, {
    required String? parentId,
    required int depth,
    required List<WidgetSceneNode> nodes,
    required bool userCodeOnly,
  }) {
    final description = json['description'] as String? ?? 'Widget';
    final diagnosticsId =
        json['valueId'] as String? ?? json['locationId'] as String? ?? description;
    final valueId = json['valueId'] as String?;
    final createdByLocalProject = json['createdByLocalProject'] == true;

    if (userCodeOnly && depth > 0 && !createdByLocalProject) {
      return null;
    }

    CreationLocation? creationLocation;
    final creationJson = json['creationLocation'];
    if (creationJson is Map<String, Object?>) {
      creationLocation = CreationLocation.fromJson(creationJson);
    }

    final childJson = json['children'];
    final childNodes = <WidgetSceneNode>[];
    if (childJson is List) {
      for (final child in childJson) {
        if (child is! Map<String, Object?>) continue;
        final parsed = _parseNode(
          child,
          parentId: diagnosticsId,
          depth: depth + 1,
          nodes: nodes,
          userCodeOnly: userCodeOnly,
        );
        if (parsed != null) {
          childNodes.add(parsed);
        }
      }
    }

    final node = WidgetSceneNode(
      diagnosticsId: diagnosticsId,
      description: description,
      valueId: valueId,
      parentId: parentId,
      depth: depth,
      createdByLocalProject: createdByLocalProject,
      creationLocation: creationLocation,
      children: childNodes,
    );
    nodes.add(node);
    return node;
  }

  void applyLayout(
    List<WidgetSceneNode> nodes,
    Map<String, Map<String, Object?>> layoutByValueId,
  ) {
    final order = [...nodes]..sort((a, b) => a.depth.compareTo(b.depth));
    for (final node in order) {
      final index = nodes.indexWhere((n) => n.diagnosticsId == node.diagnosticsId);
      if (index < 0) continue;
      final current = nodes[index];
      final valueId = current.valueId;
      if (valueId == null) continue;
      final layout = layoutByValueId[valueId];
      if (layout == null) continue;

      final size = parseLayoutSize(layout);
      final localOffset = parseParentDataOffset(layout);
      if (size == null) continue;

      final byId = {for (final n in nodes) n.diagnosticsId: n};

      SceneRect? rect;
      if (current.depth == 0 || current.description.contains('RenderView')) {
        rect = SceneRect.fromLTWH(0, 0, size.width, size.height);
      } else {
        WidgetSceneNode? findParentRenderNode(WidgetSceneNode current) {
          var parent = current.parentId != null ? byId[current.parentId] : null;
          while (parent != null) {
            if (parent.size != null) return parent;
            parent = parent.parentId != null ? byId[parent.parentId] : null;
          }
          return null;
        }

        final parent = findParentRenderNode(current);
        final parentRect = parent?.rect ?? SceneRect.zero;
        final offset = localOffset ?? SceneOffset.zero;
        rect = SceneRect.fromLTWH(
          parentRect.left + offset.dx,
          parentRect.top + offset.dy,
          size.width,
          size.height,
        );
      }

      nodes[index] = current.copyWith(
        size: size,
        localOffset: localOffset,
        rect: rect,
      );
    }
  }

  WidgetSceneNode rebuildTree(List<WidgetSceneNode> flatNodes) {
    final byId = {for (final n in flatNodes) n.diagnosticsId: n};
    WidgetSceneNode attach(WidgetSceneNode node) {
      final children = flatNodes
          .where((n) => n.parentId == node.diagnosticsId)
          .map(attach)
          .toList();
      return node.copyWith(children: children);
    }

    final root = flatNodes.firstWhere(
      (n) => n.parentId == null,
      orElse: () => flatNodes.first,
    );
    return attach(byId[root.diagnosticsId] ?? root);
  }
}
