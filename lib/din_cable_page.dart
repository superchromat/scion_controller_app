import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'lighting_settings.dart';

class DinCablePage extends StatefulWidget {
  const DinCablePage({super.key});

  @override
  State<DinCablePage> createState() => _DinCablePageState();
}

class _DinCablePageState extends State<DinCablePage> {
  String _selectedSync = 'locked';

  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon 1: Lock - Sync Locked to Sends
            _SyncTile(
              lighting: lighting,
              label: 'Sync locked\nto sends',
              isSelected: _selectedSync == 'locked',
              onTap: () => setState(() => _selectedSync = 'locked'),
              child: CustomPaint(
                size: const Size(50, 65),
                painter: _LockPainter(),
              ),
            ),
            const SizedBox(width: 16),
            // Icon 2: 3 cables (G, B, R) - Component Sync
            _SyncTile(
              lighting: lighting,
              label: 'Component\nsync (Y/G)',
              isSelected: _selectedSync == 'component',
              onTap: () => setState(() => _selectedSync = 'component'),
              cableColors: const [
                Color(0xFF22AA22), // Green
                Color(0xFF2266DD), // Blue
                Color(0xFFDD2222), // Red
              ],
              selectedCableIndices: const [0], // Green has yellow border
            ),
            const SizedBox(width: 16),
            // Icon 3: 5 cables (G, B, R, W, Grey) - External Sync
            _SyncTile(
              lighting: lighting,
              label: 'External H/V\nsync input',
              isSelected: _selectedSync == 'external',
              onTap: () => setState(() => _selectedSync = 'external'),
              cableColors: const [
                Color(0xFF22AA22), // Green
                Color(0xFF2266DD), // Blue
                Color(0xFFDD2222), // Red
                Color(0xFFE0E0E0), // White
                Color(0xFF808080), // Grey
              ],
              selectedCableIndices: const [3, 4], // White and Grey have yellow border
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncTile extends StatelessWidget {
  final LightingSettings lighting;
  final String label;
  final Widget? child;
  final bool isSelected;
  final VoidCallback onTap;
  final List<Color>? cableColors;
  final List<int>? selectedCableIndices;

  const _SyncTile({
    required this.lighting,
    required this.label,
    this.child,
    required this.isSelected,
    required this.onTap,
    this.cableColors,
    this.selectedCableIndices,
  });

  @override
  Widget build(BuildContext context) {
    const double tileWidth = 100.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: tileWidth,
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: lighting.createNeumorphicShadows(elevation: 4.0),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CustomPaint(
            painter: _TilePainter(lighting: lighting, isSelected: isSelected),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: cableColors != null
                          ? CustomPaint(
                              size: Size(tileWidth - 16, 65),
                              painter: _CableGroupPainter(
                                cableColors: cableColors!,
                                selectedIndices: selectedCableIndices ?? const [],
                              ),
                            )
                          : child ?? const SizedBox(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? Colors.white : Colors.grey[400],
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TilePainter extends CustomPainter {
  final LightingSettings lighting;
  final bool isSelected;

  _TilePainter({required this.lighting, required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    // Base gradient with lighting
    final baseColor = isSelected ? const Color(0xFF606068) : const Color(0xFF505055);
    final gradient = lighting.createPhongSurfaceGradient(
      baseColor: baseColor,
      intensity: 0.08,
    );
    canvas.drawRRect(rrect, Paint()..shader = gradient.createShader(rect));

    // Inner border highlight based on light direction (matching NeumorphicCardPainter)
    final light = lighting.lightDir2D;
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment(light.dx, light.dy),
        end: Alignment(-light.dx, -light.dy),
        colors: [
          Colors.white.withValues(alpha: 0.08),
          Colors.transparent,
          Colors.black.withValues(alpha: 0.12),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawRRect(rrect.deflate(0.5), highlightPaint);

    // Selection indicator - yellow border
    if (isSelected) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = const Color(0xFFFFD700)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Noise texture
    if (lighting.noiseImage != null) {
      final noisePaint = Paint()
        ..shader = ui.ImageShader(
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
  bool shouldRepaint(covariant _TilePainter old) =>
      old.lighting.lightPhi != lighting.lightPhi ||
      old.lighting.lightTheta != lighting.lightTheta ||
      old.lighting.noiseImage != lighting.noiseImage ||
      old.isSelected != isSelected;
}

class _LockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;

    // === Shackle (U-shaped metal part) ===
    const shackleOuterRadius = 16.0;
    const shackleThickness = 5.0;
    const shackleTop = 4.0;
    final shackleBottom = size.height * 0.42;

    // Draw shackle as a single U-shaped path with gradient
    final shackleCenterRadius = shackleOuterRadius - shackleThickness / 2;
    final arcCenter = Offset(centerX, shackleTop + shackleOuterRadius);

    // Create U-shape path (arc + two vertical lines)
    final shacklePath = Path();
    // Start at bottom left
    shacklePath.moveTo(centerX - shackleCenterRadius, shackleBottom);
    // Line up to arc start
    shacklePath.lineTo(centerX - shackleCenterRadius, arcCenter.dy);
    // Arc across top
    shacklePath.arcToPoint(
      Offset(centerX + shackleCenterRadius, arcCenter.dy),
      radius: Radius.circular(shackleCenterRadius),
      clockwise: true,
    );
    // Line down to bottom right
    shacklePath.lineTo(centerX + shackleCenterRadius, shackleBottom);

    // Draw with gradient stroke
    final shacklePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = shackleThickness
      ..strokeCap = StrokeCap.butt
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const [
          Color(0xFF808080),
          Color(0xFFB0B0B0),
          Color(0xFFD8D8D8),
          Color(0xFFB0B0B0),
          Color(0xFF808080),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(
        centerX - shackleOuterRadius,
        shackleTop,
        shackleOuterRadius * 2,
        shackleBottom - shackleTop,
      ));

    canvas.drawPath(shacklePath, shacklePaint);

    // Add highlight on top edge of arc
    canvas.drawArc(
      Rect.fromCircle(center: arcCenter, radius: shackleCenterRadius),
      3.14159,
      3.14159,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.4),
    );

    // === Lock body ===
    final bodyTop = shackleBottom - 5;
    final bodyBottom = size.height - 2;
    final bodyLeft = centerX - 20;
    final bodyRight = centerX + 20;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(bodyLeft, bodyTop, bodyRight, bodyBottom),
      const Radius.circular(4),
    );

    // Body gradient (brass/gold color)
    final bodyGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFFD4A84B),
        const Color(0xFFB8922F),
        const Color(0xFF9A7B28),
        const Color(0xFF7A6020),
      ],
      stops: const [0.0, 0.3, 0.7, 1.0],
    );

    canvas.drawRRect(
      bodyRect,
      Paint()..shader = bodyGradient.createShader(bodyRect.outerRect),
    );

    // Body edge highlight
    canvas.drawRRect(
      bodyRect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.3),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.2),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(bodyRect.outerRect),
    );

    // === Keyhole ===
    final keyholeY = bodyTop + (bodyBottom - bodyTop) * 0.45;

    // Keyhole circle (dark inset)
    final keyholeGradient = RadialGradient(
      center: const Alignment(-0.3, -0.3),
      colors: [
        const Color(0xFF3A3A3A),
        const Color(0xFF1A1A1A),
      ],
    );
    final keyholeRect = Rect.fromCircle(center: Offset(centerX, keyholeY), radius: 5);
    canvas.drawCircle(
      Offset(centerX, keyholeY),
      5,
      Paint()..shader = keyholeGradient.createShader(keyholeRect),
    );

    // Keyhole slot
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(centerX, keyholeY + 7), width: 4, height: 10),
        const Radius.circular(1.5),
      ),
      Paint()..shader = keyholeGradient.createShader(keyholeRect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CableGroupPainter extends CustomPainter {
  final List<Color> cableColors;
  final List<int> selectedIndices;

  _CableGroupPainter({
    required this.cableColors,
    required this.selectedIndices,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cableCount = cableColors.length;
    const scale = 1.0 / 3.0;
    const spacing = 14.0;

    // Center the middle cable in the tile
    // totalWidth spans from first cable center to last cable center
    final totalWidth = (cableCount - 1) * spacing;
    final startX = (size.width - totalWidth) / 2;

    for (int i = 0; i < cableCount; i++) {
      canvas.save();
      // Position at center of each cable
      final x = startX + i * spacing;
      canvas.translate(x, size.height);
      canvas.rotate(-3.14159265 / 2);
      canvas.scale(scale);
      // Offset by centerY so cable is centered on the translate point
      canvas.translate(0, -12);

      _drawCable(canvas, cableColors[i], selectedIndices.contains(i));

      canvas.restore();
    }
  }

  void _drawCable(Canvas canvas, Color heatShrinkColor, bool showYellowBorder) {
    const centerY = 12.0;

    // Border if selected: thin grey line inside, thicker yellow outside
    if (showYellowBorder) {
      // Cable outline path (shortened)
      final path = Path();
      path.moveTo(0, centerY - 5);
      path.lineTo(108, centerY - 5);
      path.lineTo(108, centerY - 10);
      path.lineTo(116, centerY - 10);
      path.lineTo(116, centerY - 11);
      path.lineTo(179, centerY - 11);
      path.lineTo(189, centerY - 6);
      path.lineTo(189, centerY + 6);
      path.lineTo(179, centerY + 11);
      path.lineTo(116, centerY + 11);
      path.lineTo(116, centerY + 10);
      path.lineTo(108, centerY + 10);
      path.lineTo(108, centerY + 5);
      path.lineTo(0, centerY + 5);
      path.close();

      // Outer yellow border (thicker)
      canvas.drawPath(path, Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18);

      // Inner grey border (thinner)
      canvas.drawPath(path, Paint()
        ..color = const Color(0xFF606060)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12);
    }

    // === Braided cable section (shortened) ===
    _drawCylindricalSection(
      canvas: canvas,
      startX: 0,
      centerY: centerY,
      width: 65,
      radius: 5,
      baseColor: const Color(0xFFD4B896),
      highlightColor: const Color(0xFFEEDDC0),
      shadowColor: const Color(0xFFA08060),
    );
    _drawBraidPattern(canvas, 0, centerY, 65, 5);

    // === Colored heat shrink section ===
    final hsl = HSLColor.fromColor(heatShrinkColor);
    _drawCylindricalSection(
      canvas: canvas,
      startX: 60,
      centerY: centerY,
      width: 50,
      radius: 5,
      baseColor: heatShrinkColor,
      highlightColor: hsl.withLightness((hsl.lightness + 0.2).clamp(0, 1)).toColor(),
      shadowColor: hsl.withLightness((hsl.lightness - 0.2).clamp(0, 1)).toColor(),
    );

    // === Rear ferrule (silver) ===
    _drawCylindricalSection(
      canvas: canvas,
      startX: 108,
      centerY: centerY,
      width: 10,
      radius: 10,
      baseColor: const Color(0xFFB0B0B0),
      highlightColor: const Color(0xFFE8E8E8),
      shadowColor: const Color(0xFF606060),
    );

    // === Smooth band ===
    _drawCylindricalSection(
      canvas: canvas,
      startX: 116,
      centerY: centerY,
      width: 20,
      radius: 11,
      baseColor: const Color(0xFFB8B8B8),
      highlightColor: const Color(0xFFE8E8E8),
      shadowColor: const Color(0xFF707070),
    );

    // === Ridge/groove ===
    _drawGroove(canvas, 127, centerY, 11);

    // === Knurled grip ===
    _drawCylindricalSection(
      canvas: canvas,
      startX: 134,
      centerY: centerY,
      width: 45,
      radius: 11,
      baseColor: const Color(0xFFA8A8A8),
      highlightColor: const Color(0xFFD8D8D8),
      shadowColor: const Color(0xFF606060),
    );
    _drawKnurlPattern(canvas, 134, centerY, 45, 11);

    // === Taper section ===
    _drawTaper(canvas, 177, centerY, 11, 6, 12);
  }

  void _drawCylindricalSection({
    required Canvas canvas,
    required double startX,
    required double centerY,
    required double width,
    required double radius,
    required Color baseColor,
    required Color highlightColor,
    required Color shadowColor,
  }) {
    final rect = Rect.fromLTWH(startX, centerY - radius, width, radius * 2);

    // Main cylindrical gradient (top highlight, middle base, bottom shadow)
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        highlightColor,
        Color.lerp(highlightColor, baseColor, 0.3)!,
        baseColor,
        Color.lerp(baseColor, shadowColor, 0.5)!,
        shadowColor,
      ],
      stops: const [0.0, 0.15, 0.4, 0.75, 1.0],
    );

    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);

    // Subtle edge highlight on top
    final topEdge = Paint()
      ..color = highlightColor.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(startX, centerY - radius + 0.5),
      Offset(startX + width, centerY - radius + 0.5),
      topEdge,
    );

    // Subtle shadow on bottom
    final bottomEdge = Paint()
      ..color = shadowColor.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(startX, centerY + radius - 0.5),
      Offset(startX + width, centerY + radius - 0.5),
      bottomEdge,
    );
  }

  void _drawBraidPattern(Canvas canvas, double startX, double centerY, double width, double radius) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(startX, centerY - radius, width, radius * 2));

    final darkBraid = Paint()
      ..color = const Color(0xFFB08050).withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final lightBraid = Paint()
      ..color = const Color(0xFFF0E0C0).withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Diamond braid pattern
    for (double x = startX - radius * 2; x < startX + width + radius * 2; x += 8) {
      // Diagonal lines going down-right
      canvas.drawLine(
        Offset(x, centerY - radius),
        Offset(x + radius * 2, centerY + radius),
        darkBraid,
      );
      // Diagonal lines going up-right
      canvas.drawLine(
        Offset(x, centerY + radius),
        Offset(x + radius * 2, centerY - radius),
        lightBraid,
      );
    }

    canvas.restore();
  }

  void _drawKnurlPattern(Canvas canvas, double startX, double centerY, double width, double radius) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(startX, centerY - radius, width, radius * 2));

    final darkLine = Paint()
      ..color = const Color(0xFF505050).withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final lightLine = Paint()
      ..color = const Color(0xFFE0E0E0).withValues(alpha: 0.4)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Diamond knurl pattern
    for (double x = startX - radius * 2; x < startX + width + radius * 2; x += 3.5) {
      canvas.drawLine(
        Offset(x, centerY - radius),
        Offset(x + radius * 2, centerY + radius),
        darkLine,
      );
      canvas.drawLine(
        Offset(x + 0.5, centerY - radius),
        Offset(x + radius * 2 + 0.5, centerY + radius),
        lightLine,
      );
      canvas.drawLine(
        Offset(x, centerY + radius),
        Offset(x + radius * 2, centerY - radius),
        darkLine,
      );
    }

    canvas.restore();
  }

  void _drawGroove(Canvas canvas, double x, double centerY, double radius) {
    // Dark groove line
    canvas.drawLine(
      Offset(x, centerY - radius),
      Offset(x, centerY + radius),
      Paint()
        ..color = const Color(0xFF404040)
        ..strokeWidth = 2,
    );
    // Light edge (highlight)
    canvas.drawLine(
      Offset(x + 2, centerY - radius),
      Offset(x + 2, centerY + radius),
      Paint()
        ..color = const Color(0xFFD0D0D0)
        ..strokeWidth = 1,
    );
  }

  void _drawTaper(Canvas canvas, double startX, double centerY, double startRadius, double endRadius, double width) {
    final path = Path();
    path.moveTo(startX, centerY - startRadius);
    path.lineTo(startX + width, centerY - endRadius);
    path.lineTo(startX + width, centerY + endRadius);
    path.lineTo(startX, centerY + startRadius);
    path.close();

    // Gradient for taper
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFFE0E0E0),
        const Color(0xFFB0B0B0),
        const Color(0xFF808080),
      ],
    );

    final rect = Rect.fromLTWH(startX, centerY - startRadius, width, startRadius * 2);
    canvas.drawPath(path, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _CableGroupPainter old) =>
      old.cableColors != cableColors || old.selectedIndices != selectedIndices;
}
