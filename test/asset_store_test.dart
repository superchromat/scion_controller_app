import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/asset_store.dart';
import 'package:SCION_Controller/network.dart';

void main() {
  test('crc32 matches known vector', () {
    // crc32("123456789") = 0xCBF43926
    expect(crc32(Uint8List.fromList('123456789'.codeUnits)), 0xCBF43926);
  });

  test('convertSprite packs 4bpp with transparent index 0', () {
    // 4x2 image: red, transparent, blue, red / blue, blue, transparent, red
    const r = [255, 0, 0, 255], b = [0, 0, 255, 255], t = [0, 0, 0, 0];
    final rgba =
        Uint8List.fromList([...r, ...t, ...b, ...r, ...b, ...b, ...t, ...r]);
    final s = convertSprite('test', 4, 2, rgba);
    expect(s.w, 4);
    expect(s.h, 2);
    expect(s.pixels.length, 2 * 2); // bpr=2, h=2
    // Palette entry 0 must be fully transparent (alpha byte 0).
    expect(s.palette[1], 0);
    // Two colours -> indices 1 and 2; transparent pixels -> 0.
    final p00 = (s.pixels[0] >> 4) & 0xF; // red
    final p01 = s.pixels[0] & 0xF; // transparent
    final p02 = (s.pixels[1] >> 4) & 0xF; // blue
    final p03 = s.pixels[1] & 0xF; // red
    expect(p01, 0);
    expect(p00, isNot(0));
    expect(p02, isNot(0));
    expect(p03, p00); // same colour -> same index
    expect(p02, isNot(p00));
    // Red entry: Y small, Cr large. Blue entry: Cb large.
    final red = s.palette.sublist(p00 * 4, p00 * 4 + 4); // [Cr, a, Cb, Y]
    final blue = s.palette.sublist(p02 * 4, p02 * 4 + 4);
    expect(red[0], greaterThan(200)); // Cr
    expect(red[1], 255); // alpha
    expect(blue[2], greaterThan(200)); // Cb
  });

  test('SPRT blob layout round-trips', () {
    final a = SpriteAsset(
        'one', 4, 2, Uint8List(64), Uint8List.fromList([1, 2, 3, 4]));
    final b =
        SpriteAsset('two', 2, 2, Uint8List(64), Uint8List.fromList([5, 6]));
    final store = SpriteStore(NorClient(FakeNetworkNever()));
    final blob = store.buildBlob([a, b]);
    expect(String.fromCharCodes(blob.sublist(0, 4)), 'SPRT');
    final bd = ByteData.sublistView(blob);
    expect(bd.getUint16(4, Endian.little), 1); // version
    expect(bd.getUint16(6, Endian.little), 2); // count
    // entry 0
    expect(String.fromCharCodes(blob.sublist(12, 15)), 'one');
    expect(bd.getUint16(12 + 16, Endian.little), 4); // w
    final off0 = bd.getUint32(12 + 20, Endian.little);
    final len0 = bd.getUint32(12 + 24, Endian.little);
    expect(len0, 4);
    // offsets are partition-absolute (sprtBase + header + 2 entries)
    expect(off0, sprtBase + 12 + 96 * 2);
    final off1 = bd.getUint32(12 + 96 + 20, Endian.little);
    expect(off1, off0 + 4);
    // pixel data lands where the directory says (relative to blob start)
    expect(blob[off0 - sprtBase], 1);
    expect(blob[off1 - sprtBase], 5);
  });

  test('SCTF appendFont shifts offsets and appends', () {
    // Synthetic blob: header + 1 dir entry + 8-byte "TTF".
    final ttf0 = Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9]);
    final blob = BytesBuilder();
    final hdr = ByteData(16);
    hdr.setUint8(0, 0x53);
    hdr.setUint8(1, 0x43); // SC
    hdr.setUint8(2, 0x54);
    hdr.setUint8(3, 0x46); // TF
    hdr.setUint16(4, 1, Endian.little); // version
    hdr.setUint16(6, 1, Endian.little); // count
    hdr.setUint32(12, 16 + 40 + 8, Endian.little); // total
    blob.add(hdr.buffer.asUint8List());
    final e = ByteData(40);
    final eb = e.buffer.asUint8List();
    eb.setRange(0, 3, 'Fam'.codeUnits);
    eb.setRange(16, 19, 'Reg'.codeUnits);
    e.setUint32(32, 56, Endian.little); // ttf at 16+40
    e.setUint32(36, 8, Endian.little);
    blob.add(eb);
    blob.add(ttf0);

    final store = FontStore(NorClient(FakeNetworkNever()));
    final ttf1 = Uint8List.fromList(List.filled(12, 7));
    final out = store.appendFont(blob.toBytes(), 'New', 'Bold', ttf1);

    final bd = ByteData.sublistView(out);
    expect(bd.getUint16(6, Endian.little), 2); // count
    // old entry (at 16) shifted by 40
    expect(bd.getUint32(16 + 32, Endian.little), 96);
    expect(out[96], 9); // old ttf content at new offset
    // new entry
    expect(String.fromCharCodes(out.sublist(56, 59)), 'New');
    final noff = bd.getUint32(56 + 32, Endian.little);
    final nlen = bd.getUint32(56 + 36, Endian.little);
    expect(nlen, 12);
    expect(out[noff], 7);
    expect(bd.getUint32(12, Endian.little), out.length); // total
    expect(noff + nlen, out.length);
  });
}

/// NorClient never touches the network in these tests; blob building is pure.
class FakeNetworkNever extends Fake implements Network {}
