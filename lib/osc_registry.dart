import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:collection/collection.dart';
import 'osc_log.dart';
import 'osc_widget_binding.dart';

/// Callback invoked on incoming OSC messages for a given address.
typedef OscCallback = void Function(List<Object?> args);

/// Holds current OSC value and notifies registered listeners.
class OscParam {
  final String address;
  List<Object?> currentValue;
  final ValueNotifier<List<Object?>> notifier;
  final Set<OscCallback> listeners = {};

  OscParam(this.address)
      : currentValue = [],
        notifier = ValueNotifier(<Object?>[]);

  void registerListener(OscCallback cb) => listeners.add(cb);
  void unregisterListener(OscCallback cb) => listeners.remove(cb);

  /// Dispatches new values to listeners and updates notifier.
  bool dispatch(List<Object?> args) {
    var notified = false;
    currentValue = args;
    notifier.value = args;
    for (final cb in listeners) {
      cb(args);
      notified = true;
    }
    return notified;
  }

  /// Update local state without invoking listeners.
  void updateLocal(List<Object?> args) {
    currentValue = args;
    notifier.value = args;
  }
}

/// Central registry for OSC-bound addresses.
class OscRegistry extends ChangeNotifier {
  static final OscRegistry _instance = OscRegistry._internal();
  factory OscRegistry() => _instance;
  OscRegistry._internal();

  final Map<String, OscParam> _params = {};
  final Map<String, List<OscCallback>> _pendingListeners = {};

  /// Ensure an OSC address is registered for sending/listening.
  void registerAddress(String address) {
    final key = address.startsWith('/') ? address : '/$address';
    final isNew = !_params.containsKey(key);
    if (isNew) {
      _params[key] = OscParam(key);
      // flush any deferred listeners
      final deferred = _pendingListeners.remove(key);
      if (deferred != null) {
        for (var cb in deferred) {
          _params[key]!.registerListener(cb);
        }
      }
      notifyListeners();
    }
  }

  /// Read-only view of all registered addresses.
  UnmodifiableMapView<String, OscParam> get allParams =>
      UnmodifiableMapView(_params);

  /// Register a callback for incoming messages on [address].
  void registerListener(String address, OscCallback cb) {
    final key = address.startsWith('/') ? address : '/$address';
    final param = _params[key];
    if (param != null) {
      param.registerListener(cb);
    } else {
      _pendingListeners.putIfAbsent(key, () => []).add(cb);
    }
  }

  /// Unregister a previously registered listener.
  void unregisterListener(String address, OscCallback cb) {
    final key = address.startsWith('/') ? address : '/$address';
    _params[key]?.unregisterListener(cb);
  }

  /// Dispatch an incoming OSC message to listeners for [address].
  void dispatch(String address, List<Object?> args) {
    final key = address.startsWith('/') ? address : '/$address';
    debugPrint('OSC dispatch → key: "$key", args: $args');

    final param = _params[key];
    if (param == null) {
      debugPrint('OSC dispatch key:"$key" NO PARAMS');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oscLogKey.currentState?.logOscMessage(
          address: key,
          arg: args,
          status: OscStatus.fail,
          direction: Direction.received,
          binary: Uint8List.fromList([0]),
        );
      });
      return;
    }

    if (!param.dispatch(args)) {
      debugPrint('OSC dispatch key:"$key" NO LISTENERS');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oscLogKey.currentState?.logOscMessage(
          address: key,
          arg: args,
          status: OscStatus.error,
          direction: Direction.received,
          binary: Uint8List.fromList([0]),
        );
      });
    }
  }

  /// Save all current values into a nested JSON structure at [path].
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
          map = map.putIfAbsent(seg, () => <String, dynamic>{})
              as Map<String, dynamic>;
        }
      }
    }
    await file.writeAsString(jsonEncode(nested));
  }

  /// Load values from a nested JSON file at [path] and dispatch them.
  Future<void> loadFromFile(String path) async {
    final file = File(path);
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    void recurse(Map<String, dynamic> node, List<String> prefix) {
      node.forEach((key, value) {
        final newPrefix = [...prefix, key];
        if (value is Map<String, dynamic>) {
          recurse(value, newPrefix);
        } else {
          final addr = '/${newPrefix.join('/')}';
          registerAddress(addr);
          final param = _params[addr]!;
          final args =
              value is List ? List<Object?>.from(value) : <Object?>[value];
          param.dispatch(args);
        }
      });
    }

    recurse(data, []);
  }
}
