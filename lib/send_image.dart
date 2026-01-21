// send_image.dart
// Image overlay upload for MFC OSD

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:archive/archive.dart' show getCrc32;
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'osc_registry.dart';
import 'network.dart';

/// Image upload widget that streams 24-bit RGB via OSC
class SendImage extends StatefulWidget {
  const SendImage({super.key});

  @override
  State<SendImage> createState() => _SendImageState();
}

class _SendImageState extends State<SendImage> {
  img.Image? _loadedImage;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _statusMessage = 'No image loaded';
  bool _imageEnabled = false;
  String _basePath = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve the OSC path from widget tree
    final segs = OscPathSegment.resolvePath(context);
    _basePath = segs.isEmpty ? '' : '/${segs.join('/')}';
  }

  Future<void> _pickAndLoadImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    // On desktop, bytes may be null - read from path instead
    Uint8List bytes;
    final file = result.files.first;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      try {
        bytes = await File(file.path!).readAsBytes();
      } catch (e) {
        setState(() => _statusMessage = 'Failed to read file: $e');
        return;
      }
    } else {
      setState(() => _statusMessage = 'Failed to read file');
      return;
    }

    setState(() => _statusMessage = 'Decoding image...');

    // Decode image
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      setState(() => _statusMessage = 'Failed to decode image');
      return;
    }

    // Limit size - firmware uses 1024-byte padded row pitch (256 pixels max width)
    // Height limit based on available RAM buffer in firmware (~25KB)
    const maxWidth = 64;
    const maxHeight = 100;
    img.Image resized;
    if (decoded.width > maxWidth || decoded.height > maxHeight) {
      final scaleW = decoded.width / maxWidth;
      final scaleH = decoded.height / maxHeight;
      final scale = scaleW > scaleH ? scaleW : scaleH;
      final newWidth = (decoded.width / scale).round();
      final newHeight = (decoded.height / scale).round();
      resized = img.copyResize(decoded, width: newWidth, height: newHeight);
      setState(() => _statusMessage = 'Resized to ${newWidth}x$newHeight');
    } else {
      resized = decoded;
    }

    setState(() {
      _loadedImage = resized;
      _statusMessage = 'Ready to upload (${resized.width}x${resized.height})';
    });
  }

  Future<void> _uploadImage() async {
    if (_loadedImage == null) {
      setState(() => _statusMessage = 'No image to upload');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _statusMessage = 'Starting upload...';
    });

    final network = context.read<Network>();
    final image = _loadedImage!;
    final width = image.width;
    final height = image.height;

    // Send begin message (just dimensions, no palette for 24-bit)
    final beginArgs = <Object>[width, height];
    network.sendOscMessage('$_basePath/image/begin', beginArgs);

    // Wait for firmware to process begin and allocate DDR
    await Future.delayed(const Duration(milliseconds: 500));

    // Bytes per row = width * 4 (ARGB)
    final bytesPerRow = width * 4;

    // Setup ACK listener
    final rowPath = '$_basePath/image/row';
    final registry = OscRegistry();
    registry.registerAddress(rowPath);

    int? receivedAck;
    void ackListener(List<Object?> args) {
      if (args.isNotEmpty && args.first is int) {
        receivedAck = args.first as int;
      }
    }
    registry.registerListener(rowPath, ackListener);

    bool uploadFailed = false;
    // Increased retries and timeout for vsync-gated DDR transfers
    // Firmware buffers ~16 rows, then flushes to DDR during vsync (~16ms per frame)
    // May need multiple vsyncs to flush, so allow more time
    const maxRetries = 10;
    const ackTimeout = Duration(milliseconds: 200);
    const retryDelay = Duration(milliseconds: 50);  // Wait between retries for vsync flush

    // CRC32 accumulator - calculate as we build rows
    int crc = 0;

    try {
      // Send rows and wait for ACK after each
      for (int y = 0; y < height && !uploadFailed; y++) {
        // Extract row pixels as 32-bit aRGB5888 for MDIN DDR format
        // MDIN expects big-endian aRGB5888: [A5_pad, R, G, B]
        // Alpha is 5-bit (bits 31-27), so we use upper 5 bits: (a >> 3) << 3
        final rowData = Uint8List(bytesPerRow);
        for (int x = 0; x < width; x++) {
          final pixel = image.getPixel(x, y);
          final offset = x * 4;
          final a5 = (pixel.a.toInt() >> 3) << 3;  // 5-bit alpha in upper bits
          rowData[offset + 0] = a5;                 // Alpha (5-bit) + padding
          rowData[offset + 1] = pixel.r.toInt();   // R
          rowData[offset + 2] = pixel.g.toInt();   // G
          rowData[offset + 3] = pixel.b.toInt();   // B
        }

        // Update CRC with this row's data
        crc = getCrc32(rowData, crc);

        // Per-row CRC to compare with firmware
        if (y < 5 || y == height - 1) {
          final rowCrc = getCrc32(rowData);
          debugPrint('Row $y CRC=0x${rowCrc.toRadixString(16).toUpperCase().padLeft(8, '0')} (len=$bytesPerRow)');
        }

        // Retry loop for this row
        bool rowAcked = false;
        for (int attempt = 0; attempt < maxRetries && !rowAcked; attempt++) {
          // Clear previous ACK
          receivedAck = null;

          // Send row
          final rowArgs = <Object>[y, rowData];
          network.sendOscMessage(rowPath, rowArgs);

          // Poll for ACK with timeout
          final deadline = DateTime.now().add(ackTimeout);
          while (DateTime.now().isBefore(deadline)) {
            await Future.delayed(const Duration(milliseconds: 5));
            if (receivedAck == y) {
              rowAcked = true;
              break;
            }
          }

          if (!rowAcked && attempt < maxRetries - 1) {
            // Wait for firmware to flush buffer during vsync before retry
            await Future.delayed(retryDelay);
            if (attempt >= 2) {
              setState(() => _statusMessage = 'Row $y: waiting for buffer flush (attempt ${attempt + 2})');
            }
          }
        }

        if (!rowAcked) {
          setState(() => _statusMessage = 'Failed row $y after $maxRetries attempts - aborting');
          uploadFailed = true;
          break;
        }

        // Update UI periodically
        if (y % 50 == 0 || y == height - 1) {
          setState(() {
            _uploadProgress = (y + 1) / height;
            _statusMessage = 'Uploading row ${y + 1}/$height';
          });
        }
      }
    } finally {
      // Cleanup listener
      registry.unregisterListener(rowPath, ackListener);
    }

    if (uploadFailed) {
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
      });
      return;
    }

    // Print CRC for comparison with firmware
    debugPrint('Client CRC32 = 0x${crc.toRadixString(16).toUpperCase().padLeft(8, '0')} ($height rows x $bytesPerRow bytes)');

    // Small delay before end
    await Future.delayed(const Duration(milliseconds: 100));

    // Send end message
    network.sendOscMessage('$_basePath/image/end', <Object>[]);

    setState(() {
      _isUploading = false;
      _uploadProgress = 1.0;
      _statusMessage = 'Upload complete!';
      _imageEnabled = true;
    });

    // Enable the image
    network.sendOscMessage('$_basePath/image/enable', <Object>[true]);
  }

  void _toggleEnable() {
    final network = context.read<Network>();
    setState(() => _imageEnabled = !_imageEnabled);
    network.sendOscMessage('$_basePath/image/enable', <Object>[_imageEnabled]);
  }

  Widget _buildPreview() {
    if (_loadedImage == null) {
      return Container(
        width: 200,
        height: 150,
        color: Colors.black26,
        child: const Center(child: Text('No image')),
      );
    }

    // Convert image to display
    final displayImg = img.encodePng(_loadedImage!);
    return Image.memory(
      Uint8List.fromList(displayImg),
      width: 200,
      fit: BoxFit.contain,
    );
  }

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'image',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preview and controls row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview
              Column(
                children: [
                  _buildPreview(),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _pickAndLoadImage,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Load Image'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: (_isUploading || _loadedImage == null)
                        ? null
                        : _uploadImage,
                    icon: const Icon(Icons.upload, size: 16),
                    label: const Text('Upload'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _toggleEnable,
                    icon: Icon(
                      _imageEnabled ? Icons.visibility : Icons.visibility_off,
                      size: 16,
                    ),
                    label: Text(_imageEnabled ? 'Hide' : 'Show'),
                  ),
                ],
              ),
            ],
          ),
          // Progress bar
          if (_isUploading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _uploadProgress),
          ],
          const SizedBox(height: 16),
          // Position controls
          Row(
            children: [
              const SizedBox(width: 70, child: Text('Position')),
              OscPathSegment(
                segment: 'pos',
                child: Row(
                  children: [
                    OscPathSegment(
                      segment: 'x',
                      child: OscRotaryKnob(
                        label: 'X',
                        minValue: 0,
                        maxValue: 3840,
                        initialValue: 100,
                        defaultValue: 100,
                        format: '%.0f',
                        size: 60,
                        preferInteger: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OscPathSegment(
                      segment: 'y',
                      child: OscRotaryKnob(
                        label: 'Y',
                        minValue: 0,
                        maxValue: 2160,
                        initialValue: 100,
                        defaultValue: 100,
                        format: '%.0f',
                        size: 60,
                        preferInteger: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
