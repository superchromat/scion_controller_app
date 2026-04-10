import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'osc_registry.dart';
import 'labeled_card.dart';
import 'lighting_settings.dart';
import 'system_overview.dart';
import 'grid.dart';
import 'rotary_knob.dart';
import 'neumorphic_slider.dart';

// Styles are now derived from GridTokens where possible, but these
// status-indicator colors don't fit the standard token palette.
const TextStyle _greenText = TextStyle(
  color: Colors.green,
  fontFamily: 'Courier',
  fontSize: 12,
);
const TextStyle _redText = TextStyle(
  color: Colors.red,
  fontFamily: 'Courier',
  fontSize: 12,
);

final TextStyle _overlayStyle = TextStyle(
  color: Colors.grey[800],
  fontSize: 72,
  fontWeight: FontWeight.bold,
);

/// PIP layer number (1-based) for a given source.
/// Sources 1..3 => Send 1..3, source 4 => Return.
/// Layer number matches source number in the new OSC API.

class SendSourceSelector extends StatelessWidget {
  final int pageNumber;

  const SendSourceSelector({super.key, required this.pageNumber});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'input',
      child: _SelectorInner(pageNumber: pageNumber),
    );
  }
}

class _SelectorInner extends StatefulWidget {
  final int pageNumber;
  const _SelectorInner({required this.pageNumber});

  @override
  State<_SelectorInner> createState() => _SelectorInnerState();
}

