import 'package:flutter/material.dart';

import 'labeled_card.dart'; // NeumorphicContainer / NeumorphicInset

/// A tactile neumorphic button that obeys the global lighting model.
///
/// At rest it is a raised key (convex Phong surface + lit-edge rim, shaded by
/// [NeumorphicContainer] from the shared light direction). Hovering lifts it
/// slightly; pressing sinks it into a concave [NeumorphicInset] with a small
/// scale — so it reacts to light exactly like the cards and panels around it,
/// instead of sitting on top as a flat Material rectangle.
class NeumorphicButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String label;

  /// Primary buttons tint their face toward the accent and use accent text;
  /// secondary buttons stay neutral grey.
  final bool primary;

  const NeumorphicButton({
    super.key,
    required this.label,
    this.onPressed,
    this.primary = false,
  });

  @override
  State<NeumorphicButton> createState() => _NeumorphicButtonState();
}

class _NeumorphicButtonState extends State<NeumorphicButton> {
  bool _pressed = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    // Button text is white/light regardless of primary; primary is distinguished
    // by its warmer face, not coloured text.
    final Color fg = !enabled
        ? const Color(0xFF74747C)
        : widget.primary
            ? const Color(0xFFF5F5F8)
            : const Color(0xFFE6E6EA);

    // Base face colour. Primary leans a touch warmer/brighter; hover lightens.
    Color base;
    if (!enabled) {
      base = const Color(0xFF2C2C31);
    } else if (widget.primary) {
      base = _hover ? const Color(0xFF3D3B33) : const Color(0xFF38362F);
    } else {
      base = _hover ? const Color(0xFF3B3B42) : const Color(0xFF34343A);
    }

    // Fixed-height box with the label centred both ways. IntrinsicWidth keeps
    // the button sized to its content (centre alignment would otherwise expand
    // it full-width). The -2px y nudge is an optical correction: DINPro's ascent
    // leading sits above the cap line, so a metrically-centred label renders ~2px
    // low; this re-centres the visible glyph box.
    final content = IntrinsicWidth(
      child: Container(
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Transform.translate(
          offset: const Offset(0, -2),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: 'DINPro',
              fontWeight: FontWeight.w600,
              fontSize: 15,
              letterSpacing: 0.05,
              color: fg,
            ),
          ),
        ),
      ),
    );

    final Widget surface = (_pressed && enabled)
        ? NeumorphicInset(
            baseColor: base,
            borderRadius: 10,
            depth: 3.5,
            child: content,
          )
        : NeumorphicContainer(
            baseColor: base,
            borderRadius: 10,
            elevation: enabled ? (_hover ? 6.0 : 4.0) : 2.0,
            child: content,
          );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed!();
              }
            : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: (_pressed && enabled) ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: surface,
        ),
      ),
    );
  }
}
