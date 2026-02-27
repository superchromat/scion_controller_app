import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'labeled_card.dart';
import 'grid.dart';
import 'shape.dart';
import 'send_color.dart';
import 'send_text.dart';
import 'send_source_selector.dart';
import 'send_overlay_source.dart';
import 'dac_parameters.dart';
import 'send_texture.dart';
import 'send_glitch.dart';
import 'osc_registry.dart';

class SendPage extends StatefulWidget {
  final int pageNumber;

  const SendPage({super.key, required this.pageNumber});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> with OscAddressMixin {
  final _glitchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Pre-register shape addresses to avoid race condition with /sync response
    final registry = OscRegistry();
    final send = '/send/${widget.pageNumber}';
    registry.registerAddress('$send/scaleX');
    registry.registerAddress('$send/scaleY');
    registry.registerAddress('$send/posX');
    registry.registerAddress('$send/posY');
    // Only register rotation for Send 1
    if (widget.pageNumber == 1) {
      registry.registerAddress('$send/rotation');
      registry.registerAddress('$send/pip/enabled');
      registry.registerAddress('$send/pip/source_send');
      registry.registerAddress('$send/pip/scaleX');
      registry.registerAddress('$send/pip/scaleY');
      registry.registerAddress('$send/pip/posX');
      registry.registerAddress('$send/pip/posY');
      registry.registerAddress('$send/pip/alpha');
      registry.registerAddress('$send/pip/opaque_blend');
      registry.registerAddress('$send/pip/opaque_thres_y');
      registry.registerAddress('$send/pip/opaque_thres_c');
    }
  }

  Widget _resetButton(VoidCallback onPressed) {
    return IconButton(
      icon: Icon(Icons.refresh, size: 18, color: Colors.grey[500]),
      onPressed: onPressed,
      tooltip: 'Reset to defaults',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final t = GridTokens(constraints.maxWidth);
        final sectionGap = t.md;
        return GridProvider(
          tokens: t,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(t.md),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OscPathSegment(
                      segment: 'send/${widget.pageNumber}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GridRow(gutter: t.md, cells: [
                            (
                              span: 12,
                              child: LabeledCard(
                                title: 'Send Source',
                                child: SendSourceSelector(
                                    pageNumber: widget.pageNumber),
                              ),
                            )
                          ]),
                          SizedBox(height: sectionGap),
                          if (widget.pageNumber == 1) ...[
                            GridRow(
                              gutter: t.md,
                              cells: [
                                (
                                  span: 12,
                                  child: LabeledCard(
                                    title: 'Overlay Source',
                                    child: SendOverlaySource(
                                        pageNumber: widget.pageNumber),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: sectionGap),
                          ],
                          GridRow(
                            gutter: t.md,
                            cells: [
                              (
                                span: 4,
                                child: LabeledCard(
                                  title: 'Shape',
                                  child: Shape(pageNumber: widget.pageNumber),
                                ),
                              ),
                              (
                                span: 4,
                                child: LabeledCard(
                                  title: 'Texture',
                                  child: const SendTexture(),
                                ),
                              ),
                              (
                                span: 4,
                                child: LabeledCard(
                                  title: 'Text',
                                  child: const SendText(),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: sectionGap),
                          GridRow(gutter: t.md, cells: [
                            (
                              span: 12,
                              child: LabeledCard(
                                title: 'Color',
                                child: SendColor(
                                  showGrade: widget.pageNumber == 1,
                                  gradePath: widget.pageNumber == 1
                                      ? '/send/${widget.pageNumber}/grade'
                                      : null,
                                ),
                              ),
                            )
                          ]),
                          SizedBox(height: sectionGap),
                          GridRow(gutter: t.md, cells: [
                            (
                              span: 12,
                              child: LabeledCard(
                                title: 'Glitch',
                                action: _resetButton(() =>
                                    (_glitchKey.currentState as dynamic)
                                        ?.reset()),
                                child: SendGlitch(key: _glitchKey),
                              ),
                            )
                          ]),
                        ],
                      ),
                    ),
                    SizedBox(height: sectionGap),
                    OscPathSegment(
                      segment: 'dac/${widget.pageNumber}',
                      child: GridRow(gutter: t.md, cells: [
                        (
                          span: 12,
                          child: const LabeledCard(
                              title: 'DAC', child: DacParameters()),
                        )
                      ]),
                    ),
                  ],
                ),
                if (kShowGrid) const Positioned.fill(child: GridOverlay()),
              ],
            ),
          ),
        );
      },
    );
  }
}
