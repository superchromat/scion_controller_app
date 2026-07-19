import 'dart:async';
import 'package:flutter/foundation.dart';
import 'network.dart';
import 'osc_registry.dart';

/// One (family, variant) font in the device's NOR blob. [index] is what
/// `/send/N/text/font` takes; [sizes] are the px sizes available for it.
class FontEntry {
  final int index;
  final String family;
  final String variant;
  final List<int> sizes;
  const FontEntry(this.index, this.family, this.variant, this.sizes);
}

/// Fetches and caches the device font catalog via `/fonts/count` + `/fonts/info`.
/// Device-global (not per-send), so a single shared instance is used.
class FontCatalog extends ChangeNotifier {
  FontCatalog._();
  static final FontCatalog instance = FontCatalog._();

  final List<FontEntry?> _entries = [];
  int _expected = 0;
  bool _gotCount = false;
  bool _listenersWired = false;
  Network? _net;

  /// Fully-loaded entries in device (index) order.
  List<FontEntry> get entries => _entries.whereType<FontEntry>().toList()
    ..sort((a, b) => a.index - b.index);

  bool get isLoaded => _gotCount && entries.length == _expected;

  /// Unique families in first-seen order.
  List<String> get families {
    final seen = <String>[];
    for (final e in entries) {
      if (!seen.contains(e.family)) seen.add(e.family);
    }
    return seen;
  }

  List<FontEntry> variantsOf(String family) =>
      entries.where((e) => e.family == family).toList();

  FontEntry? entryByIndex(int index) {
    for (final e in entries) {
      if (e.index == index) return e;
    }
    return null;
  }

  Timer? _retry;

  /// Query the device, retrying until loaded (survives connect-timing races and
  /// dropped datagrams). Safe to call repeatedly.
  void loadWith(Network net) {
    _net = net;
    _wireListeners();
    _gotCount = false;
    _expected = 0;
    _entries.clear();
    _sendCount();
    _retry?.cancel();
    _retry = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (isLoaded || _net == null) {
        t.cancel();
        return;
      }
      _sendCount(); // re-query count (+ re-request missing infos)
    });
  }

  void _sendCount() {
    if (_net == null || !_net!.isConnected) return;
    _net!.sendOscMessage('/assets/fonts/count', []);
  }

  void _wireListeners() {
    if (_listenersWired) return;
    _listenersWired = true;
    OscRegistry().registerAddress('/assets/fonts/count');
    OscRegistry().registerListener('/assets/fonts/count', _onCount);
    OscRegistry().registerAddress('/assets/fonts/info');
    OscRegistry().registerListener('/assets/fonts/info', _onInfo);
  }

  void _onCount(List<Object?> args) {
    if (args.isEmpty || args.first is! int) return;
    final n = args.first as int;
    _gotCount = true;
    if (n != _expected || _entries.length != n) {
      _expected = n;
      _entries
        ..clear()
        ..addAll(List<FontEntry?>.filled(n, null));
    }
    if (n == 0) {
      notifyListeners();
      return;
    }
    // Request any entries we don't have yet (idempotent; covers dropped replies).
    for (int i = 0; i < n; i++) {
      if (_entries[i] == null) _net?.sendOscMessage('/assets/fonts/info', [i]);
    }
  }

  void _onInfo(List<Object?> args) {
    if (args.length < 2 || args[0] is! int || args[1] is! String) return;
    final idx = args[0] as int;
    final parts = (args[1] as String).split('\x1f');
    if (parts.length < 3 || idx < 0 || idx >= _entries.length) return;
    final sizes = parts[2]
        .split(',')
        .where((s) => s.isNotEmpty)
        .map((s) => int.tryParse(s) ?? 0)
        .where((s) => s > 0)
        .toList();
    _entries[idx] = FontEntry(idx, parts[0], parts[1], sizes);
    notifyListeners();
  }
}
