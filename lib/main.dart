import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'src/ui/tree_scape_panel.dart';

void main() {
  runApp(const WidgetscapeDevToolsExtension());
}

class WidgetscapeDevToolsExtension extends StatelessWidget {
  const WidgetscapeDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(
      child: WidgetscapeHomePage(),
    );
  }
}

class WidgetscapeHomePage extends StatelessWidget {
  const WidgetscapeHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('widget-inspector-layered'),
      ),
      body: const TreeScapePanel(),
    );
  }
}
