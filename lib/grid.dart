// grid.dart — Shared layout tokens, grid row widget, and debug overlay.

import 'package:flutter/material.dart';

/// Set true to render the 12-column guide overlay on the send page.
const bool kShowGrid = false;

// ─────────────────────────────────────────────────────────────────────────────
// Grid tokens — all layout values derived from a single base unit `u`
// ─────────────────────────────────────────────────────────────────────────────

/// All spacing, sizing, and typography values derived from viewport width.
///
/// Compute once at the page level and provide via [GridProvider].
class GridTokens {
  GridTokens(double contentWidth) : u = (contentWidth * 0.01).clamp(6.0, 20.0);

  /// Base unit — everything else derives from this.
  final double u;

  // Spacing
  double get xs => 0.5 * u;
  double get sm => u;
  double get md => 1.5 * u;
  double get lg => 2.0 * u;

  // Knob diameters
  double get knobSm => 4 * u;
  double get knobMd => 5.5 * u;
  double get knobLg => 7 * u;

  // ── Typography ─────────────────────────────────────────────────────────────
  //
  // TWO weights and FOUR sizes. That is the whole type system; there is no
  // fifth size and no third weight. Before this there were 8 weights (only 4 of
  // which DIN Pro actually ships — the rest were synthesised) and 13 hardcoded
  // pixel sizes scattered across 36 files.
  //
  // Weights:  regular (400) for everything, bold (700) for emphasis.
  // Sizes:    title 2.0u · heading 1.4u · body 1.1u · caption 0.9u
  //
  // Sizes are multiples of `u` so type scales with the window. Never write a
  // literal fontSize outside this block — use a token, or copyWith() a token if
  // you need a different colour or weight.

  static const String _family = 'DINPro';
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight bold = FontWeight.w700;

  /// DIN Pro's digits are tabular, but state it explicitly so live readouts
  /// cannot jitter if the family is ever swapped.
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// Card titles.
  TextStyle get textTitle => TextStyle(
        fontSize: 2.0 * u,
        fontWeight: regular,
        fontFamily: _family,
        letterSpacing: 0.15,
        color: Colors.white,
        fontFeatures: _tabular,
      );

  /// Panel titles — the one step between a card title and body text.
  TextStyle get textHeading => TextStyle(
        fontSize: 1.4 * u,
        fontWeight: regular,
        fontFamily: _family,
        letterSpacing: 0.1,
        color: Colors.white,
        fontFeatures: _tabular,
      );

  /// Control labels, values and running prose all share one size. They differ
  /// by colour and weight, which is enough hierarchy and keeps the scale short.
  TextStyle get textLabel => TextStyle(
        fontSize: 1.1 * u,
        fontWeight: regular,
        fontFamily: _family,
        letterSpacing: 0.05,
        color: const Color(0xFFD2D2D4),
        fontFeatures: _tabular,
      );

  /// A value readout: same size as [textLabel], brighter.
  TextStyle get textValue =>
      textLabel.copyWith(color: const Color(0xFFF2F2F2));

  /// Running prose: same size as [textLabel], with room to breathe between
  /// lines because it is read line by line rather than at a glance.
  TextStyle get textBody =>
      textLabel.copyWith(height: 1.45, color: const Color(0xFFC8C8CE));

  /// Units and meta labels. The smallest type in the app.
  TextStyle get textCaption => TextStyle(
        fontSize: 0.9 * u,
        fontWeight: regular,
        fontFamily: _family,
        letterSpacing: 0.1,
        color: const Color(0xFFACACB2),
        fontFeatures: _tabular,
      );

  // Composite padding

  /// Outer margin around a page's content, equal on all four sides.
  EdgeInsets get pagePadding => EdgeInsets.all(2 * md);

  EdgeInsets get panelPadding => EdgeInsets.all(xs);
  EdgeInsets get cardPadding => EdgeInsets.all(md);

  /// Extra left inset applied inside inset panels, beyond [panelPadding].
  double get panelTitleInsetLeft => xs;

  // ── The content edge ───────────────────────────────────────────────────────
  //
  // Everything in a card lines up on ONE vertical edge: the card title, each
  // panel's title, and the controls inside those panels. The two getters below
  // are the only definitions of where that edge is; [Panel] and [LabeledCard]
  // derive from them rather than computing their own insets, and leaf controls
  // (knobs, dropdowns, checkboxes) must add NO left padding of their own.
  //
  // Enforced by test/panel_alignment_test.dart, which measures real controls.
  // It was written after this edge drifted three separate ways at once.

  /// Where a panel's content starts, measured from the panel's left edge.
  /// [Panel] applies exactly this as its left padding, for title and body alike.
  double get panelContentInset => panelPadding.left + panelTitleInsetLeft;

  /// Deprecated alias — the panel title sits on the content edge like everything
  /// else, so there is no separate "title offset" any more.
  double get panelTitleTextOffsetInPanel => panelContentInset;

