# widget-inspector-layered

Flutter inspector that turns a live widget tree into a **3D map aligned to the real screen**.

The screenshot sits in front. Behind it, each widget is a layer cut from the same pixels and positioned at its layout rect. Orbit the scene to see nesting and overlap. Click a layer to select that widget in the running app and jump toward its source.

**Repository:** [github.com/RajKavadia/widget-inspector-layered](https://github.com/RajKavadia/widget-inspector-layered)

| Surface | What you get |
| --- | --- |
| **DevTools extension** | Orbit, pan, zoom, live follow, hide outer shells, single vs multi-layer view |
| **MCP server (stdio)** | Agents connect to a running app, snapshot the tree, pick by coordinates, select widgets, save PNGs |

For AI agents, see **[agents.md](agents.md)** and **[skills.md](skills.md)**.

## Screenshots

![Example Flutter app](screenshots/01-example-app.png)

![3D widget map in DevTools](screenshots/02-devtools-widgetscape.png)

![Multi-layer inspector](screenshots/03-layered-orbit.png)

![Exploded widget layers](screenshots/04-layers-only.png)

![Single-layer mode](screenshots/05-single-layer.png)

## Requirements

- Flutter SDK (Dart ^3.13.2)
- A **debug** or **profile** Flutter app with the VM service enabled (normal `flutter run`)
- For DevTools: Flutter DevTools with extension support

## Use in your app

### 1. Add the dependency

From pub.dev:

```yaml
dev_dependencies:
  widget_inspector_layered: ^1.0.0
```

Or path dependency while developing this package:

```yaml
dev_dependencies:
  widget_inspector_layered:
    path: ../widget-inspector-layered
```

### 2. Enable the DevTools extension

Create or edit `devtools_options.yaml` in your app root:

```yaml
extensions:
  - widget_inspector_layered: true
```

### 3. Run the app and open DevTools

```bash
flutter run -d chrome   # or any device
```

Open DevTools from the IDE or `dart devtools`, connect to the running app, then open the **widget-inspector-layered** tab.

After rebuilding the extension bundle in this repo, hard-refresh DevTools and use **Refresh snapshot** in the panel.

### Example app

```bash
cd example
flutter pub get
flutter run -d chrome
```

## MCP server

The MCP server speaks JSON-RPC over **stdio** and exposes tools prefixed with `widgetscape_`. It uses the Flutter **VM service** and inspector extensions—the same data DevTools uses—so the app must be running and reachable.

### Get the VM service URI

When you `flutter run`, the console prints a VM service URL, for example:

```text
The Flutter DevTools debugger and profiler on Chrome is available at:
http://127.0.0.1:9100?uri=http://127.0.0.1:54321/AbCdEf=/ 
```

Use the **`uri=`** value (HTTP or WebSocket). The server accepts `http://`, `https://`, `ws://`, or `wss://` and normalizes to WebSocket internally.

You can also pass `--observatory-port` / enable the VM service on a known port in your workflow.

### Run standalone

From this repository:

```bash
dart pub get
dart run bin/widgetscape_mcp.dart --vm-uri 'ws://127.0.0.1:PORT/TOKEN=/ws'
```

Or use the published executable name:

```bash
dart run widget_inspector_layered --vm-uri 'ws://127.0.0.1:PORT/TOKEN=/ws'
```

### Environment variables

If you omit `--vm-uri` and tool arguments omit `vmServiceUri`, the server reads (first match wins):

| Variable | Purpose |
| --- | --- |
| `WIDGET_INSPECTOR_LAYERED_VM_URI` | Preferred default VM URI |
| `WIDGETSCAPE_VM_URI` | Legacy alias |
| `VM_SERVICE_URI` | Generic fallback |

### Cursor / Claude Desktop config

Copy [mcp/cursor.example.json](mcp/cursor.example.json) into your MCP settings. Set `cwd` to **this repo root** (or your app root if the package is a dependency) and replace the VM URI with your running app.

```json
{
  "mcpServers": {
    "widget-inspector-layered": {
      "command": "dart",
      "args": [
        "run",
        "bin/widgetscape_mcp.dart",
        "--vm-uri",
        "ws://127.0.0.1:REPLACE_PORT/REPLACE_TOKEN=/ws"
      ],
      "cwd": "/absolute/path/to/widget-inspector-layered"
    }
  }
}
```

When the MCP host runs from an app that depends on the package:

```json
"args": ["run", "widget_inspector_layered", "--vm-uri", "ws://127.0.0.1:..."],
"cwd": "/absolute/path/to/your/flutter/app"
```

### MCP tools

| Tool | Description |
| --- | --- |
| `widgetscape_connect` | Attach to a VM service URI |
| `widgetscape_snapshot` | Widget tree + layout rects in screenshot space |
| `widgetscape_pick` | Deepest widget at logical `(x, y)` |
| `widgetscape_select` | Highlight a widget in the live app by `nodeId` |
| `widgetscape_breadcrumb` | Ancestor path for a `nodeId` |
| `widgetscape_save_screenshot` | Write inspector PNG to disk |

Snapshot nodes include `id`, `label`, `depth`, `rect`, optional `location` (file/line), and `createdByLocalProject`. See [agents.md](agents.md) for recommended agent workflows.

## Rebuild the DevTools extension bundle

The checked-in web build lives under `extension/devtools/build/`.

```bash
flutter pub get
flutter build web --release
cp -r build/web/* extension/devtools/build/
```

If you change the Three.js scene, also copy:

```bash
cp web/tree_scape/scene.js extension/devtools/build/tree_scape/
```

## Development

```bash
flutter pub get
dart analyze
flutter test
```

## License

See the repository for license information.

## Related docs

- [agents.md](agents.md) — instructions for coding agents using the MCP server
- [skills.md](skills.md) — Cursor skill snippets you can install for common tasks
- [CHANGELOG.md](CHANGELOG.md)
