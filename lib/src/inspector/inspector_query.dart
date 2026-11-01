import '../model/widget_scene_node.dart';

WidgetSceneNode? pickDeepestAt(
  List<WidgetSceneNode> nodes,
  double x,
  double y,
) {
  WidgetSceneNode? hit;
  var hitArea = double.infinity;
  for (final node in nodes) {
    final rect = node.rect;
    if (rect == null || rect.width <= 0 || rect.height <= 0) continue;
    if (!rect.contains(x, y)) continue;
    final area = rect.width * rect.height;
    if (area <= hitArea) {
      hit = node;
      hitArea = area;
    }
  }
  return hit;
}

List<WidgetSceneNode> breadcrumbFor(
  List<WidgetSceneNode> nodes,
  WidgetSceneNode selected,
) {
  final byId = {for (final n in nodes) n.diagnosticsId: n};
  final path = <WidgetSceneNode>[];
  var current = selected;
  path.add(current);
  while (current.parentId != null) {
    final parent = byId[current.parentId];
    if (parent == null) break;
    path.insert(0, parent);
    current = parent;
  }
  return path;
}
