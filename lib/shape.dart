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
        fontSize: 13,
        fontWeight: FontWeight.w500,
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

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    // Only show rotation for Send 1 (pageNumber == 1)
    final showRotation = widget.pageNumber == null || widget.pageNumber == 1;

    return CardColumn(
      children: [
        GridRow(
          columns: 2,
          gutter: t.md,
          cells: [
            (
              span: 1,
              child: Panel(
                title: 'Scale',
                child: LinkableKnobPair(
                  label: 'Scale',
                  icon: Icons.zoom_out_map,
                  xKey: 'scaleX',
                  yKey: 'scaleY',
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
                  xKey: 'posX',
                  yKey: 'posY',
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
        if (showRotation)
          GridRow(
            columns: 2,
            gutter: t.md,
            cells: [
              (
                span: 1,
                child: Panel(
                  title: 'Rotation',
                  titleTrailing: const _RotationSend3WarningIcon(),
                  child: Center(
                    child: OscPathSegment(
                      segment: 'rotation',
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
              (span: 1, child: const SizedBox()),
            ],
          ),
      ],
    );
  }
}
