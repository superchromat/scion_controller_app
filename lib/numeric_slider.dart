import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'osc_widget_binding.dart';

class NumericSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final RangeValues? range;
  final List<double>? detents;
  final int? precision;
  final bool hardDetents;

  const NumericSlider(
      {super.key,
      required this.value,
      required this.onChanged,
      this.range,
      this.detents,
      this.precision,
      this.hardDetents = false});

  @override
  State<NumericSlider> createState() => NumericSliderState();
}

class NumericSliderState extends State<NumericSlider>
    with SingleTickerProviderStateMixin, OscAddressMixin {
  late double _value;
  double _displayValue = 0;
  Offset? _startDragPos;
  bool _editing = false;
  bool _externallySet = false;
  late String _inputBuffer;
  int _cursorPosition = 0;
  bool _showCursor = true;
  Timer? _cursorTimer;
  num? prev_sent_value;

  final focusNode = FocusNode();
  late final RangeValues _range;
  late final List<double> _detents;
  final double _detentThreshold = 0.1;

  late final int _precision;

  late AnimationController _animController;
  late Animation<double> _anim;
  double _animStart = 0;
  double _animTarget = 0;

  final _textStyle = const TextStyle(
    fontSize: 12,
    fontFamily: 'Courier',
    color: Colors.white,
  );


  @override
  void initState() {
    super.initState();
    _range = widget.range ?? const RangeValues(-2.0, 2.0);
    _detents = widget.detents ?? const [-1.0, 0.0, 1.0];
    _value = widget.value.clamp(_range.start, _range.end);
    setDefaultValues(_value);
    _displayValue = _value;
    _precision = widget.precision ?? 4;
    _inputBuffer =
        (_value >= 0 ? '+' : '') + _value.toStringAsFixed(_precision);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _cursorTimer?.cancel();
    focusNode.dispose();
    super.dispose();
  }

  void _onChanged(double value) {
    widget.onChanged(value);
    // Assume hard detents + integer values means its only integers, could be something set by constructor
    if (widget.hardDetents && (value == value.toInt())) {
      if (value.toInt() != prev_sent_value) {
        sendOsc(value.toInt());
        prev_sent_value = value.toInt();
      }
    } else {
      sendOsc(value);
    }
  }

  double get value => _value;

  double _nearestDetent(double rawValue) {
    return _detents
        .reduce((a, b) => (rawValue - a).abs() < (rawValue - b).abs() ? a : b);
  }

  Future<void> setValue(double newValue, {bool immediate = false}) {
    final clamped = newValue.clamp(_range.start, _range.end);
    if ((clamped - _value).abs() >= 0.0001) {
      if (immediate) {
        _value = clamped;
        _displayValue = clamped;
        _externallySet = false;
        setState(() {}); // Trigger rebuild with new displayValue
        _onChanged(_value);
        return Future.value();
      }

      _animStart = _displayValue;
      _animTarget = clamped;
      _anim = Tween(begin: _animStart, end: _animTarget).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut),
      )..addListener(() {
          setState(() {
            _displayValue = _anim.value;
          });
        });

      _externallySet = true;
      return _animController.forward(from: 0).whenComplete(() {
        _externallySet = false;
        _value = _animTarget;
        _onChanged(_value);
      });
    }
    return Future.value();
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    OscStatus status = OscStatus.ok;
    if (args.isNotEmpty && args.first is num) {
      setValue((args.first as num).toDouble(), immediate: true);
    } else {
      status = OscStatus.error;
    }
    return (status);
  }

  void _startEditing() {
    if (_editing) return;
    setState(() {
      _editing = true;
      _inputBuffer = (_value >= 0 ? '+' : '') + _value.toStringAsFixed(4);
      _cursorPosition = 0;
      _showCursor = true;
      _cursorTimer?.cancel();
      _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        setState(() {
          _showCursor = !_showCursor;
        });
      });
    });
  }

  void _cancelEditing() {
    _cursorTimer?.cancel();
    setState(() {
      _editing = false;
      _inputBuffer = '';
    });
  }

  void _commitEditing() {
    final parsed = double.tryParse(_inputBuffer);
    if (parsed != null) {
      double newValue = parsed.clamp(_range.start, _range.end);
      if (widget.hardDetents) {
        newValue = _nearestDetent(newValue);
      }
      _cursorTimer?.cancel();
      setState(() {
        _value = newValue;
        _displayValue = newValue;
        _editing = false;
        _onChanged(_value);
      });
    } else {
      _cancelEditing();
    }
  }

  void _onPanStart(DragStartDetails details) {
    _startDragPos = details.globalPosition;
    prev_sent_value = null;
  }

