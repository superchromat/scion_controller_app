import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'labeled_card.dart';
import 'grid.dart';
import 'shape.dart';
import 'send_color.dart';
import 'send_text.dart';
import 'send_source_selector.dart';
import 'dac_parameters.dart';
import 'send_texture.dart';
import 'send_glitch.dart';
import 'osc_registry.dart';
import 'network.dart';

class SendPage extends StatefulWidget {
  final int pageNumber;

  const SendPage({super.key, required this.pageNumber});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> with OscAddressMixin {
  final _glitchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Pre-register shape addresses to avoid race condition with /sync response
    final registry = OscRegistry();
    final send = '/send/${widget.pageNumber}';
    registry.registerAddress('$send/scaleX');
    registry.registerAddress('$send/scaleY');
    registry.registerAddress('$send/posX');
    registry.registerAddress('$send/posY');
    // Only register rotation for Send 1
    if (widget.pageNumber == 1) {
      registry.registerAddress('$send/rotation');
    }
    // PIP controls are supported on all send pages.
    if (widget.pageNumber >= 1 && widget.pageNumber <= 3) {
      registry.registerAddress('$send/pip/enabled');
      registry.registerAddress('$send/pip/source_send');
      registry.registerAddress('$send/pip/alpha');
      registry.registerAddress('$send/pip/opaque_blend');
      registry.registerAddress('$send/pip/opaque_thres_y');
      registry.registerAddress('$send/pip/opaque_thres_c');
    }
  }

