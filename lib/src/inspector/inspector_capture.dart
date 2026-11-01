import 'dart:math' as math;

import '../model/widget_scene_node.dart';
import 'inspector_query.dart';
import 'inspector_tree_parser.dart';

const inspectorPrefix = 'ext.flutter.inspector';

typedef InspectorExtensionCall = Future<Object?> Function(
  String method,
  Map<String, String> args,
);

class InspectorCapture {
  InspectorCapture({
    required InspectorExtensionCall call,
    InspectorTreeParser? parser,
  })  : _call = call,
        _parser = parser ?? InspectorTreeParser();

  final InspectorExtensionCall _call;
  final InspectorTreeParser _parser;
  int _groupCounter = 0;
  String? activeObjectGroup;
  WidgetSceneSnapshot? lastSnapshot;

  Future<WidgetSceneSnapshot> capture({
    required bool userCodeOnly,
    bool includeScreenshot = true,
  }) async {
    if (activeObjectGroup != null) {
      await disposeGroup(activeObjectGroup!);
    }
    final objectGroup = 'widgetscape_${_groupCounter++}';
    activeObjectGroup = objectGroup;

    final result = await _call(
      '$inspectorPrefix.getRootWidgetSummaryTree',
      {'objectGroup': objectGroup},
    );
    if (result is! Map) {
      throw StateError('Unexpected inspector tree response.');
    }
    final tree = Map<String, Object?>.from(result);

    final flatNodes = _parser.parseRoot(tree, userCodeOnly: userCodeOnly);
    final layoutCandidates = flatNodes
        .where((n) => n.valueId != null)
        .take(160)
        .toList();

    final layoutByValueId = <String, Map<String, Object?>>{};
    const concurrency = 10;
    for (var i = 0; i < layoutCandidates.length; i += concurrency) {
      final chunk = layoutCandidates.skip(i).take(concurrency);
      await Future.wait(chunk.map((node) async {
        final valueId = node.valueId!;
        try {
          final layoutResult = await _call(
            '$inspectorPrefix.getLayoutExplorerNode',
            {
              'id': valueId,
              'groupName': objectGroup,
              'objectGroup': objectGroup,
              'subtreeDepth': '0',
            },
          );
          if (layoutResult is Map) {
            layoutByValueId[valueId] = Map<String, Object?>.from(layoutResult);
          }
        } catch (_) {
          // Keep the node without layout.
        }
      }));
    }

    _parser.applyLayout(flatNodes, layoutByValueId);
    final root = _parser.rebuildTree(flatNodes);
    final viewNode = flatNodes.firstWhere(
      (n) =>
          n.description.contains('RenderView') ||
          (n.size != null && n.parentId == null),
      orElse: () => root,
    );
    final logicalWidth = viewNode.size?.width ?? viewNode.rect?.width ?? 390;
    final logicalHeight = viewNode.size?.height ?? viewNode.rect?.height ?? 844;

    String? pngBase64;
    String? screenshotWarning;
    final screenshotId = viewNode.valueId;
    if (includeScreenshot && screenshotId != null) {
      try {
        final shot = await _call(
          '$inspectorPrefix.screenshot',
          {
            'id': screenshotId,
            'width': logicalWidth.toString(),
            'height': logicalHeight.toString(),
            'maxPixelRatio': '1.0',
          },
        );
        if (shot is String && shot.isNotEmpty) {
          pngBase64 = shot;
        } else {
          screenshotWarning = 'Screenshot unavailable for this target.';
        }
      } catch (e) {
        screenshotWarning = 'Screenshot failed: $e';
      }
    } else if (screenshotId == null) {
      screenshotWarning = 'No RenderView id found for screenshot.';
    }

    return lastSnapshot = WidgetSceneSnapshot(
      nodes: flatNodes,
      root: root,
      logicalWidth: math.max(logicalWidth, 1),
      logicalHeight: math.max(logicalHeight, 1),
      pngBase64: pngBase64,
      screenshotWarning: screenshotWarning,
      objectGroup: objectGroup,
      screenshotId: screenshotId,
    );
  }

  Future<void> setSelection(String? valueId, {String? objectGroup}) async {
    if (valueId == null) return;
    await _call(
      '$inspectorPrefix.setSelectionById',
      {
        'arg': valueId,
        if (objectGroup != null) 'objectGroup': objectGroup,
      },
    );
  }

  Future<void> disposeGroup(String objectGroup) async {
    try {
      await _call(
        '$inspectorPrefix.disposeGroup',
        {'objectGroup': objectGroup},
      );
    } catch (_) {}
  }

  WidgetSceneNode? pickAt(double x, double y) {
    final snapshot = lastSnapshot;
    if (snapshot == null) return null;
    return pickDeepestAt(snapshot.nodes, x, y);
  }

  WidgetSceneNode? nodeById(String id) {
    final snapshot = lastSnapshot;
    if (snapshot == null) return null;
    for (final node in snapshot.nodes) {
      if (node.diagnosticsId == id || node.valueId == id) return node;
    }
    return null;
  }
}
