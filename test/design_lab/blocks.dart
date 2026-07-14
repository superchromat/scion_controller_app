// Faithful stand-in control blocks for layout exploration.
//
// These reuse the REAL neumorphic surfaces (NeumorphicInset/Container), grid
// tokens, typography, and RotaryKnob so visual mass + aesthetics match the
// shipping app — but carry no network/OSC coupling, so any arrangement renders
// deterministically under the golden harness.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:SCION_Controller/grid.dart';
import 'package:SCION_Controller/labeled_card.dart';
import 'package:SCION_Controller/panel.dart';
import 'package:SCION_Controller/rotary_knob.dart';

const _amber = Color(0xFFF0B830);

// ── knob + caption ───────────────────────────────────────────────────────────
class LabKnob extends StatelessWidget {
  final String label;
  final double value; // 0..1 normalized for the arc
  final bool bipolar;
  final double? size;
  const LabKnob(this.label, {super.key, this.value = 0.5, this.bipolar = false, this.size});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final d = size ?? t.knobMd;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RotaryKnob(
          value: bipolar ? (value * 2 - 1) : value,
          minValue: bipolar ? -1 : 0,
          maxValue: 1,
          isBipolar: bipolar,
          size: d,
          // restore the default/neutral detent + double-tap-reset target
          defaultValue: bipolar ? 0 : 0,
          neutralValue: bipolar ? 0 : 0,
        ),
        SizedBox(height: t.xs * 0.8),
        Text(label, style: t.textLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

// ── a titled inset panel holding a horizontal row of knobs ───────────────────
class KnobPanel extends StatelessWidget {
  final String? title;
  final List<(String, double)> knobs;
  final bool bipolar;
  final double? knobSize;
  final MainAxisAlignment align;
  const KnobPanel(this.title, this.knobs,
      {super.key, this.bipolar = false, this.knobSize, this.align = MainAxisAlignment.spaceEvenly});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Panel(
      title: title,
      child: Row(
        mainAxisAlignment: align,
        children: [
          for (final k in knobs)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: t.xs),
              child: LabKnob(k.$1, value: k.$2, bipolar: bipolar, size: knobSize),
            ),
        ],
      ),
    );
  }
}

// ── knobs wrapped into rows of [perRow] ──────────────────────────────────────
class KnobGridPanel extends StatelessWidget {
  final String? title;
  final List<(String, double)> knobs;
  final int perRow;
  final double? knobSize;
  const KnobGridPanel(this.title, this.knobs, {super.key, this.perRow = 4, this.knobSize});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final rows = <List<(String, double)>>[];
    for (var i = 0; i < knobs.length; i += perRow) {
      rows.add(knobs.sublist(i, math.min(i + perRow, knobs.length)));
    }
    return Panel(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) SizedBox(height: t.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final k in rows[r])
                  LabKnob(k.$1, value: k.$2, size: knobSize ?? t.knobSm),
                // pad short last row for alignment
                for (var p = rows[r].length; p < perRow; p++)
                  Opacity(opacity: 0, child: LabKnob('', size: knobSize ?? t.knobSm)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── color wheel stand-in ─────────────────────────────────────────────────────
class LabWheel extends StatelessWidget {
  final String label;
  final double? size;
  const LabWheel(this.label, {super.key, this.size});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final d = size ?? t.knobLg;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: d,
          height: d,
          child: CustomPaint(painter: _WheelPainter()),
        ),
        SizedBox(height: t.xs),
        Text(label, style: t.textLabel),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // recessed ring
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF1A1A1C));
    // hue conic
    final sweep = SweepGradient(colors: const [
      Color(0xFFE04848), Color(0xFFE0C048), Color(0xFF48E060),
      Color(0xFF48C0E0), Color(0xFF6048E0), Color(0xFFE048C0), Color(0xFFE04848),
    ]).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r * 0.92, Paint()..shader = sweep);
    // desaturate center
    canvas.drawCircle(
        c, r * 0.92,
        Paint()
          ..shader = RadialGradient(colors: [
            const Color(0xFF3A3A3E).withValues(alpha: 0.95),
            const Color(0xFF3A3A3E).withValues(alpha: 0.0),
          ]).createShader(Rect.fromCircle(center: c, radius: r * 0.92)));
    // inner well
    canvas.drawCircle(c, r * 0.30, Paint()..color = const Color(0xFF242427));
    // crosshair handle
    canvas.drawCircle(
        c + Offset(r * 0.34, -r * 0.20), r * 0.09, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── dropdown stand-in ────────────────────────────────────────────────────────
class LabDropdown extends StatelessWidget {
  final String label;
  final String value;
  final double? width;
  const LabDropdown(this.label, this.value, {super.key, this.width});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.textCaption),
        SizedBox(height: t.xs * 0.6),
        NeumorphicInset(
          padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 1.2),
          child: SizedBox(
            width: width,
            child: Row(
              mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Text(value, style: t.textValue),
                if (width != null) const Spacer() else SizedBox(width: t.md),
                Icon(Icons.expand_more, size: t.sm * 1.4, color: const Color(0xFF9A9AA0)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── value readout ────────────────────────────────────────────────────────────
class LabValue extends StatelessWidget {
  final String label;
  final String value;
  final bool live;
  const LabValue(this.label, this.value, {super.key, this.live = false});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (live) ...[
            Container(width: t.xs, height: t.xs, decoration: const BoxDecoration(color: Color(0xFF56C271), shape: BoxShape.circle)),
            SizedBox(width: t.xs * 0.8),
          ],
          Text(label, style: t.textCaption),
        ]),
        SizedBox(height: t.xs * 0.4),
        Text(value, style: t.textValue.copyWith(fontSize: t.u * 1.5)),
      ],
    );
  }
}

