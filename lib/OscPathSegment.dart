import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'OSCLogPage.dart';

class OscPathSegment extends InheritedWidget {
  // Used for attaching segments of an OSC address path
  // to widgets (via the mixin below), that allows
  // widgets to introspect and find their own OSC address

  final String segment;

  const OscPathSegment({
    required this.segment,
    required super.child,
    super.key,
  });

  static List<String> resolvePath(BuildContext context) {
    final path = <String>[];
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is OscPathSegment) {
        path.insert(0, widget.segment);
      }
      return true;
    });
    return path;
  }

  @override
  bool updateShouldNotify(covariant OscPathSegment oldWidget) =>
      oldWidget.segment != segment;
}

mixin OscAddressMixin<T extends StatefulWidget> on State<T> {
  late final String oscAddress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    oscAddress = '/' + OscPathSegment.resolvePath(context).join('/');
  }

  void sendOscOrig(double value) {
    // TODO: Send via OSC :)
    // should take a list of parameters and types
    print('Sending $value to $oscAddress');
  }

  void sendOsc(dynamic arg, {String? address}) {
    final args = arg is List ? arg : [arg];
    final typeTags = <String>[];

    address = address ?? oscAddress;

    for (final value in args) {
      if (value is double) {
        typeTags.add('f');
      } else if (value is int) {
        typeTags.add('i');
      } else if (value is bool) {
        typeTags.add(value ? 'T' : 'F');
      } else if (value is String) {
        typeTags.add('s');
      } else {
        typeTags.add('?');
      }
    }

    final logState = oscLogKey.currentState;
    logState?.logOscMessage(
        address: address,
        arg: arg,
        status: Status.error,
        direction: Direction.sent,
        binary: Uint8List.fromList([0]));

    print(
        'Sending $args to ${address ?? "(unknown address)"} (types: ${typeTags.join()})');
  }

  void sendOscFromContext(BuildContext context, dynamic arg) {
    final address = '/' + OscPathSegment.resolvePath(context).join('/');
    sendOsc(arg, address: address);
  }
}