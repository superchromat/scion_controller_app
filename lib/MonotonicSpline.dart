import 'dart:math';
import 'package:flutter/material.dart';

// ------------------
// Monotonic Spline
// ------------------
class MonotonicSpline {
  final List<Offset> points;
  late final List<double> _slopes;
  late final List<double> _tangents;

  MonotonicSpline(this.points) {
    assert(points.length >= 2);
    _computeSlopes();
    _computeTangents();
  }

  void _computeSlopes() {
    _slopes = [];
    for (int i = 0; i < points.length - 1; i++) {
      final dx = points[i + 1].dx - points[i].dx;
      final dy = points[i + 1].dy - points[i].dy;
      _slopes.add(dy / dx);
    }
  }

  void _computeTangents() {
    _tangents = List.filled(points.length, 0.0);

    _tangents[0] = _slopes[0];
    for (int i = 1; i < points.length - 1; i++) {
      final mPrev = _slopes[i - 1];
      final mNext = _slopes[i];

      if (mPrev * mNext <= 0) {
        _tangents[i] = 0.0;
      } else {
        _tangents[i] = (mPrev + mNext) / 2.0;
      }
    }
    _tangents[points.length - 1] = _slopes[_slopes.length - 1];

    // Enforce monotonicity constraint
    for (int i = 0; i < _slopes.length; i++) {
      if (_slopes[i] == 0.0) {
        _tangents[i] = 0.0;
        _tangents[i + 1] = 0.0;
      } else {
        final a = _tangents[i] / _slopes[i];
        final b = _tangents[i + 1] / _slopes[i];
        final s = a * a + b * b;
        if (s > 9.0) {
          final tau = 3.0 / sqrt(s);
          _tangents[i] = tau * a * _slopes[i];
          _tangents[i + 1] = tau * b * _slopes[i];
        }
      }
    }
  }

  double evaluate(double x) {
    if (x <= points.first.dx) return points.first.dy;
    if (x >= points.last.dx) return points.last.dy;

    int i = 0;
    while (i < points.length - 2 && points[i + 1].dx < x) {
      i++;
    }

    final x0 = points[i].dx;
    final x1 = points[i + 1].dx;
    final y0 = points[i].dy;
    final y1 = points[i + 1].dy;
    final t0 = _tangents[i];
    final t1 = _tangents[i + 1];
    final h = x1 - x0;
    final t = (x - x0) / h;

    final m = _slopes[i];

    // If the tangents match the slope perfectly, do linear interpolation
    if ((t0 == m && t1 == m)) {
      return y0 + (y1 - y0) * t;
    }

    // Otherwise Hermite cubic interpolation
    final h00 = (2 * t * t * t) - (3 * t * t) + 1;
    final h10 = (t * t * t) - (2 * t * t) + t;
    final h01 = (-2 * t * t * t) + (3 * t * t);
    final h11 = (t * t * t) - (t * t);

    return h00 * y0 + h10 * h * t0 + h01 * y1 + h11 * h * t1;
  }
}