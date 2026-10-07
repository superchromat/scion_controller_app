// Guards the 0.0.0.0 trap.
//
// A SCION that has just booted can answer scion.local with the unspecified
// address for a window (its mDNS responder publishes whatever
// net_if_ipv4_select_src_addr() returns, and that falls back to 0.0.0.0).
// A lookup then SUCCEEDS with an address that can never answer, so any
// "did the lookup return nothing?" check sails straight past it.
//
// Observed live on 2026-08-10; see isDialableAddress in network.dart and
// ScionDiscovery.hostForService, which must agree.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/discovery.dart';
import 'package:SCION_Controller/network.dart';

void main() {
  group('isDialableAddress', () {
    test('rejects the unspecified IPv4 address', () {
      expect(isDialableAddress(InternetAddress('0.0.0.0')), isFalse);
    });

    test('rejects the unspecified IPv6 address, however spelled', () {
      expect(isDialableAddress(InternetAddress('::')), isFalse);
      expect(isDialableAddress(InternetAddress('::0')), isFalse);
      expect(isDialableAddress(InternetAddress('0:0:0:0:0:0:0:0')), isFalse);
    });

    test('accepts real device addresses', () {
      expect(isDialableAddress(InternetAddress('192.168.100.241')), isTrue);
      expect(isDialableAddress(InternetAddress('169.254.3.7')), isTrue);
      expect(
          isDialableAddress(InternetAddress('fe80::280:e1ff:fe3b:d9bd')), isTrue);
    });

    // Loopback stays dialable on purpose: pointing the app at a simulator on
    // 127.0.0.1 is a legitimate setup, and loopback — unlike 0.0.0.0 — is a
    // real destination that either answers or refuses promptly.
    test('accepts loopback', () {
      expect(isDialableAddress(InternetAddress('127.0.0.1')), isTrue);
    });
  });

  group('ScionDiscovery.hostForService agrees', () {
    test('drops 0.0.0.0 and falls back to the mDNS hostname', () {
      expect(
        ScionDiscovery.hostForService(
            [InternetAddress('0.0.0.0')], 'scion.local'),
        'scion.local',
      );
    });

    test('prefers a real IPv4 address over the hostname', () {
      expect(
        ScionDiscovery.hostForService(
          [InternetAddress('0.0.0.0'), InternetAddress('192.168.100.241')],
          'scion.local',
        ),
        '192.168.100.241',
      );
    });
  });
}
