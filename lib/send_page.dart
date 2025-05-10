import 'package:flutter/material.dart';
import 'package:namer_app/osc_widget_binding.dart';

import 'labeled_card.dart';
import 'shape.dart';
import 'send_color.dart';
import 'osc_dropdown.dart';

class SendPage extends StatefulWidget {
  final int pageNumber;

  const SendPage({super.key, required this.pageNumber});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> with OscAddressMixin {
  late int _selectedInput;

  @override
  void initState() {
    super.initState();
    _selectedInput = widget.pageNumber;
  }

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'send/${widget.pageNumber}',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledCard(
                title: 'Send Source',
                child: OscDropdown(
                    label: 'Input',
                    items: [1, 2, 3, 4],
                    defaultValue: widget.pageNumber)),
            LabeledCard(title: 'Shape', child: Shape()),
            LabeledCard(title: 'Color', child: SendColor()),
            LabeledCard(
                title: 'Texture',
                child: const Placeholder(fallbackHeight: 100)),
          ],
        ),
      ),
    );
  }
}
