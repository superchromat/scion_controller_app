import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'labeled_card.dart';
import 'shape.dart';
import 'send_color.dart';
import 'dac_parameters.dart';
import 'send_texture.dart';

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
                  child: OscPathSegment(
                    segment: 'source',
                    child: SendSourceSelector(defaultInput: widget.pageNumber),
                  ),
                ),
                LabeledCard(title: 'Shape', child: Shape()),
                LabeledCard(title: 'Color', child: SendColor()),
                const LabeledCard(title: 'Texture', child: SendTexture()),
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

class SendSourceSelector extends StatefulWidget {
  final int defaultInput;
  const SendSourceSelector({super.key, required this.defaultInput});

  @override
  State<SendSourceSelector> createState() => _SendSourceSelectorState();
}

class _SourceOption {
  final String value;
  final String label;
  const _SourceOption(this.value, this.label);
}

class _SendSourceSelectorState extends State<SendSourceSelector>
    with OscAddressMixin {
  late String _selected;
  late final List<_SourceOption> _options;

  @override
  void initState() {
    super.initState();
    final defaultInput = widget.defaultInput.clamp(1, 3).toInt();
    _selected = 'input:$defaultInput';
    _options = const [
      _SourceOption('input:1', 'Input 1'),
      _SourceOption('input:2', 'Input 2'),
      _SourceOption('input:3', 'Input 3'),
      _SourceOption('key', 'Key Output'),
    ];
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isEmpty) return OscStatus.error;
    final value = args.first;
    String? normalized;
    if (value is String) {
      normalized = value;
    } else if (value is int) {
      normalized = 'input:$value';
    }
    if (normalized != null && _options.any((opt) => opt.value == normalized)) {
      setState(() => _selected = normalized!);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        decoration: const InputDecoration(labelText: 'Source'),
        value: _selected,
        items: _options
            .map((opt) => DropdownMenuItem<String>(
                  value: opt.value,
                  child: Text(opt.label),
                ))
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() => _selected = value);
          sendOsc(value);
        },
      ),
    );
  }
}
