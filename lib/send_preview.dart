import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'network.dart';
import 'osc_registry.dart';

/// Live JPEG preview of a send, from the device's `/send/N/preview` endpoint
/// (rev2 hybrid mode: the MDIN's internal CPU downscales the frame, the STM32
/// encodes it as JPEG). The reply is one or more `/send/N/preview` messages
/// `[w, h, total, offset, chunk]`; the next frame is requested when the last
/// one is complete, so the rate follows what the device can deliver.
class SendPreview extends StatefulWidget {
  final int pageNumber;
  final int width;
  final int height;
  final int quality;

  /// Upper bound on the request rate.
  final double maxFps;

  const SendPreview({
    super.key,
    required this.pageNumber,
    this.width = 192,
    this.height = 112,
    this.quality = 75,
    this.maxFps = 10,
  });

  @override
  State<SendPreview> createState() => _SendPreviewState();
}

class _SendPreviewState extends State<SendPreview> {
  late final String _path = '/send/${widget.pageNumber}/preview';

  Uint8List? _image; // last complete JPEG
  Uint8List? _rx; // frame being assembled
  int _rxTotal = 0;
  int _rxGot = 0;
  final Set<int> _rxOffsets = {}; // chunks already counted (drops duplicates)

  bool _running = true;
  Timer? _watchdog;
  Timer? _next;
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  int _misses = 0;

  final List<DateTime> _frameTimes = [];
  double _fps = 0;

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress(_path);
    reg.registerListener(_path, _onChunk);
    WidgetsBinding.instance.addPostFrameCallback((_) => _request());
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _next?.cancel();
    OscRegistry().unregisterListener(_path, _onChunk);
    super.dispose();
  }

  void _request() {
    _next?.cancel();
    _watchdog?.cancel();
    if (!mounted || !_running) return;
    final net = context.read<Network>();
    _lastRequest = DateTime.now();
    _rx = null;
    net.sendOscMessage(_path, [widget.width, widget.height, widget.quality],
        immediate: true);
    // No complete frame in time (lost datagram, device busy, not in hybrid
    // mode): ask again, backing off after repeated misses.
    final wait = Duration(milliseconds: _misses < 3 ? 1000 : 3000);
    _watchdog = Timer(wait, () {
      _misses++;
      if (_misses == 3 && mounted) setState(() => _fps = 0);
      _request();
    });
  }

  void _scheduleNext() {
    final minGap = Duration(microseconds: (1e6 / widget.maxFps).round());
    final since = DateTime.now().difference(_lastRequest);
    _next?.cancel();
    if (since >= minGap) {
      _request();
    } else {
      _next = Timer(minGap - since, _request);
    }
  }

  void _onChunk(List<Object?> args) {
    if (args.length < 5) return;
    final total = args[2];
    final offset = args[3];
    final chunk = args[4];
    if (total is! int || offset is! int || chunk is! Uint8List) return;
    if (total <= 0 || offset < 0 || offset + chunk.length > total) return;
    if (_rx == null || _rxTotal != total || offset == 0) {
      _rx = Uint8List(total);
      _rxTotal = total;
      _rxGot = 0;
      _rxOffsets.clear();
    }
    if (!_rxOffsets.add(offset)) return;
    _rx!.setRange(offset, offset + chunk.length, chunk);
    _rxGot += chunk.length;
    if (_rxGot < _rxTotal) return;

    // Byte count alone can't tell a whole frame from one with holes (chunks
    // of two in-flight frames with the same size); require SOI..EOI.
    final rx = _rx!;
    _rx = null;
    if (rx.length < 4 ||
        rx[0] != 0xFF || rx[1] != 0xD8 ||
        rx[rx.length - 2] != 0xFF || rx[rx.length - 1] != 0xD9) {
      debugPrint('SendPreview: dropping malformed JPEG ($total bytes)');
      return; // watchdog re-requests
    }

    final now = DateTime.now();
    _frameTimes.add(now);
    _frameTimes.removeWhere((t) => now.difference(t) > const Duration(seconds: 2));
    _misses = 0;
    _watchdog?.cancel();
    if (mounted) {
      setState(() {
        _image = rx;
        _fps = _frameTimes.length > 1
            ? (_frameTimes.length - 1) /
                (now.difference(_frameTimes.first).inMicroseconds / 1e6)
            : 0;
      });
    }
    _scheduleNext();
  }

  void _toggle() {
    setState(() => _running = !_running);
    if (_running) {
      _misses = 0;
      _request();
    } else {
      _watchdog?.cancel();
      _next?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final aspect = widget.width / widget.height;
    final img = _image;
    return AspectRatio(
      aspectRatio: aspect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black,
            child: img == null
                ? Center(
                    child: Text(
                      _misses >= 3 ? 'No preview (needs rev2 hybrid mode)' : 'Waiting for preview…',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  )
                : Image.memory(
                    img,
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stack) => const Center(
                      child: Text('Bad preview frame',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                  ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_running && img != null)
                  Text('${_fps.toStringAsFixed(1)} fps',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  color: Colors.white70,
                  tooltip: _running ? 'Pause preview' : 'Resume preview',
                  icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                  onPressed: _toggle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
