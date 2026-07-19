import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/asset_store.dart';
import 'package:SCION_Controller/network.dart';

// Build a synthetic SCTF blob with [faces] as (family, variant, body).
Uint8List sctf(List<(String, String, List<int>)> faces) {
  final dirEnd = 16 + 40 * faces.length;
  final out = BytesBuilder();
  final bodies = BytesBuilder();
  final dir = BytesBuilder();
  var off = dirEnd;
  for (final (fam, varnt, body) in faces) {
    final e = Uint8List(40);
    e.setRange(0, fam.length, fam.codeUnits);
    e.setRange(16, 16 + varnt.length, varnt.codeUnits);
    final eb = ByteData.sublistView(e);
    eb.setUint32(32, off, Endian.little);
    eb.setUint32(36, body.length, Endian.little);
    dir.add(e);
    bodies.add(body);
    final pad = (4 - body.length % 4) % 4;
    bodies.add(Uint8List(pad));
    off += body.length + pad;
  }
  final hdr = Uint8List(16);
  hdr.setRange(0, 4, 'SCTF'.codeUnits);
  final hb = ByteData.sublistView(hdr);
  hb.setUint16(4, 1, Endian.little);
  hb.setUint16(6, faces.length, Endian.little);
  hb.setUint32(12, dirEnd + bodies.length, Endian.little);
  out.add(hdr);
  out.add(dir.toBytes());
  out.add(bodies.toBytes());
  return out.toBytes();
}

(String, String, Uint8List) face(Uint8List blob, int i) {
  final e = blob.sublist(16 + i * 40, 16 + i * 40 + 40);
  final eb = ByteData.sublistView(Uint8List.fromList(e));
  final off = eb.getUint32(32, Endian.little);
  final len = eb.getUint32(36, Endian.little);
  String str(List<int> b) => String.fromCharCodes(b.takeWhile((c) => c != 0));
  return (
    str(e.sublist(0, 16)),
    str(e.sublist(16, 32)),
    Uint8List.sublistView(blob, off, off + len)
  );
}

void main() {
  final store = FontStore(NorClient(FakeNet()));
  final blob = sctf([
    ('Inter', 'Light', [1, 2, 3, 4, 5]),
    ('Lora', 'Italic', [9, 8, 7]),
    ('Bitter', 'Bold', [6, 6, 6, 6, 6, 6, 6]),
  ]);

  test('removeFont drops the face and repacks the rest', () {
    final out = store.removeFont(blob, 1);
    final count = ByteData.sublistView(out).getUint16(6, Endian.little);
    expect(count, 2);
    final f0 = face(out, 0);
    expect((f0.$1, f0.$2), ('Inter', 'Light'));
    expect(f0.$3, orderedEquals([1, 2, 3, 4, 5]));
    final f1 = face(out, 1);
    expect((f1.$1, f1.$2), ('Bitter', 'Bold'));
    expect(f1.$3, orderedEquals([6, 6, 6, 6, 6, 6, 6]));
    final total = ByteData.sublistView(out).getUint32(12, Endian.little);
    expect(total, out.length);
  });

  test('renameFont keeps bodies intact', () {
    final out = store.renameFont(blob, 2, 'Archivo', 'Black');
    final f2 = face(out, 2);
    expect((f2.$1, f2.$2), ('Archivo', 'Black'));
    expect(f2.$3, orderedEquals([6, 6, 6, 6, 6, 6, 6]));
    expect(face(out, 0).$3, orderedEquals([1, 2, 3, 4, 5]));
    expect(ByteData.sublistView(out).getUint16(6, Endian.little), 3);
  });

  test('remove then remove leaves one face', () {
    var out = store.removeFont(blob, 0);
    out = store.removeFont(out, 1);
    expect(ByteData.sublistView(out).getUint16(6, Endian.little), 1);
    expect(face(out, 0).$1, 'Lora');
  });
}

// NorClient is only needed to construct FontStore; the rebuilds are pure.
class FakeNet implements Network {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
