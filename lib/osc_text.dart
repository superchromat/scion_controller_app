import 'package:flutter/widgets.dart';
import 'osc_widget_binding.dart';

// Stateless “wrapper” that adds your segment into the inherited path
class OscText extends StatelessWidget {
  final String segment;
  final String initialText;
  final TextStyle? style;
  final TextAlign? textAlign;
  final String? suffix;

  const OscText({
    Key? key,
    required this.segment,
    this.initialText = '',
    this.style,
    this.textAlign,
    this.suffix = ''
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: segment,
      child: _OscTextInner(
        initialText: initialText,
        style: style,
        textAlign: textAlign,
        suffix: suffix
      ),
    );
  }
}

// Inner StatefulWidget that picks up the full OSC path automatically
class _OscTextInner extends StatefulWidget {
  final String initialText;
  final TextStyle? style;
  final TextAlign? textAlign;
  final String? suffix;

  const _OscTextInner({
    Key? key,
    this.initialText = '',
    this.style,
    this.textAlign,
    this.suffix
  }) : super(key: key);

  @override
  __OscTextInnerState createState() => __OscTextInnerState();
}

class __OscTextInnerState extends State<_OscTextInner>
    with OscAddressMixin<_OscTextInner> {
  late String _text;
  late String suffix;

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
    suffix = widget.suffix ?? '';
    // rel = '' → param at full oscAddress (including the segment above)
    setDefaultValues(_text);
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    final incoming = args.isNotEmpty ? args.first.toString() : '';
    if (incoming != _text) {
      setState(() => _text = incoming);
    }
    return OscStatus.ok;
  }

  @override
  Widget build(BuildContext context) {
    // by the time build runs, didChangeDependencies() will have
    // registered your listener on the exact path you want
    return Text(
      "${_text}$suffix",
      style: widget.style,
      textAlign: widget.textAlign,
    );
  }
}
