// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_registry.dart';
import 'osc_radiolist.dart';

import 'color_space_matrix.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'labeled_card.dart';
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
  bool fullRange = true; // true = Full range (0-255), false = Legal (16-235)
  bool interlaced = false; // true = Interlaced, false = Progressive

  final List<List<GlobalKey<OscRotaryKnobState>>> knobKeys = List.generate(
    3,
    (_) => List.generate(3, (_) => GlobalKey<OscRotaryKnobState>()),
  );

  bool _updatingFromPreset = false;

  @override
  void initState() {
    super.initState();

    matrixModel = ColorSpaceMatrix([
      [1.0, 0.0, 0.0],
      [0.0, 1.0, 0.0],
      [0.0, 0.0, 1.0],
    ]);

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
    if (space == 'YUV') {
      return [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
      ];
    } else if (space == 'RGB') {
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

  Widget _matrixWidget() {
    return OscPathSegment(
      segment: 'color_matrix',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (row) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (col) {
              return Padding(
                padding: const EdgeInsets.all(2),
                child: OscPathSegment(
                  segment: '$row/$col',
                  child: OscRotaryKnob(
                    key: knobKeys[row][col],
                    initialValue: matrixModel.getCell(row, col),
                    minValue: -2.0,
                    maxValue: 2.0,
                    format: '%.3f',
                    label: '',
                    defaultValue: row == col ? 1.0 : 0.0,
                    size: 45,
                    sendOsc: false,
                    isBipolar: true,
                    snapConfig: SnapConfig(
                      snapPoints: const [0.0, 1.0, -1.0],
                      snapRegionHalfWidth: 0.08,
                      snapBehavior: SnapBehavior.hard,
                    ),
                    onChanged: (newValue) {
                      if (_updatingFromPreset) return;
                      setState(() {
                        matrixModel.updateCell(row, col, newValue);
                        matrixModel.correctMatrix(row, col);
                        if (selectedColorspace != 'Custom') {
                          selectedColorspace = 'Custom';
                        }
                      });
                      _sendColorMatrix();
                    },
                  ),
                ),
              );
            }),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'analog_format',
      child: LabeledCard(
        title: 'Analog Send/Return Format',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Dropdowns first
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OscDropdown<String>(
                      label: 'Resolution',
                      items: resolutions,
                      defaultValue: resolutions[0],
                      enabled: _formatControlsEnabled,
                    ),
                    const SizedBox(height: 16),
                    OscDropdown<double>(
                      label: 'Framerate',
                      items: framerates,
                      defaultValue: framerates[0],
                      enabled: _formatControlsEnabled,
                    ),
                    if (!_formatControlsEnabled) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 180,
                        child: Text(
                          'Autodetecting from external source',
                          style: TextStyle(
                            fontSize: 19,
                            height: 0.9,
                            color: Colors.grey[400],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Transform.translate(
                      offset: const Offset(-8, 0),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 8, 48, 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: SizedBox(
                          width: 180,
                          child: OscDropdown<String>(
                            label: 'Colorspace',
                            items: colorspaces,
                            defaultValue: colorspaces[0],
                            onChanged: (value) {
                              setState(() {
                                selectedColorspace = value;
                                _updatingFromPreset = true;
                                matrixModel = ColorSpaceMatrix(
                                    getMatrixForColorspace(value));

                                final matrix = getMatrixForColorspace(value);
                                for (int i = 0; i < 3; i++) {
                                  for (int j = 0; j < 3; j++) {
                                    knobKeys[i][j].currentState
                                        ?.setValue(matrix[i][j], emit: false);
                                  }
                                }
                                _updatingFromPreset = false;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Quantization range radio buttons
                    Transform.translate(
                      offset: const Offset(-8, 0),
                      child: SizedBox(
                        width: 196, // Match dropdown width + padding
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[700],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: OscPathSegment(
                            segment: 'full_range',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Quantization Range',
                                  style: TextStyle(
                                    fontSize: 20,
                                    height: 0.9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                NeumorphicRadio<bool>(
                                  value: true,
                                  groupValue: fullRange,
                                  label: 'Full range (0-255)',
                                  size: 16,
                                  onChanged: (value) {
                                    setState(() => fullRange = value);
                                    sendOsc(true, address: '/analog_format/full_range');
                                  },
                                ),
                                const SizedBox(height: 6),
                                NeumorphicRadio<bool>(
                                  value: false,
                                  groupValue: fullRange,
                                  label: 'Legal (16-235)',
                                  size: 16,
                                  onChanged: (value) {
                                    setState(() => fullRange = value);
                                    sendOsc(false, address: '/analog_format/full_range');
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Interlaced checkbox
/*                    Transform.translate(
                      offset: const Offset(-8, 0),
                      child: SizedBox(
                        width: 196,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[700],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: OscPathSegment(
                            segment: 'interlaced',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OscCheckbox(
                                  initialValue: interlaced,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Interlaced\n(Experimental)',
                                  style: TextStyle(
                                    fontSize: 20,
                                    height: 0.9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    */
                  ],
                ),
                // Matrix second
                Transform.translate(
                  offset: const Offset(-40, 0),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: _matrixWidget(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
