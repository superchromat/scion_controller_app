import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'system_overview.dart'; // for TileLayout
import 'osc_registry.dart';
import 'labeled_card.dart'; // for NeumorphicInset
import 'lighting_settings.dart';

const TextStyle _systemTextStyle = TextStyle(
  color: Colors.green,
  fontFamily: 'Courier',
  fontSize: 12,
);
const TextStyle _systemTextStyleRed = TextStyle(
  color: Colors.red,
  fontFamily: 'Courier',
  fontSize: 12,
);

// Overlay label style for tile indices and letters
final TextStyle kOverlayTextStyle = TextStyle(
  color: Colors.grey[800],
  fontSize: 72,
  fontWeight: FontWeight.bold,
);

/// Overlay text with lighting gradient and noise texture
class _LitOverlayText extends StatelessWidget {
  final String label;
  const _LitOverlayText({required this.label});

  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return lighting.createPhongSurfaceGradient(
          baseColor: const Color(0xFF454548),  // Darker grey matching tile background
          intensity: 0.12,
        ).createShader(bounds);
      },
      child: Text(label, style: kOverlayTextStyle),
    );
  }
}

/// A generic tile that displays up to five values: resolution (String),
/// framerate (double), bit depth (int), colorspace (String), and optional chroma subsampling.
/// Each can be a static value or an OSC path (starting with '/').
/// An [overlayLabel] (e.g. "1", "R", "O") is shown behind the content.
class VideoFormatTile extends StatefulWidget {
  final String overlayLabel;
  final String? resolution;
  final String? framerate;
  final String bitDepth;
  final String colorSpace;
  final String? chromaSubsampling;
  final String? connectedPath;

  const VideoFormatTile({
    super.key,
    required this.overlayLabel,
    this.resolution,
    this.framerate,
    required this.bitDepth,
    required this.colorSpace,
    this.chromaSubsampling,
    this.connectedPath,
  });

  @override
  State<VideoFormatTile> createState() => _VideoFormatTileState();
}

