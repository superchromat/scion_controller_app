// ignore_for_file: file_names

import 'dart:math';
import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_registry.dart';

import 'color_space_matrix.dart';
import 'color_wheel.dart';
import 'color_wheel_arc.dart';
import 'drag_area.dart';
import 'grid.dart';
import 'labeled_card.dart';
import 'osc_dropdown.dart';

/// Default analog Send/Return format, matching the dropdown defaults in the
/// card below. Shown before any device `/sync` supplies real values — i.e. in
/// demo mode.
const String kAnalogDefaultResolution = '1920x1080';
const double kAnalogDefaultFramerate = 60.0;
const String kAnalogDefaultColorspace = 'YUV';
const bool kAnalogDefaultInterlaced = false;

/// Seeds the `/analog_format/*` registry entries with the card's default
/// selections so the Send/Return tiles show a real format in demo mode. The
/// tiles live on a different page than the card (so the card's own init can't
/// seed them in time) and there's no device to broadcast the values. Only fills
/// empty entries, so a connected device's `/sync` always wins; once the user
/// changes a dropdown, its local echo keeps the tiles in sync automatically.
void seedAnalogFormatDefaults() {
  final reg = OscRegistry();
  void seed(String addr, Object value) {
    reg.registerAddress(addr);
    final p = reg.allParams[addr];
    if (p != null && p.currentValue.isEmpty) {
      reg.dispatchLocal(addr, <Object?>[value]);
    }
  }

  seed('/analog_format/resolution', kAnalogDefaultResolution);
  seed('/analog_format/framerate', kAnalogDefaultFramerate);
  seed('/analog_format/colorspace', kAnalogDefaultColorspace);
  seed('/analog_format/interlaced', kAnalogDefaultInterlaced);
}

