# Agent guide — widget-inspector-layered MCP

This document is for **coding agents** (Cursor, Claude Code, custom MCP hosts) that debug or modify Flutter UIs through the **widget-inspector-layered** stdio MCP server.

Human-oriented setup lives in [README.md](README.md). Reusable Cursor skill text is in [skills.md](skills.md).

## What this server gives you

Unlike static screenshots or grep-only analysis, this MCP server reads the **live** Flutter widget tree via the VM service:

- Layout **rects** in logical screenshot coordinates
- Widget **labels** (diagnostics descriptions)
- **Source locations** when the compiler recorded them (`file`, `line`, `column`)
- **Pick** and **select** in the running app (same as DevTools inspector selection)

The DevTools 3D view is for humans; agents usually consume JSON from `widgetscape_snapshot` and related tools.

## Preconditions

1. **Flutter app is running** in debug or profile mode (`flutter run`, IDE run, integration test with VM service, etc.).
2. You have a valid **VM service URI** (WebSocket or HTTP form).
3. The MCP process can reach `127.0.0.1` (or the host where the app runs). Remote devices need port forwarding or a reachable VM URI.

If connection fails, ask the user to paste the `uri=` line from `flutter run` or set `WIDGET_INSPECTOR_LAYERED_VM_URI`.

## Connection model

- One MCP server process holds **one** VM connection and reuses the **last snapshot** until you capture again.
- Call `widgetscape_connect` explicitly when switching apps or after hot restart (VM token may change).
- After hot **restart**, reconnect and take a fresh snapshot; stale `nodeId` values may not exist.

## Recommended workflow

```text
connect (optional if env/default URI is set)
  → snapshot (userCodeOnly: true for app widgets only)
  → pick / breadcrumb / select as needed
  → save_screenshot when a PNG artifact helps the user
```

### 1. Connect

```json
{ "vmServiceUri": "ws://127.0.0.1:PORT/TOKEN=/ws" }
```

Tool: `widgetscape_connect`

### 2. Snapshot

Tool: `widgetscape_snapshot`

| Argument | Default | When to use |
| --- | --- | --- |
| `userCodeOnly` | false | `true` to drop framework noise and focus on project widgets |
| `hideOuterShells` | true | `false` if you need full tree including full-screen shells |
| `includeScreenshot` | false | `true` only when you will save or visually verify; heavier |
| `vmServiceUri` | env / prior connect | Pass when the app URI changed |

Response fields (JSON text content):

- `logicalWidth`, `logicalHeight` — coordinate space for pick
- `nodes[]` — flat list with `id`, `label`, `depth`, `parentId`, `rect`, optional `location`
- `hasScreenshot`, `screenshotWarning` — PNG may be unavailable on some embedders

Use `location.label` (e.g. `main.dart:42`) to open the right file in the editor.

### 3. Pick by coordinates

Tool: `widgetscape_pick` — requires prior snapshot (auto-captures if missing).

```json
{ "x": 120.5, "y": 400.0 }
```

Coordinates are **logical** pixels in the same space as snapshot rects (top-left origin). Prefer center of a `rect` from snapshot when the user names a widget but not a point.

Returns one node object or a text message if nothing hit.

### 4. Select in the running app

Tool: `widgetscape_select`

```json
{ "nodeId": "<id from snapshot>" }
```

Highlights the widget in the live app (useful when the user watches the screen). Does not edit source.

### 5. Breadcrumb / ancestry

Tool: `widgetscape_breadcrumb`

```json
{ "nodeId": "<id>" }
```

Returns `path`: ordered list from root toward the node. Use this to explain “why is this under a `Stack`/`Positioned`?” without guessing.

### 6. Save screenshot

Tool: `widgetscape_save_screenshot`

```json
{ "path": "/tmp/widgetscape.png" }
```

Ensures a capture with screenshot data, then writes PNG bytes. Default path is system temp `widgetscape.png`.

## Task patterns

### “What widget is at this tap / overflow?”

1. `widgetscape_snapshot` with `userCodeOnly: true`
2. `widgetscape_pick` at the reported coordinates, or search `nodes` for smallest area rect containing the point
3. `widgetscape_breadcrumb` on the hit `id`
4. Read `location` and inspect that build method in the repo

### “Why is this widget off-screen / clipped?”

1. Snapshot with `hideOuterShells: false` if ancestors were hidden
2. Breadcrumb from the widget’s `nodeId`
3. Compare ancestor labels (`ClipRect`, `OverflowBox`, `SingleChildScrollView`, `Stack`, `Positioned`) and child `rect` vs `logicalWidth`/`logicalHeight`

### “Fix layout after code change”

1. Ask the user to hot reload or save if needed
2. New snapshot (selection state may reset)
3. Compare rects before/after; do not reuse old `nodeId` after hot restart

### “Verify UI visually”

1. `widgetscape_save_screenshot` to a known path
2. Use the host’s image/view tools if available; otherwise describe rects from snapshot

## Limits and pitfalls

- **Layout cap:** layout explorer calls are batched (up to ~160 nodes with value ids). Deep trees may omit layout on some nodes; those nodes may lack `rect`.
- **Screenshot:** Some platforms warn or omit PNG; respect `screenshotWarning`.
- **Outer shells:** Default snapshot hides full-bleed shells (`MaterialApp`, `Scaffold`, etc.) when a screenshot is present—set `hideOuterShells: false` if you need them.
- **No code execution:** Tools inspect and select; they do not hot reload or edit files.
- **Security:** VM service access equals debugger access; use only on local dev apps the user owns.

## Error handling

| Symptom | Likely cause | Agent action |
| --- | --- | --- |
| `Pass vmServiceUri or set ...` | No URI | Get URI from user or env |
| `No isolates on the VM service` | App not running / wrong URI | Re-run app, reconnect |
| `Unknown nodeId` | Stale snapshot | Call `widgetscape_snapshot` again |
| `No widget at (x, y)` | Wrong coords or empty rect | Re-snapshot; try center of known rect |
| Connection refused | Port/token mismatch | Copy fresh URI after restart |

## MCP protocol

- Protocol version: `2024-11-05`
- Server name: `widget-inspector-layered`
- Methods: `initialize`, `tools/list`, `tools/call` (notifications ignored)

Implementation: [lib/src/mcp/widgetscape_mcp_server.dart](lib/src/mcp/widgetscape_mcp_server.dart)

## When not to use this MCP

- **Widget tests** in headless CI without a VM service → use `WidgetTester` and golden tests instead.
- **Production builds** without VM service → not supported.
- **Non-Flutter** projects → out of scope.

For Flutter code changes, prefer reading/editing Dart source after you identify widgets via snapshot; use MCP to **target** the right widget, not to replace reading the codebase.
