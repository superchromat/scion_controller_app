import 'package:flutter/material.dart';

import 'grid.dart';
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
/// Accent for "pick one of these" controls — region tabs, pixel scale, and any
/// other one-of-a-set selector. Carried over from the flat chips these
/// replaced, which paired it with a #4A6A8A fill.
const Color kSelectAccent = Color(0xFF6A9ACA);

/// Accent for an on/off toggle that gates an effect (glitch, posterize).
const Color kToggleAccent = Color(0xFFFF6B6B);

/// Accent for a bit/flag toggle within a set — reads as lit rather than as a
/// mode change. Takes black foreground, which [AppButton] picks automatically
/// from the accent's luminance.
const Color kFlagAccent = Color(0xFFFFF176);

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

  /// Every label this button can show, for a toggle whose text changes with
  /// its state ('ON'/'OFF', 'Show'/'Hide'). The button reserves the width of
  /// the widest one, so pressing it doesn't resize it and shove its
  /// neighbours sideways. Include the current [label] in the list.
  final List<String>? sizeToLabels;

  final String? tooltip;

  /// Why this button cannot be used right now. Distinct from `onPressed: null`,
  /// which means "there is nothing to do": a blocked button is one the user
  /// could reasonably expect to work, held shut by state elsewhere (a region
  /// already holding text, say). It greys out further, takes a forbidden
  /// cursor, and shows this string as its tooltip so the reason is reachable.
  final String? blockedReason;

  /// Fill the height offered by the parent instead of the standard button
  /// height. For a button that must align its bottom edge with a neighbouring
  /// element rather than stand at its natural size.
  final bool fillHeight;

  const AppButton({
    super.key,
    this.onPressed,
    this.label,
    this.icon,
    this.selected = false,
    this.accentColor,
    this.dense = false,
    this.sizeToLabels,
    this.tooltip,
    this.blockedReason,
    this.fillHeight = false,
  }) : assert(label != null || icon != null,
            'AppButton needs a label or an icon');

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
      // An active toggle has to read as lit from across the room, so the face
      // goes most of the way to the accent. It stops short of a flat fill so
      // the neumorphic shading still has a grey body to work against — at a
      // full accent the inset shadows wash out and the button stops reading as
      // sunk. This was 0.32, which left 'on' barely distinguishable from 'off'.
      return accent != null
          ? Color.lerp(const Color(0xFF3A3A3C), accent, 0.85)!
          : const Color(0xFF45454B);
    }
    return _hover ? _faceHover : _faceRest;
  }

  @override
  Widget build(BuildContext context) {
    final blocked = widget.blockedReason != null;
    final enabled = widget.onPressed != null && !blocked;
    final sunk = (_pressed || widget.selected) && enabled;
    final fg = _foreground(enabled);
    final base = _face(enabled);

    // Everything here scales with the grid unit. Hardcoded px meant button
    // labels stayed at 14pt while every surrounding label grew with the
    // window, so buttons read as tiny on large displays. The multipliers
    // reproduce the old 30/40px heights at the u≈14 they were chosen at.
    final t = GridProvider.of(context);
    final double h = (widget.dense ? 2.15 : 2.85) * t.u;
    final double iconSize = (widget.dense ? 1.15 : 1.4) * t.u;
    final bool iconOnly = widget.label == null;
    const double radius = 8;

    final textStyle = TextStyle(
      fontFamily: 'DINPro',
      fontWeight: FontWeight.w400,
      fontSize: (widget.dense ? 0.95 : 1.05) * t.u,
      letterSpacing: 0.05,
      color: fg,
    );

    Widget innerFor(String? label) {
      if (label != null && widget.icon != null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: iconSize, color: fg),
            SizedBox(width: t.xs),
            CapCenteredText(label, style: textStyle),
          ],
        );
      } else if (label != null) {
        return CapCenteredText(label, style: textStyle);
      }
      return Icon(widget.icon, size: iconSize, color: fg);
    }

    Widget inner = innerFor(widget.label);

    // Reserve the widest candidate label so a state-changing toggle keeps one
    // width. The alternates are laid out at zero opacity purely to occupy the
    // space — the same reservation trick Panel uses for its title. The Stack
    // sizes to its largest child, and `inner` is one of them, so the current
    // label is always covered even if the caller omits it from the list.
    final alts = widget.sizeToLabels;
    if (alts != null && alts.isNotEmpty) {
      inner = Stack(
        alignment: Alignment.center,
        children: [
          for (final l in alts) Opacity(opacity: 0, child: innerFor(l)),
          inner,
        ],
      );
    }

    // A button given a tight width by its parent (e.g. stretched in a column)
    // can be narrower than its label. Shrink the label to fit rather than
    // overflow — scaleDown never enlarges, so buttons with room are unchanged.
    inner = FittedBox(fit: BoxFit.scaleDown, child: inner);

    Widget content = Container(
      height: widget.fillHeight ? null : h,
      constraints:
          widget.fillHeight ? const BoxConstraints(minHeight: 0) : null,
      width: iconOnly ? h : null,
      alignment: Alignment.center,
      padding: iconOnly
          ? null
          : EdgeInsets.symmetric(horizontal: (widget.dense ? 0.85 : 1.3) * t.u),
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
      cursor: blocked
          ? SystemMouseCursors.forbidden
          : (enabled ? SystemMouseCursors.click : SystemMouseCursors.basic),
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

    // Blocked reads as further-back than merely disabled — the face is already
    // the disabled one, and this pushes the whole button toward the panel.
    if (blocked) button = Opacity(opacity: 0.35, child: button);

    final tip = widget.blockedReason ?? widget.tooltip;
    if (tip != null) button = Tooltip(message: tip, child: button);
    return button;
  }
}
