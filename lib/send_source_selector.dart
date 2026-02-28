import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'osc_registry.dart';
import 'labeled_card.dart';
import 'lighting_settings.dart';
import 'system_overview.dart';
import 'grid.dart';
import 'osc_dropdown.dart';
import 'rotary_knob.dart';

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

int _sourceSendForTileIndex(int tileIndex) =>
    tileIndex == 3 ? 4 : tileIndex + 1;

int _defaultOverlaySourceForPage(int pageNumber) {
  for (int send = 1; send <= 3; send++) {
    if (send != pageNumber) return send;
  }
  return 4;
}

int _normalizeOverlaySourceForPage(int pageNumber, int sourceSend) {
  if (sourceSend >= 1 && sourceSend <= 3 && sourceSend != pageNumber) {
    return sourceSend;
  }
  if (sourceSend == 4) return 4;
  return _defaultOverlaySourceForPage(pageNumber);
}

bool _isSourceDisallowedForPage(int pageNumber, int sourceSend) {
  return sourceSend >= 1 && sourceSend <= 3 && sourceSend == pageNumber;
}

class SendSourceSelector extends StatelessWidget {
  final int pageNumber;

  const SendSourceSelector({super.key, required this.pageNumber});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final sourceTiles = OscPathSegment(
      segment: 'input',
      child: _SelectorInner(pageNumber: pageNumber),
    );

