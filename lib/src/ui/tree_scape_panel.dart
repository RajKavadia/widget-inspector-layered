import 'dart:async';

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:vm_service/vm_service.dart' as vm;

import '../inspector/inspector_snapshot_service.dart';
import '../inspector/widget_selection_controller.dart';
import '../model/widget_scene_node.dart';
import '../web/tree_scape_bridge.dart';

class TreeScapePanel extends StatefulWidget {
  const TreeScapePanel({super.key});

  @override
  State<TreeScapePanel> createState() => _TreeScapePanelState();
}

class _TreeScapePanelState extends State<TreeScapePanel> {
  final _snapshotService = InspectorSnapshotService();
  final _selectionController = WidgetSelectionController();

  WidgetSceneSnapshot? _snapshot;
  WidgetSceneNode? _selected;
  var _userCodeOnly = false;
  var _hideOuterShells = true;
  var _followLive = true;
  var _showScreenshot = true;
  var _multiLayer = true;
  var _layerGap = 72.0;
  var _loading = false;
  var _liveBusy = false;
  StreamSubscription<vm.Event>? _extensionEvents;
  Timer? _liveDebounce;
  DateTime _lastTreeSync = DateTime.fromMillisecondsSinceEpoch(0);
  String? _status;
  String? _error;
  String? _screenshotWarning;

  @override
  void initState() {
    super.initState();
    ensureTreeScapeViewRegistered();
    serviceManager.connectedState.addListener(_onConnectionChanged);
    unawaited(_maybeAutoRefresh());
    registerScenePickHandler(_onScenePick);
    unawaited(_listenForAppFrames());
  }

  @override
  void dispose() {
    serviceManager.connectedState.removeListener(_onConnectionChanged);
    clearScenePickHandler();
    unawaited(_extensionEvents?.cancel());
    _liveDebounce?.cancel();
    super.dispose();
  }

  void _onConnectionChanged() {
    if (serviceManager.connectedState.value.connected) {
      unawaited(_listenForAppFrames());
      unawaited(_maybeAutoRefresh());
    }
  }

  Future<void> _listenForAppFrames() async {
    await _extensionEvents?.cancel();
    _extensionEvents = null;
    if (!serviceManager.connectedState.value.connected) return;
    final vm = serviceManager.service;
    if (vm == null) return;
    try {
      await vm.streamListen('Extension');
    } catch (_) {
      // Already listening.
    }
    _extensionEvents = vm.onExtensionEvent.listen((event) {
      final kind = event.extensionKind ?? event.kind;
      if (kind != FlutterEvent.frame &&
          kind != FlutterEvent.firstFrame &&
          kind != FlutterEvent.navigation) {
        return;
      }
      _scheduleLiveFollow();
    });
  }

