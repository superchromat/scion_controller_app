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

  /// Text style for panel group titles (e.g. "Scale", "Horizontal Blur").
  static const TextStyle panelTitleStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: Color(0xFF888888),
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

  /// Returns the page-level gutter value.  Crashes if no [GridGutterProvider]
  /// is above [context] — prefer this over [maybeOf] for widgets that must
  /// live inside a grid-aware page.
  static double of(BuildContext context) {
    final g = maybeOf(context);
    assert(g != null, 'GridGutterProvider.of() called without a GridGutterProvider ancestor');
    return g!;
  }

  @override
  bool updateShouldNotify(GridGutterProvider old) => old.gutter != gutter;
}

/// Vertical spacer that derives its height from the page-level gutter [g].
///
/// Use between card rows in a page Column to get `g` vertical spacing,
/// or pass [fraction] for sub-gutter gaps (e.g. `0.5` for `g/2`).
class GridGap extends StatelessWidget {
  const GridGap({super.key, this.fraction = 1.0});

  /// Multiplier applied to the gutter value.  Defaults to 1.0 (full `g`).
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final g = GridGutterProvider.maybeOf(context) ?? 16.0;
    return SizedBox(height: g * fraction);
  }
}

/// A [Row] whose children are positioned on a column-span grid.
///
/// Each entry in [cells] carries a [span] (number of grid columns) and a
/// [child] widget.
///
/// **Math** — given total width W and gutter g:
///   colUnit  = (W + g) / columns
///   cellWidth = span × colUnit − g
///
/// This satisfies `Σ cellWidths + (n−1)×g = W` for any partition of columns.
///
/// When a [GridGutterProvider] ancestor exists the gutter is known without
/// measuring, so `LayoutBuilder` is avoided entirely.  This lets multi-cell
/// rows wrap their content in [IntrinsicHeight] so all cells stretch to the
/// tallest child's height — card bottoms align across the row.
///
/// Place a [GridGutterProvider] at the page level so all GridRows and
/// LabeledCards share the same `g`.
class GridRow extends StatelessWidget {
  const GridRow({
    super.key,
    this.columns = 12,
    this.gutter,
    required this.cells,
  });

  /// Total number of grid columns (default 12).
  final int columns;

  /// Total gap between adjacent cell contents.  When `null` (the default),
  /// read from [GridGutterProvider] or, as a last resort, computed as
  /// `width × [AppGrid.gutterFraction]` via [LayoutBuilder].
  final double? gutter;

  /// Ordered list of (span, child) pairs. Spans should sum to [columns].
  final List<({int span, Widget child})> cells;

  @override
  Widget build(BuildContext context) {
    final knownGutter = gutter ?? GridGutterProvider.maybeOf(context);

    // Fast path — gutter is known without measuring.  Avoids LayoutBuilder
    // so the subtree can participate in intrinsic-height queries (needed by
    // IntrinsicHeight for equal-height multi-cell rows).
    if (knownGutter != null) {
      return _buildWithGutter(knownGutter);
    }

    // Fallback — compute gutter from width.  LayoutBuilder prevents
    // IntrinsicHeight from working, but this path is only hit when there
    // is no GridGutterProvider ancestor (e.g. standalone usage).
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (!w.isFinite || w <= 0) return const SizedBox.shrink();
        return _buildWithGutter(w * AppGrid.gutterFraction);
      },
    );
  }

  Widget _buildWithGutter(double g) {
    final halfG = g / 2;

    // Single-cell row: combined row-margin + cell-padding (= g) on each side.
    if (cells.length == 1) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: g),
        child: cells[0].child,
      );
    }

    // Multi-cell row: Expanded with flex = span for proportional widths.
    // Wrapped in IntrinsicHeight so all cells stretch to the tallest
    // child's height — card bottoms align across the row.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: halfG),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final cell in cells)
              Expanded(
                flex: cell.span,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: halfG),
                  child: cell.child,
                ),
              ),
          ],
        ),
      ),
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
    // Grid overlay intentionally empty — toggle kShowGrid to disable.
    // Vertical column lines and horizontal rhythm lines were removed
    // because the fine-grained mesh was not useful for visual alignment.
  }

  @override
  bool shouldRepaint(covariant _GridOverlayPainter old) =>
      old.columns != columns || old.margin != margin || old.gutterOverride != gutterOverride;
}