  /// Card-title left inset that lines the card title up with the *panel* titles
  /// inside it, for the standard card content grid.
  ///
  /// Assumes card internals use [GridRow] with gutter [md], which is the
  /// standard pattern across Send-page sections.
  ///
  /// [GridRow] insets its outer edge by a FULL gutter, not half: a single-cell
  /// row pads by `g`, and a multi-cell row pads by `g/2` on the row plus `g/2`
  /// on each cell — `g` either way. This previously used `md / 2`, which left
  /// every card title sitting `md / 2` to the left of its panels' titles.
  double get cardTitleAlignToPanelTitle => md + panelContentInset;

  /// Left inset for card content that is NOT a [GridRow] of [Panel]s — plain
  /// text or bare buttons sitting straight in a card. Use [CardBody] rather
  /// than applying this by hand; hand-application is what put the About and
  /// Configuration cards' contents flush against the card edge.
  double get cardBodyInset => panelContentInset;
}

/// Provides [GridTokens] to all descendants.
class GridProvider extends InheritedWidget {
  final GridTokens tokens;

  const GridProvider({
    super.key,
    required this.tokens,
    required super.child,
  });

  /// Returns tokens from the nearest [GridProvider], or a fallback computed
  /// from [defaultWidth] if no provider exists.  This allows widgets to be
  /// used on pages that haven't been migrated to [GridProvider] yet.
  static GridTokens of(BuildContext context, {double defaultWidth = 1200}) {
    return maybeOf(context) ?? GridTokens(defaultWidth);
  }

  static GridTokens? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GridProvider>()?.tokens;
  }

  @override
  bool updateShouldNotify(GridProvider old) => old.tokens.u != tokens.u;
}

// ─────────────────────────────────────────────────────────────────────────────
// Legacy grid constants (kept for backward compat during migration)
// ─────────────────────────────────────────────────────────────────────────────

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
    fontWeight: FontWeight.w700,
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
    return context
        .dependOnInheritedWidgetOfExactType<GridGutterProvider>()
        ?.gutter;
  }

  /// Returns the page-level gutter value.  Crashes if no [GridGutterProvider]
  /// is above [context] — prefer this over [maybeOf] for widgets that must
  /// live inside a grid-aware page.
  static double of(BuildContext context) {
    final g = maybeOf(context);
    assert(g != null,
        'GridGutterProvider.of() called without a GridGutterProvider ancestor');
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
    this.equalHeight = true,
    this.outerInset,
    required this.cells,
  });

  /// Total number of grid columns (default 12).
  final int columns;

  /// Total gap between adjacent cell contents.  When `null` (the default),
  /// read from [GridGutterProvider] or, as a last resort, computed as
  /// `width × [AppGrid.gutterFraction]` via [LayoutBuilder].
  final double? gutter;

  /// When true, multi-cell rows stretch all cells to the tallest child.
  ///
  /// Some rows (e.g. asymmetric dashboard cards) should keep natural heights.
  final bool equalHeight;

  /// Horizontal inset at the row's two outer edges. Defaults to ZERO.
  ///
  /// A GridRow divides columns; it does not invent margins. Whoever places the
  /// row owns the margin — a page via [GridTokens.pagePadding], a card via
  /// [LabeledCard]'s own content padding. When the row previously added a full
  /// gutter of its own, page margins came out at 2*md horizontally but md
  /// vertically, which is the uneven-gutter look.
  final double? outerInset;

  /// Ordered list of (span, child) pairs. Spans should sum to [columns].
  final List<({int span, Widget child})> cells;

  @override
  Widget build(BuildContext context) {
    final knownGutter = gutter ??
        GridProvider.maybeOf(context)?.lg ??
        GridGutterProvider.maybeOf(context);

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
    final outer = outerInset ?? 0.0;

    // Single-cell row: combined row-margin + cell-padding (= g) on each side.
    if (cells.length == 1) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: outer),
        child: cells[0].child,
      );
    }

    // Multi-cell row: Expanded with flex = span for proportional widths.
    // Wrapped in IntrinsicHeight so all cells stretch to the tallest
    // child's height — card bottoms align across the row.
    final row = Row(
      crossAxisAlignment:
          equalHeight ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        for (final (i, cell) in cells.indexed)
          Expanded(
            flex: cell.span,
            // The gutter goes BETWEEN cells only. Padding every cell on both
            // sides put half a gutter outside the first and last ones, which
            // no caller could cancel — the row's own inset could only add.
            child: Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? 0 : halfG,
                right: i == cells.length - 1 ? 0 : halfG,
              ),
              child: cell.child,
            ),
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: outer),
      child: equalHeight ? IntrinsicHeight(child: row) : row,
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
    final inheritedGutter = GridProvider.maybeOf(context)?.lg ??
        GridGutterProvider.maybeOf(context);
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
      old.columns != columns ||
      old.margin != margin ||
      old.gutterOverride != gutterOverride;
}
