import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NumericSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const NumericSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<NumericSlider> createState() => NumericSliderState();
}

class NumericSliderState extends State<NumericSlider>
    with SingleTickerProviderStateMixin {
  late double _value;
  double _displayValue = 0;
  Offset? _startDragPos;
  double _startDragValue = 0;
  bool _editing = false;
  bool _externallySet = false;
  String _inputBuffer =
      "\${_value >= 0 ? '+' : ''}\${_value.toStringAsFixed(4)}";
  int _cursorPosition = 0;
  bool _showCursor = true;
  Timer? _cursorTimer;

  final focusNode = FocusNode();
  final RangeValues _range = const RangeValues(-2.0, 2.0);
  final List<double> _detents = const [-1.0, 0.0, 1.0];
  final double _detentThreshold = 0.1;
  double? _activeDetent;

  late AnimationController _animController;
  late Animation<double> _anim;
  double _animStart = 0;
  double _animTarget = 0;

  final _textStyle = const TextStyle(
    fontSize: 12,
    fontFamily: 'Courier',
    color: Colors.white,
  );

  final _strutStyle = const StrutStyle(
    fontSize: 12,
    forceStrutHeight: true,
    height: 1,
  );

  @override
  void initState() {
    super.initState();
    _value = widget.value.clamp(_range.start, _range.end);
    _displayValue = _value;
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

  Future<void> setValue(double newValue) {
    final clamped = newValue.clamp(_range.start, _range.end);
    if ((clamped - _value).abs() >= 0.0001) {
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
        widget.onChanged(_value);
      });
    }
    return Future.value();
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
      final newValue = parsed.clamp(_range.start, _range.end);
      _cursorTimer?.cancel();
      setState(() {
        _value = newValue;
        _displayValue = newValue;
        _editing = false;
        widget.onChanged(_value);
      });
    } else {
      _cancelEditing();
    }
  }

  void _onPanStart(DragStartDetails details) {
    _startDragPos = details.globalPosition;
    _startDragValue = _value;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_startDragPos == null || _editing) return;
    final delta = details.globalPosition - _startDragPos!;
    final dragAmount = delta.dx + delta.dy;
    const double maxDrag = 60;

    final dragFraction = (dragAmount / maxDrag).clamp(-1.0, 1.0);
    final rawValue =
        _range.start + (_range.end - _range.start) * (dragFraction + 1) / 2;

    double snappedValue = rawValue;

    for (final detent in _detents) {
      if ((rawValue - detent).abs() <= _detentThreshold) {
        snappedValue = detent;
        break;
      }
    }

    snappedValue = snappedValue.clamp(_range.start, _range.end);

    setState(() {
      _value = snappedValue;
      _displayValue = snappedValue;
    });
    widget.onChanged(snappedValue);
  }

  bool get _isInteracting => _editing || _startDragPos != null;

  String get _displayText {
    if (_editing) return _inputBuffer;
    final sign = _displayValue >= 0 ? '+' : '';
    return sign + _displayValue.toStringAsFixed(4);
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
        final clamped = parsed.clamp(-2.0, 2.0);
        _cursorTimer?.cancel();
        setState(() {
          _value = clamped;
          _displayValue = clamped;
          _editing = false;
          widget.onChanged(_value);
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
            _activeDetent = null;
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

  _NumericSliderPainter({
    required this.value,
    required this.interacting,
    required this.externallySet,
    required this.textStyle,
    required this.text,
    required this.showCursor,
    required this.cursorPosition,
    required this.editing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
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

    if (!editing) {
      final fraction = (value / 2.0);
      final shadePaint = Paint()..color = baseColor.withOpacity(0.6);
      final shadeWidth = size.width * fraction.abs() / 2.0;
      final rect = Rect.fromLTWH(
        fraction > 0 ? centerX : centerX - shadeWidth,
        0,
        shadeWidth,
        size.height,
      );
      canvas.drawRect(rect, shadePaint);
    }

    if (!editing) {
      final lineX = centerX + (centerX * value / 2.0);
      canvas.drawLine(
        Offset(lineX, 0),
        Offset(lineX, size.height),
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
      old.editing != editing;
}
