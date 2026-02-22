import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'lighting_settings.dart';
import 'global_rect_tracking.dart';

class OscRadioList extends StatefulWidget {
  /// Each sublist is [value, label]
  final List<List<String>> options;

  /// If omitted, defaults to the first option's value
  final String? initialValue;

  /// Size of the radio button
  final double size;

  /// Whether to layout horizontally
  final bool horizontal;

  /// Spacing between options
  final double spacing;

  const OscRadioList({
    super.key,
    required this.options,
    this.initialValue,
    this.size = 20,
    this.horizontal = false,
    this.spacing = 8,
  });

  @override
  _OscRadioListState createState() => _OscRadioListState();
}

class _OscRadioListState extends State<OscRadioList>
    with OscAddressMixin<OscRadioList> {
  late String _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.initialValue ?? widget.options.first[0];
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    final incoming = args.isNotEmpty && args.first is String
        ? args.first as String
        : null;
    if (incoming != null && widget.options.any((o) => o[0] == incoming)) {
      setState(() => _selectedValue = incoming);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  void _select(String value) {
    if (value == _selectedValue) return;
    setState(() => _selectedValue = value);
    sendOsc(value);
  }

  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();

    final children = widget.options.map((opt) {
      final value = opt[0];
      final label = opt[1];
      final isSelected = value == _selectedValue;

      return _NeumorphicRadioOption(
        lighting: lighting,
        label: label,
        isSelected: isSelected,
        size: widget.size,
        onTap: () => _select(value),
      );
    }).toList();

    if (widget.horizontal) {
      return Wrap(
        spacing: widget.spacing,
        runSpacing: widget.spacing,
        children: children,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children
          .map((child) => Padding(
                padding: EdgeInsets.only(bottom: widget.spacing),
                child: child,
              ))
          .toList(),
    );
  }
}

class _NeumorphicRadioOption extends StatefulWidget {
  final LightingSettings lighting;
  final String label;
  final bool isSelected;
  final double size;
  final VoidCallback onTap;

  const _NeumorphicRadioOption({
    required this.lighting,
    required this.label,
    required this.isSelected,
    required this.size,
    required this.onTap,
  });

  @override
  State<_NeumorphicRadioOption> createState() => _NeumorphicRadioOptionState();
}

class _NeumorphicRadioOptionState extends State<_NeumorphicRadioOption> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NeumorphicRadioButton(
              lighting: widget.lighting,
              isSelected: widget.isSelected,
              size: widget.size,
              isHovered: _isHovered,
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                color: widget.isSelected ? Colors.white : Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeumorphicRadioButton extends StatefulWidget {
  final LightingSettings lighting;
  final bool isSelected;
  final double size;
  final bool isHovered;

  const _NeumorphicRadioButton({
    required this.lighting,
    required this.isSelected,
    required this.size,
    required this.isHovered,
  });

  @override
  State<_NeumorphicRadioButton> createState() => _NeumorphicRadioButtonState();
}

class _NeumorphicRadioButtonState extends State<_NeumorphicRadioButton>
    with GlobalRectTracking<_NeumorphicRadioButton> {

  @override
  Widget build(BuildContext context) {
    return Container(
      key: globalRectKey,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: widget.lighting.createNeumorphicShadows(
          elevation: 2.0,
          inset: true,
        ),
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: _RadioButtonPainter(
            lighting: widget.lighting,
            isSelected: widget.isSelected,
            isHovered: widget.isHovered,
            globalRect: trackedGlobalRect,
          ),
          size: Size(widget.size, widget.size),
        ),
      ),
    );
  }
}

class _RadioButtonPainter extends CustomPainter {
  final LightingSettings lighting;
  final bool isSelected;
  final bool isHovered;
  final Rect? globalRect;

