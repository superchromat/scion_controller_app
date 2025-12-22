import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dart:math' as math;

import 'osc_checkbox.dart';
import 'osc_radiolist.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
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

class _IndexedKnobs extends StatelessWidget {
  final String segment;
  final int length;
  final double minValue;
  final double maxValue;
  final int precision;

  const _IndexedKnobs({
    required this.segment,
    required this.length,
    this.minValue = -1,
    this.maxValue = 1,
    this.precision = 3,
  });

  @override
  Widget build(BuildContext context) {
    final format = '%.${precision}f';
    return OscPathSegment(
      segment: segment,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(length, (i) {
          return OscPathSegment(
            segment: '$i',
            child: OscRotaryKnob(
              initialValue: 0,
              minValue: minValue,
              maxValue: maxValue,
              format: format,
              label: '$i',
              defaultValue: 0,
              size: 45,
              isBipolar: minValue < 0,
              snapConfig: SnapConfig(
                snapPoints: const [0.0],
                snapRegionHalfWidth: (maxValue - minValue) * 0.02,
                snapBehavior: SnapBehavior.hard,
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

  Widget _floatKnobRow(
    String label,
    String segment, {
    double minValue = 0,
    double maxValue = 1,
    int precision = 3,
  }) {
    final format = '%.${precision}f';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OscPathSegment(
          segment: segment,
          child: OscRotaryKnob(
            initialValue: minValue,
            minValue: minValue,
            maxValue: maxValue,
            format: format,
            label: label,
            defaultValue: minValue,
            size: 50,
            isBipolar: minValue < 0,
          ),
        ),
      ],
    );
  }

  Widget _intKnobRow(
    String label,
    String segment, {
    double minValue = 0,
    double maxValue = 255,
  }) => _floatKnobRow(label, segment, minValue: minValue, maxValue: maxValue, precision: 0);

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
          const _IndexedKnobs(segment: 'coef', length: 8),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _floatKnobRow('Gain', 'gain'),
              _intKnobRow('Cor Val', 'cor_val'),
              _intKnobRow('Sat Val', 'sat_val'),
              _intKnobRow('Gain Slope', 'gain_slope'),
              _intKnobRow('Gain Thres', 'gain_thres'),
              _intKnobRow('Gain Offset', 'gain_offset'),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _checkboxRow('Enable', 'enable'),
              _checkboxRow('Gain Level En', 'gain_level_en'),
              _checkboxRow('Hact Sep', 'hact_sep'),
              _checkboxRow('No Add', 'no_add'),
              _checkboxRow('Reverse', 'reverse'),
              _checkboxRow('Cor Half', 'cor_half'),
              _checkboxRow('Cor En', 'cor_en'),
              _checkboxRow('Sat En', 'sat_en'),
            ],
          ),
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _floatKnobRow('Gain', 'gain'),
              _intKnobRow('Gain Div', 'gain_div'),
              _intKnobRow('V Delay', 'v_dly'),
              _intKnobRow('H Delay', 'h_dly'),
              _floatKnobRow('Gain Clip Low', 'gain_clip_low'),
              _floatKnobRow('Gain Clip High', 'gain_clip_high'),
              _floatKnobRow('Out Clip Low', 'out_clip_low'),
              _floatKnobRow('Out Clip High', 'out_clip_high'),
            ],
          ),
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
        NeumorphicRadio<_FilterType>(
          value: value,
          groupValue: _type,
          size: 18,
          onChanged: (v) {
            setState(() => _type = v);
            _computeAndSend();
          },
        ),
        const SizedBox(width: 6),
        Text(label),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _labelledKnob({
    required String label,
    required double value,
    required double minValue,
    required double maxValue,
    required int precision,
    required ValueChanged<double> onChanged,
  }) {
    final format = '%.${precision}f';
    return OscRotaryKnob(
      initialValue: value,
      minValue: minValue,
      maxValue: maxValue,
      format: format,
      label: label,
      defaultValue: value,
      size: 50,
      sendOsc: false,
      isBipolar: minValue < 0,
      onChanged: onChanged,
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _labelledKnob(
              label: 'Frequency',
              value: _freq,
              minValue: 0.0,
              maxValue: 0.49,
              precision: 3,
              onChanged: (v) {
                setState(() => _freq = v);
                _computeAndSend();
              },
            ),
            _labelledKnob(
              label: 'Amount',
              value: _amount,
              minValue: 0.0,
              maxValue: 3.0,
              precision: 2,
              onChanged: (v) {
                setState(() => _amount = v);
                _computeAndSend();
              },
            ),
            _labelledKnob(
              label: 'Q',
              value: _q,
              minValue: 0.5,
              maxValue: 10.0,
              precision: 2,
              onChanged: (v) {
                setState(() => _q = v);
                _computeAndSend();
              },
            ),
            if (_type != _FilterType.lowpass)
              _labelledKnob(
                label: 'DC Pass',
                value: _dc,
                minValue: 0.0,
                maxValue: 1.5,
                precision: 2,
                onChanged: (v) {
                  setState(() => _dc = v);
                  _computeAndSend();
                },
              ),
          ],
        ),
      ],
    );
  }
}
