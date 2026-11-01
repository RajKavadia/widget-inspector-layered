import 'package:widget_inspector_layered/src/mcp/widgetscape_mcp_server.dart';

Future<void> main(List<String> args) async {
  String? uri;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--vm-uri' && i + 1 < args.length) {
      uri = args[i + 1];
    }
  }
  final server = WidgetscapeMcpServer(defaultVmUri: uri);
  await server.serve();
}
