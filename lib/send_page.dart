import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'labeled_card.dart';
import 'shape.dart';
import 'send_color.dart';
import 'osc_dropdown.dart';
import 'dac_parameters.dart';

class SendPage extends StatefulWidget {
  final int pageNumber;

  const SendPage({super.key, required this.pageNumber});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> with OscAddressMixin {
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
                  child: OscDropdown(
                    label: 'Input',
                    items: [1, 2, 3, 4],
                    defaultValue: widget.pageNumber,
                  ),
                ),
                LabeledCard(title: 'Shape', child: Shape()),
                LabeledCard(title: 'Color', child: SendColor()),
                LabeledCard(
                  title: 'Texture',
                  child: const Placeholder(fallbackHeight: 100),
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
