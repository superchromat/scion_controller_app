// Flattens the icon master onto opaque black and strips the alpha channel, so
// flutter_launcher_icons never has to run its iOS alpha-removal path (which
// draws a stray guide onto the artwork).
//
// The master is sc_app_icon.tiff at the repo root. It is decoded
// format-agnostically, so swapping the master for a PNG later needs no change
// here — but keep ONE master file, or the platforms drift apart again.
import 'dart:io';
import 'package:image/image.dart' as img;

/// Every platform slot is generated from the flattened output, and the largest
/// slot (macOS) is 1024 — so master at exactly 1024 and that slot is a straight
/// copy rather than a resample.
const int kMasterSize = 1024;

void main(List<String> args) {
  final src = args.isNotEmpty ? args[0] : 'sc_app_icon.tiff';
  final dst = args.length > 1 ? args[1] : 'assets/icon/app_icon.png';

  final bytes = File(src).readAsBytesSync();
  // decodeImage sniffs the container, so the master can be TIFF, PNG, ...
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    stderr.writeln('could not decode $src');
    exit(1);
  }
  if (decoded.width != decoded.height) {
    stderr.writeln('$src is ${decoded.width}x${decoded.height}; '
        'the icon master must be square');
    exit(1);
  }

  int minA = 255;
  for (final p in decoded) {
    if (p.a < minA) minA = p.a.toInt();
  }

  final scaled = decoded.width == kMasterSize
      ? decoded
      : img.copyResize(
          decoded,
          width: kMasterSize,
          height: kMasterSize,
          interpolation: img.Interpolation.cubic,
        );

  final flat =
      img.Image(width: scaled.width, height: scaled.height, numChannels: 3);
  img.fill(flat, color: img.ColorRgb8(0, 0, 0));
  img.compositeImage(flat, scaled);

  File(dst).writeAsBytesSync(img.encodePng(flat));
  stdout.writeln('$src (${decoded.width}x${decoded.height}, min alpha $minA)  '
      '->  opaque $dst (${flat.width}x${flat.height}, '
      '${flat.numChannels} channels)');
}
