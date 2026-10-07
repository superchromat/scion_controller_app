import 'dart:async';
import 'package:flutter/material.dart';

class _GlobalRectResizeSignal extends ChangeNotifier
    with WidgetsBindingObserver {
  _GlobalRectResizeSignal._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final _GlobalRectResizeSignal instance = _GlobalRectResizeSignal._();

  Timer? _debounce;

  /// True from the first metrics change until the window has been still for
  /// the debounce interval — i.e. for the duration of a drag.
  bool get resizing => _resizing;
  bool _resizing = false;

  @override
  void didChangeMetrics() {
    _resizing = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _resizing = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Tracks a widget's global bounds without scheduling a post-frame callback on
/// every build. This avoids resize feedback loops in heavily custom-painted UI.
mixin GlobalRectTracking<T extends StatefulWidget> on State<T> {
  final GlobalKey globalRectKey = GlobalKey();
  Rect? trackedGlobalRect;

  bool _globalRectUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _GlobalRectResizeSignal.instance.addListener(_onResizeSettled);
    scheduleGlobalRectUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    scheduleGlobalRectUpdate();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    scheduleGlobalRectUpdate();
  }

  void scheduleGlobalRectUpdate() {
    if (!mounted || _globalRectUpdateScheduled) return;
    _globalRectUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _globalRectUpdateScheduled = false;
      if (!mounted) return;
      _updateGlobalRectNow();
    });
  }

  void _onResizeSettled() {
    if (!mounted) return;
    scheduleGlobalRectUpdate();
  }

  void _updateGlobalRectNow() {
    // Mid-drag, every widget has moved, so this would setState on every tracked
    // widget — and because it runs in a post-frame callback it dirties them
    // AFTER the frame, forcing a second full build/layout/paint pass for each
    // resize step. The rect it would store is stale the moment the next step
    // arrives, so the work buys nothing until the drag stops. Skip it and let
    // the settle listener do it once, when the value can actually be right.
    if (_GlobalRectResizeSignal.instance.resizing) return;

    final renderBox =
        globalRectKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final newRect = position & renderBox.size;
    if (trackedGlobalRect == newRect) return;

    setState(() => trackedGlobalRect = newRect);
  }

  @override
  void dispose() {
    _GlobalRectResizeSignal.instance.removeListener(_onResizeSettled);
    super.dispose();
  }
}
