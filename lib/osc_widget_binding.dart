// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_log.dart';
import 'network.dart';
import 'osc_registry.dart';

enum OscStatus { fail, error, ok }

enum Direction { received, sent }

/// Marks a segment in the OSC address hierarchy.
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

/// Mixin to wire a `State<T>` to OSC send/receive.
mixin OscAddressMixin<T extends StatefulWidget> on State<T> {
  /// The full OSC address (e.g. "/root/child").
  late final String oscAddress;
  bool _registered = false;

  /// Override and return false to make the widget a pure UI control that does
  /// NOT bind to the ambient OSC path — no auto send-on-change, no listener.
  /// Used when OSC is handled manually (explicit absolute address via
  /// onChanged), so the widget doesn't also fire/listen on the surrounding
  /// path context (which would cross-link sibling controls).
  bool get oscBindEnabled => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_registered) return;
    _registered = true;
    if (!oscBindEnabled) {
      oscAddress = '';
      return;
    }
    // Resolve path once all OscPathSegments are available
    final segs = OscPathSegment.resolvePath(context);
    oscAddress = segs.isEmpty ? '' : '/${segs.join('/')}';
    if (oscAddress.isNotEmpty) {
      // register path and listener
      OscRegistry().registerAddress(oscAddress);
      OscRegistry().registerListener(oscAddress, _handleOsc);
      // Seed from the last-known value so a control that just remounted (e.g.
      // after switching tabs away and back) shows the current device state
      // instead of its default — the value lives in the registry, but a fresh
      // listener isn't replayed the current value automatically.
      final seed = OscRegistry().allParams[oscAddress]?.currentValue;
      if (seed != null && seed.isNotEmpty) onOscMessage(seed);
    }
  }

  @override
  void dispose() {
    if (_registered && oscAddress.isNotEmpty) {
      OscRegistry().unregisterListener(oscAddress, _handleOsc);
    }
    super.dispose();
  }

// inside your State or wherever sendOsc lives:

  void sendOsc(dynamic arg, {String? address}) {
    final addr = (address == null || address.isEmpty)
        ? oscAddress
        : (address.startsWith('/') ? address : '$oscAddress/$address');
    final argsList = (arg is Iterable)
        ? arg.map((e) => e as Object).toList()
        : <Object>[arg as Object];

    // Fire the real OSC packet. Network logs every send centrally, so widgets
    // don't log here (that used to miss any path that bypassed this mixin).
    context.read<Network>().sendOscMessage(addr, argsList);

    // Local echo: immediately update OscRegistry so all widgets bound to the
    // same address reflect the new value without waiting for server /sync.
    try {
      final reg = OscRegistry();
      reg.registerAddress(addr);
      reg.dispatchLocal(addr, argsList.cast<Object?>());
    } catch (_) {}
  }

  void _handleOsc(List<Object?> args) {
    final status = onOscMessage(args);
    // Log incoming unless suppressed (local echo)
    if (!OscRegistry().isLogSuppressed(oscAddress)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oscLogKey.currentState?.logOscMessage(
          address: oscAddress,
          arg: args,
          status: status,
          direction: Direction.received,
          binary: Uint8List(0),
        );
      });
    }
  }

  /// Override this to react to incoming OSC messages.
  /// Return [OscStatus.ok] or [OscStatus.error].
  OscStatus onOscMessage(List<Object?> args) => OscStatus.error;
}
