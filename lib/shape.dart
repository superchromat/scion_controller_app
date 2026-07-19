// shape.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'grid.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'panel.dart';
import 'shape_canvas.dart';
import 'shape_selection.dart';
import 'send_effects.dart';
import 'send_text.dart';
import 'sprite_controls.dart';

const _tabAmber = Color(0xFFF0B830);
// Tabbed-panel surfaces: the active tab and the content pane share _tabPaneBg
// so they read as one connected shape; inactive tabs are darker (recessed).
const _tabPaneBg = Color(0xFF26262B);
const _tabInactiveBg = Color(0xFF16161A);

class LinkableKnobPair extends StatefulWidget {
  final String label;
  final IconData icon;
  final String xKey;
  final String yKey;
  final double xValue;
  final double yValue;
  final double minValue;
  final double maxValue;
  final List<double>? snapPoints;
  final int precision;

  /// If true, starts linked and shows the link icon
  final bool defaultLinked;

  const LinkableKnobPair({
    super.key,
    required this.label,
    required this.icon,
    required this.xKey,
    required this.yKey,
    required this.xValue,
    required this.yValue,
    required this.minValue,
    required this.maxValue,
    required this.precision,
    this.snapPoints,
    this.defaultLinked = false,
  });

  @override
  State<LinkableKnobPair> createState() => _LinkableKnobPairState();
}

class _LinkableKnobPairState extends State<LinkableKnobPair> {
  late bool _linked = widget.defaultLinked;
  final _xKnobKey = GlobalKey<OscRotaryKnobState>();
  final _yKnobKey = GlobalKey<OscRotaryKnobState>();
  String? _lastEditedKey;

  void _toggleLink() {
    setState(() => _linked = !_linked);
    if (_linked && _lastEditedKey != null) {
      final sourceKey = _lastEditedKey == widget.xKey ? _xKnobKey : _yKnobKey;
      final targetKey = _lastEditedKey == widget.xKey ? _yKnobKey : _xKnobKey;
      final sourceVal = sourceKey.currentState?.value;
      if (sourceVal != null) {
        targetKey.currentState?.setValue(sourceVal, sendOscNow: true);
      }
    }
  }

  void _onKnobChanged({
    required String changedKey,
    required double value,
    required GlobalKey<OscRotaryKnobState> otherKnobKey,
  }) {
    _lastEditedKey = changedKey;
    if (_linked) {
      otherKnobKey.currentState?.setValue(value, sendOscNow: true);
    }
  }

