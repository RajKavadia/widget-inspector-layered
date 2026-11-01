import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../inspector/inspector_capture.dart';
import '../inspector/inspector_query.dart';

class WidgetscapeMcpServer {
  WidgetscapeMcpServer({
    String? defaultVmUri,
    Stdin? input,
    Stdout? output,
  })  : _defaultVmUri = defaultVmUri ??
            Platform.environment['WIDGET_INSPECTOR_LAYERED_VM_URI'] ??
            Platform.environment['WIDGETSCAPE_VM_URI'] ??
            Platform.environment['VM_SERVICE_URI'],
        _stdin = input ?? stdin,
        _stdout = output ?? stdout;

  final String? _defaultVmUri;
  final Stdin _stdin;
  final Stdout _stdout;

  VmService? _vm;
  String? _isolateId;
  InspectorCapture? _capture;

  Future<void> serve() async {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in _stdin) {
      buffer.add(chunk);
      _drain(buffer);
    }
  }

  void _drain(BytesBuilder buffer) {
    while (true) {
      final data = buffer.toBytes();
      final headerEnd = _indexOfHeaderEnd(data);
      if (headerEnd < 0) {
        buffer.clear();
        buffer.add(data);
        return;
      }
      final header = utf8.decode(data.sublist(0, headerEnd));
      final match = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false)
          .firstMatch(header);
      if (match == null) {
        buffer.clear();
        buffer.add(data.sublist(headerEnd + 4));
        continue;
      }
      final length = int.parse(match.group(1)!);
      final bodyStart = headerEnd + 4;
      if (data.length < bodyStart + length) {
        buffer.clear();
        buffer.add(data);
        return;
      }
      final body = utf8.decode(data.sublist(bodyStart, bodyStart + length));
      buffer.clear();
      buffer.add(data.sublist(bodyStart + length));
      unawaited(_handleMessage(body));
    }
  }

  int _indexOfHeaderEnd(Uint8List data) {
    for (var i = 0; i < data.length - 3; i++) {
      if (data[i] == 13 &&
          data[i + 1] == 10 &&
          data[i + 2] == 13 &&
          data[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _handleMessage(String body) async {
    final message = jsonDecode(body);
    if (message is! Map) return;
    if (message.containsKey('result') || message.containsKey('error')) return;
    final id = message['id'];
    final method = message['method'] as String? ?? '';
    final params = message['params'];
    try {
      final result = await _dispatch(method, params is Map ? params : const {});
      if (id != null) {
        _write({'jsonrpc': '2.0', 'id': id, 'result': result});
      }
    } catch (e) {
      if (id != null) {
        _write({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32000, 'message': '$e'},
        });
      }
    }
  }

  Future<Object?> _dispatch(String method, Map<dynamic, dynamic> params) async {
    switch (method) {
      case 'initialize':
        return {
          'protocolVersion': '2024-11-05',
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': 'widget-inspector-layered', 'version': '1.0.0'},
        };
      case 'notifications/initialized':
      case 'initialized':
        return const {};
      case 'ping':
        return const {};
      case 'tools/list':
        return {'tools': _tools};
      case 'tools/call':
        return _callTool(
          params['name'] as String? ?? '',
          params['arguments'] is Map
              ? Map<String, Object?>.from(params['arguments'] as Map)
              : const {},
        );
      default:
        throw StateError('Unsupported MCP method: $method');
    }
  }

  Future<Map<String, Object?>> _callTool(
    String name,
    Map<String, Object?> args,
  ) async {
    switch (name) {
      case 'widgetscape_connect':
        await connect(args['vmServiceUri'] as String? ?? _defaultVmUri);
        return _text('Connected to isolate $_isolateId');
      case 'widgetscape_snapshot':
        await _ensureConnected(args['vmServiceUri'] as String?);
        final snapshot = await _capture!.capture(
          userCodeOnly: args['userCodeOnly'] == true,
          includeScreenshot: args['includeScreenshot'] == true,
        );
        final hideOuter = args['hideOuterShells'] != false;
        return _json({
          'logicalWidth': snapshot.logicalWidth,
          'logicalHeight': snapshot.logicalHeight,
          'screenshotWarning': snapshot.screenshotWarning,
          'hasScreenshot': snapshot.pngBase64 != null,
          'nodes': snapshot
              .visibleNodes(hideOuterShells: hideOuter)
              .map((n) => n.toSceneJson())
              .toList(),
        });
      case 'widgetscape_pick':
        await _ensureSnapshot(args);
        final x = _asDouble(args['x']);
        final y = _asDouble(args['y']);
        final hit = _capture!.pickAt(x, y);
        if (hit == null) return _text('No widget at ($x, $y).');
        return _json(hit.toSceneJson());
      case 'widgetscape_select':
        await _ensureSnapshot(args);
        final id = args['nodeId'] as String? ?? '';
        final node = _capture!.nodeById(id);
        if (node == null) {
          throw StateError('Unknown nodeId: $id. Capture a snapshot first.');
        }
        await _capture!.setSelection(
          node.valueId,
          objectGroup: _capture!.activeObjectGroup,
        );
        return _json({
          ...node.toSceneJson(),
          'selected': true,
        });
      case 'widgetscape_save_screenshot':
        await _ensureSnapshot({...args, 'includeScreenshot': true});
        var snapshot = _capture!.lastSnapshot;
        if (snapshot?.pngBase64 == null) {
          snapshot = await _capture!.capture(
            userCodeOnly: args['userCodeOnly'] == true,
            includeScreenshot: true,
          );
        }
        final path = args['path'] as String? ??
            '${Directory.systemTemp.path}/widgetscape.png';
        final bytes = base64Decode(snapshot!.pngBase64!);
        await File(path).writeAsBytes(bytes);
        return _text('Wrote screenshot to $path');
      case 'widgetscape_breadcrumb':
        await _ensureSnapshot(args);
        final id = args['nodeId'] as String? ?? '';
        final node = _capture!.nodeById(id);
        if (node == null) throw StateError('Unknown nodeId: $id');
        return _json({
          'path': breadcrumbFor(_capture!.lastSnapshot!.nodes, node)
              .map((n) => n.toSceneJson())
              .toList(),
        });
      default:
        throw StateError('Unknown tool: $name');
    }
  }

  Future<void> connect(String? uri) async {
    final resolved = uri ?? _defaultVmUri;
    if (resolved == null || resolved.isEmpty) {
      throw StateError(
        'Pass vmServiceUri or set WIDGET_INSPECTOR_LAYERED_VM_URI / VM_SERVICE_URI.',
      );
    }
    await _vm?.dispose();
    _vm = await vmServiceConnectUri(_normalizeWs(resolved));
    final vm = await _vm!.getVM();
    final isolates = vm.isolates ?? const <IsolateRef>[];
    if (isolates.isEmpty) {
      throw StateError('No isolates on the VM service.');
    }
    final main = isolates.firstWhere(
      (i) => (i.name ?? '').toLowerCase().contains('main'),
      orElse: () => isolates.first,
    );
    _isolateId = main.id;
    _capture = InspectorCapture(call: (method, args) async {
      final response = await _vm!.callServiceExtension(
        method,
        isolateId: _isolateId,
        args: args,
      );
      return response.json?['result'];
    });
  }

  Future<void> _ensureConnected(String? uri) async {
    if (_capture == null) await connect(uri);
  }

  Future<void> _ensureSnapshot(Map<String, Object?> args) async {
    await _ensureConnected(args['vmServiceUri'] as String?);
    if (_capture!.lastSnapshot == null) {
      await _capture!.capture(
        userCodeOnly: args['userCodeOnly'] == true,
        includeScreenshot: args['includeScreenshot'] == true,
      );
    }
  }

  String _normalizeWs(String uri) {
    if (uri.startsWith('http://')) {
      return 'ws://${uri.substring('http://'.length)}';
    }
    if (uri.startsWith('https://')) {
      return 'wss://${uri.substring('https://'.length)}';
    }
    return uri;
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, Object?> _text(String text) {
    return {
      'content': [
        {'type': 'text', 'text': text},
      ],
    };
  }

  Map<String, Object?> _json(Object value) {
    return {
      'content': [
        {'type': 'text', 'text': const JsonEncoder.withIndent('  ').convert(value)},
      ],
    };
  }

  void _write(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode(message));
    _stdout.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
    _stdout.add(body);
  }

  static const _tools = [
    {
      'name': 'widgetscape_connect',
      'description':
          'Connect widget-inspector-layered to a running Flutter VM service (ws:// or http://).',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'vmServiceUri': {'type': 'string'},
        },
      },
    },
    {
      'name': 'widgetscape_snapshot',
      'description':
          'Capture the live widget tree and layout rects mapped to the screenshot space.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'vmServiceUri': {'type': 'string'},
          'userCodeOnly': {'type': 'boolean'},
          'hideOuterShells': {'type': 'boolean'},
          'includeScreenshot': {'type': 'boolean'},
        },
      },
    },
    {
      'name': 'widgetscape_pick',
      'description':
          'Pick the deepest widget at logical screenshot coordinates (x, y).',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'x': {'type': 'number'},
          'y': {'type': 'number'},
        },
        'required': ['x', 'y'],
      },
    },
    {
      'name': 'widgetscape_select',
      'description':
          'Select a widget in the running app by nodeId from the last snapshot.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'nodeId': {'type': 'string'},
        },
        'required': ['nodeId'],
      },
    },
    {
      'name': 'widgetscape_breadcrumb',
      'description': 'Return the parent path for a widget nodeId.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'nodeId': {'type': 'string'},
        },
        'required': ['nodeId'],
      },
    },
    {
      'name': 'widgetscape_save_screenshot',
      'description': 'Write the current Flutter inspector screenshot to a PNG file.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
      },
    },
  ];
}
