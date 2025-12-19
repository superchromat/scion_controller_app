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
  final String? pathSegment;
  final String? displayLabel;
  final bool enabled;

  const OscDropdown({
    super.key,
    required this.label,
    required this.items,
    this.defaultValue,
    this.onChanged,
    this.pathSegment,
    this.displayLabel,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final segment = (pathSegment ?? label).toLowerCase();
    final uiLabel = displayLabel ?? label;
    return OscPathSegment(
      segment: segment,
      child: _OscDropdownInner<T>(
        label: uiLabel,
        items: items,
        defaultValue: defaultValue,
        onChanged: onChanged,
        enabled: enabled,
      ),
    );
  }
}

class _OscDropdownInner<T> extends StatefulWidget {
  final String label;
  final List<T> items;
  final T? defaultValue;
  final OnChangedCallback<T>? onChanged;
  final bool enabled;

  const _OscDropdownInner({
    super.key,
    required this.label,
    required this.items,
    this.defaultValue,
    this.onChanged,
    this.enabled = true,
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
    if (incoming is double) {
      for (final item in widget.items) {
        if (item is double && (item - incoming).abs() < 0.01) {
          setState(() => _selected = item as T);
          return OscStatus.ok;
        }
      }
    }
    return OscStatus.error;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<T>(
        decoration: InputDecoration(
          labelText: widget.label,
          enabled: widget.enabled,
        ),
        style: TextStyle(
          fontFamily: 'monospace',
          color: widget.enabled ? null : Colors.grey,
        ),
        value: _selected,
        items: widget.items
            .map((item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(_formatLabel(item)),
                ))
            .toList(),
        onChanged: widget.enabled
            ? (value) {
                if (value == null) return;
                setState(() => _selected = value);
                // send OSC and update registry
                sendOsc(value);
                // invoke custom handler if provided
                widget.onChanged?.call(value);
              }
            : null,
      ),
    );
  }

  String _formatLabel(T item) {
    if (item is double) {
      // Ensure consistent formatting for fractional frame rates
      final value = item;
      if ((value - value.roundToDouble()).abs() < 1e-6) {
        return value.toStringAsFixed(0);
      }
      return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return item.toString();
  }
}
