import 'dart:convert';

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_extensions/devtools_extensions.dart';

import '../model/widget_scene_node.dart';
import 'inspector_query.dart' as query;

class WidgetSelectionController {
  static const navigateSource = 'widgetscape.inspector';

  Future<void> selectAndNavigate({
    required WidgetSceneNode node,
    String? objectGroup,
  }) async {
    await serviceManager.onServiceAvailable;
    final vmService = serviceManager.service;
    if (vmService == null) {
      throw StateError('VM service not connected.');
    }

    if (node.valueId != null) {
      await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.flutter.inspector.setSelectionById',
        args: {
          'arg': node.valueId!,
          if (objectGroup != null) 'objectGroup': objectGroup,
        },
      );
    }

    final location = node.creationLocation;
    if (location == null || location.file.isEmpty) {
      throw StateError(
        'No creation location for ${node.description}. '
        'Try a widget defined in your project.',
      );
    }

    final fileUri = _toFileUri(location.file);
    await vmService.navigateToCode(
      fileUriString: fileUri,
      line: location.line,
      column: location.column,
      source: navigateSource,
    );
  }

  String _toFileUri(String file) {
    if (file.startsWith('file://')) return file;
    final normalized = file.replaceAll('\\', '/');
    if (normalized.contains(':/')) {
      return Uri.file(normalized).toString();
    }
    return Uri.file(normalized).toString();
  }

  WidgetSceneNode? pickDeepestAt(
    List<WidgetSceneNode> nodes,
    double x,
    double y,
  ) {
    return query.pickDeepestAt(nodes, x, y);
  }

  List<WidgetSceneNode> breadcrumbFor(
    List<WidgetSceneNode> nodes,
    WidgetSceneNode selected,
  ) {
    return query.breadcrumbFor(nodes, selected);
  }
}

String encodeSnapshotForJs(
  WidgetSceneSnapshot snapshot, {
  bool hideOuterShells = false,
}) {
  return jsonEncode(snapshot.toSceneJson(hideOuterShells: hideOuterShells));
}
