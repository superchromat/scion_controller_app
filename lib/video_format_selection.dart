// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';

import 'color_space_matrix.dart';
import 'numeric_slider.dart';
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

  final List<List<GlobalKey<NumericSliderState>>> sliderKeys = List.generate(
    3,
    (_) => List.generate(3, (_) => GlobalKey<NumericSliderState>()),
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
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(80),
        children: List.generate(3, (row) {
          return TableRow(
            children: List.generate(3, (col) {
              final top = row == 0 ? 0.0 : 4.0;
              final bottom = row == 2 ? 0.0 : 4.0;
              return Padding(
                padding: EdgeInsets.fromLTRB(4, top, 4, bottom),
                child: SizedBox(
                  width: 45,
                  height: 20,
                  child: OscPathSegment(
                    segment: '$row/$col',
                    child: NumericSlider(
                      key: sliderKeys[row][col],
                      value: matrixModel.getCell(row, col),
                      sendOsc: false,
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
                    ),
                    const SizedBox(height: 16),
                    OscDropdown<double>(
                      label: 'Framerate',
                      items: framerates,
                      defaultValue: framerates[0],
                    ),
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
                                setState(() {
                                  selectedColorspace = value;
                                  _updatingFromPreset = true;
                                  matrixModel = ColorSpaceMatrix(
                                      getMatrixForColorspace(value));
                                });

                                final matrix = getMatrixForColorspace(value);
                                final futures = <Future<void>>[];

                                for (int i = 0; i < 3; i++) {
                                  for (int j = 0; j < 3; j++) {
                                    final future = sliderKeys[i][j].currentState
                                        ?.setValue(matrix[i][j]);
                                    if (future != null) futures.add(future);
                                  }
                                }

                                Future.wait(futures).then((_) {
                                  setState(() {
                                    _updatingFromPreset = false;
                                  });
                                });
                              });
                            },
                          ),
                        ),
                      ),
                    ),
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
