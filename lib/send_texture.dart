import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dart:math' as math;

import 'osc_checkbox.dart';
import 'numeric_slider.dart';
import 'osc_widget_binding.dart';
import 'osc_registry.dart';
import 'network.dart';
import 'osc_log.dart';

class AbsoluteOscCheckbox extends StatefulWidget {
  final String address;
  const AbsoluteOscCheckbox({super.key, required this.address});

  @override
  State<AbsoluteOscCheckbox> createState() => _AbsoluteOscCheckboxState();
}

class _AbsoluteOscCheckboxState extends State<AbsoluteOscCheckbox> {
  bool _value = false;

  void _listener(List<Object?> args) {
    if (args.isNotEmpty && args.first is bool) {
      setState(() => _value = args.first as bool);
      if (!OscRegistry().isLogSuppressed(widget.address)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oscLogKey.currentState?.logOscMessage(
            address: widget.address,
            arg: args,
            status: OscStatus.ok,
            direction: Direction.received,
            binary: Uint8List(0),
          );
        });
      }
    } else {
      if (!OscRegistry().isLogSuppressed(widget.address)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oscLogKey.currentState?.logOscMessage(
            address: widget.address,
            arg: args,
            status: OscStatus.error,
            direction: Direction.received,
            binary: Uint8List(0),
          );
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    OscRegistry().registerAddress(widget.address);
    OscRegistry().registerListener(widget.address, _listener);
  }

  @override
  void dispose() {
    OscRegistry().unregisterListener(widget.address, _listener);
    super.dispose();
  }

  void _send(bool val) {
    context.read<Network>().sendOscMessage(widget.address, [val]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oscLogKey.currentState?.logOscMessage(
        address: widget.address,
        arg: [val],
        status: OscStatus.ok,
        direction: Direction.sent,
        binary: Uint8List(0),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: _value,
      onChanged: (val) {
        if (val == null) return;
        setState(() => _value = val);
        _send(val);
      },
    );
  }
}

class _IndexedSliders extends StatelessWidget {
  final String segment;
  final int length;
  final RangeValues range;
  final int precision;

  const _IndexedSliders({
    required this.segment,
    required this.length,
    this.range = const RangeValues(-1, 1),
    this.precision = 3,
  });

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: segment,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: List.generate(length, (i) {
          return SizedBox(
            width: 60,
            height: 24,
            child: OscPathSegment(
              segment: '$i',
              child: NumericSlider(
                value: range.start,
                range: range,
                precision: precision,
                onChanged: (v) {},
              ),
            ),
          );
        }),
      ),
    );
  }
}

class SendTexture extends StatelessWidget {
  const SendTexture({super.key});

