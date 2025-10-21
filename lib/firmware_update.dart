import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'labeled_card.dart';
import 'network.dart';
import 'osc_registry.dart';

enum FirmwareStage { idle, ready, uploading, finalizing, done, error }

class FirmwareUpdateSection extends StatefulWidget {
  const FirmwareUpdateSection({super.key});

  @override
  State<FirmwareUpdateSection> createState() => _FirmwareUpdateSectionState();
}

class _FirmwareUpdateSectionState extends State<FirmwareUpdateSection> {
  String? _path;
  String? _fileName;
  int _totalBytes = 0;
  int _sentBytes = 0;
  FirmwareStage _stage = FirmwareStage.idle;
  String? _statusText;
  int _chunkSize = 1024; // default; will be confirmed by ack_begin

  // Ack handling
  Completer<void>? _beginAck;
  Completer<void>? _endAck;
  Completer<void>? _chunkAck;
  int _expectedChunkSeq = -1;

  @override
  void initState() {
    super.initState();
    // Register listeners for firmware acks
    final reg = OscRegistry();
    reg.registerAddress('/firmware/ack_begin');
    reg.registerAddress('/firmware/ack_chunk');
    reg.registerAddress('/firmware/ack_end');
    reg.registerAddress('/firmware/status');
    reg.registerAddress('/firmware/error');
    reg.registerAddress('/error');
    reg.registerListener('/firmware/ack_begin', _onAckBegin);
    reg.registerListener('/firmware/ack_chunk', _onAckChunk);
    reg.registerListener('/firmware/ack_end', _onAckEnd);
    reg.registerListener('/firmware/error', _onErrorMsg);
    reg.registerListener('/error', _onErrorMsg);
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    reg.unregisterListener('/firmware/ack_begin', _onAckBegin);
    reg.unregisterListener('/firmware/ack_chunk', _onAckChunk);
    reg.unregisterListener('/firmware/ack_end', _onAckEnd);
    reg.unregisterListener('/firmware/error', _onErrorMsg);
    reg.unregisterListener('/error', _onErrorMsg);
    super.dispose();
  }

  void _onErrorMsg(List<Object?> args) {
    if (!mounted) return;
    // Only surface errors prominently when we're in an active firmware flow
    if (!(_stage == FirmwareStage.uploading || _stage == FirmwareStage.finalizing)) return;
    final msg = args.isNotEmpty ? args.first?.toString() ?? 'Firmware error' : 'Firmware error';
    setState(() {
      _stage = FirmwareStage.error;
      _statusText = msg;
    });
  }

  void _onAckBegin(List<Object?> args) {
    // Expect: (status:int, chunk_size:int)
    if (_beginAck == null || _beginAck!.isCompleted) return;
    try {
      final status = (args.isNotEmpty ? (args[0] as num).toInt() : -1);
      final chunkSz = (args.length > 1 ? (args[1] as num).toInt() : _chunkSize);
      if (status == 0) {
        _chunkSize = chunkSz;
        _beginAck!.complete();
      } else {
        _beginAck!.completeError('Begin failed (status=$status)');
      }
    } catch (e) {
      _beginAck!.completeError('Bad ack_begin args: $args');
    }
  }

  void _onAckChunk(List<Object?> args) {
    // Expect: (seq:int, status:int)
    if (_chunkAck == null || _chunkAck!.isCompleted) return;
    try {
      final seq = (args.isNotEmpty ? (args[0] as num).toInt() : -1);
      final status = (args.length > 1 ? (args[1] as num).toInt() : -1);
      if (seq == _expectedChunkSeq) {
        if (status == 0) {
          _chunkAck!.complete();
        } else {
          _chunkAck!.completeError('Chunk $seq failed (status=$status)');
        }
      }
    } catch (_) {}
  }

  void _onAckEnd(List<Object?> args) {
    if (_endAck == null || _endAck!.isCompleted) return;
    try {
      final status = (args.isNotEmpty ? (args[0] as num).toInt() : -1);
      if (status == 0) {
        _endAck!.complete();
      } else {
        _endAck!.completeError('End failed (status=$status)');
      }
    } catch (e) {
      _endAck!.completeError('Bad ack_end args: $args');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Firmware Image',
        withData: false,
        type: FileType.any,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final stat = await File(path).stat();
      setState(() {
        _path = path;
        _fileName = path.split(Platform.pathSeparator).last;
        _totalBytes = stat.size;
        _sentBytes = 0;
        _stage = FirmwareStage.ready;
        _statusText = null;
      });
    } catch (e, st) {
      if (kDebugMode) debugPrint('File pick error: $e\n$st');
      setState(() {
        _stage = FirmwareStage.error;
        _statusText = 'File selection failed: $e';
      });
    }
  }

