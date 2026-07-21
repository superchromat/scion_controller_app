import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/lut_io.dart';

void main() {
  test('.cube round trip parse/format', () {
    final id = composeColorCube(
      knobs: const PictureKnobs(0.5, 0.5, 0.5, 0.0),
      lutR: Lut1D.fromPoints(const [(0, 0), (1, 1)]),
      lutG: Lut1D.fromPoints(const [(0, 0), (1, 1)]),
      lutB: Lut1D.fromPoints(const [(0, 0), (1, 1)]),
      grade: const [
        GradeZone(0, 0, 0, 0.5, 0.5, 0.25, 0.1),
        GradeZone(0, 0, 0, 0.5, 0.5, 0.75, 0.1),
        GradeZone(0, 0, 0, 0.5, 0.5, 1.0, 0.1),
      ],
      n: 9,
    );
    final reparsed = CubeLut.parse(id.format());
    expect(reparsed.n, 9);
    // neutral everything => identity cube
    for (var i = 0; i < 9; i++) {
      final v = i / 8.0;
      final (r, g, b) = reparsed.sample(v, v, v);
      expect(r, closeTo(v, 1e-4));
      expect(g, closeTo(v, 1e-4));
      expect(b, closeTo(v, 1e-4));
    }
  });

  test('knob CSC: contrast scales around black, saturation kills chroma', () {
    const half = PictureKnobs(0.5, 0.25, 0.5, 0.0); // contrast ~0.5x
    final (r1, _, _) = half.apply(0.8, 0.8, 0.8);
    expect(r1, closeTo(0.8 * (0.25 * 255 / 128), 0.02));
    const desat = PictureKnobs(0.5, 0.5, 0.0, 0.0);
    final (r2, g2, b2) = desat.apply(0.9, 0.2, 0.4);
    expect((r2 - g2).abs() < 0.02 && (g2 - b2).abs() < 0.02, isTrue,
        reason: 'zero saturation should be grayscale, got $r2 $g2 $b2');
  });

  test('grade eval matches firmware behaviour for a lift', () {
    const zones = [
      GradeZone(0, 0, 0.2, 0.5, 0.5, 0.25, 0.1), // shadows lift
      GradeZone(0, 0, 0, 0.5, 0.5, 0.75, 0.1),
      GradeZone(0, 0, 0, 0.5, 0.5, 1.0, 0.1),
    ];
    final (r, g, b) = gradeEval(0.05, 0.05, 0.05, zones);
    expect(r, closeTo(0.25, 0.02)); // deep shadow fully lifted by 0.2
    final (r2, _, _) = gradeEval(0.9, 0.9, 0.9, zones);
    expect(r2, closeTo(0.9, 1e-3)); // highlights untouched
  });

  test('trilinear resample of identity stays identity at 17^3', () {
    final id = composeColorCube(
      knobs: const PictureKnobs(0.5, 0.5, 0.5, 0.0),
      lutR: Lut1D.fromPoints(const [(0, 0), (1, 1)]),
      lutG: Lut1D.fromPoints(const [(0, 0), (1, 1)]),
      lutB: Lut1D.fromPoints(const [(0, 0), (1, 1)]),
      grade: const [
        GradeZone(0, 0, 0, 0.5, 0.5, 0.25, 0.1),
        GradeZone(0, 0, 0, 0.5, 0.5, 0.75, 0.1),
        GradeZone(0, 0, 0, 0.5, 0.5, 1.0, 0.1),
      ],
      n: 33,
    );
    final blob = packLut3dBlob(id, 't');
    // spot check: mid grid point (8,8,8) of 17^3 should be ~2040/4080
    const n = 17;
    final off = 40 + (((8 * n + 8) * n + 8) * 3) * 2;
    final v = blob[off] | (blob[off + 1] << 8);
    expect(v, closeTo(2048, 3));
  });
}
