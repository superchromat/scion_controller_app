import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'grid.dart';

/// Posterizer band editor (Send 1 only — drives the global /poster/*
/// endpoints on the monitor zebra/colour-pattern block).
///
/// A horizontal strip shows the 16 luma bands. Drag the dividers to move the
/// 15 thresholds; tap a band to select it, then set its type (original /
/// zebra stripes / solid) and colour below. Preset buttons regenerate the
/// whole band set. The UI owns the band state and pushes it to the firmware.
class PosterEditor extends StatefulWidget {
  const PosterEditor({super.key});

  @override
  State<PosterEditor> createState() => _PosterEditorState();
}

class _PosterEditorState extends State<PosterEditor> {
  bool _enabled = false;
  bool _blink = false;
  int _zebraWidth = 2;
  int _zebraRepeat = 10;
  final List<int> _th = List.generate(15, (i) => (i + 1) * 256 ~/ 16)
      .map((v) => v.clamp(0, 255))
      .toList();
  final List<int> _type = List.filled(16, 7);
  final List<int> _color = List.filled(16, 0xFFFFFF);
  int _selected = 0;
  int? _dragDivider;

  static const List<String> _typeLabels = [
    'Original', 'Zebra ↗', 'Zebra ↖', 'Zebra —', 'Zebra |',
    '5', '6', 'Solid',
  ];
  static const List<int> _typeValues = [0, 1, 2, 3, 4, 7];

  static const List<int> _swatches = [
    0x000000, 0xFFFFFF, 0xFF0000, 0xFF8000, 0xFFFF00, 0x00FF00,
    0x00FFFF, 0x0080FF, 0x0000FF, 0x8000FF, 0xFF00FF, 0x808080,
  ];

  void _send(String path, List<Object> args) {
    context.read<Network>().sendOscMessage(path, args);
  }

  void _pushBand(int i) {
    _send('/poster/band', [i, _type[i], _color[i]]);
  }

  void _pushAll() {
    for (int i = 0; i < 15; i++) {
      _send('/poster/th', [i, _th[i]]);
    }
    for (int i = 0; i < 16; i++) {
      _pushBand(i);
    }
    _send('/poster/zebra', [_zebraWidth, _zebraRepeat]);
    _send('/poster/blink', [_blink ? 1 : 0]);
  }

  // Presets mirror the firmware generators, but are built locally so the
  // strip always shows exactly what was pushed.
  void _preset(int n, int mode) {
    setState(() {
      for (int i = 0; i < 15; i++) {
        _th[i] = (i < n - 1) ? ((i + 1) * 256 ~/ n).clamp(0, 255) : 255;
      }
      for (int i = 0; i < 16; i++) {
        final band = (i < n) ? i : n - 1;
        final lum = band * 255 ~/ (n - 1);
        switch (mode) {
          case 0:
            _type[i] = 7;
            _color[i] = (lum << 16) | (lum << 8) | lum;
          case 1:
            _type[i] = 7;
            final h = band * 6 * 255 ~/ n;
            final seg = h ~/ 255, f = h % 255;
            int r = 0, g = 0, b = 0;
            switch (seg) {
              case 0: r = 255; g = f;
              case 1: r = 255 - f; g = 255;
              case 2: g = 255; b = f;
              case 3: g = 255 - f; b = 255;
              case 4: r = f; b = 255;
              default: r = 255; b = 255 - f;
            }
            _color[i] = (r << 16) | (g << 8) | b;
          case 2:
            _type[i] = (band.isOdd) ? 7 : 0;
            _color[i] = 0xFFFFFF;
        }
      }
    });
    _pushAll();
  }

  // Map an x fraction (0..1) to the divider index being grabbed, or null.
  int? _hitDivider(double fx) {
    double best = 0.02;  // grab radius in fraction of width
    int? hit;
    for (int i = 0; i < 15; i++) {
      final d = (fx - _th[i] / 255.0).abs();
      if (d < best) { best = d; hit = i; }
    }
    return hit;
  }

