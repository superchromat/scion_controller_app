import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'labeled_card.dart';
import 'app_button.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'grid.dart';

enum FirmwareStage { idle, uploading, finalizing, done, error }

/// Firmware Update card for the Setup page.
///
/// Shows the device's current firmware version and a single "Firmware Update"
/// button. Pressing it opens a file picker; the chosen file is validated
/// locally as an MCUboot image (header magic) before anything is sent. An
/// invalid file raises a modal alert and nothing is uploaded. A valid file
/// starts the upload immediately, replacing the button with a progress bar.
/// On completion the device reboots to apply the image and a confirmation
/// dialog is shown.
class FirmwareUpdateSection extends StatefulWidget {
  const FirmwareUpdateSection({super.key});

  @override
  State<FirmwareUpdateSection> createState() => _FirmwareUpdateSectionState();
}

class _FirmwareUpdateSectionState extends State<FirmwareUpdateSection> {
  static const _oscFwVersion = '/device/fw_version';

  /// MCUboot image header magic (`IMAGE_MAGIC`), stored little-endian at the
  /// very start of a signed image. Header is 32 bytes.
  static const int _mcubootMagic = 0x96f3b83d;
  static const int _mcubootHeaderBytes = 32;

  String? _path;
  String? _fileName;
  int _totalBytes = 0;
  int _sentBytes = 0;
  FirmwareStage _stage = FirmwareStage.idle;
  int _chunkSize = 1024; // default; will be confirmed by ack_begin

  String? _fwVersion;
  Network? _net;
  bool _wasConnected = false;

  // Ack handling
  Completer<void>? _beginAck;
  Completer<void>? _endAck;
  Completer<void>? _chunkAck;
  int _expectedChunkSeq = -1;

  // Fixed dimensions for the control region so the card never resizes between
  // stages (button ↔ progress bar).
  static const double _kFileLineHeight = 20;
  static const double _kBarHeight = 18; // 12px bar + 2×3px inset padding
  static const double _kControlRegionHeight =
      _kFileLineHeight + 8 + _kBarHeight;

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress('/firmware/ack_begin');
    reg.registerAddress('/firmware/ack_chunk');
    reg.registerAddress('/firmware/ack_end');
    reg.registerAddress('/firmware/status');
    reg.registerAddress('/firmware/error');
    reg.registerAddress('/error');
    reg.registerAddress(_oscFwVersion);
    reg.registerListener('/firmware/ack_begin', _onAckBegin);
    reg.registerListener('/firmware/ack_chunk', _onAckChunk);
    reg.registerListener('/firmware/ack_end', _onAckEnd);
    reg.registerListener('/firmware/error', _onErrorMsg);
    reg.registerListener('/error', _onErrorMsg);
    reg.registerListener(_oscFwVersion, _onFwVersion);

