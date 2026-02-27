import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'grid.dart';
import 'labeled_card.dart';
import 'lighting_settings.dart';
import 'osc_checkbox.dart';
import 'osc_registry.dart';
import 'osc_rotary_knob.dart';
import 'osc_value_dropdown.dart';
import 'osc_widget_binding.dart';
import 'panel.dart';
import 'rotary_knob.dart';

const TextStyle _overlayGreenText = TextStyle(
  color: Colors.green,
  fontFamily: 'Courier',
  fontSize: 11,
  height: 1.2,
);

const TextStyle _overlayRedText = TextStyle(
  color: Colors.red,
  fontFamily: 'Courier',
  fontSize: 11,
  height: 1.2,
);

bool _parseOscBool(Object? raw) {
  if (raw is bool) return raw;
  final s = raw?.toString().toLowerCase() ?? '';
  return s == 't' || s == 'true' || s == '1';
}

class _SourceInfo {
  final bool connected;
  final String resolution;
  final double framerate;
  final int bitDepth;
  final String colorSpace;
  final String chromaSubsampling;

  const _SourceInfo({
    required this.connected,
    required this.resolution,
    required this.framerate,
    required this.bitDepth,
    required this.colorSpace,
    required this.chromaSubsampling,
  });
}

class SendOverlaySource extends StatelessWidget {
  final int pageNumber;

  const SendOverlaySource({super.key, required this.pageNumber});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'pip',
      child: _SendOverlaySourceInner(pageNumber: pageNumber),
    );
  }
}

class _SendOverlaySourceInner extends StatelessWidget {
  final int pageNumber;

  const _SendOverlaySourceInner({required this.pageNumber});