class _VideoFormatTileState extends State<VideoFormatTile>
    with TickerProviderStateMixin {
  String _res = '';
  double _fps = 0.0;
  int _bpp = 0;
  String _cs = '';
  String _sub = '';
  bool _connected = true;

  late final AnimationController _resController;
  late final Animation<Color?> _resColor;
  late final AnimationController _fpsController;
  late final Animation<Color?> _fpsColor;
  late final AnimationController _bppController;
  late final Animation<Color?> _bppColor;
  late final AnimationController _csController;
  late final Animation<Color?> _csColor;
  late final AnimationController _subController;
  late final Animation<Color?> _subColor;

  @override
  void initState() {
    super.initState();
    const flashTime = 500; // ms

    _resController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: flashTime),
      value: 1,
    );
    _resColor = ColorTween(begin: Colors.yellow, end: Colors.green)
        .animate(_resController);

    _fpsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: flashTime),
      value: 1,
    );
    _fpsColor = ColorTween(begin: Colors.yellow, end: Colors.green)
        .animate(_fpsController);

    _bppController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: flashTime),
      value: 1,
    );
    _bppColor = ColorTween(begin: Colors.yellow, end: Colors.green)
        .animate(_bppController);

    _csController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: flashTime),
      value: 1,
    );
    _csColor = ColorTween(begin: Colors.yellow, end: Colors.green)
        .animate(_csController);

    _subController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: flashTime),
      value: 1,
    );
    _subColor = ColorTween(begin: Colors.yellow, end: Colors.green)
        .animate(_subController);
  }

  @override
  void dispose() {
    _resController.dispose();
    _fpsController.dispose();
    _bppController.dispose();
    _csController.dispose();
    _subController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = OscRegistry();

    bool parseBool(dynamic raw) {
      if (raw is bool) return raw;
      final s = raw.toString().toLowerCase();
      return s == 't' || s == 'true' || s == '1';
    }

    void bindString(
      String? src,
      String Function() getOld,
      ValueSetter<String> setter,
      AnimationController ctl,
    ) {
      if (src == null) return;
      if (src.startsWith('/')) {
        registry.registerAddress(src);
        final param = registry.allParams[src];
        if (param != null && param.currentValue.isNotEmpty) {
          final newVal = param.currentValue.first.toString();
          if (getOld() != newVal) {
            setState(() => setter(newVal));
            ctl.forward(from: 0);
          }
        }
        registry.registerListener(src, (args) {
          final newVal = args.isNotEmpty ? args.first.toString() : '';
          if (!mounted) return;
          if (getOld() != newVal) {
            setState(() => setter(newVal));
            ctl.forward(from: 0);
          }
        });
      } else {
        if (getOld() != src) setState(() => setter(src));
      }
    }

    void bindDouble(
      String? src,
      double Function() getOld,
      ValueSetter<double> setter,
      AnimationController ctl,
    ) {
      if (src == null) return;
      if (src.startsWith('/')) {
        registry.registerAddress(src);
        final param = registry.allParams[src];
        if (param != null && param.currentValue.isNotEmpty) {
          final newVal =
              double.tryParse(param.currentValue.first.toString()) ?? 0.0;
          if (getOld() != newVal) {
            setState(() => setter(newVal));
            ctl.forward(from: 0);
          }
        }
        registry.registerListener(src, (args) {
          final newVal = double.tryParse(
                args.isNotEmpty ? args.first.toString() : '',
              ) ??
              0.0;
          if (!mounted) return;
          if (getOld() != newVal) {
            setState(() => setter(newVal));
            ctl.forward(from: 0);
          }
        });
      } else {
        final parsed = double.tryParse(src) ?? 0.0;
        if (getOld() != parsed) setState(() => setter(parsed));
      }
    }

    void bindInt(
      String src,
      int Function() getOld,
      ValueSetter<int> setter,
      AnimationController ctl,
    ) {
      if (src.startsWith('/')) {
        registry.registerAddress(src);
        final param = registry.allParams[src];
        if (param != null && param.currentValue.isNotEmpty) {
          final newVal = int.tryParse(param.currentValue.first.toString()) ?? 0;
          if (getOld() != newVal) {
            setState(() => setter(newVal));
            ctl.forward(from: 0);
          }
        }
        registry.registerListener(src, (args) {
          final newVal = int.tryParse(
                args.isNotEmpty ? args.first.toString() : '',
              ) ??
              0;
          if (!mounted) return;
          if (getOld() != newVal) {
            setState(() => setter(newVal));
            ctl.forward(from: 0);
          }
        });
      } else {
        final parsed = int.tryParse(src) ?? 0;
        if (getOld() != parsed) setState(() => setter(parsed));
      }
    }

    if (widget.connectedPath != null) {
      final src = widget.connectedPath!;
      if (src.startsWith('/')) {
        registry.registerAddress(src);
        final param = registry.allParams[src];
        if (param != null && param.currentValue.isNotEmpty) {
          final newVal = parseBool(param.currentValue.first);
          if (_connected != newVal) _connected = newVal;
        }
        registry.registerListener(src, (args) {
          final newVal = args.isNotEmpty ? parseBool(args.first) : false;
          if (!mounted) return;
          if (_connected != newVal) {
            setState(() => _connected = newVal);
          }
        });
      } else {
        final newVal = parseBool(src);
        if (_connected != newVal) _connected = newVal;
      }
    } else if (!_connected) {
      _connected = true;
    }

    bindString(widget.resolution, () => _res, (v) => _res = v, _resController);
    bindDouble(widget.framerate, () => _fps, (v) => _fps = v, _fpsController);
    bindInt(widget.bitDepth, () => _bpp, (v) => _bpp = v, _bppController);
    bindString(widget.colorSpace, () => _cs, (v) => _cs = v, _csController);
    bindString(
        widget.chromaSubsampling, () => _sub, (v) => _sub = v, _subController);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(TileLayout.tileOuterMargin),
      child: NeumorphicInset(
        baseColor: const Color(0xFF262628),
        borderRadius: 4.0,
        child: Stack(
          children: [
            Positioned(
              right: 4,
              bottom: -8,
              child: _LitOverlayText(label: widget.overlayLabel),
            ),
            if (_connected)
              Padding(
                padding: EdgeInsets.all(TileLayout.sectionBoxPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.resolution != null)
                      AnimatedBuilder(
                        animation: _resColor,
                        builder: (ctx, _) => Text(
                          _res,
                          style:
                              _systemTextStyle.copyWith(color: _resColor.value),
                        ),
                      ),
                    if (widget.framerate != null)
                      AnimatedBuilder(
                        animation: _fpsColor,
                        builder: (ctx, _) => Text(
                          _fps.toStringAsFixed(2),
                          style:
                              _systemTextStyle.copyWith(color: _fpsColor.value),
                        ),
                      ),
                    AnimatedBuilder(
                      animation: _bppColor,
                      builder: (ctx, _) => Text(
                        '$_bpp bit',
                        style: _systemTextStyle.copyWith(color: _bppColor.value),
                      ),
                    ),
                    Row(
                      children: [
                        AnimatedBuilder(
                          animation: _csColor,
                          builder: (ctx, _) => Text(
                            _cs,
                            style:
                                _systemTextStyle.copyWith(color: _csColor.value),
                          ),
                        ),
                        if (widget.chromaSubsampling != null) ...[
                          const SizedBox(width: 8),
                          AnimatedBuilder(
                            animation: _subColor,
                            builder: (ctx, _) => Text(
                              _sub,
                              style: _systemTextStyle.copyWith(
                                  color: _subColor.value),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              )
            else
              Center(
                child: Text('Disconnected', style: _systemTextStyleRed),
              ),
          ],
        ),
      ),
    );
  }
}

/// Wraps VideoFormatTile for each section
class AnalogSendTile extends StatelessWidget {
  final int index;
  const AnalogSendTile({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'input',
      child: OscPathSegment(
        segment: index.toString(),
        child: VideoFormatTile(
          overlayLabel: index.toString(),
          resolution: '/analog_format/resolution',
          framerate: '/analog_format/framerate',
          bitDepth: '10',
          colorSpace: '/analog_format/colorspace',
          chromaSubsampling: '4:4:4',
        ),
      ),
    );
  }
}

class ReturnTile extends StatelessWidget {
  const ReturnTile({super.key});

  @override
  Widget build(BuildContext context) {
    return VideoFormatTile(
      overlayLabel: 'R',
      resolution: '/analog_format/resolution',
      framerate: '/analog_format/framerate',
      bitDepth: '12',
      colorSpace: '/analog_format/colorspace',
      chromaSubsampling: '4:4:4',
    );
  }
}

class HDMIOutTile extends StatelessWidget {
  const HDMIOutTile({super.key});

  @override
  Widget build(BuildContext context) {
    return VideoFormatTile(
      overlayLabel: 'O',
      connectedPath: '/output/connected',
      resolution: '/output/resolution',
      framerate: '/output/framerate',
      bitDepth: '/output/bit_depth',
      colorSpace: '/output/colorspace',
      chromaSubsampling: '/output/chroma_subsampling',
    );
  }
}

/// Input tiles: show large number behind content
class InputTile extends StatelessWidget {
  final int index;
  const InputTile({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'input',
      child: OscPathSegment(
        segment: index.toString(),
        child: _InputTileInner(index: index),
      ),
    );
  }
}

class _InputTileInner extends StatefulWidget {
  final int index;
  const _InputTileInner({required this.index});

  @override
  __InputTileInnerState createState() => __InputTileInnerState();
}

class __InputTileInnerState extends State<_InputTileInner> {
  bool _connected = false;
  String _res = '';
  double _fps = 0.0;
  int _bpp = 0;
  String _cs = '';
  String _sub = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = OscRegistry();
    final base = '/input/${widget.index}';
    final segments = [
      'connected',
      'resolution',
      'framerate',
      'bit_depth',
      'colorspace',
      'chroma_subsampling',
    ];
    for (var seg in segments) {
      registry.registerAddress('$base/$seg');
    }

    registry.registerListener('$base/connected', (args) {
      final v = args.isNotEmpty && args.first == true;
      if (v != _connected) setState(() => _connected = v);
    });
    registry.registerListener('$base/resolution', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _res) setState(() => _res = v);
    });
    registry.registerListener('$base/framerate', (args) {
      final parsed = double.tryParse(
            args.isNotEmpty ? args.first.toString() : '',
          ) ??
          0.0;
      if (parsed != _fps) setState(() => _fps = parsed);
    });
    registry.registerListener('$base/bit_depth', (args) {
      final parsed = int.tryParse(
            args.isNotEmpty ? args.first.toString() : '',
          ) ??
          0;
      if (parsed != _bpp) setState(() => _bpp = parsed);
    });
    registry.registerListener('$base/colorspace', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _cs) setState(() => _cs = v);
    });
    registry.registerListener('$base/chroma_subsampling', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _sub) setState(() => _sub = v);
    });
  }

  @override
  void dispose() {
    final registry = OscRegistry();
    final base = '/input/${widget.index}';
    for (var seg in [
      'connected',
      'resolution',
      'framerate',
      'bit_depth',
      'colorspace',
      'chroma_subsampling',
    ]) {
      registry.unregisterListener('$base/$seg', (_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(TileLayout.tileOuterMargin),
      child: NeumorphicInset(
        baseColor: const Color(0xFF262628),
        borderRadius: 4.0,
        child: Stack(
          children: [
            Positioned(
              right: 4,
              bottom: -8,
              child: _LitOverlayText(label: widget.index.toString()),
            ),
            if (_connected)
              Padding(
                padding: EdgeInsets.all(TileLayout.sectionBoxPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_res, style: _systemTextStyle),
                    Text(_fps.toStringAsFixed(2), style: _systemTextStyle),
                    Text('$_bpp bpp', style: _systemTextStyle),
                    Row(children: [
                      Text(_cs, style: _systemTextStyle),
                      const SizedBox(width: 8),
                      Text(_sub, style: _systemTextStyle),
                    ]),
                  ],
                ),
              )
            else
              Center(
                child: Text('Disconnected', style: _systemTextStyleRed),
              ),
          ],
        ),
      ),
    );
  }
}

class SyncLock extends StatelessWidget {
  const SyncLock({super.key});

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.lock, color: Colors.yellow, size: 48);
  }
}
