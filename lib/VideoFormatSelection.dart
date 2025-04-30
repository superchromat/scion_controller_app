import 'package:flutter/material.dart';

import 'ColorSpaceMatrix.dart';
import 'NumericSlider.dart';

class VideoFormatSelectionSection extends StatefulWidget {
  const VideoFormatSelectionSection({super.key});

  @override
  State<VideoFormatSelectionSection> createState() =>
      _VideoFormatSelectionSectionState();
}

class _VideoFormatSelectionSectionState
    extends State<VideoFormatSelectionSection> {
  late ColorSpaceMatrix matrixModel;

  final List<String> resolutions = [
    '1920x1080',
    '1600x1200',
    '1280x720',
    '800x600',
    '720x576',
    '720x480',
    '640x480',
  ];

  final List<double> framerates = [
    60.0,
    50.0,
    30.0,
    25.0,
    24.0,
  ];

  final List<String> colourspaces = [
    'RGB',
    'YUV',
    'Custom',
  ];

  String selectedResolution = '1920x1080';
  double selectedFramerate = 30.0;
  String selectedColourspace = 'YUV';

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

  List<List<double>> getMatrixForColourspace(String space) {
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

  Widget _matrixWidget() {
    return Table(
      defaultColumnWidth: const FixedColumnWidth(80),
      children: List.generate(3, (row) {
        return TableRow(
          children: List.generate(3, (col) {
            return Padding(
              padding: const EdgeInsets.all(4),
              child: SizedBox(
                width: 45,
                height: 20,
                child: NumericSlider(
                  key: sliderKeys[row][col],
                  value: matrixModel.getCell(row, col),
                  onChanged: (newValue) {
                    if (_updatingFromPreset) return;
                    setState(() {
                      matrixModel.updateCell(row, col, newValue);
                      matrixModel.correctMatrix(row, col);
                      if (selectedColourspace != 'Custom') {
                        selectedColourspace = 'Custom';
                      }
                    });
                  },
                ),
              ),
            );
          }),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Video Format Selection',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Dropdowns first
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        decoration:
                            const InputDecoration(labelText: 'Resolution'),
                        value: selectedResolution,
                        style: const TextStyle(fontFamily: 'monospace'),
                        items: resolutions
                            .map((res) => DropdownMenuItem(
                                  value: res,
                                  child: Text(res),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              selectedResolution = value;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<double>(
                        decoration:
                            const InputDecoration(labelText: 'Framerate (fps)'),
                        value: selectedFramerate,
                        style: const TextStyle(fontFamily: 'monospace'),
                        items: framerates
                            .map((rate) => DropdownMenuItem(
                                  value: rate,
                                  child: Text(rate.toStringAsFixed(0)),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              selectedFramerate = value;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 8, 48, 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          decoration:
                              const InputDecoration(labelText: 'Colourspace'),
                          value: selectedColourspace,
                          items: colourspaces
                              .map((space) => DropdownMenuItem(
                                    value: space,
                                    child: Text(space),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                selectedColourspace = value;
                                _updatingFromPreset = true;
                                matrixModel = ColorSpaceMatrix(
                                    getMatrixForColourspace(value));
                              });
                        
                              final matrix = getMatrixForColourspace(value);
                              final futures = <Future<void>>[];
                        
                              for (int i = 0; i < 3; i++) {
                                for (int j = 0; j < 3; j++) {
                                  final future = sliderKeys[i][j]
                                      .currentState
                                      ?.setValue(matrix[i][j]);
                                  if (future != null) futures.add(future);
                                }
                              }
                        
                              Future.wait(futures).then((_) {
                                setState(() {
                                  _updatingFromPreset = false;
                                });
                              });
                            }
                          },
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
                      color: Colors.grey[800],
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
