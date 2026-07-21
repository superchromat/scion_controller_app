import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'osc_dropdown.dart';
import 'rotary_knob.dart';
import 'grid.dart';
import 'panel.dart';

/// Effect panels for Send 1 (the only send with the warp / uniformity /
/// GAC hardware). Embedded as sections inside the Shape / Color / Glitch
/// cards; knob segments are card-relative (shape/warp/*, color/field/*,
/// glitch/gac/*) under the ambient /send/1 path.

Widget _knob(
    BuildContext context, String label, String seg, double min, double max,
    {double initial = 0, bool bipolar = false, double? size}) {
  final t = GridProvider.maybeOf(context);
  return OscPathSegment(
    segment: seg,
    child: OscRotaryKnob(
      label: label,
      minValue: min,
      maxValue: max,
      initialValue: initial,
      defaultValue: initial,
      format: '%d',
      isBipolar: bipolar,
      preferInteger: true,
      size: size ?? t?.knobMd ?? 60,
      labelStyle: t?.textLabel,
      // Detent at the neutral / 'no effect' default so a knob clicks back to
      // rest.
      snapConfig: SnapConfig(
        snapPoints: [initial],
        snapRegionHalfWidth: (max - min) * 0.015,
        snapBehavior: SnapBehavior.hard,
      ),
    ),
  );
}

Widget _dropdown(String label, String seg, List<String> options,
    {double width = 110}) {
  return OscDropdown<int>(
    label: label,
    pathSegment: seg,
    items: List.generate(options.length, (i) => i),
    itemLabels: {for (int i = 0; i < options.length; i++) i: options[i]},
    defaultValue: 0,
    width: width,
  );
}