  Future<void> _startUpgrade(BuildContext context) async {
    if (_path == null) return;
    final net = Provider.of<Network>(context, listen: false);
    if (!net.isConnected) {
      setState(() {
        _stage = FirmwareStage.error;
        _statusText = 'Not connected to device';
      });
      return;
    }

    setState(() {
      _stage = FirmwareStage.uploading;
      _sentBytes = 0;
      _statusText = 'Computing SHA-256...';
    });

    late Uint8List bytes;
    try {
      bytes = await File(_path!).readAsBytes();
    } catch (e) {
      setState(() {
        _stage = FirmwareStage.error;
        _statusText = 'Failed to read file: $e';
      });
      return;
    }

    // Compute SHA-256
    final sha = crypto.sha256.convert(bytes).bytes;

    // Send /firmware/begin: (total_size:int, sha256:blob)
    _beginAck = Completer<void>();
    net.sendOscMessage('/firmware/begin', [
      _totalBytes,
      Uint8List.fromList(sha),
    ]);

    try {
      await _beginAck!.future.timeout(const Duration(seconds: 3));
    } catch (e) {
      setState(() {
        if (_stage != FirmwareStage.error) {
          _stage = FirmwareStage.error;
          _statusText = 'Firmware begin failed: $e';
        }
      });
      return;
    }

    // Stream chunks
    final total = _totalBytes;
    int seq = 0;
    for (int offset = 0; offset < total; offset += _chunkSize, seq++) {
      final end = (offset + _chunkSize < total) ? offset + _chunkSize : total;
      final chunk = bytes.sublist(offset, end);
      final crc = _crc32(chunk);

      setState(() {
        _statusText = 'Uploading...';
      });

      _expectedChunkSeq = seq;
      _chunkAck = Completer<void>();
      net.sendOscMessage('/firmware/chunk', [
        seq,
        crc,
        Uint8List.fromList(chunk),
      ]);

      try {
        await _chunkAck!.future.timeout(const Duration(seconds: 2));
      } catch (e) {
        setState(() {
          if (_stage != FirmwareStage.error) {
            _stage = FirmwareStage.error;
            _statusText = 'Chunk $seq not acknowledged: $e';
          }
        });
        return;
      }

      setState(() {
        _sentBytes = end;
      });
    }

    // Finalize
    setState(() {
      _stage = FirmwareStage.finalizing;
      _statusText = 'Finalizing...';
    });
    _endAck = Completer<void>();
    net.sendOscMessage('/firmware/end', []);
    try {
      await _endAck!.future.timeout(const Duration(seconds: 3));
      setState(() {
        _stage = FirmwareStage.finalizing;
        _statusText = 'Upgrade initiated. Device will reboot...';
      });
      // Suppress disconnect due to inactivity while we await device reboot
      net.suppressTimeoutsFor(const Duration(seconds: 90));
      // Wait for first /ack after this point to consider reconnect successful
      await _awaitRebootAndReport(context, net, timeout: const Duration(seconds: 90));
    } catch (e) {
      setState(() {
        if (_stage != FirmwareStage.error) {
          _stage = FirmwareStage.error;
          _statusText = 'Finalize failed: $e';
        }
      });
    }
  }

  Future<void> _awaitRebootAndReport(BuildContext context, Network net,
      {required Duration timeout}) async {
    final start = DateTime.now();
    final completer = Completer<bool>();
    void listener() {
      final t = net.lastAckTime;
      if (t != null && t.isAfter(start) && !completer.isCompleted) {
        completer.complete(true);
      }
    }
    net.addListener(listener);
    Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });

    final ok = await completer.future;
    net.removeListener(listener);

    if (!mounted) return;
    if (ok) {
      setState(() {
        _stage = FirmwareStage.done;
        _statusText = 'Device reconnected after upgrade';
      });
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Firmware Upgrade'),
          content: const Text('Upgrade completed and device is back online.'
              ' If this was a test upgrade, remember to confirm it.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      setState(() {
        _stage = FirmwareStage.error;
        _statusText = 'Device did not reconnect after upgrade';
      });
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Firmware Upgrade Failed'),
          content: const Text('The device did not reconnect within the configured window. The upgrade likely failed or the device is taking longer to reboot.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // CRC32 (IEEE) implementation
  static const int _crc32Polynomial = 0xEDB88320;
  static List<int>? _crcTable;

  static void _ensureCrcTable() {
    if (_crcTable != null) return;
    _crcTable = List<int>.filled(256, 0);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int k = 0; k < 8; k++) {
        if ((c & 1) != 0) {
          c = _crc32Polynomial ^ (c >> 1);
        } else {
          c = c >> 1;
        }
      }
      _crcTable![n] = c;
    }
  }

  static int _crc32(List<int> data) {
    _ensureCrcTable();
    int c = 0xFFFFFFFF;
    for (final b in data) {
      c = _crcTable![(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) >>> 0;
  }

  @override
  Widget build(BuildContext context) {
    final net = Provider.of<Network>(context);
    final connected = net.isConnected;
    final progress = _totalBytes == 0 ? 0.0 : _sentBytes / _totalBytes;

    return LabeledCard(
      title: 'Firmware Update',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _stage == FirmwareStage.uploading
                    ? null
                    : () => _pickFile(),
                icon: const Icon(Icons.file_open),
                label: const Text('Select Firmware'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: (_path != null && connected &&
                        (_stage == FirmwareStage.ready ||
                            _stage == FirmwareStage.error))
                    ? () => _startUpgrade(context)
                    : null,
                icon: const Icon(Icons.system_update_alt),
                label: const Text('Begin Upgrade'),
              ),
              const SizedBox(width: 12),
              if (_fileName != null)
                Text(
                  _fileName!,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (_stage == FirmwareStage.uploading ||
                    _stage == FirmwareStage.finalizing ||
                    _stage == FirmwareStage.done)
                ? progress.clamp(0.0, 1.0)
                : 0.0,
            minHeight: 8,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _statusText ??
                    (_stage == FirmwareStage.uploading
                        ? 'Uploading...'
                        : _stage == FirmwareStage.finalizing
                            ? 'Finalizing...'
                            : _stage == FirmwareStage.done
                                ? 'Done'
                                : connected
                                    ? 'Ready'
                                    : 'Not connected'),
              ),
              if (_totalBytes > 0)
                Text('${_sentBytes}/${_totalBytes} bytes'
                    ' (${(progress * 100).toStringAsFixed(1)}%)'),
            ],
          ),
        ],
      ),
    );
  }
}