/// Compute the required ADC output bias for a matrix.
/// Returns the maximum absolute bias needed across all channels.
/// Large values indicate the matrix may not be practically recoverable in hardware.
double computeRequiredAdcBias(List<List<double>> m) {
  // Step 1: Compute output range and scale factor
  double scale = 1.0;
  List<double> minOut = [0, 0, 0];

  for (int row = 0; row < 3; row++) {
    double posSum = 0, negSum = 0;
    for (int col = 0; col < 3; col++) {
      if (m[row][col] > 0) {
        posSum += m[row][col];
      } else {
        negSum += m[row][col];
      }
    }
    minOut[row] = negSum;
    double range = posSum - negSum;
    if (range > scale) scale = range;
  }
  scale *= 1.05; // margin

  // Step 2: Compute DAC output bias = -min/scale
  List<double> dacBias = [
    -minOut[0] / scale,
    -minOut[1] / scale,
    -minOut[2] / scale,
  ];

  // Step 3: Compute inverse matrix
  final det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
      m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
      m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

  if (det.abs() < 1e-10) return double.infinity;

  final adj = [
    [
      m[1][1] * m[2][2] - m[1][2] * m[2][1],
      m[0][2] * m[2][1] - m[0][1] * m[2][2],
      m[0][1] * m[1][2] - m[0][2] * m[1][1]
    ],
    [
      m[1][2] * m[2][0] - m[1][0] * m[2][2],
      m[0][0] * m[2][2] - m[0][2] * m[2][0],
      m[0][2] * m[1][0] - m[0][0] * m[1][2]
    ],
    [
      m[1][0] * m[2][1] - m[1][1] * m[2][0],
      m[0][1] * m[2][0] - m[0][0] * m[2][1],
      m[0][0] * m[1][1] - m[0][1] * m[1][0]
    ],
  ];

  // M^-1 = adj / det
  List<List<double>> mInv =
      List.generate(3, (i) => List.generate(3, (j) => adj[i][j] / det));

  // Step 4: Compute ADC output bias = -M^-1 × scale × dacBias
  double maxAdcBias = 0;
  for (int row = 0; row < 3; row++) {
    double sum = 0;
    for (int col = 0; col < 3; col++) {
      sum += mInv[row][col] * scale * dacBias[col];
    }
    double adcBias = sum.abs(); // We negate in firmware, so absolute value
    if (adcBias > maxAdcBias) maxAdcBias = adcBias;
  }

  return maxAdcBias;
}

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
    [
      m[1][1] * m[2][2] - m[1][2] * m[2][1],
      m[0][2] * m[2][1] - m[0][1] * m[2][2],
      m[0][1] * m[1][2] - m[0][2] * m[1][1]
    ],
    [
      m[1][2] * m[2][0] - m[1][0] * m[2][2],
      m[0][0] * m[2][2] - m[0][2] * m[2][0],
      m[0][2] * m[1][0] - m[0][0] * m[1][2]
    ],
    [
      m[1][0] * m[2][1] - m[1][1] * m[2][0],
      m[0][1] * m[2][0] - m[0][0] * m[2][1],
      m[0][0] * m[1][1] - m[0][1] * m[1][0]
    ],
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
    extends State<VideoFormatSelectionSection> with OscAddressMixin {
  late ColorSpaceMatrix matrixModel;
  String _syncMode = 'locked'; // Track current sync mode
  bool _dacGenlock = false; // Track DAC genlock state

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

  // Track drag mode: 0 = none, 1 = wheel (chromaticity), 2 = arc (intensity)
  int _dragMode = 0;

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
    return !_dacGenlock; // Enabled when dac_genlock is OFF
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
    final flatMatrix =
        matrixModel.matrix.expand((row) => row).toList(growable: false);
    sendOsc(flatMatrix, address: '/analog_format/color_matrix');
  }

  void _syncPrimariesFromMatrix() {
    // Primaries are columns of the matrix
    _primary1 = [
      matrixModel.matrix[0][0],
      matrixModel.matrix[1][0],
      matrixModel.matrix[2][0]
    ];
    _primary2 = [
      matrixModel.matrix[0][1],
      matrixModel.matrix[1][1],
      matrixModel.matrix[2][1]
    ];
    _primary3 = [
      matrixModel.matrix[0][2],
      matrixModel.matrix[1][2],
      matrixModel.matrix[2][2]
    ];
  }

  void _syncSlidersFromPrimaries() {
    // Extract slider values from current primaries using rgbToWheelCoords
    final coords1 = rgbToWheelCoords(_primary1);
    final coords2 = rgbToWheelCoords(_primary2);
    final coords3 = rgbToWheelCoords(_primary3);
    _slider1 = coords1[2]; // The 's' component
    _slider2 = coords2[2];
    _slider3 = coords3[2];
  }

  double _getSliderForPrimary(int index) {
    switch (index) {
      case 0:
        return _slider1;
      case 1:
        return _slider2;
      case 2:
        return _slider3;
      default:
        return 0.0;
    }
  }

  void _setSliderForPrimary(int index, double value) {
    switch (index) {
      case 0:
        _slider1 = value;
      case 1:
        _slider2 = value;
      case 2:
        _slider3 = value;
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
      // Send OSC message to update colorspace on device
      sendOsc('Custom', address: '/analog_format/colorspace');
    }
  }

  void _handleWheelDrag(Offset pos, double size, int primaryIndex,
      Offset globalPos, Offset localOrigin) {
    final sliderValue = _getSliderForPrimary(primaryIndex);
    final rgb = wheelPositionToRgb(pos, size, sliderValue);

    setState(() {
      _draggingWheelIndex = primaryIndex;
      _dragGlobalPosition = globalPos; // Use actual mouse position, not clamped
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
    final adcBias = _getCurrentRequiredAdcBias();
    final rgb = _draggingWheelIndex == 0
        ? _primary1
        : _draggingWheelIndex == 1
            ? _primary2
            : _primary3;

    // Position so the circle CENTER is at the cursor position
    // Bar layout: [leftPadding][circle 16px][gap][text][gap][bar]
    // Circle center is at leftPadding + circleRadius from bar's left edge
    const barHeight = 28.0;
    const circleRadius = 8.0;
    const leftPadding = 6.0;
    const circleCenterFromLeft = leftPadding + circleRadius; // 14px

    return Positioned(
      left: _dragGlobalPosition.dx - circleCenterFromLeft,
      top: _dragGlobalPosition.dy - barHeight / 2,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: _buildKappaOverlay(kappa, adcBias, rgb),
        ),
      ),
    );
  }

  void _handleSliderChange(int primaryIndex, double newValue) {
    // Get current wheel position (a, b) from the primary
    final primary = primaryIndex == 0
        ? _primary1
        : (primaryIndex == 1 ? _primary2 : _primary3);
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
      _dragMode = 0;
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

  double _getCurrentRequiredAdcBias() {
    final matrix = [
      [_primary1[0], _primary2[0], _primary3[0]],
      [_primary1[1], _primary2[1], _primary3[1]],
      [_primary1[2], _primary2[2], _primary3[2]],
    ];
    return computeRequiredAdcBias(matrix);
  }

  Widget _buildKappaOverlay(double kappa, double adcBias, List<double> rgb) {
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
    final Color kappaTextColor;
    if (kappa <= 4) {
      kappaTextColor = const Color(0xFF4CAF50); // Green
    } else if (kappa <= 15) {
      kappaTextColor = const Color(0xFFF0B830); // Yellow/amber
    } else {
      kappaTextColor = const Color(0xFFF44336); // Red
    }

    // ADC bias warning - check if it exceeds hardware limit
    return Container(
      height: barHeight,
      padding: const EdgeInsets.only(left: 6, right: 8),
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(barHeight / 2), // Semicircle on left
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
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'Courier',
              fontFamilyFallback: const ['Courier New', 'monospace'],
              color: kappaTextColor,
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

  /// The RGB readout style. Shared so the wheel-group geometry can ask a
  /// TextPainter for this exact type's descent rather than assuming one.
  TextStyle _rgbTextStyle(BuildContext context) => TextStyle(
        fontSize: 0.9 * GridProvider.of(context).u,
        fontFamily: 'Courier',
        fontFamilyFallback: const ['Courier New', 'monospace'],
      );

  Widget _buildColorWheel(BuildContext context, String label, int primaryIndex,
      List<double> rgb, List<double> other1, List<double> other2) {
    // Scales with the grid unit so the wheels grow with the window and stay
    // legible on high-density tablet screens. 8.4u reproduces the old fixed
    // 105px at the u this was originally drawn against.
    final totalSize = 8.4 * GridProvider.of(context).u;
    final arcWidth = 0.72 * GridProvider.of(context).u;
    const arcGap = 2.0; // Gap between arc and wheel
    final sliderValue = _getSliderForPrimary(primaryIndex);

    // Label color matches the primary's RGB value (clamped for display)
    final labelColor = Color.fromRGBO(
      (rgb[0].clamp(0, 1) * 255).round(),
      (rgb[1].clamp(0, 1) * 255).round(),
      (rgb[2].clamp(0, 1) * 255).round(),
      1,
    );

    // Channel 2 (primaryIndex == 1) has flipped layout: RGB on top, wheel on bottom
    final bool isFlipped = primaryIndex == 1;

    // DragArea so the wheel drag wins over the scrolling page on touch.
    final wheelWidget = DragArea(
      onPointerDown: (p, g) => _handleCombinedDrag(
          p, totalSize, arcWidth, arcGap, primaryIndex, g, g - p,
          isStart: true),
      onDragUpdate: (p, g) => _handleCombinedDrag(
          p, totalSize, arcWidth, arcGap, primaryIndex, g, g - p,
          isStart: false),
      onDragEnd: _handleWheelDragEnd,
      onTap: (_, __) => _handleWheelDragEnd(),
      child: CustomPaint(
        size: Size(totalSize, totalSize),
        painter: _WheelWithArcPainter(
          rgb: rgb,
          other1: other1,
          other2: other2,
          wheelIndex: primaryIndex,
          sliderValue: sliderValue,
          arcWidth: arcWidth,
          arcGap: arcGap,
        ),
      ),
    );

    final u = GridProvider.of(context).u;
    final labelWidget = Text(label,
        style: TextStyle(
            fontSize: 1.1 * u, color: labelColor, fontWeight: FontWeight.w700));

    final rgbWidget = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${rgb[0] >= 0 ? '+' : ''}${rgb[0].toStringAsFixed(2)}',
          style:
              _rgbTextStyle(context).copyWith(color: const Color(0xFFFF6B6B)),
        ),
        Text(
          '${rgb[1] >= 0 ? '+' : ''}${rgb[1].toStringAsFixed(2)}',
          style:
              _rgbTextStyle(context).copyWith(color: const Color(0xFF69DB7C)),
        ),
        Text(
          '${rgb[2] >= 0 ? '+' : ''}${rgb[2].toStringAsFixed(2)}',
          style:
              _rgbTextStyle(context).copyWith(color: const Color(0xFF74C0FC)),
        ),
      ],
    );

    // Ch1 hugs the left edge and Ch3 the right, so their captions lean AWAY
    // from Channel 2's wheel. Centred captions were what forced step >= 0.8*d;
    // this is what lets the columns close up further.
    final cross = primaryIndex == 0
        ? CrossAxisAlignment.start
        : (primaryIndex == 2
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.center);

    if (isFlipped) {
      // Channel 2: RGB on top, label in middle, wheel on bottom
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: cross,
        children: [
          rgbWidget,
          const SizedBox(height: 2),
          labelWidget,
          const SizedBox(height: 4),
          wheelWidget,
        ],
      );
    } else {
      // Channels 1 & 3: Wheel on top, label in middle, RGB on bottom
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: cross,
        children: [
          wheelWidget,
          const SizedBox(height: 4),
          // Label and readout form one block that hugs the outer edge together,
          // with the numbers centred under the label rather than flush to that
          // edge — the caption reads as a unit instead of two ragged columns.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              labelWidget,
              const SizedBox(height: 2),
              rgbWidget,
            ],
          ),
        ],
      );
    }
  }

  void _handleCombinedDrag(Offset pos, double totalSize, double arcWidth,
      double arcGap, int primaryIndex, Offset globalPos, Offset localOrigin,
      {required bool isStart}) {
    final center = Offset(totalSize / 2, totalSize / 2);
    final offset = pos - center;
    final dist = offset.distance;
    final outerRadius = totalSize / 2;
    final innerRadius = outerRadius - arcWidth - arcGap; // Arc + gap

    // On drag start, determine and lock the mode
    if (isStart) {
      _dragMode = dist > innerRadius ? 2 : 1; // 2 = arc, 1 = wheel
    }

    if (_dragMode == 2) {
      // Dragging on arc - adjust intensity based on angle
      // Arc uses same convention as rotary knob: startAngle = 0.75π, sweepAngle = 1.5π
      // This gives 270° arc from 135° to 405° (bottom dead zone)
      const startAngle = 0.75 * pi; // 135°
      const sweepAngle = 1.5 * pi; // 270°

      // Get angle of drag position (canvas coords: 0 = right, increases clockwise)
      var angle = atan2(offset.dy, offset.dx);

      // Normalize angle to be relative to startAngle
      var relAngle = angle - startAngle;
      // Wrap to [0, 2π)
      while (relAngle < 0) {
        relAngle += 2 * pi;
      }
      while (relAngle >= 2 * pi) {
        relAngle -= 2 * pi;
      }

      // Clamp to arc range
      if (relAngle > sweepAngle) {
        // In dead zone - snap to nearest end
        relAngle = relAngle < (sweepAngle + (2 * pi - sweepAngle) / 2)
            ? sweepAngle
            : 0;
      }

      // Map to normalized 0-1, then to slider -2 to +2
      final normalized = relAngle / sweepAngle;
      final sliderValue = -2.0 + normalized * 4.0; // 0 -> -2, 1 -> +2

      _handleSliderChange(primaryIndex, sliderValue.clamp(-2.0, 2.0));
      // No overlay for arc dragging - only for wheel dragging
    } else {
      // Dragging on inner wheel - adjust chromaticity
      final wheelSize = innerRadius * 2;
      // Remap position to inner wheel coordinates
      final wheelPos = Offset(
        (offset.dx / innerRadius) * (wheelSize / 2) + wheelSize / 2,
        (offset.dy / innerRadius) * (wheelSize / 2) + wheelSize / 2,
      );
      _handleWheelDrag(
          wheelPos, wheelSize, primaryIndex, globalPos, localOrigin);
    }
  }

  /// The three primaries packed as a triangle: Ch1 top-left, Ch3 top-right,
  /// Ch2 dropped to bottom-centre.
  ///
  /// A plain Row forced groupW = 3*D and left ~20% of the panel's height
  /// unused. Here the columns OVERLAP horizontally by 0.2*D each — which is
  /// safe because Channel 2 renders flipped (values above, wheel below), so its
  /// wheel sits a full caption-height lower than its neighbours' and the
  /// circles never meet. That takes the group from 3.0*D wide to 2.6*D, and
  /// since FittedBox is width-limited here, the wheels grow by the same ~13%.
  ///
  /// Each column is exactly D wide (a channel's caption is narrower than its
  /// wheel), so the offsets below are pure functions of the wheel diameter —
  /// nothing is measured and nothing is tuned.
  Widget _colorWheelsWidget(BuildContext context) {
    final d = 8.4 * GridProvider.of(context).u; // wheel diameter
    // Overlap is bounded by the CAPTIONS, not the wheels. With Ch1/Ch3 captions
    // pushed to the outer edges (see _buildColorWheel) they no longer reach
    // toward Channel 2, so the columns can close from 0.9*d to 0.78*d. That is
    // the balance point: it trades the ~10% spare height the group had into
    // width, which is the axis FittedBox was limited on. Group is 2.56*d wide
    // against a plain Row's 3.0*d.
    // A channel's caption block, as a fraction of its wheel. MEASURED against
    // the rendered card (caption 52.4 / wheel 84.8), not estimated.
    const capW = 0.618;
    // The formula below puts Channel 2's caption exactly tangent to Channel 1's
    // wheel box. A wheel's arc and glow paint slightly outside that box, so
    // tangent reads as a collision — hence explicit clearance.
    const clearance = 0.06;

    // What limits the packing is Channel 2's CAPTION, not any wheel: it sits in
    // the gap between the outer wheels, so clearing Channel 1's wheel needs
    //     step >= 0.5 + capW / 2
    // There is no `v` in that. Dropping Channel 2 relaxes it only once v >= 1*d,
    // and that makes the group 2.6*d tall — height then binds and the wheels come
    // out far smaller. So `v` is worth exactly the height left spare once the
    // group is width-limited, and no more.
    final step = (0.5 + capW / 2 + clearance) * d;
    // Channel 2 drops below the outer wheels.
    final v = 0.1 * d;

    Widget at(double left, Widget child) =>
        Padding(padding: EdgeInsets.only(left: left), child: child);

    // Channels 1 and 3 are the only NON-positioned children, so they alone size
    // the Stack. Channel 2 is Positioned and therefore contributes nothing to
    // that size: dropping it by `v` moves it without growing the group's box,
    // which is what kept the enclosing FittedBox from rescaling every wheel.
    return Stack(
      alignment: Alignment.topLeft,
      clipBehavior: Clip.none,
      children: [
        at(
            0,
            _buildColorWheel(
                context, 'Channel 1', 0, _primary1, _primary2, _primary3)),
        at(
            2 * step,
            _buildColorWheel(
                context, 'Channel 3', 2, _primary3, _primary1, _primary2)),
        Positioned(
          left: step,
          top: v,
          child: _buildColorWheel(
              context, 'Channel 2', 1, _primary2, _primary1, _primary3),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── Layout ─────────────────────────────────────────────────────────────
    //
    // No coordinates. The previous version positioned every element by hand in
    // a Stack, which meant each constant was only correct at the one window
    // size it was tuned against — at 1200x800 the wheels landed on top of the
    // format column. Everything here is decided by Row/Column/Expanded, so it
    // holds at any width, and the few real numbers scale with the grid unit so
    // it holds at any pixel density too.
    final t = GridProvider.of(context);
    final u = t.u;

    // ONE gap. The distance from a field to the grey is the same relationship
    // whether it is measured across or down, so it is the same value: the grey
    // box's own padding, which is what sets the horizontal gap.
    final gap = 1.0 * u;
    final gapY = gap; // between stacked fields
    final gapX = gap; // between the Framerate and Scan/Format dropdowns
    final pad = gap; // padding inside the grey
    final radius = Radius.circular(0.9 * u);
    final grey = Colors.grey[700]!;

    // One width drives the whole format column: Resolution and Colorspace take
    // it, and the Framerate + Scan/Format pair divides it exactly, so all three
    // rows share an edge by construction rather than by coincidence.
    // 17u is the narrowest that fits "Progressive" plus its chevron in the
    // mode dropdown at this value size. Because both the width and the font
    // scale with u, that relationship holds at every window size and density.
    // An OscDropdown is as wide as its label OR its button, whichever is
    // greater. So the two buttons must each clear their own label, or the row
    // silently grows past fieldW and Resolution stops lining up with
    // Scan/Format's right edge. Measured proportionally: "Framerate" is ~6.1u
    // and "Scan / Format" ~10.5u at this label size, and both scale with u, so
    // these hold at every window size.
    final framerateW = 6.5 * u;
    final modeW = 11.0 * u;
    final fieldW = framerateW + gapX + modeW;
    // OscDropdown's default value size is 13. 1.3*u reproduces that here and
    // keeps scaling, so these fields no longer read smaller than every other
    // dropdown in the app.
    final valueFontSize = 1.3 * u;

    Widget resolution = OscDropdown<String>(
      label: 'Resolution',
      items: resolutions,
      defaultValue: resolutions[0],
      enabled: _formatControlsEnabled,
      // Must be passed, not wrapped: OscDropdown applies its own `width`
      // (default 160) to the button, so a SizedBox around it does nothing.
      width: fieldW,
      valueFontSize: valueFontSize,
    );

    Widget framerateRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OscDropdown<double>(
          label: 'Framerate',
          items: framerates,
          defaultValue: framerates[0],
          enabled: _formatControlsEnabled,
          width: framerateW,
          valueFontSize: valueFontSize,
        ),
        SizedBox(width: gapX),
        _AnalogFormatModeDropdown(
          enabled: _formatControlsEnabled,
          width: modeW,
          valueFontSize: valueFontSize,
        ),
      ],
    );

    Widget colorspace = OscDropdown<String>(
      key: ValueKey('colorspace_$selectedColorspace'),
      label: 'Colorspace',
      items: colorspaces,
      defaultValue: selectedColorspace,
      width: fieldW,
      valueFontSize: valueFontSize,
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
              final primary =
                  col == 0 ? _primary1 : (col == 1 ? _primary2 : _primary3);
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
    );

    // The grey "L" is two boxes that touch: the Colorspace box at the bottom
    // left, and the wheels box down the right spanning the FULL card height.
    // Because they share an edge with no gap between them, they read as one
    // continuous L. Corners are rounded only where the shape actually turns.
    // The L's inner corner is reentrant, so BorderRadius cannot round it.
    // Painted here instead: this box's own top-right corner IS that corner, at
    // (size.width, 0), so the fillet needs no measurement and no constants
    // shared with anything else.
    final colorspaceBox = CustomPaint(
      foregroundPainter: null,
      painter: _LCornerFillet(color: grey, r: radius.x),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: grey,
          borderRadius: BorderRadius.only(topLeft: radius, bottomLeft: radius),
        ),
        child: Padding(
          // Symmetric by construction — "equal above and below" as layout, not
          // as arithmetic to be re-checked against a screenshot. The `pad` on
          // the left is what puts the Colorspace dropdown on the same edge as
          // Resolution and Framerate while the grey still wraps it: the box
          // starts a `pad` further left than they do (see the Column below).
          padding: EdgeInsets.all(pad),
          child: colorspace,
        ),
      ),
    );

    final wheelsBox = DecoratedBox(
      decoration: BoxDecoration(
        color: grey,
        borderRadius: BorderRadius.only(
            topLeft: radius, topRight: radius, bottomRight: radius),
      ),
      child: Padding(
        padding: EdgeInsets.all(pad),
        // NO Center here. Center passes LOOSE constraints, and a FittedBox
        // under loose constraints sizes itself to its child — so BoxFit.contain
        // silently degrades to scaleDown and the wheels can only ever shrink,
        // never grow into the panel. Taking the tight constraints straight from
        // the stretched Expanded is what makes `contain` actually contain.
        child: FittedBox(
          fit: BoxFit.contain,
          child: _colorWheelsWidget(context),
        ),
      ),
    );

    return OscPathSegment(
      segment: 'analog_format',
      child: LabeledCard(
        title: 'Analog Send/Return Format',
        // Not CardBody: the grey L has to start a `pad` to the LEFT of the
        // content edge so it can wrap the Colorspace dropdown while that
        // dropdown still lines up with Resolution and Framerate above it. So
        // the grey boxes sit at 0 here and the plain fields are inset by pad,
        // which lands them on exactly the content edge (pad == cardBodyInset).
        child: Padding(
          padding: EdgeInsets.only(right: t.cardBodyInset),
          child: IntrinsicHeight(
            child: Row(
              // stretch: the wheels box takes the full height the three
              // stacked fields define, so the L has no dead space in it.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                        padding: EdgeInsets.only(left: pad), child: resolution),
                    SizedBox(height: gapY),
                    Padding(
                        padding: EdgeInsets.only(left: pad),
                        child: framerateRow),
                    SizedBox(height: gapY),
                    colorspaceBox,
                  ],
                ),
                // No gap: the two grey boxes must touch to form one L.
                Expanded(child: wheelsBox),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fills the L's reentrant corner with a concave quarter-round.
///
/// Drawn relative to the Colorspace box's own top-right corner — (size.width,
/// 0) — and painted `r` above it, into the notch between the band's top edge
/// and the wheels box's left edge. Because it is anchored to the box that
/// forms the corner, it stays correct at any size with no shared constants.
class _LCornerFillet extends CustomPainter {
  final Color color;
  final double r;

  _LCornerFillet({required this.color, required this.r});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, -r)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - r, 0)
      ..arcToPoint(
        Offset(size.width, -r),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LCornerFillet old) =>
      old.color != color || old.r != r;
}

enum _AnalogFormatMode { progressive, interlaced, composite }

class _AnalogFormatModeDropdown extends StatefulWidget {
  final bool enabled;
  final double width;
  final double valueFontSize;

  const _AnalogFormatModeDropdown({
    required this.enabled,
    this.width = 110,
    this.valueFontSize = 13,
  });

  @override
  State<_AnalogFormatModeDropdown> createState() =>
      _AnalogFormatModeDropdownState();
}

class _AnalogFormatModeDropdownState extends State<_AnalogFormatModeDropdown>
    with OscAddressMixin {
  static const String _interlacedAddr = '/analog_format/interlaced';
  static const String _compositeAddr = '/analog_format/composite';

  bool _interlaced = false;
  bool _composite = false;
  bool _listenersRegistered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listenersRegistered) return;
    _listenersRegistered = true;
    final reg = OscRegistry();
    reg.registerAddress(_interlacedAddr);
    reg.registerAddress(_compositeAddr);
    reg.registerListener(_interlacedAddr, _onInterlaced);
    reg.registerListener(_compositeAddr, _onComposite);
    // Seed from any value already cached in the registry.
    _interlaced =
        _boolFrom(reg.allParams[_interlacedAddr]?.currentValue) ?? _interlaced;
    _composite =
        _boolFrom(reg.allParams[_compositeAddr]?.currentValue) ?? _composite;
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    reg.unregisterListener(_interlacedAddr, _onInterlaced);
    reg.unregisterListener(_compositeAddr, _onComposite);
    super.dispose();
  }

  // This widget drives sub-addresses directly; its own address is unused.
  @override
  OscStatus onOscMessage(List<Object?> args) => OscStatus.ok;

  void _onInterlaced(List<Object?> args) {
    final v = _boolFrom(args);
    if (v != null && v != _interlaced && mounted) {
      setState(() => _interlaced = v);
    }
  }

  void _onComposite(List<Object?> args) {
    final v = _boolFrom(args);
    if (v != null && v != _composite && mounted) {
      setState(() => _composite = v);
    }
  }

  static bool? _boolFrom(List<Object?>? args) {
    if (args == null || args.isEmpty) return null;
    final v = args.first;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toUpperCase();
    if (s == 'T' || s == 'TRUE' || s == '1') return true;
    if (s == 'F' || s == 'FALSE' || s == '0') return false;
    return null;
  }

  _AnalogFormatMode get _mode {
    if (_composite) return _AnalogFormatMode.composite;
    if (_interlaced) return _AnalogFormatMode.interlaced;
    return _AnalogFormatMode.progressive;
  }

  void _select(_AnalogFormatMode mode) {
    final bool composite = mode == _AnalogFormatMode.composite;
    // Composite is always interlaced; otherwise follow the explicit choice.
    final bool interlaced = composite || mode == _AnalogFormatMode.interlaced;
    setState(() {
      _composite = composite;
      _interlaced = interlaced;
    });
    sendOsc(interlaced, address: _interlacedAddr);
    sendOsc(composite, address: _compositeAddr);
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicDropdown<_AnalogFormatMode>(
      label: 'Scan / Format',
      width: widget.width,
      valueFontSize: widget.valueFontSize,
      enabled: widget.enabled,
      value: _mode,
      items: const [
        _AnalogFormatMode.progressive,
        _AnalogFormatMode.interlaced,
        _AnalogFormatMode.composite,
      ],
      itemLabels: const {
        _AnalogFormatMode.progressive: 'Progressive',
        _AnalogFormatMode.interlaced: 'Interlaced',
        _AnalogFormatMode.composite: 'Composite',
      },
      onChanged: _select,
    );
  }
}

