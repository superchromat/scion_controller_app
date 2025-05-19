import 'dart:math';
import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';   // for OscPathSegment & OscAddressMixin
import 'labeled_card.dart';        // for LabeledCard

enum LabelPosition { top, bottom }

class SystemOverview extends StatefulWidget {
  const SystemOverview({Key? key}) : super(key: key);

  @override
  _SystemOverviewState createState() => _SystemOverviewState();
}

class _SystemOverviewState extends State<SystemOverview> {
  static const double _lockColumnWidth = 60;

  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _inputKeys = List.generate(4, (_) => GlobalKey());
  final List<GlobalKey> _sendKeys  = List.generate(4, (_) => GlobalKey());
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
      final fromBox = _inputKeys[fromIndex].currentContext?.findRenderObject() as RenderBox?;
      final toBox   = _sendKeys[toIndex].currentContext?.findRenderObject() as RenderBox?;
      if (fromBox == null || toBox == null) return;

      // bottom-center of the input tile
      final fromGlobal = fromBox.localToGlobal(
        Offset(fromBox.size.width / 2, fromBox.size.height),
      );
      // top-center of the send tile
      final toGlobal = toBox.localToGlobal(
        Offset(toBox.size.width / 2, 0),
      );

      final fromLocal = stackBox.globalToLocal(fromGlobal);
      final toLocal   = stackBox.globalToLocal(toGlobal);
      newArrows.add(Arrow(fromLocal, toLocal));
    }

    // your connections:
    connect(0, 0);
    connect(1, 1);
    connect(1, 2);
    connect(2, 2);
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
            : [child, const SizedBox(height: 4), Align(alignment: Alignment.centerLeft, child: label)],
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
          const double marginPerTile = 8; // 4px left + 4px right
          final double availableWidth = constraints.maxWidth - _lockColumnWidth;
          final double tileSize = (availableWidth - 5 * marginPerTile) / 5;

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
                              (i) => sizedTile(InputTile(index: i + 1), _inputKeys[i]),
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
                          child: sizedTile(const HdmiOutTile(), GlobalKey()),
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
                              (i) => sizedTile(AnalogSendTile(index: i + 1), _sendKeys[i]),
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
                          child: sizedTile(const ReturnTile(), GlobalKey()),
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

class _ArrowsPainter extends CustomPainter {
  final List<Arrow> arrows;
  _ArrowsPainter(this.arrows);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4; 

    for (final a in arrows) {
      canvas.drawLine(a.from, a.to, paint);

      final angle = (a.to - a.from).direction;
      const headLen = 12.0, headAngle = pi / 6;
      final p1 = a.to - Offset(headLen * cos(angle - headAngle), headLen * sin(angle - headAngle));
      final p2 = a.to - Offset(headLen * cos(angle + headAngle), headLen * sin(angle + headAngle));
      canvas.drawLine(a.to, p1, paint);
      canvas.drawLine(a.to, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowsPainter old) => old.arrows != arrows;
}

// ----------------------------------------------------------------------------
// Tile stubs below.  Replace "Fixme" and static text with your OSC watch/getValue.
// ----------------------------------------------------------------------------

class InputTile extends StatelessWidget {
  final int index;
  const InputTile({Key? key, required this.index}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'input',
      child: OscPathSegment(
        segment: index.toString(),
        child: Container(
          margin: const EdgeInsets.all(4),
          color: Colors.grey[900],
          child: Stack(
            children: [
              Center(
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 96,
                    color: Colors.white.withOpacity(0.2),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Fixme',
                    style: TextStyle(color: Colors.green, fontFamily: 'Courier', fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
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
          child: Stack(
            children: [
              Center(
                child: Text(
                  '$index',
                  style: TextStyle(fontSize: 96, color: Colors.white.withOpacity(0.2), fontWeight: FontWeight.bold),
                ),
              ),
              const Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('10bit', style: TextStyle(color: Colors.green, fontFamily: 'Courier', fontSize: 12)),
                      Text('Custom 4:4:4', style: TextStyle(color: Colors.green, fontFamily: 'Courier', fontSize: 12)),
                    ],
                  ),
                ),
              ),
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
        margin: const EdgeInsets.all(4),
        color: Colors.grey[900],
        child: Stack(
          children: [
            Center(
              child: Text(
                'R',
                style: TextStyle(fontSize: 96, color: Colors.white.withOpacity(0.2), fontWeight: FontWeight.bold),
              ),
            ),
            const Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('1920x1080', style: TextStyle(color: Colors.green, fontFamily: 'Courier', fontSize: 12)),
                    Text('66fps',      style: TextStyle(color: Colors.green, fontFamily: 'Courier', fontSize: 12)),
                    Text('128bit',     style: TextStyle(color: Colors.green, fontFamily: 'Courier', fontSize: 12)),
                    Text('BLK 9:0:2',  style: TextStyle(color: Colors.green, fontFamily: 'Courier', fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
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
        child: Stack(
          children: [
            Center(
              child: Text(
                'O',
                style: TextStyle(fontSize: 96, color: Colors.white.withOpacity(0.2), fontWeight: FontWeight.bold),
              ),
            ),
            const Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('12bit',    style: TextStyle(color: Colors.green, fontFamily: 'Courier', fontSize: 12)),
                    Text('RGB 4:4:4',style: TextStyle(color: Colors.green, fontFamily: 'Courier', fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
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
    return Icon(locked ? Icons.lock : Icons.lock_open, color: locked ? Colors.yellow : Colors.grey, size: 48);
  }
}
