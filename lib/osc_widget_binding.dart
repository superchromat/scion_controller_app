// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
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

/// Mixin to wire a State<T> to OSC send/receive.
mixin OscAddressMixin<T extends StatefulWidget> on State<T> {
  /// The full OSC address (e.g. "/root/child").
  late final String oscAddress;
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_registered) return;
    _registered = true;
    // Resolve path once all OscPathSegments are available
    final segs = OscPathSegment.resolvePath(context);
    oscAddress = segs.isEmpty ? '' : '/${segs.join('/')}';
    if (oscAddress.isNotEmpty) {
      // register path and listener
      OscRegistry().registerAddress(oscAddress);
      OscRegistry().registerListener(oscAddress, _handleOsc);
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

/// Minimum interval between log entries
final Duration _minLogInterval = const Duration(milliseconds: 50);
DateTime _lastLogTime = DateTime.fromMillisecondsSinceEpoch(0);
Timer? _logTimer;

/// Cache of the most recent log info
String? _cachedAddress;
List<Object>? _cachedArgs;
OscStatus? _cachedStatus;
Direction? _cachedDirection;
Uint8List? _cachedBinary;

void sendOsc(dynamic arg, {String? address}) {
  final addr = (address == null || address.isEmpty)
      ? oscAddress
      : (address.startsWith('/') ? address : '$oscAddress/$address');
  final argsList = (arg is Iterable)
      ? arg.map((e) => e as Object).toList()
      : <Object>[arg as Object];

  // 1) always fire the real OSC packet immediately:
  context.read<Network>().sendOscMessage(addr, argsList);

  // 2) cache for logging
  _cachedAddress = addr;
  _cachedArgs = argsList;
  _cachedStatus = OscStatus.ok;
  _cachedDirection = Direction.sent;
  _cachedBinary = Uint8List(0);

  // 3) decide whether to flush now or schedule
  final now = DateTime.now();
  final elapsed = now.difference(_lastLogTime);
  if (elapsed >= _minLogInterval) {
    _flushLog();
  } else _logTimer ??= Timer(_minLogInterval - elapsed, _flushLog);
}

void _flushLog() {
  // perform the log on the next frame
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_cachedAddress != null && _cachedArgs != null) {
      oscLogKey.currentState?.logOscMessage(
        address: _cachedAddress!,
        arg: _cachedArgs!,
        status: _cachedStatus!,
        direction: _cachedDirection!,
        binary: _cachedBinary!,
      );
    }
  });

  _lastLogTime = DateTime.now();
  _logTimer?.cancel();
  _logTimer = null;
}


  void _handleOsc(List<Object?> args) {
    final status = onOscMessage(args);
    // Log incoming
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

  /// Override this to react to incoming OSC messages.
  /// Return [OscStatus.ok] or [OscStatus.error].
  OscStatus onOscMessage(List<Object?> args) => OscStatus.error;
}
