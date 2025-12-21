import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Global lighting settings provider for consistent neumorphic styling across the app.
///
/// Provides:
/// - Light direction (theta/phi angles)
/// - Shared noise texture image
/// - Helper methods for computing gradients and edge lighting
class LightingSettings extends ChangeNotifier {
  /// Azimuthal angle in radians (0 = right, pi/2 = top)
  double _lightPhi = math.pi / 2;

  /// Polar angle in radians
  double _lightTheta = 320 * math.pi / 180;

  /// Shared noise texture
  ui.Image? _noiseImage;
  bool _noiseImageLoading = false;

  LightingSettings() {
    _generateNoiseImage();
  }

  double get lightPhi => _lightPhi;
  double get lightTheta => _lightTheta;
  ui.Image? get noiseImage => _noiseImage;

  /// Light phi in degrees for UI display
  double get lightPhiDegrees => _lightPhi * 180 / math.pi;

  /// Light theta in degrees for UI display
  double get lightThetaDegrees => _lightTheta * 180 / math.pi;

  void setLightPhi(double radians) {
    _lightPhi = radians;
    notifyListeners();
  }

  void setLightTheta(double radians) {
    _lightTheta = radians;
    notifyListeners();
  }

  void setLightPhiDegrees(double degrees) {
    _lightPhi = degrees * math.pi / 180;
    notifyListeners();
  }

  void setLightThetaDegrees(double degrees) {
    _lightTheta = degrees * math.pi / 180;
    notifyListeners();
  }

  /// Compute 2D light direction from spherical coordinates
  /// Returns (Lx, Ly) where positive Ly is down (screen coords)
  Offset get lightDir2D {
    final lx = math.sin(_lightTheta) * math.cos(_lightPhi);
    final ly = -math.sin(_lightTheta) * math.sin(_lightPhi);
    return Offset(lx, ly);
  }

  /// Compute edge brightness from normal direction
  double edgeBrightness(Offset normal) {
    final light = lightDir2D;
    final dot = normal.dx * light.dx + normal.dy * light.dy;
    return dot.clamp(0.0, 1.0);
  }

  Future<void> _generateNoiseImage() async {
    if (_noiseImage != null || _noiseImageLoading) return;
    _noiseImageLoading = true;

    const size = 256;
    final random = math.Random(12345);

    // Create raw greyscale noise values
    final rawNoise = Uint8List(size * size);
    for (int i = 0; i < size * size; i++) {
      rawNoise[i] = 128 + random.nextInt(20);
    }

    // Apply 3x3 convolution: [[1,1,1],[1,8,1],[1,1,1]] / 16
    // This is a mild blur that preserves detail while softening harsh edges
    final blurredNoise = Uint8List(size * size);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        int sum = 0;
        // Sample 3x3 neighborhood with wrap-around for seamless tiling
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = (x + dx) % size;
            final ny = (y + dy) % size;
            final weight = (dx == 0 && dy == 0) ? 4 : 1;
            sum += rawNoise[ny * size + nx] * weight;
          }
        }
        blurredNoise[y * size + x] = (sum ~/ 12).clamp(0, 255);
      }
    }

    // Create RGBA pixel data from blurred noise
    final pixels = Uint8List(size * size * 4);
    for (int i = 0; i < size * size; i++) {
      final grey = blurredNoise[i];
      pixels[i * 4 + 0] = grey; // R
      pixels[i * 4 + 1] = grey; // G
      pixels[i * 4 + 2] = grey; // B
      pixels[i * 4 + 3] = 255; // A
    }

    // Decode raw pixels into image
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    _noiseImage = await completer.future;
    _noiseImageLoading = false;
    notifyListeners();
  }

  /// Create a gradient shader for a card surface based on light direction
  Shader createSurfaceGradient(Rect bounds, {Color baseColor = const Color(0xFF3A3A3C)}) {
    final light = lightDir2D;
    // Gradient center offset based on light direction
    final centerX = 0.5 - light.dx * 0.3;
    final centerY = 0.5 - light.dy * 0.3;

    return RadialGradient(
      center: Alignment(centerX * 2 - 1, centerY * 2 - 1),
      radius: 1.0,
      colors: [
        Color.lerp(baseColor, Colors.white, 0.08)!,
        baseColor,
        Color.lerp(baseColor, Colors.black, 0.08)!,
      ],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(bounds);
  }

  /// Create box shadows for neumorphic effect based on light direction
  List<BoxShadow> createNeumorphicShadows({
    double elevation = 4.0,
    bool inset = false,
  }) {
    final light = lightDir2D;
    final shadowOffset = Offset(-light.dx * elevation, -light.dy * elevation);
    final highlightOffset = Offset(light.dx * elevation, light.dy * elevation);

    if (inset) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          offset: highlightOffset * 0.5,
          blurRadius: elevation,
          spreadRadius: -1,
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.05),
          offset: shadowOffset * 0.5,
          blurRadius: elevation,
          spreadRadius: -1,
        ),
      ];
    }

    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.5),
        offset: shadowOffset,
        blurRadius: elevation * 1.5,
      ),
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.03),
        offset: highlightOffset,
        blurRadius: elevation,
      ),
    ];
  }

  /// Get a linear gradient for a surface based on light direction
  LinearGradient createLinearSurfaceGradient({
    Color baseColor = const Color(0xFF3A3A3C),
    double intensity = 0.04,
  }) {
    final light = lightDir2D;
    // Convert light direction to alignment
    final beginAlign = Alignment(light.dx, light.dy);
    final endAlign = Alignment(-light.dx, -light.dy);

    return LinearGradient(
      begin: beginAlign,
      end: endAlign,
      colors: [
        Color.lerp(baseColor, Colors.white, intensity)!,
        baseColor,
        Color.lerp(baseColor, Colors.black, intensity)!,
      ],
      stops: const [0.0, 0.5, 1.0],
    );
  }
}
