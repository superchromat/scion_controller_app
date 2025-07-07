import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';

class OscNumberField extends StatefulWidget {
  final int precision; // 0 => int
  final bool readOnly;
  final num initialValue;
  const OscNumberField({
    super.key,
    this.precision = 0,
    this.readOnly = false,
    this.initialValue = 0,
  });

  @override
  State<OscNumberField> createState() => _OscNumberFieldState();
}

class _OscNumberFieldState extends State<OscNumberField> with OscAddressMixin {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.initialValue));
  }

  String _format(num v) {
    return widget.precision == 0
        ? v.toInt().toString()
        : v.toStringAsFixed(widget.precision);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isNotEmpty && args.first is num) {
      final val = args.first as num;
      setState(() => _controller.text = _format(val));
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  void _commit() {
    final parsed = num.tryParse(_controller.text);
    if (parsed != null && !widget.readOnly) {
      final out = widget.precision == 0 ? parsed.toInt() : parsed.toDouble();
      sendOsc(out);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      readOnly: widget.readOnly,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => _commit(),
      onEditingComplete: _commit,
    );
  }
}
