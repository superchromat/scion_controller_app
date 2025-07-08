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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oscLogKey.currentState?.logOscMessage(
          address: widget.address,
          arg: args,
          status: OscStatus.ok,
          direction: Direction.received,
          binary: Uint8List(0),
        );
      });
    } else {
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

class _FloatArrayEditor extends StatefulWidget {
  final String segment;
  final int length;
  const _FloatArrayEditor({required this.segment, required this.length});

  @override
  State<_FloatArrayEditor> createState() => _FloatArrayEditorState();
}

class _FloatArrayEditorState extends State<_FloatArrayEditor> {
  late final List<double> _values = List.filled(widget.length, 0.0);
  late final List<GlobalKey<NumericSliderState>> _keys = List.generate(
    widget.length,
    (_) => GlobalKey<NumericSliderState>(),
  );

  late String _address;
  bool _registered = false;

  void _listener(List<Object?> args) {
    if (args.length >= widget.length &&
        args.take(widget.length).every((e) => e is num)) {
      for (int i = 0; i < widget.length; i++) {
        final v = (args[i] as num).toDouble();
        _values[i] = v;
        _keys[i].currentState?.setValue(v, immediate: true);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oscLogKey.currentState?.logOscMessage(
          address: _address,
          arg: args,
          status: OscStatus.ok,
          direction: Direction.received,
          binary: Uint8List(0),
        );
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oscLogKey.currentState?.logOscMessage(
          address: _address,
          arg: args,
          status: OscStatus.error,
          direction: Direction.received,
          binary: Uint8List(0),
        );
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_registered) return;
    final segs = OscPathSegment.resolvePath(context);
    segs.add(widget.segment);
    _address = segs.isEmpty ? '' : '/${segs.join('/')}';
    if (_address.isNotEmpty) {
      OscRegistry().registerAddress(_address);
      OscRegistry().registerListener(_address, _listener);
      _registered = true;
    }
  }

  @override
  void dispose() {
    if (_registered) {
      OscRegistry().unregisterListener(_address, _listener);
    }
    super.dispose();
  }

  void _send() {
    final args = _values.toList();
    context.read<Network>().sendOscMessage(_address, args);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oscLogKey.currentState?.logOscMessage(
        address: _address,
        arg: args,
        status: OscStatus.ok,
        direction: Direction.sent,
        binary: Uint8List(0),
      );
    });
  }

  void _onChanged(int idx, double v) {
    _values[idx] = v;
    _send();
  }

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: widget.segment,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: List.generate(widget.length, (i) {
          return SizedBox(
            width: 60,
            height: 24,
            child: NumericSlider(
              key: _keys[i],
              value: _values[i],
              range: const RangeValues(0, 1),
              precision: 3,
              onChanged: (v) => _onChanged(i, v),
              sendOsc: false,
            ),
          );
        }),
      ),
    );
  }
}

class SendTexture extends StatelessWidget {
  const SendTexture({super.key});

  Widget _sliderRow(
    String label,
    String segment,
    GlobalKey<NumericSliderState> key,
  ) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        SizedBox(
          width: 60,
          height: 24,
          child: OscPathSegment(
            segment: segment,
            child: NumericSlider(
              key: key,
              value: 0.0,
              range: const RangeValues(0, 1),
              detents: const [0.0, 1.0],
              precision: 3,
              onChanged: (v) {},
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => key.currentState?.setValue(0.0, immediate: true),
          child: const Icon(Icons.refresh, size: 16),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final _pHKey = GlobalKey<NumericSliderState>();
    final _pVKey = GlobalKey<NumericSliderState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 80, child: Text('LTI')),
            OscPathSegment(segment: 'lti', child: const OscCheckbox()),
            const SizedBox(width: 32),
            const SizedBox(width: 80, child: Text('CTI')),
            OscPathSegment(segment: 'cti', child: const OscCheckbox()),
          ],
        ),
        const SizedBox(height: 8),
        _sliderRow('Peaking H', 'peakingH', _pHKey),
        const SizedBox(height: 8),
        _sliderRow('Peaking V', 'peakingV', _pVKey),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: 80, child: Text('Color Enhance')),
            OscPathSegment(
              segment: 'color_enhance',
              child: const OscCheckbox(),
            ),
            const SizedBox(width: 32),
            const SizedBox(width: 80, child: Text('Front NR')),
            OscPathSegment(segment: 'front_nr', child: const OscCheckbox()),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Front NR Y Coef'),
        const _FloatArrayEditor(segment: 'front_nr_ycoef', length: 8),
        const SizedBox(height: 8),
        const Text('Front NR C Coef'),
        const _FloatArrayEditor(segment: 'front_nr_ccoef', length: 4),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: 80, child: Text('Block NR')),
            const AbsoluteOscCheckbox(address: '/block_nr'),
          ],
        ),
      ],
    );
  }
}
