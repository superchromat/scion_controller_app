import 'package:flutter/material.dart';

import 'ColorSpaceMatrix.dart';
import 'ColorSpaceSelection.dart';

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
  double selectedFramerate = 60.0;
  String selectedColourspace = 'RGB';

  List<List<TextEditingController>> matrixControllers = [];

  @override
  void initState() {
    super.initState();

    matrixModel = ColorSpaceMatrix([
      [1.0, 0.0, 0.0],
      [0.0, 1.0, 0.0],
      [0.0, 0.0, 1.0],
    ]);
    _initializeMatrixControllers();
  }

  void _initializeMatrixControllers() {
    final matrix = getMatrixForColourspace(selectedColourspace);
    matrixControllers = List.generate(3, (i) {
      return List.generate(3, (j) {
        return TextEditingController(text: formatCell(matrix[i][j]));
      });
    });
  }

  void _updateMatrixControllers() {
    final matrix = getMatrixForColourspace(selectedColourspace);
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        matrixControllers[i][j].text = formatCell(matrix[i][j]);
      }
    }
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

  String formatCell(double value) {
    return "${value >= 0 ? '+' : ''}${value.toStringAsFixed(4)}";
  }

  @override
  void dispose() {
    for (var row in matrixControllers) {
      for (var controller in row) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  void _syncControllersToMatrix() {
  final corrected = matrixModel.matrix;
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      matrixControllers[i][j].text = formatCell(corrected[i][j]);
    }
  }
}

  @override
  Widget build(BuildContext context) {
    if (matrixControllers.isEmpty) {
      return const SizedBox.shrink(); // or a spinner if you want
    }
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dropdowns first
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    SizedBox(
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
                              _updateMatrixControllers();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 32),
                // Matrix second
                Table(
                  border: TableBorder.all(color: Colors.grey, width: 0.5),
                  defaultColumnWidth: const FixedColumnWidth(80),
                  children: List.generate(3, (row) {
                    return TableRow(
                      children: List.generate(3, (col) {
                        return Padding(
                          padding: const EdgeInsets.all(4),
                          child: TextFormField(
                            controller: matrixControllers[row][col],
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 14),
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                            readOnly: false,
                            onChanged: (value) {
                              final parsed = double.tryParse(value);
                              if (parsed != null) {
                                setState(() {
                                  matrixModel.updateCell(row, col, parsed);

                                  // Now correct the matrix based on the edited cell
                                  matrixModel.correctMatrix(row, col);

                                  // Update all TextEditingControllers to match corrected matrix
                                  _syncControllersToMatrix();
                                });
                              }
                            },
                          ),
                        );
                      }),
                    );
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
