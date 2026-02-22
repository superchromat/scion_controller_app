import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'grid.dart';
import 'network.dart';
import 'osc_widget_binding.dart';
import 'lighting_settings.dart';

class LabeledCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool networkIndependent;
  final Widget? action;
  final bool fillChild;

  const LabeledCard({
    super.key,
    required this.title,
    required this.child,
    this.networkIndependent = false,
    this.action,
    this.fillChild = false,
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

    // Use grid tokens when available, fall back to legacy gutter.
    final t = GridProvider.maybeOf(context);
    final titlePadH = t?.cardTitleAlignToPanelTitle ?? 16.0;
    final titlePadTop = t?.md ?? (GridGutterProvider.maybeOf(context) ?? 16.0);
    final titleGap = t?.xs ?? (titlePadTop / 2);
    final contentPadH = 0.0; // GridRow handles horizontal spacing
    final contentPadBot = t?.md ?? (GridGutterProvider.maybeOf(context) ?? 16.0);
    final titleStyle = t?.textTitle ?? Theme.of(context).textTheme.titleLarge!;

    return IgnorePointer(
      ignoring: disabled,
      child: Opacity(
        opacity: disabled ? 0.2 : 1.0,
        child: _NeumorphicCard(
          lighting: lighting,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(titlePadH, titlePadTop, titlePadH, 0),
                child: Row(
                  children: [
                    Expanded(child: Text(title, style: titleStyle)),
                    if (action != null) action!,
                  ],
                ),
              ),
              SizedBox(height: titleGap),
              if (fillChild)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(contentPadH, 0, contentPadH, contentPadBot),
                    child: child,
                  ),
                )
              else
                Padding(
                  padding: EdgeInsets.fromLTRB(contentPadH, 0, contentPadH, contentPadBot),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A neumorphic card widget with subtle gradients, shadows, and noise texture.
/// Tracks its global position for physically accurate lighting.
class _NeumorphicCard extends StatefulWidget {
  final LightingSettings lighting;
  final Widget child;
  final Color baseColor;
  final double borderRadius;
  final double elevation;

  const _NeumorphicCard({
    required this.lighting,
    required this.child,
    this.baseColor = const Color(0xFF323236),
    this.borderRadius = 8.0,
    this.elevation = 4.0,
  });

  @override
  State<_NeumorphicCard> createState() => _NeumorphicCardState();
}

class _NeumorphicCardState extends State<_NeumorphicCard> {
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
    // Update position on each build in case of scroll/resize
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGlobalRect());

    return Container(
      key: _key,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: widget.lighting.createNeumorphicShadows(elevation: widget.elevation),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: CustomPaint(
          painter: _NeumorphicCardPainter(
            lighting: widget.lighting,
            baseColor: widget.baseColor,
            borderRadius: widget.borderRadius,
            globalRect: _globalRect,
          ),
          child: widget.child,
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
  final Rect? globalRect;

  _NeumorphicCardPainter({
    required this.lighting,
    required this.baseColor,
    required this.borderRadius,
    this.globalRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Base gradient fill using Phong diffuse shading with global position
    final gradient = lighting.createPhongSurfaceGradient(
      baseColor: baseColor,
      intensity: 0.035,
      globalRect: globalRect,
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
          Colors.white.withValues(alpha: 0.085),
          Colors.transparent,
          Colors.black.withValues(alpha: 0.06),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawRRect(
      rrect.deflate(0.5),
      highlightPaint,
    );

    // Noise texture overlay - DISABLED FOR DEBUG
    // if (lighting.noiseImage != null) {
    //   final noisePaint = Paint()
    //     ..shader = ImageShader(
    //       lighting.noiseImage!,
    //       TileMode.repeated,
    //       TileMode.repeated,
    //       Matrix4.identity().storage,
    //     )
    //     ..blendMode = BlendMode.overlay;
    //   canvas.save();
    //   canvas.clipRRect(rrect);
    //   canvas.drawRect(rect, noisePaint);
    //   canvas.restore();
    // }
  }

  @override
  bool shouldRepaint(covariant _NeumorphicCardPainter oldDelegate) {
    return oldDelegate.lighting.lightPhi != lighting.lightPhi ||
        oldDelegate.lighting.lightTheta != lighting.lightTheta ||
        oldDelegate.lighting.lightDistance != lighting.lightDistance ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.globalRect != globalRect ||
        oldDelegate.lighting.noiseImage != lighting.noiseImage;
  }
}

/// A standalone neumorphic container that can be used anywhere.
/// This is a public version of the internal card widget.
/// Tracks global position for physically accurate lighting.
class NeumorphicContainer extends StatefulWidget {
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
  State<NeumorphicContainer> createState() => _NeumorphicContainerState();
}

class _NeumorphicContainerState extends State<NeumorphicContainer> {
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
    final lighting = context.watch<LightingSettings>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGlobalRect());

    Widget content = widget.child;
    if (widget.padding != null) {
      content = Padding(padding: widget.padding!, child: content);
    }

    return Container(
      key: _key,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: lighting.createNeumorphicShadows(elevation: widget.elevation),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: CustomPaint(
          painter: _NeumorphicCardPainter(
            lighting: lighting,
            baseColor: widget.baseColor,
            borderRadius: widget.borderRadius,
            globalRect: _globalRect,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// An inset neumorphic container (appears pressed in).
/// Tracks global position for physically accurate lighting.
class NeumorphicInset extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final double borderRadius;
  final double depth;
  final EdgeInsetsGeometry? padding;

  const NeumorphicInset({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFF29292D),
    this.borderRadius = 6.0,
    this.depth = 3.0,
    this.padding,
  });

  @override
  State<NeumorphicInset> createState() => _NeumorphicInsetState();
}

class _NeumorphicInsetState extends State<NeumorphicInset> {
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
    final lighting = context.watch<LightingSettings>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGlobalRect());

    Widget content = widget.child;
    if (widget.padding != null) {
      content = Padding(padding: widget.padding!, child: content);
    }

    return Container(
      key: _key,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: lighting.createNeumorphicShadows(
          elevation: widget.depth,
          inset: true,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: CustomPaint(
          painter: _NeumorphicInsetPainter(
            lighting: lighting,
            baseColor: widget.baseColor,
            borderRadius: widget.borderRadius,
            globalRect: _globalRect,
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
  final Rect? globalRect;

  _NeumorphicInsetPainter({
    required this.lighting,
    required this.baseColor,
    required this.borderRadius,
    this.globalRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Darker base for inset using Phong diffuse shading with global position
    final gradient = lighting.createPhongSurfaceGradient(
      baseColor: baseColor,
      intensity: 0.035,
      globalRect: globalRect,
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
          Colors.black.withValues(alpha: 0.12),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.06),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawRRect(
      rrect.deflate(0.75),
      shadowPaint,
    );

    // Noise texture overlay - DISABLED FOR DEBUG
    // if (lighting.noiseImage != null) {
    //   final noisePaint = Paint()
    //     ..shader = ImageShader(
    //       lighting.noiseImage!,
    //       TileMode.repeated,
    //       TileMode.repeated,
    //       Matrix4.identity().storage,
    //     )
    //     ..blendMode = BlendMode.overlay;
    //   canvas.save();
    //   canvas.clipRRect(rrect);
    //   canvas.drawRect(rect, noisePaint);
    //   canvas.restore();
    // }
  }

  @override
  bool shouldRepaint(covariant _NeumorphicInsetPainter oldDelegate) {
    return oldDelegate.lighting.lightPhi != lighting.lightPhi ||
        oldDelegate.lighting.lightTheta != lighting.lightTheta ||
        oldDelegate.lighting.lightDistance != lighting.lightDistance ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.globalRect != globalRect ||
        oldDelegate.lighting.noiseImage != lighting.noiseImage;
  }
}
