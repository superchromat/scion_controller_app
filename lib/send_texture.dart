import 'package:flutter/material.dart';

import 'dart:math' as math;

import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'osc_widget_binding.dart';

/// Simplified texture controls with knobs:
/// - H Texture: -1 (blur) to +1 (edges) via Front NR Y FIR
/// - H Sharpen: 0 to 1 via H-Peak gain
/// - C Blur: 0 to 1 via Front NR C lowpass
/// - Focus Peak: 0 to 1 enables focus peaking (colored edge overlay) via MDIN Monitor
class SendTexture extends StatefulWidget {
  const SendTexture({super.key});

  @override
  State<SendTexture> createState() => _SendTextureState();
}

class _SendTextureState extends State<SendTexture> with OscAddressMixin {
  // Knob values
  double _hTexture = 0.0;  // -1 (blur) to +1 (edges)
  double _hSharpen = 0.0;  // 0 to 1
  double _focusPeak = 0.0; // 0 to 1 - Focus peaking (colored edge overlay)
  double _vSharpen = 0.0;  // 0 to 1 - V-Peak combined gain/divider
  double _hBlurY = 0.0;    // 0 to 1 - HAA luma blur
  double _hBlurC = 0.0;    // 0 to 1 - HAA chroma blur
  double _vBlurY = 0.0;    // 0 to 1 - VAA luma blur

  // Fixed Q value for filter design (mid-range Hamming-ish window)
  static const double _filterQ = 3.0;

  // FIR design constants
  static const int _yTaps = 15;  // Luma FIR length
  static const int _cTaps = 7;   // Chroma FIR length

  //----------------------------------------------------------------------------
  // FIR Filter Design (adapted from original _FrontNrDesigner)
  //----------------------------------------------------------------------------

  List<double> _windowCoeffs(double q) {
    const double qMin = 0.5;
    const double qMax = 10.0;
    final t = ((q - qMin) / (qMax - qMin)).clamp(0.0, 1.0);
    // Blackman → Hamming → Rectangular
    const b0 = 0.42, b1 = 0.50, b2 = 0.08;
    const h0 = 0.54, h1 = 0.46, h2 = 0.0;
    const r0 = 1.0, r1 = 0.0, r2 = 0.0;
    if (t < 0.5) {
      final u = t / 0.5;
      return [b0 + (h0 - b0) * u, b1 + (h1 - b1) * u, b2 + (h2 - b2) * u];
    } else {
      final u = (t - 0.5) / 0.5;
      return [h0 + (r0 - h0) * u, h1 + (r1 - h1) * u, h2 + (r2 - h2) * u];
    }
  }

  List<double> _designLowpass(int nTaps, double fc, double q) {
    final N = nTaps;
    final M = (N - 1) ~/ 2;
    final f = fc.clamp(0.0, 0.4999);
    if (f <= 1e-12) {
      return List<double>.generate(N, (i) => i == M ? 1.0 : 0.0);
    }
    final coeffs = List<double>.filled(N, 0.0);
    final wc = _windowCoeffs(q);
    for (int i = 0; i < N; i++) {
      final n = i - M;
      final x = 2.0 * f * n;
      final sinc = (n == 0) ? 1.0 : math.sin(math.pi * x) / (math.pi * x);
      final ideal = 2.0 * f * sinc;
      final w = wc[0]
          - wc[1] * math.cos((2 * math.pi * i) / (N - 1))
          + wc[2] * math.cos((4 * math.pi * i) / (N - 1));
      coeffs[i] = ideal * w;
    }
    final sum = coeffs.fold<double>(0.0, (a, b) => a + b);
    if (sum.abs() > 1e-12) {
      for (int i = 0; i < N; i++) {
        coeffs[i] /= sum;
      }
    }
    return coeffs;
  }

  List<double> _designHighpass(int nTaps, double fc, double q) {
    final lp = _designLowpass(nTaps, fc, q);
    final N = nTaps;
    final M = (N - 1) ~/ 2;
    return List<double>.generate(N, (i) => (i == M ? 1.0 : 0.0) - lp[i]);
  }

  List<double> _uniqueFromFull(List<double> h) {
    final N = h.length;
    final M = (N - 1) ~/ 2;
    return List<double>.generate(M + 1, (k) => h[M - k]);
  }

  //----------------------------------------------------------------------------
  // OSC Sending
  //----------------------------------------------------------------------------

  void _sendFrontNrCoeffs(String channel, List<double> unique) {
    // Send as array in single OSC message
    sendOsc(unique, address: 'filter/front_nr/$channel');
  }

