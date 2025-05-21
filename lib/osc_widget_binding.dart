// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'osc_log.dart';
import 'network.dart';
import 'package:provider/provider.dart';
import 'osc_registry.dart';

enum OscStatus { fail, error, ok }

enum Direction { received, sent }

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
    if (rel.startsWith('/')) return rel; // absolute
    if (rel.isEmpty) return oscAddress; // base
    return oscAddress.isEmpty // relative
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
      if (v is double)
        tags.add('f');
      else if (v is int)
        tags.add('i');
      else if (v is bool)
        tags.add(v ? 'T' : 'F');
      else if (v is String)
        tags.add('s');
      else {
        tags.add('?');
        status = OscStatus.error;
      }
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
