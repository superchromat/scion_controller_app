import 'package:flutter/material.dart';
import 'labeled_card.dart';
import 'system_overview_tiles.dart';
import 'arrow.dart';
import 'osc_registry.dart';

/// Centralized layout constants
class TileLayout {
  static const double marginPerTile = 8;
  static const double tileOuterMargin = 4;
  static const double sectionBoxPadding = 8;
  static const double cardPaddingTB = 0;
  static const double cardPaddingLR = 12;  // Match Analog Format's 12px left padding
  static const double lockColumnWidth = 60;
  static const double rowSpacing = 40;

  // Tile width calculated to make left section width ≈ 500px (matching Analog Format content)
  // Section width = 3*tileWidth + 3*marginPerTile + 2*(tileOuterMargin + sectionBoxPadding)
  //              = 3*tileWidth + 24 + 24 = 3*tileWidth + 48
  // For 500px: tileWidth = (500 - 48) / 3 = 150.67 ≈ 151
  static const double tileWidth = 151.0;
  static const double tileHeight = 100.0;  // Keep original height

  // Right offset to align tile center with Return Sync center (200px from card right edge)
  // Path from Row right edge to LabeledCard outer edge: cardPaddingLR + 24 (LabeledCard internal padding)
  // Tile center from Row right edge: rightOffset + sectionOverhead + tileWidth/2
  // where sectionOverhead = tileOuterMargin + sectionBoxPadding = 12
  // For tile center at 200px from LabeledCard outer edge:
  // rightOffset + 12 + tileWidth/2 + cardPaddingLR + 24 = 200
  // rightOffset = 164 - cardPaddingLR - tileWidth/2
  static double computeRightOffset() => 164 - cardPaddingLR - tileWidth / 2;

  static double totalHorizontalPaddingPerTile() =>
      2 * (tileOuterMargin + sectionBoxPadding);
}

enum LabelPosition { top, bottom }

class SystemOverview extends StatefulWidget {
  const SystemOverview({super.key});
  @override
  _SystemOverviewState createState() => _SystemOverviewState();
}

class _SystemOverviewState extends State<SystemOverview>
    with WidgetsBindingObserver {
  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _inputKeys = List.generate(3, (_) => GlobalKey());
  final List<GlobalKey> _sendKeys = List.generate(3, (_) => GlobalKey());
  final GlobalKey _returnKey = GlobalKey();
  final GlobalKey _outputKey = GlobalKey();

  List<Arrow> _arrows = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Listen for changes in mappings
    final registry = OscRegistry();
    for (var i = 1; i <= _sendKeys.length; i++) {
      final path = '/send/$i/input';
      registry.registerAddress(path);
      registry.registerListener(path, (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
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
      margin: EdgeInsets.all(TileLayout.tileOuterMargin),
      child: NeumorphicContainer(
        baseColor: const Color(0xFF323234),
        borderRadius: 6.0,
        elevation: 3.0,
        padding: EdgeInsets.all(TileLayout.sectionBoxPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: labelPosition == LabelPosition.top
              ? [label, const SizedBox(height: 4), child]
              : [child, const SizedBox(height: 4), Align(alignment: Alignment.centerLeft, child: label)],
        ),
      ),
    );
  }

  void _updateArrows() {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    const tileWidth = TileLayout.tileWidth;
    const tileHeight = TileLayout.tileHeight;
    final registry = OscRegistry();
    final List<Arrow> newArrows = [];

    void connect(GlobalKey fromKey, GlobalKey toKey, Offset fromOffset, Offset toOffset) {
      final fromBox = fromKey.currentContext?.findRenderObject() as RenderBox?;
      final toBox = toKey.currentContext?.findRenderObject() as RenderBox?;
      if (fromBox == null || toBox == null) return;
      final fromGlobal = fromBox.localToGlobal(fromOffset);
      final toGlobal = toBox.localToGlobal(toOffset);
      final fromLocal = box.globalToLocal(fromGlobal);
      final toLocal = box.globalToLocal(toGlobal);
      newArrows.add(Arrow(fromLocal, toLocal));
    }

    // dynamic input->send arrows based on registry values
    for (var i = 0; i < _sendKeys.length; i++) {
      final sendIdx = i + 1;
      final path = '/send/$sendIdx/input';
      final param = registry.allParams[path];
      if (param != null && param.currentValue.isNotEmpty) {
        final val = param.currentValue.first;
        final inIdx = val is int ? val : int.tryParse(val.toString()) ?? -1;
        if (inIdx >= 1 && inIdx <= _inputKeys.length) {
          connect(
            _inputKeys[inIdx - 1],
            _sendKeys[i],
            Offset(tileWidth / 2, tileHeight),
            Offset(tileWidth / 2, 0),
          );
        }
      }
    }

    // static return->output arrow
    connect(
      _returnKey,
      _outputKey,
      Offset(tileWidth / 2, 0),
      Offset(tileWidth / 2, tileHeight),
    );

    setState(() => _arrows = newArrows);
  }

  @override
  Widget build(BuildContext context) {
    return LabeledCard(
      networkIndependent: false,
      title: 'System Overview',
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          TileLayout.cardPaddingLR,
          TileLayout.cardPaddingTB,
          TileLayout.cardPaddingLR,
          TileLayout.cardPaddingTB,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const tileWidth = TileLayout.tileWidth;
            const tileHeight = TileLayout.tileHeight;
            Widget sizedTile(Widget tile, GlobalKey key) => SizedBox(
                  key: key,
                  width: tileWidth,
                  height: tileHeight,
                  child: tile,
                );
            return Stack(
              key: _stackKey,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _sectionBox(
                          title: 'HDMI Inputs',
                          labelPosition: LabelPosition.top,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              3,
                              (i) => Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: TileLayout.marginPerTile / 2),
                                child: sizedTile(
                                    InputTile(index: i + 1), _inputKeys[i]),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: TileLayout.lockColumnWidth),
                        const Spacer(),
                        _sectionBox(
                          title: 'HDMI Out',
                          labelPosition: LabelPosition.top,
                          child: sizedTile(const HDMIOutTile(), _outputKey),
                        ),
                        SizedBox(width: TileLayout.computeRightOffset()),
                      ],
                    ),
                    SizedBox(height: TileLayout.rowSpacing),
                    Row(
                      children: [
                        _sectionBox(
                          title: 'Analog Sends',
                          labelPosition: LabelPosition.bottom,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              3,
                              (i) => Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: TileLayout.marginPerTile / 2),
                                child: sizedTile(
                                    AnalogSendTile(index: i + 1), _sendKeys[i]),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: TileLayout.lockColumnWidth,
                          child: Center(child: const SyncLock()),
                        ),
                        const Spacer(),
                        _sectionBox(
                          title: 'Return',
                          labelPosition: LabelPosition.bottom,
                          child: sizedTile(const ReturnTile(), _returnKey),
                        ),
                        SizedBox(width: TileLayout.computeRightOffset()),
                      ],
                    ),
                  ],
                ),
                Positioned.fill(
                  child: CustomPaint(painter: ArrowsPainter(_arrows)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