  Widget _buildSettingsPanel(BuildContext context) {
    final t = GridProvider.of(context);
    return Panel(
      title: 'Settings',
      child: Row(
        children: [
          Expanded(
            child: OscPathSegment(
              segment: 'enabled',
              child: Align(
                alignment: Alignment.centerLeft,
                child: OscCheckbox(
                  initialValue: false,
                  label: 'Enable',
                  size: 20,
                ),
              ),
            ),
          ),
          SizedBox(width: t.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Blend Mode', style: t.textLabel),
                SizedBox(height: t.xs),
                OscPathSegment(
                  segment: 'opaque_blend',
                  child: OscValueDropdown<int>(
                    values: const [0, 1, 2],
                    labels: const ['Off', 'On', 'Reverse'],
                    initialValue: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlendPanel(BuildContext context) {
    final t = GridProvider.of(context);
    return Panel(
      title: 'Mix',
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: OscPathSegment(
                segment: 'alpha',
                child: OscRotaryKnob(
                  initialValue: 1.0,
                  minValue: 0.0,
                  maxValue: 1.0,
                  format: '%.2f',
                  label: 'A',
                  defaultValue: 1.0,
                  size: t.knobMd,
                  labelStyle: t.textLabel,
                  snapConfig: const SnapConfig(
                    snapPoints: [0.0, 0.25, 0.5, 0.75, 1.0],
                    snapRegionHalfWidth: 0.02,
                    snapBehavior: SnapBehavior.hard,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: OscPathSegment(
                segment: 'opaque_thres_y',
                child: OscRotaryKnob(
                  initialValue: 0.0,
                  minValue: 0.0,
                  maxValue: 4095.0,
                  format: '%.0f',
                  label: 'Y',
                  defaultValue: 0.0,
                  size: t.knobMd,
                  labelStyle: t.textLabel,
                  preferInteger: true,
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: OscPathSegment(
                segment: 'opaque_thres_c',
                child: OscRotaryKnob(
                  initialValue: 0.0,
                  minValue: 0.0,
                  maxValue: 255.0,
                  format: '%.0f',
                  label: 'C',
                  defaultValue: 0.0,
                  size: t.knobMd,
                  labelStyle: t.textLabel,
                  preferInteger: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcePanel(BuildContext context) {
    return Panel(
      title: 'Source',
      fillChild: true,
      child: OscPathSegment(
        segment: 'source_send',
        child: _OverlaySourceSelector(pageNumber: pageNumber),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return CardColumn(
      children: [
        _buildSettingsPanel(context),
        _buildBlendPanel(context),
        SizedBox(
          height: t.knobMd * 3.4,
          child: _buildSourcePanel(context),
        ),
      ],
    );
  }
}

class _OverlaySourceSelector extends StatefulWidget {
  final int pageNumber;

  const _OverlaySourceSelector({required this.pageNumber});

  @override
  State<_OverlaySourceSelector> createState() => _OverlaySourceSelectorState();
}

class _OverlaySourceSelectorState extends State<_OverlaySourceSelector>
    with OscAddressMixin {
  int _selectedSource = 0;

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isEmpty) return OscStatus.error;
    final raw = args.first;
    final parsed = raw is int
        ? raw
        : (raw is num ? raw.toInt() : int.tryParse(raw.toString()));
    if (parsed == null) return OscStatus.error;
    if (parsed != _selectedSource) {
      setState(() => _selectedSource = parsed);
    }
    return OscStatus.ok;
  }

  void _selectSource(int sourceId) {
    setState(() => _selectedSource = sourceId);
    sendOsc(sourceId);
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _OverlaySendPipelineTile(
                  sendIndex: 1,
                  selected: _selectedSource == 1,
                  onTap: () => _selectSource(1),
                ),
              ),
              SizedBox(width: t.sm),
              Expanded(
                child: _OverlaySendPipelineTile(
                  sendIndex: 2,
                  selected: _selectedSource == 2,
                  onTap: () => _selectSource(2),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: t.sm),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _OverlaySendPipelineTile(
                  sendIndex: 3,
                  selected: _selectedSource == 3,
                  onTap: () => _selectSource(3),
                ),
              ),
              SizedBox(width: t.sm),
              Expanded(
                child: _OverlayReturnTile(
                  selected: _selectedSource == 4,
                  onTap: () => _selectSource(4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverlaySendPipelineTile extends StatefulWidget {
  final int sendIndex;
  final bool selected;
  final VoidCallback onTap;

  const _OverlaySendPipelineTile({
    required this.sendIndex,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_OverlaySendPipelineTile> createState() =>
      _OverlaySendPipelineTileState();
}

class _OverlaySendPipelineTileState extends State<_OverlaySendPipelineTile> {
  int _mappedInput = 1;
  final Map<String, void Function(List<Object?>)> _listeners = {};

  final Map<int, bool> _connected = {1: false, 2: false, 3: false};
  final Map<int, String> _resolution = {1: '', 2: '', 3: ''};
  final Map<int, double> _framerate = {1: 0.0, 2: 0.0, 3: 0.0};
  final Map<int, int> _bitDepth = {1: 0, 2: 0, 3: 0};
  final Map<int, String> _colorSpace = {1: '', 2: '', 3: ''};
  final Map<int, String> _chroma = {1: '', 2: '', 3: ''};

  String _returnResolution = '';
  double _returnFramerate = 0.0;
  String _returnColorSpace = '';

  void _listen(String path, void Function(List<Object?>) cb) {
    final registry = OscRegistry();
    registry.registerAddress(path);
    _listeners[path] = cb;
    registry.registerListener(path, cb);
  }

  @override
  void initState() {
    super.initState();

    _mappedInput = widget.sendIndex;
    final sendPath = '/send/${widget.sendIndex}/input';
    _listen(sendPath, (args) {
      final parsed = args.isNotEmpty
          ? int.tryParse(args.first.toString()) ?? _mappedInput
          : _mappedInput;
      if (parsed != _mappedInput && mounted) {
        setState(() => _mappedInput = parsed);
      }
    });

    for (int i = 1; i <= 3; i++) {
      _listen('/input/$i/connected', (args) {
        final value = args.isNotEmpty && _parseOscBool(args.first);
        if (_connected[i] != value && mounted) {
          setState(() => _connected[i] = value);
        }
      });
      _listen('/input/$i/resolution', (args) {
        final value = args.isNotEmpty ? args.first.toString() : '';
        if (_resolution[i] != value && mounted) {
          setState(() => _resolution[i] = value);
        }
      });
      _listen('/input/$i/framerate', (args) {
        final value = double.tryParse(
              args.isNotEmpty ? args.first.toString() : '',
            ) ??
            0.0;
        if (_framerate[i] != value && mounted) {
          setState(() => _framerate[i] = value);
        }
      });
      _listen('/input/$i/bit_depth', (args) {
        final value = int.tryParse(
              args.isNotEmpty ? args.first.toString() : '',
            ) ??
            0;
        if (_bitDepth[i] != value && mounted) {
          setState(() => _bitDepth[i] = value);
        }
      });
      _listen('/input/$i/colorspace', (args) {
        final value = args.isNotEmpty ? args.first.toString() : '';
        if (_colorSpace[i] != value && mounted) {
          setState(() => _colorSpace[i] = value);
        }
      });
      _listen('/input/$i/chroma_subsampling', (args) {
        final value = args.isNotEmpty ? args.first.toString() : '';
        if (_chroma[i] != value && mounted) {
          setState(() => _chroma[i] = value);
        }
      });
    }

    _listen('/analog_format/resolution', (args) {
      final value = args.isNotEmpty ? args.first.toString() : '';
      if (_returnResolution != value && mounted) {
        setState(() => _returnResolution = value);
      }
    });
    _listen('/analog_format/framerate', (args) {
      final value = double.tryParse(
            args.isNotEmpty ? args.first.toString() : '',
          ) ??
          0.0;
      if (_returnFramerate != value && mounted) {
        setState(() => _returnFramerate = value);
      }
    });
    _listen('/analog_format/colorspace', (args) {
      final value = args.isNotEmpty ? args.first.toString() : '';
      if (_returnColorSpace != value && mounted) {
        setState(() => _returnColorSpace = value);
      }
    });

    final registry = OscRegistry();
    for (final entry in _listeners.entries) {
      final param = registry.allParams[entry.key];
      if (param != null && param.currentValue.isNotEmpty) {
        entry.value(param.currentValue.cast<Object?>());
      }
    }
  }

  @override
  void dispose() {
    final registry = OscRegistry();
    _listeners.forEach((path, cb) => registry.unregisterListener(path, cb));
    super.dispose();
  }

  _SourceInfo _activeInfo() {
    if (_mappedInput == 4) {
      return _SourceInfo(
        connected: true,
        resolution: _returnResolution,
        framerate: _returnFramerate,
        bitDepth: 12,
        colorSpace: _returnColorSpace,
        chromaSubsampling: '4:4:4',
      );
    }

    if (_mappedInput < 1 || _mappedInput > 3) {
      return const _SourceInfo(
        connected: false,
        resolution: '',
        framerate: 0.0,
        bitDepth: 0,
        colorSpace: '',
        chromaSubsampling: '',
      );
    }

    return _SourceInfo(
      connected: _connected[_mappedInput] ?? false,
      resolution: _resolution[_mappedInput] ?? '',
      framerate: _framerate[_mappedInput] ?? 0.0,
      bitDepth: _bitDepth[_mappedInput] ?? 0,
      colorSpace: _colorSpace[_mappedInput] ?? '',
      chromaSubsampling: _chroma[_mappedInput] ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _OverlaySelectableTile(
      overlayLabel: widget.sendIndex.toString(),
      selected: widget.selected,
      onTap: widget.onTap,
      child: _OverlayFormatInfo(info: _activeInfo()),
    );
  }
}

class _OverlayReturnTile extends StatefulWidget {
  final bool selected;
  final VoidCallback onTap;

  const _OverlayReturnTile({
    required this.selected,
    required this.onTap,
  });

  @override
  State<_OverlayReturnTile> createState() => _OverlayReturnTileState();
}

class _OverlayReturnTileState extends State<_OverlayReturnTile> {
  final Map<String, void Function(List<Object?>)> _listeners = {};
  String _resolution = '';
  double _framerate = 0.0;
  String _colorSpace = '';

  void _listen(String path, void Function(List<Object?>) cb) {
    final registry = OscRegistry();
    registry.registerAddress(path);
    _listeners[path] = cb;
    registry.registerListener(path, cb);
  }

  @override
  void initState() {
    super.initState();

    _listen('/analog_format/resolution', (args) {
      final value = args.isNotEmpty ? args.first.toString() : '';
      if (value != _resolution && mounted) {
        setState(() => _resolution = value);
      }
    });

    _listen('/analog_format/framerate', (args) {
      final value = double.tryParse(
            args.isNotEmpty ? args.first.toString() : '',
          ) ??
          0.0;
      if (value != _framerate && mounted) {
        setState(() => _framerate = value);
      }
    });

    _listen('/analog_format/colorspace', (args) {
      final value = args.isNotEmpty ? args.first.toString() : '';
      if (value != _colorSpace && mounted) {
        setState(() => _colorSpace = value);
      }
    });

    final registry = OscRegistry();
    for (final entry in _listeners.entries) {
      final param = registry.allParams[entry.key];
      if (param != null && param.currentValue.isNotEmpty) {
        entry.value(param.currentValue.cast<Object?>());
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
    return _OverlaySelectableTile(
      overlayLabel: 'R',
      selected: widget.selected,
      onTap: widget.onTap,
      child: _OverlayFormatInfo(
        info: _SourceInfo(
          connected: true,
          resolution: _resolution,
          framerate: _framerate,
          bitDepth: 12,
          colorSpace: _colorSpace,
          chromaSubsampling: '4:4:4',
        ),
      ),
    );
  }
}

class _OverlayFormatInfo extends StatelessWidget {
  final _SourceInfo info;

  const _OverlayFormatInfo({required this.info});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final green = _overlayGreenText.copyWith(
      fontSize: (t.textCaption.fontSize ?? 11) * 0.95,
    );
    final red = _overlayRedText.copyWith(
      fontSize: (t.textCaption.fontSize ?? 11) * 0.95,
    );

    if (!info.connected) {
      return Center(child: Text('Disconnected', style: red));
    }

    return Padding(
      padding: EdgeInsets.all(t.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(info.resolution, style: green),
          Text(info.framerate.toStringAsFixed(2), style: green),
          Text('${info.bitDepth} bit', style: green),
          Row(
            children: [
              Flexible(child: Text(info.colorSpace, style: green)),
              SizedBox(width: t.xs),
              Flexible(child: Text(info.chromaSubsampling, style: green)),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverlaySelectableTile extends StatelessWidget {
  final String overlayLabel;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _OverlaySelectableTile({
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
                bottom: -7,
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
                  child: Text(
                    overlayLabel,
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontSize: 50,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
