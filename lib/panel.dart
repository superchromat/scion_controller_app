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
  final Widget child;
  final Color? baseColor;

  const Panel({
    super.key,
    this.rows,
    this.title,
    required this.child,
  }) : baseColor = null;

  const Panel.dark({
    super.key,
    this.rows,
    this.title,
    required this.child,
  }) : baseColor = const Color(0xFF252527);

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    if (rows != null) {
      // Reference includes title area so height matches a titled knob panel.
      final reference = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: Text(' ', style: t.textHeading)),
          SizedBox(height: t.xs),
          for (int i = 0; i < rows!; i++) ...[
            if (i > 0) SizedBox(height: t.sm),
            SizedBox(height: t.knobMd),
            Text(' ', style: t.textLabel),
          ],
        ],
      );

      return NeumorphicInset(
        padding: t.panelPadding,
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              title!,
              style: t.textHeading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          SizedBox(height: t.xs),
          child,
        ],
      );
    } else {
      body = child;
    }

    return NeumorphicInset(
      padding: t.panelPadding,
      baseColor: baseColor ?? const Color(0xFF2A2A2C),
      child: body,
    );
  }
}

/// Arranges children vertically with [GridTokens.md] gaps between them.
class CardColumn extends StatelessWidget {
  final List<Widget> children;

  const CardColumn({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: t.md),
          children[i],
        ],
      ],
    );
  }
}