class _SelectorInnerState extends State<_SelectorInner> with OscAddressMixin {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.pageNumber;
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    final incoming = args.isNotEmpty ? args.first : null;
    if (incoming is int) {
      setState(() => _selected = incoming);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  void _select(int value) {
    setState(() => _selected = value);
    sendOsc(value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TileLayout.tileHeight,
      child: GridRow(
        cells: [
          for (int i = 1; i <= 3; i++)
            (
              span: 3,
              child: _InputSourceTile(
                inputIndex: i,
                selected: _selected == i,
                onTap: () => _select(i),
              ),
            ),
          (
            span: 3,
            child: _ReturnSourceTile(
              selected: _selected == 4,
              onTap: () => _select(4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile for HDMI inputs 1-3. Listens to /input/N/... OSC paths.
class _InputSourceTile extends StatefulWidget {
  final int inputIndex;
  final bool selected;
  final VoidCallback onTap;

  const _InputSourceTile({
    required this.inputIndex,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_InputSourceTile> createState() => _InputSourceTileState();
}

class _InputSourceTileState extends State<_InputSourceTile> {
  bool _connected = false;
  String _res = '';
  double _fps = 0.0;
  int _bpp = 0;
  String _cs = '';
  String _sub = '';

  static const _segments = [
    'connected',
    'resolution',
    'framerate',
    'bit_depth',
    'colorspace',
    'chroma_subsampling',
  ];

  late final String _base;
  final Map<String, void Function(List<Object?>)> _listeners = {};

  @override
  void initState() {
    super.initState();
    _base = '/input/${widget.inputIndex}';
    final registry = OscRegistry();

    for (var seg in _segments) {
      registry.registerAddress('$_base/$seg');
    }

    void listen(String seg, void Function(List<Object?>) cb) {
      _listeners['$_base/$seg'] = cb;
      registry.registerListener('$_base/$seg', cb);
    }

    listen('connected', (args) {
      final v = args.isNotEmpty && args.first == true;
      if (v != _connected && mounted) setState(() => _connected = v);
    });
    listen('resolution', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _res && mounted) setState(() => _res = v);
    });
    listen('framerate', (args) {
      final v = double.tryParse(
            args.isNotEmpty ? args.first.toString() : '',
          ) ??
          0.0;
      if (v != _fps && mounted) setState(() => _fps = v);
    });
    listen('bit_depth', (args) {
      final v = int.tryParse(
            args.isNotEmpty ? args.first.toString() : '',
          ) ??
          0;
      if (v != _bpp && mounted) setState(() => _bpp = v);
    });
    listen('colorspace', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _cs && mounted) setState(() => _cs = v);
    });
    listen('chroma_subsampling', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _sub && mounted) setState(() => _sub = v);
    });

    // Read initial values from registry
    for (var seg in _segments) {
      final param = registry.allParams['$_base/$seg'];
      if (param != null && param.currentValue.isNotEmpty) {
        final raw = param.currentValue.first;
        switch (seg) {
          case 'connected':
            _connected = raw == true;
          case 'resolution':
            _res = raw.toString();
          case 'framerate':
            _fps = double.tryParse(raw.toString()) ?? 0.0;
          case 'bit_depth':
            _bpp = int.tryParse(raw.toString()) ?? 0;
          case 'colorspace':
            _cs = raw.toString();
          case 'chroma_subsampling':
            _sub = raw.toString();
        }
      }
    }
  }

  @override
  void dispose() {
    final registry = OscRegistry();
    _listeners.forEach((path, cb) => registry.unregisterListener(path, cb));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SelectableTile(
      overlayLabel: widget.inputIndex.toString(),
      selected: widget.selected,
      onTap: widget.onTap,
      child: _connected
          ? _FormatInfo(res: _res, fps: _fps, bpp: _bpp, cs: _cs, sub: _sub)
          : Center(child: Text('Disconnected', style: _redText)),
    );
  }
}

/// Tile for the Return loopback source.
class _ReturnSourceTile extends StatefulWidget {
  final bool selected;
  final VoidCallback onTap;

  const _ReturnSourceTile({required this.selected, required this.onTap});

  @override
  State<_ReturnSourceTile> createState() => _ReturnSourceTileState();
}

class _ReturnSourceTileState extends State<_ReturnSourceTile> {
  String _res = '';
  double _fps = 0.0;
  String _cs = '';
  bool _interlaced = false;

  final Map<String, void Function(List<Object?>)> _listeners = {};

  @override
  void initState() {
    super.initState();
    final registry = OscRegistry();

    void listen(String path, void Function(List<Object?>) cb) {
      registry.registerAddress(path);
      _listeners[path] = cb;
      registry.registerListener(path, cb);
    }

    listen('/analog_format/resolution', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _res && mounted) setState(() => _res = v);
    });
    listen('/analog_format/framerate', (args) {
      final v = double.tryParse(
            args.isNotEmpty ? args.first.toString() : '',
          ) ??
          0.0;
      if (v != _fps && mounted) setState(() => _fps = v);
    });
    listen('/analog_format/colorspace', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _cs && mounted) setState(() => _cs = v);
    });
    listen('/analog_format/interlaced', (args) {
      final v = args.isNotEmpty && args.first.toString().toUpperCase() == 'T';
      if (v != _interlaced && mounted) setState(() => _interlaced = v);
    });

    // Read initial values
    for (var path in _listeners.keys) {
      final param = registry.allParams[path];
      if (param != null && param.currentValue.isNotEmpty) {
        final raw = param.currentValue.first;
        if (path.endsWith('resolution')) {
          _res = raw.toString();
        }
        if (path.endsWith('framerate')) {
          _fps = double.tryParse(raw.toString()) ?? 0.0;
        }
        if (path.endsWith('colorspace')) {
          _cs = raw.toString();
        }
        if (path.endsWith('interlaced')) {
          _interlaced = raw.toString().toUpperCase() == 'T';
        }
      }
    }
  }

  @override
  void dispose() {
    final registry = OscRegistry();
    _listeners.forEach((path, cb) => registry.unregisterListener(path, cb));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SelectableTile(
      overlayLabel: 'R',
      selected: widget.selected,
      onTap: widget.onTap,
      child: _FormatInfo(res: _res, fps: _fps, bpp: 12, cs: _cs, sub: '4:4:4', interlaced: _interlaced),
    );
  }
}

/// Format info column used by both tile types.
class _FormatInfo extends StatelessWidget {
  final String res;
  final double fps;
  final int bpp;
  final String cs;
  final String sub;
  final bool interlaced;