  Widget _checkboxRow(String label, String segment) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        OscPathSegment(segment: segment, child: const OscCheckbox()),
      ],
    );
  }

  Widget _floatSliderRow(
    String label,
    String segment, {
    RangeValues range = const RangeValues(0, 1),
    int precision = 3,
  }) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        SizedBox(
          width: 60,
          height: 24,
          child: OscPathSegment(
            segment: segment,
            child: NumericSlider(
              value: range.start,
              range: range,
              precision: precision,
              onChanged: (v) {},
            ),
          ),
        ),
      ],
    );
  }

  Widget _intSliderRow(
    String label,
    String segment, {
    RangeValues range = const RangeValues(0, 255),
  }) => _floatSliderRow(label, segment, range: range, precision: 0);

  Widget _frontNrSection() {
    return OscPathSegment(
      segment: 'front_nr',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 120, child: Text('Enable Y')),
              OscPathSegment(segment: 'enable_y', child: const OscCheckbox()),
              const SizedBox(width: 32),
              const SizedBox(width: 120, child: Text('Enable C')),
              OscPathSegment(segment: 'enable_c', child: const OscCheckbox()),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 120, child: Text('Bypass Y')),
              OscPathSegment(segment: 'bypass_y', child: const OscCheckbox()),
              const SizedBox(width: 32),
              const SizedBox(width: 120, child: Text('Bypass Cb')),
              OscPathSegment(segment: 'bypass_cb', child: const OscCheckbox()),
              const SizedBox(width: 32),
              const SizedBox(width: 120, child: Text('Bypass Cr')),
              OscPathSegment(segment: 'bypass_cr', child: const OscCheckbox()),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Front NR (Y)'),
          // Designer for Y (15-tap, 8 unique, index 0 = center)
          const _FrontNrDesigner(channel: 'y', taps: 15),
          const SizedBox(height: 8),
          const Text('Front NR (C)'),
          // Designer for C (7-tap, 4 unique, index 0 = center)
          const _FrontNrDesigner(channel: 'c', taps: 7),
        ],
      ),
    );
  }

  Widget _hPeakSection() {
    return OscPathSegment(
      segment: 'h_peak',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Coefficients'),
          const _IndexedSliders(segment: 'coef', length: 8),
          const SizedBox(height: 8),
          _floatSliderRow('Gain', 'gain'),
          _checkboxRow('Gain Level En', 'gain_level_en'),
          _checkboxRow('Hact Sep', 'hact_sep'),
          _checkboxRow('No Add', 'no_add'),
          _checkboxRow('Reverse', 'reverse'),
          _intSliderRow('Cor Val', 'cor_val'),
          _intSliderRow('Sat Val', 'sat_val'),
          _checkboxRow('Cor Half', 'cor_half'),
          _checkboxRow('Cor En', 'cor_en'),
          _checkboxRow('Sat En', 'sat_en'),
          _checkboxRow('Enable', 'enable'),
          _intSliderRow('Gain Slope', 'gain_slope'),
          _intSliderRow('Gain Thres', 'gain_thres'),
          _intSliderRow('Gain Offset', 'gain_offset'),
        ],
      ),
    );
  }

  Widget _vPeakSection() {
    return OscPathSegment(
      segment: 'v_peak',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _checkboxRow('Enable', 'enable'),
          _floatSliderRow('Gain', 'gain'),
          _intSliderRow('Gain Div', 'gain_div'),
          _intSliderRow('V Delay', 'v_dly'),
          _intSliderRow('H Delay', 'h_dly'),
          _floatSliderRow('Gain Clip Low', 'gain_clip_low'),
          _floatSliderRow('Gain Clip High', 'gain_clip_high'),
          _floatSliderRow('Out Clip Low', 'out_clip_low'),
          _floatSliderRow('Out Clip High', 'out_clip_high'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'filter',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _frontNrSection(),
          const SizedBox(height: 8),
          _hPeakSection(),
          const SizedBox(height: 8),
          _vPeakSection(),
        ],
      ),
    );
  }
}

enum _FilterType { lowpass, highpass, bandpass }

class _FrontNrDesigner extends StatefulWidget {
  final String channel; // 'y' or 'c'
  final int taps;       // 15 for Y, 7 for C

  const _FrontNrDesigner({super.key, required this.channel, required this.taps});

  @override
  State<_FrontNrDesigner> createState() => _FrontNrDesignerState();
}

class _FrontNrDesignerState extends State<_FrontNrDesigner> with OscAddressMixin {
  _FilterType _type = _FilterType.lowpass;
  double _freq = 0.10; // normalized (0..0.5)
  double _q = 2.0;     // generic slope/bandwidth control
  double _amount = 1.0; // effect strength (0=no change, 1=normal, >1=strong)
  double _dc = 1.0;     // DC pass mix for HP/BP (0..1.5)

  int get _halfLen => (widget.taps - 1) ~/ 2; // M

