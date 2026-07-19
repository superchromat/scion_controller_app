// panel.dart — Grid-aware panel and card-column layout widgets.

import 'package:flutter/material.dart';
import 'grid.dart';
import 'labeled_card.dart';

/// An inset neumorphic panel with optional title.
///
/// When [rows] is null (the default), the child takes its natural height.
/// Use this for knob panels.
///
/// When [rows] is specified, an invisible reference sets the panel height to
/// match a titled knob panel with that many knob rows.  The reference includes
/// the title area so that a fill-panel (e.g. a TextField) has exactly the same
/// height as a sibling knob panel — guaranteeing alignment across cards in
/// an IntrinsicHeight row.  The child fills the entire panel content area via
/// Positioned.fill.
class Panel extends StatelessWidget {
  final int? rows;
  final String? title;
  final Widget? titleTrailing;
  final Widget child;
  final Color? baseColor;
  final bool fillChild;

  const Panel({
    super.key,
    this.rows,
    this.title,
    this.titleTrailing,
    required this.child,
    this.fillChild = false,
  }) : baseColor = null;

  const Panel.dark({
    super.key,
    this.rows,
    this.title,
    this.titleTrailing,
    required this.child,
    this.fillChild = false,
  }) : baseColor = const Color(0xFF252527);

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    // The panel owns the content edge: this padding applies to the title and
    // the body alike, so they cannot disagree. Leaf controls inside must add no
    // left padding of their own. See GridTokens.panelContentInset.
    final panelPad = EdgeInsets.fromLTRB(
      t.panelContentInset,
      t.panelPadding.top,
      t.panelPadding.right,
      t.panelPadding.bottom,
    );

    if (rows != null) {
      // Reference includes title area so height matches a titled knob panel.
      final reference = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(' ', style: t.textHeading),
          ),
          SizedBox(height: t.xs),
          for (int i = 0; i < rows!; i++) ...[
            if (i > 0) SizedBox(height: t.sm),
            SizedBox(height: t.knobMd),
            Text(' ', style: t.textLabel),
          ],
        ],
      );

      return NeumorphicInset(
        padding: panelPad,
        baseColor: baseColor ?? const Color(0xFF2A2A2C),
        child: Stack(
          children: [
            Opacity(opacity: 0, child: reference),
            Positioned.fill(child: child),
          ],
        ),
      );
    }

    // Natural-height panel (knob panels).
    Widget body;
    if (title != null) {
      body = Column(
        mainAxisSize: fillChild ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title!,
                    style: t.textHeading,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              ),
              if (titleTrailing != null) ...[
                SizedBox(width: t.xs),
                titleTrailing!,
              ],
            ],
          ),
          SizedBox(height: t.xs),
          if (fillChild) Expanded(child: child) else child,
        ],
      );
    } else {
      body = fillChild ? SizedBox.expand(child: child) : child;
    }

    return NeumorphicInset(
      padding: panelPad,
      baseColor: baseColor ?? const Color(0xFF2A2A2C),
      child: body,
    );
  }
}

/// Wraps card content that is NOT a [GridRow] of [Panel]s — plain text, a bare
/// row of buttons — so it lands on the same left edge as the card title.
///
/// [LabeledCard] gives its child no horizontal padding, because the usual child
/// is a [GridRow] which brings its own gutter. Anything else has to inset
/// itself, and doing that by hand is what left the About and Configuration
/// cards' contents flush against the card edge. Use this instead of reaching
/// for [GridTokens.cardBodyInset] directly.
class CardBody extends StatelessWidget {
  final Widget child;
  final double? top;

  const CardBody({super.key, required this.child, this.top});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Padding(
      // Symmetric: a card's content edge applies on both sides, so trailing
      // controls (e.g. "Restore to Defaults") don't touch the card border.
      padding: EdgeInsets.fromLTRB(
          t.cardBodyInset, top ?? 0, t.cardBodyInset, 0),
      child: child,
    );
  }
}

/// Lays fixed-size controls (knobs, dropdowns, toggles) into [cols] even
/// columns so they align to a consistent grid, wrapping to new rows. Each
/// control is centred in its cell and scaled down if the cell is narrower than
/// it — replacing ad-hoc [Wrap]s that left-pack and leave ragged gaps.
class ControlGrid extends StatelessWidget {
  final List<Widget> children;
  final int cols;

  const ControlGrid({super.key, required this.children, this.cols = 4});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final rows = <Widget>[];
    for (int i = 0; i < children.length; i += cols) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int c = 0; c < cols; c++)
            Expanded(
              child: (i + c) < children.length
                  ? Padding(
                      padding: EdgeInsets.symmetric(horizontal: t.xs * 0.5),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: children[i + c],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: t.sm),
          rows[r],
        ],
      ],
    );
  }
}

/// Arranges children vertically with a gap between them (default [GridTokens.md];
/// pass [spacing] for a tighter or looser rhythm).
class CardColumn extends StatelessWidget {
  final List<Widget> children;
  final double? spacing;

  const CardColumn({super.key, required this.children, this.spacing});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final gap = spacing ?? t.md;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );
  }
}
