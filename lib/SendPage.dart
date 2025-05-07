import 'package:flutter/material.dart';
import 'package:namer_app/OscPathSegment.dart';

import 'LabeledCard.dart';
import 'Shape.dart';
import 'SendColor.dart';

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

  Widget oscDropdown(String label, List<int> items, int defaultValue) {
    return OscPathSegment(
      segment: label.toLowerCase(),
      child: Builder(
        builder: (dropdownContext) => SizedBox(
          width: 180,
          child: DropdownButtonFormField(
            decoration: InputDecoration(labelText: label),
            style: const TextStyle(fontFamily: 'monospace'),
            value: defaultValue,
            items: items
                .map((res) => DropdownMenuItem(
                      value: res,
                      child: Text('HDMI Input ' + res.toString()),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  sendOscFromContext(dropdownContext, value);
                });
              }
            },
          ),
        ),
      ),
    );
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
                child: oscDropdown('Input', [1,2,3,4],
                    widget.pageNumber)),
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
