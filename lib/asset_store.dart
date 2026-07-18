// asset_store.dart
// In-app management of the device's NOR asset store: fonts (SCTF blob at
// offset 0) and sprites (SPRT blob at +8 MB). Read-modify-write over the
// /fonts/nor/{read,erase,write,verify} OSC transport, plus a pure-Dart
// PNG→4bpp sprite converter (median-cut to 15 colours + transparency).
//
// Blob formats mirror tools/fonts/{gen_ttf,spritectl}.py — see osc_sprite.c
// and ttf_font.c for the firmware readers.

import 'dart:async';
import 'dart:typed_data';
import 'network.dart';
import 'osc_registry.dart';

const sprtBase = 0x800000;
const fwTtfMax = 48 * 1024; // firmware g_ttf buffer (ttf_font.c TTF_MAX)
const spriteMaxBytes = 245760; // ext-region DDR budget (w/2 * h)
const spriteMaxW = 1920;
const _chunk = 896; // read/write chunk (fits the 1 KB firmware OSC buffer)

// ---------------------------------------------------------------- crc32 ----

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int crc32(Uint8List data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

int _signed32(int v) => v >= 0x80000000 ? v - 0x100000000 : v;

// ------------------------------------------------------------ NOR client ---

/// Request/response client for the /fonts/nor/* transport. One in-flight
/// request at a time (the device replies on the same path).
class NorClient {
  final Network net;
  NorClient(this.net);

  Future<List<Object?>> _call(String addr, List<Object> args,
      {Duration timeout = const Duration(seconds: 3), int tries = 3}) async {
    OscRegistry().registerAddress(addr);
    for (var attempt = 0; attempt < tries; attempt++) {
      final c = Completer<List<Object?>>();
      void listener(List<Object?> a) {
        if (!c.isCompleted) c.complete(a);
      }

      OscRegistry().registerListener(addr, listener);
      try {
        // Synchronous RPC: bypass the 30 Hz coalescer so long read/erase/verify
        // chains (e.g. sprite delete = full-blob read + rewrite) aren't slowed
        // by ~33 ms of queuing latency per call.
        net.sendOscMessage(addr, args, immediate: true);
        return await c.future.timeout(timeout);
      } on TimeoutException {
        // retry
      } finally {
        OscRegistry().unregisterListener(addr, listener);
      }
    }
    throw TimeoutException('no reply to $addr');
  }

  /// Public request/response for asset-manager endpoints.
  Future<List<Object?>> call(String addr, List<Object> args,
          {Duration timeout = const Duration(seconds: 3), int tries = 3}) =>
      _call(addr, args, timeout: timeout, tries: tries);

  Future<Uint8List> read(int off, int len) async {
    final out = BytesBuilder();
    var pos = 0;
    while (pos < len) {
      final n = (len - pos).clamp(0, _chunk);
      final r = await _call('/assets/fonts/nor/read', [off + pos, n]);
      // reply: [off, count, blob]
      if (r.length < 3 || r[1] is! int || (r[1] as int) < 0 || r[2] is! Uint8List) {
        throw Exception('NOR read failed at ${off + pos}: $r');
      }
      final blob = r[2] as Uint8List;
      out.add(blob.sublist(0, (r[1] as int).clamp(0, blob.length)));
      pos += n;
    }
    return out.toBytes();
  }

  /// Erase + write + CRC-verify `blob` at `off`.
  Future<void> writeBlob(int off, Uint8List blob,
      {void Function(double)? onProgress}) async {
    final er = await _call('/assets/fonts/nor/erase', [blob.length, off],
        timeout: const Duration(seconds: 10));
    if (er.isEmpty || er[0] is! int || (er[0] as int) < blob.length) {
      throw Exception('erase failed: $er');
    }
    for (var pos = 0; pos < blob.length; pos += _chunk) {
      final chunk = Uint8List.sublistView(
          blob, pos, (pos + _chunk).clamp(0, blob.length));
      final r = await _call(
          '/assets/fonts/nor/write', [off + pos, _signed32(crc32(chunk)), chunk]);
      if (r.length < 2 || r[1] != 0) {
        throw Exception('write failed at ${off + pos}: $r');
      }
      onProgress?.call((pos + chunk.length) / blob.length);
    }
    final v = await _call('/assets/fonts/nor/verify', [off, blob.length],
        timeout: const Duration(seconds: 10));
    if (v.isEmpty || (v[0] as int? ?? -1) & 0xFFFFFFFF != crc32(blob)) {
      throw Exception('verify failed: $v vs ${crc32(blob).toRadixString(16)}');
    }
  }
}

// -------------------------------------------------------------- sprites ----

class SpriteAsset {
  final String name;
  final int w, h;
  final Uint8List palette; // 64 B, MDIN [Cr, alpha, Cb, Y] entries
  final Uint8List pixels; // 4bpp rows, bpr = (w+1)~/2
  SpriteAsset(this.name, this.w, this.h, this.palette, this.pixels);
}

class SpriteStore {
  final NorClient nor;
  SpriteStore(this.nor);

  /// Fetch and parse the on-device SPRT blob (empty list if absent).
  Future<List<SpriteAsset>> fetch() async {
    final hdr = await nor.read(sprtBase, 12);
    if (hdr.length < 12 ||
        String.fromCharCodes(hdr.sublist(0, 4)) != 'SPRT' ||
        hdr[4] != 1) {
      return [];
    }
    final bd = ByteData.sublistView(hdr);
    final count = bd.getUint16(6, Endian.little);
    final out = <SpriteAsset>[];
    for (var i = 0; i < count; i++) {
      final e = await nor.read(sprtBase + 12 + i * 96, 96);
      final eb = ByteData.sublistView(e);
      final name = String.fromCharCodes(e.sublist(0, 16).takeWhile((c) => c != 0));
      final w = eb.getUint16(16, Endian.little);
      final h = eb.getUint16(18, Endian.little);
      final off = eb.getUint32(20, Endian.little);
      final len = eb.getUint32(24, Endian.little);
      final pal = Uint8List.fromList(e.sublist(28, 92));
      final px = await nor.read(off, len);
      out.add(SpriteAsset(name, w, h, pal, px));
    }
    return out;
  }

  /// Catalog metadata only (no pixel data) — cheap listing for the Files page.
  Future<List<(String, int, int, int)>> catalog() async {
    final hdr = await nor.read(sprtBase, 12);
    if (hdr.length < 12 ||
        String.fromCharCodes(hdr.sublist(0, 4)) != 'SPRT' ||
        hdr[4] != 1) {
      return [];
    }
    final count = ByteData.sublistView(hdr).getUint16(6, Endian.little);
    final out = <(String, int, int, int)>[];
    for (var i = 0; i < count; i++) {
      final e = await nor.read(sprtBase + 12 + i * 96, 96);
      final eb = ByteData.sublistView(e);
      final name =
          String.fromCharCodes(e.sublist(0, 16).takeWhile((c) => c != 0));
      out.add((name, eb.getUint16(16, Endian.little),
          eb.getUint16(18, Endian.little), eb.getUint32(24, Endian.little)));
    }
    return out;
  }

  /// Read just one sprite's 64-byte palette (no pixel data) — cheap enough to
  /// call whenever the selected sprite changes.
  Future<Uint8List?> fetchPalette(int index) async {
    final hdr = await nor.read(sprtBase, 12);
    if (hdr.length < 12 ||
        String.fromCharCodes(hdr.sublist(0, 4)) != 'SPRT' ||
        hdr[4] != 1) {
      return null;
    }
    final count = ByteData.sublistView(hdr).getUint16(6, Endian.little);
    if (index < 0 || index >= count) return null;
    final pal = await nor.read(sprtBase + 12 + index * 96 + 28, 64);
    return pal.length >= 64 ? Uint8List.fromList(pal.sublist(0, 64)) : null;
  }

  /// Persist an edited palette for sprite [index] by rewriting the whole store
  /// (the NOR transport erases + rewrites the SPRT blob; pixel data is carried
  /// through unchanged).
  Future<void> savePalette(int index, Uint8List palette,
      {void Function(double)? onProgress}) async {
    final sprites = await fetch();
    if (index < 0 || index >= sprites.length) return;
    final s = sprites[index];
    sprites[index] = SpriteAsset(s.name, s.w, s.h, palette, s.pixels);
    await push(sprites, onProgress: onProgress);
  }

  Uint8List buildBlob(List<SpriteAsset> sprites) {
    final body = BytesBuilder();
    final dir = BytesBuilder();
    var dataOff = sprtBase + 12 + 96 * sprites.length;
    for (final s in sprites) {
      final e = ByteData(96);
      final nameBytes = s.name.codeUnits.take(16).toList();
      for (var i = 0; i < nameBytes.length; i++) {
        e.setUint8(i, nameBytes[i]);
      }
      e.setUint16(16, s.w, Endian.little);
      e.setUint16(18, s.h, Endian.little);
      e.setUint32(20, dataOff, Endian.little);
      e.setUint32(24, s.pixels.length, Endian.little);
      final eb = e.buffer.asUint8List();
      eb.setRange(28, 92, s.palette);
      dir.add(eb);
      body.add(s.pixels);
      dataOff += s.pixels.length;
    }
    final hdr = ByteData(12);
    hdr.setUint8(0, 0x53); hdr.setUint8(1, 0x50); // 'S' 'P'
    hdr.setUint8(2, 0x52); hdr.setUint8(3, 0x54); // 'R' 'T'
    hdr.setUint16(4, 1, Endian.little);
    hdr.setUint16(6, sprites.length, Endian.little);
    final out = BytesBuilder();
    out.add(hdr.buffer.asUint8List());
    out.add(dir.toBytes());
    out.add(body.toBytes());
    return out.toBytes();
  }

  Future<void> push(List<SpriteAsset> sprites,
      {void Function(double)? onProgress}) =>
      nor.writeBlob(sprtBase, buildBlob(sprites), onProgress: onProgress);
}

// ------------------------------------------------- sprite conversion -------

/// Median-cut quantization of opaque pixels to at most [n] colours.
/// [rgba] is w*h*4. Returns the palette as a list of [r,g,b].
List<List<int>> _medianCut(Uint8List rgba, int n) {
  // Sample opaque pixels (cap the sample for speed).
  final px = <int>[]; // packed 0xRRGGBB
  final total = rgba.length ~/ 4;
  final step = total > 65536 ? total ~/ 65536 : 1;
  for (var i = 0; i < total; i += step) {
    if (rgba[i * 4 + 3] >= 128) {
      px.add((rgba[i * 4] << 16) | (rgba[i * 4 + 1] << 8) | rgba[i * 4 + 2]);
    }
  }
  if (px.isEmpty) return [];
  var boxes = <List<int>>[px];
  while (boxes.length < n) {
    // Split the box with the widest channel range.
    var bi = -1, bch = 0, brange = -1;
    for (var i = 0; i < boxes.length; i++) {
      if (boxes[i].length < 2) continue;
      for (var ch = 0; ch < 3; ch++) {
        final sh = (2 - ch) * 8;
        var lo = 255, hi = 0;
        for (final p in boxes[i]) {
          final v = (p >> sh) & 0xFF;
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }
        if (hi - lo > brange) {
          brange = hi - lo;
          bi = i;
          bch = ch;
        }
      }
    }
    if (bi < 0 || brange <= 0) break;
    final sh = (2 - bch) * 8;
    final box = boxes[bi]..sort((a, b) => ((a >> sh) & 0xFF) - ((b >> sh) & 0xFF));
    final mid = box.length ~/ 2;
    boxes[bi] = box.sublist(0, mid);
    boxes.add(box.sublist(mid));
  }
  return [
    for (final box in boxes)
      [
        box.map((p) => (p >> 16) & 0xFF).reduce((a, b) => a + b) ~/ box.length,
        box.map((p) => (p >> 8) & 0xFF).reduce((a, b) => a + b) ~/ box.length,
        box.map((p) => p & 0xFF).reduce((a, b) => a + b) ~/ box.length,
      ]
  ];
}

/// Convert RGBA pixels to a SpriteAsset: 15 colours + transparent index 0,
/// 4bpp packed (high nibble first). Rows are padded to 16-px multiples
/// (8-byte display pitch — unaligned widths skew). Caller must pre-scale to
/// fit [spriteMaxW] / [spriteMaxBytes] (see fitSpriteSize).
SpriteAsset convertSprite(String name, int w, int h, Uint8List rgba) {
  // Pad width to a 32-px multiple (16-byte display pitch) with transparent
  // pixels — 16-px padding still skewed on hardware.
  if (w % 32 != 0) {
    final pw = w + 32 - w % 32;
    final padded = Uint8List(pw * h * 4);
    for (var y = 0; y < h; y++) {
      padded.setRange(y * pw * 4, y * pw * 4 + w * 4, rgba, y * w * 4);
    }
    rgba = padded;
    w = pw;
  }
  final pal = _medianCut(rgba, 15);
  // Display-block palette: RGB, byte order [R, alpha, B, G] in limited-range
  // values (probed on hardware); entry 0 stays transparent (alpha 0).
  int lim(int v) => 16 + (v * 219 + 127) ~/ 255;
  final mp = Uint8List(64);
  for (var i = 0; i < pal.length; i++) {
    mp[(i + 1) * 4] = lim(pal[i][0]); // R
    mp[(i + 1) * 4 + 1] = 255; // alpha
    mp[(i + 1) * 4 + 2] = lim(pal[i][2]); // B
    mp[(i + 1) * 4 + 3] = lim(pal[i][1]); // G
  }
  int nearest(int r, int g, int b) {
    var best = 0, bd = 1 << 30;
    for (var i = 0; i < pal.length; i++) {
      final d = (r - pal[i][0]) * (r - pal[i][0]) +
          (g - pal[i][1]) * (g - pal[i][1]) +
          (b - pal[i][2]) * (b - pal[i][2]);
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best + 1;
  }

  final bpr = (w + 1) ~/ 2;
  final data = Uint8List(bpr * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final idx = rgba[i + 3] < 128 ? 0 : nearest(rgba[i], rgba[i + 1], rgba[i + 2]);
      data[y * bpr + x ~/ 2] |= idx << (x % 2 == 0 ? 4 : 0);
    }
  }
  return SpriteAsset(name, w, h, mp, data);
}

/// Target (w, h) so the sprite fits the firmware budget; (w, h) unchanged if
/// already small enough.
(int, int) fitSpriteSize(int w, int h) {
  var tw = w, th = h;
  if (tw > spriteMaxW) {
    th = th * spriteMaxW ~/ tw;
    tw = spriteMaxW;
  }
  while ((tw + 1) ~/ 2 * th > spriteMaxBytes) {
    tw = tw * 3 ~/ 4;
    th = th * 3 ~/ 4;
  }
  return (tw, th);
}

// ---------------------------------------------------------------- fonts ----

class FontStore {
  final NorClient nor;
  FontStore(this.nor);

  /// Read the full SCTF blob (header + directory + TTFs). Returns null if the
  /// store is unprovisioned.
  Future<Uint8List?> fetchBlob() async {
    final hdr = await nor.read(0, 16);
    if (hdr.length < 16 ||
        String.fromCharCodes(hdr.sublist(0, 4)) != 'SCTF' ||
        hdr[4] != 1) {
      return null;
    }
    final total = ByteData.sublistView(hdr).getUint32(12, Endian.little);
    if (total < 16 || total > 4 * 1024 * 1024) return null;
    return nor.read(0, total);
  }

  /// Append a TTF (must already fit [fwTtfMax]) and return the new blob.
  Uint8List appendFont(
      Uint8List blob, String family, String variant, Uint8List ttf) {
    final bd = ByteData.sublistView(blob);
    final count = bd.getUint16(6, Endian.little);
    final dirEnd = 16 + 40 * count;
    // New directory is 40 B longer: shift every TTF offset by 40 (+ pad).
    final newDirEnd = dirEnd + 40;
    final shift = newDirEnd - dirEnd;
    final out = BytesBuilder();
    final hdr = Uint8List.fromList(blob.sublist(0, 16));
    final body = blob.sublist(dirEnd);
    ByteData.sublistView(hdr).setUint16(6, count + 1, Endian.little);
    final newBodyLen = ((body.length + 3) & ~3) + ttf.length;
    ByteData.sublistView(hdr)
        .setUint32(12, newDirEnd + newBodyLen, Endian.little);
    out.add(hdr);
    for (var i = 0; i < count; i++) {
      final e = Uint8List.fromList(blob.sublist(16 + i * 40, 16 + i * 40 + 40));
      final eb = ByteData.sublistView(e);
      eb.setUint32(32, eb.getUint32(32, Endian.little) + shift, Endian.little);
      out.add(e);
    }
    // New entry: TTF goes after the (4-aligned) existing body.
    final pad = (4 - body.length % 4) % 4;
    final e = Uint8List(40);
    final fb = family.codeUnits.take(16).toList();
    final vb = variant.codeUnits.take(16).toList();
    e.setRange(0, fb.length, fb);
    e.setRange(16, 16 + vb.length, vb);
    final eb = ByteData.sublistView(e);
    eb.setUint32(32, newDirEnd + body.length + pad, Endian.little);
    eb.setUint32(36, ttf.length, Endian.little);
    out.add(e);
    out.add(body);
    out.add(Uint8List(pad));
    out.add(ttf);
    return out.toBytes();
  }

  Future<void> push(Uint8List blob, {void Function(double)? onProgress}) =>
      nor.writeBlob(0, blob, onProgress: onProgress);

  /// Rebuild the blob without face [index] (repacks the kept TTF bodies).
  Uint8List removeFont(Uint8List blob, int index) =>
      _rebuild(blob, skip: index);

  /// Rebuild with face [index] renamed.
  Uint8List renameFont(
          Uint8List blob, int index, String family, String variant) =>
      _rebuild(blob, rename: index, family: family, variant: variant);

  Uint8List _rebuild(Uint8List blob,
      {int skip = -1, int rename = -1, String? family, String? variant}) {
    final bd = ByteData.sublistView(blob);
    final count = bd.getUint16(6, Endian.little);
    final faces = <(Uint8List name, Uint8List ttf)>[];
    for (var i = 0; i < count; i++) {
      if (i == skip) continue;
      final e = Uint8List.fromList(blob.sublist(16 + i * 40, 16 + i * 40 + 40));
      final eb = ByteData.sublistView(e);
      final off = eb.getUint32(32, Endian.little);
      final len = eb.getUint32(36, Endian.little);
      if (i == rename) {
        e.fillRange(0, 32, 0);
        final fb = (family ?? '').codeUnits.take(16).toList();
        final vb = (variant ?? '').codeUnits.take(16).toList();
        e.setRange(0, fb.length, fb);
        e.setRange(16, 16 + vb.length, vb);
      }
      faces.add((e, Uint8List.sublistView(blob, off, off + len)));
    }
    final hdr = Uint8List.fromList(blob.sublist(0, 16));
    ByteData.sublistView(hdr).setUint16(6, faces.length, Endian.little);
    final out = BytesBuilder();
    out.add(hdr);
    var off = 16 + 40 * faces.length;
    final bodies = BytesBuilder();
    for (final (e, ttf) in faces) {
      final eb = ByteData.sublistView(e);
      eb.setUint32(32, off, Endian.little);
      eb.setUint32(36, ttf.length, Endian.little);
      out.add(e);
      bodies.add(ttf);
      final pad = (4 - ttf.length % 4) % 4;
      bodies.add(Uint8List(pad));
      off += ttf.length + pad;
    }
    final total = 16 + 40 * faces.length + bodies.length;
    ByteData.sublistView(hdr).setUint32(12, total, Endian.little);
    final result = out.toBytes() + bodies.toBytes();
    final res = Uint8List.fromList(result);
    res.setRange(0, 16, hdr);
    return res;
  }
}

/// True if the TTF has TrueType glyf outlines (the firmware renderer can't
/// rasterise OTF/CFF).
bool ttfHasGlyf(Uint8List ttf) {
  if (ttf.length < 12) return false;
  final bd = ByteData.sublistView(ttf);
  final numTables = bd.getUint16(4);
  for (var i = 0; i < numTables && 12 + i * 16 + 16 <= ttf.length; i++) {
    final tag = String.fromCharCodes(ttf.sublist(12 + i * 16, 12 + i * 16 + 4));
    if (tag == 'glyf') return true;
  }
  return false;
}