    if (pageNumber < 1 || pageNumber > 3) return sourceTiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sourceTiles,
        SizedBox(height: t.sm),
        GridRow(
          cells: [
            for (int tileIdx = 0; tileIdx < 4; tileIdx++)
              (
                span: 3,
                child: _isSourceDisallowedForPage(
                  pageNumber,
                  _sourceSendForTileIndex(tileIdx),
                )
                    ? const SizedBox.shrink()
                    : OscPathSegment(
                        segment: 'pip',
                        child: _SendOverlayCompactControls(
                          pageNumber: pageNumber,
                          sourceSend: _sourceSendForTileIndex(tileIdx),
                        ),
                      ),
              ),
          ],
        ),
      ],
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
      child: _FormatInfo(res: _res, fps: _fps, bpp: 12, cs: _cs, sub: '4:4:4'),
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

  const _FormatInfo({
    required this.res,
    required this.fps,
    required this.bpp,
    required this.cs,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.maybeOf(context);
    return Padding(
      padding: EdgeInsets.all(t?.sm ?? 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(res, style: _greenText),
          Text(fps.toStringAsFixed(2), style: _greenText),
          Text('$bpp bit', style: _greenText),
          Row(children: [
            Text(cs, style: _greenText),
            const SizedBox(width: 8),
            Text(sub, style: _greenText),
          ]),
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
        child: NeumorphicInset(
          baseColor: const Color(0xFF262628),
          borderRadius: 4.0,
          child: Stack(
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
    );
  }
}

class _SendOverlayCompactControls extends StatefulWidget {
  final int pageNumber;
  final int sourceSend;

  const _SendOverlayCompactControls({
    required this.pageNumber,
    required this.sourceSend,
  });

  @override
  State<_SendOverlayCompactControls> createState() =>
      _SendOverlayCompactControlsState();
}

class _SendOverlayCompactControlsState
    extends State<_SendOverlayCompactControls> with OscAddressMixin {
  late int _activeSource;
  int _deviceSource = 0;
  bool _deviceEnabled = false;
  int _deviceBlend = 0;
  double _deviceAlpha = 1.0;
  double _deviceYKey = 0.0;
  double _deviceCKey = 0.0;

  int _mode = 0;
  double _alpha = 1.0;
  double _yKey = 0.0;
  double _cKey = 0.0;

  final Map<String, void Function(List<Object?>)> _listeners = {};

  String get _sourcePath => '/send/${widget.pageNumber}/pip/source_send';
  String get _enabledPath => '/send/${widget.pageNumber}/pip/enabled';
  String get _blendPath => '/send/${widget.pageNumber}/pip/opaque_blend';
  String get _alphaPath => '/send/${widget.pageNumber}/pip/alpha';
  String get _yKeyPath => '/send/${widget.pageNumber}/pip/opaque_thres_y';
  String get _cKeyPath => '/send/${widget.pageNumber}/pip/opaque_thres_c';

  @override
  void initState() {
    super.initState();
    _activeSource = _defaultOverlaySourceForPage(widget.pageNumber);
    _deviceSource = _activeSource;
    _listenPath(_sourcePath, _handleSourceUpdate);
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

  static int _parseOscInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static double _parseOscDouble(Object? raw, double fallback) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static bool _parseOscBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final s = raw?.toString().toLowerCase() ?? '';
    return s == 't' || s == 'true' || s == '1';
  }

  int _modeFromEnabledBlend(bool enabled, int blend) {
    if (!enabled) return 0;
    return switch (blend) {
      1 => 2,
      2 => 3,
      _ => 1,
    };
  }

  bool _enabledForMode(int mode) => mode != 0;

  int _blendForMode(int mode) {
    return switch (mode) {
      2 => 1,
      3 => 2,
      _ => 0,
    };
  }

  void _syncLocalFromDevice() {
    if (_activeSource != widget.sourceSend) return;
    final nextMode = _modeFromEnabledBlend(_deviceEnabled, _deviceBlend);
    final nextAlpha = _deviceAlpha.clamp(0.0, 1.0);
    final nextY = _deviceYKey.clamp(0.0, 4095.0);
    final nextC = _deviceCKey.clamp(0.0, 255.0);
    if (nextMode != _mode ||
        (nextAlpha - _alpha).abs() > 0.0001 ||
        (nextY - _yKey).abs() > 0.0001 ||
        (nextC - _cKey).abs() > 0.0001) {
      setState(() {
        _mode = nextMode;
        _alpha = nextAlpha;
        _yKey = nextY;
        _cKey = nextC;
      });
    }
  }

  void _sendLocalPresetToDevice() {
    sendOsc(_enabledForMode(_mode), address: _enabledPath);
    sendOsc(_blendForMode(_mode), address: _blendPath);
    sendOsc(_alpha, address: _alphaPath);
    sendOsc(_yKey.round(), address: _yKeyPath);
    sendOsc(_cKey.round(), address: _cKeyPath);
  }

  void _ensureSourceSelected({bool applyPresetIfChanged = false}) {
    if (_activeSource == widget.sourceSend) return;
    setState(() => _activeSource = widget.sourceSend);
    sendOsc(widget.sourceSend, address: _sourcePath);
    if (applyPresetIfChanged) {
      _sendLocalPresetToDevice();
    }
  }

  void _handleSourceUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final incoming = _parseOscInt(args.first, _deviceSource);
    final normalized =
        _normalizeOverlaySourceForPage(widget.pageNumber, incoming);
    _deviceSource = normalized;
    if (normalized != _activeSource && mounted) {
      setState(() => _activeSource = normalized);
    }
    _syncLocalFromDevice();
  }

  void _handleEnabledUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscBool(args.first);
    if (next != _deviceEnabled) {
      _deviceEnabled = next;
      _syncLocalFromDevice();
    }
  }

  void _handleBlendUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscInt(args.first, _deviceBlend).clamp(0, 2);
    if (next != _deviceBlend) {
      _deviceBlend = next;
      _syncLocalFromDevice();
    }
  }

  void _handleAlphaUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscDouble(args.first, _deviceAlpha).clamp(0.0, 1.0);
    if ((next - _deviceAlpha).abs() > 0.0001) {
      _deviceAlpha = next;
      _syncLocalFromDevice();
    }
  }

  void _handleYKeyUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscDouble(args.first, _deviceYKey).clamp(0.0, 4095.0);
    if ((next - _deviceYKey).abs() > 0.0001) {
      _deviceYKey = next;
      _syncLocalFromDevice();
    }
  }

  void _handleCKeyUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscDouble(args.first, _deviceCKey).clamp(0.0, 255.0);
    if ((next - _deviceCKey).abs() > 0.0001) {
      _deviceCKey = next;
      _syncLocalFromDevice();
    }
  }

  void _activateSource() {
    _ensureSourceSelected(applyPresetIfChanged: true);
  }

  void _onModeChanged(int mode) {
    if (mode < 0 || mode > 3) return;
    if (mode != _mode) {
      setState(() => _mode = mode);
    }
    _ensureSourceSelected();
    sendOsc(_enabledForMode(mode), address: _enabledPath);
    sendOsc(_blendForMode(mode), address: _blendPath);
  }

  void _onAlphaChanged(double value) {
    final next = value.clamp(0.0, 1.0);
    if ((next - _alpha).abs() > 0.0001) {
      setState(() => _alpha = next);
    }
    _ensureSourceSelected();
    sendOsc(_alpha, address: _alphaPath);
  }

  void _onYKeyChanged(double value) {
    final next = value.clamp(0.0, 4095.0);
    if ((next - _yKey).abs() > 0.0001) {
      setState(() => _yKey = next);
    }
    _ensureSourceSelected();
    sendOsc(_yKey.round(), address: _yKeyPath);
  }

  void _onCKeyChanged(double value) {
    final next = value.clamp(0.0, 255.0);
    if ((next - _cKey).abs() > 0.0001) {
      setState(() => _cKey = next);
    }
    _ensureSourceSelected();
    sendOsc(_cKey.round(), address: _cKeyPath);
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final knobSize = (t.knobSm * 0.72).clamp(34.0, 56.0);
    final isActive = _activeSource == widget.sourceSend;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.all(t.xs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive ? const Color(0x66FFF176) : Colors.transparent,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OverlayModeDropdown(
            mode: _mode,
            sourceSend: widget.sourceSend,
            onChanged: _onModeChanged,
            onActivateSource: _activateSource,
          ),
          _OverlayModeKnobs(
            knobSize: knobSize,
            mode: _mode,
            alphaValue: _alpha,
            yKeyValue: _yKey,
            cKeyValue: _cKey,
            onAlphaChanged: _onAlphaChanged,
            onYKeyChanged: _onYKeyChanged,
            onCKeyChanged: _onCKeyChanged,
            onInteract: _activateSource,
          ),
        ],
      ),
    );
  }
}

