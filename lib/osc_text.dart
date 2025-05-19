import 'package:flutter/widgets.dart';
import 'osc_widget_binding.dart';

/// 1) Stateless “wrapper” that adds your segment into the inherited path
class OscText extends StatelessWidget {
  final String segment;
  final String initialText;
  final TextStyle? style;
  final TextAlign? textAlign;

  const OscText({
    Key? key,
    required this.segment,
    this.initialText = '',
    this.style,
    this.textAlign,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // now any OscAddressMixin below will see this segment in resolvePath()
    return OscPathSegment(
      segment: segment,
      child: _OscTextInner(
        initialText: initialText,
        style: style,
        textAlign: textAlign,
      ),
    );
  }
}

/// 2) Inner StatefulWidget that picks up the full OSC path automatically
class _OscTextInner extends StatefulWidget {
  final String initialText;
  final TextStyle? style;
  final TextAlign? textAlign;

  const _OscTextInner({
    Key? key,
    this.initialText = '',
    this.style,
    this.textAlign,
  }) : super(key: key);

  @override
  __OscTextInnerState createState() => __OscTextInnerState();
}

class __OscTextInnerState extends State<_OscTextInner>
    with OscAddressMixin<_OscTextInner> {
  late String _text;

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
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
      _text,
      style: widget.style,
      textAlign: widget.textAlign,
    );
  }
}
