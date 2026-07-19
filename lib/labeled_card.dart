import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'grid.dart';
import 'osc_registry.dart';
import 'lighting_settings.dart';
import 'global_rect_tracking.dart';
import 'network.dart';
import 'osc_widget_binding.dart';

class LabeledCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool networkIndependent;
  final Widget? action;
  final bool fillChild;
  final Color? borderColor;

  /// OSC subtree this card's controls live under, enabling the preset
  /// save / load / reset icons. Relative values (e.g. 'text') append to the
  /// ambient OscPathSegment path ('send/1' -> '/send/1/text'); a leading '/'
  /// makes it absolute. Presets are NAMED and stored on the DEVICE via
  /// /assets/presets/*; a card can have any number of them.
  final String? snapPath;

  /// Optional extra reset run alongside the subtree "Reset to defaults" icon.
  /// For cards whose controls span more than one OSC subtree (e.g. Texture,
  /// which also holds the glitch block on /send/N/glitch and needs its own
  /// hardware reinit), this folds the second reset into the same button so
  /// there's a single "Reset to defaults".
  final VoidCallback? onReset;

  const LabeledCard({
    super.key,
    required this.title,
    required this.child,
    this.networkIndependent = false,
    this.action,
    this.fillChild = false,
    this.borderColor,
    this.snapPath,
    this.onReset,
  });

  String _resolveSnapPath(BuildContext context) {
    if (snapPath!.startsWith('/')) return snapPath!;
    final segs = OscPathSegment.resolvePath(context);
    return '/${[...segs, snapPath!].join('/')}';
  }

  void _toast(BuildContext context, String m) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
  }

  /// One request/reply against the preset endpoints.
  Future<List<Object?>?> _call(BuildContext context, String addr,
      List<Object> args) async {
    final net = context.read<Network>();
    final c = Completer<List<Object?>>();
    void listener(List<Object?> a) {
      if (!c.isCompleted) c.complete(a);
    }

    OscRegistry().registerAddress(addr);
    OscRegistry().registerListener(addr, listener);
    try {
      net.sendOscMessage(addr, args, immediate: true); // synchronous RPC
      return await c.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      return null;
    } finally {
      OscRegistry().unregisterListener(addr, listener);
    }
  }

  Future<void> _savePreset(BuildContext context) async {
    final path = _resolveSnapPath(context);
    final ctl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Save $title preset'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 31,
          decoration: const InputDecoration(hintText: 'preset name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    final r =
        await _call(context, '/assets/presets/save', [path, name]);
    if (!context.mounted) return;
    final n = (r != null && r.length >= 3) ? r[2] as int : -99;
    _toast(context,
        n >= 0 ? '$title: saved "$name"' : '$title: save failed ($n)');
  }

  /// List presets whose path matches this card, then offer a menu.
  Future<void> _loadPreset(BuildContext context) async {
    final path = _resolveSnapPath(context);
    final names = <String>[];
    final c = await _call(context, '/assets/presets/count', []);
    final n = (c != null && c.isNotEmpty) ? c[0] as int : 0;
    for (var i = 0; i < n; i++) {
      if (!context.mounted) return;
      final e = await _call(context, '/assets/presets/info', [i]);
      if (e != null && e.length >= 5 && e[3] == path) {
        names.add(e[2] as String);
      }
    }
    if (!context.mounted) return;
    if (names.isEmpty) {
      _toast(context, '$title: no saved presets');
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Load $title preset'),
        children: [
          for (final nm in names)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, nm),
              child: Text(nm),
            ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    final r = await _call(context, '/assets/presets/load', [name]);
    if (!context.mounted) return;
    final msgs = (r != null && r.length >= 2) ? r[1] as int : -99;
    _toast(context,
        msgs >= 0 ? '$title: loaded "$name"' : '$title: load failed ($msgs)');
  }

  void _resetPreset(BuildContext context) {
    final path = _resolveSnapPath(context);
    context.read<Network>().sendOscMessage('/assets/presets/reset', [path]);
    onReset?.call(); // extra reset for sibling subtrees (e.g. glitch)
    _toast(context, '$title: reset to defaults');
  }

  Widget _snapIcons(BuildContext context) {
    Widget btn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(icon, size: 15, color: Colors.grey[500]),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.save_outlined, 'Save preset…', () => _savePreset(context)),
      btn(Icons.history, 'Load preset…', () => _loadPreset(context)),
      btn(Icons.restart_alt, 'Reset to defaults', () => _resetPreset(context)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // rebuild on network status
    // ignore for now final connected = context.watch<Network>().isConnected;
    // Get lighting settings
    final lighting = context.watch<LightingSettings>();

    // Use grid tokens when available, fall back to legacy gutter.
    // GridProvider.of (not maybeOf + a private fallback): Panel and CardBody
    // resolve tokens the same way, so on a page with no GridProvider ancestor
    // the title and the content still land on the same edge. They previously
    // disagreed by 14px there — LabeledCard fell back to a hardcoded 16.0
    // while everything else fell back to GridTokens(1200).
    final t = GridProvider.of(context);
    final titlePadH = t.cardTitleAlignToPanelTitle;
    // Pull the title closer to the top so its visual inset matches the left inset.
    final titlePadTop = titlePadH - (t.xs);
    final titleGap = t.xs;
    // The card owns this, not GridRow. titlePadH = md + panelContentInset, so
    // the card indents its body by md and whatever sits inside (a Panel, or a
    // CardBody) adds panelContentInset — landing exactly on the title.
    final contentPadH = t.md;
    final contentPadBot = t.md;
    final titleStyle = t.textTitle;

    Widget card = _NeumorphicCard(
      lighting: lighting,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(titlePadH, titlePadTop, titlePadH, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: titleStyle.copyWith(height: 1.0),
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  ),
                ),
                if (snapPath != null) _snapIcons(context),
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
    );
    if (borderColor != null) {
      card = Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            left: 1, top: 1, right: 1, bottom: 1,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor!, width: 1),
                  borderRadius: BorderRadius.circular(7.0),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return card;
  }
}

