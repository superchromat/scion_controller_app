import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:osc/osc.dart';
import 'OscLog.dart';
import 'network.dart';

enum OscStatus { fail, error, ok }

enum Direction { received, sent }

typedef OscCallback = void Function(List<Object?> args);

class OscParam {
  final String address;
  final List<Object?> defaultValue;

  List<Object?> lastLoadedValue;
  List<Object?> currentValue;
  final ValueNotifier<List<Object?>> notifier;
  final Set<OscCallback> listeners = {};

  OscParam({
    required this.address,
    required this.defaultValue,
  })  : lastLoadedValue = List.of(defaultValue),
        currentValue = List.of(defaultValue),
        notifier = ValueNotifier<List<Object?>>(List.of(defaultValue));

  void registerListener(OscCallback cb) => listeners.add(cb);
  void unregisterListener(OscCallback cb) => listeners.remove(cb);

  void dispatch(List<Object?> args) {
    currentValue = args;
    notifier.value = args;
    for (final cb in listeners) cb(args);
  }

  // Update local state & notifier without treating it as an "incoming" dispatch.
  void updateLocal(List<Object?> args) {
    currentValue = args;
    notifier.value = args;
  }
}

class OscRegistry {
  static final OscRegistry _instance = OscRegistry._internal();
  factory OscRegistry() => _instance;
  OscRegistry._internal();

  final Map<String, OscParam> _params = {};

  void registerParam(String address, List<Object?> defaultValue) {
    _params.putIfAbsent(
      address,
      () => OscParam(address: address, defaultValue: defaultValue),
    );
  }

  OscParam? getParam(String address) => _params[address];

  void registerListener(String address, OscCallback cb) {
    _params[address]?.registerListener(cb);
  }

  void unregisterListener(String address, OscCallback cb) {
    _params[address]?.unregisterListener(cb);
  }

   Future<void> saveToFile(String path) async {
    final file = File(path);
    final jsonMap = {
      for (var p in _params.values) p.address: p.currentValue,
    };
    await file.writeAsString(jsonEncode(jsonMap));
    // update lastLoadedValue to reflect what was saved
    for (var p in _params.values) {
      p.lastLoadedValue = List<Object?>.from(p.currentValue);
    }
  }


  Future<void> loadFromFile(String path) async {
    final file = File(path);
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    data.forEach((address, rawList) {
      final param = _params[address];
      if (param != null) {
        final args = List<Object?>.from(rawList as List);
        param.lastLoadedValue = args;
        param.dispatch(args);
      }
    });
  }

  /// Reset all params whose address starts with [prefix] back to defaults.
  void resetToDefaults(String? prefix) {
    _params.forEach((address, param) {
      if (prefix == null || address.startsWith(prefix)) {
        param.dispatch(List<Object?>.from(param.defaultValue));
      }
    });
  }

  void resetToFile(String? prefix) {
    _params.forEach((address, param) {
      if (prefix == null || address.startsWith(prefix)) {
        param.dispatch(List<Object?>.from(param.lastLoadedValue));
      }
    });
  }

  void dispatch(String address, List<Object?> args) {
    final param = _params[address];
    if (param == null) {
      final logState = oscLogKey.currentState;
      logState?.logOscMessage(
        address: address,
        arg: args,
        status: OscStatus.fail,
        direction: Direction.received,
        binary: Uint8List.fromList([0]),
      );
      return;
    }
    param.dispatch(args);
  }
}

class OscPathSegment extends InheritedWidget {
  final String segment;
  const OscPathSegment({
    required this.segment,
    required super.child,
    super.key,
  });

  static List<String> resolvePath(BuildContext context) {
    final path = <String>[];
    context.visitAncestorElements((el) {
      final w = el.widget;
      if (w is OscPathSegment) path.insert(0, w.segment);
      return true;
    });
    return path;
  }

  @override
  bool updateShouldNotify(covariant OscPathSegment old) =>
      old.segment != segment;
}

mixin OscAddressMixin<T extends StatefulWidget> on State<T> {
  late final String oscAddress;
  bool _listenerRegistered = false;
  List<Object?>? _pendingDefaults;

  @override
  void initState() {
    super.initState();
    // _pendingDefaults may be set by widget in its initState
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    oscAddress = '/' + OscPathSegment.resolvePath(context).join('/');
    if (!_listenerRegistered) {
      // register defaults once address is known
      if (_pendingDefaults != null) {
        OscRegistry().registerParam(oscAddress, _pendingDefaults!);
        _pendingDefaults = null;
      }
      // then register for incoming OSC
      OscRegistry().registerListener(oscAddress, _handleOsc);
      _listenerRegistered = true;
    }
  }

  /// Call in initState() with either a single value or a list; actual
  /// registration happens in didChangeDependencies once oscAddress exists.
  void setDefaultValues(dynamic defaults) {
    _pendingDefaults =
        defaults is List ? List<Object?>.from(defaults) : <Object?>[defaults];
  }

  @override
  void dispose() {
    OscRegistry().unregisterListener(oscAddress, _handleOsc);
    super.dispose();
  }

  void sendOsc(dynamic arg, {String? address}) {
    final List<Object> argsList =
        arg is List ? List<Object>.from(arg) : <Object>[arg as Object];
    address ??= oscAddress;

    final typeTags = <String>[];
    var status = OscStatus.ok;
    for (var v in argsList) {
      if (v is double)
        typeTags.add('f');
      else if (v is int)
        typeTags.add('i');
      else if (v is bool)
        typeTags.add(v ? 'T' : 'F');
      else if (v is String)
        typeTags.add('s');
      else {
        status = OscStatus.error;
        typeTags.add('?');
      }
    }

    oscLogKey.currentState?.logOscMessage(
      address: address,
      arg: arg,
      status: status,
      direction: Direction.sent,
      binary: Uint8List.fromList([0]),
    );

    print('Sending \$argsList to \$address (types: \${typeTags.join()})');
    network.sendOscMessage(address, argsList);

    final param = OscRegistry().getParam(address!);
    if (param != null) {
      param.updateLocal(argsList);
    }
  }

  void sendOscFromContext(BuildContext ctx, dynamic arg) {
    final addr = '/' + OscPathSegment.resolvePath(ctx).join('/');
    sendOsc(arg, address: addr);
  }

  void _handleOsc(List<Object?> args) {
    final logState = oscLogKey.currentState;
    final status = onOscMessage(args);
    logState?.logOscMessage(
      address: oscAddress,
      arg: args,
      status: status,
      direction: Direction.received,
      binary: Uint8List.fromList([0]),
    );
  }

  /// Override in State to handle incoming OSC.
  OscStatus onOscMessage(List<Object?> args) {
    debugPrint('Unhandled OSC at \$oscAddress → \$args');
    return OscStatus.error;
  }
}
