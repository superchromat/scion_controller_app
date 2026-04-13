import 'package:flutter/foundation.dart';

import 'network.dart';
import 'osc_registry.dart';

/// Shared service that listens for thumbnail OSC messages and provides
/// BMP image data for each channel. Used by both ThumbnailPage and
/// system overview tiles.
class ThumbnailService extends ChangeNotifier {
  static final ThumbnailService _instance = ThumbnailService._internal();
  factory ThumbnailService() => _instance;
  ThumbnailService._internal() {
    _init();
  }

  static const _addresses = [
    '/output/thumbnail',
    '/send/1/thumbnail',
    '/send/2/thumbnail',
    '/send/3/thumbnail',
  ];

  final Map<String, Uint8List> _bmpImages = {};
  final Map<String, int> _thumbW = {};
  final Map<String, int> _thumbH = {};
  final Map<String, Uint8List> _accumBuf = {};

  void _init() {
    final reg = OscRegistry();
    for (final addr in _addresses) {
      reg.registerAddress(addr);
      reg.registerListener(addr, (args) => _onThumbnail(addr, args));
    }
  }

  /// Get the BMP image for a thumbnail address, or null if not yet received.
  Uint8List? getBmp(String address) => _bmpImages[address];

  /// Request a thumbnail refresh for all channels.
  void requestAll(Network network) {
    if (!network.isConnected) return;
    for (final addr in _addresses) {
      network.sendOscMessage(addr, []);
    }
  }

  void _onThumbnail(String addr, List<Object?> args) {
    // Chunked protocol: (int width, int height, int offset, blob chunk)
    if (args.length >= 4 &&
        args[0] is int && args[1] is int && args[2] is int && args[3] is Uint8List) {
      final w = args[0] as int;
      final h = args[1] as int;
      final offset = args[2] as int;
      final chunk = args[3] as Uint8List;
      final total = w * h * 3;

      if (_thumbW[addr] != w || _thumbH[addr] != h ||
          _accumBuf[addr] == null || _accumBuf[addr]!.length != total) {
        _thumbW[addr] = w;
        _thumbH[addr] = h;
        _accumBuf[addr] = Uint8List(total);
      }

      final buf = _accumBuf[addr]!;
      final end = (offset + chunk.length).clamp(0, total);
      buf.setRange(offset, end, chunk);

      if (end >= total || offset + chunk.length >= total) {
        _bmpImages[addr] = _ycbcrToBmp(buf, w, h);
        notifyListeners();
      }
      return;
    }

    // Legacy: single blob
    if (args.isNotEmpty && args.first is Uint8List) {
      final blob = args.first as Uint8List;
      final pixels = blob.length ~/ 3;
      int w = 64, h = 32;
      if (pixels == 64 * 32) { w = 64; h = 32; }
      else if (pixels == 64 * 64) { w = 64; h = 64; }
      _bmpImages[addr] = _ycbcrToBmp(blob, w, h);
      notifyListeners();
    }
  }

  static Uint8List _ycbcrToBmp(Uint8List ycbcr, int w, int h) {
    final pixelCount = w * h;
    final rgba = Uint8List(pixelCount * 4);

    if (ycbcr.length >= pixelCount * 3) {
      for (int i = 0; i < pixelCount; i++) {
        final y  = ycbcr[i * 3 + 0].toDouble();
        final cb = ycbcr[i * 3 + 1].toDouble() - 128;
        final cr = ycbcr[i * 3 + 2].toDouble() - 128;
        rgba[i * 4 + 0] = (y + 1.5748 * cr).round().clamp(0, 255);
        rgba[i * 4 + 1] = (y - 0.1873 * cb - 0.4681 * cr).round().clamp(0, 255);
        rgba[i * 4 + 2] = (y + 1.8556 * cb).round().clamp(0, 255);
        rgba[i * 4 + 3] = 255;
      }
    }

    return _encodeBmp(rgba, w, h);
  }

  static Uint8List _encodeBmp(Uint8List rgba, int width, int height) {
    final rowBytes = width * 4;
    final imageSize = rowBytes * height;
    final fileSize = 54 + imageSize;

    final bmp = ByteData(fileSize);
    bmp.setUint8(0, 0x42);
    bmp.setUint8(1, 0x4D);
    bmp.setUint32(2, fileSize, Endian.little);
    bmp.setUint32(10, 54, Endian.little);
    bmp.setUint32(14, 40, Endian.little);
    bmp.setInt32(18, width, Endian.little);
    bmp.setInt32(22, -height, Endian.little);
    bmp.setUint16(26, 1, Endian.little);
    bmp.setUint16(28, 32, Endian.little);
    bmp.setUint32(30, 0, Endian.little);
    bmp.setUint32(34, imageSize, Endian.little);

    final pixels = bmp.buffer.asUint8List(54);
    for (int i = 0; i < width * height; i++) {
      pixels[i * 4 + 0] = rgba[i * 4 + 2]; // B
      pixels[i * 4 + 1] = rgba[i * 4 + 1]; // G
      pixels[i * 4 + 2] = rgba[i * 4 + 0]; // R
      pixels[i * 4 + 3] = rgba[i * 4 + 3]; // A
    }

    return bmp.buffer.asUint8List();
  }
}
