class SceneOffset {
  const SceneOffset(this.dx, this.dy);
  static const zero = SceneOffset(0, 0);
  final double dx;
  final double dy;
}

class SceneSize {
  const SceneSize(this.width, this.height);
  final double width;
  final double height;
}

class SceneRect {
  const SceneRect(this.left, this.top, this.width, this.height);
  factory SceneRect.fromLTWH(double left, double top, double width, double height) {
    return SceneRect(left, top, width, height);
  }
  static const zero = SceneRect(0, 0, 0, 0);
  final double left;
  final double top;
  final double width;
  final double height;
  bool contains(double x, double y) {
    return x >= left && y >= top && x <= left + width && y <= top + height;
  }
}

class CreationLocation {
  const CreationLocation({
    required this.file,
    required this.line,
    required this.column,
    this.name,
  });

  factory CreationLocation.fromJson(Map<String, Object?> json) {
    return CreationLocation(
      file: json['file'] as String? ?? '',
      line: _parseInt(json['line']),
      column: _parseInt(json['column']),
      name: json['name'] as String?,
    );
  }

  final String file;
  final int line;
  final int column;
  final String? name;

  String get displayLabel {
    if (file.isEmpty) return 'unknown';
    final parts = file.split(RegExp(r'[/\\]'));
    final short = parts.isNotEmpty ? parts.last : file;
    return '$short:$line';
  }
}

class WidgetSceneNode {
  WidgetSceneNode({
    required this.diagnosticsId,
    required this.description,
    this.valueId,
    this.parentId,
    this.depth = 0,
    this.createdByLocalProject = false,
    this.creationLocation,
    this.rect,
    this.localOffset,
    this.size,
    this.children = const [],
  });

  final String diagnosticsId;
  final String description;
  final String? valueId;
  final String? parentId;
  final int depth;
  final bool createdByLocalProject;
  final CreationLocation? creationLocation;
  final SceneRect? rect;
  final SceneOffset? localOffset;
  final SceneSize? size;
  final List<WidgetSceneNode> children;

  WidgetSceneNode copyWith({
    SceneRect? rect,
    SceneOffset? localOffset,
    SceneSize? size,
    List<WidgetSceneNode>? children,
  }) {
    return WidgetSceneNode(
      diagnosticsId: diagnosticsId,
      description: description,
      valueId: valueId,
      parentId: parentId,
      depth: depth,
      createdByLocalProject: createdByLocalProject,
      creationLocation: creationLocation,
      rect: rect ?? this.rect,
      localOffset: localOffset ?? this.localOffset,
      size: size ?? this.size,
      children: children ?? this.children,
    );
  }

  Map<String, Object?> toSceneJson() {
    final rect = this.rect;
    return {
      'id': diagnosticsId,
      'valueId': valueId,
      'label': description,
      'depth': depth,
      'parentId': parentId,
      'createdByLocalProject': createdByLocalProject,
      if (creationLocation != null)
        'location': {
          'file': creationLocation!.file,
          'line': creationLocation!.line,
          'column': creationLocation!.column,
          'label': creationLocation!.displayLabel,
        },
      if (rect != null)
        'rect': {
          'left': rect.left,
          'top': rect.top,
          'width': rect.width,
          'height': rect.height,
        },
    };
  }
}

class WidgetSceneSnapshot {
  const WidgetSceneSnapshot({
    required this.nodes,
    required this.root,
    required this.logicalWidth,
    required this.logicalHeight,
    this.pngBase64,
    this.screenshotWarning,
    this.objectGroup,
    this.screenshotId,
  });

  final List<WidgetSceneNode> nodes;
  final WidgetSceneNode root;
  final double logicalWidth;
  final double logicalHeight;
  final String? pngBase64;
  final String? screenshotWarning;
  final String? objectGroup;
  final String? screenshotId;

  WidgetSceneSnapshot copyWith({
    String? pngBase64,
    String? screenshotWarning,
  }) {
    return WidgetSceneSnapshot(
      nodes: nodes,
      root: root,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      pngBase64: pngBase64 ?? this.pngBase64,
      screenshotWarning: screenshotWarning ?? this.screenshotWarning,
      objectGroup: objectGroup,
      screenshotId: screenshotId,
    );
  }

  Map<String, Object?> toSceneJson({bool hideOuterShells = false}) {
    return {
      'logicalWidth': logicalWidth,
      'logicalHeight': logicalHeight,
      if (pngBase64 != null) 'pngBase64': pngBase64,
      'nodes': visibleNodes(hideOuterShells: hideOuterShells)
          .map((n) => n.toSceneJson())
          .toList(),
    };
  }

  /// Full-window wrappers (`RenderView`, `MaterialApp`, `Scaffold`, …)
  /// that paint no unique content of their own.
  List<WidgetSceneNode> visibleNodes({required bool hideOuterShells}) {
    final dropShells = hideOuterShells || pngBase64 != null;
    if (!dropShells) return nodes;
    final kept = nodes.where((node) {
      if (!isFullBleed(node)) return true;
      return false;
    }).toList();
    if (kept.any((n) => n.rect != null)) return kept;

    WidgetSceneNode? fallback;
    for (final node in nodes) {
      if (node.rect == null) continue;
      if (fallback == null || node.depth >= fallback.depth) {
        fallback = node;
      }
    }
    return fallback == null ? nodes : [fallback];
  }

  bool isFullBleed(WidgetSceneNode node, {double coverage = 0.92}) {
    final rect = node.rect;
    if (rect == null) return false;
    return rect.width >= logicalWidth * coverage &&
        rect.height >= logicalHeight * coverage;
  }
}

int _parseInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _parseDouble(Object? value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

SceneOffset? parseParentDataOffset(Map<String, Object?>? layoutJson) {
  if (layoutJson == null) return null;
  final parentData = layoutJson['parentData'];
  if (parentData is! Map) return null;
  return SceneOffset(
    _parseDouble(parentData['offsetX']),
    _parseDouble(parentData['offsetY']),
  );
}

SceneSize? parseLayoutSize(Map<String, Object?>? layoutJson) {
  if (layoutJson == null) return null;
  final direct = _sizeFromMap(layoutJson['size']);
  if (direct != null) return direct;

  final renderObject = layoutJson['renderObject'];
  if (renderObject is Map<String, Object?>) {
    final fromRender = parseLayoutSize(renderObject);
    if (fromRender != null) return fromRender;
  }

  final children = layoutJson['children'];
  if (children is List) {
    for (final child in children) {
      if (child is Map<String, Object?>) {
        final parsed = parseLayoutSize(child);
        if (parsed != null) return parsed;
      }
    }
  }

  final properties = layoutJson['properties'];
  if (properties is List) {
    for (final prop in properties) {
      if (prop is! Map) continue;
      if (prop['name'] == 'size' && prop['value'] is Map) {
        final parsed = _sizeFromMap(prop['value']);
        if (parsed != null) return parsed;
      }
      if (prop['value'] is Map<String, Object?>) {
        final parsed = parseLayoutSize(prop['value'] as Map<String, Object?>);
        if (parsed != null) return parsed;
      }
    }
  }
  return null;
}

SceneSize? _sizeFromMap(Object? size) {
  if (size is! Map) return null;
  final width = _parseDouble(size['width']);
  final height = _parseDouble(size['height']);
  if (width <= 0 || height <= 0) return null;
  return SceneSize(width, height);
}