/// Draws L-shape using two overlapping rounded rectangles with lighting
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
      notchPath.quadraticBezierTo(leftBaseX, barY,
          leftBaseX + cornerRadius * 0.7, barY - cornerRadius * 0.7);
      notchPath.lineTo(snapX, tipY);
      notchPath.lineTo(
          rightBaseX - cornerRadius * 0.7, barY - cornerRadius * 0.7);
      notchPath.quadraticBezierTo(
          rightBaseX, barY, rightBaseX + cornerRadius, barY);
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
        Rect.fromLTWH(-1, barY - notchDepth - 1, size.width + 2,
            barHeight + notchDepth + 2),
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
          Rect.fromLTWH(
              0, barY - notchDepth, valueWidth, barHeight + notchDepth),
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
      canvas.drawLine(
          Offset(midSegStart, barY), Offset(midSegEnd, barY), topEdgePaint);
    }

    // Right segment (after κ=15 notch)
    final rightSegStart = notch15X + notchHalfWidth + cornerRadius;
    if (rightSegStart < size.width) {
      canvas.drawLine(
          Offset(rightSegStart, barY), Offset(size.width, barY), topEdgePaint);
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

      final leftStart =
          Offset(leftBaseX + cornerRadius * 0.7, barY - cornerRadius * 0.7);
      final tip = Offset(snapX, tipY);
      final rightEnd =
          Offset(rightBaseX - cornerRadius * 0.7, barY - cornerRadius * 0.7);

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
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..strokeWidth = 0.75,
    );
  }

  @override
  bool shouldRepaint(covariant _KappaBarPainter old) =>
      old.barFraction != barFraction || old.kappa != kappa;
}

