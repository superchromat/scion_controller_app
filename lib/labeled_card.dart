import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'osc_widget_binding.dart';
import 'lighting_settings.dart';

class LabeledCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool networkIndependent;

  const LabeledCard({
    super.key,
    required this.title,
    required this.child,
    this.networkIndependent = false,
  });

  @override
  Widget build(BuildContext context) {
    // rebuild on network status
    // ignore for now final connected = context.watch<Network>().isConnected;
    // TODO: Re-enable connection check when device is back online
    const disabled = false; // !networkIndependent && !connected;

    // compute OSC namespace prefix for this card
    final prefix = '/${OscPathSegment.resolvePath(context).join('/')}';

    // Get lighting settings
    final lighting = context.watch<LightingSettings>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: IgnorePointer(
        ignoring: disabled,
        child: Opacity(
          opacity: disabled ? 0.2 : 1.0,
          child: _NeumorphicCard(
            lighting: lighting,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // title row with reset button
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A neumorphic card widget with subtle gradients, shadows, and noise texture.
class _NeumorphicCard extends StatelessWidget {
  final LightingSettings lighting;
  final Widget child;
  final Color baseColor;
  final double borderRadius;
  final double elevation;

  const _NeumorphicCard({
    required this.lighting,
    required this.child,
    this.baseColor = const Color(0xFF3A3A3C),
    this.borderRadius = 8.0,
    this.elevation = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: lighting.createNeumorphicShadows(elevation: elevation),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CustomPaint(
          painter: _NeumorphicCardPainter(
            lighting: lighting,
            baseColor: baseColor,
            borderRadius: borderRadius,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Painter for neumorphic card background with gradient and noise texture.
class _NeumorphicCardPainter extends CustomPainter {
  final LightingSettings lighting;
  final Color baseColor;
  final double borderRadius;

  _NeumorphicCardPainter({
    required this.lighting,
    required this.baseColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Base gradient fill
    final gradient = lighting.createLinearSurfaceGradient(
      baseColor: baseColor,
      intensity: 0.03,
    );
    final gradientPaint = Paint()
      ..shader = gradient.createShader(rect);

    canvas.drawRRect(rrect, gradientPaint);

    // Subtle inner border highlight on lit edge
    final light = lighting.lightDir2D;
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment(light.dx, light.dy),
        end: Alignment(-light.dx, -light.dy),
        colors: [
          Colors.white.withValues(alpha: 0.06),
          Colors.transparent,
          Colors.black.withValues(alpha: 0.08),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawRRect(
      rrect.deflate(0.5),
      highlightPaint,
    );

    // Noise texture overlay
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
  bool shouldRepaint(covariant _NeumorphicCardPainter oldDelegate) {
    return oldDelegate.lighting.lightPhi != lighting.lightPhi ||
        oldDelegate.lighting.lightTheta != lighting.lightTheta ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.lighting.noiseImage != lighting.noiseImage;
  }
}

/// A standalone neumorphic container that can be used anywhere.
/// This is a public version of the internal card widget.
class NeumorphicContainer extends StatelessWidget {
  final Widget child;
  final Color baseColor;
  final double borderRadius;
  final double elevation;
  final EdgeInsetsGeometry? padding;

  const NeumorphicContainer({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFF3A3A3C),
    this.borderRadius = 8.0,
    this.elevation = 4.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: lighting.createNeumorphicShadows(elevation: elevation),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CustomPaint(
          painter: _NeumorphicCardPainter(
            lighting: lighting,
            baseColor: baseColor,
            borderRadius: borderRadius,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// An inset neumorphic container (appears pressed in).
class NeumorphicInset extends StatelessWidget {
  final Widget child;
  final Color baseColor;
  final double borderRadius;
  final double depth;
  final EdgeInsetsGeometry? padding;

  const NeumorphicInset({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFF2A2A2C),
    this.borderRadius = 6.0,
    this.depth = 3.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: lighting.createNeumorphicShadows(
          elevation: depth,
          inset: true,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CustomPaint(
          painter: _NeumorphicInsetPainter(
            lighting: lighting,
            baseColor: baseColor,
            borderRadius: borderRadius,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Painter for inset neumorphic container.
class _NeumorphicInsetPainter extends CustomPainter {
  final LightingSettings lighting;
  final Color baseColor;
  final double borderRadius;

  _NeumorphicInsetPainter({
    required this.lighting,
    required this.baseColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Darker base for inset
    final gradient = lighting.createLinearSurfaceGradient(
      baseColor: baseColor,
      intensity: 0.04,
    );
    final gradientPaint = Paint()
      ..shader = gradient.createShader(rect);

    canvas.drawRRect(rrect, gradientPaint);

    // Inner shadow border (inverted from raised)
    final light = lighting.lightDir2D;
    final shadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
        begin: Alignment(light.dx, light.dy),
        end: Alignment(-light.dx, -light.dy),
        colors: [
          Colors.black.withValues(alpha: 0.15),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.03),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawRRect(
      rrect.deflate(0.75),
      shadowPaint,
    );

    // Noise texture overlay
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
  bool shouldRepaint(covariant _NeumorphicInsetPainter oldDelegate) {
    return oldDelegate.lighting.lightPhi != lighting.lightPhi ||
        oldDelegate.lighting.lightTheta != lighting.lightTheta ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.lighting.noiseImage != lighting.noiseImage;
  }
}
