import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/discovery.dart';

/// Which address a discovered mDNS service should be dialled on.
///
/// The case that matters is 0.0.0.0. mDNS announces a service as soon as it
/// appears, before its A record is necessarily known, and nsd reports that as
/// the unspecified address. Accepting it stranded the app: a service at
/// 0.0.0.0 counts as a discovered device, so the scion.local fallback was
/// never reached and the browse was never restarted.
void main() {
  final v4 = InternetAddress('192.168.100.238');
  final linkLocalV6 = InternetAddress('fe80::280:e1ff:fe3b:d9bd');
  final unspecifiedV4 = InternetAddress('0.0.0.0');
  final unspecifiedV6 = InternetAddress('::');
  final loopback = InternetAddress('127.0.0.1');

  test('0.0.0.0 is never dialled; the mDNS hostname is used instead', () {
    expect(ScionDiscovery.hostForService([unspecifiedV4], 'scion.local.'),
        'scion.local.');
  });

  test(':: is never dialled either', () {
    expect(ScionDiscovery.hostForService([unspecifiedV6], 'scion.local.'),
        'scion.local.');
  });

  test('a real address alongside 0.0.0.0 wins', () {
    expect(ScionDiscovery.hostForService([unspecifiedV4, v4], 'scion.local.'),
        '192.168.100.238');
  });

  test('IPv4 is preferred over link-local IPv6', () {
    expect(
        ScionDiscovery.hostForService([linkLocalV6, v4], 'scion.local.'),
        '192.168.100.238');
  });

  test('loopback is not dialled', () {
    expect(ScionDiscovery.hostForService([loopback], 'scion.local.'),
        'scion.local.');
  });

  test('no addresses at all falls back to the hostname', () {
    expect(ScionDiscovery.hostForService(null, 'scion.local.'), 'scion.local.');
    expect(ScionDiscovery.hostForService([], 'scion.local.'), 'scion.local.');
  });

  test('nothing usable and no hostname yields nothing to dial', () {
    // The caller skips the service entirely rather than inventing an endpoint.
    expect(ScionDiscovery.hostForService([unspecifiedV4], null), isNull);
  });

  test('a usable address is still used when there is no hostname', () {
    expect(ScionDiscovery.hostForService([v4], null), '192.168.100.238');
  });
}
