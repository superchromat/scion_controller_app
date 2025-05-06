import 'package:flutter/material.dart';

import 'LabeledCard.dart';
import 'Shape.dart';
import 'SendColor.dart';

class SendPage extends StatefulWidget {
  final int pageNumber;

  const SendPage({super.key, required this.pageNumber});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  late String _selectedInput;

  final List<String> _inputOptions = List.generate(
    4,
    (i) => 'HDMI Input ${i + 1}',
  );

  @override
  void initState() {
    super.initState();
    final clampedIndex =
        (widget.pageNumber-1).clamp(0, _inputOptions.length - 1).toInt();
    _selectedInput = _inputOptions[clampedIndex];
  }

@override
Widget build(BuildContext context) {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledCard(
          title: 'Input',
          child: DropdownButton<String>(
            value: _selectedInput,
            isExpanded: true,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedInput = value;
                });
              }
            },
            items: _inputOptions.map((option) {
              return DropdownMenuItem(
                value: option,
                child: Text(option),
              );
            }).toList(),
          ),
        ),
        LabeledCard(
            title: 'Shape', child: Shape()),
        LabeledCard(
            title: 'Color', child: SendColor()),
        LabeledCard(
            title: 'Texture', child: const Placeholder(fallbackHeight: 100)),
      ],
    ),
  );
}
}