  int _bandAt(double fx) {
    final v = (fx * 255).round().clamp(0, 255);
    for (int i = 0; i < 15; i++) {
      if (v < _th[i]) return i;
    }
    return 15;
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    Widget chip(String label, VoidCallback onTap, {bool active = false}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.md, vertical: t.xs),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFF6B6B) : const Color(0xFF2A2A2C),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: active ? const Color(0xFFFF6B6B) : Colors.grey[600]!,
            ),
          ),
          child: Text(label,
              style: t.textLabel.copyWith(
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : Colors.grey[300],
              )),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top row: enable, presets, zebra geometry, blink
        Wrap(
          spacing: t.sm,
          runSpacing: t.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            chip(_enabled ? 'ON' : 'OFF', () {
              setState(() => _enabled = !_enabled);
              if (_enabled) _pushAll();
              _send('/poster/enable', [_enabled ? 1 : 0]);
            }, active: _enabled),
            SizedBox(width: t.sm),
            chip('Gray 6', () => _preset(6, 0)),
            chip('Hue 8', () => _preset(8, 1)),
            chip('Contour 8', () => _preset(8, 2)),
            chip('Gray 16', () => _preset(16, 0)),
            SizedBox(width: t.sm),
            chip(_blink ? 'Blink ON' : 'Blink', () {
              setState(() => _blink = !_blink);
              _send('/poster/blink', [_blink ? 1 : 0]);
            }, active: _blink),
            // Zebra stripe geometry (applies to zebra-type bands)
            Text('Stripe W', style: t.textLabel),
            Slider(
              value: _zebraWidth.toDouble(), min: 0, max: 15, divisions: 15,
              onChanged: (v) {
                setState(() => _zebraWidth = v.round());
                _send('/poster/zebra', [_zebraWidth, _zebraRepeat]);
              },
            ),
            Text('Repeat', style: t.textLabel),
            Slider(
              value: _zebraRepeat.toDouble(), min: 0, max: 15, divisions: 15,
              onChanged: (v) {
                setState(() => _zebraRepeat = v.round());
                _send('/poster/zebra', [_zebraWidth, _zebraRepeat]);
              },
            ),
          ],
        ),
        SizedBox(height: t.sm),
        // The band strip
        LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          return GestureDetector(
            onPanDown: (d) {
              final fx = d.localPosition.dx / w;
              _dragDivider = _hitDivider(fx);
              if (_dragDivider == null) {
                setState(() => _selected = _bandAt(fx));
              }
            },
            onPanUpdate: (d) {
              final i = _dragDivider;
              if (i == null) return;
              final lo = (i > 0) ? _th[i - 1] + 1 : 1;
              final hi = (i < 14) ? _th[i + 1] - 1 : 255;
              final v = (d.localPosition.dx / w * 255).round().clamp(lo, hi);
              if (v != _th[i]) {
                setState(() => _th[i] = v);
                _send('/poster/th', [i, v]);
              }
            },
            onPanEnd: (_) => _dragDivider = null,
            child: CustomPaint(
              size: Size(w, 56),
              painter: _BandStripPainter(
                  th: _th, type: _type, color: _color, selected: _selected),
            ),
          );
        }),
        SizedBox(height: t.sm),
        // Selected band controls
        Wrap(
          spacing: t.sm,
          runSpacing: t.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Band ${_selected + 1}', style: t.textLabel),
            DropdownButton<int>(
              value: _typeValues.contains(_type[_selected]) ? _type[_selected] : 7,
              isDense: true,
              dropdownColor: const Color(0xFF2A2A2E),
              style: t.textLabel.copyWith(color: Colors.white),
              items: [
                for (final v in _typeValues)
                  DropdownMenuItem(value: v, child: Text(_typeLabels[v])),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _type[_selected] = v);
                _pushBand(_selected);
              },
            ),
            for (final c in _swatches)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _color[_selected] = c;
                    if (_type[_selected] == 0) _type[_selected] = 7;
                  });
                  _pushBand(_selected);
                },
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: Color(0xFF000000 | c),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _color[_selected] == c
                          ? Colors.white
                          : Colors.grey[700]!,
                      width: _color[_selected] == c ? 2 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BandStripPainter extends CustomPainter {
  final List<int> th;
  final List<int> type;
  final List<int> color;
  final int selected;

  _BandStripPainter({
    required this.th,
    required this.type,
    required this.color,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (int i = 0; i < 16; i++) {
      final x0 = (i == 0 ? 0 : th[i - 1]) / 255.0 * size.width;
      final x1 = (i == 15 ? 255 : th[i]) / 255.0 * size.width;
      final rect = Rect.fromLTRB(x0, 0, x1, size.height);
      if (type[i] == 0) {
        // "original" — dark checker
        paint.color = const Color(0xFF202024);
        canvas.drawRect(rect, paint);
        paint.color = const Color(0xFF3A3A40);
        const cs = 7.0;
        for (double y = 0; y < size.height; y += cs) {
          for (double x = x0; x < x1; x += cs) {
            if (((x ~/ cs) + (y ~/ cs)).isOdd) {
              canvas.drawRect(
                  Rect.fromLTWH(x, y, cs.clamp(0, x1 - x), cs), paint);
            }
          }
        }
      } else {
        paint.color = Color(0xFF000000 | color[i]);
        canvas.drawRect(rect, paint);
        if (type[i] >= 1 && type[i] <= 4) {
          // stripe hint for zebra types
          paint.color = Colors.black.withValues(alpha: 0.45);
          const sw = 5.0;
          if (type[i] == 3) {
            for (double y = 0; y < size.height; y += sw * 2) {
              canvas.drawRect(Rect.fromLTRB(x0, y, x1, y + sw), paint);
            }
          } else if (type[i] == 4) {
            for (double x = x0; x < x1; x += sw * 2) {
              canvas.drawRect(
                  Rect.fromLTRB(x, 0, (x + sw).clamp(x0, x1), size.height),
                  paint);
            }
          } else {
            // diagonal
            canvas.save();
            canvas.clipRect(rect);
            final slope = (type[i] == 1) ? -1.0 : 1.0;
            for (double x = x0 - size.height;
                x < x1 + size.height;
                x += sw * 2.8) {
              final p = Path()
                ..moveTo(x, type[i] == 1 ? size.height : 0)
                ..lineTo(x + size.height * slope.abs(),
                    type[i] == 1 ? 0 : size.height)
                ..lineTo(x + size.height * slope.abs() + sw,
                    type[i] == 1 ? 0 : size.height)
                ..lineTo(x + sw, type[i] == 1 ? size.height : 0)
                ..close();
              canvas.drawPath(p, paint);
            }
            canvas.restore();
          }
        }
      }
      // selection highlight
      if (i == selected) {
        paint
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawRect(rect.deflate(1), paint);
        paint.style = PaintingStyle.fill;
      }
    }
    // dividers
    paint
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.5;
    for (int i = 0; i < 15; i++) {
      final x = th[i] / 255.0 * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      // handle nub
      canvas.drawCircle(Offset(x, size.height - 6), 3.5, paint);
    }
  }

  @override
  bool shouldRepaint(_BandStripPainter old) => true;
}
