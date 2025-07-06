import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';

class OscCheckbox extends StatefulWidget {
  final bool initialValue;
  final bool readOnly;
  const OscCheckbox({
    super.key,
    this.initialValue = false,
    this.readOnly = false,
  });

  @override
  State<OscCheckbox> createState() => _OscCheckboxState();
}

class _OscCheckboxState extends State<OscCheckbox> with OscAddressMixin {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isNotEmpty && args.first is bool) {
      setState(() => _value = args.first as bool);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: _value,
      onChanged: widget.readOnly
          ? null
          : (val) {
              if (val == null) return;
              setState(() => _value = val);
              sendOsc(val);
            },
    );
  }
}
