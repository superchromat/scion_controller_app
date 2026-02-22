import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'lighting_settings.dart';
import 'global_rect_tracking.dart';

class OscCheckbox extends StatefulWidget {
  final bool initialValue;
  final bool readOnly;
  final String? label;
  final double size;
  final ValueChanged<bool>? onChanged;

  const OscCheckbox({
    super.key,
    this.initialValue = false,
    this.readOnly = false,
    this.label,
    this.size = 22,
    this.onChanged,
  });

  @override
  State<OscCheckbox> createState() => _OscCheckboxState();
}

class _OscCheckboxState extends State<OscCheckbox> with OscAddressMixin {
  late bool _value;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isNotEmpty && args.first is bool) {
      setState(() => _value = args.first as bool);
      return OscStatus.ok;
    }
    // Also accept int 0/1
    if (args.isNotEmpty && args.first is int) {
      setState(() => _value = (args.first as int) != 0);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  void _toggle() {
    if (widget.readOnly) return;
    final next = !_value;
    setState(() => _value = next);
    if (oscAddress.isNotEmpty) {
      sendOsc(next);
    }
    widget.onChanged?.call(next);
  }

  @override
  void didUpdateWidget(covariant OscCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        widget.initialValue != _value) {
      _value = widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();

    Widget checkbox = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.readOnly ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggle,
        child: _NeumorphicCheckbox(
          lighting: lighting,
          value: _value,
          size: widget.size,
          isHovered: _isHovered,
          enabled: !widget.readOnly,
        ),
      ),
    );

    if (widget.label != null) {
      return GestureDetector(
        onTap: _toggle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            checkbox,
            const SizedBox(width: 8),
            Text(
              widget.label!,
              style: TextStyle(
                fontSize: 13,
                color: widget.readOnly ? Colors.grey[600] : Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return checkbox;
  }
}

class _NeumorphicCheckbox extends StatefulWidget {
  final LightingSettings lighting;
  final bool value;
  final double size;
  final bool isHovered;
  final bool enabled;

  const _NeumorphicCheckbox({
    required this.lighting,
    required this.value,
    required this.size,
    required this.isHovered,
    required this.enabled,
  });

  @override
  State<_NeumorphicCheckbox> createState() => _NeumorphicCheckboxState();
}

class _NeumorphicCheckboxState extends State<_NeumorphicCheckbox>
    with GlobalRectTracking<_NeumorphicCheckbox> {

  @override
  Widget build(BuildContext context) {
    return Container(
      key: globalRectKey,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: widget.lighting.createNeumorphicShadows(
          elevation: 2.0,
          inset: true,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          painter: _CheckboxPainter(
            lighting: widget.lighting,
            value: widget.value,
            isHovered: widget.isHovered,
            enabled: widget.enabled,
            globalRect: trackedGlobalRect,
          ),
          size: Size(widget.size, widget.size),
        ),
      ),
    );
  }
}

class _CheckboxPainter extends CustomPainter {
  final LightingSettings lighting;
  final bool value;
  final bool isHovered;
  final bool enabled;
  final Rect? globalRect;

  _CheckboxPainter({
    required this.lighting,
    required this.value,
    required this.isHovered,
    required this.enabled,
    this.globalRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    // Slot dimensions (like the knob/radio)
    final borderInset = size.width * 0.12;

    // Light direction from settings
    final light = lighting.lightDir2D;
    final lightAlign = Alignment(light.dx * 0.4, light.dy * 0.4);
    final shadowAlign = Alignment(-light.dx * 0.5, -light.dy * 0.5);

    // === 1. BORDER (grey rim around the hole) ===
    final borderGradient = RadialGradient(
      center: lightAlign,
      radius: 0.7,
      colors: const [Color(0xFF686868), Color(0xFF484848), Color(0xFF383838)],
      stops: const [0.0, 0.5, 1.0],
    );
    final borderPaint = Paint()..shader = borderGradient.createShader(rect);
    canvas.drawRRect(rrect, borderPaint);

    // === 2. OUTER SHADOW (shadow on lit side where rim blocks light into hole) ===
    final innerRRect = rrect.deflate(borderInset);
    final outerShadowGradient = RadialGradient(
      center: lightAlign,
      radius: 0.6,
      colors: const [Color(0xFF0C0C0C), Color(0xFF040404), Color(0x00000000)],
      stops: const [0.0, 0.3, 0.8],
    );
    final outerShadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader = outerShadowGradient.createShader(rect);
    canvas.drawRRect(innerRRect.deflate(-1), outerShadowPaint);

    // === 3. INNER HIGHLIGHT (highlight on shadow side where light hits inner wall) ===
    final innerHighlightGradient = RadialGradient(
      center: shadowAlign,
      radius: 0.6,
      colors: const [Color(0xFF454545), Color(0xFF353535), Color(0x00000000)],
      stops: const [0.0, 0.2, 0.5],
    );
    final innerHighlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = innerHighlightGradient.createShader(rect);
    canvas.drawRRect(innerRRect.deflate(1), innerHighlightPaint);

    // === 4. FLOOR (the surface behind the hole) ===
    final floorRRect = rrect.deflate(borderInset + 1);
    final floorColor = value
        ? const Color(0xFFFFF176)  // Yellow when checked
        : const Color(0xFF1A1A1A); // Dark grey when unchecked

    final floorGradient = RadialGradient(
      center: lightAlign,
      radius: 0.7,
      colors: value
          ? [
              floorColor,
              Color.lerp(floorColor, Colors.black, 0.10)!,
              Color.lerp(floorColor, Colors.black, 0.20)!,
            ]
          : const [Color(0xFF1A1A1A), Color(0xFF141414), Color(0xFF0E0E0E)],
      stops: const [0.0, 0.5, 1.0],
    );
    final floorPaint = Paint()..shader = floorGradient.createShader(rect);
    canvas.drawRRect(floorRRect, floorPaint);

    // Highlight on floor when checked
    if (value) {
      final highlightGradient = RadialGradient(
        center: Alignment(light.dx * 0.6, light.dy * 0.6),
        radius: 0.5,
        colors: [
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.7],
      );
      final highlightPaint = Paint()..shader = highlightGradient.createShader(rect);
      canvas.drawRRect(floorRRect, highlightPaint);
    }

    // === NOISE TEXTURE ===
    if (lighting.noiseImage != null) {
      final noisePaint = Paint()
        ..shader = ImageShader(
          lighting.noiseImage!,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..blendMode = BlendMode.overlay;

      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(rect, noisePaint);
      canvas.restore();
    }

  }

  @override
  bool shouldRepaint(covariant _CheckboxPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.isHovered != isHovered ||
        oldDelegate.enabled != enabled ||
        oldDelegate.globalRect != globalRect ||
        oldDelegate.lighting.noiseImage != lighting.noiseImage;
  }
}