  _RadioButtonPainter({
    required this.lighting,
    required this.isSelected,
    required this.isHovered,
    this.globalRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final rect = Offset.zero & size;

    // Slot dimensions (like the knob)
    final slotWidth = outerRadius * 0.8;  // Width of the slot/hole
    final borderWidth = slotWidth + 2;    // Border is slightly wider
    final floorWidth = slotWidth - 2;     // Floor is slightly smaller

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
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..shader = borderGradient.createShader(rect);
    canvas.drawCircle(center, outerRadius - borderWidth / 2, borderPaint);

    // === 2. OUTER SHADOW (shadow on lit side where rim blocks light into hole) ===
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
    final outerShadowRadius = outerRadius - borderWidth / 2 + slotWidth / 2 - 1;
    canvas.drawCircle(center, outerShadowRadius, outerShadowPaint);

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
    final innerHighlightRadius = outerRadius - borderWidth / 2 - slotWidth / 2 + 1;
    canvas.drawCircle(center, innerHighlightRadius, innerHighlightPaint);

    // === 4. FLOOR (dark background of slot) - filled circle ===
    final floorRadius = outerRadius - borderWidth / 2 + floorWidth / 2;
    final floorRect = Rect.fromCircle(center: center, radius: floorRadius);
    final floorGradient = RadialGradient(
      center: lightAlign,
      radius: 0.7,
      colors: const [Color(0xFF1C1C1C), Color(0xFF161616), Color(0xFF101010)],
      stops: const [0.0, 0.5, 1.0],
    );
    final floorPaint = Paint()
      ..shader = floorGradient.createShader(floorRect);
    canvas.drawCircle(center, floorRadius, floorPaint);

    // === 5. VALUE SURFACE (colored disk when selected) - filled circle ===
    if (isSelected) {
      const baseColor = Color(0xFFFFF176);
      final valueGradient = RadialGradient(
        center: lightAlign,
        radius: 0.8,
        colors: [
          baseColor,
          Color.lerp(baseColor, Colors.black, 0.10)!,
          Color.lerp(baseColor, Colors.black, 0.20)!,
        ],
        stops: const [0.0, 0.5, 1.0],
      );
      final valuePaint = Paint()
        ..shader = valueGradient.createShader(floorRect);
      canvas.drawCircle(center, floorRadius, valuePaint);

      // Highlight on value surface
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
      final highlightPaint = Paint()
        ..shader = highlightGradient.createShader(floorRect);
      canvas.drawCircle(center, floorRadius, highlightPaint);
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
      canvas.clipPath(Path()..addOval(rect));
      canvas.drawRect(rect, noisePaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RadioButtonPainter oldDelegate) {
    return oldDelegate.isSelected != isSelected ||
        oldDelegate.isHovered != isHovered ||
        oldDelegate.globalRect != globalRect ||
        oldDelegate.lighting.noiseImage != lighting.noiseImage;
  }
}

/// A single neumorphic radio button for use outside of OscRadioList
class NeumorphicRadio<T> extends StatefulWidget {
  final T value;
  final T groupValue;
  final ValueChanged<T> onChanged;
  final String? label;
  final double size;

  const NeumorphicRadio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.label,
    this.size = 20,
  });

  @override
  State<NeumorphicRadio<T>> createState() => _NeumorphicRadioState<T>();
}

class _NeumorphicRadioState<T> extends State<NeumorphicRadio<T>> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();
    final isSelected = widget.value == widget.groupValue;

    Widget radio = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onChanged(widget.value),
        child: _NeumorphicRadioButton(
          lighting: lighting,
          isSelected: isSelected,
          size: widget.size,
          isHovered: _isHovered,
        ),
      ),
    );

    if (widget.label != null) {
      return GestureDetector(
        onTap: () => widget.onChanged(widget.value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            radio,
            const SizedBox(width: 8),
            Text(
              widget.label!,
              style: TextStyle(
                fontSize: 13,
                color: isSelected ? Colors.white : Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    return radio;
  }
}