class _Toggle extends StatefulWidget {
  final String label;
  const _Toggle({required this.label});
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> with OscAddressMixin {
  bool _on = false;

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isNotEmpty && args.first is int) {
      setState(() => _on = (args.first as int) != 0);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: t.xs, bottom: t.xs),
          child: Text(widget.label, style: t.textLabel),
        ),
        GestureDetector(
          onTap: () {
            final v = !_on;
            setState(() => _on = v);
            sendOsc(v ? 1 : 0);
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: t.md, vertical: t.xs),
            decoration: BoxDecoration(
              color: _on ? const Color(0xFFFF6B6B) : const Color(0xFF2A2A2C),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: _on ? const Color(0xFFFF6B6B) : Colors.grey[600]!,
              ),
            ),
            child: Text(
              _on ? 'ON' : 'OFF',
              style: t.textLabel.copyWith(
                fontWeight: FontWeight.w700,
                color: _on ? Colors.white : Colors.grey[300],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Widget _wrap(BuildContext context, List<Widget> children, {int cols = 4}) {
  // Even column grid so knobs/dropdowns align consistently across panels,
  // instead of a Wrap that left-packs and leaves the right side empty.
  return ControlGrid(cols: cols, children: children);
}

/// Affine warp — homography engine: 7 ms updates, animates at frame rate.
/// Keystone and shear. Owns Send 1's transform while enabled (the Shape
/// rotation/scale knobs pause). Warp turns on automatically whenever the
/// matrix is non-neutral and off when it returns to neutral — no toggle.
class WarpAffinePanel extends StatelessWidget {
  /// Compact = a 2×2 grid of smaller knobs (for the tight Warp-tab row).
  final bool compact;
  const WarpAffinePanel({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final ks = compact ? GridProvider.maybeOf(context)?.knobSm : null;
    return Panel(
      title: 'Keystone',
      child: _wrap(
          context,
          [
            _knob(context, 'Key H', 'shape/warp/key_h', -600, 600,
                bipolar: true, size: ks),
            _knob(context, 'Key V', 'shape/warp/key_v', -400, 400,
                bipolar: true, size: ks),
            _knob(context, 'Shear X', 'shape/warp/shear_x', -600, 600,
                bipolar: true, size: ks),
            _knob(context, 'Shear Y', 'shape/warp/shear_y', -400, 400,
                bipolar: true, size: ks),
          ],
          cols: compact ? 2 : 4),
    );
  }
}

/// LUT warp — free-form engine: full LUT rewrite per update (~120 ms).
/// Barrel/lens distortion. Zoom lives on the Shape Scale knobs, not here.
class WarpLutPanel extends StatelessWidget {
  /// Compact = a 2×2 grid of smaller knobs (for the tight Warp-tab row).
  final bool compact;
  const WarpLutPanel({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final ks = compact ? GridProvider.maybeOf(context)?.knobSm : null;
    return Panel(
      title: 'Lens',
      child: _wrap(
          context,
          [
            _knob(context, 'Barrel', 'shape/warp/barrel', -400, 400,
                bipolar: true, size: ks),
            _knob(context, 'Lens X', 'shape/warp/lens_x', -960, 960,
                bipolar: true, size: ks),
            _knob(context, 'Lens Y', 'shape/warp/lens_y', -540, 540,
                bipolar: true, size: ks),
            _knob(context, 'Radius', 'shape/warp/radius', 0, 960, size: ks),
          ],
          cols: compact ? 2 : 4),
    );
  }
}

/// Animation — the time-varying warps: the procedural basis field
/// (ripple/twirl/wave, whose phase advances with Speed) plus the wobble,
/// breathe and roam amplitudes. All driven by the shared Speed clock.
class WarpAnimationPanel extends StatelessWidget {
  const WarpAnimationPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Animation',
      child: _wrap(context, [
        _dropdown('Field', 'shape/warp/field',
            const ['Off', 'Ripple', 'Twirl', 'Wave'],
            width: 90),
        _knob(context, 'F Amp', 'shape/warp/famp', 0, 300),
        _knob(context, 'F Freq', 'shape/warp/ffreq', 50, 1200, initial: 300),
        _knob(context, 'Speed', 'shape/warp/speed', -2000, 2000,
            initial: 250, bipolar: true),
        _knob(context, 'Wobble', 'shape/warp/wobble', 0, 200),
        _knob(context, 'Breathe', 'shape/warp/breathe', 0, 300),
        _knob(context, 'Roam', 'shape/warp/roam', 0, 500),
      ]),
    );
  }
}

/// Uniformity-correction colour field — animated per-region RGB gains.
class ColorFieldPanel extends StatelessWidget {
  const ColorFieldPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return _wrap(context, [
      const OscPathSegment(
          segment: 'color/field/enable', child: _Toggle(label: 'Enable')),
      _dropdown('Basis', 'color/field/fx',
          const ['Flat', 'Gradient', 'Rings', 'Plaid']),
      _knob(context, 'Amount', 'color/field/amount', 0, 127, initial: 127),
      _knob(context, 'Amp R', 'color/field/amp_r', -1023, 1023, bipolar: true),
      _knob(context, 'Amp G', 'color/field/amp_g', -1023, 1023, bipolar: true),
      _knob(context, 'Amp B', 'color/field/amp_b', -1023, 1023, bipolar: true),
      _knob(context, 'Freq', 'color/field/freq', 10, 800, initial: 100),
      _knob(context, 'Angle', 'color/field/angle', 0, 360),
      _knob(context, 'Speed', 'color/field/speed', -2000, 2000, bipolar: true),
      _knob(context, 'Center X', 'color/field/cx', 0, 1920, initial: 960),
      _knob(context, 'Center Y', 'color/field/cy', 0, 1080, initial: 540),
      _knob(context, 'Res', 'color/field/res', 4, 63, initial: 16),
      _knob(context, 'Bias', 'color/field/bias', 0, 1023, initial: 768),
    ]);
  }
}

/// GAC rectangle-copy tiling — live blitter grid from a source rect.
class RectCopyPanel extends StatelessWidget {
  const RectCopyPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.maybeOf(context);
    // A left-packing Wrap (not the 4-column ControlGrid) so the 12 controls
    // flow into ~1 dense row across the full-width card instead of a tall 4×3.
    return Wrap(
      spacing: t?.sm ?? 8,
      runSpacing: t?.sm ?? 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const OscPathSegment(
            segment: 'glitch/gac/enable', child: _Toggle(label: 'Enable')),
        _knob(context, 'From X', 'glitch/gac/x', 0, 1912, initial: 896),
        _knob(context, 'From Y', 'glitch/gac/y', 0, 1072, initial: 476),
        _knob(context, 'To X', 'glitch/gac/dst_x', 0, 1912, initial: 896),
        _knob(context, 'To Y', 'glitch/gac/dst_y', 0, 1072, initial: 476),
        _knob(context, 'Size', 'glitch/gac/size', 8, 512, initial: 128),
        _knob(context, 'Grid', 'glitch/gac/grid', 1, 16, initial: 4),
        // Spacing > Size spreads the tiles across the frame with live video
        // between them (per-tile copies); <= Size tiles edge-to-edge.
        _knob(context, 'Spacing', 'glitch/gac/spacing', 0, 640),
        // 0 = grid layout, 1000 = radial rings around the source; smooth
        // interpolation between.
        _knob(context, 'Radial', 'glitch/gac/morph', 0, 1000),
        const OscPathSegment(
            segment: 'glitch/gac/yonly', child: _Toggle(label: 'Y Only')),
        _knob(context, 'Shear In', 'glitch/gac/shear_src', -192, 192,
            bipolar: true),
        _knob(context, 'Shear Out', 'glitch/gac/shear_dst', -192, 192,
            bipolar: true),
      ],
    );
  }
}
