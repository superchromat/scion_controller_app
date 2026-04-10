import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'network.dart';
import 'osc_registry.dart';
import 'labeled_card.dart';
import 'grid.dart';

/// Page that grabs and displays 64x64 thumbnails from each video channel.
class ThumbnailPage extends StatefulWidget {
  const ThumbnailPage({super.key});

  @override
  State<ThumbnailPage> createState() => _ThumbnailPageState();
}

class _ThumbnailPageState extends State<ThumbnailPage> {
  // Raw blob data per channel (null = not yet captured)
  Uint8List? _outputData;
  Uint8List? _send1Data;
  Uint8List? _send2Data;
  Uint8List? _send3Data;

  bool _loading = false;

  static const _channels = [
    ('/output/thumbnail', 'Output'),
    ('/send/1/thumbnail', 'Send 1'),
    ('/send/2/thumbnail', 'Send 2'),
    ('/send/3/thumbnail', 'Send 3'),
  ];

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    for (final (addr, _) in _channels) {
      reg.registerAddress(addr);
      reg.registerListener(addr, _makeListener(addr));
    }
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    for (final (addr, _) in _channels) {
      reg.unregisterListener(addr, _makeListener(addr));
    }
    super.dispose();
  }

  // We need stable listener references for register/unregister.
  // Use a map keyed by address.
  final Map<String, void Function(List<Object?>)> _listeners = {};

  void Function(List<Object?>) _makeListener(String addr) {
    return _listeners.putIfAbsent(addr, () => (args) => _onThumbnail(addr, args));
  }

  // Track width/height and accumulating buffer per channel
  final Map<String, int> _thumbW = {};
  final Map<String, int> _thumbH = {};
  final Map<String, Uint8List> _thumbAccum = {};

  void _onThumbnail(String addr, List<Object?> args) {
    // New chunked protocol: (int width, int height, int offset, blob chunk)
    if (args.length >= 4 &&
        args[0] is int && args[1] is int && args[2] is int && args[3] is Uint8List) {
      final w = args[0] as int;
      final h = args[1] as int;
      final offset = args[2] as int;
      final chunk = args[3] as Uint8List;
      final total = w * h * 3;

      // Allocate or reset buffer if dimensions changed
      if (_thumbW[addr] != w || _thumbH[addr] != h ||
          _thumbAccum[addr] == null || _thumbAccum[addr]!.length != total) {
        _thumbW[addr] = w;
        _thumbH[addr] = h;
        _thumbAccum[addr] = Uint8List(total);
      }

      final buf = _thumbAccum[addr]!;
      final end = (offset + chunk.length).clamp(0, total);
      buf.setRange(offset, end, chunk);

      // When last chunk received, update display
      if (end >= total || offset + chunk.length >= total) {
        setState(() {
          switch (addr) {
            case '/output/thumbnail': _outputData = Uint8List.fromList(buf);
            case '/send/1/thumbnail': _send1Data = Uint8List.fromList(buf);
            case '/send/2/thumbnail': _send2Data = Uint8List.fromList(buf);
            case '/send/3/thumbnail': _send3Data = Uint8List.fromList(buf);
          }
        });
      }
      return;
    }

    // Legacy: single blob (old protocol)
    if (args.isNotEmpty && args.first is Uint8List) {
      final blob = args.first as Uint8List;
      setState(() {
        switch (addr) {
          case '/output/thumbnail': _outputData = blob;
          case '/send/1/thumbnail': _send1Data = blob;
          case '/send/2/thumbnail': _send2Data = blob;
          case '/send/3/thumbnail': _send3Data = blob;
        }
      });
    }
  }

  Uint8List? _dataFor(String addr) {
    return switch (addr) {
      '/output/thumbnail' => _outputData,
      '/send/1/thumbnail' => _send1Data,
      '/send/2/thumbnail' => _send2Data,
      '/send/3/thumbnail' => _send3Data,
      _ => null,
    };
  }

  Future<void> _grabAll() async {
    final network = context.read<Network>();
    if (!network.isConnected) return;

    setState(() => _loading = true);

    for (final (addr, _) in _channels) {
      network.sendOscMessage(addr, []);
      // Small delay between requests to avoid overwhelming the firmware
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // Wait for responses
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final t = GridTokens(constraints.maxWidth);
      return GridProvider(
        tokens: t,
        child: ListView(
          padding: EdgeInsets.all(t.md),
          children: [
            LabeledCard(
              title: 'Channel Thumbnails',
              networkIndependent: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.icon(
                    onPressed: _loading ? null : _grabAll,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt),
                    label: Text(_loading ? 'Capturing...' : 'Grab Thumbnails'),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final (addr, label) in _channels)
                        _ThumbnailTile(
                          label: label,
                          data: _dataFor(addr),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Displays a single channel's thumbnail blob as a scaled image.
class _ThumbnailTile extends StatelessWidget {
  final String label;
  final Uint8List? data;

  const _ThumbnailTile({required this.label, this.data});

  @override
  Widget build(BuildContext context) {
    const thumbSize = 64;
    const displaySize = 192.0; // Scale up for visibility

    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          width: displaySize,
          height: displaySize,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.grey.shade700),
            borderRadius: BorderRadius.circular(4),
          ),
          child: data == null
              ? const Center(
                  child: Text('No data', style: TextStyle(color: Colors.grey)),
                )
              : _buildImage(thumbSize),
        ),
        if (data != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${data!.length} bytes',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildImage(int _) {
    final bytes = data!;

    // Determine dimensions: prefer stored w/h, else infer from size
    int thumbW = 0, thumbH = 0;
    // Check parent's stored dimensions
    // (passed via the tile — we'll use data length heuristic)
    if (bytes.length % 3 == 0) {
      final pixels = bytes.length ~/ 3;
      // Try common non-square sizes first
      if (pixels == 64 * 32) { thumbW = 64; thumbH = 32; }
      else if (pixels == 64 * 64) { thumbW = 64; thumbH = 64; }
      else {
        final side = _isqrt(pixels);
        if (side * side == pixels) { thumbW = side; thumbH = side; }
      }
    }
    if (thumbW == 0) {
      final side = _isqrt(bytes.length);
      thumbW = side > 0 ? side : 1;
      thumbH = thumbW;
    }

    final isRgb = bytes.length >= thumbW * thumbH * 3;
    final pixelCount = thumbW * thumbH;
    final rgba = Uint8List(pixelCount * 4);

    if (isRgb) {
      // Firmware sends Y, Cb, Cr per pixel (zero-centered chroma)
      for (int i = 0; i < pixelCount; i++) {
        final y  = bytes[i * 3 + 0].toDouble();
        final cb = bytes[i * 3 + 1].toDouble() - 128;
        final cr = bytes[i * 3 + 2].toDouble() - 128;
        // BT.709 YCbCr → RGB (offset-128 chroma)
        final r = (y + 1.5748 * cr).round().clamp(0, 255);
        final g = (y - 0.1873 * cb - 0.4681 * cr).round().clamp(0, 255);
        final b = (y + 1.8556 * cb).round().clamp(0, 255);
        rgba[i * 4 + 0] = r;
        rgba[i * 4 + 1] = g;
        rgba[i * 4 + 2] = b;
        rgba[i * 4 + 3] = 255;
      }
    } else {
      for (int i = 0; i < pixelCount && i < bytes.length; i++) {
        rgba[i * 4 + 0] = bytes[i];
        rgba[i * 4 + 1] = bytes[i];
        rgba[i * 4 + 2] = bytes[i];
        rgba[i * 4 + 3] = 255;
      }
    }

    final bmp = _encodeBmp(rgba, thumbW, thumbH);
    return Image(
      image: MemoryImage(bmp),
      width: 256,
      height: 256.0 * thumbH / thumbW,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none, // Nearest-neighbor for crisp pixels
    );
  }

  static int _isqrt(int n) {
    if (n <= 0) return 0;
    int x = n;
    int y = (x + 1) ~/ 2;
    while (y < x) {
      x = y;
      y = (x + n ~/ x) ~/ 2;
    }
    return x;
  }

  /// Encode RGBA pixel data as a 32-bit BMP.
  static Uint8List _encodeBmp(Uint8List rgba, int width, int height) {
    final rowBytes = width * 4;
    final imageSize = rowBytes * height;
    final fileSize = 54 + imageSize; // 14 (file header) + 40 (DIB header) + pixels

    final bmp = ByteData(fileSize);
    // File header
    bmp.setUint8(0, 0x42); // 'B'
    bmp.setUint8(1, 0x4D); // 'M'
    bmp.setUint32(2, fileSize, Endian.little);
    bmp.setUint32(10, 54, Endian.little); // pixel data offset

    // DIB header (BITMAPINFOHEADER)
    bmp.setUint32(14, 40, Endian.little); // header size
    bmp.setInt32(18, width, Endian.little);
    bmp.setInt32(22, -height, Endian.little); // negative = top-down
    bmp.setUint16(26, 1, Endian.little); // planes
    bmp.setUint16(28, 32, Endian.little); // bits per pixel
    bmp.setUint32(30, 0, Endian.little); // compression (none)
    bmp.setUint32(34, imageSize, Endian.little);

    // Pixel data (BMP uses BGRA)
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
