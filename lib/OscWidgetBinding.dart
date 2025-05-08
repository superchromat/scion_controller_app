import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'OscLog.dart';

typedef OscCallback = void Function(List<Object?> args);


enum OscStatus { fail, error, ok }
enum Direction { received, sent }


class OscRegistry {
  static final OscRegistry _instance = OscRegistry._internal();
  final Map<String, Set<OscCallback>> _listeners = {};

  OscRegistry._internal();

  factory OscRegistry() => _instance;

  void register(String address, OscCallback callback) {
    _listeners.putIfAbsent(address, () => {}).add(callback);
  }

  void unregister(String address, OscCallback callback) {
    _listeners[address]?.remove(callback);
    if (_listeners[address]?.isEmpty ?? false) {
      _listeners.remove(address);
    }
  }

  void dispatch(String address, List<Object?> args) {
    for (final cb in _listeners[address] ?? {}) {
      cb(args);
    }
  }
}

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
    OscRegistry().register(oscAddress, _handleOsc);
  }

  @override
  void dispose() {
    OscRegistry().unregister(oscAddress, _handleOsc);
    super.dispose();
  }

  void sendOsc(dynamic arg, {String? address}) {
    final args = arg is List ? arg : [arg];
    final typeTags = <String>[];
    OscStatus status = OscStatus.ok;

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
        status = OscStatus.error;
        typeTags.add('?');
      }
    }

    final logState = oscLogKey.currentState;
    logState?.logOscMessage(
        address: address,
        arg: arg,
        status: status,
        direction: Direction.sent,
        binary: Uint8List.fromList([0]));

    print(
        'Sending $args to ${address ?? "(unknown address)"} (types: ${typeTags.join()})');
  }

  void sendOscFromContext(BuildContext context, dynamic arg) {
    final address = '/' + OscPathSegment.resolvePath(context).join('/');
    sendOsc(arg, address: address);
  }

  void _handleOsc(List<Object?> args) {
    final logState = oscLogKey.currentState;
    OscStatus status = onOscMessage(args);

    logState?.logOscMessage(
        address: oscAddress,
        arg: args,
        status: status,
        direction: Direction.received,
        binary: Uint8List.fromList([0]));
  }

  OscStatus onOscMessage(List<Object?> args) {
    debugPrint('Unhandled OSC at $oscAddress → $args');
    return (OscStatus.error);
  }
}
