import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'osc_log.dart';
import 'network.dart';
import 'package:provider/provider.dart';

// TODO: method to Sync OSC settings on startup and then let the user manually sync?x`

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
    for (final cb in listeners) {
      cb(args);
    }
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

  /// Save nested JSON: splits addresses by '/', storing currentValue accordingly.
  Future<void> saveToFile(String path) async {
    final file = File(path);
    final nested = <String, dynamic>{};
    for (var p in _params.values) {
      final segments = p.address.split('/').where((s) => s.isNotEmpty).toList();
      var map = nested;
      for (var i = 0; i < segments.length; i++) {
        final seg = segments[i];
        if (i == segments.length - 1) {
          final val = p.currentValue.length == 1
              ? p.currentValue.first
              : p.currentValue;
          map[seg] = val;
        } else {
          if (map[seg] is! Map<String, dynamic>) {
            map[seg] = <String, dynamic>{};
          }
          map = map[seg] as Map<String, dynamic>;
        }
      }
    }
    await file.writeAsString(jsonEncode(nested));
    for (var p in _params.values) {
      p.lastLoadedValue = List<Object?>.from(p.currentValue);
    }
  }

  /// Load nested JSON: traverse by address and dispatch values.
  Future<void> loadFromFile(String path) async {
    final file = File(path);
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    for (final entry in _params.entries) {
      final address = entry.key;
      final param = entry.value;
      final segments = address.split('/').where((s) => s.isNotEmpty).toList();
      dynamic leaf = data;
      var found = true;
      for (final seg in segments) {
        if (leaf is Map<String, dynamic> && leaf.containsKey(seg)) {
          leaf = leaf[seg];
        } else {
          found = false;
          break;
        }
      }
      if (!found) continue;
      List<Object?> args;
      if (leaf is List) {
        args = List<Object?>.from(leaf);
      } else {
        args = <Object?>[leaf];
      }
      param.lastLoadedValue = args;
      param.dispatch(args);
    }
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

  // Holds defaults registered before we know the base address
  final Map<String, List<Object?>> _pendingDefaultsMap = {};

  @override
  void initState() {
    super.initState();
    // You can call setDefaultValues(...) here if needed
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Build this widget's base OSC address:
    oscAddress = '/${OscPathSegment.resolvePath(context).join('/')}';

    if (!_listenerRegistered) {
      // 1) Register any defaults stashed earlier
      _pendingDefaultsMap.forEach((relAddr, defaults) {
        final fullAddr = _resolveFullAddress(relAddr);
        OscRegistry().registerParam(fullAddr, defaults);
      });
      _pendingDefaultsMap.clear();

      // 2) Listen for incoming OSC on the base path
      OscRegistry().registerListener(oscAddress, _handleOsc);
      _listenerRegistered = true;
    }
  }

  @override
  void dispose() {
    OscRegistry().unregisterListener(oscAddress, _handleOsc);
    super.dispose();
  }

  /// Stash—or if the base address is known, immediately register—default values
  /// under [address].
  ///
  /// - If [address] is `null` or empty, defaults apply to [oscAddress] itself.
  /// - If [address] starts with `'/'`, it is treated as an absolute OSC path.
  /// - Otherwise it is treated as a relative segment appended to [oscAddress].
  void setDefaultValues(dynamic defaults, {String? address}) {
    final rel = (address ?? '').trim();
    final list = defaults is List<Object?>
        ? List<Object?>.from(defaults)
        : <Object?>[defaults as Object?];

    if (_listenerRegistered) {
      final fullAddr = _resolveFullAddress(rel);
      OscRegistry().registerParam(fullAddr, list);
    } else {
      _pendingDefaultsMap[rel] = list;
    }
  }

  String _resolveFullAddress(String rel) {
    if (rel.startsWith('/')) {
      // absolute path
      return rel;
    } else if (rel.isEmpty) {
      // base path
      return oscAddress;
    } else {
      // relative segment
      return '$oscAddress/$rel';
    }
  }

  /// Send an OSC message to [address] (relative or absolute) with [arg] or
  /// list of args.
  void sendOsc(dynamic arg, {String? address}) {
    final addr = (address == null || address.isEmpty)
        ? oscAddress
        : (address.startsWith('/') ? address : '$oscAddress/$address');

    final argsList = arg is List<Object>
        ? List<Object>.from(arg)
        : <Object>[arg as Object];

    // Build type tags & status
    final typeTags = <String>[];
    var status = OscStatus.ok;
    for (var v in argsList) {
      if (v is double) typeTags.add('f');
      else if (v is int) typeTags.add('i');
      else if (v is bool) typeTags.add(v ? 'T' : 'F');
      else if (v is String) typeTags.add('s');
      else {
        typeTags.add('?');
        status = OscStatus.error;
      }
    }

    // Log it
    oscLogKey.currentState?.logOscMessage(
      address: addr,
      arg: arg,
      status: status,
      direction: Direction.sent,
      binary: Uint8List.fromList([0]),
    );

    // Send over network
    print('Sending $argsList to $addr (types: ${typeTags.join()})');
    context.read<Network>().sendOscMessage(addr, argsList);

    // Update local registry param so saveToFile sees it
    final param = OscRegistry().getParam(addr);
    if (param != null) {
      param.updateLocal(argsList);
    }
  }

  /// Shortcut to send OSC to the path resolved from a BuildContext
  void sendOscFromContext(BuildContext ctx, dynamic arg) {
    final addr = '/${OscPathSegment.resolvePath(ctx).join('/')}';
    sendOsc(arg, address: addr);
  }

  void _handleOsc(List<Object?> args) {
    final status = onOscMessage(args);
    oscLogKey.currentState?.logOscMessage(
      address: oscAddress,
      arg: args,
      status: status,
      direction: Direction.received,
      binary: Uint8List.fromList([0]),
    );
  }

  /// Override in your State to handle incoming OSC messages.
  /// Return OscStatus.ok if you handled it, or OscStatus.error if not.
  OscStatus onOscMessage(List<Object?> args) => OscStatus.error;
}
