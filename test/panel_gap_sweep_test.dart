// TEMPORARY verification sweep — measures the real gap between sibling Panels,
// and from a Panel to its card's content edge, on every page and every Shape
// tab, at several widths. Delete once the result has been read.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/grid.dart';
import 'package:SCION_Controller/labeled_card.dart';
import 'package:SCION_Controller/panel.dart';
import 'package:SCION_Controller/mixer_page.dart';
import 'package:SCION_Controller/return_page.dart';
import 'package:SCION_Controller/send_page.dart';
import 'package:SCION_Controller/setup_page.dart';
import 'package:SCION_Controller/system_page.dart';
import 'package:SCION_Controller/system_overview.dart';

import 'design_lab/harness.dart';

const widths = <double>[1024, 1400, 1948];

Rect _rect(Element e) {
  final ro = e.renderObject as RenderBox;
  final o = ro.localToGlobal(Offset.zero);
  return o & ro.size;
}

/// Panels that are direct children of [card] (not nested inside another Panel).
List<Rect> _panelsIn(Element card) {
  final out = <Rect>[];
  void walk(Element e) {
    if (e != card && e.widget is LabeledCard) return;
    if (e.widget is Panel) {
      final ro = e.renderObject;
      if (ro is RenderBox && ro.hasSize) out.add(_rect(e));
      return; // don't descend — nested panels are not siblings
    }
    e.visitChildren(walk);
  }

  card.visitChildren(walk);
  return out;
}

void main() {
  final pages = <String, Widget Function()>{
    'System': () => const SystemPage(),
    'Setup': () => const SetupPage(isActive: false),
    'Send1': () => const SendPage(pageNumber: 1),
    'Send2': () => const SendPage(pageNumber: 2),
    'Send3': () => const SendPage(pageNumber: 3),
    'Return': () => const ReturnPage(),
    'Mixer': () => const MixerPage(),
  };
  const tabs = ['Transform', 'Warp', 'Text', 'Sprites', 'Color Field'];

  testWidgets('panel gaps are uniform everywhere', (t) async {
    await loadAppFonts();
    final report = <String>[];

    Future<void> measure(String label, double w) async {
      // Grid unit, hence expected gap, comes from the tree itself.
      final tokens = GridProvider.of(
          find.byType(LabeledCard).evaluate().first as BuildContext);
      final expected = tokens.panelGap;

      // CARD-to-CARD gaps on the page itself. The panel sweep never looked at
      // these, which is how an uneven gap survived on the System page.
      final cards = <Rect>[];
      for (final c in find.byType(LabeledCard).evaluate()) {
        final ro = c.renderObject;
        if (ro is RenderBox && ro.hasSize) cards.add(_rect(c));
      }
      void pairs(List<Rect> rs, bool horizontal) {
        final buckets = <double, List<Rect>>{};
        for (final r in rs) {
          final v = horizontal ? r.top : r.left;
          final k = buckets.keys
              .firstWhere((k) => (k - v).abs() < 2.0, orElse: () => v);
          buckets.putIfAbsent(k, () => []).add(r);
        }
        for (final b in buckets.values) {
          b.sort((x, y) =>
              horizontal ? x.left.compareTo(y.left) : x.top.compareTo(y.top));
          for (int i = 0; i + 1 < b.length; i++) {
            final g = horizontal
                ? b[i + 1].left - b[i].right
                : b[i + 1].top - b[i].bottom;
            if ((g - expected).abs() > 0.6) {
              report.add(
                  '$label @${w.toInt()} CARD ${horizontal ? "H" : "V"}-gap '
                  '${g.toStringAsFixed(1)} != ${expected.toStringAsFixed(1)}');
            }
          }
        }
      }

      pairs(cards, true);
      pairs(cards, false);

      for (final card in find.byType(LabeledCard).evaluate()) {
        final title = (card.widget as LabeledCard).title;
        final ps = _panelsIn(card);
        if (ps.length < 2) continue;

        // Rows: panels sharing a top edge, compared LEFT-TO-RIGHT and only
        // against their immediate neighbour. Comparing every pair reported the
        // distance across the whole card as if it were a gap.
        final rows = <double, List<Rect>>{};
        for (final p in ps) {
          final k = rows.keys
              .firstWhere((k) => (k - p.top).abs() < 2.0, orElse: () => p.top);
          rows.putIfAbsent(k, () => []).add(p);
        }
        for (final row in rows.values) {
          row.sort((a, b) => a.left.compareTo(b.left));
          for (int i = 0; i + 1 < row.length; i++) {
            final g = row[i + 1].left - row[i].right;
            if ((g - expected).abs() > 0.6) {
              report.add('$label @${w.toInt()} "$title" H-gap '
                  '${g.toStringAsFixed(1)} != ${expected.toStringAsFixed(1)}');
            }
          }
        }

        // Columns: panels sharing a left edge, compared TOP-TO-BOTTOM.
        final cols = <double, List<Rect>>{};
        for (final p in ps) {
          final k = cols.keys.firstWhere((k) => (k - p.left).abs() < 2.0,
              orElse: () => p.left);
          cols.putIfAbsent(k, () => []).add(p);
        }
        for (final col in cols.values) {
          col.sort((a, b) => a.top.compareTo(b.top));
          for (int i = 0; i + 1 < col.length; i++) {
            final a = col[i], b = col[i + 1];
            // Skip if another panel sits in the band between them — they share
            // a left edge but are not neighbours, and the distance across the
            // intervening panel is not a gap.
            final blocked = ps.any((p) =>
                p != a && p != b && p.top < b.top && p.bottom > a.bottom);
            if (blocked) continue;
            final g = b.top - a.bottom;
            if ((g - expected).abs() > 0.6) {
              report.add('$label @${w.toInt()} "$title" V-gap '
                  '${g.toStringAsFixed(1)} != ${expected.toStringAsFixed(1)}');
            }
          }
        }
      }
    }

    for (final w in widths) {
      t.view.physicalSize = Size(w, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      for (final e in pages.entries) {
        await t.pumpWidget(labScaffold(child: e.value(), width: w));
        await t.pump(const Duration(milliseconds: 400));
        await measure(e.key, w);

        // Shape tabs live only on Send pages.
        if (e.key.startsWith('Send')) {
          for (final tab in tabs) {
            final f = find.text(tab);
            if (f.evaluate().isEmpty) continue;
            await t.tap(f.first, warnIfMissed: false);
            await t.pump(const Duration(milliseconds: 400));
            await measure('${e.key}/$tab', w);
          }
        }
      }
    }

    expect(report, isEmpty, reason: '\n${report.join('\n')}\n');
  });
}
