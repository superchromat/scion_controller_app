import 'package:flutter/material.dart';

import 'labeled_card.dart'; // NeumorphicContainer / NeumorphicInset

/// The single button used everywhere in the app.
///
/// A tactile neumorphic key that obeys the global lighting model: raised at
/// rest (convex [NeumorphicContainer]), sunk into a concave [NeumorphicInset]
/// when pressed or [selected]. Hovering lightens it; pressing adds a small
/// scale. This keeps every button — setup actions, sidebar file actions, LUT
/// channel toggles — visually identical.
///
/// Supports a text [label], an [icon], or both. [selected] gives a toggle/active
/// look (used by the LUT channel + lock toggles). [accentColor] tints the
/// active face and draws a hairline rim (e.g. per-channel colour, reset red);
/// when omitted the button is neutral grey (no colour cast).
class AppButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;

  /// Active/toggle state — renders sunk-in and tinted toward [accentColor].
  final bool selected;

  /// Optional accent. Tints the [selected] face, the rim, and (for icon/letter
  /// buttons) the foreground. Leave null for a neutral button.
  final Color? accentColor;

  /// Smaller footprint for dense toolbars (e.g. the LUT editor).
  final bool dense;

  final String? tooltip;

  const AppButton({
    super.key,
    this.onPressed,
    this.label,
    this.icon,
    this.selected = false,
    this.accentColor,
    this.dense = false,
    this.tooltip,
  }) : assert(label != null || icon != null, 'AppButton needs a label or an icon');

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;
  bool _hover = false;

  static const Color _fgNeutral = Color(0xFFE6E6EA);
  static const Color _fgDisabled = Color(0xFF74747C);
  static const Color _faceRest = Color(0xFF34343A);
  static const Color _faceHover = Color(0xFF3B3B42);
  static const Color _faceDisabled = Color(0xFF2C2C31);

  Color _foreground(bool enabled) {
    if (!enabled) return _fgDisabled;
    if (widget.selected) {
      final base = widget.accentColor ?? const Color(0xFF8A8A92);
      // Pick dark or light text for contrast against the tinted active face.
      return base.computeLuminance() > 0.55
          ? const Color(0xFF1A1A1A)
          : const Color(0xFFF5F5F8);
    }
    return widget.accentColor ?? _fgNeutral;
  }

  Color _face(bool enabled) {
    if (!enabled) return _faceDisabled;
    if (widget.selected) {
      final accent = widget.accentColor;
      return accent != null
          ? Color.lerp(const Color(0xFF3A3A3C), accent, 0.32)!
          : const Color(0xFF45454B);
    }
    return _hover ? _faceHover : _faceRest;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final sunk = (_pressed || widget.selected) && enabled;
    final fg = _foreground(enabled);
    final base = _face(enabled);

    final double h = widget.dense ? 30 : 40;
    final double iconSize = widget.dense ? 16 : 20;
    final bool iconOnly = widget.label == null;
    const double radius = 8;

    final textStyle = TextStyle(
      fontFamily: 'DINPro',
      fontWeight: FontWeight.w500,
      fontSize: widget.dense ? 12.5 : 14,
      letterSpacing: 0.05,
      color: fg,
    );

    Widget inner;
    if (widget.label != null && widget.icon != null) {
      inner = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: iconSize, color: fg),
          const SizedBox(width: 8),
          // DINPro sits ~2px low when metrically centred; nudge up.
          Transform.translate(offset: const Offset(0, -1), child: Text(widget.label!, style: textStyle)),
        ],
      );
    } else if (widget.label != null) {
      inner = Transform.translate(
        offset: const Offset(0, -2),
        child: Text(widget.label!, style: textStyle),
      );
    } else {
      inner = Icon(widget.icon, size: iconSize, color: fg);
    }

    Widget content = Container(
      height: h,
      width: iconOnly ? h : null,
      alignment: Alignment.center,
      padding: iconOnly
          ? null
          : EdgeInsets.symmetric(horizontal: widget.dense ? 12 : 18),
      child: inner,
    );
    if (!iconOnly) content = IntrinsicWidth(child: content);

    Widget surface = sunk
        ? NeumorphicInset(
            baseColor: base,
            borderRadius: radius,
            depth: 3.0,
            child: content,
          )
        : NeumorphicContainer(
            baseColor: base,
            borderRadius: radius,
            elevation: enabled ? (_hover ? 6.0 : 4.0) : 2.0,
            child: content,
          );

    // Hairline accent rim for accented-but-unselected buttons (reset, channels).
    if (widget.accentColor != null && !widget.selected && enabled) {
      surface = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: widget.accentColor!.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: surface,
      );
    }

    Widget button = MouseRegion(
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
          scale: sunk ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: surface,
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