/// A neumorphic card widget with subtle gradients, shadows, and noise texture.
/// Tracks its global position for physically accurate lighting.
class _NeumorphicCard extends StatefulWidget {
  final LightingSettings lighting;
  final Widget child;

  const _NeumorphicCard({
    required this.lighting,
    required this.child,
  });

  @override
  State<_NeumorphicCard> createState() => _NeumorphicCardState();
}

class _NeumorphicCardState extends State<_NeumorphicCard>
    with GlobalRectTracking<_NeumorphicCard> {

  @override
  Widget build(BuildContext context) {
    const borderRadius = 8.0;
    const elevation = 4.0;
    const baseColor = Color(0xFF323236);
    return RepaintBoundary(
      child: Container(
        key: globalRectKey,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: widget.lighting.createNeumorphicShadows(elevation: elevation),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: CustomPaint(
            painter: _NeumorphicCardPainter(
              lighting: widget.lighting,
              baseColor: baseColor,
              borderRadius: borderRadius,
              globalRect: trackedGlobalRect,
            ),
            child: widget.child,
          ),
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

class _NeumorphicContainerState extends State<NeumorphicContainer>
    with GlobalRectTracking<NeumorphicContainer> {

  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();

    Widget content = widget.child;
    if (widget.padding != null) {
      content = Padding(padding: widget.padding!, child: content);
    }

    return RepaintBoundary(
      child: Container(
        key: globalRectKey,
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
              globalRect: trackedGlobalRect,
            ),
            child: content,
          ),
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

class _NeumorphicInsetState extends State<NeumorphicInset>
    with GlobalRectTracking<NeumorphicInset> {

  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();

    Widget content = widget.child;
    if (widget.padding != null) {
      content = Padding(padding: widget.padding!, child: content);
    }

    return RepaintBoundary(
      child: Container(
        key: globalRectKey,
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
              globalRect: trackedGlobalRect,
            ),
            child: content,
          ),
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
