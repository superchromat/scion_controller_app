import 'package:flutter/material.dart';

import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'osc_widget_binding.dart';
import 'grid.dart';
import 'panel.dart';

/// Texture controls with 7 knobs:
/// - H Blur: 0 to 1 - horizontal blur amount
/// - H Blur Shp: 0 (triangular) to 1 (box) - blur coefficient distribution
/// - H Sharp: 0 to 1 - horizontal sharpening amount
/// - H Shrp Shp: 0 (narrow/fine) to 1 (wide/coarse) - sharpening kernel shape
/// - V Blur: 0 to 1 - vertical blur amount
/// - V Blur Shp: 0 (triangular) to 1 (box) - blur coefficient distribution
/// - V Sharp: 0 to 1 - vertical sharpening amount
class SendTexture extends StatefulWidget {
  const SendTexture({super.key});

  @override
  State<SendTexture> createState() => _SendTextureState();
}

class _SendTextureState extends State<SendTexture> with OscAddressMixin {
  // Knob values
  double _hBlur = 0.0;       // 0 to 1
  double _hBlurShape = 0.5;  // 0 (triangular) to 1 (box)
  double _hSharp = 0.0;      // 0 to 1
  double _hSharpShape = 0.0; // 0 (narrow/fine) to 1 (wide/coarse)
  double _vBlur = 0.0;       // 0 to 1
  double _vBlurShape = 0.5;  // 0 (triangular) to 1 (box)
  double _vSharp = 0.0;      // 0 to 1
  int _resetCount = 0;       // Used to force knob recreation on reset

  /// Reset all texture/filter controls to defaults
  void reset() {
    setState(() {
      _hBlur = 0.0;
      _hBlurShape = 0.5;
      _hSharp = 0.0;
      _hSharpShape = 0.0;
      _vBlur = 0.0;
      _vBlurShape = 0.5;
      _vSharp = 0.0;
      _resetCount++;
    });
    _applyHorizontalBlur();
    _applyHorizontalSharpen();
    _applyVerticalBlur();
    _applyVerticalSharpen();
  }


  //----------------------------------------------------------------------------
  // Coefficient Generation
  //----------------------------------------------------------------------------

  /// Generate blur coefficients for HAA (15-tap symmetric, 8 unique coefficients)
  /// Shape: 0 = triangular, 1 = box
  /// Amount: 0 = identity, 1 = max blur
  List<int> _haaBlurCoeffs(double amount, double shape) {
    const identity = [256, 0, 0, 0, 0, 0, 0, 0];
    const triangular = [32, 28, 24, 20, 16, 12, 8, 4];
    const box = [18, 17, 17, 17, 17, 17, 17, 17];

    return List<int>.generate(8, (i) {
      final blur = triangular[i] + (box[i] - triangular[i]) * shape;
      return (identity[i] + (blur - identity[i]) * amount).round();
    });
  }

  /// Generate blur coefficients for VAA (11-tap symmetric, 6 unique coefficients)
  List<int> _vaaBlurCoeffs(double amount, double shape) {
    const identity = [256, 0, 0, 0, 0, 0];
    const triangular = [42, 36, 28, 22, 14, 7];
    const box = [24, 23, 23, 23, 23, 23];

    return List<int>.generate(6, (i) {
      final blur = triangular[i] + (box[i] - triangular[i]) * shape;
      return (identity[i] + (blur - identity[i]) * amount).round();
    });
  }

  /// Generate blur coefficients for Front NR Y (15-tap symmetric, 8 unique coefficients)
  List<double> _frontNrYBlurCoeffs(double amount, double shape) {
    const identity = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    const triangular = [0.125, 0.109375, 0.09375, 0.078125, 0.0625, 0.046875, 0.03125, 0.015625];
    const box = [0.0667, 0.0667, 0.0667, 0.0667, 0.0667, 0.0667, 0.0667, 0.0667];

    return List<double>.generate(8, (i) {
      final blur = triangular[i] + (box[i] - triangular[i]) * shape;
      return identity[i] + (blur - identity[i]) * amount;
    });
  }

