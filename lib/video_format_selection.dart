// ignore_for_file: file_names

import 'dart:math';
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

/// Compute condition number for a 3x3 matrix using Frobenius norm
double computeConditionNumber(List<List<double>> m) {
  double frobM = 0;
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      frobM += m[i][j] * m[i][j];
    }
  }
  frobM = sqrt(frobM);

  final det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
              m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
              m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

  if (det.abs() < 1e-10) return double.infinity;

  final adj = [
    [m[1][1]*m[2][2] - m[1][2]*m[2][1], m[0][2]*m[2][1] - m[0][1]*m[2][2], m[0][1]*m[1][2] - m[0][2]*m[1][1]],
    [m[1][2]*m[2][0] - m[1][0]*m[2][2], m[0][0]*m[2][2] - m[0][2]*m[2][0], m[0][2]*m[1][0] - m[0][0]*m[1][2]],
    [m[1][0]*m[2][1] - m[1][1]*m[2][0], m[0][1]*m[2][0] - m[0][0]*m[2][1], m[0][0]*m[1][1] - m[0][1]*m[1][0]],
  ];

  double frobAdj = 0;
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      frobAdj += adj[i][j] * adj[i][j];
    }
  }
  final frobInv = sqrt(frobAdj) / det.abs();

  return frobM * frobInv;
}

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

  // Primaries for color wheels (columns of the matrix)
  List<double> _primary1 = [1, 0, 0];
  List<double> _primary2 = [0, 1, 0];
  List<double> _primary3 = [0, 0, 1];

  // Saved custom primaries (remembered when switching away from Custom)
  List<double> _customPrimary1 = [1, 0, 0];
  List<double> _customPrimary2 = [0, 1, 0];
  List<double> _customPrimary3 = [0, 0, 1];

  // Track which wheel is currently being dragged (-1 = none)
  int _draggingWheelIndex = -1;
  Offset _dragGlobalPosition = Offset.zero;
  OverlayEntry? _kappaOverlayEntry;

  // Slider values for each wheel (controls position along gray axis)
  double _slider1 = 0.0;
  double _slider2 = 0.0;
  double _slider3 = 0.0;

  @override
  void initState() {
    super.initState();

    // Initialize with YUV matrix to match default dropdown selection
    matrixModel = ColorSpaceMatrix(getMatrixForColorspace('YUV'));
    _syncPrimariesFromMatrix();
    _syncSlidersFromPrimaries();

    // Listen to sync_mode changes to enable/disable format controls
    OscRegistry().registerAddress('/sync_mode');
    OscRegistry().registerListener('/sync_mode', _onSyncModeChanged);
    // Listen to dac_genlock changes
    OscRegistry().registerAddress('/dac_genlock');
    OscRegistry().registerListener('/dac_genlock', _onDacGenlockChanged);
  }

  @override
  void dispose() {
    _hideKappaOverlay();
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

  void _syncSlidersFromPrimaries() {
    // Extract slider values from current primaries using rgbToWheelCoords
    final coords1 = rgbToWheelCoords(_primary1);
    final coords2 = rgbToWheelCoords(_primary2);
    final coords3 = rgbToWheelCoords(_primary3);
    _slider1 = coords1[2];  // The 's' component
    _slider2 = coords2[2];
    _slider3 = coords3[2];
  }

  double _getSliderForPrimary(int index) {
    switch (index) {
      case 0: return _slider1;
      case 1: return _slider2;
      case 2: return _slider3;
      default: return 0.0;
    }
  }

  void _setSliderForPrimary(int index, double value) {
    switch (index) {
      case 0: _slider1 = value; break;
      case 1: _slider2 = value; break;
      case 2: _slider3 = value; break;
    }
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

  void _handleWheelDrag(Offset pos, double size, int primaryIndex, Offset globalPos, Offset localOrigin) {
    final sliderValue = _getSliderForPrimary(primaryIndex);
    final rgb = wheelPositionToRgb(pos, size, sliderValue);

    // Clamp the overlay position to the wheel boundary
    final center = Offset(size / 2, size / 2);
    var offset = pos - center;
    final radius = size / 2;
    final dist = offset.distance;
    if (dist > radius) {
      offset = offset * (radius / dist);
    }
    final clampedLocal = center + offset;
    final clampedGlobal = localOrigin + clampedLocal;

    setState(() {
      _draggingWheelIndex = primaryIndex;
      _dragGlobalPosition = clampedGlobal;
      if (primaryIndex == 0) {
        _primary1 = rgb;
      } else if (primaryIndex == 1) {
        _primary2 = rgb;
      } else {
        _primary3 = rgb;
      }
      _updateMatrixFromPrimary(primaryIndex, rgb);
    });

    _updateKappaOverlay();
  }

  void _showKappaOverlay() {
    _kappaOverlayEntry?.remove();
    _kappaOverlayEntry = OverlayEntry(
      builder: (context) => _buildKappaOverlayPositioned(),
    );
    Overlay.of(context).insert(_kappaOverlayEntry!);
  }

  void _updateKappaOverlay() {
    if (_kappaOverlayEntry == null) {
      _showKappaOverlay();
    } else {
      _kappaOverlayEntry!.markNeedsBuild();
    }
  }

  void _hideKappaOverlay() {
    _kappaOverlayEntry?.remove();
    _kappaOverlayEntry = null;
  }

  Widget _buildKappaOverlayPositioned() {
    final kappa = _getCurrentConditionNumber();
    final rgb = _draggingWheelIndex == 0
        ? _primary1
        : _draggingWheelIndex == 1
            ? _primary2
            : _primary3;

    // Position so the circle is centered on the drag position
    // Bar height is 28, circle is centered vertically, left padding is 6
    const barHeight = 28.0;
    const circleRadius = 8.0;
    const leftPadding = 6.0;

    return Positioned(
      left: _dragGlobalPosition.dx - circleRadius - leftPadding,
      top: _dragGlobalPosition.dy - barHeight / 2,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: _buildKappaOverlay(kappa, rgb),
        ),
      ),
    );
  }

  void _handleSliderChange(int primaryIndex, double newValue) {
    // Get current wheel position (a, b) from the primary
    final primary = primaryIndex == 0 ? _primary1 : (primaryIndex == 1 ? _primary2 : _primary3);
    final coords = rgbToWheelCoords(primary);
    final a = coords[0];
    final b = coords[1];

    // Compute new RGB with updated slider value
    final rgb = wheelCoordsToRgb(a, b, newValue);

    setState(() {
      _setSliderForPrimary(primaryIndex, newValue);
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

  void _handleWheelDragEnd() {
    _hideKappaOverlay();
    setState(() {
      _draggingWheelIndex = -1;
    });
  }

  double _getCurrentConditionNumber() {
    final matrix = [
      [_primary1[0], _primary2[0], _primary3[0]],
      [_primary1[1], _primary2[1], _primary3[1]],
      [_primary1[2], _primary2[2], _primary3[2]],
    ];
    return computeConditionNumber(matrix);
  }

  Widget _buildConditionBar(double kappa) {
    // Log scale: kappa 1 = 0%, kappa 1000 = 100%
    final logKappa = log(kappa.clamp(1, 1000)) / log(1000);
    final percentage = (logKappa * 100).clamp(0.0, 100.0);

    // Color: green (good) -> yellow -> red (bad)
    Color barColor;
    if (kappa < 3) {
      barColor = const Color(0xFF4CAF50); // Green
    } else if (kappa < 10) {
      barColor = const Color(0xFFFFC107); // Yellow
    } else if (kappa < 100) {
      barColor = const Color(0xFFFF9800); // Orange
    } else {
      barColor = const Color(0xFFF44336); // Red
    }

    return Container(
      width: 90,
      height: 16,
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Stack(
        children: [
          // Fill bar
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: percentage / 100,
            child: Container(
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // κ value text
          Center(
            child: Text(
              'κ=${kappa.isFinite ? kappa.toStringAsFixed(1) : '∞'}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                shadows: [Shadow(blurRadius: 2, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKappaOverlay(double kappa, List<double> rgb) {
    // Clamp color for display
    final displayColor = Color.fromRGBO(
      (rgb[0].clamp(0, 1) * 255).round(),
      (rgb[1].clamp(0, 1) * 255).round(),
      (rgb[2].clamp(0, 1) * 255).round(),
      1,
    );

    // Bar width based on kappa (log scale, max at ~100)
    final kappaForBar = kappa.clamp(1, 100);
    final barFraction = (log(kappaForBar) / log(100)).clamp(0.0, 1.0);

    const double barHeight = 28.0;
    const double circleSize = 16.0;

    // Format kappa as fixed width: "κ=XX.X" or "κ= ∞ "
    final kappaStr = kappa.isFinite
        ? kappa.clamp(0, 99.9).toStringAsFixed(1).padLeft(4)
        : '  ∞ ';

    // Text color based on kappa value
    final Color textColor;
    if (kappa <= 4) {
      textColor = const Color(0xFF4CAF50); // Green
    } else if (kappa <= 15) {
      textColor = const Color(0xFFF0B830); // Yellow/amber
    } else {
      textColor = const Color(0xFFF44336); // Red
    }

    return Container(
      height: barHeight,
      padding: const EdgeInsets.only(left: 6, right: 8),
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(barHeight / 2),  // Semicircle on left
          right: const Radius.circular(6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Color indicator circle (same size as wheel indicator: radius 8)
          Container(
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              color: displayColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey[600]!, width: 2),
            ),
          ),
          const SizedBox(width: 6),
          // Kappa text - fixed width monospace, colored based on kappa
          Text(
            'κ=$kappaStr',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'Courier',
              fontFamilyFallback: const ['Courier New', 'monospace'],
              color: textColor,
            ),
          ),
          const SizedBox(width: 8),
          // Bar with V-notches at 4 and 15
          CustomPaint(
            size: const Size(80, 14),
            painter: _KappaBarPainter(
              barFraction: barFraction,
              kappa: kappa,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorWheel(BuildContext context, String label, int primaryIndex, List<double> rgb, List<double> other1, List<double> other2) {
    const size = 90.0;
    final sliderValue = _getSliderForPrimary(primaryIndex);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wheel
        GestureDetector(
          onPanStart: (d) {
            final origin = d.globalPosition - d.localPosition;
            _handleWheelDrag(d.localPosition, size, primaryIndex, d.globalPosition, origin);
          },
          onPanUpdate: (d) {
            final origin = d.globalPosition - d.localPosition;
            _handleWheelDrag(d.localPosition, size, primaryIndex, d.globalPosition, origin);
          },
          onPanEnd: (_) => _handleWheelDragEnd(),
          onTapDown: (d) {
            final origin = d.globalPosition - d.localPosition;
            _handleWheelDrag(d.localPosition, size, primaryIndex, d.globalPosition, origin);
          },
          onTapUp: (_) => _handleWheelDragEnd(),
          child: CustomPaint(
            size: const Size(size, size),
            painter: ColorWheelPainter(rgb, other1, other2, primaryIndex, sliderValue: sliderValue, isCompact: true),
          ),
        ),
        const SizedBox(height: 4),
        // Intensity slider - hidden for testing
        // SizedBox(
        //   width: size,
        //   height: 24,
        //   child: Row(
        //     children: [
        //       Text('−', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        //       Expanded(
        //         child: SliderTheme(
        //           data: SliderTheme.of(context).copyWith(
        //             trackHeight: 3,
        //             thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        //             overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        //             activeTrackColor: Colors.grey[400],
        //             inactiveTrackColor: Colors.grey[700],
        //             thumbColor: Colors.grey[300],
        //           ),
        //           child: Slider(
        //             value: sliderValue.clamp(-2.0, 2.0),
        //             min: -2.0,
        //             max: 2.0,
        //             onChanged: (v) => _handleSliderChange(primaryIndex, v),
        //           ),
        //         ),
        //       ),
        //       Text('+', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        //     ],
        //   ),
        // ),
        // Label below wheel
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[400], fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
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
                          _syncSlidersFromPrimaries();
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

    // Noise texture overlay - DISABLED FOR DEBUG
    // if (lighting.noiseImage != null) {
    //   final noisePaint = Paint()
    //     ..shader = ImageShader(
    //       lighting.noiseImage!,
    //       TileMode.repeated,
    //       TileMode.repeated,
    //       Matrix4.identity().storage,
    //     )
    //     ..blendMode = BlendMode.overlay;
    //   canvas.save();
    //   canvas.clipPath(combinedPath);
    //   canvas.drawRect(combined, noisePaint);
    //   canvas.restore();
    // }
  }

  @override
  bool shouldRepaint(covariant _LPainter old) =>
      old.color != color || old.hBar != hBar || old.vBar != vBar ||
      old.lighting.lightPhi != lighting.lightPhi ||
      old.lighting.lightTheta != lighting.lightTheta ||
      old.lighting.noiseImage != lighting.noiseImage ||
      old.globalRect != globalRect;
}

/// Custom painter for the kappa bar with V-notches at κ=4 and κ=15
class _KappaBarPainter extends CustomPainter {
  final double barFraction;
  final double kappa;

  // Same amber color as rotary knob
  static const Color _activeColor = Color(0xFFF0B830);

  // Notch positions on log scale (kappa 1-100)
  // κ=4 → log(4)/log(100) ≈ 0.30
  // κ=15 → log(15)/log(100) ≈ 0.59
  static final double _notch4Position = log(4) / log(100);
  static final double _notch15Position = log(15) / log(100);

  _KappaBarPainter({
    required this.barFraction,
    required this.kappa,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const notchDepth = 4.0;
    const notchHalfWidth = 3.0;
    const cornerRadius = 1.5;

    final barY = 0.0;
    final barHeight = size.height;

    // Notch positions in pixels
    final notch4X = _notch4Position * size.width;
    final notch15X = _notch15Position * size.width;

    // Build combined slot + notches path
    final combinedPath = Path();
    combinedPath.addRect(Rect.fromLTWH(0, barY, size.width, barHeight));

    // Add V-notches at κ=4 and κ=15
    for (final snapX in [notch4X, notch15X]) {
      final leftBaseX = snapX - notchHalfWidth;
      final rightBaseX = snapX + notchHalfWidth;
      final tipY = barY - notchDepth;

      final notchPath = Path();
      notchPath.moveTo(leftBaseX - cornerRadius, barY);
      notchPath.quadraticBezierTo(leftBaseX, barY, leftBaseX + cornerRadius * 0.7, barY - cornerRadius * 0.7);
      notchPath.lineTo(snapX, tipY);
      notchPath.lineTo(rightBaseX - cornerRadius * 0.7, barY - cornerRadius * 0.7);
      notchPath.quadraticBezierTo(rightBaseX, barY, rightBaseX + cornerRadius, barY);
      notchPath.close();

      combinedPath.addPath(notchPath, Offset.zero);
    }

    // Outer border/lip
    final borderGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFF404040), Color(0xFF585858)],
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = borderGradient.createShader(
        Rect.fromLTWH(-1, barY - notchDepth - 1, size.width + 2, barHeight + notchDepth + 2),
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-1, barY - 1, size.width + 2, barHeight + 2),
        const Radius.circular(3),
      ),
      borderPaint,
    );

    // Dark floor (fills combined slot + notches shape)
    final floorGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFF141414), Color(0xFF1C1C1C)],
    );
    final floorPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = floorGradient.createShader(
        Rect.fromLTWH(0, barY - notchDepth, size.width, barHeight + notchDepth),
      );

    canvas.save();
    canvas.clipPath(combinedPath);
    canvas.drawRect(
      Rect.fromLTWH(0, barY - notchDepth, size.width, barHeight + notchDepth),
      floorPaint,
    );
    canvas.restore();

    // Value bar fill (amber color, clipped to combined shape)
    if (barFraction > 0.005) {
      final valueWidth = size.width * barFraction;

      canvas.save();
      canvas.clipPath(combinedPath);

      // Value bar with amber color
      final valueGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _activeColor,
          Color.lerp(_activeColor, Colors.black, 0.15)!,
        ],
      );
      final valuePaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = valueGradient.createShader(
          Rect.fromLTWH(0, barY - notchDepth, valueWidth, barHeight + notchDepth),
        );

      canvas.drawRect(
        Rect.fromLTWH(0, barY - notchDepth, valueWidth, barHeight + notchDepth),
        valuePaint,
      );

      // Top highlight on value bar
      final highlightGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.0),
        ],
      );
      final highlightPaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = highlightGradient.createShader(
          Rect.fromLTWH(0, barY - notchDepth, valueWidth, 3),
        );
      canvas.drawRect(
        Rect.fromLTWH(0, barY - notchDepth, valueWidth, 3),
        highlightPaint,
      );

      canvas.restore();
    }

    // Edge highlights - top edge segments between notches
    final topEdgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..color = Colors.white.withValues(alpha: 0.25);

    // Left segment (before κ=4 notch)
    final leftSegEnd = notch4X - notchHalfWidth - cornerRadius;
    if (leftSegEnd > 0) {
      canvas.drawLine(Offset(0, barY), Offset(leftSegEnd, barY), topEdgePaint);
    }

    // Middle segment (between κ=4 and κ=15 notches)
    final midSegStart = notch4X + notchHalfWidth + cornerRadius;
    final midSegEnd = notch15X - notchHalfWidth - cornerRadius;
    if (midSegEnd > midSegStart) {
      canvas.drawLine(Offset(midSegStart, barY), Offset(midSegEnd, barY), topEdgePaint);
    }

    // Right segment (after κ=15 notch)
    final rightSegStart = notch15X + notchHalfWidth + cornerRadius;
    if (rightSegStart < size.width) {
      canvas.drawLine(Offset(rightSegStart, barY), Offset(size.width, barY), topEdgePaint);
    }

    // Notch edge highlights
    final notchEdgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.3);

    for (final snapX in [notch4X, notch15X]) {
      final leftBaseX = snapX - notchHalfWidth;
      final rightBaseX = snapX + notchHalfWidth;
      final tipY = barY - notchDepth;

      final leftStart = Offset(leftBaseX + cornerRadius * 0.7, barY - cornerRadius * 0.7);
      final tip = Offset(snapX, tipY);
      final rightEnd = Offset(rightBaseX - cornerRadius * 0.7, barY - cornerRadius * 0.7);

      // Left edge
      canvas.drawLine(leftStart, tip, notchEdgePaint);
      // Left corner fillet
      final leftCornerPath = Path()
        ..moveTo(leftBaseX - cornerRadius, barY)
        ..quadraticBezierTo(leftBaseX, barY, leftStart.dx, leftStart.dy);
      canvas.drawPath(leftCornerPath, notchEdgePaint);

      // Right edge
      canvas.drawLine(tip, rightEnd, notchEdgePaint);
      // Right corner fillet
      final rightCornerPath = Path()
        ..moveTo(rightEnd.dx, rightEnd.dy)
        ..quadraticBezierTo(rightBaseX, barY, rightBaseX + cornerRadius, barY);
      canvas.drawPath(rightCornerPath, notchEdgePaint);
    }

    // Bottom edge highlight
    canvas.drawLine(
      Offset(0, barY + barHeight),
      Offset(size.width, barY + barHeight),
      Paint()..color = Colors.white.withValues(alpha: 0.15)..strokeWidth = 0.75,
    );
  }

  @override
  bool shouldRepaint(covariant _KappaBarPainter old) =>
      old.barFraction != barFraction || old.kappa != kappa;
}

