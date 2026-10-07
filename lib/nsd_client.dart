// lib/nsd_client.dart

import 'dart:async';
import 'dart:io';
import 'package:nsd/nsd.dart';
import 'package:flutter/foundation.dart';

import 'network.dart' show isDialableAddress;

/// Holds a discovered host + port.
class NetworkAddress {
  /// The address we actually connect to (a resolved IP when available).
  final String host;
  final int port;

  /// Friendly label for display — the mDNS hostname/instance (e.g.
  /// `jorge.local`), independent of the resolved IP. Null for manually-entered
  /// or recent endpoints where no discovered name is known.
  final String? name;

  NetworkAddress({
    required this.host,
    required this.port,
    this.name,
  });

  @override
  String toString() => '$host:$port';
}

/// mDNS/DNS-SD discovery wrapper using the `nsd` plugin.
class NSDClient {
  /// How long to listen before returning.
  final Duration scanDuration;

  NSDClient({this.scanDuration = const Duration(seconds: 5)});

  /// Discover instances of [resource] (e.g. "_scion._udp.local").
  /// Completes with a list of found host:port addresses.
  Future<List<NetworkAddress>> discover({
    String resource = '_scion._udp',
  }) async {
    final discovery = await startDiscovery(
      resource,
      autoResolve: true,
      ipLookupType: IpLookupType.any,
    );

    // wait for responses
    await Future.delayed(scanDuration);

    if (kDebugMode) {
      for (final s in discovery.services) {
        debugPrint(
            'NSD: service name="${s.name}" type="${s.type}" host=${s.host} port=${s.port}');
      }
    }

    final results = discovery.services
        .where((s) =>
            s.port != null &&
            (s.host != null || (s.addresses?.isNotEmpty ?? false)))
        .map((s) {
      String host;
      // Same guard as ScionDiscovery.hostForService / isDialableAddress: a
      // responder can advertise 0.0.0.0 before its address is usable, and that
      // must never be taken as a dialable host.
      final addrs =
          (s.addresses ?? const <InternetAddress>[]).where(isDialableAddress);
      if (addrs.isNotEmpty) {
        final preferred =
            addrs.where((a) => a.type == InternetAddressType.IPv4);
        host = (preferred.isNotEmpty ? preferred.first : addrs.first).address;
      } else {
        host = s.host!;
      }
      while (host.endsWith('.')) {
        host = host.substring(0, host.length - 1);
      }
      return NetworkAddress(host: host, port: s.port!);
    }).toList();

    await stopDiscovery(discovery);
    return results;
  }
}
