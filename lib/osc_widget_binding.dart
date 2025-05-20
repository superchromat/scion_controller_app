// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'osc_log.dart';
import 'network.dart';
import 'package:provider/provider.dart';

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

class OscRegistry extends ChangeNotifier {
  static final OscRegistry _instance = OscRegistry._internal();
  factory OscRegistry() => _instance;
  OscRegistry._internal();

  final Map<String, OscParam> _params = {};

  void registerParam(String address, List<Object?> defaultValue) {
    _params.putIfAbsent(
      address,
      () => OscParam(address: address, defaultValue: defaultValue),
    );
    notifyListeners();
  }

  OscParam? getParam(String address) => _params[address];

  UnmodifiableMapView<String, OscParam> get allParams =>
      UnmodifiableMapView(_params);

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
  /// Your resolved OSC address, e.g. '/input/1'
  String oscAddress = '';

  /// Defaults stashed before we know our base path
  final Map<String, List<Object?>> _pendingDefaults = {};

  /// Whether we've already done the one-time registration
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    // Wait until after the first build so OscPathSegment ancestors exist:
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _registered) return;
      _registered = true;

      // 1) Resolve the full OSC path from the tree
      final segs = OscPathSegment.resolvePath(context);
      oscAddress = segs.isEmpty ? '' : '/${segs.join('/')}';

      // 2) Register any defaults the user called earlier
      _pendingDefaults.forEach((rel, defaults) {
        final full = _resolveFullAddress(rel);
        OscRegistry().registerParam(full, defaults);
      });
      _pendingDefaults.clear();

      // 3) Listen for incoming OSC on our base address
      if (oscAddress.isNotEmpty) {
        OscRegistry().registerListener(oscAddress, _handleOsc);
      }
    });
  }

  @override
  void dispose() {
    if (_registered && oscAddress.isNotEmpty) {
      OscRegistry().unregisterListener(oscAddress, _handleOsc);
    }
    super.dispose();
  }

  /// Stash—or immediately register—a default value under [address].
  /// If [address] is null/empty → applies to [oscAddress].
  /// If it starts with '/' → absolute; otherwise relative.
  void setDefaultValues(dynamic defaults, {String? address}) {
    final rel = (address ?? '').trim();
    final list = (defaults is List<Object?>)
        ? List<Object?>.from(defaults)
        : <Object?>[defaults as Object?];

    if (_registered) {
      OscRegistry().registerParam(_resolveFullAddress(rel), list);
    } else {
      _pendingDefaults[rel] = list;
    }
  }

  String _resolveFullAddress(String rel) {
    if (rel.startsWith('/')) return rel;           // absolute
    if (rel.isEmpty) return oscAddress;           // base
    return oscAddress.isEmpty                     // relative
        ? '/$rel'
        : '$oscAddress/$rel';
  }

  /// Send an OSC message, logging and updating the registry.
  void sendOsc(dynamic arg, {String? address}) {
    final addr = (address == null || address.isEmpty)
        ? oscAddress
        : (address.startsWith('/') ? address : '$oscAddress/$address');

    // ensure List<Object>
    final argsList = (arg is Iterable)
        ? arg.map((e) => e as Object).toList()
        : <Object>[arg as Object];

    // build type tags & status
    final tags = <String>[];
    var status = OscStatus.ok;
    for (var v in argsList) {
      if (v is double) tags.add('f');
      else if (v is int) tags.add('i');
      else if (v is bool) tags.add(v ? 'T' : 'F');
      else if (v is String) tags.add('s');
      else { tags.add('?'); status = OscStatus.error; }
    }

    // log outgoing
    oscLogKey.currentState?.logOscMessage(
      address: addr,
      arg: argsList,
      status: status,
      direction: Direction.sent,
      binary: Uint8List.fromList([0]),
    );

    // send over network
    context.read<Network>().sendOscMessage(addr, argsList);

    // update local registry param
    final param = OscRegistry().getParam(addr);
    //if (param != null) param.updateLocal(argsList);
    if (param != null) param.dispatch(argsList);
  }

  void _handleOsc(List<Object?> args) {
    final status = onOscMessage(args);
    // log incoming
    oscLogKey.currentState?.logOscMessage(
      address: oscAddress,
      arg: args,
      status: status,
      direction: Direction.received,
      binary: Uint8List.fromList([0]),
    );
  }

  /// Override to handle incoming OSC. Return ok or error.
  OscStatus onOscMessage(List<Object?> args) => OscStatus.error;
}
