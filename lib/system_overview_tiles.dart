import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_text.dart';
import 'system_overview.dart'; // for TileLayout

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
  color: Colors.grey[850],
  fontSize: 96,
  fontWeight: FontWeight.bold,
);

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

  const VideoFormatTile({
    Key? key,
    required this.overlayLabel,
    this.resolution,
    this.framerate,
    required this.bitDepth,
    required this.colorSpace,
    this.chromaSubsampling,
  }) : super(key: key);

  @override
  _VideoFormatTileState createState() => _VideoFormatTileState();
}

class _VideoFormatTileState extends State<VideoFormatTile> {
  String _res = '';
  double _fps = 0.0;
  int _bpp = 0;
  String _cs = '';
  String _sub = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    void _bindString(String? src, ValueSetter<String> setter) {
      if (src == null) return;
      if (src.startsWith('/')) {
        final param = OscRegistry().getParam(src);
        if (param != null && param.currentValue.isNotEmpty)
          setState(() => setter(param.currentValue.first.toString()));
        OscRegistry().registerListener(src, (args) {
          final v = args.isNotEmpty ? args.first.toString() : '';
          if (!mounted) return;
          setState(() => setter(v));
        });
      } else {
        setState(() => setter(src));
      }
    }

    void _bindDouble(String? src, ValueSetter<double> setter) {
      if (src == null) return;
      if (src.startsWith('/')) {
        final param = OscRegistry().getParam(src);
        if (param != null && param.currentValue.isNotEmpty)
          setState(() => setter(double.tryParse(param.currentValue.first.toString()) ?? 0.0));
        OscRegistry().registerListener(src, (args) {
          final v = double.tryParse(args.isNotEmpty ? args.first.toString() : '') ?? 0.0;
          if (!mounted) return;
          setState(() => setter(v));
        });
      } else {
        setState(() => setter(double.tryParse(src) ?? 0.0));
      }
    }

    void _bindInt(String src, ValueSetter<int> setter) {
      if (src.startsWith('/')) {
        final param = OscRegistry().getParam(src);
        if (param != null && param.currentValue.isNotEmpty)
          setState(() => setter(int.tryParse(param.currentValue.first.toString()) ?? 0));
        OscRegistry().registerListener(src, (args) {
          final v = int.tryParse(args.isNotEmpty ? args.first.toString() : '') ?? 0;
          if (!mounted) return;
          setState(() => setter(v));
        });
      } else {
        setState(() => setter(int.tryParse(src) ?? 0));
      }
    }

    _bindString(widget.resolution, (v) => _res = v);
    _bindDouble(widget.framerate, (v) => _fps = v);
    _bindInt(widget.bitDepth, (v) => _bpp = v);
    _bindString(widget.colorSpace, (v) => _cs = v);
    _bindString(widget.chromaSubsampling, (v) => _sub = v);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(TileLayout.tileOuterMargin),
      color: Colors.grey[900],
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(widget.overlayLabel, style: kOverlayTextStyle),
          Padding(
            padding: EdgeInsets.all(TileLayout.sectionBoxPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.resolution != null)
                  Text(_res, style: _systemTextStyle),
                if (widget.framerate != null)
                  Text(_fps.toStringAsFixed(2), style: _systemTextStyle),
                Text('$_bpp bpp', style: _systemTextStyle),
                Row(
                  children: [
                    Text(_cs, style: _systemTextStyle),
                    if (widget.chromaSubsampling != null) ...[
                      const SizedBox(width: 8),
                      Text(_sub, style: _systemTextStyle),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps VideoFormatTile for each section
class AnalogSendTile extends StatelessWidget {
  final int index;
  const AnalogSendTile({Key? key, required this.index}) : super(key: key);

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
          colorSpace: '/analog_format/colourspace',
          chromaSubsampling: '4:4:4',
        ),
      ),
    );
  }
}

class ReturnTile extends StatelessWidget {
  const ReturnTile({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return VideoFormatTile(
      overlayLabel: 'R',
      resolution: '/return/resolution',
      framerate: '/return/framerate',
      bitDepth: '128',
      colorSpace: 'BLK',
      chromaSubsampling: '9:0:2',
    );
  }
}

class HDMIOutTile extends StatelessWidget {
  const HDMIOutTile({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return VideoFormatTile(
      overlayLabel: 'O',
      resolution: '/analog_format/resolution',
      framerate: '/analog_format/framerate',
      bitDepth: '12',
      colorSpace: 'RGB',
      chromaSubsampling: '4:4:4',
    );
  }
}

/// Input tiles: show large number behind content
class InputTile extends StatelessWidget {
  final int index;
  const InputTile({Key? key, required this.index}) : super(key: key);

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
  const _InputTileInner({Key? key, required this.index}) : super(key: key);

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
    final base = '/input/${widget.index}';
    for (var seg in [
      'connected',
      'resolution',
      'framerate',
      'bit_depth',
      'colorspace',
      'chroma_subsampling',
    ]) {
      OscRegistry().registerParam(
        '$base/$seg',
        seg == 'connected' ? [false] : [''],
      );
    }
    OscRegistry().registerListener('$base/connected', (args) {
      final v = args.isNotEmpty && args.first == true;
      if (v != _connected) setState(() => _connected = v);
    });
    OscRegistry().registerListener('$base/resolution', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _res) setState(() => _res = v);
    });
    OscRegistry().registerListener('$base/framerate', (args) {
      final parsed = double.tryParse(
            args.isNotEmpty ? args.first.toString() : '',
          ) ??
          0.0;
      if (parsed != _fps) setState(() => _fps = parsed);
    });
    OscRegistry().registerListener('$base/bit_depth', (args) {
      final parsed = int.tryParse(
            args.isNotEmpty ? args.first.toString() : '',
          ) ??
          0;
      if (parsed != _bpp) setState(() => _bpp = parsed);
    });
    OscRegistry().registerListener('$base/colorspace', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _cs) setState(() => _cs = v);
    });
    OscRegistry().registerListener('$base/chroma_subsampling', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _sub) setState(() => _sub = v);
    });
  }

  @override
  void dispose() {
    final base = '/input/${widget.index}';
    for (var seg in [
      'connected',
      'resolution',
      'framerate',
      'bit_depth',
      'colorspace',
      'chroma_subsampling',
    ]) {
      OscRegistry().unregisterListener('$base/$seg', (_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(TileLayout.tileOuterMargin),
      color: Colors.grey[900],
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(widget.index.toString(), style: kOverlayTextStyle),
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
    );
  }
}

/// SyncLock remains unchanged
class SyncLock extends StatelessWidget {
  const SyncLock({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const locked = true;
    return Icon(
      locked ? Icons.lock : Icons.lock_open,
      color: locked ? Colors.yellow : Colors.grey,
      size: 48,
    );
  }
}