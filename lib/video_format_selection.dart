// ignore_for_file: file_names

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'osc_registry.dart';

import 'color_space_matrix.dart';
import 'color_wheel.dart';
import 'labeled_card.dart';
import 'lighting_settings.dart';
import 'osc_dropdown.dart';

class VideoFormatSelectionSection extends StatefulWidget {
  const VideoFormatSelectionSection({super.key});

  @override
  State<VideoFormatSelectionSection> createState() =>
      _VideoFormatSelectionSectionState();
}

class _VideoFormatSelectionSectionState
    extends State<VideoFormatSelectionSection>
    with OscAddressMixin {
  late ColorSpaceMatrix matrixModel;
  String _syncMode = 'locked';  // Track current sync mode
  bool _dacGenlock = false;     // Track DAC genlock state

  final List<String> resolutions = [
    '1920x1080',
    '1280x720',
    '720x576',
    '720x480',
  ];

  final List<double> framerates = [60.0, 50.0, 30.0, 25.0, 24.0];

  final List<String> colorspaces = [
    'RGB',
    'YUV',
    'Custom',
  ];

  String selectedResolution = '1920x1080';
  double selectedFramerate = 30.0;
  String selectedColorspace = 'YUV';
  bool fullRange = true;

  // Primaries for color wheels (columns of the matrix)
  List<double> _primary1 = [1, 0, 0];
  List<double> _primary2 = [0, 1, 0];
  List<double> _primary3 = [0, 0, 1];

  // Saved custom primaries (remembered when switching away from Custom)
  List<double> _customPrimary1 = [1, 0, 0];
  List<double> _customPrimary2 = [0, 1, 0];
  List<double> _customPrimary3 = [0, 0, 1];

  @override
  void initState() {
    super.initState();

    // Initialize with YUV matrix to match default dropdown selection
    matrixModel = ColorSpaceMatrix(getMatrixForColorspace('YUV'));
    _syncPrimariesFromMatrix();

    // Listen to sync_mode changes to enable/disable format controls
    OscRegistry().registerAddress('/sync_mode');
    OscRegistry().registerListener('/sync_mode', _onSyncModeChanged);
    // Listen to dac_genlock changes
    OscRegistry().registerAddress('/dac_genlock');
    OscRegistry().registerListener('/dac_genlock', _onDacGenlockChanged);
  }

  @override
  void dispose() {
    OscRegistry().unregisterListener('/sync_mode', _onSyncModeChanged);
    OscRegistry().unregisterListener('/dac_genlock', _onDacGenlockChanged);
    super.dispose();
  }

  void _onSyncModeChanged(List<Object?> args) {
    if (args.isNotEmpty && args.first is String) {
      setState(() {
        _syncMode = (args.first as String).toLowerCase();
      });
    }
  }

  void _onDacGenlockChanged(List<Object?> args) {
    if (args.isNotEmpty && args.first is bool) {
      setState(() {
        _dacGenlock = args.first as bool;
      });
    }
  }

  /// Returns true if format controls should be enabled
  /// - In 'locked' mode: always enabled
  /// - In 'component'/'external' mode: enabled only if dac_genlock is OFF
  bool get _formatControlsEnabled {
    if (_syncMode == 'locked') return true;
    return !_dacGenlock;  // Enabled when dac_genlock is OFF
  }

  List<List<double>> getMatrixForColorspace(String space) {
    if (space == 'RGB') {
      // Identity matrix - no conversion
      return [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
      ];
    } else if (space == 'YUV') {
      // YUV to RGB conversion matrix
      return [
        [1.0000, 0.0000, 1.5748],
        [1.0000, -0.1873, -0.4681],
        [1.0000, 1.8556, 0.0000],
      ];
    } else {
      return [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
      ];
    }
  }

  void _sendColorMatrix() {
    final flatMatrix = matrixModel.matrix
        .expand((row) => row)
        .toList(growable: false);
    sendOsc(flatMatrix, address: '/analog_format/color_matrix');
  }

  void _syncPrimariesFromMatrix() {
    // Primaries are columns of the matrix
    _primary1 = [matrixModel.matrix[0][0], matrixModel.matrix[1][0], matrixModel.matrix[2][0]];
    _primary2 = [matrixModel.matrix[0][1], matrixModel.matrix[1][1], matrixModel.matrix[2][1]];
    _primary3 = [matrixModel.matrix[0][2], matrixModel.matrix[1][2], matrixModel.matrix[2][2]];
  }

  void _updateMatrixFromPrimary(int primaryIndex, List<double> rgb) {
    // Update the column of the matrix
    for (int row = 0; row < 3; row++) {
      matrixModel.updateCell(row, primaryIndex, rgb[row]);
    }
    _sendColorMatrix();

    // Save custom primaries whenever user edits wheels
    _customPrimary1 = List.from(_primary1);
    _customPrimary2 = List.from(_primary2);
    _customPrimary3 = List.from(_primary3);

    if (selectedColorspace != 'Custom') {
      selectedColorspace = 'Custom';
    }
  }

  void _handleWheelDrag(Offset pos, double size, int primaryIndex) {
    final rgb = wheelPositionToRgb(pos, size);

    setState(() {
      if (primaryIndex == 0) {
        _primary1 = rgb;
      } else if (primaryIndex == 1) {
        _primary2 = rgb;
      } else {
        _primary3 = rgb;
      }
      _updateMatrixFromPrimary(primaryIndex, rgb);
    });
  }

  Widget _buildColorWheel(BuildContext context, String label, int primaryIndex, List<double> rgb, List<double> other1, List<double> other2) {
    const size = 90.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wheel first
        GestureDetector(
          onPanUpdate: (d) => _handleWheelDrag(d.localPosition, size, primaryIndex),
          onTapDown: (d) => _handleWheelDrag(d.localPosition, size, primaryIndex),
          child: CustomPaint(
            size: const Size(size, size),
            painter: ColorWheelPainter(rgb, other1, other2, primaryIndex),
          ),
        ),
        const SizedBox(height: 10),
        // Label below wheel, styled to match dropdown labels
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[400], fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        // RGB triplets below label
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${rgb[0] >= 0 ? '+' : ''}${rgb[0].toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12, fontFamily: 'Courier', fontFamilyFallback: ['Courier New', 'monospace'], color: Color(0xFFFF6B6B)),
            ),
            Text(
              '${rgb[1] >= 0 ? '+' : ''}${rgb[1].toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12, fontFamily: 'Courier', fontFamilyFallback: ['Courier New', 'monospace'], color: Color(0xFF69DB7C)),
            ),
            Text(
              '${rgb[2] >= 0 ? '+' : ''}${rgb[2].toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12, fontFamily: 'Courier', fontFamilyFallback: ['Courier New', 'monospace'], color: Color(0xFF74C0FC)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _colorWheelsWidget(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildColorWheel(context, 'Channel 1', 0, _primary1, _primary2, _primary3),
        const SizedBox(width: 10),
        _buildColorWheel(context, 'Channel 2', 1, _primary2, _primary1, _primary3),
        const SizedBox(width: 10),
        _buildColorWheel(context, 'Channel 3', 2, _primary3, _primary1, _primary2),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Measurements
    const double colWidth = 190.0;
    const double resFrameHeight = 124.0; // Resolution + Framerate height (tighter)
    const double colorspaceBoxHeight = 75.0;
    const double colorspaceBoxWidth = 200.0;
    const double wheelsBoxWidth = 310.0;
    const double wheelsBoxHeight = 170.0;
    const double r = 12.0;
    const double gap = 0.0;

    return OscPathSegment(
      segment: 'analog_format',
      child: LabeledCard(
        title: 'Analog Send/Return Format',
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              SizedBox(
                width: colWidth + gap + wheelsBoxWidth,
                height: resFrameHeight + colorspaceBoxHeight,
                child: Stack(
                children: [
                  // L-shaped grey background: two overlapping rounded rects
                  // Both share the same bottom-right corner
                  Positioned.fill(
                    child: Builder(
                      builder: (context) {
                        final lighting = context.watch<LightingSettings>();
                        const double vBarTop = 0.0; // Top aligns with Resolution dropdown
                        final sharedRight = colWidth + gap + wheelsBoxWidth;
                        final sharedBottom = resFrameHeight + colorspaceBoxHeight;
                        return CustomPaint(
                          painter: _LPainter(
                            color: Colors.grey[700]!,
                            r: r,
                            // Horizontal bar: extends past left edge to hide rounded corner
                            hBar: Rect.fromLTRB(-r, resFrameHeight, sharedRight, sharedBottom),
                            // Vertical bar: wraps wheels, shares corner with hBar
                            vBar: Rect.fromLTRB(colWidth + gap, vBarTop, sharedRight, sharedBottom),
                            lighting: lighting,
                          ),
                        );
                      },
                    ),
                  ),
                  // Resolution (outside grey)
                  Positioned(
                    left: 0, top: 0,
                    width: colWidth,
                    child: OscDropdown<String>(
                      label: 'Resolution',
                      items: resolutions,
                      defaultValue: resolutions[0],
                      enabled: _formatControlsEnabled,
                    ),
                  ),
                  // Framerate (outside grey)
                  Positioned(
                    left: 0, top: 62,
                    width: colWidth,
                    child: OscDropdown<double>(
                      label: 'Framerate',
                      items: framerates,
                      defaultValue: framerates[0],
                      enabled: _formatControlsEnabled,
                    ),
                  ),
                  // Colorspace (inside grey L, bottom-left) - aligned with dropdowns above
                  Positioned(
                    left: 0, top: resFrameHeight + 10,
                    width: colWidth,
                    child: OscDropdown<String>(
                      key: ValueKey('colorspace_$selectedColorspace'),
                      label: 'Colorspace',
                      items: colorspaces,
                      defaultValue: selectedColorspace,
                      onChanged: (value) {
                        setState(() {
                          selectedColorspace = value;
                          if (value == 'Custom') {
                            // Restore saved custom primaries
                            _primary1 = List.from(_customPrimary1);
                            _primary2 = List.from(_customPrimary2);
                            _primary3 = List.from(_customPrimary3);
                            // Rebuild matrix from custom primaries
                            for (int col = 0; col < 3; col++) {
                              final primary = col == 0 ? _primary1 : (col == 1 ? _primary2 : _primary3);
                              for (int row = 0; row < 3; row++) {
                                matrixModel.updateCell(row, col, primary[row]);
                              }
                            }
                          } else {
                            matrixModel = ColorSpaceMatrix(getMatrixForColorspace(value));
                            _syncPrimariesFromMatrix();
                          }
                          _sendColorMatrix();
                        });
                      },
                    ),
                  ),
                  // Wheels (inside grey L, top-right) - 10px padding = wheel gap
                  Positioned(
                    left: colWidth + gap + 10,
                    top: 12,
                    child: _colorWheelsWidget(context),
                  ),
                ],
              ),
            ),
            // Quantization range dropdown
            const SizedBox(height: 16),
            SizedBox(
              width: colWidth,
              child: OscDropdown<String>(
                label: 'Quantization Range',
                items: const ['Full (0-255)', 'Legal (16-235)'],
                defaultValue: 'Full (0-255)',
                onChanged: (value) {
                  final isFullRange = value == 'Full (0-255)';
                  setState(() => fullRange = isFullRange);
                  sendOsc(isFullRange, address: '/analog_format/full_range');
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}

/// Draws L-shape using two overlapping rounded rectangles with lighting
class _LPainter extends CustomPainter {
  final Color color;
  final double r;
  final Rect hBar;
  final Rect vBar;
  final LightingSettings lighting;
  final Rect? globalRect;

  _LPainter({
    required this.color,
    required this.r,
    required this.hBar,
    required this.vBar,
    required this.lighting,
    this.globalRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect1 = RRect.fromRectAndRadius(hBar, Radius.circular(r));
    final rrect2 = RRect.fromRectAndRadius(vBar, Radius.circular(r));

    // Combined bounds for gradient
    final combined = hBar.expandToInclude(vBar);

    // Create combined path for both rectangles
    final combinedPath = Path()
      ..addRRect(rrect1)
      ..addRRect(rrect2);

    // Lighting gradient
    final gradient = lighting.createPhongSurfaceGradient(
      baseColor: color,
      intensity: 0.08,
      globalRect: globalRect,
    );
    final gradientPaint = Paint()..shader = gradient.createShader(combined);

    canvas.drawPath(combinedPath, gradientPaint);

    // Noise texture overlay - draw once for combined shape
    if (lighting.noiseImage != null) {
      final noisePaint = Paint()
        ..shader = ImageShader(
          lighting.noiseImage!,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..blendMode = BlendMode.overlay;

      canvas.save();
      canvas.clipPath(combinedPath);
      canvas.drawRect(combined, noisePaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _LPainter old) =>
      old.color != color || old.hBar != hBar || old.vBar != vBar ||
      old.lighting.lightPhi != lighting.lightPhi ||
      old.lighting.lightTheta != lighting.lightTheta ||
      old.lighting.noiseImage != lighting.noiseImage ||
      old.globalRect != globalRect;
}

