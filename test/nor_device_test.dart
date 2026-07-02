// Device-in-the-loop test of the NOR asset transport (needs the bench device
// at 192.168.100.200). Run explicitly:
//   flutter test --no-pub test/nor_device_test.dart
// Proves NorClient read + the osc fork's blob decode against real replies.
@Tags(['device'])
library;

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/asset_store.dart';
import 'package:SCION_Controller/network.dart';

void main() {
  test('NorClient reads SCTF + SPRT headers from the device', () async {
    final net = Network();
    await net.connect('192.168.100.200', 9000);
    // Give the handshake a moment; NorClient itself retries.
    await Future.delayed(const Duration(seconds: 2));
    final nor = NorClient(net);

    final sctf = await nor.read(0, 16);
    expect(String.fromCharCodes(sctf.sublist(0, 4)), 'SCTF');
    final total = ByteData.sublistView(sctf).getUint32(12, Endian.little);
    expect(total, greaterThan(16));

    final sprt = await nor.read(sprtBase, 12);
    expect(String.fromCharCodes(sprt.sublist(0, 4)), 'SPRT');

    // Multi-chunk read: pull the whole font directory (~576 B for 14 fonts)
    // plus enough to cross a chunk boundary, and check a directory entry.
    final blob = await nor.read(0, 2048);
    expect(blob.length, 2048);
    final fam = String.fromCharCodes(
        blob.sublist(16, 32).takeWhile((c) => c != 0));
    expect(fam, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
