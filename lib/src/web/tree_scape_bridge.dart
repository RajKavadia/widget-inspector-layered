import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart';

import '../inspector/widget_selection_controller.dart';
import '../model/widget_scene_node.dart';

typedef TreeScapePickCallback = void Function(String nodeId, double x, double y);

@JS('widgetscapeBridge')
external _WidgetscapeBridge? get _bridge;

@JS()
@staticInterop
class _WidgetscapeBridge {}

extension _WidgetscapeBridgeExt on _WidgetscapeBridge {
  external void loadSnapshot(String json);
  external void setSelection(String? nodeId);
  external void setTheme(String theme);
  external void resetCamera();
  external void setLayerGap(double gap);
  external void setLayerMode(String mode);
  external void updateScreenshot(String pngBase64);
  external void setShowScreenshot(bool visible);
  external void setPickHandler(JSFunction? handler);
  external bool isReady();
}

bool _viewFactoryRegistered = false;
const _viewType = 'widgetscape-tree-scape';
String? _pendingSnapshotJson;
TreeScapePickCallback? _pendingPickHandler;
Timer? _bridgePoll;

void ensureTreeScapeViewRegistered() {
  if (_viewFactoryRegistered) return;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
    final host = HTMLDivElement()
      ..id = 'widgetscape-host-$viewId'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.minHeight = '400px'
      ..style.overflow = 'hidden'
      ..style.position = 'relative';

    final threeScript = HTMLScriptElement()
      ..src = 'tree_scape/vendor/three.min.js';

    threeScript.addEventListener(
      'load',
      ((Event _) {
        final sceneScript = HTMLScriptElement()
          ..src = 'tree_scape/scene.js';
        host.append(sceneScript);
      }).toJS,
    );

    host.append(threeScript);
    return host;
  });
  _viewFactoryRegistered = true;
}

String get treeScapeViewType => _viewType;

void _flushPendingToBridge() {
  final bridge = _bridge;
  if (bridge == null) return;
  final json = _pendingSnapshotJson;
  if (json != null) {
    bridge.loadSnapshot(json);
    _pendingSnapshotJson = null;
  }
  final pick = _pendingPickHandler;
  if (pick != null) {
    bridge.setPickHandler(
      ((JSString id, JSNumber x, JSNumber y) {
        pick(id.toDart, x.toDartDouble, y.toDartDouble);
      }).toJS,
    );
  }
  bridge.setShowScreenshot(_pendingShowScreenshot);
  bridge.setLayerMode(_pendingLayerMode);
}

bool _pendingShowScreenshot = true;
String _pendingLayerMode = 'multi';

void _ensureBridgePoll() {
  _bridgePoll ??= Timer.periodic(const Duration(milliseconds: 150), (_) {
    final bridge = _bridge;
    if (bridge == null) return;
    if (bridge.isReady() || _pendingSnapshotJson != null) {
      _flushPendingToBridge();
    }
    if (_pendingSnapshotJson == null && bridge.isReady()) {
      _bridgePoll?.cancel();
      _bridgePoll = null;
    }
  });
}

void loadSnapshotIntoScene(
  WidgetSceneSnapshot snapshot, {
  bool hideOuterShells = false,
}) {
  _pendingSnapshotJson = encodeSnapshotForJs(
    snapshot,
    hideOuterShells: hideOuterShells,
  );
  final bridge = _bridge;
  if (bridge != null && bridge.isReady()) {
    _flushPendingToBridge();
  } else {
    _ensureBridgePoll();
  }
}

void setSceneSelection(String? diagnosticsId) {
  _bridge?.setSelection(diagnosticsId);
}

void resetSceneCamera() {
  _bridge?.resetCamera();
}

void setSceneLayerGap(double gap) {
  _bridge?.setLayerGap(gap);
}

void setSceneLayerMode(bool multiLayer) {
  _pendingLayerMode = multiLayer ? 'multi' : 'single';
  _bridge?.setLayerMode(_pendingLayerMode);
}

void updateSceneScreenshot(String pngBase64) {
  _bridge?.updateScreenshot(pngBase64);
}

void setSceneShowScreenshot(bool visible) {
  _pendingShowScreenshot = visible;
  _bridge?.setShowScreenshot(visible);
}

void setSceneTheme(Brightness brightness) {
  _bridge?.setTheme(brightness == Brightness.dark ? 'dark' : 'light');
}

void registerScenePickHandler(TreeScapePickCallback onPick) {
  _pendingPickHandler = onPick;
  _flushPendingToBridge();
  _ensureBridgePoll();
}

void clearScenePickHandler() {
  _pendingPickHandler = null;
  _bridge?.setPickHandler(null);
}
