import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Global lighting settings provider for consistent neumorphic styling across the app.
///
/// Provides:
/// - Light direction (theta/phi angles) and distance
/// - Phong diffuse shading for surfaces
/// - Shared noise texture image
/// - Helper methods for computing gradients and edge lighting
class LightingSettings extends ChangeNotifier {
  /// Azimuthal angle in radians (0 = right, pi/2 = top)
  double _lightPhi = math.pi / 2;

  /// Polar angle in radians (angle from z-axis)
  double _lightTheta = 320 * math.pi / 180;

  /// Distance from surface to light source (in surface-width units)
  /// Smaller values = more dramatic falloff, larger = more uniform
  double _lightDistance = 2.0;

  /// Shared noise texture
  ui.Image? _noiseImage;
  bool _noiseImageLoading = false;

  LightingSettings() {
    _generateNoiseImage();
  }

  double get lightPhi => _lightPhi;
  double get lightTheta => _lightTheta;
  double get lightDistance => _lightDistance;
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

  void setLightDistance(double distance) {
    _lightDistance = distance.clamp(0.5, 10.0);
    notifyListeners();
  }

  /// Compute 3D light position from spherical coordinates
  /// Returns (Lx, Ly, Lz) where Z points out of screen
  (double, double, double) get lightPos3D {
    final lx = _lightDistance * math.sin(_lightTheta) * math.cos(_lightPhi);
    final ly = -_lightDistance * math.sin(_lightTheta) * math.sin(_lightPhi);
    final lz = _lightDistance * math.cos(_lightTheta);
    return (lx, ly, lz);
  }

  /// Compute 2D light direction from spherical coordinates
  /// Returns (Lx, Ly) where positive Ly is down (screen coords)
  Offset get lightDir2D {
    final lx = math.sin(_lightTheta) * math.cos(_lightPhi);
    final ly = -math.sin(_lightTheta) * math.sin(_lightPhi);
    return Offset(lx, ly);
  }

  /// Compute Phong diffuse shading at a point on a flat surface.
  /// [x], [y] are normalized coordinates (-1 to 1) on the surface.
  /// Returns brightness value 0.0 to 1.0.
  double phongDiffuse(double x, double y) {
    final (lx, ly, lz) = lightPos3D;
    // Vector from surface point to light
    final dx = lx - x;
    final dy = ly - y;
    final dz = lz; // Surface is at z=0
    // Distance to light
    final dist = math.sqrt(dx * dx + dy * dy + dz * dz);
    // N·L where N=(0,0,1), so it's just the z-component normalized
    final nDotL = dz / dist;
    return nDotL.clamp(0.0, 1.0);
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

  /// Reference screen size for global light positioning.
  /// Light position is computed relative to this size.
  static const double _refScreenWidth = 1200.0;
  static const double _refScreenHeight = 800.0;

  /// Create a Phong diffuse shaded gradient for a flat surface.
  /// [globalRect] is the widget's position in screen coordinates.
  /// Light position is computed globally so all surfaces share the same light.
  Gradient createPhongSurfaceGradient({
    Color baseColor = const Color(0xFF3A3A3C),
    double intensity = 0.04,
    Rect? globalRect,
  }) {
    // Light position in normalized screen coordinates (-1 to 1)
    // centered on screen, with light distance in screen-width units
    final (lx, ly, lz) = lightPos3D;

    // Scale light position to screen coordinates
    final lightScreenX = _refScreenWidth / 2 + lx * _refScreenWidth / 2;
    final lightScreenY = _refScreenHeight / 2 + ly * _refScreenHeight / 2;
    final lightScreenZ = lz * _refScreenWidth / 2;

    if (globalRect == null || globalRect.isEmpty) {
      // Fallback: simple radial gradient if no global position provided
      return RadialGradient(
        center: Alignment(lx.clamp(-1.0, 1.0), ly.clamp(-1.0, 1.0)),
        radius: 1.5,
        colors: [
          Color.lerp(baseColor, Colors.white, intensity)!,
          baseColor,
          Color.lerp(baseColor, Colors.black, intensity * 0.5)!,
        ],
        stops: const [0.0, 0.6, 1.0],
      );
    }

    // Compute light position relative to this widget's bounds
    // Convert to Alignment coordinates (-1 to 1)
    final relLightX = 2 * (lightScreenX - globalRect.left) / globalRect.width - 1;
    final relLightY = 2 * (lightScreenY - globalRect.top) / globalRect.height - 1;

    // Compute Phong diffuse at corners to determine brightness range
    // Use widget center as reference point
    final widgetCenterScreenX = globalRect.center.dx;
    final widgetCenterScreenY = globalRect.center.dy;

    // Normalized distance from widget center to light (in screen coords)
    final dx = lightScreenX - widgetCenterScreenX;
    final dy = lightScreenY - widgetCenterScreenY;
    final dz = lightScreenZ;
    final dist = math.sqrt(dx * dx + dy * dy + dz * dz);

    // N·L for flat surface (N = 0,0,1)
    final nDotL = (dz / dist).clamp(0.0, 1.0);

    // Brightness at this widget based on its position
    final brightness = nDotL * intensity * 2;

    // Radius based on light height and widget size
    final avgSize = (globalRect.width + globalRect.height) / 2;
    final radius = (lightScreenZ / avgSize * 2 + 0.5).clamp(0.8, 4.0);

    return RadialGradient(
      center: Alignment(relLightX.clamp(-3.0, 3.0), relLightY.clamp(-3.0, 3.0)),
      radius: radius,
      colors: [
        Color.lerp(baseColor, Colors.white, brightness.clamp(0, intensity * 2))!,
        baseColor,
        Color.lerp(baseColor, Colors.black, (brightness * 0.3).clamp(0, intensity))!,
      ],
      stops: const [0.0, 0.7, 1.0],
    );
  }

  /// Get a linear gradient for a surface based on light direction (legacy method).
  /// Consider using createPhongSurfaceGradient for more realistic shading.
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
