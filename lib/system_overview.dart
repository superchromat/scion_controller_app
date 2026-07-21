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
    double? contentInset,
    bool hugRight = false,
  }) {
    // The lead of the first tile inside the shaded box: the Row's half-gap plus
    // the tile's own outer margin. Adding this to the label makes the label and
    // the first tile share one left edge.
    const double leadPad =
        TileLayout.marginPerTile / 2 + TileLayout.tileOuterMargin;

    // When [contentInset] is set (the left Inputs/Sends column), the shaded box
    // HUGS the card's content origin — its left edge lands on the same vertical
    // as the grey L-box in the card below — while the label and first tile are
    // inset to [contentInset], the content edge that the card title sits on.
    final bool hug = contentInset != null;

    // A metric smidge, so the label reads as sitting just inside the tiles'
    // left edge rather than dead-flush with it.
    const double labelNudge = 3.0;

    final Widget label = Padding(
      padding: EdgeInsets.only(left: hug ? leadPad + labelNudge : 0),
      child: Text(
        title,
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );

    // Drop the outer margin on whichever side hugs a card edge, so the shaded
    // box's edge lands exactly on the content edge / grey-box line: left for the
    // Inputs/Sends column, right for the Out/Return column.
    final EdgeInsets outerPad = EdgeInsets.fromLTRB(
      hug ? 0 : TileLayout.tileOuterMargin,
      TileLayout.tileOuterMargin,
      hugRight ? 0 : TileLayout.tileOuterMargin,
      TileLayout.tileOuterMargin,
    );

    // Left inset lands the tiles on [contentInset]; the label's own [leadPad]
    // lands it there too. Clamp so a very narrow window can't go negative.
    final EdgeInsets innerPad = hug
        ? EdgeInsets.fromLTRB(
            (contentInset - leadPad).clamp(0.0, double.infinity),
            TileLayout.sectionBoxPadding,
            TileLayout.sectionBoxPadding,
            TileLayout.sectionBoxPadding)
        : EdgeInsets.all(TileLayout.sectionBoxPadding);

    return Padding(
      padding: outerPad,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          NeumorphicContainer(
            baseColor: borderColor != null
                ? Color.lerp(const Color(0xFF323234), borderColor, 0.07)!
                : const Color(0xFF323234),
            borderRadius: 6.0,
            elevation: 3.0,
            padding: innerPad,
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
              left: 1,
              top: 1,
              right: 1,
              bottom: 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: borderColor.withOpacity(0.2), width: 1),
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
    final registry = OscRegistry();
    final List<Arrow> newArrows = [];

    // Anchors are FRACTIONS of each tile, not pixels: the tiles flex to fill
    // the card, so their width is not known here.
    void connect(
        GlobalKey fromKey, GlobalKey toKey, Offset fromFrac, Offset toFrac,
        {double arcUp = 0}) {
      final fromBox = fromKey.currentContext?.findRenderObject() as RenderBox?;
      final toBox = toKey.currentContext?.findRenderObject() as RenderBox?;
      if (fromBox == null || toBox == null) return;
      final fromOffset = Offset(
          fromBox.size.width * fromFrac.dx, fromBox.size.height * fromFrac.dy);
      final toOffset =
          Offset(toBox.size.width * toFrac.dx, toBox.size.height * toFrac.dy);
      final fromGlobal = fromBox.localToGlobal(fromOffset);
      final toGlobal = toBox.localToGlobal(toOffset);
      final fromLocal = box.globalToLocal(fromGlobal);
      final toLocal = box.globalToLocal(toGlobal);
      newArrows.add(Arrow(fromLocal, toLocal, arcUp: arcUp));
    }

    // dynamic input->send arrows based on registry values. When no device has
    // supplied a routing (e.g. demo mode), default each send to the matching
    // input so the cables still show.
    for (var i = 0; i < _sendKeys.length; i++) {
      final sendIdx = i + 1;
      final path = '/send/$sendIdx/input';
      final param = registry.allParams[path];
      final int inIdx;
      if (param != null && param.currentValue.isNotEmpty) {
        final val = param.currentValue.first;
        inIdx = val is int ? val : int.tryParse(val.toString()) ?? -1;
      } else {
        inIdx = sendIdx; // demo / no device: identity routing.
      }
      if (inIdx >= 1 && inIdx <= _inputKeys.length) {
        connect(
          _inputKeys[inIdx - 1],
          _sendKeys[i],
          const Offset(0.5, 1),
          const Offset(0.5, 0),
        );
      } else if (inIdx == 5) {
        connect(
          _returnKey,
          _sendKeys[i],
          const Offset(0.5, 0),
          const Offset(0.5, 0),
          arcUp: TileLayout.rowSpacing / 2,
        );
      }
    }

    // static return->output arrow
    connect(
      _returnKey,
      _outputKey,
      const Offset(0.5, 0),
      const Offset(0.5, 1),
    );

    setState(() => _arrows = newArrows);
  }

  @override
  Widget build(BuildContext context) {
    // Use the page-level gutter for internal content padding, matching the
    // old LabeledCard inner padding that the grid refactor removed.
    // Must equal the card-title inset, or the tiles sit left of the title.
    // computeRightOffset() takes the same value, so the tile maths stays
    // consistent with whatever this is.
    final contentPadding = GridProvider.of(context).cardBodyInset;

    return LabeledCard(
      networkIndependent: false,
      title: 'System Overview',
      // Right inset only: the diagram's LEFT edge sits on the card's content
      // origin (one [contentPadding] left of the title) so the Inputs/Sends
      // shaded boxes line up with the grey L-box in the card below — which uses
      // this same right-only pattern — and its RIGHT edge sits on the right
      // content edge so the Out/Return box (hugRight) lines up with the grey box
      // in the Return Sync card below. Both boxes then inset their own labels and
      // tiles back to the content edge.
      child: Padding(
        padding: EdgeInsets.only(right: contentPadding),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const tileWidth = TileLayout.tileWidth;
            const tileHeight = TileLayout.tileHeight;
            final rightOffset = TileLayout.computeRightOffset(contentPadding);
            // Clamp rightOffset so it never pushes content past the available width.
            const inputSectionMinWidth = 4 *
                    (TileLayout.tileWidth + TileLayout.marginPerTile) +
                2 * (TileLayout.tileOuterMargin + TileLayout.sectionBoxPadding);
            const rightColMinWidth = TileLayout.tileWidth +
                2 * (TileLayout.tileOuterMargin + TileLayout.sectionBoxPadding);
            // The diagram is built from fixed-size tiles, so below this width
            // it cannot fit — no amount of clamping helps, and it used to just
            // overflow (the yellow stripe). Lay it out at its natural width and
            // let the FittedBox below scale the whole schematic down instead.
            const minDiagramWidth = inputSectionMinWidth +
                TileLayout.lockColumnWidth +
                rightColMinWidth;
            final diagramWidth = constraints.maxWidth > minDiagramWidth
                ? constraints.maxWidth
                : minDiagramWidth;
            // Grow every tile so the four Inputs span the width left of the
            // Out/Return column. Fixed 151px tiles left a large dead zone in
            // the middle of the card on any reasonably wide window.
            final slackForInputs = diagramWidth -
                TileLayout.lockColumnWidth -
                rightColMinWidth -
                rightOffset -
                2 * (TileLayout.tileOuterMargin + TileLayout.sectionBoxPadding);
            final tileW = (slackForInputs / 4 - TileLayout.marginPerTile)
                .clamp(TileLayout.tileWidth, 2.2 * TileLayout.tileWidth);

            // Width defaults to the computed [tileW] so Inputs/Sends stretch
            // across the card; the Out/Return column passes the fixed width so
            // it stays put over the Return Sync card below.
            Widget sizedTile(Widget tile, GlobalKey key, {double? width}) =>
                SizedBox(
                  key: key,
                  width: width ?? tileW,
                  height: tileHeight,
                  child: tile,
                );
            // Only scale when the diagram genuinely cannot fit. Wrapping
            // unconditionally meant any width mistake silently shrank the whole
            // schematic instead of reporting an overflow.
            final needsScaling = constraints.maxWidth < minDiagramWidth;
            Widget wrap(Widget d) => needsScaling
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: d)
                : d;
            return wrap(
              SizedBox(
                width: diagramWidth,
                child: Stack(
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
                              contentInset: contentPadding,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  4,
                                  (i) => Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal:
                                            TileLayout.marginPerTile / 2),
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
                              contentInset: contentPadding,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  3,
                                  (i) => Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal:
                                            TileLayout.marginPerTile / 2),
                                    child: sizedTile(
                                        AnalogSendTile(index: i + 1),
                                        _sendKeys[i]),
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
                              hugRight: true,
                              child: sizedTile(const HDMIOutTile(), _outputKey,
                                  width: tileWidth),
                            ),
                            SizedBox(height: TileLayout.rowSpacing),
                            _sectionBox(
                              title: 'Return',
                              labelPosition: LabelPosition.bottom,
                              borderColor: const Color(0xFF49A0F8),
                              alignLabelRight: true,
                              hugRight: true,
                              child: sizedTile(const ReturnTile(), _returnKey,
                                  width: tileWidth),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Decorative arrow overlay — must never absorb pointer events,
                    // or the (now-interactive) input tiles below it can't be tapped.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: ArrowsPainter(_arrows)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
