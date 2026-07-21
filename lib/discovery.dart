import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart';

import 'network.dart';
import 'nsd_client.dart' show NetworkAddress;

/// What the disconnected scrim should show while there's no connection.
enum DiscoveryPhase { searching, timedOut }

/// The single authority for connecting to a SCION. It continuously browses the
/// local network (mDNS service `_scion._udp`, independent of the device's
/// hostname), reconnects to the last endpoint, and connects automatically — so
/// nobody has to press "find":
///   - repeat users reconnect to their last endpoint instantly;
///   - a single discovered device auto-connects;
///   - multiple devices raise [needsPicker] so the UI can offer a choice;
///   - nothing found within [_timeout] flips [phase] to [timedOut] (help shown).
///
/// It also owns reconnection on drop, so [Network]'s built-in auto-reconnect is
/// disabled to avoid two drivers fighting.
///
/// [demoMode] disables all of this and hides the scrim, letting people click
/// around without a live device.
class ScionDiscovery extends ChangeNotifier {
  final Network network;

  ScionDiscovery(this.network) {
    network.autoReconnectEnabled = false; // we own reconnection
    _wasConnected = network.isConnected;
    network.addListener(_onNetworkChanged);
    _init();
  }

  static const String _serviceType = '_scion._udp';
  static const Duration _timeout = Duration(seconds: 8);
  static const Duration _connectWait = Duration(seconds: 4);
  static const Duration _retryInterval = Duration(seconds: 3);
  static const String _prefKey = 'recent_endpoints';
  static const int _defaultPort = 9000;
  static const int _maxRecents = 5;

  /// The device's well-known mDNS hostname (CONFIG_NET_HOSTNAME on the
  /// firmware). Its A record is answered even when DNS-SD service discovery is
  /// slow, backed off, or unavailable, so we fall back to it — see
  /// [_tryReconnect].
  static const String _fallbackHost = 'scion.local';

  nsd.Discovery? _discovery;
  Timer? _timeoutTimer;
  Timer? _retryTimer;
  DiscoveryPhase _phase = DiscoveryPhase.searching;
  List<NetworkAddress> _devices = <NetworkAddress>[];
  List<String> _recents = <String>[];
  bool _busy = false;
  bool _wasConnected = false;
  bool _demoMode = false;

  DiscoveryPhase get phase => _phase;
  List<NetworkAddress> get devices => List.unmodifiable(_devices);
  List<String> get recents => List.unmodifiable(_recents);
  bool get connected => network.isConnected;
  bool get demoMode => _demoMode;