  Widget _buildKnob({
    required String label,
    required String segment,
    required GlobalKey<OscRotaryKnobState> knobKey,
    required double initialValue,
    required void Function(double) onChanged,
  }) {
    final t = GridProvider.of(context);
    final format = '%.${widget.precision}f';
    return OscPathSegment(
      segment: segment,
      child: OscRotaryKnob(
        key: knobKey,
        initialValue: initialValue,
        minValue: widget.minValue,
        maxValue: widget.maxValue,
        format: format,
        label: label,
        defaultValue: initialValue,
        size: t.knobMd,
        labelStyle: t.textLabel,
        snapConfig: SnapConfig(
          snapPoints: widget.snapPoints ?? [],
          snapRegionHalfWidth: (widget.maxValue - widget.minValue) * 0.02,
          snapBehavior: SnapBehavior.hard,
        ),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Center(
            child: _buildKnob(
              label: 'X',
              segment: widget.xKey,
              knobKey: _xKnobKey,
              initialValue: widget.xValue,
              onChanged: (v) => _onKnobChanged(
                changedKey: widget.xKey,
                value: v,
                otherKnobKey: _yKnobKey,
              ),
            ),
          ),
        ),
        widget.defaultLinked
            ? GestureDetector(
                onTap: _toggleLink,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Spacer matching knob circle height
                    SizedBox(height: t.knobMd),
                    // Icon at label level (between X and Y labels)
                    SizedBox(
                      width: t.md,
                      child: Center(
                        child: Icon(
                          _linked ? Icons.link : Icons.link_off,
                          size: t.knobMd * 0.3,
                          color: _linked
                              ? const Color(0xFFFFF176)
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : SizedBox(width: t.md),
        Expanded(
          child: Center(
            child: _buildKnob(
              label: 'Y',
              segment: widget.yKey,
              knobKey: _yKnobKey,
              initialValue: widget.yValue,
              onChanged: (v) => _onKnobChanged(
                changedKey: widget.yKey,
                value: v,
                otherKnobKey: _xKnobKey,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class Shape extends StatefulWidget {
  final int? pageNumber;

  const Shape({super.key, this.pageNumber});

  @override
  ShapeState createState() => ShapeState();
}

class _RotationSend3WarningIcon extends StatefulWidget {
  const _RotationSend3WarningIcon();

  @override
  State<_RotationSend3WarningIcon> createState() =>
      _RotationSend3WarningIconState();
}

class _RotationSend3WarningIconState extends State<_RotationSend3WarningIcon> {
  static const _send3InputPath = '/send/3/input';

  final Map<String, void Function(List<Object?>)> _listeners = {};
  final Map<int, bool> _inputConnected = <int, bool>{
    1: false,
    2: false,
    3: false,
  };

  int _send3Input = 0;

  bool get _shouldShow {
    final selectedSource = _send3Input;
    if (selectedSource < 1 || selectedSource > 3) return false;
    return _inputConnected[selectedSource] == true;
  }

  @override
  void initState() {
    super.initState();
    final registry = OscRegistry();
    registry.registerAddress(_send3InputPath);
    for (int i = 1; i <= 3; i++) {
      registry.registerAddress('/input/$i/connected');
    }

    _seedFromRegistry(registry);
    _listenPath(_send3InputPath, _handleSend3Input);
    for (int i = 1; i <= 3; i++) {
      _listenPath(
          '/input/$i/connected', (args) => _handleInputConnected(i, args));
    }

    // Explicit reads ensure warning state is available even if this page is
    // opened after the last /sync snapshot was processed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final network = context.read<Network>();
      if (!network.isConnected) return;
      network.sendOscMessage(_send3InputPath, const []);
      for (int i = 1; i <= 3; i++) {
        network.sendOscMessage('/input/$i/connected', const []);
      }
    });
  }

  void _seedFromRegistry(OscRegistry registry) {
    final routeParam = registry.allParams[_send3InputPath];
    final route = _asInt(routeParam?.currentValue);
    if (route != null) {
      _send3Input = route;
    }

    for (int i = 1; i <= 3; i++) {
      final connectedPath = '/input/$i/connected';
      final connectedParam = registry.allParams[connectedPath];
      _inputConnected[i] = _asBool(connectedParam?.currentValue);
    }
  }

  void _listenPath(String path, void Function(List<Object?>) listener) {
    _listeners[path] = listener;
    OscRegistry().registerListener(path, listener);
  }

  int? _asInt(List<Object?>? args) {
    if (args == null || args.isEmpty) return null;
    final value = args.first;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  bool _asBool(List<Object?>? args) {
    if (args == null || args.isEmpty) return false;
    final value = args.first;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == 't' || normalized == '1';
  }

  void _handleSend3Input(List<Object?> args) {
    final next = _asInt(args);
    if (next == null || next == _send3Input) return;
    setState(() => _send3Input = next);
  }

  void _handleInputConnected(int inputIndex, List<Object?> args) {
    final next = _asBool(args);
    final current = _inputConnected[inputIndex] ?? false;
    if (current == next) return;
    setState(() => _inputConnected[inputIndex] = next);
  }

  @override
  void dispose() {
    final registry = OscRegistry();
    _listeners.forEach((path, listener) {
      registry.unregisterListener(path, listener);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) return const SizedBox.shrink();
    return Tooltip(
      message: 'Adjusting rotation will disable Send 3.',
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(milliseconds: 1200),
      preferBelow: false,
      verticalOffset: 14,
      textStyle: const TextStyle(
        fontFamily: 'DINPro',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.08,
        color: Color(0xFFF0F0F3),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D31),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.warning_amber,
        color: Color(0xFFFFC107),
        size: 16,
      ),
    );
  }
}

class ShapeState extends State<Shape> {
  final _rotationKey = GlobalKey<OscRotaryKnobState>();
  int _tab = 0; // 0 Transform · 1 Text · 2 Sprites · 3 Color Field

  // Shared selection/occupancy for the canvas + the two editors (see
  // ShapeSelection). When a text/sprite is picked on the canvas the selection's
  // kind flips; we follow it here by switching to the matching editor tab.
  final ShapeSelection _sel = ShapeSelection();
  List<String> _tabLabels = const [];
  // Last selection we acted on, so occupancy-only notifications (which don't
  // change kind/region) don't yank the user off whatever tab they're on.
  ShapeSel _lastSelKind = ShapeSel.none;
  int _lastSelRegion = 0;

  @override
  void initState() {
    super.initState();
    _sel.addListener(_onSelChanged);
  }

  @override
  void dispose() {
    _sel.removeListener(_onSelChanged);
    _sel.dispose();
    super.dispose();
  }

  // A genuine selection change (kind or region) → open the matching editor tab.
  // Ignores occupancy-only notifications so a text/sprite appearing elsewhere
  // doesn't pull the user off their current tab.
  void _onSelChanged() {
    if (_sel.kind == _lastSelKind && _sel.region == _lastSelRegion) return;
    _lastSelKind = _sel.kind;
    _lastSelRegion = _sel.region;
    final label = _sel.kind == ShapeSel.text
        ? 'Text'
        : _sel.kind == ShapeSel.sprite
            ? 'Sprites'
            : null;
    if (label == null) return;
    final want = _tabLabels.indexOf(label);
    if (want >= 0 && want != _tab && mounted) setState(() => _tab = want);
  }

  // One crop-edge knob (fraction of source removed from that edge, 0..0.95).
  // Firmware clamps to 0.95/edge and 0.95/axis; a single edge can trim down to
  // a 5% sliver (e.g. left+bottom at 0.95 => a 5% x 5% top-right window). Crop
  // trims without zooming.
  Widget _cropKnob(BuildContext context, String edge, String label) {
    final t = GridProvider.of(context);
    return OscPathSegment(
      segment: 'shape/crop/$edge',
      child: OscRotaryKnob(
        initialValue: 0.0,
        minValue: 0.0,
        maxValue: 0.95,
        format: '%.3f',
        label: label,
        defaultValue: 0.0,
        size: t.knobMd,
        labelStyle: t.textLabel,
        snapConfig: const SnapConfig(
          snapPoints: [0.0, 0.25, 0.5, 0.75, 0.95],
          snapRegionHalfWidth: 0.01,
          snapBehavior: SnapBehavior.hard,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    // Only show rotation for Send 1 (pageNumber == 1)
    final showRotation = widget.pageNumber == null || widget.pageNumber == 1;

    // Full-width row: the direct-manipulation canvas on the left (always
    // visible), a tabbed control pane on the right. Transform is the knob set;
    // the other tabs pull in the text OSD, sprite and uniformity controls.
    final tabs = <(String, Widget)>[
      ('Transform', _transformColumn(context, t)),
      // Warp (rotation, keystone, lens/LUT) is Send-1 only.
      if (showRotation) ('Warp', _warpColumn(context, t)),
      ('Text', const SendText()),
      // Single-group tabs: the tab pane IS the card, so the content sits
      // directly in it (grid-inset), not wrapped in another titled panel.
      ('Sprites', const SpritePanel()),
      if (showRotation) ('Color Field', _tabBody(t, const ColorFieldPanel())),
    ];
    if (_tab >= tabs.length) _tab = 0;

    // Drive the canvas overlay from the active tab: the canvas stays live while
    // the tabs switch, showing transform handles / text + sprite placeholders /
    // the colour-field mesh to match whatever is being edited on the right.
    // Transform and Warp both use the same direct-manipulation handle set.
    const overlayKeys = {
      'Transform': 'transform',
      'Warp': 'transform',
      'Text': 'text',
      'Sprites': 'sprites',
      'Color Field': 'colorField',
    };
    final activeOverlay = overlayKeys[tabs[_tab].$1] ?? 'transform';
    _tabLabels = [for (final e in tabs) e.$1];

    return ChangeNotifierProvider<ShapeSelection>.value(
      value: _sel,
      child: GridRow(
        columns: 12,
        cells: [
          (
            span: 6,
            child: ShapeCanvas(
                pageNumber: widget.pageNumber, overlay: activeOverlay),
          ),
          (
            span: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // One surface holds both the tab row and the content, so the
                // active tab (transparent) is literally the same paint as the
                // content below it — real connected tabs. Only the active tab's
                // content is built (controls bind/unbind on switch; OSC state
                // lives in the registry, so they re-seed).
                _tabbedPanel(
                    context, t, [for (final e in tabs) e.$1], tabs[_tab].$2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // A single-surface tabbed panel: one container (`_tabPaneBg`, rounded bottom)
  // holds both the tab row and the content. The active tab is transparent, so
  // that surface shows straight through it — it is the *same paint* as the
  // content, so the join can't look even slightly different. Only inactive tabs
  // get their own darker fill; they sit lower to read as "behind".
  Widget _tabbedPanel(
      BuildContext context, GridTokens t, List<String> labels, Widget content) {
    return Container(
      decoration: const BoxDecoration(
        color: _tabPaneBg,
        borderRadius: BorderRadius.all(Radius.circular(10)),
        // Subtle, tight shadow — a heavy one makes the bottom gap read as much
        // larger than the (equal) top gap between the tabs and first panel.
        boxShadow: [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < labels.length; i++)
                Expanded(
                    child: _tabChip(
                        context, t, labels[i], i, i == labels.length - 1)),
            ],
          ),
          Padding(
            // panelGap, not sm: this is the gap from the tab pane's edge to the
            // panels inside it, which must read as the same gap as the one
            // between two of those panels.
            padding: EdgeInsets.all(t.panelGap),
            child: ConstrainedBox(
              // Floor set above the tallest tab's content (Warp ≈ 35u) so every
              // tab pane is the same height — switching tabs doesn't resize the
              // card. u-relative so it tracks the window width.
              constraints: BoxConstraints(minHeight: t.u * 36),
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(
      BuildContext context, GridTokens t, String label, int i, bool last) {
    final active = _tab == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = i),
      child: Container(
        // Active tab: transparent (the panel surface reads through it) with a
        // flat amber top accent, so it merges into the content. Inactive tabs:
        // their own darker fill, rounded top, nudged down so they read behind.
        padding: EdgeInsets.symmetric(horizontal: t.xs, vertical: t.sm * 1.05),
        decoration: BoxDecoration(
          // Active: a top-lit gradient fading to the *exact* pane colour, so it
          // is physically raised up top yet merges into the content where they
          // join. Inactive: a flat darker fill. Tabs are flush with a hairline
          // groove between them, so the pane surface never peeks above or
          // between them (that was the artifact).
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF35353C), _tabPaneBg],
                )
              : null,
          color: active ? null : _tabInactiveBg,
          border: Border(
            top: BorderSide(
              color: active ? _tabAmber : Colors.white.withValues(alpha: 0.06),
              width: active ? 2 : 1,
            ),
            right: last
                ? BorderSide.none
                : BorderSide(color: Colors.black.withValues(alpha: 0.30)),
          ),
          // No shadow on the tab — any blur would bleed into the content join
          // below. The top-lit gradient supplies the raised, physical read.
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: t.textCaption.copyWith(
              fontSize: t.u * 1.15,
              color: active ? Colors.white : const Color(0xFF7A7A82),
              fontWeight: active ? FontWeight.w700 : FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  // Inset a single-group tab's content to the same left/right grid margin as
  // the multi-panel tabs, without wrapping it in another card.
  Widget _tabBody(GridTokens t, Widget child) =>
      GridRow(columns: 2, cells: [(span: 2, child: child)]);

  // Transform tab — the basic geometry available on every send: scale,
  // position and crop.
  Widget _transformColumn(BuildContext context, GridTokens t) {
    return CardColumn(
      children: [
        GridRow(
          columns: 2,
          cells: [
            (
              span: 1,
              child: Panel(
                title: 'Scale',
                child: LinkableKnobPair(
                  label: 'Scale',
                  icon: Icons.zoom_out_map,
                  xKey: 'shape/scale/x',
                  yKey: 'shape/scale/y',
                  xValue: 1.0,
                  yValue: 1.0,
                  minValue: 0.0,
                  maxValue: 4.0,
                  snapPoints: const [0.0, 0.5, 1.0, 2.0, 4.0],
                  precision: 3,
                  defaultLinked: true,
                ),
              ),
            ),
            (
              span: 1,
              child: Panel(
                title: 'Position',
                child: LinkableKnobPair(
                  label: 'Position',
                  icon: Icons.open_with,
                  xKey: 'shape/pos/x',
                  yKey: 'shape/pos/y',
                  xValue: 0.5,
                  yValue: 0.5,
                  minValue: 0.0,
                  maxValue: 1.0,
                  snapPoints: const [0.0, 0.5, 1.0],
                  precision: 3,
                ),
              ),
            ),
          ],
        ),
        GridRow(
          columns: 2,
          cells: [
            (
              span: 2,
              child: Panel(
                title: 'Crop',
                // Even 4-column grid — one knob per column across the panel —
                // matching the warp knob groups (via ControlGrid).
                child: ControlGrid(children: [
                  _cropKnob(context, 'left', 'Left'),
                  _cropKnob(context, 'right', 'Right'),
                  _cropKnob(context, 'top', 'Top'),
                  _cropKnob(context, 'bottom', 'Bottom'),
                ]),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Warp tab (Send 1 only) — rotation, keystone/shear, and the lens/LUT warp
  // plus its animation field. Each group is wrapped in a single-cell GridRow so
  // it gets the same horizontal grid inset as the Transform panels.
  Widget _warpColumn(BuildContext context, GridTokens t) {
    return CardColumn(
      children: [
        // One compact row: Rotation (1 knob) | Keystone (2×2) | Lens (2×2).
        GridRow(columns: 6, cells: [
          (
            span: 2,
            child: Panel(
              title: 'Rotation',
              titleTrailing: const _RotationSend3WarningIcon(),
              fillChild: true,
              child: Center(
                child: OscPathSegment(
                  segment: 'shape/rotation',
                  child: OscRotaryKnob(
                    key: _rotationKey,
                    initialValue: 180.0,
                    minValue: 0.0,
                    maxValue: 360.0,
                    format: '%.1f',
                    label: 'φ',
                    defaultValue: 180.0,
                    size: t.knobMd,
                    labelStyle: t.textLabel,
                    snapConfig: SnapConfig(
                      snapPoints: const [0.0, 90.0, 180.0, 270.0, 360.0],
                      snapRegionHalfWidth: 7.2,
                      snapBehavior: SnapBehavior.hard,
                    ),
                  ),
                ),
              ),
            ),
          ),
          (span: 2, child: const WarpAffinePanel(compact: true)),
          (span: 2, child: const WarpLutPanel(compact: true)),
        ]),
        GridRow(columns: 2, cells: [
          (span: 2, child: const WarpAnimationPanel()),
        ]),
      ],
    );
  }
}