    final args = reg.allParams[_oscFwVersion]?.currentValue;
    if (args != null && args.isNotEmpty) _onFwVersion(List<Object?>.from(args));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final net = context.read<Network>();
    if (!identical(_net, net)) {
      _net?.removeListener(_onNet);
      _net = net;
      _wasConnected = net.isConnected;
      _net!.addListener(_onNet);
    }
  }

  @override
  void dispose() {
    _net?.removeListener(_onNet);
    final reg = OscRegistry();
    reg.unregisterListener('/firmware/ack_begin', _onAckBegin);
    reg.unregisterListener('/firmware/ack_chunk', _onAckChunk);
    reg.unregisterListener('/firmware/ack_end', _onAckEnd);
    reg.unregisterListener('/firmware/error', _onErrorMsg);
    reg.unregisterListener('/error', _onErrorMsg);
    reg.unregisterListener(_oscFwVersion, _onFwVersion);
    super.dispose();
  }

  // fw_version isn't always part of /sync, so pull it the moment the link
  // comes up — otherwise a page opened after connect would show "—".
  void _onNet() {
    final connected = _net?.isConnected ?? false;
    if (connected && !_wasConnected) {
      _net?.sendOscMessage(_oscFwVersion, const []);
    }
    _wasConnected = connected;
  }

  void _onFwVersion(List<Object?> args) {
    if (!mounted || args.isEmpty) return;
    final v = args.first?.toString().trim();
    setState(() => _fwVersion = (v == null || v.isEmpty) ? null : v);
  }

  void _onErrorMsg(List<Object?> args) {
    if (!mounted) return;
    // Only surface errors prominently when we're in an active firmware flow
    if (!(_stage == FirmwareStage.uploading ||
        _stage == FirmwareStage.finalizing)) {
      return;
    }
    final msg = args.isNotEmpty
        ? args.first?.toString() ?? 'Firmware error'
        : 'Firmware error';
    // Break any in-flight await so the upload stops promptly, then alert.
    _failPendingCompleters(msg);
    _fail(msg);
  }

  /// Move to the error state and raise a modal alert. Every firmware failure —
  /// device-reported (e.g. "invalid MCUBoot header"), transport, or local —
  /// funnels through here. Guards against stacking a second dialog when one
  /// failure has already been reported for this attempt.
  void _fail(String message) {
    if (!mounted) return;
    final alreadyError = _stage == FirmwareStage.error;
    setState(() {
      _stage = FirmwareStage.error;
    });
    if (!alreadyError) _showErrorDialog(message);
  }

  Future<void> _showErrorDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Firmware Update Error'),
        content: Text(message),
        actions: [
          AppButton(
            label: 'OK',
            dense: true,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
    // Return to idle so the button comes back for another attempt.
    if (mounted && _stage == FirmwareStage.error) {
      setState(() => _stage = FirmwareStage.idle);
    }
  }

  Future<void> _showRebootDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Firmware Update'),
        content: const Text(
          'The firmware was uploaded successfully. The device is now '
          'rebooting to apply the update.',
        ),
        actions: [
          AppButton(
            label: 'OK',
            dense: true,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  void _failPendingCompleters(Object error) {
    if (_beginAck != null && !_beginAck!.isCompleted) {
      _beginAck!.completeError(error);
    }
    if (_chunkAck != null && !_chunkAck!.isCompleted) {
      _chunkAck!.completeError(error);
    }
    if (_endAck != null && !_endAck!.isCompleted) _endAck!.completeError(error);
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

  /// Open the picker, locally validate the choice as an MCUboot image, and —
  /// if valid — start the upload immediately. Invalid files raise an alert and
  /// nothing is sent.
  Future<void> _pickAndStart() async {
    final path = await _pickFile();
    if (path == null) return; // user cancelled

    final valid = await _isValidMcubootImage(path);
    if (!mounted) return;
    if (!valid) {
      await _showErrorDialog(
        'The selected file is not a valid SCION firmware image '
        '(missing MCUboot header).',
      );
      return;
    }

    final stat = await File(path).stat();
    if (!mounted) return;
    setState(() {
      _path = path;
      _fileName = path.split(Platform.pathSeparator).last;
      _totalBytes = stat.size;
      _sentBytes = 0;
    });
    await _startUpgrade();
  }

  /// Returns the chosen file path, or null if the user cancelled / it failed.
  Future<String?> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Firmware Image',
        withData: false,
        type: FileType.any,
      );
      return result?.files.single.path;
    } catch (e, st) {
      if (kDebugMode) debugPrint('File pick error: $e\n$st');
      await _showErrorDialog('File selection failed: $e');
      return null;
    }
  }

  /// Validate the file as an MCUboot image: at least a full header, with the
  /// little-endian magic `0x96f3b83d` at offset 0.
  Future<bool> _isValidMcubootImage(String path) async {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      if (await file.length() < _mcubootHeaderBytes) return false;
      raf = await file.open();
      final head = await raf.read(4);
      if (head.length < 4) return false;
      final magic =
          (head[0] | (head[1] << 8) | (head[2] << 16) | (head[3] << 24)) &
              0xFFFFFFFF;
      return magic == _mcubootMagic;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Firmware validation error: $e\n$st');
      return false;
    } finally {
      await raf?.close();
    }
  }

  Future<void> _startUpgrade() async {
    if (_path == null) return;
    final net = Provider.of<Network>(context, listen: false);
    if (!net.isConnected) {
      _fail('Not connected to device');
      return;
    }

    setState(() {
      _stage = FirmwareStage.uploading;
      _sentBytes = 0;
    });

    late Uint8List bytes;
    try {
      bytes = await File(_path!).readAsBytes();
    } catch (e) {
      _fail('Failed to read file: $e');
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
      _fail('Firmware begin failed: $e');
      return;
    }

    // Stream chunks
    final total = _totalBytes;
    int seq = 0;
    for (int offset = 0; offset < total; offset += _chunkSize, seq++) {
      final end = (offset + _chunkSize < total) ? offset + _chunkSize : total;
      final chunk = bytes.sublist(offset, end);
      final crc = _crc32(chunk);

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
        _fail('Chunk $seq not acknowledged: $e');
        return;
      }

      setState(() {
        _sentBytes = end;
      });
    }

    // Finalize
    setState(() {
      _stage = FirmwareStage.finalizing;
    });
    _endAck = Completer<void>();
    net.sendOscMessage('/firmware/end', []);
    try {
      await _endAck!.future.timeout(const Duration(seconds: 3));
    } catch (e) {
      _fail('Finalize failed: $e');
      return;
    }

    // Upload accepted — the device now reboots to apply the image. Suppress
    // the inactivity-disconnect overlay during the reboot window and tell the
    // user what's happening.
    net.suppressTimeoutsFor(const Duration(seconds: 90));
    if (!mounted) return;
    setState(() => _stage = FirmwareStage.done);
    await _showRebootDialog();
    if (mounted) {
      setState(() {
        _stage = FirmwareStage.idle;
        _fileName = null;
        _path = null;
        _sentBytes = 0;
        _totalBytes = 0;
      });
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

  bool get _showBar =>
      _stage == FirmwareStage.uploading ||
      _stage == FirmwareStage.finalizing ||
      _stage == FirmwareStage.done;

  Widget _versionRow(GridTokens? t) {
    final labelStyle =
        t?.textCaption ?? const TextStyle(fontSize: 11, letterSpacing: 0.5);
    final valueStyle = TextStyle(
      fontFamily: 'Courier',
      fontFamilyFallback: const ['Courier New', 'monospace'],
      fontSize: (t != null ? (t.u * 1.15).clamp(13.0, 17.0) : 15.0),
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: const Color(0xFFE9E9EC),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('FIRMWARE', style: labelStyle),
        SizedBox(width: t?.sm ?? 8),
        Expanded(
          child: Text(
            _fwVersion ?? '—',
            style: valueStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final net = Provider.of<Network>(context);
    final connected = net.isConnected;
    final progress = _totalBytes == 0 ? 0.0 : _sentBytes / _totalBytes;
    final t = GridProvider.maybeOf(context);

    return LabeledCard(
      title: 'Firmware Update',
      fillChild: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          GridProvider.of(context).cardBodyInset,
          t?.xs ?? 8,
          t?.md ?? 16,
          t?.md ?? 16,
        ),
        child: Column(
          // Centre content vertically — the card shares Network Setup's
          // height with Front Panel.
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            _versionRow(t),
            SizedBox(height: t?.md ?? 12),
            // Fixed-height region so the card doesn't jump as we swap the
            // button for the progress bar.
            SizedBox(
              height: _kControlRegionHeight,
              child: _showBar
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: _kFileLineHeight,
                          child: _fileName == null
                              ? null
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _fileName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontStyle: FontStyle.italic),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: _kBarHeight,
                          child: _StyledProgressBar(
                              value: progress.clamp(0.0, 1.0)),
                        ),
                      ],
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: 'Firmware Update',
                        onPressed: connected ? _pickAndStart : null,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Neumorphic determinate progress bar: an inset track with a solid,
/// hard-edged accent fill that eases toward the target as chunks ack.
class _StyledProgressBar extends StatelessWidget {
  final double value;
  const _StyledProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      borderRadius: 4,
      depth: 2,
      padding: const EdgeInsets.all(3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 12,
          width: double.infinity,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            builder: (context, v, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v <= 0 ? 0.0 : v,
              heightFactor: 1.0,
              child: const ColoredBox(color: Color(0xFFFFC400)),
            ),
          ),
        ),
      ),
    );
  }
}
