// Flattens the icon master onto opaque black and strips the alpha channel, so
// flutter_launcher_icons never has to run its iOS alpha-removal path (which
// draws a stray guide onto the artwork).
import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final src = args.isNotEmpty ? args[0] : 'assets/icon/app_icon_src.png';
  final dst = args.length > 1 ? args[1] : 'assets/icon/app_icon.png';

  final bytes = File(src).readAsBytesSync();
  final decoded = img.decodePng(bytes);
  if (decoded == null) {
    stderr.writeln('could not decode $src');
    exit(1);
  }

  int minA = 255;
  for (final p in decoded) {
    if (p.a < minA) minA = p.a.toInt();
  }

  final flat = img.Image(width: decoded.width, height: decoded.height, numChannels: 3);
  img.fill(flat, color: img.ColorRgb8(0, 0, 0));
  img.compositeImage(flat, decoded);

  File(dst).writeAsBytesSync(img.encodePng(flat));
  stdout.writeln('min alpha in source: $minA  ->  wrote opaque $dst '
      '(${flat.width}x${flat.height}, ${flat.numChannels} channels)');
}
