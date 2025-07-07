import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';

class OscValueDropdown<T> extends StatefulWidget {
  final List<T> values;
  final List<String> labels;
  final T initialValue;

  const OscValueDropdown({
    super.key,
    required this.values,
    required this.labels,
    required this.initialValue,
  });

  @override
  State<OscValueDropdown<T>> createState() => _OscValueDropdownState<T>();
}

class _OscValueDropdownState<T> extends State<OscValueDropdown<T>>
    with OscAddressMixin {
  late T _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isNotEmpty && args.first is T) {
      setState(() => _selected = args.first as T);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      isDense: true,
      value: _selected,
      items: List.generate(widget.values.length, (i) {
        return DropdownMenuItem<T>(
          value: widget.values[i],
          child: Text(widget.labels[i]),
        );
      }),
      onChanged: (val) {
        if (val == null) return;
        setState(() => _selected = val);
        sendOsc(val);
      },
    );
  }
}
