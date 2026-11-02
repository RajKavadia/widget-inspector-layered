# Cursor skills — widget-inspector-layered MCP

Copy any block below into a project or user skill (`.cursor/skills/<name>/SKILL.md`). Each block includes YAML frontmatter Cursor uses for skill discovery.

Skills assume the **widget-inspector-layered** MCP server is configured in the host (see [README.md](README.md)) and a Flutter app is running with a valid VM service URI.

---

## Skill: widgetscape-connect

```markdown
---
name: widgetscape-connect
description: Connect the widget-inspector-layered MCP server to a running Flutter app via VM service URI. Use before other widgetscape_* tools when the app was restarted, the URI changed, or connection errors occur.
---

# Connect to Flutter VM

1. Obtain the VM service URI from `flutter run` (`uri=` query parameter) or `WIDGET_INSPECTOR_LAYERED_VM_URI`.
2. Call MCP tool `widgetscape_connect` with `{ "vmServiceUri": "<ws or http uri>" }`.
3. Confirm success text mentions an isolate id.
4. If the user switched apps or hot restarted, reconnect before snapshotting.

Do not guess ports; use the exact tokenized URI from the running session.
```

---

## Skill: widgetscape-snapshot-tree

```markdown
---
name: widgetscape-snapshot-tree
description: Capture the live Flutter widget tree with layout rects via widget-inspector-layered. Use when debugging layout, overflow, wrong widget, or mapping UI to source before editing Dart code.
---

# Snapshot widget tree

1. Ensure the app is running and MCP is connected (`widgetscape_connect` if needed).
2. Call `widgetscape_snapshot` with:
   - `userCodeOnly: true` unless framework ancestors are required
   - `hideOuterShells: false` only when full-bleed shells matter
   - `includeScreenshot: true` only if saving or visual proof is next
3. Parse JSON: `logicalWidth`, `logicalHeight`, `nodes[]` with `id`, `label`, `rect`, `location`.
4. Map widgets to files using `location.file` and `location.line` when present.
5. After hot restart, snapshot again; do not reuse old `nodeId` values.

Prefer rect geometry over guessing from widget names alone.
```

---

## Skill: widgetscape-pick-widget

```markdown
---
name: widgetscape-pick-widget
description: Hit-test the deepest Flutter widget at logical (x, y) using widget-inspector-layered. Use when the user reports a tap target, overflow pixel, or misaligned control at specific coordinates.
---

# Pick widget at coordinates

1. Run `widgetscape_snapshot` with `userCodeOnly: true` if no recent snapshot exists.
2. Call `widgetscape_pick` with logical `x` and `y` (same space as snapshot rects).
3. If the user named a widget but not coordinates, use the center of that node's `rect` from the snapshot.
4. On hit, call `widgetscape_breadcrumb` with the returned `id` to explain ancestor chain.
5. Open the reported `location` in the codebase before proposing fixes.

If pick misses, verify coords are not device pixels on a high-DPI screen without conversion.
```

---

## Skill: widgetscape-select-highlight

```markdown
---
name: widgetscape-select-highlight
description: Highlight a widget in the running Flutter app by nodeId through widget-inspector-layered. Use when the user is watching the screen and you want to confirm the correct widget before code changes.
---

# Select widget in running app

1. Capture or reuse a recent `widgetscape_snapshot`.
2. Identify `nodeId` from snapshot `id` field (or from `widgetscape_pick`).
3. Call `widgetscape_select` with `{ "nodeId": "<id>" }`.
4. Tell the user to look for inspector selection on device/emulator/browser.
5. Proceed to source edits using `location` from the same node.

Selection does not hot reload; it only mirrors DevTools inspector selection.
```

---

## Skill: widgetscape-layout-debug

```markdown
---
name: widgetscape-layout-debug
description: Diagnose Flutter layout issues (overflow, clipping, off-stage widgets) using widgetscape_snapshot and widgetscape_breadcrumb from widget-inspector-layered.
---

# Debug layout with MCP

1. Snapshot with `userCodeOnly: true`; set `hideOuterShells: false` if ancestors were filtered out.
2. Find the affected widget by label search in `nodes` or `widgetscape_pick` at the problem area.
3. Run `widgetscape_breadcrumb` for that `nodeId`.
4. In the path, inspect types in labels: `Stack`, `Positioned`, `Flex`, `Expanded`, `ClipRect`, scrollables.
5. Compare widget `rect` to `logicalWidth`/`logicalHeight` and sibling rects.
6. Edit the Dart build method at `location`; ask user to hot reload.
7. Re-snapshot to verify rect changes.

Report findings with widget labels, rects, and file:line citations—not screenshots alone.
```

---

## Skill: widgetscape-screenshot-artifact

```markdown
---
name: widgetscape-screenshot-artifact
description: Save a Flutter inspector screenshot PNG via widget-inspector-layered for walkthroughs, PR proof, or visual regression notes.
---

# Save inspector screenshot

1. Connect MCP if needed.
2. Call `widgetscape_save_screenshot` with optional `path` (absolute path in agent environment).
3. If the tool reports warnings, note `screenshotWarning` from a prior snapshot.
4. Attach or reference the PNG in the user-facing summary.

Pair with `widgetscape_snapshot` JSON when explaining which widgets correspond to visible regions.
```

---

## Installing in Cursor

1. Create a folder such as `.cursor/skills/widgetscape-snapshot-tree/` in your Flutter app or monorepo.
2. Paste one skill block into `SKILL.md` (frontmatter + body only—omit the outer fenced code label).
3. Ensure MCP config points at `widget_inspector_layered` with a valid `--vm-uri` or environment variable.
4. Start the Flutter app before the agent invokes tools.

For full agent behavior and error tables, see [agents.md](agents.md).
