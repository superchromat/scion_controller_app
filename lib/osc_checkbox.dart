import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'lighting_settings.dart';

class OscCheckbox extends StatefulWidget {
  final bool initialValue;
  final bool readOnly;
  final String? label;
  final double size;

  const OscCheckbox({
    super.key,
    this.initialValue = false,
    this.readOnly = false,
    this.label,
    this.size = 22,
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
    setState(() => _value = !_value);
    sendOsc(_value);
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

class _NeumorphicCheckbox extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: lighting.createNeumorphicShadows(
          elevation: 2.0,
          inset: true,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          painter: _CheckboxPainter(
            lighting: lighting,
            value: value,
            isHovered: isHovered,
            enabled: enabled,
          ),
          size: Size(size, size),
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

  _CheckboxPainter({
    required this.lighting,
    required this.value,
    required this.isHovered,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    // Inset background
    final baseColor = enabled
        ? (isHovered ? const Color(0xFF2E2E30) : const Color(0xFF262628))
        : const Color(0xFF1E1E20);

    final gradient = lighting.createLinearSurfaceGradient(
      baseColor: baseColor,
      intensity: 0.04,
    );
    final bgPaint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, bgPaint);

    // Inner shadow border
    final light = lighting.lightDir2D;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment(light.dx, light.dy),
        end: Alignment(-light.dx, -light.dy),
        colors: [
          Colors.black.withValues(alpha: 0.3),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(0.5), borderPaint);

    // Noise texture
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

    // Check mark when selected
    if (value) {
      final checkPaint = Paint()
        ..color = const Color(0xFFFFF176)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final cx = size.width / 2;
      final cy = size.height / 2;
      final s = size.width * 0.25;

      path.moveTo(cx - s, cy);
      path.lineTo(cx - s * 0.3, cy + s * 0.7);
      path.lineTo(cx + s, cy - s * 0.6);

      canvas.drawPath(path, checkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CheckboxPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.isHovered != isHovered ||
        oldDelegate.enabled != enabled ||
        oldDelegate.lighting.noiseImage != lighting.noiseImage;
  }
}
