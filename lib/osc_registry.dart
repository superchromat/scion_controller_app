import 'dart:io';
import 'dart:convert';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'osc_log.dart';
import 'osc_widget_binding.dart';

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

class OscRegistry extends ChangeNotifier {
  static final OscRegistry _instance = OscRegistry._internal();
  factory OscRegistry() => _instance;
  OscRegistry._internal();

  final Map<String, OscParam> _params = {};
  final Map<String, List<OscCallback>> _pendingListeners = {};

void registerParam(String address, List<Object?> defaultValue) {
  // 1) did we already have a param at that address?
  final bool wasNew = !_params.containsKey(address);

  // 2) insert it if missing
  _params.putIfAbsent(
    address,
    () => OscParam(address: address, defaultValue: defaultValue),
  );

  if (wasNew) {
    // flush any pending listeners for this new address...
    final pend = _pendingListeners.remove(address);
    if (pend != null) {
      final param = _params[address]!;
      for (var cb in pend) param.registerListener(cb);
    }
  }

  notifyListeners();
}


  OscParam? getParam(String address) => _params[address];

  UnmodifiableMapView<String, OscParam> get allParams =>
      UnmodifiableMapView(_params);

  void registerListener(String address, OscCallback cb) {
    final param = _params[address];
    if (param != null) {
      // param exists → attach immediately
      param.registerListener(cb);
    } else {
      // param not yet registered → defer
      _pendingListeners.putIfAbsent(address, () => []).add(cb);
    }
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

  /// In osc_widget_binding.dart, inside class OscRegistry:
  void dispatch(String address, List<Object?> args) {
    // Normalize to always start with '/'
    final key = address.startsWith('/') ? address : '/$address';
    // Debug log so you can see exactly what's being dispatched
    debugPrint('OSC dispatch → key: "$key", args: $args');

    final param = _params[key];
    if (param == null) {
      // Log failure as before
      final logState = oscLogKey.currentState;
      logState?.logOscMessage(
        address: key,
        arg: args,
        status: OscStatus.fail,
        direction: Direction.received,
        binary: Uint8List.fromList([0]),
      );
      return;
    }
    // Route to any listeners
    param.dispatch(args);
  }
}
