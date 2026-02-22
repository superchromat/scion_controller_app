import 'dart:async';
import 'package:flutter/material.dart';

class _GlobalRectResizeSignal extends ChangeNotifier with WidgetsBindingObserver {
  _GlobalRectResizeSignal._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final _GlobalRectResizeSignal instance = _GlobalRectResizeSignal._();

  Timer? _debounce;

  @override
  void didChangeMetrics() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), notifyListeners);
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
    final renderBox = globalRectKey.currentContext?.findRenderObject() as RenderBox?;
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