  void _scheduleLiveFollow() {
    if (!_followLive || _loading || _liveBusy) return;
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_followCurrentState());
    });
  }

  Future<void> _followCurrentState() async {
    if (!_followLive || !mounted || _liveBusy) return;
    final current = _snapshot;
    if (current == null) return;
    _liveBusy = true;
    try {
      final now = DateTime.now();
      final shouldResyncTree =
          now.difference(_lastTreeSync) > const Duration(seconds: 2);
      if (shouldResyncTree) {
        final snapshot = await _snapshotService.capture(
          userCodeOnly: _userCodeOnly,
        );
        if (!mounted || !_followLive) return;
        _lastTreeSync = now;
        _pushSnapshot(snapshot);
        setSceneLayerGap(_layerGap);
        if (_selected != null) {
          setSceneSelection(_selected!.diagnosticsId);
        }
        setState(() {
          _snapshot = snapshot;
          _screenshotWarning = snapshot.screenshotWarning;
          final shown =
              snapshot.visibleNodes(hideOuterShells: _hideOuterShells);
          _status =
              '${shown.length} shown · live · ${snapshot.nodes.length} in tree';
        });
      } else {
        final updated = await _snapshotService.refreshScreenshot(current);
        if (!mounted || !_followLive) return;
        if (updated.pngBase64 != null) {
          updateSceneScreenshot(updated.pngBase64!);
          setState(() => _snapshot = updated);
        }
      }
    } catch (_) {
      // Keep the last good frame; the next tick retries.
    } finally {
      _liveBusy = false;
    }
  }

  Future<void> _maybeAutoRefresh() async {
    if (!serviceManager.connectedState.value.connected) return;
    if (_snapshot != null || _loading) return;
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = 'Connecting…';
    });
    try {
      final brightness = Theme.of(context).brightness;
      final snapshot = await _snapshotService.capture(
        userCodeOnly: _userCodeOnly,
        onProgress: (message) {
          if (mounted) setState(() => _status = message);
        },
      );
      _pushSnapshot(snapshot);
      setSceneTheme(brightness);
      setSceneLayerGap(_layerGap);
      setState(() {
        _snapshot = snapshot;
        _screenshotWarning = snapshot.screenshotWarning;
        _selected = null;
        final shown = snapshot.visibleNodes(hideOuterShells: _hideOuterShells);
        _status = '${shown.length} shown · live · ${snapshot.nodes.length} in tree';
        _lastTreeSync = DateTime.now();
      });
      setSceneSelection(null);
    } catch (e) {
      setState(() {
        _error = '$e';
        _status = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pushSnapshot(WidgetSceneSnapshot snapshot) {
    loadSnapshotIntoScene(
      snapshot,
      hideOuterShells: _hideOuterShells,
    );
    setSceneShowScreenshot(_showScreenshot);
    setSceneLayerMode(_multiLayer);
  }

  void _onHideOuterShellsChanged(bool? value) {
    setState(() => _hideOuterShells = value ?? false);
    final snapshot = _snapshot;
    if (snapshot != null) {
      _pushSnapshot(snapshot);
      setSceneLayerGap(_layerGap);
      final shown = snapshot.visibleNodes(hideOuterShells: _hideOuterShells);
      _status = '${shown.length} shown · ${snapshot.nodes.length} in tree';
    }
  }

  void _onScenePick(String nodeId, double x, double y) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    WidgetSceneNode? node;
    for (final candidate in snapshot.nodes) {
      if (candidate.diagnosticsId == nodeId) {
        node = candidate;
        break;
      }
    }
    node ??= _selectionController.pickDeepestAt(snapshot.nodes, x, y);
    if (node == null) return;
    unawaited(_selectNode(node));
  }

  Future<void> _selectNode(WidgetSceneNode node) async {
    setState(() => _selected = node);
    setSceneSelection(node.diagnosticsId);
    try {
      await _selectionController.selectAndNavigate(
        node: node,
        objectGroup: _snapshot?.objectGroup,
      );
      if (mounted) {
        extensionManager.showNotification(
          'Opened ${node.creationLocation?.displayLabel ?? node.description}',
        );
      }
    } catch (e) {
      if (mounted) {
        extensionManager.showNotification('Selection: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = serviceManager.connectedState.value.connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(denseSpacing),
          child: Wrap(
            spacing: denseSpacing,
            runSpacing: denseSpacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DevToolsButton(
                label: 'Refresh snapshot',
                icon: Icons.refresh,
                onPressed: !connected || _loading ? null : _refresh,
              ),
              DevToolsButton(
                label: 'Reset camera',
                icon: Icons.threed_rotation,
                onPressed: _snapshot == null ? null : resetSceneCamera,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _userCodeOnly,
                    onChanged: _loading
                        ? null
                        : (value) {
                            setState(() => _userCodeOnly = value ?? false);
                          },
                  ),
                  Text('User code only', style: theme.regularTextStyle),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _hideOuterShells,
                    onChanged: _snapshot == null ? null : _onHideOuterShellsChanged,
                  ),
                  Text('Hide outer shells', style: theme.regularTextStyle),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _followLive,
                    onChanged: (value) {
                      setState(() => _followLive = value ?? false);
                      if (value == true) _scheduleLiveFollow();
                    },
                  ),
                  Text('Follow live app', style: theme.regularTextStyle),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _showScreenshot,
                    onChanged: (value) {
                      final next = value ?? false;
                      setState(() => _showScreenshot = next);
                      setSceneShowScreenshot(next);
                    },
                  ),
                  Text('Show screenshot', style: theme.regularTextStyle),
                ],
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Single layer'),
                    icon: Icon(Icons.layers_outlined, size: 16),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Multi layer'),
                    icon: Icon(Icons.layers, size: 16),
                  ),
                ],
                selected: {_multiLayer},
                onSelectionChanged: (selected) {
                  final next = selected.contains(true);
                  setState(() => _multiLayer = next);
                  setSceneLayerMode(next);
                },
              ),
              SizedBox(
                width: 220,
                child: Row(
                  children: [
                    Text('Layer gap', style: theme.subtleTextStyle),
                    Expanded(
                      child: Slider(
                        min: 24,
                        max: 160,
                        divisions: 17,
                        value: _layerGap,
                        label: _layerGap.round().toString(),
                        onChanged: !_multiLayer
                            ? null
                            : (value) {
                                setState(() => _layerGap = value);
                                setSceneLayerGap(value);
                              },
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (_status != null) Text(_status!, style: theme.subtleTextStyle),
            ],
          ),
        ),
        if (!connected)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: denseSpacing),
            child: Text(
              'Connect DevTools to a running Flutter app to load the widget tree.',
              style: theme.subtleTextStyle,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: denseSpacing),
            child: Text(_error!, style: theme.errorTextStyle),
          ),
        if (_screenshotWarning != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: denseSpacing),
            child: Text(_screenshotWarning!, style: theme.subtleTextStyle),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(denseSpacing),
            child: Row(
              children: [
                Expanded(
                  child: RoundedOutlinedBorder(
                    child: ClipRRect(
                      borderRadius: defaultBorderRadius,
                      child: HtmlElementView(viewType: treeScapeViewType),
                    ),
                  ),
                ),
                const SizedBox(width: denseSpacing),
                SizedBox(
                  width: 260,
                  child: _SelectionSidebar(
                    selected: _selected,
                    breadcrumb: _selected == null || _snapshot == null
                        ? const []
                        : _selectionController.breadcrumbFor(
                            _snapshot!.nodes,
                            _selected!,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectionSidebar extends StatelessWidget {
  const _SelectionSidebar({
    required this.selected,
    required this.breadcrumb,
  });

  final WidgetSceneNode? selected;
  final List<WidgetSceneNode> breadcrumb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RoundedOutlinedBorder(
      child: Padding(
        padding: const EdgeInsets.all(denseSpacing),
        child: selected == null
            ? Text(
                'Left-drag orbits, right-drag pans, scroll zooms. Hover a plane for its name; click to jump to code.',
                style: theme.subtleTextStyle,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(selected!.description, style: theme.regularTextStyle),
                  const SizedBox(height: densePadding),
                  if (selected!.creationLocation != null)
                    Text(
                      selected!.creationLocation!.displayLabel,
                      style: theme.subtleTextStyle,
                    ),
                  const SizedBox(height: denseSpacing),
                  Text('Path', style: theme.subtleTextStyle),
                  const SizedBox(height: densePadding),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final node in breadcrumb)
                          Padding(
                            padding: const EdgeInsets.only(bottom: densePadding),
                            child: Text(
                              node.description,
                              style: theme.regularTextStyle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
