// send_text.dart
// Text overlay controls for MFC OSD

import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';

/// Text field widget that sends string via OSC on every change
class OscTextField extends StatefulWidget {
  final String initialValue;
  final String hintText;
  final int maxLines;

  const OscTextField({
    super.key,
    this.initialValue = '',
    this.hintText = 'Enter text...',
    this.maxLines = 1,
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
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text,
      maxLines: widget.maxLines,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        border: const OutlineInputBorder(),
      ),
      onChanged: _onChanged,
    );
  }
}

/// Position control with separate X and Y OSC endpoints under /text/pos/
class OscPositionControl extends StatelessWidget {
  const OscPositionControl({super.key});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'pos',
      child: Row(
        children: [
          OscPathSegment(
            segment: 'x',
            child: OscRotaryKnob(
              label: 'X',
              minValue: 0,
              maxValue: 3840,
              initialValue: 100,
              defaultValue: 100,
              format: '%.0f',
              size: 60,
              preferInteger: true,
            ),
          ),
          const SizedBox(width: 8),
          OscPathSegment(
            segment: 'y',
            child: OscRotaryKnob(
              label: 'Y',
              minValue: 0,
              maxValue: 2160,
              initialValue: 100,
              defaultValue: 100,
              format: '%.0f',
              size: 60,
              preferInteger: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// RGB color control that sends R,G,B as combined OSC message
class OscColorControl extends StatefulWidget {
  final int initialR;
  final int initialG;
  final int initialB;

  const OscColorControl({
    super.key,
    this.initialR = 255,
    this.initialG = 255,
    this.initialB = 255,
  });

  @override
  State<OscColorControl> createState() => _OscColorControlState();
}

class _OscColorControlState extends State<OscColorControl> with OscAddressMixin {
  late int _r;
  late int _g;
  late int _b;
  final _rKey = GlobalKey<OscRotaryKnobState>();
  final _gKey = GlobalKey<OscRotaryKnobState>();
  final _bKey = GlobalKey<OscRotaryKnobState>();

  @override
  void initState() {
    super.initState();
    _r = widget.initialR;
    _g = widget.initialG;
    _b = widget.initialB;
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.length >= 3 && args[0] is num && args[1] is num && args[2] is num) {
      setState(() {
        _r = (args[0] as num).toInt();
        _g = (args[1] as num).toInt();
        _b = (args[2] as num).toInt();
      });
      _rKey.currentState?.setValue(_r.toDouble(), emit: false);
      _gKey.currentState?.setValue(_g.toDouble(), emit: false);
      _bKey.currentState?.setValue(_b.toDouble(), emit: false);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  void _sendColor() {
    sendOsc([_r, _g, _b]);
  }

  void _onRChanged(double value) {
    _r = value.toInt();
    setState(() {}); // Update color preview
    _sendColor();
  }

  void _onGChanged(double value) {
    _g = value.toInt();
    setState(() {});
    _sendColor();
  }

  void _onBChanged(double value) {
    _b = value.toInt();
    setState(() {});
    _sendColor();
  }

  Color get _previewColor => Color.fromARGB(255, _r, _g, _b);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Color preview swatch
        Container(
          width: 48,
          height: 48,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: _previewColor,
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        // RGB knobs
        OscRotaryKnob(
          key: _rKey,
          label: 'R',
          minValue: 0,
          maxValue: 255,
          initialValue: _r.toDouble(),
          defaultValue: 255,
          format: '%.0f',
          size: 60,
          onChanged: _onRChanged,
          sendOsc: false,
        ),
        const SizedBox(width: 8),
        OscRotaryKnob(
          key: _gKey,
          label: 'G',
          minValue: 0,
          maxValue: 255,
          initialValue: _g.toDouble(),
          defaultValue: 255,
          format: '%.0f',
          size: 60,
          onChanged: _onGChanged,
          sendOsc: false,
        ),
        const SizedBox(width: 8),
        OscRotaryKnob(
          key: _bKey,
          label: 'B',
          minValue: 0,
          maxValue: 255,
          initialValue: _b.toDouble(),
          defaultValue: 255,
          format: '%.0f',
          size: 60,
          onChanged: _onBChanged,
          sendOsc: false,
        ),
      ],
    );
  }
}

/// Main SendText widget containing all text overlay controls
class SendText extends StatelessWidget {
  const SendText({super.key});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'text',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text input (multiline)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 70, child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Text'),
              )),
              Expanded(
                child: OscPathSegment(
                  segment: 'string',
                  child: OscTextField(
                    hintText: 'Enter overlay text...',
                    maxLines: 4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Position row - X and Y have their own OSC paths under 'text'
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 70, child: Text('Position')),
              const OscPositionControl(),
            ],
          ),
          const SizedBox(height: 16),
          // Color row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 70, child: Text('Color')),
              const OscPathSegment(
                segment: 'color',
                child: OscColorControl(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