  // Map Q to window shape: low Q → Blackman, mid → Hamming, high → Rectangular
  // Returns (a0, a1, a2) for generalized cosine window: a0 - a1*cos(2πn/N-1) + a2*cos(4πn/N-1)
  List<double> _windowCoeffsFromQ(double q) {
    const double qMin = 0.5;
    const double qMax = 10.0;
    final t = ((q - qMin) / (qMax - qMin)).clamp(0.0, 1.0);
    // Blackman
    const b0 = 0.42, b1 = 0.50, b2 = 0.08;
    // Hamming
    const h0 = 0.54, h1 = 0.46, h2 = 0.0;
    // Rectangular
    const r0 = 1.0, r1 = 0.0, r2 = 0.0;
    if (t < 0.5) {
      final u = t / 0.5; // 0..1 from Blackman→Hamming
      final a0 = b0 + (h0 - b0) * u;
      final a1 = b1 + (h1 - b1) * u;
      final a2 = b2 + (h2 - b2) * u;
      return [a0, a1, a2];
    } else {
      final u = (t - 0.5) / 0.5; // 0..1 from Hamming→Rectangular
      final a0 = h0 + (r0 - h0) * u;
      final a1 = h1 + (r1 - h1) * u;
      final a2 = h2 + (r2 - h2) * u;
      return [a0, a1, a2];
    }
  }

  List<double> _designLowpass(int nTaps, double fc, double q) {
    final N = nTaps;
    final M = (N - 1) ~/ 2;
    // Clamp frequency to a valid range, allow exact 0 for identity
    final f = fc.clamp(0.0, 0.4999);
    if (f <= 1e-12) {
      return List<double>.generate(N, (i) => i == M ? 1.0 : 0.0);
    }
    final coeffs = List<double>.filled(N, 0.0);
    final wc = _windowCoeffsFromQ(q);
    for (int i = 0; i < N; i++) {
      final n = i - M;
      final x = 2.0 * f * n;
      final sinc = (n == 0)
          ? 1.0
          : math.sin(math.pi * x) / (math.pi * x);
      final ideal = 2.0 * f * sinc; // ideal LP
      // generalized cosine window
      final w = wc[0]
          - wc[1] * math.cos((2 * math.pi * i) / (N - 1))
          + wc[2] * math.cos((4 * math.pi * i) / (N - 1));
      coeffs[i] = ideal * w;
    }
    // Normalize DC gain to 1
    final sum = coeffs.fold<double>(0.0, (a, b) => a + b);
    if (sum.abs() > 1e-12) {
      for (int i = 0; i < N; i++) coeffs[i] /= sum;
    }
    return coeffs;
  }

  List<double> _designHighpass(int nTaps, double fc, double q) {
    // Classic spectral-inversion HP (zero-DC): hp0 = δ - lp
    final lp = _designLowpass(nTaps, fc, q);
    final N = nTaps;
    final M = (N - 1) ~/ 2;
    final hp0 = List<double>.generate(N, (i) => (i == M ? 1.0 : 0.0) - lp[i]);
    return hp0;
  }

  List<double> _designBandpass(int nTaps, double f0, double q) {
    // For BP, Q = f0 / BW -> BW = f0 / Q
    final fCenter = f0.clamp(0.0, 0.499);
    if (fCenter <= 1e-12) {
      return List<double>.filled(nTaps, 0.0);
    }
    final bw = (fCenter / q).clamp(0.005, 0.49);
    double f1 = (fCenter - bw / 2).clamp(0.0, 0.49);
    double f2 = (fCenter + bw / 2).clamp(0.0, 0.49);
    if (f2 <= f1 + 1e-6) {
      f2 = (f1 + 0.005).clamp(0.006, 0.49);
    }
    final lp2 = _designLowpass(nTaps, f2, q);
    final lp1 = _designLowpass(nTaps, f1, q);
    final bp0 = List<double>.generate(nTaps, (i) => lp2[i] - lp1[i]);
    return bp0;
  }

  List<double> _uniqueFromFull(List<double> h) {
    final N = h.length;
    final M = (N - 1) ~/ 2;
    // Index 0 corresponds to center tap, then move outward
    final unique = List<double>.generate(M + 1, (k) => h[M - k]);
    return unique;
  }

