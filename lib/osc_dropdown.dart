import 'package:flutter/material.dart';
import 'osc_widget_binding.dart'; // for OscPathSegment & OscAddressMixin

/// Callback type for custom onChanged handling.
typedef OnChangedCallback<T> = void Function(T value);

/// A generic OSC-backed dropdown. T can be String, double, int, etc.
/// Allows an optional custom default and onChanged callback.
class OscDropdown<T> extends StatelessWidget {
  final String label;
  final List<T> items;
  final T? defaultValue;
  final OnChangedCallback<T>? onChanged;

  const OscDropdown({
    super.key,
    required this.label,
    required this.items,
    this.defaultValue,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: label.toLowerCase(),
      child: _OscDropdownInner<T>(
        label: label,
        items: items,
        defaultValue: defaultValue,
        onChanged: onChanged,
      ),
    );
  }
}

class _OscDropdownInner<T> extends StatefulWidget {
  final String label;
  final List<T> items;
  final T? defaultValue;
  final OnChangedCallback<T>? onChanged;

  const _OscDropdownInner({
    super.key,
    required this.label,
    required this.items,
    this.defaultValue,
    this.onChanged,
  });

  @override
  State<_OscDropdownInner<T>> createState() => _OscDropdownInnerState<T>();
}

class _OscDropdownInnerState<T> extends State<_OscDropdownInner<T>>
    with OscAddressMixin {
  late T _selected;

  @override
  void initState() {
    super.initState();
    // Use provided defaultValue if specified and valid, otherwise first item
    if (widget.defaultValue != null &&
        widget.items.contains(widget.defaultValue)) {
      _selected = widget.defaultValue as T;
    } else {
      _selected = widget.items.first;
    }
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    // take the first argument, cast to T if possible
    final incoming = args.isNotEmpty ? args.first : null;
    if (incoming is T && widget.items.contains(incoming)) {
      setState(() => _selected = incoming);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<T>(
        decoration: InputDecoration(labelText: widget.label),
        style: const TextStyle(fontFamily: 'monospace'),
        value: _selected,
        items: widget.items
            .map((item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(item.toString()),
                ))
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() => _selected = value);
          // send OSC and update registry
          sendOsc(value);
          // invoke custom handler if provided
          widget.onChanged?.call(value);
        },
      ),
    );
  }
}
