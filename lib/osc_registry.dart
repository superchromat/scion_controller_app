import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:collection/collection.dart';
import 'osc_log.dart';
import 'osc_widget_binding.dart';

/// Per-packet OSC trace logging. Off by default — flip to true to dump every
/// received message and dispatch to the console while debugging.
const bool kOscTrace = false;

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
  static const String _nodeValueKey = '__value';
  static final OscRegistry _instance = OscRegistry._internal();
  factory OscRegistry() => _instance;
  OscRegistry._internal();

  final Map<String, OscParam> _params = {};
  final Map<String, List<OscCallback>> _pendingListeners = {};
  // Addresses for which we should suppress logging during local echo dispatch
  final Set<String> _suppressLogAddresses = {};

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
    if (kOscTrace) debugPrint('OSC dispatch → key: "$key", args: $args');

    final param = _params[key];
    if (param == null) {
      // No client-side param for this address — e.g. a control whose page
      // hasn't been built yet this session, or a read-only telemetry value the
      // UI doesn't bind. The device broadcasts its whole state on /sync, so
      // this is expected, not a failure: log it as OK (received, just untracked).
      debugPrint('OSC dispatch key:"$key" NO PARAMS (untracked)');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oscLogKey.currentState?.logOscMessage(
          address: key,
          arg: args,
          status: OscStatus.ok,
          direction: Direction.received,
          binary: Uint8List.fromList([0]),
        );
      });
      return;
    }

    if (!param.dispatch(args)) {
      // Known address, but no widget is currently mounted to listen. This is
      // normal (the control just isn't on the visible page) — the value is
      // still cached in the param, so log it as OK rather than an error.
      debugPrint('OSC dispatch key:"$key" NO LISTENERS (cached)');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oscLogKey.currentState?.logOscMessage(
          address: key,
          arg: args,
          status: OscStatus.ok,
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
          final existing = map[seg];
          if (existing is Map<String, dynamic>) {
            existing[_nodeValueKey] = val;
          } else {
            map[seg] = val;
          }
        } else {
          final existing = map[seg];
          if (existing is Map<String, dynamic>) {
            map = existing;
          } else if (existing == null) {
            final child = <String, dynamic>{};
            map[seg] = child;
            map = child;
          } else {
            final child = <String, dynamic>{_nodeValueKey: existing};
            map[seg] = child;
            map = child;
          }
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
      if (node.containsKey(_nodeValueKey)) {
        final addr = '/${prefix.join('/')}';
        if (prefix.isNotEmpty) {
          registerAddress(addr);
          final param = _params[addr]!;
          final value = node[_nodeValueKey];
          final args =
              value is List ? List<Object?>.from(value) : <Object?>[value];
          param.dispatch(args);
        }
      }

      node.forEach((key, value) {
        if (key == _nodeValueKey) return;
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

  /// Dispatch a value locally (from UI) and suppress log entries for listeners.
  /// This keeps widgets bound to the same address in sync without polluting
  /// the OSC log with mirror "received" entries for locally-originated sends.
  void dispatchLocal(String address, List<Object?> args) {
    final key = address.startsWith('/') ? address : '/$address';
    final param = _params[key];
    if (param == null) {
      // If not registered yet, do nothing; caller should registerAddress first.
      return;
    }
    _suppressLogAddresses.add(key);
    try {
      param.dispatch(args);
    } finally {
      _suppressLogAddresses.remove(key);
    }
  }

  /// True if logs should be suppressed for this address during current dispatch.
  bool isLogSuppressed(String address) {
    final key = address.startsWith('/') ? address : '/$address';
    return _suppressLogAddresses.contains(key);
  }
}
