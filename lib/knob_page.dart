import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'rotary_knob.dart';
import 'labeled_card.dart';

class KnobPage extends StatefulWidget {
  const KnobPage({super.key});

  @override
  State<KnobPage> createState() => _KnobPageState();
}

class _KnobPageState extends State<KnobPage> {
  // Test values for various knob configurations
  double _basicValue = 0.5;
  double _bipolarValue = 0.0;
  double _precisionValue = 1.0;
  double _snappingValue = 0.0;
  double _wideRangeValue = 50.0;
  double _percentValue = 75.0;

  // Nonlinear mapping values
  double _scaleValue = 1.0;  // 0x to 4x, neutral at 1x
  double _expValue = 0.0;    // exponential curve
  double _logFreqValue = 1000.0;  // log frequency

  // Soft snap tuning values
  double _softSnapDemoValue = 0.0;
  double _softSnapExponent = 2.0;  // 0.5 to 4.0
  double _softSnapRegionWidth = 0.3;  // 0.1 to 1.0

  // Light direction controls (spherical coordinates)
  double _lightPhi = 90.0;    // Azimuthal angle in degrees (0 = right, 90 = top)
  double _lightTheta = 30.0;  // Polar angle from vertical in degrees (0 = above, 90 = horizontal)

  // Arc geometry controls
  double _arcWidth = 8.0;     // Arc/slot width in pixels
  double _notchDepth = 4.0;   // Notch depth in pixels
  double _notchAngle = 3.15;  // Notch half-angle in degrees

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Basic Knobs Section
        LabeledCard(
          title: 'Basic Knobs',
          networkIndependent: true,
          child: Wrap(
            spacing: 32,
            runSpacing: 24,
            alignment: WrapAlignment.start,
            children: [
              // Simple 0-1 knob
              RotaryKnob(
                minValue: 0,
                maxValue: 1,
                value: _basicValue,
                format: '%.2f',
                label: 'Gain',
                defaultValue: 0.5,
                onChanged: (v) => setState(() => _basicValue = v),
              ),

              // Percentage knob
              RotaryKnob(
                minValue: 0,
                maxValue: 100,
                value: _percentValue,
                format: '%.0f%%',
                label: 'Mix',
                defaultValue: 50,
                onChanged: (v) => setState(() => _percentValue = v),
              ),

              // Wide range knob
              RotaryKnob(
                minValue: 0,
                maxValue: 1000,
                value: _wideRangeValue,
                format: '%.0f',
                label: 'Frequency',
                defaultValue: 100,
                size: 100,
                onChanged: (v) => setState(() => _wideRangeValue = v),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Lighting Controls Section
        LabeledCard(
          title: 'Lighting & Geometry Controls',
          networkIndependent: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 32,
                runSpacing: 24,
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  // Phi control (azimuthal angle)
                  RotaryKnob(
                    minValue: 0,
                    maxValue: 360,
                    value: _lightPhi,
                    format: '%.0f°',
                    label: 'Phi (φ)',
                    defaultValue: 90,
                    size: 70,
                    snapConfig: const SnapConfig(
                      snapPoints: [0, 90, 180, 270, 360],
                      snapRegionHalfWidth: 10,
                      snapBehavior: SnapBehavior.hard,
                    ),
                    onChanged: (v) => setState(() => _lightPhi = v),
                  ),

                  // Theta control (polar angle)
                  RotaryKnob(
                    minValue: 0,
                    maxValue: 90,
                    value: _lightTheta,
                    format: '%.0f°',
                    label: 'Theta (θ)',
                    defaultValue: 30,
                    size: 70,
                    snapConfig: const SnapConfig(
                      snapPoints: [0, 30, 45, 60, 90],
                      snapRegionHalfWidth: 5,
                      snapBehavior: SnapBehavior.hard,
                    ),
                    onChanged: (v) => setState(() => _lightTheta = v),
                  ),

                  // Arc width control
                  RotaryKnob(
                    minValue: 2,
                    maxValue: 20,
                    value: _arcWidth,
                    format: '%.1f',
                    label: 'Arc Width',
                    defaultValue: 8,
                    size: 70,
                    snapConfig: const SnapConfig(
                      snapPoints: [4, 8, 12, 16],
                      snapRegionHalfWidth: 1,
                      snapBehavior: SnapBehavior.hard,
                    ),
                    onChanged: (v) => setState(() => _arcWidth = v),
                  ),

                  // Notch depth control
                  RotaryKnob(
                    minValue: 0,
                    maxValue: 10,
                    value: _notchDepth,
                    format: '%.1f',
                    label: 'Notch Depth',
                    defaultValue: 4,
                    size: 70,
                    snapConfig: const SnapConfig(
                      snapPoints: [0, 2, 4, 6, 8],
                      snapRegionHalfWidth: 0.5,
                      snapBehavior: SnapBehavior.hard,
                    ),
                    onChanged: (v) => setState(() => _notchDepth = v),
                  ),

                  // Notch angle control
                  RotaryKnob(
                    minValue: 1,
                    maxValue: 10,
                    value: _notchAngle,
                    format: '%.1f°',
                    label: 'Notch Angle',
                    defaultValue: 3.15,
                    size: 70,
                    snapConfig: const SnapConfig(
                      snapPoints: [2, 3, 4, 5, 6],
                      snapRegionHalfWidth: 0.3,
                      snapBehavior: SnapBehavior.hard,
                    ),
                    onChanged: (v) => setState(() => _notchAngle = v),
                  ),

                  // Demo knob with dynamic lighting and geometry
                  RotaryKnob(
                    minValue: 0,
                    maxValue: 1,
                    value: _basicValue,
                    format: '%.2f',
                    label: 'Demo',
                    defaultValue: 0.5,
                    size: 100,
                    lightPhi: _lightPhi * math.pi / 180,
                    lightTheta: _lightTheta * math.pi / 180,
                    arcWidth: _arcWidth,
                    notchDepth: _notchDepth,
                    notchHalfAngle: _notchAngle * math.pi / 180,
                    snapConfig: const SnapConfig(
                      snapPoints: [0, 0.25, 0.5, 0.75, 1.0],
                      snapRegionHalfWidth: 0.03,
                      snapBehavior: SnapBehavior.hard,
                    ),
                    onChanged: (v) => setState(() => _basicValue = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Phi (φ): Azimuthal angle, 0° = right, 90° = top\n'
                  'Theta (θ): Polar angle from vertical, 0° = above, 90° = horizontal\n'
                  'Arc Width: Thickness of the slot/arc in pixels\n'
                  'Notch Depth: Height of V-notches in pixels\n'
                  'Notch Angle: Half-width of V-notches in degrees',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Bipolar Knobs Section
        LabeledCard(
          title: 'Bipolar Knobs',
          networkIndependent: true,
          child: Wrap(
            spacing: 32,
            runSpacing: 24,
            alignment: WrapAlignment.start,
            children: [
              // Bipolar -1 to +1 knob
              RotaryKnob(
                minValue: -1,
                maxValue: 1,
                value: _bipolarValue,
                format: '%+.2f',
                label: 'Pan',
                isBipolar: true,
                defaultValue: 0,
                onChanged: (v) => setState(() => _bipolarValue = v),
              ),

              // Bipolar with snap at zero
              RotaryKnob(
                minValue: -100,
                maxValue: 100,
                value: _bipolarValue * 100,
                format: '%+.0f',
                label: 'Balance',
                isBipolar: true,
                defaultValue: 0,
                snapConfig: const SnapConfig(
                  snapPoints: [0],
                  snapRegionHalfWidth: 5,
                  snapBehavior: SnapBehavior.hard,
                ),
                onChanged: (v) => setState(() => _bipolarValue = v / 100),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Precision Knobs Section
        LabeledCard(
          title: 'Precision Controls',
          networkIndependent: true,
          child: Wrap(
            spacing: 32,
            runSpacing: 24,
            alignment: WrapAlignment.start,
            children: [
              // High precision knob
              RotaryKnob(
                minValue: 0,
                maxValue: 2,
                value: _precisionValue,
                format: '%.4f',
                label: 'Fine Tune',
                defaultValue: 1.0,
                dragBarWidth: 500,
                onChanged: (v) => setState(() => _precisionValue = v),
              ),

              // Compact knob
              RotaryKnob(
                minValue: 0,
                maxValue: 10,
                value: _precisionValue * 5,
                format: '%.1f',
                label: 'Compact',
                size: 60,
                dragBarWidth: 300,
                onChanged: (v) => setState(() => _precisionValue = v / 5),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Snapping Knobs Section
        LabeledCard(
          title: 'Snapping Behavior',
          networkIndependent: true,
          child: Wrap(
            spacing: 32,
            runSpacing: 24,
            alignment: WrapAlignment.start,
            children: [
              // Hard snap at integer values
              RotaryKnob(
                minValue: -2,
                maxValue: 2,
                value: _snappingValue,
                format: '%+.1f',
                label: 'Hard Snap',
                isBipolar: true,
                defaultValue: 0,
                snapConfig: const SnapConfig(
                  snapPoints: [-2, -1, 0, 1, 2],
                  snapRegionHalfWidth: 0.2,
                  snapBehavior: SnapBehavior.hard,
                  snapHysteresisMultiplier: 1.5,
                ),
                onChanged: (v) => setState(() => _snappingValue = v),
              ),

              // Soft snap
              RotaryKnob(
                minValue: -2,
                maxValue: 2,
                value: _snappingValue,
                format: '%+.2f',
                label: 'Soft Snap',
                isBipolar: true,
                defaultValue: 0,
                snapConfig: const SnapConfig(
                  snapPoints: [-1, 0, 1],
                  snapRegionHalfWidth: 0.3,
                  snapBehavior: SnapBehavior.soft,
                  snapHysteresisMultiplier: 2.0,
                ),
                onChanged: (v) => setState(() => _snappingValue = v),
              ),

              // Many snap points
              RotaryKnob(
                minValue: 0,
                maxValue: 12,
                value: _snappingValue + 6,
                format: '%.0f',
                label: 'Semitones',
                defaultValue: 0,
                size: 100,
                snapConfig: const SnapConfig(
                  snapPoints: [0, 3, 5, 7, 12],
                  snapRegionHalfWidth: 0.5,
                  snapBehavior: SnapBehavior.hard,
                ),
                onChanged: (v) => setState(() => _snappingValue = v - 6),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Soft Snap Tuning Section
        LabeledCard(
          title: 'Soft Snap Tuning',
          networkIndependent: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 32,
                runSpacing: 24,
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  // Exponent control
                  RotaryKnob(
                    minValue: 0.25,
                    maxValue: 4,
                    value: _softSnapExponent,
                    format: '%.2f',
                    label: 'Exponent',
                    defaultValue: 2.0,
                    size: 80,
                    mappingSegments: [
                      MappingSegment.linear(t0: 0.0, t1: 0.5, v0: 0.25, v1: 2.0),
                      MappingSegment.linear(t0: 0.5, t1: 1.0, v0: 2.0, v1: 4.0),
                    ],
                    snapConfig: const SnapConfig(
                      snapPoints: [0.5, 1.0, 2.0, 3.0],
                      snapRegionHalfWidth: 0.1,
                      snapBehavior: SnapBehavior.hard,
                    ),
                    onChanged: (v) => setState(() => _softSnapExponent = v),
                  ),

                  // Region width control
                  RotaryKnob(
                    minValue: 0.1,
                    maxValue: 1.0,
                    value: _softSnapRegionWidth,
                    format: '%.2f',
                    label: 'Region',
                    defaultValue: 0.3,
                    size: 80,
                    snapConfig: const SnapConfig(
                      snapPoints: [0.25, 0.5, 0.75],
                      snapRegionHalfWidth: 0.05,
                      snapBehavior: SnapBehavior.hard,
                    ),
                    onChanged: (v) => setState(() => _softSnapRegionWidth = v),
                  ),

                  // Demo knob with soft snap
                  RotaryKnob(
                    minValue: -2,
                    maxValue: 2,
                    value: _softSnapDemoValue,
                    format: '%+.2f',
                    label: 'Demo',
                    isBipolar: true,
                    defaultValue: 0,
                    size: 100,
                    snapConfig: SnapConfig(
                      snapPoints: const [-1, 0, 1],
                      snapRegionHalfWidth: _softSnapRegionWidth,
                      snapBehavior: SnapBehavior.soft,
                      softSnapExponent: _softSnapExponent,
                      snapHysteresisMultiplier: 1.5,
                    ),
                    onChanged: (v) => setState(() => _softSnapDemoValue = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Exponent: 0.5=strong pull, 1.0=linear, 2.0=quadratic (default), 3.0+=gentle\n'
                  'Region: width of snap zone in value units\n'
                  'Tip: Hold Ctrl while dragging to bypass snapping entirely',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Nonlinear Mapping Section
        LabeledCard(
          title: 'Nonlinear Mapping',
          networkIndependent: true,
          child: Wrap(
            spacing: 32,
            runSpacing: 24,
            alignment: WrapAlignment.start,
            children: [
              // Scale knob: 0x-4x with 1x at center
              // 50% of range (0-0.5) maps 0 to 1
              // 50% of range (0.5-1) maps 1 to 4
              RotaryKnob(
                minValue: 0,
                maxValue: 4,
                value: _scaleValue,
                format: '%.2fx',
                label: 'Scale',
                isBipolar: true,
                neutralValue: 1.0,
                defaultValue: 1.0,
                size: 100,
                mappingSegments: [
                  MappingSegment.linear(t0: 0.0, t1: 0.5, v0: 0.0, v1: 1.0),
                  MappingSegment.linear(t0: 0.5, t1: 1.0, v0: 1.0, v1: 4.0),
                ],
                snapConfig: const SnapConfig(
                  snapPoints: [1.0],
                  snapRegionHalfWidth: 0.1,
                  snapBehavior: SnapBehavior.hard,
                ),
                onChanged: (v) => setState(() => _scaleValue = v),
              ),

              // Exposure compensation style: -3 to +3 EV with more resolution near 0
              RotaryKnob(
                minValue: -3,
                maxValue: 3,
                value: _expValue,
                format: '%+.1f EV',
                label: 'Exposure',
                isBipolar: true,
                neutralValue: 0,
                defaultValue: 0,
                size: 100,
                mappingSegments: [
                  // -3 to -1 in first 25%
                  MappingSegment.linear(t0: 0.0, t1: 0.25, v0: -3.0, v1: -1.0),
                  // -1 to +1 in middle 50% (more resolution near zero)
                  MappingSegment.linear(t0: 0.25, t1: 0.75, v0: -1.0, v1: 1.0),
                  // +1 to +3 in last 25%
                  MappingSegment.linear(t0: 0.75, t1: 1.0, v0: 1.0, v1: 3.0),
                ],
                snapConfig: const SnapConfig(
                  snapPoints: [-2, -1, 0, 1, 2],
                  snapRegionHalfWidth: 0.15,
                  snapBehavior: SnapBehavior.hard,
                ),
                onChanged: (v) => setState(() => _expValue = v),
              ),

              // Audio frequency with log-like response
              // 20Hz-200Hz in first 33%, 200Hz-2kHz in middle 33%, 2kHz-20kHz in last 33%
              RotaryKnob(
                minValue: 20,
                maxValue: 20000,
                value: _logFreqValue,
                format: '%.0f Hz',
                label: 'Frequency',
                defaultValue: 1000,
                size: 100,
                dragBarWidth: 500,
                mappingSegments: [
                  MappingSegment.linear(t0: 0.0, t1: 0.33, v0: 20, v1: 200),
                  MappingSegment.linear(t0: 0.33, t1: 0.66, v0: 200, v1: 2000),
                  MappingSegment.linear(t0: 0.66, t1: 1.0, v0: 2000, v1: 20000),
                ],
                snapConfig: const SnapConfig(
                  snapPoints: [100, 1000, 10000],
                  snapRegionHalfWidth: 50,
                  snapBehavior: SnapBehavior.soft,
                ),
                onChanged: (v) => setState(() => _logFreqValue = v),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Instructions
        LabeledCard(
          title: 'Usage Instructions',
          networkIndependent: true,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _instructionRow('Click and drag horizontally', 'Adjust value with drag bar'),
                _instructionRow('Double-tap', 'Reset to default value'),
                _instructionRow('Slow drag', 'Bypass snap points'),
                _instructionRow('Fast drag', 'Snap briefly when crossing snap points'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Current Values Display
        LabeledCard(
          title: 'Current Values',
          networkIndependent: true,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Basic: ${_basicValue.toStringAsFixed(3)}'),
                Text('Bipolar: ${_bipolarValue.toStringAsFixed(3)}'),
                Text('Precision: ${_precisionValue.toStringAsFixed(4)}'),
                Text('Snapping: ${_snappingValue.toStringAsFixed(3)}'),
                Text('Wide Range: ${_wideRangeValue.toStringAsFixed(1)}'),
                Text('Percent: ${_percentValue.toStringAsFixed(1)}%'),
                const SizedBox(height: 8),
                Text('Scale: ${_scaleValue.toStringAsFixed(2)}x'),
                Text('Exposure: ${_expValue >= 0 ? '+' : ''}${_expValue.toStringAsFixed(1)} EV'),
                Text('Frequency: ${_logFreqValue.toStringAsFixed(0)} Hz'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _instructionRow(String action, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text(
              action,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.yellow,
              ),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: TextStyle(color: Colors.grey[400]),
            ),
          ),
        ],
      ),
    );
  }
}
