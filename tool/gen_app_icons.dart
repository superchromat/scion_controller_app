// Regenerates app-icon PNGs from a 1024x1024 master.
//
// The SCION wordmark (white) is centred on a black field. iOS/Android outputs
// are flattened onto opaque black (no alpha — the App Store rejects a
// marketing icon with alpha, and Android launcher bitmaps want none). macOS
// keeps alpha because its master is a rounded-square panel with transparent
// margins (macOS does not auto-mask app icons).
//
// Usage:
//   dart run tool/gen_app_icons.dart ios     tool/app_icon_master.svg.png
//   dart run tool/gen_app_icons.dart macos   tool/app_icon_macos_master.svg.png
//   dart run tool/gen_app_icons.dart android tool/app_icon_master.svg.png
import 'dart:io';
import 'package:image/image.dart' as img;

// filename -> pixel size, relative to the platform's asset directory.
const _ios = <String, int>{
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

const _macos = <String, int>{
  'app_icon_16.png': 16,
  'app_icon_32.png': 32,
  'app_icon_64.png': 64,
  'app_icon_128.png': 128,
  'app_icon_256.png': 256,
  'app_icon_512.png': 512,
  'app_icon_1024.png': 1024,
};

// Android: one ic_launcher.png per density directory.
const _android = <String, int>{
  'mipmap-mdpi/ic_launcher.png': 48,
  'mipmap-hdpi/ic_launcher.png': 72,
  'mipmap-xhdpi/ic_launcher.png': 96,
  'mipmap-xxhdpi/ic_launcher.png': 144,
  'mipmap-xxxhdpi/ic_launcher.png': 192,
};

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Usage: dart run tool/gen_app_icons.dart <ios|macos|android> <master.png>');
    exit(64);
  }
  final set = args[0];
  final master = img.decodePng(File(args[1]).readAsBytesSync());
  if (master == null) {
    stderr.writeln('Could not decode master: ${args[1]}');
    exit(1);
  }

  late final String dir;
  late final Map<String, int> icons;
  late final bool keepAlpha;
  switch (set) {
    case 'ios':
      dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      icons = _ios;
      keepAlpha = false;
    case 'macos':
      dir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      icons = _macos;
      keepAlpha = true;
    case 'android':
      dir = 'android/app/src/main/res';
      icons = _android;
      keepAlpha = false;
    default:
      stderr.writeln('Unknown set: $set (expected ios|macos|android)');
      exit(64);
  }

  icons.forEach((name, px) {
    final resized = img.copyResize(
      master,
      width: px,
      height: px,
      interpolation: img.Interpolation.average,
    );
    final img.Image out;
    if (keepAlpha) {
      out = resized;
    } else {
      // Flatten onto opaque black -> RGB (no alpha).
      out = img.Image(width: px, height: px, numChannels: 3);
      img.fill(out, color: img.ColorRgb8(0, 0, 0));
      img.compositeImage(out, resized);
    }
    File('$dir/$name').writeAsBytesSync(img.encodePng(out));
    stdout.writeln('wrote $dir/$name (${px}x$px)');
  });
}
