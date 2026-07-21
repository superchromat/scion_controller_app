// color_channels.dart — 8-bit sRGB channel access.

import 'dart:ui' show Color;

/// The 0-255 sRGB channels of a [Color].
///
/// `Color.red` / `.green` / `.blue` are deprecated: Flutter's channels are
/// doubles now, and the wide-gamut migration turned every one of those getters
/// into a rounding decision at the call site. The device speaks 8-bit over OSC,
/// so we make that conversion once, here, instead of scattering
/// `(c.r * 255.0).round().clamp(0, 255)` through the UI.
extension Rgb8 on Color {
  int get r8 => (r * 255.0).round().clamp(0, 255);
  int get g8 => (g * 255.0).round().clamp(0, 255);
  int get b8 => (b * 255.0).round().clamp(0, 255);
}