  Widget _resetButton(VoidCallback onPressed) {
    return IconButton(
      icon: Icon(Icons.refresh, size: 18, color: Colors.grey[500]),
      onPressed: onPressed,
      tooltip: 'Reset to defaults',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final t = GridTokens(constraints.maxWidth);
        final sectionGap = t.md;
        return GridProvider(
          tokens: t,
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.all(t.md),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OscPathSegment(
                          segment: 'send/${widget.pageNumber}',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              GridRow(gutter: t.md, cells: [
                                (
                                  span: 12,
                                  child: LabeledCard(
                                    title: 'Send Source',
                                    child: SendSourceSelector(
                                        pageNumber: widget.pageNumber),
                                  ),
                                )
                              ]),
                              SizedBox(height: sectionGap),
                              GridRow(
                                gutter: t.md,
                                cells: [
                                  (
                                    span: 4,
                                    child: LabeledCard(
                                      title: 'Shape',
                                      child:
                                          Shape(pageNumber: widget.pageNumber),
                                    ),
                                  ),
                                  (
                                    span: 4,
                                    child: LabeledCard(
                                      title: 'Texture',
                                      child: const SendTexture(),
                                    ),
                                  ),
                                  (
                                    span: 4,
                                    child: LabeledCard(
                                      title: 'Text',
                                      child: const SendText(),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: sectionGap),
                              GridRow(gutter: t.md, cells: [
                                (
                                  span: 12,
                                  child: LabeledCard(
                                    title: 'Color',
                                    child: SendColor(
                                      showGrade: widget.pageNumber == 1,
                                      gradePath: widget.pageNumber == 1
                                          ? '/send/${widget.pageNumber}/grade'
                                          : null,
                                    ),
                                  ),
                                )
                              ]),
                              SizedBox(height: sectionGap),
                              GridRow(gutter: t.md, cells: [
                                (
                                  span: 12,
                                  child: LabeledCard(
                                    title: 'Glitch',
                                    action: _resetButton(() =>
                                        (_glitchKey.currentState as dynamic)
                                            ?.reset()),
                                    child: SendGlitch(key: _glitchKey),
                                  ),
                                )
                              ]),
                            ],
                          ),
                        ),
                        SizedBox(height: sectionGap),
                        OscPathSegment(
                          segment: 'dac/${widget.pageNumber}',
                          child: GridRow(gutter: t.md, cells: [
                            (
                              span: 12,
                              child: const LabeledCard(
                                  title: 'DAC', child: DacParameters()),
                            )
                          ]),
                        ),
                      ],
                    ),
                    if (kShowGrid) const Positioned.fill(child: GridOverlay()),
                  ],
                ),
              ),
              if (widget.pageNumber == 3)
                const Positioned.fill(
                  child: _Send3RotationDisabledOverlay(),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Send3RotationDisabledOverlay extends StatefulWidget {
  const _Send3RotationDisabledOverlay();

  @override
  State<_Send3RotationDisabledOverlay> createState() =>
      _Send3RotationDisabledOverlayState();
}

class _Send3RotationDisabledOverlayState
    extends State<_Send3RotationDisabledOverlay> {
  static const _send1RotationPath = '/send/1/rotation';
  static const _send3InputPath = '/send/3/input';

  final Map<String, void Function(List<Object?>)> _listeners = {};
  final Map<int, bool> _inputConnected = <int, bool>{
    1: false,
    2: false,
    3: false,
  };

  double _send1Rotation = 0.0;
  int _send3Input = 0;

  bool get _rotationEnabled => (_send1Rotation - 180.0).abs() > 0.0001;

  bool get _send3ConnectedToActiveSource {
    final source = _send3Input;
    if (source < 1 || source > 3) return false;
    return _inputConnected[source] == true;
  }

  bool get _showOverlay => _rotationEnabled && _send3ConnectedToActiveSource;

  @override
  void initState() {
    super.initState();
    final registry = OscRegistry();
    registry.registerAddress(_send1RotationPath);
    registry.registerAddress(_send3InputPath);
    for (int i = 1; i <= 3; i++) {
      registry.registerAddress('/input/$i/connected');
    }

    _seedFromRegistry(registry);
    _listenPath(_send1RotationPath, _handleSend1Rotation);
    _listenPath(_send3InputPath, _handleSend3Input);
    for (int i = 1; i <= 3; i++) {
      _listenPath(
          '/input/$i/connected', (args) => _handleInputConnected(i, args));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final network = context.read<Network>();
      if (!network.isConnected) return;
      network.sendOscMessage(_send1RotationPath, const []);
      network.sendOscMessage(_send3InputPath, const []);
      for (int i = 1; i <= 3; i++) {
        network.sendOscMessage('/input/$i/connected', const []);
      }
    });
  }

  void _seedFromRegistry(OscRegistry registry) {
    _send1Rotation =
        _asDouble(registry.allParams[_send1RotationPath]?.currentValue);
    final routed = _asInt(registry.allParams[_send3InputPath]?.currentValue);
    if (routed != null) _send3Input = routed;
    for (int i = 1; i <= 3; i++) {
      _inputConnected[i] =
          _asBool(registry.allParams['/input/$i/connected']?.currentValue);
    }
  }

  void _listenPath(String path, void Function(List<Object?>) listener) {
    _listeners[path] = listener;
    OscRegistry().registerListener(path, listener);
  }

  double _asDouble(List<Object?>? args) {
    if (args == null || args.isEmpty) return 0.0;
    final value = args.first;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
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

  void _handleSend1Rotation(List<Object?> args) {
    final next = _asDouble(args);
    if ((next - _send1Rotation).abs() < 0.0001) return;
    setState(() => _send1Rotation = next);
  }

  void _handleSend3Input(List<Object?> args) {
    final next = _asInt(args);
    if (next == null || next == _send3Input) return;
    setState(() => _send3Input = next);
  }

  void _handleInputConnected(int inputIndex, List<Object?> args) {
    final next = _asBool(args);
    final current = _inputConnected[inputIndex] ?? false;
    if (next == current) return;
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
    if (!_showOverlay) return const SizedBox.shrink();
    final textColor = Colors.white.withValues(alpha: 0.78);
    return Container(
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 78, 78, 78).withValues(alpha: 0.35),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber, color: textColor, size: 32),
              const SizedBox(height: 10),
              Text(
                'Send 3 disabled while Send 1 is rotated',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
