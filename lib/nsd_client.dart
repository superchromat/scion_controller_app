// lib/nsd_client.dart

import 'dart:async';
import 'package:nsd/nsd.dart';

/// Holds a discovered host + port.
class NetworkAddress {
  final String host;
  final int port;

  NetworkAddress({
    required this.host,
    required this.port,
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
    String resource = '_scion._udp.local',
  }) async {
    final discovery = await startDiscovery(
      resource,
      autoResolve: true,
      ipLookupType: IpLookupType.any,
    );

    // wait for responses
    await Future.delayed(scanDuration);

    final results = discovery.services
        .where((s) => s.host != null && s.port != null)
        .map((s) => NetworkAddress(host: s.host!, port: s.port!))
        .toList();

    await stopDiscovery(discovery);
    return results;
  }
}

