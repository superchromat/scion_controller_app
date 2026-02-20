import 'package:flutter/material.dart';

import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'osc_widget_binding.dart';
import 'labeled_card.dart';

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
    // Identity: [256, 0, 0, 0, 0, 0, 0, 0]
    // Triangular: [32, 28, 24, 20, 16, 12, 8, 4] → 32 + 2*(28+24+20+16+12+8+4) = 256
    // Box: [18, 17, 17, 17, 17, 17, 17, 17] → 18 + 17*14 = 256

    const identity = [256, 0, 0, 0, 0, 0, 0, 0];
    const triangular = [32, 28, 24, 20, 16, 12, 8, 4];
    const box = [18, 17, 17, 17, 17, 17, 17, 17];

    return List<int>.generate(8, (i) {
      // Blend triangular and box based on shape
      final blur = triangular[i] + (box[i] - triangular[i]) * shape;
      // Blend identity and blur based on amount
      return (identity[i] + (blur - identity[i]) * amount).round();
    });
  }

  /// Generate blur coefficients for VAA (11-tap symmetric, 6 unique coefficients)
  /// Shape: 0 = triangular, 1 = box
  /// Amount: 0 = identity, 1 = max blur
  List<int> _vaaBlurCoeffs(double amount, double shape) {
    // Identity: [256, 0, 0, 0, 0, 0]
    // Triangular: [42, 36, 28, 22, 14, 7] → 42 + 2*(36+28+22+14+7) = 42 + 214 = 256
    // Box: [24, 23, 23, 23, 23, 23] → 24 + 23*10 = 254 ≈ 256

    const identity = [256, 0, 0, 0, 0, 0];
    const triangular = [42, 36, 28, 22, 14, 7];
    const box = [24, 23, 23, 23, 23, 23];

    return List<int>.generate(6, (i) {
      // Blend triangular and box based on shape
      final blur = triangular[i] + (box[i] - triangular[i]) * shape;
      // Blend identity and blur based on amount
      return (identity[i] + (blur - identity[i]) * amount).round();
    });
  }

  /// Generate blur coefficients for Front NR Y (15-tap symmetric, 8 unique coefficients)
  /// Uses floating point coefficients that sum to 1.0
  /// Shape: 0 = triangular, 1 = box
  /// Amount: 0 = identity, 1 = max blur
  List<double> _frontNrYBlurCoeffs(double amount, double shape) {
    // Identity: [1.0, 0, 0, 0, 0, 0, 0, 0]
    // Triangular: normalized linear decay
    // Box: [1/15, 1/15, ...] but symmetric so [2/15, 2/15, ..., 1/15 center]

    const identity = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    // Triangular: weights 8,7,6,5,4,3,2,1 normalized (sum with symmetry = 64)
    const triangular = [0.125, 0.109375, 0.09375, 0.078125, 0.0625, 0.046875, 0.03125, 0.015625];
    // Box: 1/15 each, center gets 1/15, sides get 2/15 each in symmetric form
    // Unique coeffs: center=1/15, others=1/15 (but doubled in hardware)
    // So: [1/15, 1/15, 1/15, 1/15, 1/15, 1/15, 1/15, 1/15] with symmetric doubling
    const box = [0.0667, 0.0667, 0.0667, 0.0667, 0.0667, 0.0667, 0.0667, 0.0667];

    return List<double>.generate(8, (i) {
      final blur = triangular[i] + (box[i] - triangular[i]) * shape;
      return identity[i] + (blur - identity[i]) * amount;
    });
  }

  /// Generate blur coefficients for Front NR C (7-tap symmetric, 4 unique coefficients)
  /// Uses floating point coefficients that sum to 1.0
  /// Shape: 0 = triangular, 1 = box
  /// Amount: 0 = identity, 1 = max blur
  List<double> _frontNrCBlurCoeffs(double amount, double shape) {
    // Identity: [1.0, 0, 0, 0]
    // 7-tap symmetric: c0 + 2*c1 + 2*c2 + 2*c3 = 1.0

    const identity = [1.0, 0.0, 0.0, 0.0];
    // Triangular: weights 4,3,2,1 → 4 + 2*(3+2+1) = 4 + 12 = 16, normalized
    const triangular = [0.25, 0.1875, 0.125, 0.0625];
    // Box: 1/7 each → center=1/7, sides=1/7 each
    const box = [0.143, 0.143, 0.143, 0.143];

    return List<double>.generate(4, (i) {
      final blur = triangular[i] + (box[i] - triangular[i]) * shape;
      return identity[i] + (blur - identity[i]) * amount;
    });
  }

  /// Generate sharpening kernel for H-Peak
  /// Shape: 0 = narrow (affects fine detail), 1 = wide (affects coarse detail)
  List<double> _hpeakKernel(double shape) {
    // Laplacian-style kernels: center positive, neighbors negative
    // Narrow (fine detail): [1.0, -0.5, 0, 0, 0, 0, 0, 0]
    // Wide (coarse detail): [1.0, -0.3, -0.2, -0.15, -0.1, -0.05, 0, 0]

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
      // Blur mode: stack Front NR and HAA for maximum range
      final blurAmount = _hBlur;

      // Front NR Y: apply blur based on amount
      final frontNrYCoeffs = _frontNrYBlurCoeffs(blurAmount, _hBlurShape);
      sendOsc(frontNrYCoeffs, address: 'filter/front_nr/y');
      sendOsc(true, address: 'filter/front_nr/enable_y');
      sendOsc(false, address: 'filter/front_nr/bypass_y');

      // Front NR C: apply matching blur to keep Y/C aligned
      final frontNrCCoeffs = _frontNrCBlurCoeffs(blurAmount, _hBlurShape);
      sendOsc(frontNrCCoeffs, address: 'filter/front_nr/c');
      sendOsc(true, address: 'filter/front_nr/enable_c');
      sendOsc(false, address: 'filter/front_nr/bypass_cb');
      sendOsc(false, address: 'filter/front_nr/bypass_cr');

      // HAA: stack on top for extra blur (Y only - HAA C has issues)
      final haaCoeffs = _haaBlurCoeffs(blurAmount, _hBlurShape);
      sendOsc(haaCoeffs, address: 'filter/haa/y');
      sendOsc(true, address: 'filter/haa/enable_y');
    } else {
      // No blur: disable blur filters, reset Front NR to identity
      sendOsc(false, address: 'filter/haa/enable_y');
      sendOsc(const [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], address: 'filter/front_nr/y');
      sendOsc(const [1.0, 0.0, 0.0, 0.0], address: 'filter/front_nr/c');
      sendOsc(true, address: 'filter/front_nr/enable_y');  // Keep enabled as master
      sendOsc(false, address: 'filter/front_nr/bypass_y');
    }
  }

  void _applyHorizontalSharpen() {
    if (_hSharp > 0.001) {
      // Sharpen mode: use H-Peak with shape-controlled kernel
      final kernel = _hpeakKernel(_hSharpShape);
      sendOsc(kernel, address: 'filter/h_peak/coef');
      sendOsc(0, address: 'filter/h_peak/gain_thres');
      sendOsc(0, address: 'filter/h_peak/gain_offset');

      // Gain scales with amount (max 1.8 to avoid overflow)
      final gain = _hSharp * 1.8;
      sendOsc(gain, address: 'filter/h_peak/gain');
      sendOsc(true, address: 'filter/h_peak/enable');
    } else {
      // No sharpening
      sendOsc(false, address: 'filter/h_peak/enable');
    }
  }

  void _applyVerticalBlur() {
    if (_vBlur > 0.001) {
      // Blur mode: use VAA
      final coeffs = _vaaBlurCoeffs(_vBlur, _vBlurShape);
      debugPrint('VAA blur: amount=$_vBlur shape=$_vBlurShape coeffs=$coeffs');

      // Send coefficients first (stored but not applied), then enable triggers apply_vaa
      sendOsc(coeffs, address: 'filter/vaa/y');
      sendOsc(true, address: 'filter/vaa/enable_y');
    } else {
      // No blur: disable VAA
      sendOsc(false, address: 'filter/vaa/enable_y');
    }
  }

  void _applyVerticalSharpen() {
    if (_vSharp > 0.001) {
      // Sharpen mode: use V-Peak
      // Fixed divider (mid-range)
      sendOsc(4, address: 'filter/v_peak/gain_div');

      // Gain scales with amount (0-1.96875 range to fit in 6-bit register)
      // Register is 6 bits (0-63), scaled so 1.0 = 32, max = 63/32 = 1.96875
      final gain = (_vSharp * 1.96875).clamp(0.0, 1.96875);
      sendOsc(gain, address: 'filter/v_peak/gain');
    } else {
      // No sharpening
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
    return OscRotaryKnob(
      key: ValueKey('$label-$_resetCount'),
      initialValue: value,
      minValue: minValue,
      maxValue: maxValue,
      format: '%.2f',
      label: label,
      defaultValue: 0,
      size: _dialSize,
      labelStyle: _knobLabelStyle,
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

  // Grid constants — match shape.dart
  static const double _dialSize = 50;
  static const double _knobGap = 12;
  static const EdgeInsets _panelPadding = EdgeInsets.fromLTRB(6, 6, 6, 4);
  static const TextStyle _knobLabelStyle = TextStyle(
    fontSize: 11,
    color: Color(0xFF999999),
  );
  static const Color _iconColor = Color(0xFF888888);
  static const double _iconSize = 14;

  Widget _iconRow(String tooltip, IconData icon, List<Widget> knobs) {
    return NeumorphicInset(
      padding: _panelPadding,
      child: Row(
        children: [
          Tooltip(
            message: tooltip,
            child: Icon(icon, size: _iconSize, color: _iconColor),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < knobs.length; i++) ...[
                  if (i > 0) SizedBox(width: _knobGap),
                  knobs[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _iconRow('Horizontal Blur', Icons.blur_linear, [
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
              const SizedBox(width: 8),
              Expanded(
                child: _iconRow('Horizontal Sharpening', Icons.deblur, [
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
        ),
        const SizedBox(height: 8),
        _iconRow('Vertical', Icons.swap_vert, [
          _knob(
            label: 'Blur',
            value: _vBlur,
            minValue: 0.0,
            maxValue: 1.0,
            onChanged: (v) {
              setState(() => _vBlur = v);
              _applyVerticalBlur();
            },
          ),
          _knob(
            label: 'Blur Shp',
            value: _vBlurShape,
            minValue: 0.0,
            maxValue: 1.0,
            snapPoints: const [0.5],
            onChanged: (v) {
              setState(() => _vBlurShape = v);
              _applyVerticalBlur();
            },
          ),
          _knob(
            label: 'Sharp',
            value: _vSharp,
            minValue: 0.0,
            maxValue: 1.0,
            onChanged: (v) {
              setState(() => _vSharp = v);
              _applyVerticalSharpen();
            },
          ),
        ]),
      ],
    );
  }
}
