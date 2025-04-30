import 'dart:math';

class ColorSpaceMatrix {
  static const double epsilon = 1e-5;
  static const double minAllowedValue = -2.0;
  static const double maxAllowedValue = 2.0;

  List<List<double>> _matrix;

  ColorSpaceMatrix(List<List<double>> initialMatrix)
      : _matrix = initialMatrix.map((row) => List<double>.from(row)).toList();

  List<List<double>> get matrix =>
      _matrix.map((row) => List<double>.from(row)).toList();

  void updateCell(int row, int col, double newValue) {
    _matrix[row][col] = newValue;
  }

  double determinant() {
    // 3x3 determinant manually
    double det = _matrix[0][0] *
            (_matrix[1][1] * _matrix[2][2] - _matrix[1][2] * _matrix[2][1]) -
        _matrix[0][1] *
            (_matrix[1][0] * _matrix[2][2] - _matrix[1][2] * _matrix[2][0]) +
        _matrix[0][2] *
            (_matrix[1][0] * _matrix[2][1] - _matrix[1][1] * _matrix[2][0]);
    return det;
  }

  bool isInvertible() {
    return determinant().abs() > epsilon;
  }

  bool valuesWithinRange() {
    for (var row in _matrix) {
      for (var value in row) {
        if (value < minAllowedValue || value > maxAllowedValue) {
          return false;
        }
      }
    }
    return true;
  }

  double normalizedLoss(
      List<List<double>> originalMatrix, int editedRow, int editedCol) {
    double loss = 0.0;
    const double powerPenaltyWeight = 0.01;

    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        if (i != editedRow && j != editedCol) {
          double oldValue = originalMatrix[i][j];
          double newValue = _matrix[i][j];
          double denom = max(oldValue.abs(), epsilon);
          double delta = (newValue - oldValue) / denom;
          loss += delta * delta;
        }

        // Always apply power penalty, even on edited cells
        double expected =
            (i == j) ? 1.0 : 0.0; // Prefer 1.0 for diagonal, 0.0 elsewhere
        double diff = (_matrix[i][j] - expected);
        loss += powerPenaltyWeight * (diff * diff);
      }
    }
    return loss;
  }

  bool needsCorrection() {
    return !isInvertible() || !valuesWithinRange();
  }

  void correctMatrix(int editedRow, int editedCol) {
    const int maxIterations = 100;
    const double learningRate = 0.01;
    const double lossThreshold = 1e-6;

    if (!needsCorrection()) return;

    List<List<double>> original = matrix; // Snapshot before fixing

    // Identify free cells (those not in edited row/column)
    List<Point<int>> freeCells = [];
    for (int i = 0; i < 3; i++) {
      if (i == editedRow) continue;
      for (int j = 0; j < 3; j++) {
        if (j == editedCol) continue;
        freeCells.add(Point(i, j));
      }
    }

    for (int iteration = 0; iteration < maxIterations; iteration++) {
      double currentLoss = normalizedLoss(original, editedRow, editedCol);

      if (isInvertible() &&
          currentLoss < lossThreshold &&
          valuesWithinRange()) {
        return; // Fixed!
      }

      // For each free cell, compute approximate gradient
      for (var cell in freeCells) {
        int i = cell.x;
        int j = cell.y;

        double oldValue = _matrix[i][j];

        // Finite difference gradient
        double delta = 1e-5;
        _matrix[i][j] = oldValue + delta;
        double lossPlus = normalizedLoss(original, editedRow, editedCol);
        double detPlus = determinant();

        _matrix[i][j] = oldValue - delta;
        double lossMinus = normalizedLoss(original, editedRow, editedCol);
        double detMinus = determinant();

        // Restore to original value
        _matrix[i][j] = oldValue;

        // Compute numerical gradient of loss and determinant
        double gradLoss = (lossPlus - lossMinus) / (2 * delta);
        double gradDet = (detPlus - detMinus) / (2 * delta);

        // Combined objective: prefer invertibility and low loss
        double combinedGradient =
            gradLoss - gradDet.sign * 0.01; // small bias to fix determinant

        // Gradient descent step
        _matrix[i][j] -= learningRate * combinedGradient;

        // Clamp to valid range
        _matrix[i][j] = _matrix[i][j].clamp(minAllowedValue, maxAllowedValue);
      }
    }

    // Final check
    if (!isInvertible()) {
      print('Warning: Gradient descent failed to restore invertibility.');
    }
  }
}
