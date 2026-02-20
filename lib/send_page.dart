import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'labeled_card.dart';
import 'shape.dart';
import 'send_color.dart';
import 'send_text.dart';
import 'send_image.dart';
import 'send_source_selector.dart';
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
  final _textureKey = GlobalKey();
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OscPathSegment(
            segment: 'send/${widget.pageNumber}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledCard(
                  title: 'Send Source',
                  child: SendSourceSelector(pageNumber: widget.pageNumber),
                ),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: LabeledCard(
                          title: 'Shape',
                          child: Shape(pageNumber: widget.pageNumber),
                        ),
                      ),
                      Expanded(
                        child: LabeledCard(
                          title: 'Texture',
                          action: _resetButton(() => (_textureKey.currentState as dynamic)?.reset()),
                          child: SendTexture(key: _textureKey),
                        ),
                      ),
                      const Expanded(
                        child: LabeledCard(
                          title: 'Text',
                          child: SendText(),
                        ),
                      ),
                    ],
                  ),
                ),
                LabeledCard(
                  title: 'Color',
                  child: SendColor(
                    showGrade: widget.pageNumber == 1,
                    gradePath: '/send/${widget.pageNumber}/grade',
                  ),
                ),
//                const LabeledCard(title: 'Image', child: SendImage()),
                LabeledCard(
                  title: 'Glitch',
                  action: _resetButton(() => (_glitchKey.currentState as dynamic)?.reset()),
                  child: SendGlitch(key: _glitchKey),
                ),
              ],
            ),
          ),
          OscPathSegment(
            segment: 'dac/${widget.pageNumber}',
            child: LabeledCard(title: 'DAC', child: const DacParameters()),
          ),
        ],
      ),
    );
  }
}
