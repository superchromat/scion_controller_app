import 'package:flutter/material.dart';
import 'dart:async';
import 'grid.dart';
import 'labeled_card.dart';
import 'system_overview_tiles.dart';
import 'arrow.dart';
import 'osc_registry.dart';

/// Centralized layout constants
class TileLayout {
  static const double marginPerTile = 8;
  static const double tileOuterMargin = 4;
  static const double sectionBoxPadding = 8;
  static const double lockColumnWidth = 60;
  static const double rowSpacing = 60;

  static const double tileWidth = 151.0;
  static const double tileHeight = 100.0;

  // Section box label dimensions
  static const double sectionLabelHeight = 16.0;
  static const double sectionLabelSpacing = 4.0;

  // Right offset to align tile center with Return Sync center (200px from card right edge)
  // Now LabeledCard has no inner horizontal padding; only contentPadding matters.
  // Tile center from Row right edge: rightOffset + sectionOverhead + tileWidth/2
  // where sectionOverhead = tileOuterMargin + sectionBoxPadding = 12
  static double computeRightOffset(double contentPadding) =>
      200 - 12 - tileWidth / 2 - contentPadding;

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
  final List<GlobalKey> _inputKeys = List.generate(4, (_) => GlobalKey());
  final List<GlobalKey> _sendKeys = List.generate(3, (_) => GlobalKey());
  final GlobalKey _returnKey = GlobalKey();
  final GlobalKey _outputKey = GlobalKey();

  List<Arrow> _arrows = [];
  Timer? _resizeArrowDebounce;

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
    _resizeArrowDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _resizeArrowDebounce?.cancel();
    _resizeArrowDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
    });
  }

  Widget _sectionBox({
    required String title,
    required Widget child,
    required LabelPosition labelPosition,
    Color? borderColor,
    bool alignLabelRight = false,
  }) {
    final label = Text(
      title,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    );
    return Padding(
      padding: EdgeInsets.all(TileLayout.tileOuterMargin),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          NeumorphicContainer(
            baseColor: borderColor != null
                ? Color.lerp(const Color(0xFF323234), borderColor, 0.07)!
                : const Color(0xFF323234),
            borderRadius: 6.0,
            elevation: 3.0,
            padding: EdgeInsets.all(TileLayout.sectionBoxPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: alignLabelRight
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: labelPosition == LabelPosition.top
                  ? [label, const SizedBox(height: 4), child]
                  : [child, const SizedBox(height: 4), label],
            ),
          ),
          if (borderColor != null)
            Positioned(
              left: 1, top: 1, right: 1, bottom: 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor.withOpacity(0.2), width: 1),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                ),
              ),
            ),
        ],
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

    void connect(GlobalKey fromKey, GlobalKey toKey, Offset fromOffset, Offset toOffset, {double arcUp = 0}) {
      final fromBox = fromKey.currentContext?.findRenderObject() as RenderBox?;
      final toBox = toKey.currentContext?.findRenderObject() as RenderBox?;
      if (fromBox == null || toBox == null) return;
      final fromGlobal = fromBox.localToGlobal(fromOffset);
      final toGlobal = toBox.localToGlobal(toOffset);
      final fromLocal = box.globalToLocal(fromGlobal);
      final toLocal = box.globalToLocal(toGlobal);
      newArrows.add(Arrow(fromLocal, toLocal, arcUp: arcUp));
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
        } else if (inIdx == 5) {
          connect(
            _returnKey,
            _sendKeys[i],
            Offset(tileWidth / 2, 0),
            Offset(tileWidth / 2, 0),
            arcUp: TileLayout.rowSpacing / 2,
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
    // Use the page-level gutter for internal content padding, matching the
    // old LabeledCard inner padding that the grid refactor removed.
    final g = GridGutterProvider.maybeOf(context) ?? 16.0;
    final contentPadding = g;

    return LabeledCard(
      networkIndependent: false,
      title: 'System Overview',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: contentPadding),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const tileWidth = TileLayout.tileWidth;
            const tileHeight = TileLayout.tileHeight;
            final rightOffset = TileLayout.computeRightOffset(contentPadding);
            // Clamp rightOffset so it never pushes content past the available width.
            const inputSectionMinWidth = 4 * (TileLayout.tileWidth + TileLayout.marginPerTile)
                + 2 * (TileLayout.tileOuterMargin + TileLayout.sectionBoxPadding);
            const rightColMinWidth = TileLayout.tileWidth
                + 2 * (TileLayout.tileOuterMargin + TileLayout.sectionBoxPadding);
            final safeRightOffset = (constraints.maxWidth
                    - inputSectionMinWidth
                    - TileLayout.lockColumnWidth
                    - rightColMinWidth)
                .clamp(0.0, rightOffset);
            Widget sizedTile(Widget tile, GlobalKey key) => SizedBox(
                  key: key,
                  width: tileWidth,
                  height: tileHeight,
                  child: tile,
                );
            return Stack(
              key: _stackKey,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sectionBox(
                          title: 'Inputs',
                          labelPosition: LabelPosition.top,
                          borderColor: Colors.white,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              4,
                              (i) => Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: TileLayout.marginPerTile / 2),
                                child: sizedTile(
                                    InputTile(index: i + 1), _inputKeys[i]),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: TileLayout.rowSpacing),
                        _sectionBox(
                          title: 'Sends',
                          labelPosition: LabelPosition.bottom,
                          borderColor: const Color(0xFFF8BA00),
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
                      ],
                    ),
                    SizedBox(width: TileLayout.lockColumnWidth),
                    const Spacer(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sectionBox(
                          title: 'Out',
                          labelPosition: LabelPosition.top,
                          borderColor: const Color(0xFF49A0F8),
                          alignLabelRight: true,
                          child: sizedTile(const HDMIOutTile(), _outputKey),
                        ),
                        SizedBox(height: TileLayout.rowSpacing),
                        _sectionBox(
                          title: 'Return',
                          labelPosition: LabelPosition.bottom,
                          borderColor: const Color(0xFF49A0F8),
                          alignLabelRight: true,
                          child: sizedTile(const ReturnTile(), _returnKey),
                        ),
                      ],
                    ),
                    SizedBox(width: safeRightOffset),
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