/*
TODO:

The slider mechanics needs to be reworked. 
- If you click in the slider, the value should move to that spot
- Dragging should cause velocity in proportion to the distance away from the starting spot
- Velocity needs to be independent of framerate
- Detents should act like springs, where the velocity slows around a detent during a drag
- If the user lets go during a drag in a detent region, the value should oscilliate like a dampened spring to the detent value
- Detents should be visible as horizontal lines in the display
- (Text editing also needs a rework)
*/


  void _onPanUpdate(DragUpdateDetails details) {
    if (_startDragPos == null || _editing) return;
    final delta = details.globalPosition - _startDragPos!;
    final dragAmount = delta.dx + delta.dy;
    const double maxDrag = 60;

    final dragFraction = (dragAmount / maxDrag).clamp(-1.0, 1.0);
    final rawValue =
        _range.start + (_range.end - _range.start) * (dragFraction + 1) / 2;

    double snappedValue;
    if (widget.hardDetents) {
      snappedValue = _nearestDetent(rawValue);
    } else {
      snappedValue = rawValue;
      for (final detent in _detents) {
        if ((rawValue - detent).abs() <= _detentThreshold) {
          snappedValue = detent;
          break;
        }
      }
    }
    snappedValue = snappedValue.clamp(_range.start, _range.end);

    setState(() {
      _value = snappedValue;
      _displayValue = snappedValue;
    });
    _onChanged(snappedValue);
  }

  bool get _isInteracting => _editing || _startDragPos != null;

  String get _displayText {
    if (_editing) return _inputBuffer;
    final sign = _displayValue >= 0 ? '+' : '';
    return sign + _displayValue.toStringAsFixed(_precision);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!_editing || event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final label = key.keyLabel;

    if (key == LogicalKeyboardKey.escape) {
      _cancelEditing();
    } else if (key == LogicalKeyboardKey.enter) {
      final trimmed = _inputBuffer.trim();
      final parsed = double.tryParse(trimmed);
      final isValid =
          parsed != null && RegExp(r'^[+-]?\d\.\d{4}$').hasMatch(trimmed);

      if (isValid) {
        double clamped = parsed.clamp(_range.start, _range.end);
        if (widget.hardDetents) {
          clamped = _nearestDetent(clamped);
        }
        _cursorTimer?.cancel();
        setState(() {
          _value = clamped;
          _displayValue = clamped;
          _editing = false;
          _onChanged(_value);
        });
      } else {
        _cancelEditing();
      }
    } else if (key == LogicalKeyboardKey.backspace) {
      setState(() {
        if (_cursorPosition > 0) {
          _inputBuffer = _inputBuffer.replaceRange(
            _cursorPosition - 1,
            _cursorPosition,
            '',
          );
          _cursorPosition--;
        }
      });
    } else if (key == LogicalKeyboardKey.delete) {
      setState(() {
        if (_cursorPosition < _inputBuffer.length) {
          _inputBuffer = _inputBuffer.replaceRange(
            _cursorPosition,
            _cursorPosition + 1,
            '',
          );
        }
      });
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        _cursorPosition = (_cursorPosition - 1).clamp(0, _inputBuffer.length);
      });
    } else if (key == LogicalKeyboardKey.arrowRight) {
      setState(() {
        _cursorPosition = (_cursorPosition + 1).clamp(0, _inputBuffer.length);
      });
    } else if (RegExp(r'[0-9+\-\.]').hasMatch(label)) {
      // Position-specific character validation
      if (_cursorPosition == 0) {
        if (label != '+' && label != '-') return KeyEventResult.handled;
      } else if (_cursorPosition == 1) {
        if (!RegExp(r'\d').hasMatch(label)) return KeyEventResult.handled;
      } else if (_cursorPosition == 2) {
        if (label != '.') return KeyEventResult.handled;
      } else if (_cursorPosition >= 3 && _cursorPosition <= 6) {
        if (!RegExp(r'\d').hasMatch(label)) return KeyEventResult.handled;
      } else {
        return KeyEventResult.handled;
      }

      setState(() {
        if (_cursorPosition < _inputBuffer.length) {
          _inputBuffer = _inputBuffer.replaceRange(
            _cursorPosition,
            _cursorPosition + 1,
            label,
          );
        } else {
          _inputBuffer += label;
        }
        _cursorPosition = (_cursorPosition + 1).clamp(0, _inputBuffer.length);
      });
    }

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) => Focus(
        focusNode: focusNode,
        autofocus: true,
        onFocusChange: (hasFocus) {
          if (!hasFocus && _editing) {
            final trimmed = _inputBuffer.trim();
            final parsed = double.tryParse(trimmed);
            final isValid =
                parsed != null && RegExp(r'^[+-]?\d\.\d{4}$').hasMatch(trimmed);
            if (isValid) {
              _commitEditing();
            } else {
              _cancelEditing();
            }
          }
        },
        onKeyEvent: _onKeyEvent,
        child: GestureDetector(
          onTap: () {
            if (!_editing) {
              focusNode
                  .requestFocus(); // triggers autofocus AND lets onFocusChange trigger on blur
              _startEditing();
            }
          },
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: (_) => setState(() {
            _startDragPos = null;
          }),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _NumericSliderPainter(
                  value: _editing ? _value : _displayValue,
                  interacting: _isInteracting,
                  externallySet: _externallySet,
                  textStyle: _textStyle,
                  text: _displayText,
                  showCursor: _editing && _showCursor,
                  cursorPosition: _cursorPosition,
                  editing: _editing,
                  range: _range,
                  detents: _detents,
                  precision: _precision,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NumericSliderPainter extends CustomPainter {
  final double value;
  final bool interacting;
  final bool externallySet;
  final TextStyle textStyle;
  final String text;
  bool showCursor = false;
  final int cursorPosition;
  final bool editing;
  final RangeValues range;
  final List<double> detents;
  final int precision;

  _NumericSliderPainter(
      {required this.value,
      required this.interacting,
      required this.externallySet,
      required this.textStyle,
      required this.text,
      required this.showCursor,
      required this.cursorPosition,
      required this.editing,
      required this.range,
      required this.detents,
      required this.precision});

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = externallySet
        ? Colors.yellow[700]!
        : interacting
            ? Colors.yellow
            : Colors.white;

    final bgPaint = Paint()..color = Colors.transparent;
    final linePaint = Paint()
      ..color = baseColor.withOpacity(0.6)
      ..strokeWidth = 1;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );

    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.grey
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final clipPath = Path()..addRRect(rrect);
    canvas.save();
    canvas.clipPath(clipPath);

    for (var d in detents) {
      final X = (d - range.start) /
          (range.end - range.start).clamp(0, 1) *
          size.width;
      canvas.drawLine(Offset(X, 0), Offset(X, size.height), linePaint);
    }

    if (!editing) {
      final normalized =
          ((value - range.start) / (range.end - range.start)).clamp(0.0, 1.0);
      final posX = size.width * normalized;
      final centerX = size.width / 2;

      final shadePaint = Paint()..color = baseColor.withOpacity(0.6);
      final shadeWidth = (posX - centerX).abs();
      final rect = Rect.fromLTWH(
        posX >= centerX ? centerX : posX,
        0,
        shadeWidth,
        size.height,
      );
      canvas.drawRect(rect, shadePaint);

      canvas.drawLine(
        Offset(posX, 0),
        Offset(posX, size.height),
        linePaint,
      );
    }

    canvas.restore();

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(color: baseColor),
      ),
      textDirection: TextDirection.ltr,
      strutStyle: const StrutStyle(
        fontSize: 12,
        forceStrutHeight: true,
        height: 1,
      ),
    );
    textPainter.layout();
    final textOffset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );
    textPainter.paint(canvas, textOffset);

    if (editing && showCursor && cursorPosition < text.length) {
      final boxes = textPainter.getBoxesForSelection(
        TextSelection(
            baseOffset: cursorPosition, extentOffset: cursorPosition + 1),
      );

      if (boxes.isNotEmpty) {
        final rect = boxes.first.toRect();
        final adjustedBox = Rect.fromLTWH(
          rect.left + textOffset.dx,
          (size.height - rect.height) / 2,
          rect.width,
          rect.height,
        );
        final paint = Paint()
          ..color = Colors.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRRect(
          RRect.fromRectAndRadius(adjustedBox.inflate(1.5), Radius.circular(1)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NumericSliderPainter old) =>
      old.value != value ||
      old.interacting != interacting ||
      old.externallySet != externallySet ||
      old.textStyle != textStyle ||
      old.text != text ||
      old.showCursor != showCursor ||
      old.cursorPosition != cursorPosition ||
      old.editing != editing ||
      old.range != range ||
      old.detents != detents;
}