  void _applyHTexture() {
    final N = _yTaps;
    final M = (N - 1) ~/ 2;
    final delta = List<double>.generate(N, (i) => i == M ? 1.0 : 0.0);

    List<double> h;
    if (_hTexture <= 0) {
      // Blur mode: -1 = max blur, 0 = identity
      final amount = -_hTexture; // 0 to 1

      // At -1.0: box filter (all coefficients = 1/16)
      // Blend from identity toward box filter
      const boxCoeff = 1.0 / 16.0;
      final box = List<double>.filled(N, boxCoeff);
      h = List<double>.generate(N, (i) =>
          (1.0 - amount) * delta[i] + amount * box[i]);
    } else {
      // Edge mode: 0 = identity, +1 = max edges
      // Map texture to highpass frequency: 0 → identity, +1 → highpass at 0.15
      final amount = _hTexture; // 0 to 1
      final freq = 0.05 + (0.10 * amount); // 0.05 to 0.15
      final hp = _designHighpass(N, freq, _filterQ);
      // Blend identity with highpass; keep some DC to avoid pure edge detection
      final dcMix = 1.0 - (0.7 * amount); // 1.0 down to 0.3
      h = List<double>.generate(N, (i) => dcMix * delta[i] + amount * hp[i]);
    }

    final u = _uniqueFromFull(h);
    _sendFrontNrCoeffs('y', u);

    // Always keep enable_y=true - it acts as master enable for the Front NR block
    // (required for C Blur to work). Identity coefficients at _hTexture=0 pass through unchanged.
    sendOsc(true, address: 'filter/front_nr/enable_y');
    sendOsc(false, address: 'filter/front_nr/bypass_y');

    // Auto-enable LTI when in edge mode
    sendOsc(_hTexture > 0.3, address: 'lti');
  }

  void _applyHSharpen() {
    if (_hSharpen < 0.01) {
      sendOsc(false, address: 'filter/h_peak/enable');
      return;
    }

    // Use fixed sharpening kernel (Laplacian-style)
    // Center positive, neighbors negative = edge detection
    // Format: [center, side1, side2, side3, side4, side5, side6, side7]
    const sharpKernel = [1.0, -0.5, -0.25, -0.1, 0.0, 0.0, 0.0, 0.0];
    sendOsc(sharpKernel, address: 'filter/h_peak/coef');

    // Disable threshold so subtle sharpening isn't suppressed
    sendOsc(0, address: 'filter/h_peak/gain_thres');
    sendOsc(0, address: 'filter/h_peak/gain_offset');

    // Gain controls intensity - overflow occurred at ~2.0, limit below that
    final gain = _hSharpen * 1.8;
    sendOsc(gain, address: 'filter/h_peak/gain');
    sendOsc(true, address: 'filter/h_peak/enable');
  }

  void _applyVSharpen() {
    // Single knob controls both gain and divider for smooth progression
    // Effect strength ≈ gain / 2^divider
    //
    // At knob=0: off
    // At knob=0.5: moderate sharpening
    // At knob=1.0: strong sharpening

    if (_vSharpen < 0.01) {
      sendOsc(0.0, address: 'filter/v_peak/gain');
      return;
    }

    // Divider: starts at 6, decreases to 2 as knob increases
    final divider = (6 - (_vSharpen * 4)).round().clamp(2, 6);

    // Gain: increases with knob position (0-2 range)
    final gain = _vSharpen * 2.0;

    sendOsc(divider, address: 'filter/v_peak/gain_div');
    sendOsc(gain, address: 'filter/v_peak/gain');
  }


  void _applyHBlurY() {
    if (_hBlurY < 0.01) {
      // Disable HAA Y channel
      sendOsc(false, address: 'filter/haa/enable_y');
      return;
    }

    // HAA is 15-tap symmetric filter (8 unique coefficients), 10-bit values (0-1023)
    // Total weight with symmetric doubling: c0 + 2*c1 + 2*c2 + ... + 2*c7 = sum
    // For normalized unity gain: sum should equal 256
    //
    // Identity: [256, 0, 0, 0, 0, 0, 0, 0] → 256 total (matches firmware default)
    // 15-tap box: [18, 17, 17, 17, 17, 17, 17, 17] → 18 + 17*14 = 256
    const identityCenter = 256;
    const boxCenter = 18;
    const boxSide = 17;

    final coeffs = List<int>.generate(8, (i) {
      final identity = (i == 0) ? identityCenter : 0;
      final box = (i == 0) ? boxCenter : boxSide;
      return ((1.0 - _hBlurY) * identity + _hBlurY * box).round();
    });
    sendOsc(coeffs, address: 'filter/haa/y');

    sendOsc(true, address: 'filter/haa/enable_y');
  }

