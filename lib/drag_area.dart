import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A direct-manipulation surface whose drag beats a scrollable ancestor.
///
/// On touch devices a parent scrollable's vertical-drag recogniser normally wins
/// the gesture arena, so dragging a crop handle, a warp point or a band divider
/// scrolls the page instead of moving the thing under your finger. This claims
/// the arena on pointer-down — the same approach the LUT editor and colour
/// wheels already use — then re-derives tap-vs-drag from raw pointer events so
/// callers keep [GestureDetector]-style semantics.
///
/// Use this instead of a [GestureDetector] with `onPan*` callbacks for anything
/// the user manipulates directly inside a scrolling page.
/// Reports both the local position (the common case) and the global position,
/// which a few callers need to place overlays.
typedef DragAreaCallback = void Function(
    Offset localPosition, Offset globalPosition);

class DragArea extends StatefulWidget {
  /// Fires on pointer-down, before we know whether this is a tap or a drag.
  /// Equivalent to `onPanDown`.
  final DragAreaCallback? onPointerDown;

  /// Fires once movement passes the touch slop, with the *original* down
  /// position (matching `onPanStart`).
  final DragAreaCallback? onDragStart;
  final DragAreaCallback? onDragUpdate;
  final VoidCallback? onDragEnd;

  /// Fires on release when the pointer never moved beyond the touch slop.
  final DragAreaCallback? onTap;

  final Widget child;

  const DragArea({
    super.key,
    this.onPointerDown,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onTap,
    required this.child,
  });

  @override
  State<DragArea> createState() => _DragAreaState();
}

class _DragAreaState extends State<DragArea> {
  Offset _down = Offset.zero;
  Offset _downGlobal = Offset.zero;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        // Claims the arena on pointer-down so no scrollable ancestor can steal
        // the drag. The Listener below does the actual work.
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(),
          (_) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          _down = e.localPosition;
          _downGlobal = e.position;
          _dragging = false;
          widget.onPointerDown?.call(e.localPosition, e.position);
        },
        onPointerMove: (e) {
          if (!_dragging) {
            if ((e.localPosition - _down).distance <= kTouchSlop) return;
            _dragging = true;
            widget.onDragStart?.call(_down, _downGlobal);
          }
          widget.onDragUpdate?.call(e.localPosition, e.position);
        },
        onPointerUp: (e) {
          if (_dragging) {
            widget.onDragEnd?.call();
          } else {
            widget.onTap?.call(e.localPosition, e.position);
          }
          _dragging = false;
        },
        onPointerCancel: (_) {
          if (_dragging) widget.onDragEnd?.call();
          _dragging = false;
        },
        child: widget.child,
      ),
    );
  }
}