  /// Multiple candidates and none we can auto-pick — the UI shows a chooser.
  bool get needsPicker =>
      !_demoMode &&
      !connected &&
      !_busy &&
      _devices.length > 1 &&
      _autoTarget() == null;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _recents = prefs.getStringList(_prefKey) ?? <String>[];
    _restartTimeout();
    _startBrowse();
    _startRetry(); // immediate attempt + periodic while disconnected
  }

  Future<void> _startBrowse() async {
    if (_discovery != null || _demoMode) return;
    try {
      _discovery = await nsd.startDiscovery(_serviceType,
          autoResolve: true, ipLookupType: nsd.IpLookupType.any);
      _discovery!.addListener(_onServices);
      _onServices();
    } catch (e) {
      if (kDebugMode) debugPrint('mDNS discovery unavailable: $e');
    }
  }

  Future<void> _stopBrowse() async {
    final d = _discovery;
    _discovery = null;
    if (d != null) {
      d.removeListener(_onServices);
      try {
        await nsd.stopDiscovery(d);
      } catch (_) {}
    }
  }

  void _onServices() {
    final d = _discovery;
    if (d == null) return;
    final list = <NetworkAddress>[];
    final seen = <String>{};
    for (final s in d.services) {
      final port = s.port;
      if (port == null) continue;
      String? host;
      final addrs = s.addresses;
      if (addrs != null && addrs.isNotEmpty) {
        final v4 = addrs.where((a) => a.type == InternetAddressType.IPv4);
        host = (v4.isNotEmpty ? v4.first : addrs.first).address;
      } else {
        host = s.host;
      }
      if (host == null || host.isEmpty) continue;
      while (host!.endsWith('.')) {
        host = host.substring(0, host.length - 1);
      }
      if (seen.add('$host:$port')) {
        list.add(NetworkAddress(host: host, port: port));
      }
    }
    _devices = list;
    _tryReconnect();
    notifyListeners();
  }

  /// The device we can connect to without asking: a recent match, else the sole
  /// device found.
  NetworkAddress? _autoTarget() {
    if (_devices.isEmpty) return null;
    for (final r in _recents) {
      final ep = _parse(r);
      if (ep == null) continue;
      for (final d in _devices) {
        if (d.host == ep.host && d.port == ep.port) return d;
      }
    }
    return _devices.length == 1 ? _devices.first : null;
  }

  /// Try to (re)connect: a discovered auto-target, otherwise — if no picker is
  /// warranted — the last-used endpoint (mDNS may not have found it yet).
  Future<void> _tryReconnect() async {
    if (connected || _busy || _demoMode) return;
    final target = _autoTarget();
    if (target != null) {
      await _connect(target.host, target.port);
      return;
    }
    if (_devices.length > 1) return; // let the user pick
    // No usable mDNS result. Try the last endpoint, then the device's
    // well-known hostname. The hostname (A record) resolves even when DNS-SD
    // discovery hasn't surfaced the service yet, so this connects on a fresh
    // machine (no recents) or when the browse has stalled/backed off.
    if (_recents.isNotEmpty) {
      final ep = _parse(_recents.first);
      if (ep != null && await _connect(ep.host, ep.port)) return;
    }
    await _connect(_fallbackHost, _defaultPort);
  }

  Future<bool> _connect(String host, int port) async {
    if (_busy || connected || _demoMode) return connected;
    _busy = true;
    notifyListeners();
    try {
      await network.connect(host, port, userInitiated: false);
      final ok = await _waitConnected(_connectWait);
      if (ok) await _saveRecent(host, port);
      return ok;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> _waitConnected(Duration timeout) async {
    if (network.isConnected) return true;
    final completer = Completer<bool>();
    void listener() {
      if (network.isConnected && !completer.isCompleted) {
        completer.complete(true);
      }
    }

    network.addListener(listener);
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(network.isConnected);
    });
    final result = await completer.future;
    network.removeListener(listener);
    timer.cancel();
    return result;
  }

  /// Connect to an explicitly chosen endpoint (picker tap or manual entry).
  Future<bool> connectTo(String host, int port) {
    if (network.isConnected) network.disconnect();
    return _connect(host, port);
  }

  /// Manual re-scan (the demoted "find" button). Discovery already runs
  /// continuously; this just resets the search state and re-evaluates.
  void rescan() {
    if (_demoMode) return;
    _restartTimeout();
    _startBrowse();
    _startRetry();
  }

  // ---- demo mode -----------------------------------------------------------

  void enterDemoMode() {
    if (_demoMode) return;
    _demoMode = true;
    _cancelTimeout();
    _stopRetry();
    _stopBrowse();
    notifyListeners();
  }

  void exitDemoMode() {
    if (!_demoMode) return;
    _demoMode = false;
    if (!connected) {
      _restartTimeout();
      _startBrowse();
      _startRetry();
    }
    notifyListeners();
  }

  // ---- reconnection loop / timeouts ---------------------------------------

  void _startRetry() {
    if (_demoMode) return;
    _retryTimer?.cancel();
    _tryReconnect();
    _retryTimer = Timer.periodic(_retryInterval, (_) => _tryReconnect());
  }

  void _stopRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _restartTimeout() {
    _timeoutTimer?.cancel();
    if (_phase != DiscoveryPhase.searching) {
      _phase = DiscoveryPhase.searching;
      notifyListeners();
    }
    _timeoutTimer = Timer(_timeout, () {
      // Show the help once we've had time to find AND connect. A lingering mDNS
      // record (device just unplugged) shouldn't keep us "searching" forever, so
      // this fires whenever we're still not connected — the picker still wins
      // over the help in the scrim when multiple live devices are present.
      if (!connected && !_demoMode) {
        _phase = DiscoveryPhase.timedOut;
        notifyListeners();
      }
    });
  }

  void _cancelTimeout() => _timeoutTimer?.cancel();

  void _onNetworkChanged() {
    final now = network.isConnected;
    if (now && !_wasConnected) {
      _cancelTimeout();
      _stopRetry();
    } else if (!now && _wasConnected && !_demoMode) {
      _restartTimeout(); // dropped — resume searching + reconnecting
      _startRetry();
    }
    _wasConnected = now;
    notifyListeners();
  }

  Future<void> _saveRecent(String host, int port) async {
    final entry = _format(host, port);
    _recents.remove(entry);
    _recents.insert(0, entry);
    if (_recents.length > _maxRecents) _recents.removeLast();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, _recents);
  }

  ({String host, int port})? _parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    String host = text;
    int port = _defaultPort;
    if (text.startsWith('[')) {
      final end = text.indexOf(']');
      if (end <= 1) return null;
      host = text.substring(1, end);
      final tail = text.substring(end + 1);
      if (tail.startsWith(':')) {
        final p = int.tryParse(tail.substring(1));
        if (p != null && p > 0 && p <= 65535) port = p;
      }
    } else if (':'.allMatches(text).length == 1) {
      final idx = text.lastIndexOf(':');
      host = text.substring(0, idx);
      final p = int.tryParse(text.substring(idx + 1));
      if (p == null || p <= 0 || p > 65535) return null;
      port = p;
    }
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    return host.isEmpty ? null : (host: host, port: port);
  }

  String _format(String host, int port) {
    if (port == _defaultPort) return host;
    return host.contains(':') ? '[$host]:$port' : '$host:$port';
  }

  @override
  void dispose() {
    network.removeListener(_onNetworkChanged);
    _timeoutTimer?.cancel();
    _retryTimer?.cancel();
    _stopBrowse();
    super.dispose();
  }
}