  void _applyHBlurC() {
    if (_hBlurC < 0.01) {
      // Disable HAA C channel
      sendOsc(false, address: 'filter/haa/enable_c');
      return;
    }

    // HAA chroma is 7-tap (4 unique coefficients) - last 4 MUST be zero
    // or image gets green tint. This applies even for 4:4:4 video.
    // Total weight with symmetric doubling: c0 + 2*c1 + 2*c2 + 2*c3 = sum
    // For normalized unity gain: sum should equal 256
    //
    // Identity: [256, 0, 0, 0, 0, 0, 0, 0] → 256 total
    // 7-tap box: [38, 36, 36, 36, 0, 0, 0, 0] → 38 + 36*6 = 254 ≈ 256
    const identityCenter = 256;
    const boxCenter = 38;
    const boxSide = 36;

    final coeffs = List<int>.generate(8, (i) {
      if (i >= 4) return 0;  // Last 4 must be zero!
      final identity = (i == 0) ? identityCenter : 0;
      final box = (i == 0) ? boxCenter : boxSide;
      return ((1.0 - _hBlurC) * identity + _hBlurC * box).round();
    });
    sendOsc(coeffs, address: 'filter/haa/c');
    sendOsc(true, address: 'filter/haa/enable_c');
  }

  void _applyVBlurY() {
    if (_vBlurY < 0.01) {
      // Disable VAA Y channel
      sendOsc(false, address: 'filter/vaa/enable_y');
      return;
    }

    // VAA is 11-tap symmetric filter (6 unique coefficients), 10-bit values (0-1023)
    // Total weight with symmetric doubling: c0 + 2*c1 + 2*c2 + 2*c3 + 2*c4 + 2*c5 = sum
    // For normalized unity gain: sum should equal 256
    //
    // Identity: [256, 0, 0, 0, 0, 0] → 256 total
    // 11-tap box: [24, 23, 23, 23, 23, 23] → 24 + 23*10 = 254 ≈ 256
    const identityCenter = 256;
    const boxCenter = 24;
    const boxSide = 23;

    final coeffs = List<int>.generate(6, (i) {
      final identity = (i == 0) ? identityCenter : 0;
      final box = (i == 0) ? boxCenter : boxSide;
      return ((1.0 - _vBlurY) * identity + _vBlurY * box).round();
    });
    debugPrint('V Blur Y=$_vBlurY coeffs=$coeffs');
    sendOsc(coeffs, address: 'filter/vaa/y');

    sendOsc(true, address: 'filter/vaa/enable_y');
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
      initialValue: value,
      minValue: minValue,
      maxValue: maxValue,
      format: '%.2f',
      label: label,
      defaultValue: 0,
      size: 60,
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

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        _knob(
          label: 'H Texture',
          value: _hTexture,
          minValue: -1.0,
          maxValue: 1.0,
          snapPoints: const [0.0],
          onChanged: (v) {
            setState(() => _hTexture = v);
            _applyHTexture();
          },
        ),
        _knob(
          label: 'H Sharpen',
          value: _hSharpen,
          minValue: 0.0,
          maxValue: 1.0,
          snapPoints: const [0.0],
          onChanged: (v) {
            setState(() => _hSharpen = v);
            _applyHSharpen();
          },
        ),
        _knob(
          label: 'V Sharp',
          value: _vSharpen,
          minValue: 0.0,
          maxValue: 1.0,
          snapPoints: const [0.0],
          onChanged: (v) {
            setState(() => _vSharpen = v);
            _applyVSharpen();
          },
        ),
        _knob(
          label: 'H Blur Y',
          value: _hBlurY,
          minValue: 0.0,
          maxValue: 1.0,
          snapPoints: const [0.0],
          onChanged: (v) {
            setState(() => _hBlurY = v);
            _applyHBlurY();
          },
        ),
        _knob(
          label: 'H Blur C',
          value: _hBlurC,
          minValue: 0.0,
          maxValue: 1.0,
          snapPoints: const [0.0],
          onChanged: (v) {
            setState(() => _hBlurC = v);
            _applyHBlurC();
          },
        ),
        _knob(
          label: 'V Blur Y',
          value: _vBlurY,
          minValue: 0.0,
          maxValue: 1.0,
          snapPoints: const [0.0],
          onChanged: (v) {
            setState(() => _vBlurY = v);
            _applyVBlurY();
          },
        ),
      ],
    );
  }
}
