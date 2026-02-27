import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'osc_registry.dart';
import 'labeled_card.dart';
import 'lighting_settings.dart';
import 'system_overview.dart';
import 'grid.dart';
import 'osc_rotary_knob.dart';
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

    if (pageNumber != 1 && pageNumber != 2) return sourceTiles;

    final controlTileColumn = pageNumber == 1 ? 1 : 0;

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
                child: tileIdx == controlTileColumn
                    ? OscPathSegment(
                        segment: 'pip',
                        child: _SendOverlayCompactControls(
                          pageNumber: pageNumber,
                        ),
                      )
                    : const SizedBox.shrink(),
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

class _SendOverlayCompactControls extends StatelessWidget {
  final int pageNumber;

  const _SendOverlayCompactControls({required this.pageNumber});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final knobSize = (t.knobSm * 0.72).clamp(34.0, 56.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverlayModeDropdown(pageNumber: pageNumber),
        _OverlayModeKnobs(knobSize: knobSize, pageNumber: pageNumber),
      ],
    );
  }
}

class _OverlayModeKnobs extends StatefulWidget {
  final double knobSize;
  final int pageNumber;

  const _OverlayModeKnobs({
    required this.knobSize,
    required this.pageNumber,
  });

  @override
  State<_OverlayModeKnobs> createState() => _OverlayModeKnobsState();
}

class _OverlayModeKnobsState extends State<_OverlayModeKnobs> {
  bool _enabled = false;
  int _blendMode = 0;
  int _mode = 0;
  final Map<String, void Function(List<Object?>)> _listeners = {};

  String get _enabledPath => '/send/${widget.pageNumber}/pip/enabled';
  String get _blendPath => '/send/${widget.pageNumber}/pip/opaque_blend';

  @override
  void initState() {
    super.initState();
    _listenPath(_enabledPath, _handleEnabledUpdate);
    _listenPath(_blendPath, _handleBlendUpdate);
    _primeFromRegistry();
  }

  @override
  void dispose() {
    final registry = OscRegistry();
    _listeners.forEach((path, cb) => registry.unregisterListener(path, cb));
    super.dispose();
  }

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
    _refreshModeFromState();
  }

  static bool _parseOscBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final s = raw?.toString().toLowerCase() ?? '';
    return s == 't' || s == 'true' || s == '1';
  }

  static int _parseOscInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  void _handleEnabledUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscBool(args.first);
    if (next != _enabled) {
      setState(() => _enabled = next);
      _refreshModeFromState();
    }
  }

  void _handleBlendUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscInt(args.first, _blendMode).clamp(0, 2);
    if (next != _blendMode) {
      setState(() => _blendMode = next);
      _refreshModeFromState();
    }
  }

  void _refreshModeFromState() {
    final resolvedMode = !_enabled
        ? 0
        : switch (_blendMode) {
            1 => 2,
            2 => 3,
            _ => 1,
          };
    if (resolvedMode != _mode && mounted) {
      setState(() => _mode = resolvedMode);
    }
  }

  Widget _alphaKnob(TextStyle? labelStyle) {
    return OscPathSegment(
      segment: 'alpha',
      child: OscRotaryKnob(
        initialValue: 1.0,
        minValue: 0.0,
        maxValue: 1.0,
        format: '%.2f',
        label: 'Mix',
        defaultValue: 1.0,
        size: widget.knobSize,
        labelStyle: labelStyle,
        snapConfig: const SnapConfig(
          snapPoints: [0.0, 0.25, 0.5, 0.75, 1.0],
          snapRegionHalfWidth: 0.02,
          snapBehavior: SnapBehavior.hard,
        ),
      ),
    );
  }

  Widget _yKeyKnob(TextStyle? labelStyle) {
    return OscPathSegment(
      segment: 'opaque_thres_y',
      child: OscRotaryKnob(
        initialValue: 0.0,
        minValue: 0.0,
        maxValue: 4095.0,
        format: '%.0f',
        label: 'Y Key',
        defaultValue: 0.0,
        size: widget.knobSize,
        labelStyle: labelStyle,
        preferInteger: true,
      ),
    );
  }

  Widget _cKeyKnob(TextStyle? labelStyle) {
    return OscPathSegment(
      segment: 'opaque_thres_c',
      child: OscRotaryKnob(
        initialValue: 0.0,
        minValue: 0.0,
        maxValue: 255.0,
        format: '%.0f',
        label: 'C Key',
        defaultValue: 0.0,
        size: widget.knobSize,
        labelStyle: labelStyle,
        preferInteger: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    if (_mode == 0) {
      return const SizedBox.shrink();
    }

    if (_mode == 1) {
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

class _OverlayModeDropdown extends StatefulWidget {
  final int pageNumber;

  const _OverlayModeDropdown({required this.pageNumber});

  @override
  State<_OverlayModeDropdown> createState() => _OverlayModeDropdownState();
}

class _OverlayModeDropdownState extends State<_OverlayModeDropdown>
    with OscAddressMixin {
  int _mode = 0;
  bool _enabled = false;
  int _blendMode = 0;
  final Map<String, void Function(List<Object?>)> _listeners = {};

  String get _enabledPath => '/send/${widget.pageNumber}/pip/enabled';
  String get _blendPath => '/send/${widget.pageNumber}/pip/opaque_blend';

  @override
  void initState() {
    super.initState();
    _listenPath(_enabledPath, _handleEnabledUpdate);
    _listenPath(_blendPath, _handleBlendUpdate);
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
    _refreshModeFromState();
  }

  static bool _parseOscBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final s = raw?.toString().toLowerCase() ?? '';
    return s == 't' || s == 'true' || s == '1';
  }

  static int _parseOscInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  void _handleEnabledUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscBool(args.first);
    if (next != _enabled) {
      setState(() => _enabled = next);
      _refreshModeFromState();
    }
  }

  void _handleBlendUpdate(List<Object?> args) {
    if (args.isEmpty) return;
    final next = _parseOscInt(args.first, _blendMode).clamp(0, 2);
    if (next != _blendMode) {
      setState(() => _blendMode = next);
      _refreshModeFromState();
    }
  }

  void _refreshModeFromState() {
    final resolvedMode = !_enabled
        ? 0
        : switch (_blendMode) {
            1 => 2,
            2 => 3,
            _ => 1,
          };
    if (resolvedMode != _mode && mounted) {
      setState(() => _mode = resolvedMode);
    }
  }

  void _sendMode(int mode) {
    if (mode < 0 || mode > 3) return;

    final enabled = mode != 0;
    final blend = switch (mode) {
      2 => 1,
      3 => 2,
      _ => 0,
    };

    setState(() {
      _mode = mode;
      _enabled = enabled;
      _blendMode = blend;
    });

    sendOsc(enabled, address: _enabledPath);
    sendOsc(blend, address: _blendPath);
  }

  @override
  Widget build(BuildContext context) {
    return OscDropdown<int>(
      key: ValueKey<int>(_mode),
      label: 'Mode',
      pathSegment: '_overlay_mode',
      items: const [0, 1, 2, 3],
      itemLabels: const {
        0: 'No Overlay',
        1: 'Mix',
        2: 'Key',
        3: 'Key Reverse',
      },
      defaultValue: _mode,
      sendOscDirect: false,
      showLabel: false,
      width: double.infinity,
      onChanged: _sendMode,
    );
  }
}