class _OverlayModeKnobs extends StatelessWidget {
  final double knobSize;
  final int mode;
  final double alphaValue;
  final double yKeyValue;
  final double cKeyValue;
  final ValueChanged<double> onAlphaChanged;
  final ValueChanged<double> onYKeyChanged;
  final ValueChanged<double> onCKeyChanged;
  final VoidCallback onInteract;

  const _OverlayModeKnobs({
    required this.knobSize,
    required this.mode,
    required this.alphaValue,
    required this.yKeyValue,
    required this.cKeyValue,
    required this.onAlphaChanged,
    required this.onYKeyChanged,
    required this.onCKeyChanged,
    required this.onInteract,
  });

  Widget _withSourceSelection(Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onInteract(),
      child: child,
    );
  }

  Widget _alphaKnob(TextStyle? labelStyle) {
    return _withSourceSelection(
      RotaryKnob(
        value: alphaValue,
        minValue: 0.0,
        maxValue: 1.0,
        format: '%.2f',
        label: 'Mix',
        defaultValue: 1.0,
        size: knobSize,
        labelStyle: labelStyle,
        onChanged: onAlphaChanged,
        snapConfig: const SnapConfig(
          snapPoints: [0.0, 0.25, 0.5, 0.75, 1.0],
          snapRegionHalfWidth: 0.02,
          snapBehavior: SnapBehavior.hard,
        ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    if (mode == 0) {
      return const SizedBox.shrink();
    }

    if (mode == 1) {
      return Padding(
        padding: EdgeInsets.only(top: t.xs),
        child: Center(child: _alphaKnob(t.textLabel)),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: t.xs),
      child: Row(
        children: [
          Expanded(child: Center(child: _alphaKnob(t.textLabel))),
          Expanded(child: Center(child: _yKeyKnob(t.textLabel))),
          Expanded(child: Center(child: _cKeyKnob(t.textLabel))),
        ],
      ),
    );
  }
}

class _OverlayModeDropdown extends StatelessWidget {
  final int mode;
  final int sourceSend;
  final ValueChanged<int> onChanged;
  final VoidCallback onActivateSource;

  const _OverlayModeDropdown({
    required this.mode,
    required this.sourceSend,
    required this.onChanged,
    required this.onActivateSource,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onActivateSource(),
      child: OscDropdown<int>(
        key: ValueKey<int>(mode),
        label: 'Mode',
        pathSegment: '_overlay_mode_$sourceSend',
        items: const [0, 1, 2, 3],
        itemLabels: const {
          0: 'No Overlay',
          1: 'Mix',
          2: 'Key',
          3: 'Key Reverse',
        },
        defaultValue: mode,
        sendOscDirect: false,
        showLabel: false,
        width: double.infinity,
        onChanged: onChanged,
      ),
    );
  }
}
