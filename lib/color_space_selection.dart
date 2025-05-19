import 'package:flutter/material.dart';

class ColorSpaceSelectionSection extends StatefulWidget {
  const ColorSpaceSelectionSection({super.key});

  @override
  State<ColorSpaceSelectionSection> createState() =>
      _ColorSpaceSelectionSectionState();
}

class _ColorSpaceSelectionSectionState
    extends State<ColorSpaceSelectionSection> {
  String selectedMode = 'RGB'; // RGB, YUV, Custom
  bool studioClamp = false;

  late List<List<double>> matrix;

  @override
  void initState() {
    super.initState();
    loadMatrixForMode(selectedMode);
  }

  void loadMatrixForMode(String mode) {
    setState(() {
      if (mode == 'YUV') {
        matrix = [
          [1.0, 0.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 0.0, 1.0],
        ];
      } else if (mode == 'RGB') {
        matrix = [
          [1.0000, 0.0000, 1.5748],
          [1.0000, -0.1873, -0.4681],
          [1.0000, 1.8556, 0.0000],
        ];
      } else {
        // Custom (default to Identity)
        matrix = [
          [1.0, 0.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 0.0, 1.0],
        ];
      }
    });
  }

  void setMatrixValue(int row, int col, String value) {
    final parsed = double.tryParse(value);
    if (parsed != null) {
      setState(() {
        matrix[row][col] = parsed;
        if (selectedMode != 'Custom') {
          selectedMode = 'Custom';
        }
      });
    }
  }

  String formatCell(double value) {
    return "${value >= 0 ? '+' : ''}${value.toStringAsFixed(4)}";
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
              'Colourspace Selection',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Flexible(
                  child: RadioListTile<String>(
                    title: const Text('RGB'),
                    value: 'RGB',
                    groupValue: selectedMode,
                    onChanged: (value) {
                      if (value != null) {
                        selectedMode = value;
                        loadMatrixForMode(value);
                      }
                    },
                  ),
                ),
                Flexible(
                  child: RadioListTile<String>(
                    title: const Text('YUV'),
                    value: 'YUV',
                    groupValue: selectedMode,
                    onChanged: (value) {
                      if (value != null) {
                        selectedMode = value;
                        loadMatrixForMode(value);
                      }
                    },
                  ),
                ),
                Flexible(
                  child: RadioListTile<String>(
                    title: const Text('Custom'),
                    value: 'Custom',
                    groupValue: selectedMode,
                    onChanged: (value) {
                      if (value != null) {
                        selectedMode = value;
                        loadMatrixForMode(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 24),
                Switch(
                  value: studioClamp,
                  onChanged: (value) {
                    setState(() {
                      studioClamp = value;
                    });
                  },
                ),
                const SizedBox(width: 8),
                const Text('Studio Clamp'),
              ],
            ),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Table(
                border: TableBorder.all(color: Colors.grey, width: 0.5),
                defaultColumnWidth: const FixedColumnWidth(80),
                children: List.generate(3, (row) {
                  return TableRow(
                    children: List.generate(3, (col) {
                      return Padding(
                        padding: const EdgeInsets.all(4),
                        child: TextFormField(
                          initialValue: formatCell(matrix[row][col]),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 14),
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (value) => setMatrixValue(row, col, value),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
