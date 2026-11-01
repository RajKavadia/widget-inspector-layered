import 'package:flutter_test/flutter_test.dart';
import 'package:widget_inspector_layered/src/inspector/inspector_query.dart';
import 'package:widget_inspector_layered/src/inspector/inspector_tree_parser.dart';
import 'package:widget_inspector_layered/src/model/widget_scene_node.dart';

void main() {
  test('parses inspector summary tree and layout rects', () {
    const tree = {
      'description': 'RenderView',
      'valueId': 'rv',
      'children': [
        {
          'description': 'Padding',
          'valueId': 'pad',
          'createdByLocalProject': true,
          'creationLocation': {
            'file': 'lib/main.dart',
            'line': 10,
            'column': 12,
          },
          'children': [],
        },
      ],
    };

    final parser = InspectorTreeParser();
    final nodes = parser.parseRoot(tree, userCodeOnly: false);
    expect(nodes.length, 2);

    parser.applyLayout(nodes, {
      'rv': {
        'size': {'width': '400', 'height': '800'},
      },
      'pad': {
        'size': {'width': '200', 'height': '100'},
        'parentData': {'offsetX': '16', 'offsetY': '24'},
      },
    });

    final root = nodes.firstWhere((n) => n.valueId == 'rv');
    final padding = nodes.firstWhere((n) => n.valueId == 'pad');
    expect(root.rect?.width, 400);
    expect(padding.rect?.left, 16);
    expect(padding.rect?.top, 24);
    expect(padding.creationLocation?.line, 10);

    final snapshot = WidgetSceneSnapshot(
      nodes: nodes,
      root: root,
      logicalWidth: 400,
      logicalHeight: 800,
    );
    final hidden = snapshot.visibleNodes(hideOuterShells: true);
    expect(hidden.any((n) => n.valueId == 'rv'), isFalse);
    expect(hidden.any((n) => n.valueId == 'pad'), isTrue);
  });

  test('picks the deepest widget at a point', () {
    final nodes = [
      WidgetSceneNode(
        diagnosticsId: 'a',
        description: 'Scaffold',
        rect: const SceneRect(0, 0, 400, 800),
      ),
      WidgetSceneNode(
        diagnosticsId: 'b',
        description: 'Button',
        rect: const SceneRect(16, 24, 200, 100),
      ),
    ];
    final hit = pickDeepestAt(nodes, 20, 30);
    expect(hit?.diagnosticsId, 'b');
  });
}
