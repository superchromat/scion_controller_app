// system_overview_tiles.dart

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
  String _res = '', _fps = '', _bpp = '', _cs = '', _sub = '';

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
      OscRegistry()
          .registerParam('$base/$seg', seg == 'connected' ? [false] : ['']);
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
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _fps) setState(() => _fps = v);
    });
    OscRegistry().registerListener('$base/bit_depth', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _bpp) setState(() => _bpp = v);
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
      child: _connected
          ? Padding(
              padding:
                  EdgeInsets.all(TileLayout.sectionBoxPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_res, style: _systemTextStyle),
                  Text(_fps, style: _systemTextStyle),
                  Text('$_bpp bpp', style: _systemTextStyle),
                  Row(children: [
                    Text(_cs, style: _systemTextStyle),
                    const SizedBox(width: 8),
                    Text(_sub, style: _systemTextStyle),
                  ]),
                ],
              ),
            )
          : Center(
              child: Text(
                'Disconnected',
                style: _systemTextStyleRed,
              ),
            ),
    );
  }
}

class AnalogSendTile extends StatelessWidget {
  final int index;
  const AnalogSendTile({Key? key, required this.index})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'input',
      child: OscPathSegment(
        segment: index.toString(),
        child: _AnalogSendTileInner(index: index),
      ),
    );
  }
}

class _AnalogSendTileInner extends StatefulWidget {
  final int index;
  const _AnalogSendTileInner({Key? key, required this.index})
      : super(key: key);

  @override
  __AnalogSendTileInnerState createState() =>
      __AnalogSendTileInnerState();
}

class __AnalogSendTileInnerState
    extends State<_AnalogSendTileInner> {
  String _res = '', _fps = '', _bpp = '10', _cs = '', _sub = '4:4:4';
  final base = '/analog_format';

  @override
  void dispose() {
    for (var seg in [
      'resolution',
      'framerate',
      'colorspace',
    ]) {
      OscRegistry().unregisterListener('$base/$seg', (_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    OscRegistry().registerListener('$base/resolution', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _res) setState(() => _res = v);
    });
    OscRegistry().registerListener('$base/framerate', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _fps) setState(() => _fps = v);
    });
    OscRegistry().registerListener('$base/colourspace', (args) {
      final v = args.isNotEmpty ? args.first.toString() : '';
      if (v != _cs) setState(() => _cs = v);
    });

    return Container(
      margin: EdgeInsets.all(TileLayout.tileOuterMargin),
      color: Colors.grey[900],
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding:
              EdgeInsets.all(TileLayout.sectionBoxPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_res, style: _systemTextStyle),
              Text(_fps, style: _systemTextStyle),
              Text('$_bpp bpp', style: _systemTextStyle),
              Row(children: [
                Text(_cs, style: _systemTextStyle),
                const SizedBox(width: 8),
                Text(_sub, style: _systemTextStyle),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class ReturnTile extends StatelessWidget {
  const ReturnTile({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'return',
      child: Container(
        margin: EdgeInsets.all(TileLayout.tileOuterMargin),
        color: Colors.grey[900],
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding:
                EdgeInsets.all(TileLayout.sectionBoxPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1920x1080', style: _systemTextStyle),
                Text('66fps', style: _systemTextStyle),
                Text('128bit', style: _systemTextStyle),
                Text('BLK 9:0:2', style: _systemTextStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HdmiOutTile extends StatelessWidget {
  const HdmiOutTile({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'output',
      child: Container(
        margin: EdgeInsets.all(TileLayout.tileOuterMargin),
        color: Colors.grey[900],
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding:
                EdgeInsets.all(TileLayout.sectionBoxPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('12bit', style: _systemTextStyle),
                Text('RGB 4:4:4', style: _systemTextStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
