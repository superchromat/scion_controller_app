// send_text.dart
// Text overlay controls for MFC OSD

import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'shape_selection.dart';
import 'font_controls.dart';
import 'oklch_color_picker.dart';
import 'grid.dart';
import 'panel.dart';
import 'labeled_card.dart';
import 'network.dart';

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
  DateTime? _lastEdit;

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
      // Reflect device state (sync/reset/other peers) unless the user is
      // actively typing right now — a focused-but-idle field still updates,
      // so a device reset clears the box even when it kept focus.
      final typing = _lastEdit != null &&
          DateTime.now().difference(_lastEdit!).inMilliseconds < 1500;
      if (val != _controller.text && !typing) {
        setState(() => _controller.text = val);
      }
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  void _onChanged(String value) {
    _lastEdit = DateTime.now();
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
    this.initialR = 255,
    this.initialG = 255,
    this.initialB = 255,
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
class SendText extends StatefulWidget {
  const SendText({super.key});

  @override
  State<SendText> createState() => _SendTextState();
}

class _SendTextState extends State<SendText> {
  // Selected text region (1-4). Region 1 = the legacy text overlay; regions
  // 2-4 are extra sprites with independent typeface/colour/position. All
  // controls below bind under region/N, whose endpoints mirror the legacy
  // field set exactly (region 1 aliases the flat /text/* fields).
  int _region = 1;

  // Shared canvas/editor selection (provided by Shape). We follow it (canvas
  // tap → this region) and drive it (region tab → canvas highlight).
  ShapeSelection? _sel;
  bool _selWired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_selWired) return;
    _selWired = true;
    _sel = context.read<ShapeSelection>();
    _sel!.addListener(_onSel);
    // On entering the Text tab: adopt the selection if it already points at a
    // text region (canvas-driven), otherwise claim it for our current region.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sel = _sel;
      if (sel == null || !mounted) return;
      if (sel.kind == ShapeSel.text) {
        if (sel.region != _region) setState(() => _region = sel.region);
      } else {
        sel.select(ShapeSel.text, _region);
      }
    });
  }

  @override
  void dispose() {
    _sel?.removeListener(_onSel);
    super.dispose();
  }

  void _onSel() {
    final sel = _sel;
    if (sel == null || !mounted) return;
    if (sel.kind == ShapeSel.text && sel.region != _region) {
      setState(() => _region = sel.region);
    }
  }

  void _selectRegion(int r) {
    setState(() => _region = r);
    _sel?.select(ShapeSel.text, r);
  }

  Widget _regionTabs(BuildContext context) {
    final t = GridProvider.of(context);
    // Rebuild the tabs when occupancy changes so a region gained/lost by a
    // sprite greys/ungreys live.
    final sel = context.watch<ShapeSelection>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Region', style: t.textLabel),
        SizedBox(width: t.sm),
        for (int r = 1; r <= 4; r++) ...[
          // Regions 2-4 hold text OR a sprite: if a sprite occupies this region,
          // it can't hold text, so disable and grey the tab.
          Builder(builder: (context) {
            final blocked = r >= 2 && sel.spriteOccupied(r);
            final tab = GestureDetector(
              onTap: blocked ? null : () => _selectRegion(r),
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: t.md, vertical: t.xs),
                decoration: BoxDecoration(
                  color: _region == r
                      ? const Color(0xFF4A6A8A)
                      : const Color(0xFF2A2A2C),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: _region == r
                        ? const Color(0xFF6A9ACA)
                        : Colors.grey[600]!,
                  ),
                ),
                child: Text('$r',
                    style: t.textLabel.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _region == r ? Colors.white : Colors.grey[300],
                    )),
              ),
            );
            return Opacity(
              opacity: blocked ? 0.35 : 1.0,
              child: blocked
                  ? Tooltip(
                      message: 'Region $r has a sprite',
                      child: MouseRegion(
                          cursor: SystemMouseCursors.forbidden, child: tab))
                  : tab,
            );
          }),
          SizedBox(width: t.xs),
        ],
      ],
    );
  }

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
        spacing: t.sm,
        children: [
          // Region selector + the Layer (osd) dropdown for that region, inset
          // to the same grid margin as the panels below.
          GridRow(columns: 1, gutter: t.md, cells: [
            (
              span: 1,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _regionTabs(context),
                  SizedBox(width: t.lg),
                  KeyedSubtree(
                    key: ValueKey(_region),
                    child: OscPathSegment(
                      segment: 'region/$_region',
                      child: const TextLayerDropdown(),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          KeyedSubtree(
            key: ValueKey(_region),
            child: OscPathSegment(
              segment: 'region/$_region',
              child: CardColumn(spacing: t.sm, children: [
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
          // Font: nested typeface/variant + size + upload, with the small
          // Tracking/Leading knobs riding on the space freed by the merge and
          // by moving Layer up to the region row. (No title — it's redundant.)
          GridRow(
            columns: 1,
            gutter: t.md,
            cells: [
              (
                span: 1,
                child: Panel(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(child: FontControls()),
                      SizedBox(width: t.md),
                      OscPathSegment(
                        segment: 'tracking',
                        child: OscRotaryKnob(
                          label: 'Tracking',
                          minValue: -20,
                          maxValue: 40,
                          initialValue: 0,
                          defaultValue: 0,
                          format: '%.0f',
                          size: t.knobSm,
                          labelStyle: t.textLabel,
                          preferInteger: true,
                        ),
                      ),
                      SizedBox(width: t.sm),
                      OscPathSegment(
                        segment: 'leading',
                        child: OscRotaryKnob(
                          label: 'Leading',
                          minValue: -20,
                          maxValue: 60,
                          initialValue: 0,
                          defaultValue: 0,
                          format: '%.0f',
                          size: t.knobSm,
                          labelStyle: t.textLabel,
                          preferInteger: true,
                        ),
                      ),
                    ],
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
                child: Panel(
                  title: 'Color',
                  // Both knobs get an equal, centered half (matching the
                  // Position card); the compact Copper toggle sits between them.
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Center(
                          child: OscPathSegment(
                            segment: 'color',
                            child: OscColorControl(size: t.knobMd * 1.15),
                          ),
                        ),
                      ),
                      const TextCopperToggle(),
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
                child: Panel(
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
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact "Copper" toggle riding in the Color card's title row. Sends
/// `/send/N/text/region/M/copper <0|1>`; the firmware drives a per-scanline
/// rainbow on the text's solid-colour palette entry (the glyph body cycles,
/// AA edges keep their hue). The effect is transient with no device-side state
/// to read back, and the card is keyed by region, so the toggle resets to off
/// when the region changes.
class TextCopperToggle extends StatefulWidget {
  const TextCopperToggle({super.key});

  @override
  State<TextCopperToggle> createState() => _TextCopperToggleState();
}

class _TextCopperToggleState extends State<TextCopperToggle> {
  String _base = '';
  bool _on = false;
  bool _wired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final segs = OscPathSegment.resolvePath(context);
    _base = segs.isEmpty ? '' : '/${segs.join('/')}';
  }

  void _toggle() {
    if (_base.isEmpty) return;
    final next = !_on;
    context.read<Network>().sendOscMessage('$_base/copper', [next ? 1 : 0]);
    setState(() => _on = next);
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7A5CFF);
    return Tooltip(
      message: _on ? 'Copper on' : 'Copper (rainbow text)',
      child: GestureDetector(
        onTap: _toggle,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _on ? accent.withValues(alpha: 0.22) : const Color(0xFF2A2A2C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _on ? accent : Colors.grey[700]!,
              width: _on ? 1.5 : 1,
            ),
          ),
          child: const Text('🌈', style: TextStyle(fontSize: 17)),
        ),
      ),
    );
  }
}
