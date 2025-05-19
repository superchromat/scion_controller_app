import 'dart:math';
import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'labeled_card.dart';
import 'osc_text.dart';

enum LabelPosition { top, bottom }

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

class SystemOverview extends StatefulWidget {
  const SystemOverview({Key? key}) : super(key: key);

  @override
  _SystemOverviewState createState() => _SystemOverviewState();
}

class _SystemOverviewState extends State<SystemOverview> {
  static const double _lockColumnWidth = 60;

  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _inputKeys = List.generate(4, (_) => GlobalKey());
  final List<GlobalKey> _sendKeys = List.generate(4, (_) => GlobalKey());
  List<Arrow> _arrows = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  void _updateArrows() {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;

    final List<Arrow> newArrows = [];

    void connect(int fromIndex, int toIndex) {
      final fromBox = _inputKeys[fromIndex].currentContext?.findRenderObject()
          as RenderBox?;
      final toBox =
          _sendKeys[toIndex].currentContext?.findRenderObject() as RenderBox?;
      if (fromBox == null || toBox == null) return;

      final fromGlobal = fromBox.localToGlobal(
        Offset(fromBox.size.width / 2, fromBox.size.height),
      );
      final toGlobal = toBox.localToGlobal(
        Offset(toBox.size.width / 2, 0),
      );

      final fromLocal = stackBox.globalToLocal(fromGlobal);
      final toLocal = stackBox.globalToLocal(toGlobal);
      newArrows.add(Arrow(fromLocal, toLocal));
    }

    connect(0, 0);
    connect(1, 1);
    connect(1, 2);
    connect(2, 3);
    connect(2, 3);

    setState(() => _arrows = newArrows);
  }

  Widget _sectionBox({
    required String title,
    required Widget child,
    required LabelPosition labelPosition,
  }) {
    final label = Text(
      title,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    );
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[700]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: labelPosition == LabelPosition.top
            ? [label, const SizedBox(height: 4), child]
            : [
                child,
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: label)
              ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LabeledCard(
      title: 'System Overview',
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(builder: (context, constraints) {
          const double marginPerTile = 8;
          final double availableWidth = constraints.maxWidth - _lockColumnWidth;
          final double tileSize =
              (availableWidth - 5 * marginPerTile) / 5;

          Widget sizedTile(Widget tile, GlobalKey key) => SizedBox(
                key: key,
                width: tileSize,
                height: tileSize,
                child: tile,
              );

          return Stack(
            key: _stackKey,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top row
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: _sectionBox(
                          title: 'HDMI Inputs',
                          labelPosition: LabelPosition.top,
                          child: Row(
                            children: List.generate(
                              4,
                              (i) => sizedTile(
                                InputTile(index: i + 1),
                                _inputKeys[i],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: _lockColumnWidth),
                      Expanded(
                        flex: 1,
                        child: _sectionBox(
                          title: 'HDMI Out',
                          labelPosition: LabelPosition.top,
                          child: sizedTile(
                            const HdmiOutTile(),
                            GlobalKey(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),

                  // Bottom row
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: _sectionBox(
                          title: 'Analog Sends',
                          labelPosition: LabelPosition.bottom,
                          child: Row(
                            children: List.generate(
                              4,
                              (i) => sizedTile(
                                AnalogSendTile(index: i + 1),
                                _sendKeys[i],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: _lockColumnWidth,
                        child: Center(child: const SyncLock()),
                      ),
                      Expanded(
                        flex: 1,
                        child: _sectionBox(
                          title: 'Return',
                          labelPosition: LabelPosition.bottom,
                          child: sizedTile(
                            const ReturnTile(),
                            GlobalKey(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // arrows overlay
              Positioned.fill(
                child: CustomPaint(painter: _ArrowsPainter(_arrows)),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class Arrow {
  final Offset from, to;
  Arrow(this.from, this.to);
}

/// 1) Stateless wrapper that installs the “input” + “n” segments
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

/// 2) Inner StatefulWidget that manually hooks up its six listeners
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

    // 1) register defaults so they appear in the registry
    for (var seg in [
      'connected',
      'resolution',
      'framerate',
      'bit_depth',
      'colorspace',
      'chroma_subsampling',
    ]) {
      OscRegistry().registerParam('$base/$seg', seg == 'connected' ? [false] : ['']);
    }

    // 2) hook up listeners for each path
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
      margin: const EdgeInsets.all(4),
      color: Colors.grey[900],
      child: _connected
          ? Padding(
              padding: const EdgeInsets.all(8),
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
              child:
                  Text('Disconnected', style: _systemTextStyleRed),
            ),
    );
  }
}





class AnalogSendTile extends StatelessWidget {
  final int index;
  const AnalogSendTile({Key? key, required this.index}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'send',
      child: OscPathSegment(
        segment: index.toString(),
        child: Container(
          margin: const EdgeInsets.all(4),
          color: Colors.grey[900],
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text('10bit', style: _systemTextStyle),
                  Text('Custom 4:4:4', style: _systemTextStyle),
                ],
              ),
            ),
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
        margin: const EdgeInsets.all(4),
        color: Colors.grey[900],
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
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
        margin: const EdgeInsets.all(4),
        color: Colors.grey[900],
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
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

class _ArrowsPainter extends CustomPainter {
  final List<Arrow> arrows;
  _ArrowsPainter(this.arrows);

  Color? col = Colors.grey[400];

  @override
  void paint(Canvas canvas, Size size) {
    final shaftPaint = Paint()
      ..color = col!
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final headFillPaint = Paint()
      ..color = col!
      ..style = PaintingStyle.fill;
    final headStrokePaint = Paint()
      ..color = col!
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (final a in arrows) {
      final angle = (a.to - a.from).direction;
      const headLen = 12.0, headAngle = pi / 6;
      final p1 = a.to -
          Offset(
            headLen * cos(angle - headAngle),
            headLen * sin(angle - headAngle),
          );
      final p2 = a.to -
          Offset(
            headLen * cos(angle + headAngle),
            headLen * sin(angle + headAngle),
          );
      final baseCenter = Offset(
        (p1.dx + p2.dx) / 2,
        (p1.dy + p2.dy) / 2,
      );
      canvas.drawLine(a.from, baseCenter, shaftPaint);

      final path = Path()
        ..moveTo(a.to.dx, a.to.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      canvas.drawPath(path, headFillPaint);
      canvas.drawPath(path, headStrokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowsPainter old) =>
      old.arrows != arrows;
}