  void _sendCoeffs(String channel, List<double> unique) {
    // Use OscAddressMixin to send relative to '/.../front_nr'
    for (int i = 0; i < unique.length; i++) {
      sendOsc(unique[i], address: '$channel/$i');
    }
  }

  void _computeAndSend() {
    final N = widget.taps;
    List<double> h;
    // delta (identity) kernel
    final M = (N - 1) ~/ 2;
    final delta = List<double>.generate(N, (i) => i == M ? 1.0 : 0.0);
    switch (_type) {
      case _FilterType.lowpass:
        final lp = _designLowpass(N, _freq, _q);
        // Blend identity with lowpass for controllable smoothing
        // h = (1-amount)*δ + amount*lp
        h = List<double>.generate(N, (i) => (1.0 - _amount) * delta[i] + _amount * lp[i]);
        break;
      case _FilterType.highpass:
        final hp0 = _designHighpass(N, _freq, _q); // zero-DC
        // h = dc*δ + amount*hp0
        h = List<double>.generate(N, (i) => _dc * delta[i] + _amount * hp0[i]);
        break;
      case _FilterType.bandpass:
        final bp0 = _designBandpass(N, _freq, _q); // zero-DC
        // h = dc*δ + amount*bp0
        h = List<double>.generate(N, (i) => _dc * delta[i] + _amount * bp0[i]);
        break;
    }
    final u = _uniqueFromFull(h);
    _sendCoeffs(widget.channel, u);
    // Ensure channel is enabled and not bypassed for immediate effect
    if (widget.channel == 'y') {
      sendOsc(true, address: 'enable_y');
      sendOsc(false, address: 'bypass_y');
    } else if (widget.channel == 'c') {
      sendOsc(true, address: 'enable_c');
      sendOsc(false, address: 'bypass_cb');
      sendOsc(false, address: 'bypass_cr');
    }
  }

  Widget _radioChoice(_FilterType value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<_FilterType>(
          value: value,
          groupValue: _type,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) {
            if (v == null) return;
            setState(() => _type = v);
            _computeAndSend();
          },
        ),
        Text(label),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _labelledSlider({
    required String label,
    required double value,
    required RangeValues range,
    required int precision,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        SizedBox(
          width: 100,
          height: 24,
          child: NumericSlider(
            value: value,
            range: range,
            precision: precision,
            sendOsc: false,
            onChanged: (v) => onChanged(v),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 120, child: Text('Filter Type')),
            _radioChoice(_FilterType.lowpass, 'Low Pass'),
            _radioChoice(_FilterType.highpass, 'High Pass'),
            _radioChoice(_FilterType.bandpass, 'Band Pass'),
          ],
        ),
        const SizedBox(height: 4),
        _labelledSlider(
          label: 'Frequency',
          value: _freq,
          range: const RangeValues(0.0, 0.49),
          precision: 3,
          onChanged: (v) {
            setState(() => _freq = v);
            _computeAndSend();
          },
        ),
        const SizedBox(height: 4),
        _labelledSlider(
          label: 'Amount',
          value: _amount,
          range: const RangeValues(0.0, 3.0),
          precision: 2,
          onChanged: (v) {
            setState(() => _amount = v);
            _computeAndSend();
          },
        ),
        const SizedBox(height: 4),
        _labelledSlider(
          label: 'Q',
          value: _q,
          range: const RangeValues(0.5, 10.0),
          precision: 2,
          onChanged: (v) {
            setState(() => _q = v);
            _computeAndSend();
          },
        ),
        if (_type != _FilterType.lowpass) ...[
          const SizedBox(height: 4),
          _labelledSlider(
            label: 'DC Pass',
            value: _dc,
            range: const RangeValues(0.0, 1.5),
            precision: 2,
            onChanged: (v) {
              setState(() => _dc = v);
              _computeAndSend();
            },
          ),
        ],
      ],
    );
  }
}
