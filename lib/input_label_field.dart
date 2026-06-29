import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'network.dart';
import 'osc_registry.dart';

/// Shared line metrics for the input tile rows + label, tightened just enough
/// to fit five rows in the tile (the format tiles only carry four).
const TextStyle kInputRowStyle = TextStyle(
  color: Colors.green,
  fontFamily: 'Courier',
  fontSize: 12,
  height: 1.32,
);
const StrutStyle kInputRowStrut = StrutStyle(
  fontFamily: 'Courier',
  fontSize: 12,
  height: 1.32,
  forceStrutHeight: true,
);

/// Fixed per-row slot height for the System Overview input tile, so all five
/// rows (label + four format rows) are evenly spaced and fit the tile.
const double kInputRowSlot = 17.0;

/// Editable, persisted human-readable name for an HDMI input, bound to
/// `/input/<index>/label`.
///
/// Always an inline editor (never swaps widgets, so the tile never jumps),
/// styled to match the format rows, with a small pencil icon on the right.
/// Free text up to 16 chars; commits on Enter or focus loss. Defaults to
/// "Input N" until the device reports a stored value.
class InputLabelField extends StatefulWidget {
  final int inputIndex;
  const InputLabelField({super.key, required this.inputIndex});

  @override
  State<InputLabelField> createState() => _InputLabelFieldState();
}

class _InputLabelFieldState extends State<InputLabelField> {
  static const int _maxLen = 16;

  late final String _addr = '/input/${widget.inputIndex}/label';
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  late final void Function(List<Object?>) _listener;
  String _committed = '';
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _committed = 'Input ${widget.inputIndex}';
    _ctrl = TextEditingController(text: _committed);

    final reg = OscRegistry();
    reg.registerAddress(_addr);
    final cur = reg.allParams[_addr]?.currentValue;
    if (cur != null && cur.isNotEmpty) {
      _applyIncoming(cur.first?.toString() ?? '');
    }
    _listener = (args) {
      if (args.isEmpty) return;
      _applyIncoming(args.first?.toString() ?? '');
    };
    reg.registerListener(_addr, _listener);

    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  void _applyIncoming(String v) {
    if (_editing) return;
    final s = v.trim();
    if (s.isEmpty || s == _committed) return;
    setState(() => _committed = s);
  }

  void _startEdit() {
    _ctrl.text = _committed;
    _ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: _committed.length);
    setState(() => _editing = true);
  }

  void _commit() {
    var v = _ctrl.text.trim();
    if (v.length > _maxLen) v = v.substring(0, _maxLen);
    final next = v.isEmpty ? _committed : v; // empty reverts
    final changed = next != _committed;
    setState(() {
      _committed = next;
      _editing = false;
    });
    if (!changed) return;

    final net = context.read<Network>();
    final sent = net.sendOscMessage(_addr, <Object>[next]);
    if (sent) {
      final reg = OscRegistry();
      reg.registerAddress(_addr);
      reg.dispatchLocal(_addr, <Object?>[next]);
    }
  }

  @override
  void dispose() {
    OscRegistry().unregisterListener(_addr, _listener);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // At rest the label is `Align(centerLeft, Text)` — the *exact* structure the
    // format rows use — so it lines up pixel-for-pixel. It becomes an
    // EditableText only while editing; the fixed-height slot means no jump.
    final Widget content = _editing
        ? EditableText(
            controller: _ctrl,
            focusNode: _focus,
            style: kInputRowStyle,
            strutStyle: kInputRowStrut,
            cursorColor: Colors.green,
            backgroundCursorColor: Colors.transparent,
            selectionColor: Colors.green.withValues(alpha: 0.35),
            cursorWidth: 1.0,
            maxLines: 1,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [LengthLimitingTextInputFormatter(_maxLen)],
            onSubmitted: (_) {
              _commit();
              _focus.unfocus();
            },
          )
        : Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _committed,
              style: kInputRowStyle,
              strutStyle: kInputRowStrut,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _editing ? null : _startEdit,
      child: SizedBox(
        height: kInputRowSlot,
        child: Stack(
          children: [
            // Reserve the right 16px for the icon via the Positioned bounds, so
            // the content is the exact same Align(centerLeft, Text) as the rows.
            Positioned(left: 0, top: 0, bottom: 0, right: 16, child: content),
            const Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Icon(Icons.edit, size: 11, color: Color(0x80FFFFFF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
