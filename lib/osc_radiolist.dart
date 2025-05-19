import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';

class OscRadioList extends StatefulWidget {
  /// each sublist is [value, label]
  final List<List<String>> options;

  /// if omitted, defaults to the first option’s value
  final String? initialValue;

  const OscRadioList({
    Key? key,
    required this.options,
    this.initialValue,
  }) : super(key: key);

  @override
  _OscRadioListState createState() => _OscRadioListState();
}
class _OscRadioListState extends State<OscRadioList>
    with OscAddressMixin<OscRadioList> {
  late String _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.initialValue ?? widget.options.first[0];
    setDefaultValues(_selectedValue);
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    final incoming = args.isNotEmpty && args.first is String
        ? args.first as String
        : null;
    if (incoming != null && widget.options.any((o) => o[0] == incoming)) {
      setState(() => _selectedValue = incoming);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.options.map((opt) {
        return RadioListTile<String>(
          title: Text(opt[1], style: Theme.of(context).textTheme.bodyMedium),
          value: opt[0],
          groupValue: _selectedValue,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedValue = value);
            // send out the new value
            sendOsc(value);
          },
        );
      }).toList(),
    );
  }
}
