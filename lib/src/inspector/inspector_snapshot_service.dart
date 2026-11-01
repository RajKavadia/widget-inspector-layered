import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:logging/logging.dart';

import '../model/widget_scene_node.dart';
import 'inspector_capture.dart';

final _log = Logger('inspector_snapshot');

class InspectorSnapshotService {
  InspectorSnapshotService()
      : _capture = InspectorCapture(call: _devtoolsCall);

  final InspectorCapture _capture;

  static Future<Object?> _devtoolsCall(
    String method,
    Map<String, String> args,
  ) async {
    await serviceManager.onServiceAvailable;
    final response = await serviceManager.callServiceExtensionOnMainIsolate(
      method,
      args: args,
    );
    return response.json?['result'];
  }

  Future<WidgetSceneSnapshot> capture({
    required bool userCodeOnly,
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Fetching widget tree…');
    try {
      return await _capture.capture(userCodeOnly: userCodeOnly);
    } catch (e, s) {
      _log.severe('Capture failed', e, s);
      rethrow;
    }
  }

  Future<WidgetSceneSnapshot> refreshScreenshot(WidgetSceneSnapshot snapshot) async {
    final screenshotId = snapshot.screenshotId;
    if (screenshotId == null) return snapshot;
    try {
      final shot = await _devtoolsCall(
        '$inspectorPrefix.screenshot',
        {
          'id': screenshotId,
          'width': snapshot.logicalWidth.toString(),
          'height': snapshot.logicalHeight.toString(),
          'maxPixelRatio': '1.0',
        },
      );
      if (shot is String && shot.isNotEmpty) {
        return snapshot.copyWith(pngBase64: shot);
      }
    } catch (e, s) {
      _log.fine('Live screenshot refresh failed', e, s);
    }
    return snapshot;
  }

  Future<void> setSelection(String? valueId, {String? objectGroup}) {
    return _capture.setSelection(valueId, objectGroup: objectGroup);
  }
}
