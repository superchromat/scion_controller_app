// grid.dart — Shared layout tokens, grid row widget, and debug overlay.

import 'package:flutter/material.dart';

/// Set true to render the 12-column guide overlay on the send page.
const bool kShowGrid = true;

/// Layout tokens shared across all send-page sections.
///
/// These replace the scattered local `_dialSize`, `_knobGap`, etc. constants
/// that were duplicated in shape.dart, send_texture.dart, and send_text.dart.
abstract class AppGrid {
  /// Gutter as a fraction of the row width. Both [GridRow] and [GridOverlay]
  /// use this when no explicit gutter is given, so the spacing scales with
  /// the window.  ~16 px at 1200 px content width.
  static const double gutterFraction = 0.013;

  /// Gap between sibling panels inside a section (NeumorphicInset rows).
  static const double gutter = 8.0;

  /// Standard padding inside a NeumorphicInset panel.
  static const EdgeInsets panelPadding = EdgeInsets.fromLTRB(6, 6, 6, 4);

  /// Standard knob diameter for compact sections (Shape, Texture, Text).
  static const double knobSize = 50.0;

  /// Larger knob diameter for spacious sections (Color global row).
  static const double largeKnobSize = 70.0;

  /// Horizontal gap between adjacent knobs inside a panel.
  static const double knobGap = 12.0;

  /// Small icon size used as row labels alongside knobs.
  static const double iconSize = 14.0;

  /// Icon color used as row labels alongside knobs.
  static const Color iconColor = Color(0xFF888888);

  /// Text style applied to knob labels.
  static const TextStyle knobLabelStyle = TextStyle(
    fontSize: 11,
    color: Color(0xFF999999),
  );
}

/// Provides a computed gutter value to all descendant [GridRow] widgets.
///
/// Place at the page level so every GridRow — top-level or nested inside
/// cards — uses the same absolute gutter.  Without this, each GridRow
/// computes its own proportional gutter from its local width, producing
/// inconsistent spacing at different nesting depths.
class GridGutterProvider extends InheritedWidget {
  final double gutter;

  const GridGutterProvider({
    super.key,
    required this.gutter,
    required super.child,
  });

  static double? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GridGutterProvider>()?.gutter;
  }

  @override
  bool updateShouldNotify(GridGutterProvider old) => old.gutter != gutter;
}

/// A [Row] whose children are positioned on a column-span grid.
///
/// Each entry in [cells] carries a [span] (number of grid columns) and a
/// [child] widget. Cell widths are computed from [LayoutBuilder] so the row
/// is fully responsive to its parent width.
///
/// **Math** — given total width W and gutter g:
///   colUnit  = (W + g) / columns
///   cellWidth = span × colUnit − g
///
/// This satisfies `Σ cellWidths + (n−1)×g = W` for any partition of columns.
///
/// **Gutter with [LabeledCard] children** — pass the same gutter value used
/// by [GridOverlay] (default 16) and set [LabeledCard.outerPadding] to
/// `EdgeInsets.symmetric(vertical: 8)` so that card edges land on grid rules.
class GridRow extends StatelessWidget {
  const GridRow({
    super.key,
    this.columns = 12,
    this.gutter,
    required this.cells,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  /// Total number of grid columns (default 12).
  final int columns;

  /// Total gap between adjacent cell contents.  When `null` (the default),
  /// computed as `width × [AppGrid.gutterFraction]` so it scales with the
  /// window.  Distributed as half-gutter padding inside each cell — content
  /// is centred within its column span and grid lines fall at cell boundaries.
  final double? gutter;

  /// Ordered list of (span, child) pairs. Spans should sum to [columns].
  final List<({int span, Widget child})> cells;

  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    // Read the page-level gutter BEFORE entering LayoutBuilder so that
    // nested GridRows inside cards use the same absolute spacing as the
    // top-level grid.
    final inheritedGutter = GridGutterProvider.maybeOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (!w.isFinite || w <= 0) return const SizedBox.shrink();
        final g = gutter ?? inheritedGutter ?? w * AppGrid.gutterFraction;
        final halfG = g / 2;
        final colUnit = (w - g) / columns;

        // Single-cell row: no Row/IntrinsicHeight needed.  Just apply
        // the combined row-margin + cell-padding (= g) on each side.
        if (cells.length == 1) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: g),
            child: cells[0].child,
          );
        }

        // Multi-cell row: SizedBox per cell with half-gutter padding.
        final List<Widget> children = [];
        for (var i = 0; i < cells.length; i++) {
          children.add(SizedBox(
            width: cells[i].span * colUnit,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: halfG),
              child: cells[i].child,
            ),
          ));
        }

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: halfG),
          child: Row(
            crossAxisAlignment: crossAxisAlignment,
            children: children,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid overlay
// ─────────────────────────────────────────────────────────────────────────────

/// Debug overlay that draws column guides over the send page.
///
/// Uses the same column-unit formula as [GridRow]:
///   colUnit = (W − 2·margin + gutter) / columns
///
/// **Major rules** (thick, bright) are drawn every [majorEvery] columns —
/// these mark cell boundaries in the Shape/Texture/Text 4-4-4 row.
/// **Minor rules** (thin, faint) mark sub-column positions.
/// No fills — just lines, so the overlay stays readable.
///
/// Place as the last child of a [Stack] wrapped in [Positioned.fill].
/// [IgnorePointer] is applied internally. Toggle with [kShowGrid].
class GridOverlay extends StatelessWidget {
  const GridOverlay({
    super.key,
    this.columns = 12,
    this.margin = 0.0,
  });

  final int columns;
  final double margin;

  @override
  Widget build(BuildContext context) {
    final inheritedGutter = GridGutterProvider.maybeOf(context);
    return IgnorePointer(
      child: CustomPaint(
        painter: _GridOverlayPainter(
          columns: columns,
          margin: margin,
          gutterOverride: inheritedGutter,
        ),
      ),
    );
  }
}

class _GridOverlayPainter extends CustomPainter {
  const _GridOverlayPainter({
    required this.columns,
    required this.margin,
    this.gutterOverride,
  });

  final int columns;
  final double margin;
  final double? gutterOverride;

  @override
  void paint(Canvas canvas, Size size) {
    final g = gutterOverride ?? size.width * AppGrid.gutterFraction;
    final halfG = g / 2;
    final colUnit = (size.width - g) / columns;

    final paint = Paint()
      ..color = const Color(0x994FC3F7)
      ..strokeWidth = 1.0;

    for (var i = 0; i <= columns; i++) {
      final x = halfG + i * colUnit;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridOverlayPainter old) =>
      old.columns != columns || old.margin != margin || old.gutterOverride != gutterOverride;
}