// ── toggle chip ──────────────────────────────────────────────────────────────
class LabToggle extends StatelessWidget {
  final String label;
  final bool on;
  const LabToggle(this.label, {super.key, this.on = false});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: t.sm * 1.4,
        height: t.sm * 1.4,
        decoration: BoxDecoration(
          color: on ? _amber.withValues(alpha: 0.9) : const Color(0xFF1E1E20),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: on ? _amber : const Color(0xFF3A3A3E), width: 1),
        ),
        child: on ? Icon(Icons.check, size: t.sm, color: Colors.black) : null,
      ),
      SizedBox(width: t.xs),
      Text(label, style: t.textLabel),
    ]);
  }
}

// ── text-input stand-in ──────────────────────────────────────────────────────
class LabTextField extends StatelessWidget {
  final String hint;
  const LabTextField(this.hint, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return NeumorphicInset(
      padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 1.4),
      child: Row(children: [
        Text(hint, style: t.textLabel.copyWith(color: const Color(0xFF7A7A80))),
      ]),
    );
  }
}

// ── swatch strip (color primaries / LUT preview) ─────────────────────────────
class LabSwatchStrip extends StatelessWidget {
  final int n;
  const LabSwatchStrip({super.key, this.n = 6});
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    const hues = [
      Color(0xFFE05A5A), Color(0xFFE0A24A), Color(0xFFD8DC50),
      Color(0xFF5AD070), Color(0xFF50B8D8), Color(0xFF7A6AE0),
    ];
    return NeumorphicInset(
      padding: EdgeInsets.all(t.xs),
      child: Row(children: [
        for (var i = 0; i < n; i++)
          Expanded(
            child: Container(
              height: t.knobSm * 0.6,
              margin: EdgeInsets.symmetric(horizontal: t.xs * 0.5),
              decoration: BoxDecoration(
                color: hues[i % hues.length],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ]),
    );
  }
}

// ── live video preview stand-in (a workflow anchor some layouts introduce) ───
class LabPreview extends StatelessWidget {
  final String tag;
  final double aspect;
  const LabPreview({super.key, this.tag = 'PREVIEW', this.aspect = 16 / 9});
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return NeumorphicInset(
      baseColor: const Color(0xFF161618),
      padding: EdgeInsets.all(t.xs),
      child: AspectRatio(
        aspectRatio: aspect,
        child: CustomPaint(
          painter: _PreviewPainter(),
          child: Center(
            child: Text(tag,
                style: t.textCaption.copyWith(
                    letterSpacing: 2, color: Colors.white.withValues(alpha: 0.35))),
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF243040), Color(0xFF3A2438)],
          ).createShader(rect));
    // faint scanlines
    final p = Paint()..color = Colors.black.withValues(alpha: 0.10)..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── section header divider (reused across layouts) ───────────────────────────
class LabSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const LabSectionHeader(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.sm, bottom: t.xs),
      child: Row(children: [
        Text(title.toUpperCase(),
            style: t.textCaption.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.w600, color: const Color(0xFF8A8A90))),
        SizedBox(width: t.sm),
        Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.08))),
        if (trailing != null) ...[SizedBox(width: t.sm), trailing!],
      ]),
    );
  }
}

/// Convenience re-export so layout files import one thing.
Widget card({required String title, required Widget child, Widget? action, Color? border}) =>
    LabeledCard(title: title, action: action, borderColor: border, child: child);
