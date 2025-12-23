import 'dart:math';
import 'package:flutter/material.dart';

import 'color_wheel.dart';
import 'color_space_matrix.dart';

class ColorPrimariesPage extends StatefulWidget {
  const ColorPrimariesPage({super.key});

  @override
  State<ColorPrimariesPage> createState() => _ColorPrimariesPageState();
}

class _ColorPrimariesPageState extends State<ColorPrimariesPage> {
  late ColorSpaceMatrix matrixModel;

  final List<String> colorspaces = ['RGB', 'YUV', 'Custom'];
  String selectedColorspace = 'YUV';

  // Primaries (columns of the matrix)
  List<double> _primary1 = [1, 0, 0];
  List<double> _primary2 = [0, 1, 0];
  List<double> _primary3 = [0, 0, 1];

  // Saved custom primaries
  List<double> _customPrimary1 = [1, 0, 0];
  List<double> _customPrimary2 = [0, 1, 0];
  List<double> _customPrimary3 = [0, 0, 1];

  // Slider values for each wheel
  double _slider1 = 0.0;
  double _slider2 = 0.0;
  double _slider3 = 0.0;


  @override
  void initState() {
    super.initState();
    matrixModel = ColorSpaceMatrix(_getMatrixForColorspace('YUV'));
    _syncPrimariesFromMatrix();
    _syncSlidersFromPrimaries();
  }