  /// Generate blur coefficients for Front NR C (7-tap symmetric, 4 unique coefficients)
  List<double> _frontNrCBlurCoeffs(double amount, double shape) {
    const identity = [1.0, 0.0, 0.0, 0.0];
    const triangular = [0.25, 0.1875, 0.125, 0.0625];
    const box = [0.143, 0.143, 0.143, 0.143];

    return List<double>.generate(4, (i) {
      final blur = triangular[i] + (box[i] - triangular[i]) * shape;
      return identity[i] + (blur - identity[i]) * amount;
    });
  }

  /// Generate sharpening kernel for H-Peak
  List<double> _hpeakKernel(double shape) {
    const narrow = [1.0, -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    const wide = [1.0, -0.3, -0.2, -0.15, -0.1, -0.05, 0.0, 0.0];

    return List<double>.generate(8, (i) {
      return narrow[i] + (wide[i] - narrow[i]) * shape;
    });
  }

  //----------------------------------------------------------------------------
  // Apply Functions
  //----------------------------------------------------------------------------

  void _applyHorizontalBlur() {
    if (_hBlur > 0.001) {
      final blurAmount = _hBlur;

      final frontNrYCoeffs = _frontNrYBlurCoeffs(blurAmount, _hBlurShape);
      sendOsc(frontNrYCoeffs, address: 'filter/front_nr/y');
      sendOsc(true, address: 'filter/front_nr/enable_y');
      sendOsc(false, address: 'filter/front_nr/bypass_y');

      final frontNrCCoeffs = _frontNrCBlurCoeffs(blurAmount, _hBlurShape);
      sendOsc(frontNrCCoeffs, address: 'filter/front_nr/c');
      sendOsc(true, address: 'filter/front_nr/enable_c');
      sendOsc(false, address: 'filter/front_nr/bypass_cb');
      sendOsc(false, address: 'filter/front_nr/bypass_cr');

      final haaCoeffs = _haaBlurCoeffs(blurAmount, _hBlurShape);
      sendOsc(haaCoeffs, address: 'filter/haa/y');
      sendOsc(true, address: 'filter/haa/enable_y');
    } else {
      sendOsc(false, address: 'filter/haa/enable_y');
      sendOsc(const [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], address: 'filter/front_nr/y');
      sendOsc(const [1.0, 0.0, 0.0, 0.0], address: 'filter/front_nr/c');
      sendOsc(true, address: 'filter/front_nr/enable_y');
      sendOsc(false, address: 'filter/front_nr/bypass_y');
    }
  }

  void _applyHorizontalSharpen() {
    if (_hSharp > 0.001) {
      final kernel = _hpeakKernel(_hSharpShape);
      sendOsc(kernel, address: 'filter/h_peak/coef');
      sendOsc(0, address: 'filter/h_peak/gain_thres');
      sendOsc(0, address: 'filter/h_peak/gain_offset');

      final gain = _hSharp * 1.8;
      sendOsc(gain, address: 'filter/h_peak/gain');
      sendOsc(true, address: 'filter/h_peak/enable');
    } else {
      sendOsc(false, address: 'filter/h_peak/enable');
    }
  }

  void _applyVerticalBlur() {
    if (_vBlur > 0.001) {
      final coeffs = _vaaBlurCoeffs(_vBlur, _vBlurShape);
      debugPrint('VAA blur: amount=$_vBlur shape=$_vBlurShape coeffs=$coeffs');

      sendOsc(coeffs, address: 'filter/vaa/y');
      sendOsc(true, address: 'filter/vaa/enable_y');
    } else {
      sendOsc(false, address: 'filter/vaa/enable_y');
    }
  }

  void _applyVerticalSharpen() {
    if (_vSharp > 0.001) {
      sendOsc(4, address: 'filter/v_peak/gain_div');

      final gain = (_vSharp * 1.96875).clamp(0.0, 1.96875);
      sendOsc(gain, address: 'filter/v_peak/gain');
    } else {
      sendOsc(0.0, address: 'filter/v_peak/gain');
    }
  }

  //----------------------------------------------------------------------------
  // UI
  //----------------------------------------------------------------------------

  Widget _knob({
    required String label,
    required double value,
    required double minValue,
    required double maxValue,
    required ValueChanged<double> onChanged,
    List<double> snapPoints = const [],
  }) {
    final t = GridProvider.of(context);
    return OscRotaryKnob(
      key: ValueKey('$label-$_resetCount'),
      initialValue: value,
      minValue: minValue,
      maxValue: maxValue,
      format: '%.2f',
      label: label,
      defaultValue: 0,
      size: t.knobMd,
      labelStyle: t.textLabel,
      sendOsc: false,
      isBipolar: minValue < 0,
      snapConfig: SnapConfig(
        snapPoints: snapPoints,
        snapRegionHalfWidth: (maxValue - minValue) * 0.03,
        snapBehavior: SnapBehavior.hard,
      ),
      onChanged: onChanged,
    );
  }

  /// Builds a titled panel of knob slots.
  Widget _knobPanel(String title, List<Widget?> knobs) {
    return Panel(
      title: title,
      child: Row(
        children: [
          for (final k in knobs)
            Expanded(child: Center(child: k ?? const SizedBox())),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return CardColumn(
      children: [
        GridRow(
          columns: 2,
          gutter: t.md,
          cells: [
            (
              span: 1,
              child: _knobPanel('H Blur', [
                _knob(
                  label: 'Amount',
                  value: _hBlur,
                  minValue: 0.0,
                  maxValue: 1.0,
                  onChanged: (v) {
                    setState(() => _hBlur = v);
                    _applyHorizontalBlur();
                  },
                ),
                _knob(
                  label: 'Shape',
                  value: _hBlurShape,
                  minValue: 0.0,
                  maxValue: 1.0,
                  snapPoints: const [0.5],
                  onChanged: (v) {
                    setState(() => _hBlurShape = v);
                    _applyHorizontalBlur();
                  },
                ),
              ]),
            ),
            (
              span: 1,
              child: _knobPanel('H Sharpen', [
                _knob(
                  label: 'Amount',
                  value: _hSharp,
                  minValue: 0.0,
                  maxValue: 1.0,
                  onChanged: (v) {
                    setState(() => _hSharp = v);
                    _applyHorizontalSharpen();
                  },
                ),
                _knob(
                  label: 'Shape',
                  value: _hSharpShape,
                  minValue: 0.0,
                  maxValue: 1.0,
                  snapPoints: const [0.5],
                  onChanged: (v) {
                    setState(() => _hSharpShape = v);
                    _applyHorizontalSharpen();
                  },
                ),
              ]),
            ),
          ],
        ),
        GridRow(
          columns: 2,
          gutter: t.md,
          cells: [
            (
              span: 1,
              child: _knobPanel('V Blur', [
                _knob(
                  label: 'Amount',
                  value: _vBlur,
                  minValue: 0.0,
                  maxValue: 1.0,
                  onChanged: (v) {
                    setState(() => _vBlur = v);
                    _applyVerticalBlur();
                  },
                ),
                _knob(
                  label: 'Shape',
                  value: _vBlurShape,
                  minValue: 0.0,
                  maxValue: 1.0,
                  snapPoints: const [0.5],
                  onChanged: (v) {
                    setState(() => _vBlurShape = v);
                    _applyVerticalBlur();
                  },
                ),
              ]),
            ),
            (
              span: 1,
              child: _knobPanel('V Sharpen', [
                _knob(
                  label: 'Amount',
                  value: _vSharp,
                  minValue: 0.0,
                  maxValue: 1.0,
                  onChanged: (v) {
                    setState(() => _vSharp = v);
                    _applyVerticalSharpen();
                  },
                ),
              ]),
            ),
          ],
        ),
      ],
    );
  }
}