  const _FormatInfo({
    required this.res,
    required this.fps,
    required this.bpp,
    required this.cs,
    required this.sub,
    this.interlaced = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.maybeOf(context);
    return Padding(
      padding: EdgeInsets.all(t?.xs ?? 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(res, style: _greenText, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${fps.toStringAsFixed(2)}${interlaced ? 'i' : 'p'}', style: _greenText),
          Text('$bpp bit', style: _greenText),
          Text('$cs $sub', style: _greenText, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Wraps tile content with selection border, overlay label, and tap handling.
class _SelectableTile extends StatelessWidget {
  final String overlayLabel;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _SelectableTile({
    required this.overlayLabel,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? const Color(0xFFFFF176) : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: NeumorphicInset(
            baseColor: const Color(0xFF262628),
            borderRadius: 4.0,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  right: 4,
                  bottom: -8,
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) {
                      return lighting
                          .createPhongSurfaceGradient(
                            baseColor: const Color(0xFF454548),
                            intensity: 0.12,
                          )
                          .createShader(bounds);
                    },
                    child: Text(overlayLabel, style: _overlayStyle),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SendOverlayCompactControls extends StatefulWidget {
  final int pageNumber;
  final int sourceSend;

  /// Crossfade weight (0.0–1.0). When [crossfadeActive] is true, this
  /// directly controls the effective alpha sent to the device (0→100%).
  final double alphaWeight;

  /// True when this cell is assigned to an A/B group. When active, the
  /// crossfader overrides the Mix slider — effective alpha = [alphaWeight].
  /// When false, effective alpha = user's Mix slider value.
  final bool crossfadeActive;

  const SendOverlayCompactControls({
    super.key,
    required this.pageNumber,
    required this.sourceSend,
    this.alphaWeight = 1.0,
    this.crossfadeActive = false,
  });

  @override
  State<SendOverlayCompactControls> createState() =>
      _SendOverlayCompactControlsState();
}

class _SendOverlayCompactControlsState
    extends State<SendOverlayCompactControls> with OscAddressMixin {
  // Device echo state (for tracking what firmware reports back)
  int _deviceBlend = 0;
  double _deviceAlpha = 0.0;
  double _deviceYKey = 0.0;
  double _deviceCKey = 0.0;

  double _alpha = 0.0;
  double _yKey = 0.0;
  double _cKey = 0.0;
  bool _keyReverse = false;

  final Map<String, void Function(List<Object?>)> _listeners = {};

  /// PIP layer number matches the source number (1..4).
  int get _layer => widget.sourceSend;

  String get _enabledPath => '/send/${widget.pageNumber}/pip/$_layer/enabled';
  String get _blendPath => '/send/${widget.pageNumber}/pip/$_layer/opaque_blend';
  String get _alphaPath => '/send/${widget.pageNumber}/pip/$_layer/alpha';
  String get _yKeyPath => '/send/${widget.pageNumber}/pip/$_layer/opaque_thres_y';
  String get _cKeyPath => '/send/${widget.pageNumber}/pip/$_layer/opaque_thres_c';

  @override
  void initState() {
    super.initState();
    _listenPath(_enabledPath, _handleEnabledUpdate);
    _listenPath(_blendPath, _handleBlendUpdate);
    _listenPath(_alphaPath, _handleAlphaUpdate);
    _listenPath(_yKeyPath, _handleYKeyUpdate);
    _listenPath(_cKeyPath, _handleCKeyUpdate);
    _primeFromRegistry();
  }

  @override
  void dispose() {
    final registry = OscRegistry();
    _listeners.forEach((path, cb) => registry.unregisterListener(path, cb));
    super.dispose();
  }

  @override
  OscStatus onOscMessage(List<Object?> args) => OscStatus.ok;

  void _listenPath(String path, void Function(List<Object?>) cb) {
    final registry = OscRegistry();
    registry.registerAddress(path);
    _listeners[path] = cb;
    registry.registerListener(path, cb);
  }

  void _primeFromRegistry() {
    final registry = OscRegistry();
    for (final entry in _listeners.entries) {
      final param = registry.allParams[entry.key];
      if (param != null && param.currentValue.isNotEmpty) {
        entry.value(param.currentValue.cast<Object?>());
      }
    }
  }

  static double _parseOscDouble(Object? raw, double fallback) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static int _parseOscInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  /// When crossfade is active, the weight IS the alpha (0→100%).
  /// When inactive (unassigned), the user's Mix slider controls alpha.
  double get _effectiveAlpha =>
      widget.crossfadeActive ? widget.alphaWeight : _alpha;

  /// PIP should be enabled if there's any mix intent OR keying.
  /// When crossfade-active, any non-zero weight counts as mix intent.
  bool get _hasMix => widget.crossfadeActive
      ? widget.alphaWeight > 0.0001
      : _alpha > 0.0001;
  bool get _hasKey => _yKey > 0.0001 || _cKey > 0.0001;

  @override
  void didUpdateWidget(SendOverlayCompactControls old) {
    super.didUpdateWidget(old);
    if (old.crossfadeActive != widget.crossfadeActive) {
      // Mode changed — send everything
      _sendAll();
    } else if ((old.alphaWeight - widget.alphaWeight).abs() > 0.0001) {
      // Crossfade moving — only send alpha + enabled (fast path)
      _sendAlphaOnly();
    }
  }

  /// Send just the alpha and enabled state (fast path for crossfader drag).
  void _sendAlphaOnly() {
    final enabled = _hasMix || _hasKey;
    sendOsc(enabled, address: _enabledPath);
    sendOsc(_effectiveAlpha, address: _alphaPath);
  }

  /// Send everything to device: effective alpha, key values, enabled, blend.
  void _sendAll() {
    final enabled = _hasMix || _hasKey;
    final blend = _hasKey ? (_keyReverse ? 2 : 1) : 0;
    sendOsc(enabled, address: _enabledPath);
    sendOsc(blend, address: _blendPath);
    sendOsc(_effectiveAlpha, address: _alphaPath);
    sendOsc(_yKey.round(), address: _yKeyPath);
    sendOsc(_cKey.round(), address: _cKeyPath);
  }

  // --- Device echo handlers ---
  // enabled/blend echoes just track device state; they don't touch local values.
  // Value echoes (alpha/yKey/cKey) update local state directly.

  void _handleEnabledUpdate(List<Object?> args) {
    // enabled is a derived output — we don't sync from it.
  }

  void _handleBlendUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscInt(args.first, _deviceBlend).clamp(0, 2);
    _deviceBlend = next;
    final nextReverse = next == 2;
    if (nextReverse != _keyReverse) {
      setState(() => _keyReverse = nextReverse);
    }
  }

  void _handleAlphaUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscDouble(args.first, _deviceAlpha).clamp(0.0, 1.0);
    _deviceAlpha = next;
    // Ignore echoes that match what we sent (not an external change).
    if ((next - _effectiveAlpha).abs() < 0.01) return;
    // External change — recover user alpha from effective.
    final w = widget.alphaWeight;
    final userAlpha = w > 0.0001 ? (next / w).clamp(0.0, 1.0) : _alpha;
    if ((userAlpha - _alpha).abs() > 0.0001) {
      setState(() => _alpha = userAlpha);
    }
  }

  void _handleYKeyUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscDouble(args.first, _deviceYKey).clamp(0.0, 4095.0);
    _deviceYKey = next;
    if ((next - _yKey).abs() > 0.0001) {
      setState(() => _yKey = next);
    }
  }

  void _handleCKeyUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscDouble(args.first, _deviceCKey).clamp(0.0, 255.0);
    _deviceCKey = next;
    if ((next - _cKey).abs() > 0.0001) {
      setState(() => _cKey = next);
    }
  }

  // --- User interaction handlers ---

  void _onAlphaChanged(double value) {
    final next = value.clamp(0.0, 1.0);
    if ((next - _alpha).abs() > 0.0001) {
      setState(() => _alpha = next);
    }
    _sendAll();
  }

  void _onYKeyChanged(double value) {
    final next = value.clamp(0.0, 4095.0);
    if ((next - _yKey).abs() > 0.0001) {
      setState(() => _yKey = next);
    }
    _sendAll();
  }

  void _onCKeyChanged(double value) {
    final next = value.clamp(0.0, 255.0);
    if ((next - _cKey).abs() > 0.0001) {
      setState(() => _cKey = next);
    }
    _sendAll();
  }

  void _onKeyReverseChanged(bool value) {
    if (value != _keyReverse) {
      setState(() => _keyReverse = value);
    }
    _sendAll();
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final knobSize = (t.knobSm * 0.92).clamp(44.0, 68.0);

    return Padding(
      padding: EdgeInsets.all(t.xs),
      child: Center(
        child: _OverlayModeKnobs(
            knobSize: knobSize,
            alphaValue: _alpha,
            alphaWeight: widget.alphaWeight,
            crossfadeActive: widget.crossfadeActive,
            yKeyValue: _yKey,
            cKeyValue: _cKey,
            keyReverse: _keyReverse,
            onAlphaChanged: _onAlphaChanged,
            onYKeyChanged: _onYKeyChanged,
            onCKeyChanged: _onCKeyChanged,
            onKeyReverseChanged: _onKeyReverseChanged,
            onInteract: () {},
            alphaOscPath: _alphaPath,
            yKeyOscPath: _yKeyPath,
            cKeyOscPath: _cKeyPath,
          ),
      ),
    );
  }
}

class _OverlayModeKnobs extends StatelessWidget {
  final double knobSize;
  final double alphaValue;      // user intent (0-1)
  final double alphaWeight;     // crossfade weight (0-1)
  final bool crossfadeActive;   // true when cell is in an A/B group
  final double yKeyValue;
  final double cKeyValue;
  final bool keyReverse;
  final ValueChanged<double> onAlphaChanged;
  final ValueChanged<double> onYKeyChanged;
  final ValueChanged<double> onCKeyChanged;
  final ValueChanged<bool> onKeyReverseChanged;
  final VoidCallback onInteract;
  final String? alphaOscPath;
  final String? yKeyOscPath;
  final String? cKeyOscPath;

  const _OverlayModeKnobs({
    required this.knobSize,
    required this.alphaValue,
    this.alphaWeight = 1.0,
    this.crossfadeActive = false,
    required this.yKeyValue,
    required this.cKeyValue,
    required this.keyReverse,
    required this.onAlphaChanged,
    required this.onYKeyChanged,
    required this.onCKeyChanged,
    required this.onKeyReverseChanged,
    required this.onInteract,
    this.alphaOscPath,
    this.yKeyOscPath,
    this.cKeyOscPath,
  });

  Widget _withSourceSelection(Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onInteract(),
      child: child,
    );
  }

  Widget _alphaSlider(double trackLength) {
    // When crossfade-active, slider shows the crossfade weight directly.
    // When inactive, slider shows the user's alpha value.
    final display = crossfadeActive ? alphaWeight : alphaValue;
    return _withSourceSelection(
      NeumorphicSlider(
        value: display * 100,
        minValue: 0.0,
        maxValue: 100.0,
        format: '',
        label: '',
        defaultValue: 100.0,
        axis: SliderAxis.vertical,
        trackLength: trackLength,
        trackWidth: 8,
        thumbLength: 24,
        graduations: 10,
        onChanged: (v) => onAlphaChanged(v / 100.0),
      ),
    );
  }

  Widget _yKeyKnob(TextStyle? labelStyle) {
    return _withSourceSelection(
      RotaryKnob(
        value: yKeyValue,
        minValue: 0.0,
        maxValue: 4095.0,
        format: '%.0f',
        label: 'Y Key',
        defaultValue: 0.0,
        size: knobSize,
        labelStyle: labelStyle,
        integerOnly: true,
        onChanged: onYKeyChanged,
        oscPath: yKeyOscPath,
      ),
    );
  }

  Widget _cKeyKnob(TextStyle? labelStyle) {
    return _withSourceSelection(
      RotaryKnob(
        value: cKeyValue,
        minValue: 0.0,
        maxValue: 255.0,
        format: '%.0f',
        label: 'C Key',
        defaultValue: 0.0,
        size: knobSize,
        labelStyle: labelStyle,
        integerOnly: true,
        onChanged: onCKeyChanged,
        oscPath: cKeyOscPath,
      ),
    );
  }

  Widget _keyReverseToggle(TextStyle? labelStyle) {
    return _withSourceSelection(
      GestureDetector(
        onTap: () => onKeyReverseChanged(!keyReverse),
        child: Icon(
          Icons.invert_colors,
          size: (labelStyle?.fontSize ?? 11) * 1.6,
          color: keyReverse
              ? const Color(0xFFF0B830)
              : const Color(0xFFD2D2D4),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    // Slider height sized to fit two knobs + gap + reverse checkbox
    final sliderHeight = knobSize * 2 + t.sm * 2 + 20;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Vertical Mix % slider
        _alphaSlider(sliderHeight),
        SizedBox(width: t.xs),
        // Key knobs stacked vertically with Reverse checkbox
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _yKeyKnob(t.textLabel),
            SizedBox(height: t.xs),
            _cKeyKnob(t.textLabel),
            SizedBox(height: t.xs),
            _keyReverseToggle(t.textLabel),
          ],
        ),
      ],
    );
  }
}

/// Compact 2×2 source selector for the mixer page.
///
/// Lays out four tiles (Input 1, Input 2, Input 3, Return) in a 2-column grid.
/// Sends the selected source index to `/send/<pageNumber>/input`.
class SendSourceSelector2x2 extends StatelessWidget {
  final int pageNumber;

  const SendSourceSelector2x2({super.key, required this.pageNumber});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'send/$pageNumber/input',
      child: _Selector2x2Inner(pageNumber: pageNumber),
    );
  }
}

class _Selector2x2Inner extends StatefulWidget {
  final int pageNumber;
  const _Selector2x2Inner({required this.pageNumber});

  @override
  State<_Selector2x2Inner> createState() => _Selector2x2InnerState();
}

class _Selector2x2InnerState extends State<_Selector2x2Inner>
    with OscAddressMixin {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.pageNumber;
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    final incoming = args.isNotEmpty ? args.first : null;
    if (incoming is int) {
      setState(() => _selected = incoming);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  void _select(int value) {
    setState(() => _selected = value);
    sendOsc(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final gap = t.xs;

    return Column(
      // Fill parent height when inside Expanded (mixer page),
      // otherwise use natural height (send page).
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _InputSourceTile(
                  inputIndex: 1,
                  selected: _selected == 1,
                  onTap: () => _select(1),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _InputSourceTile(
                  inputIndex: 2,
                  selected: _selected == 2,
                  onTap: () => _select(2),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: gap),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _InputSourceTile(
                  inputIndex: 3,
                  selected: _selected == 3,
                  onTap: () => _select(3),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _ReturnSourceTile(
                  selected: _selected == 4,
                  onTap: () => _select(4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