  List<List<double>> _getMatrixForColorspace(String space) {
    if (space == 'RGB') {
      return [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
      ];
    } else if (space == 'YUV') {
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

  void _syncPrimariesFromMatrix() {
    _primary1 = [matrixModel.matrix[0][0], matrixModel.matrix[1][0], matrixModel.matrix[2][0]];
    _primary2 = [matrixModel.matrix[0][1], matrixModel.matrix[1][1], matrixModel.matrix[2][1]];
    _primary3 = [matrixModel.matrix[0][2], matrixModel.matrix[1][2], matrixModel.matrix[2][2]];
  }

  void _syncSlidersFromPrimaries() {
    final coords1 = rgbToWheelCoords(_primary1);
    final coords2 = rgbToWheelCoords(_primary2);
    final coords3 = rgbToWheelCoords(_primary3);
    _slider1 = coords1[2];
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

  List<double> _getPrimary(int index) {
    switch (index) {
      case 0: return _primary1;
      case 1: return _primary2;
      case 2: return _primary3;
      default: return [1, 1, 1];
    }
  }

  void _setPrimary(int index, List<double> value) {
    switch (index) {
      case 0: _primary1 = value; break;
      case 1: _primary2 = value; break;
      case 2: _primary3 = value; break;
    }
  }

  void _updateMatrixFromPrimary(int primaryIndex, List<double> rgb) {
    for (int row = 0; row < 3; row++) {
      matrixModel.updateCell(row, primaryIndex, rgb[row]);
    }
    _customPrimary1 = List.from(_primary1);
    _customPrimary2 = List.from(_primary2);
    _customPrimary3 = List.from(_primary3);
    if (selectedColorspace != 'Custom') {
      selectedColorspace = 'Custom';
    }
  }

  void _handleWheelDrag(Offset pos, double size, int primaryIndex) {
    final sliderValue = _getSliderForPrimary(primaryIndex);
    final rgb = wheelPositionToRgb(pos, size, sliderValue);

    setState(() {
      _setPrimary(primaryIndex, rgb);
      _updateMatrixFromPrimary(primaryIndex, rgb);
    });
  }

  void _handleSliderChange(int primaryIndex, double newValue) {
    final primary = _getPrimary(primaryIndex);
    final coords = rgbToWheelCoords(primary);
    final a = coords[0];
    final b = coords[1];
    final rgb = wheelCoordsToRgb(a, b, newValue);

    setState(() {
      _setSliderForPrimary(primaryIndex, newValue);
      _setPrimary(primaryIndex, rgb);
      _updateMatrixFromPrimary(primaryIndex, rgb);
    });
  }

  double _getConditionNumber() {
    final matrix = [
      [_primary1[0], _primary2[0], _primary3[0]],
      [_primary1[1], _primary2[1], _primary3[1]],
      [_primary1[2], _primary2[2], _primary3[2]],
    ];
    return _computeConditionNumber(matrix);
  }

  double _computeConditionNumber(List<List<double>> m) {
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

  Widget _buildColorWheel(int primaryIndex, String label) {
    const double wheelSize = 180.0;
    final rgb = _getPrimary(primaryIndex);
    final sliderValue = _getSliderForPrimary(primaryIndex);

    // Get other primaries for heatmap
    final other1 = _getPrimary((primaryIndex + 1) % 3);
    final other2 = _getPrimary((primaryIndex + 2) % 3);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey[300],
          ),
        ),
        const SizedBox(height: 12),

        // Wheel
        GestureDetector(
          onPanStart: (d) => _handleWheelDrag(d.localPosition, wheelSize, primaryIndex),
          onPanUpdate: (d) => _handleWheelDrag(d.localPosition, wheelSize, primaryIndex),
          onTapDown: (d) => _handleWheelDrag(d.localPosition, wheelSize, primaryIndex),
          child: CustomPaint(
            size: const Size(wheelSize, wheelSize),
            painter: ColorWheelPainter(
              rgb, other1, other2, primaryIndex,
              sliderValue: sliderValue,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Intensity slider
        SizedBox(
          width: wheelSize,
          child: Row(
            children: [
              Text('Dark', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    activeTrackColor: Colors.grey[400],
                    inactiveTrackColor: Colors.grey[700],
                    thumbColor: Colors.grey[300],
                  ),
                  child: Slider(
                    value: sliderValue.clamp(-2.0, 2.0),
                    min: -2.0,
                    max: 2.0,
                    onChanged: (v) => _handleSliderChange(primaryIndex, v),
                  ),
                ),
              ),
              Text('Bright', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Slider value display
        Text(
          'Intensity: ${sliderValue.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        const SizedBox(height: 12),

        // RGB values
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _buildRgbRow('R', rgb[0], const Color(0xFFFF6B6B)),
              const SizedBox(height: 4),
              _buildRgbRow('G', rgb[1], const Color(0xFF69DB7C)),
              const SizedBox(height: 4),
              _buildRgbRow('B', rgb[2], const Color(0xFF74C0FC)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRgbRow(String channel, double value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          child: Text(
            channel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        Text(
          '${value >= 0 ? '+' : ''}${value.toStringAsFixed(3)}',
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Courier',
            fontFamilyFallback: const ['Courier New', 'monospace'],
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final kappa = _getConditionNumber();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with preset dropdown and condition number
            Row(
              children: [
                // Preset dropdown
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedColorspace,
                    decoration: InputDecoration(
                      labelText: 'Preset',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: colorspaces.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedColorspace = value;
                        if (value == 'Custom') {
                          _primary1 = List.from(_customPrimary1);
                          _primary2 = List.from(_customPrimary2);
                          _primary3 = List.from(_customPrimary3);
                          for (int col = 0; col < 3; col++) {
                            final primary = _getPrimary(col);
                            for (int row = 0; row < 3; row++) {
                              matrixModel.updateCell(row, col, primary[row]);
                            }
                          }
                        } else {
                          matrixModel = ColorSpaceMatrix(_getMatrixForColorspace(value));
                          _syncPrimariesFromMatrix();
                        }
                        _syncSlidersFromPrimaries();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 24),

                // Condition number display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: kappa < 3 ? Colors.green.withValues(alpha: 0.2) :
                           kappa < 10 ? Colors.yellow.withValues(alpha: 0.2) :
                           kappa < 100 ? Colors.orange.withValues(alpha: 0.2) :
                           Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: kappa < 3 ? Colors.green :
                             kappa < 10 ? Colors.yellow :
                             kappa < 100 ? Colors.orange :
                             Colors.red,
                    ),
                  ),
                  child: Text(
                    'Condition Number (κ): ${kappa.isFinite ? kappa.toStringAsFixed(2) : '∞'}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kappa < 3 ? Colors.green[300] :
                             kappa < 10 ? Colors.yellow[300] :
                             kappa < 100 ? Colors.orange[300] :
                             Colors.red[300],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Color wheels
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildColorWheel(0, 'Channel 1'),
                  _buildColorWheel(1, 'Channel 2'),
                  _buildColorWheel(2, 'Channel 3'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
