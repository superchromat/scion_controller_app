import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          const Text('Y Coefficients'),
          const _IndexedSliders(segment: 'y', length: 8),
          const SizedBox(height: 8),
          const Text('C Coefficients'),
          const _IndexedSliders(segment: 'c', length: 4),
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