/// Painter for color wheel with intensity arc around it (rotary knob style)
class _WheelWithArcPainter extends CustomPainter {
  final List<double> rgb;
  final List<double> other1;
  final List<double> other2;
  final int wheelIndex;
  final double sliderValue;
  final double arcWidth;
  final double arcGap;

  _WheelWithArcPainter({
    required this.rgb,
    required this.other1,
    required this.other2,
    required this.wheelIndex,
    required this.sliderValue,
    required this.arcWidth,
    required this.arcGap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final arcRadius = outerRadius - arcWidth / 2;
    final slotInnerRadius = outerRadius - arcWidth;
    final wheelRadius = slotInnerRadius - arcGap;

    // Neumorphic slot + bipolar intensity arc, using the shared treatment
    // (rounded slot ends, groove-wall lip, value-colour glow, rounded fill at
    // the extremes) — matching the rotary knobs and luma slot.
    paintArcSlot(canvas, center, outerRadius, arcRadius, slotInnerRadius);
    const Color activeColor = Color(0xFFF0B830);
    // sliderValue: -2..+2, neutral at 0 → normalized 0..1 with 0.5 = neutral.
    final normalized = (sliderValue + 2.0) / 4.0;
    paintBipolarArc(
        canvas, center, arcRadius, outerRadius, normalized, activeColor);

    // === DRAW INNER WHEEL ===
    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: wheelRadius)));

    final wheelPainter = ColorWheelPainter(
      rgb,
      other1,
      other2,
      wheelIndex,
      sliderValue: sliderValue,
      isCompact: true,
    );

    // Scale and translate to fit in the inner area
    final wheelDiameter = wheelRadius * 2;
    final scale = wheelDiameter / size.width;
    canvas.translate(center.dx - wheelRadius, center.dy - wheelRadius);
    canvas.scale(scale);
    wheelPainter.paint(canvas, Size(size.width, size.height));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WheelWithArcPainter old) =>
      old.rgb != rgb || old.sliderValue != sliderValue;
}
