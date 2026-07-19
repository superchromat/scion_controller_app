import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'grid.dart';
import 'panel.dart';

/// Texture controls with 7 knobs bound directly to the device's knob-level
/// endpoints (/send/N/texture/{blur,sharp}/{h,v}/{amount,shape}). The DEVICE
/// derives the FIR/IIR filter coefficients from these — the old client-side
/// maths is gone, which means the knobs sync from the device like every
/// other control (the coefficient computation was not invertible).
///
/// - Blur Amount: 0 (identity) to 1 (max blur)
/// - Blur Shape:  0 (triangular) to 1 (box)
/// - Sharpen Amount: 0 to 1
/// - Sharpen Shape (H only): 0 (narrow/fine) to 1 (wide/coarse)
class SendTexture extends StatelessWidget {
  const SendTexture({super.key, this.pageNumber = 1});
  final int pageNumber;

  Widget _knob(BuildContext context, String label, String segment,
      {List<double> snapPoints = const []}) {
    final t = GridProvider.of(context);
    return OscPathSegment(
      segment: segment,
      child: OscRotaryKnob(
        initialValue: 0,
        minValue: 0.0,
        maxValue: 1.0,
        format: '%.2f',
        label: label,
        defaultValue: 0,
        size: t.knobMd,
        labelStyle: t.textLabel,
        snapConfig: SnapConfig(
          snapPoints: snapPoints,
          snapRegionHalfWidth: 0.03,
          snapBehavior: SnapBehavior.hard,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Two packed panels side by side: Blur (H/V × Amount/Shape) and Sharpen
    // (H Amount/Shape, V Amount) — one row instead of the old 2×2 of near-empty
    // panels.
    return OscPathSegment(
      segment: 'texture',
      child: GridRow(columns: 2, cells: [
        (
          span: 1,
          child: Panel(
            title: 'Blur',
            child: ControlGrid(children: [
              _knob(context, 'H Amt', 'blur/h/amount'),
              _knob(context, 'H Shape', 'blur/h/shape',
                  snapPoints: const [0.5]),
              _knob(context, 'V Amt', 'blur/v/amount'),
              _knob(context, 'V Shape', 'blur/v/shape',
                  snapPoints: const [0.5]),
            ]),
          ),
        ),
        (
          span: 1,
          child: Panel(
            title: 'Sharpen',
            child: ControlGrid(children: [
              _knob(context, 'H Amt', 'sharp/h/amount'),
              _knob(context, 'H Shape', 'sharp/h/shape',
                  snapPoints: const [0.5]),
              _knob(context, 'V Amt', 'sharp/v/amount'),
            ]),
          ),
        ),
      ]),
    );
  }
}
