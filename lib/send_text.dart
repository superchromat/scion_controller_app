// send_text.dart
// Text overlay controls for MFC OSD

import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'oklch_color_picker.dart';
import 'grid.dart';
import 'panel.dart';
import 'labeled_card.dart';

/// Text field widget that sends string via OSC on every change
class OscTextField extends StatefulWidget {
  final String initialValue;
  final String hintText;
  final int maxLines;
  final bool expands;

  const OscTextField({
    super.key,
    this.initialValue = '',
    this.hintText = 'Enter text...',
    this.maxLines = 1,
    this.expands = false,
  });

  @override
  State<OscTextField> createState() => _OscTextFieldState();
}

class _OscTextFieldState extends State<OscTextField> with OscAddressMixin {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isNotEmpty && args.first is String) {
      final val = args.first as String;
      if (!_focusNode.hasFocus) {
        setState(() => _controller.text = val);
      }
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  void _onChanged(String value) {
    sendOsc(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.multiline,
      maxLines: widget.expands ? null : widget.maxLines,
      expands: widget.expands,
      textAlignVertical: widget.expands ? TextAlignVertical.top : null,
      style: t.textValue.copyWith(
        fontFamily: 'Courier',
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        hintStyle: t.textLabel.copyWith(
          fontWeight: FontWeight.w400,
          fontFamily: 'Courier',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        contentPadding: EdgeInsets.symmetric(vertical: t.sm, horizontal: t.sm),
        filled: true,
        fillColor: const Color(0x14000000),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: Color(0xFFF3DA77), width: 1.2),
        ),
      ),
      onChanged: _onChanged,
    );
  }
}

/// OKLCH color picker that sends R,G,B as combined OSC message
class OscColorControl extends StatefulWidget {
  final int initialR;
  final int initialG;
  final int initialB;
  final double size;

  const OscColorControl({
    super.key,
    this.initialR = 128,
    this.initialG = 128,
    this.initialB = 128,
    this.size = 90,
  });

  @override
  State<OscColorControl> createState() => _OscColorControlState();
}

class _OscColorControlState extends State<OscColorControl> with OscAddressMixin {
  late Color _color;
  final _pickerKey = GlobalKey<OklchColorPickerState>();

  @override
  void initState() {
    super.initState();
    _color = Color.fromARGB(255, widget.initialR, widget.initialG, widget.initialB);
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    // Skip echo while picker is being dragged — the rebuild disrupts gestures
    // and the RGB→OKLCH roundtrip is lossy.
    final pickerState = _pickerKey.currentState;
    if (pickerState != null && pickerState.isDragging) return OscStatus.ok;

    if (args.length >= 3 && args[0] is num && args[1] is num && args[2] is num) {
      final r = (args[0] as num).toInt().clamp(0, 255);
      final g = (args[1] as num).toInt().clamp(0, 255);
      final b = (args[2] as num).toInt().clamp(0, 255);
      setState(() {
        _color = Color.fromARGB(255, r, g, b);
      });
      _pickerKey.currentState?.setColor(_color);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  void _onColorChanged(Color color) {
    setState(() {
      _color = color;
    });
    sendOsc([color.red, color.green, color.blue]);
  }

  @override
  Widget build(BuildContext context) {
    return OklchColorPicker(
      key: _pickerKey,
      initialColor: _color,
      onColorChanged: _onColorChanged,
      size: widget.size,
    );
  }
}

/// Main SendText widget containing all text overlay controls
class SendText extends StatelessWidget {
  const SendText({super.key});

  Widget _textInputSizedSlot(BuildContext context, Widget child) {
    // Match the old `Panel(rows: 1)` footprint exactly, but without drawing
    // the inset panel chrome.
    final reference = Panel(
      rows: 1,
      child: const SizedBox.shrink(),
    );

    return Stack(
      children: [
        Opacity(opacity: 0, child: reference),
        Positioned.fill(
          child: NeumorphicInset(
            baseColor: const Color(0xFF26262A),
            borderRadius: 6.0,
            depth: 1.6,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: child,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    return OscPathSegment(
      segment: 'text',
      child: CardColumn(
        children: [
          GridRow(
            columns: 1,
            gutter: t.md,
            cells: [
              (
                span: 1,
                child: _textInputSizedSlot(
                  context,
                  OscPathSegment(
                    segment: 'string',
                    child: OscTextField(
                      hintText: 'Enter overlay text...',
                      expands: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
          GridRow(
            columns: 2,
            gutter: t.md,
            cells: [
              (
                span: 1,
                child: Panel.dark(
                  title: 'Color',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      OscPathSegment(
                        segment: 'color',
                        child: OscColorControl(size: t.knobMd * 1.15),
                      ),
                      SizedBox(width: t.sm),
                      Expanded(
                        child: Center(
                          child: OscPathSegment(
                            segment: 'alpha',
                            child: OscRotaryKnob(
                              label: 'Alpha',
                              minValue: 0,
                              maxValue: 255,
                              initialValue: 255,
                              defaultValue: 255,
                              format: '%.0f',
                              size: t.knobMd,
                              labelStyle: t.textLabel,
                              preferInteger: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              (
                span: 1,
                child: Panel.dark(
                  title: 'Position',
                  child: OscPathSegment(
                    segment: 'pos',
                    child: Row(
                      children: [
                        Expanded(
                          child: Center(
                            child: OscPathSegment(
                              segment: 'x',
                              child: OscRotaryKnob(
                                label: 'X',
                                minValue: 0,
                                maxValue: 3840,
                                initialValue: 100,
                                defaultValue: 100,
                                format: '%.0f',
                                size: t.knobMd,
                                labelStyle: t.textLabel,
                                preferInteger: true,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: t.md),
                        Expanded(
                          child: Center(
                            child: OscPathSegment(
                              segment: 'y',
                              child: OscRotaryKnob(
                                label: 'Y',
                                minValue: 0,
                                maxValue: 2160,
                                initialValue: 100,
                                defaultValue: 100,
                                format: '%.0f',
                                size: t.knobMd,
                                labelStyle: t.textLabel,
                                preferInteger: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
