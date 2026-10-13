// Builds the macOS app-icon master: the artwork inset on Apple's icon grid,
// with rounded corners and transparent margins baked into the pixels.
//
// macOS does not mask app icons. iOS clips whatever you give it to the system
// shape; macOS draws your bitmap verbatim, so a full-bleed square ships as a
// full-bleed square and sits in the Dock looking nothing like its neighbours.
// The rounding and the margin have to BE in the artwork.
//
// This is easy to get wrong locally: macOS 26 auto-masks legacy icons, so a
// square icon looks correctly rounded on a current Mac and raw on every older
// one. Trust `sips -g hasAlpha` on the generated PNGs, not the Dock.
//
// Geometry is Apple's 1024 grid, and matches tool/app_icon_macos_master.svg —
// which is the reference for these numbers, not the artwork itself (that SVG
// still holds the older plain-wordmark design, superseded by sc_app_icon.tiff).
//
// Usage:
//   dart run tool/macos_icon_master.dart
//     -> tool/app_icon_macos_master.png   (1024x1024, alpha, intermediate)
//   dart run tool/gen_app_icons.dart macos tool/app_icon_macos_master.png
//     -> macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Full canvas. The largest macOS slot is 1024, so the body is rasterised once
/// here at full size and only ever downsampled afterwards.
const int kCanvas = 1024;

/// The icon body, centred — 100px of transparent margin on every side.
const int kBody = 824;

/// Corner radius of the body, from app_icon_macos_master.svg's `rx`.
const double kRadius = 185;

void main(List<String> args) {
  final src = args.isNotEmpty ? args[0] : 'sc_app_icon.tiff';
  final dst = args.length > 1 ? args[1] : 'tool/app_icon_macos_master.png';

  final decoded = img.decodeImage(File(src).readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('could not decode $src');
    exit(1);
  }
  if (decoded.width != decoded.height) {
    stderr.writeln('$src is ${decoded.width}x${decoded.height}; '
        'the icon master must be square');
    exit(1);
  }

  final scaled = img.copyResize(
    decoded,
    width: kBody,
    height: kBody,
    interpolation: img.Interpolation.cubic,
  );

  // Flatten onto black first. The master may carry alpha of its own, and the
  // macOS body has to read as one solid panel — otherwise the corner mask below
  // is competing with holes in the artwork.
  final body = img.Image(width: kBody, height: kBody, numChannels: 3);
  img.fill(body, color: img.ColorRgb8(0, 0, 0));
  img.compositeImage(body, scaled);

  final out = img.Image(width: kCanvas, height: kCanvas, numChannels: 4);

  // Signed distance to a rounded rectangle, evaluated at each pixel centre.
  // Cheaper and sharper than supersampling, and the 1px coverage ramp it gives
  // is what keeps the corners from stair-stepping at the 16px slot.
  const half = kBody / 2.0;
  const inner = half - kRadius;
  const origin = (kCanvas - kBody) ~/ 2;

  for (var y = 0; y < kBody; y++) {
    for (var x = 0; x < kBody; x++) {
      final qx = (x + 0.5 - half).abs() - inner;
      final qy = (y + 0.5 - half).abs() - inner;
      final ox = math.max(qx, 0.0);
      final oy = math.max(qy, 0.0);
      final d = math.sqrt(ox * ox + oy * oy) +
          math.min(math.max(qx, qy), 0.0) -
          kRadius;

      final coverage = (0.5 - d).clamp(0.0, 1.0);
      if (coverage <= 0) continue;

      final p = body.getPixel(x, y);
      out.setPixelRgba(
        origin + x,
        origin + y,
        p.r.toInt(),
        p.g.toInt(),
        p.b.toInt(),
        (coverage * 255).round(),
      );
    }
  }

  File(dst).writeAsBytesSync(img.encodePng(out));
  stdout.writeln('$src (${decoded.width}x${decoded.height})  ->  $dst '
      '(${kCanvas}x$kCanvas, ${kBody}px body, r$kRadius, alpha)');
}
