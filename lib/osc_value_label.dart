import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';

class OscValueLabel extends StatefulWidget {
  final String label;
  final String defaultValue;
  final String Function(Object?)? formatter;

  const OscValueLabel({
    super.key,
    required this.label,
    this.defaultValue = '?',
    this.formatter,
  });

  @override
  State<OscValueLabel> createState() => _OscValueLabelState();
}

class _OscValueLabelState extends State<OscValueLabel> with OscAddressMixin {
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.defaultValue;
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isEmpty) return OscStatus.error;
    final raw = args.first;
    final formatted = widget.formatter != null
        ? widget.formatter!(raw)
        : _defaultFormatter(raw);
    if (formatted != _value) {
      setState(() => _value = formatted);
    }
    return OscStatus.ok;
  }

  String _defaultFormatter(Object? raw) {
    if (raw == null) return widget.defaultValue;
    if (raw is double) {
      final rounded = raw.toStringAsFixed(2);
      if (rounded.contains('.')) {
        var trimmed = rounded;
        trimmed = trimmed.replaceAll(RegExp(r'0+$'), '');
        if (trimmed.endsWith('.')) {
          trimmed = trimmed.substring(0, trimmed.length - 1);
        }
        return trimmed.isEmpty ? '0' : trimmed;
      }
      return rounded;
    }
    return raw.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey[700]!),
              color: Colors.grey[850],
            ),
            child: Text(
              _value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
