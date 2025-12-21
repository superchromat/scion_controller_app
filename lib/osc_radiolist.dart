import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'lighting_settings.dart';

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

class _NeumorphicRadioButtonState extends State<_NeumorphicRadioButton> {
  final GlobalKey _key = GlobalKey();
  Rect? _globalRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGlobalRect());
  }

  void _updateGlobalRect() {
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final position = renderBox.localToGlobal(Offset.zero);
      final newRect = position & renderBox.size;
      if (_globalRect != newRect) {
        setState(() => _globalRect = newRect);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGlobalRect());

    return Container(
      key: _key,
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
            globalRect: _globalRect,
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
    final radius = size.width / 2;
    final rect = Offset.zero & size;

    // Inset background with global position for Phong shading
    final baseColor = isHovered ? const Color(0xFF2E2E30) : const Color(0xFF262628);

    final gradient = lighting.createPhongSurfaceGradient(
      baseColor: baseColor,
      intensity: 0.04,
      globalRect: globalRect,
    );
    final bgPaint = Paint()..shader = gradient.createShader(rect);
    canvas.drawCircle(center, radius, bgPaint);

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
    canvas.drawCircle(center, radius - 0.5, borderPaint);

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
      canvas.clipPath(Path()..addOval(rect));
      canvas.drawRect(rect, noisePaint);
      canvas.restore();
    }

    // Selected dot
    if (isSelected) {
      final dotRadius = radius * 0.4;

      // Glow
      final glowPaint = Paint()
        ..color = const Color(0xFFFFF176).withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(center, dotRadius + 2, glowPaint);

      // Solid dot
      final dotPaint = Paint()..color = const Color(0xFFFFF176);
      canvas.drawCircle(center, dotRadius, dotPaint);
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
