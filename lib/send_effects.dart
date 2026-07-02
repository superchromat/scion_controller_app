import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'osc_dropdown.dart';
import 'grid.dart';

/// Effect panels for Send 1 (the only send with the warp / uniformity /
/// GAC hardware). These live as page-level cards; their knobs bind under
/// the 'glitch' path segment so the firmware endpoint addresses are
/// unchanged (/send/1/glitch/warp_*, uc_*, gac_*).

Widget _knob(BuildContext context, String label, String seg, double min,
    double max,
    {double initial = 0, bool bipolar = false}) {
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
      size: t?.knobMd ?? 60,
      labelStyle: t?.textLabel,
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

Widget _wrap(BuildContext context, List<Widget> children) {
  final t = GridProvider.of(context);
  return Wrap(
    spacing: t.sm,
    runSpacing: t.sm,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}

/// Affine warp — homography engine: 7 ms updates, animates at frame rate.
/// Keystone, shear and the corner wobble. Owns Send 1's transform while
/// enabled (the Shape rotation/scale knobs pause).
class WarpAffinePanel extends StatelessWidget {
  const WarpAffinePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'glitch',
      child: _wrap(context, [
        const OscPathSegment(
            segment: 'warp_enable', child: _Toggle(label: 'Enable')),
        _knob(context, 'Key H', 'warp_key_h', -600, 600, bipolar: true),
        _knob(context, 'Key V', 'warp_key_v', -400, 400, bipolar: true),
        _knob(context, 'Shear X', 'warp_shear_x', -600, 600, bipolar: true),
        _knob(context, 'Shear Y', 'warp_shear_y', -400, 400, bipolar: true),
        _knob(context, 'Wobble', 'warp_wobble', 0, 200),
        _knob(context, 'Speed', 'warp_speed', -2000, 2000,
            initial: 250, bipolar: true),
      ]),
    );
  }
}

/// LUT warp — free-form engine: full LUT rewrite per update (~120 ms, so
/// animation runs at ~8 Hz). Barrel/lens distortion plus the ripple/twirl/
/// wave basis fields. Mutually exclusive with the affine family — the
/// last-touched knob's engine wins.
class WarpLutPanel extends StatelessWidget {
  const WarpLutPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'glitch',
      child: _wrap(context, [
        _knob(context, 'Barrel', 'warp_barrel', -400, 400, bipolar: true),
        _knob(context, 'Zoom', 'warp_zoom', 400, 1600, initial: 1000),
        _knob(context, 'Lens X', 'warp_lens_x', -960, 960, bipolar: true),
        _knob(context, 'Lens Y', 'warp_lens_y', -540, 540, bipolar: true),
        _knob(context, 'Radius', 'warp_radius', 0, 960),
        _knob(context, 'Breathe', 'warp_breathe', 0, 300),
        _knob(context, 'Roam', 'warp_roam', 0, 500),
        _dropdown('Field', 'warp_field',
            const ['Off', 'Ripple', 'Twirl', 'Wave'], width: 90),
        _knob(context, 'F Amp', 'warp_famp', 0, 300),
        _knob(context, 'F Freq', 'warp_ffreq', 50, 1200, initial: 300),
      ]),
    );
  }
}

/// Uniformity-correction colour field — animated per-region RGB gains.
class ColorFieldPanel extends StatelessWidget {
  const ColorFieldPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'glitch',
      child: _wrap(context, [
        const OscPathSegment(
            segment: 'uc_enable', child: _Toggle(label: 'Enable')),
        _dropdown('Basis', 'uc_fx',
            const ['Flat', 'Gradient', 'Rings', 'Plaid']),
        _knob(context, 'Amount', 'uc_amount', 0, 127, initial: 127),
        _knob(context, 'Amp R', 'uc_amp_r', -1023, 1023, bipolar: true),
        _knob(context, 'Amp G', 'uc_amp_g', -1023, 1023, bipolar: true),
        _knob(context, 'Amp B', 'uc_amp_b', -1023, 1023, bipolar: true),
        _knob(context, 'Freq', 'uc_freq', 10, 800, initial: 100),
        _knob(context, 'Angle', 'uc_angle', 0, 360),
        _knob(context, 'Speed', 'uc_speed', -2000, 2000, bipolar: true),
        _knob(context, 'Center X', 'uc_cx', 0, 1920, initial: 960),
        _knob(context, 'Center Y', 'uc_cy', 0, 1080, initial: 540),
        _knob(context, 'Res', 'uc_res', 4, 63, initial: 16),
        _knob(context, 'Bias', 'uc_bias', 0, 1023, initial: 768),
      ]),
    );
  }
}

/// GAC rectangle-copy tiling — live blitter grid from a source rect.
class RectCopyPanel extends StatelessWidget {
  const RectCopyPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'glitch',
      child: _wrap(context, [
        const OscPathSegment(
            segment: 'gac_enable', child: _Toggle(label: 'Enable')),
        _knob(context, 'From X', 'gac_x', 0, 1912, initial: 896),
        _knob(context, 'From Y', 'gac_y', 0, 1072, initial: 476),
        _knob(context, 'Size', 'gac_size', 8, 512, initial: 128),
        _knob(context, 'Grid', 'gac_grid', 1, 16, initial: 4),
        // Spacing > Size spreads the tiles across the frame with live video
        // between them (per-tile copies); <= Size tiles edge-to-edge.
        _knob(context, 'Spacing', 'gac_spacing', 0, 640),
        // 0 = grid layout, 1000 = radial rings around the source; smooth
        // interpolation between.
        _knob(context, 'Radial', 'gac_morph', 0, 1000),
        const OscPathSegment(
            segment: 'gac_yonly', child: _Toggle(label: 'Y Only')),
        _knob(context, 'Shear In', 'gac_shear_src', -192, 192, bipolar: true),
        _knob(context, 'Shear Out', 'gac_shear_dst', -192, 192, bipolar: true),
      ]),
    );
  }
}
