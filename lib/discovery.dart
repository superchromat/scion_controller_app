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
  static const Duration _retryInterval = Duration(milliseconds: 1500);
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
  String? _connectedLabel;
  String? _connectedHost;
  bool _restartingBrowse = false;
  DateTime _browseStarted = DateTime.now();
  /// A browse is restarted only after this long without a device. The resolve of a found service takes ~5 s in
  /// this app on macOS (2026-10-30, 773292): restarting every 3 s, as it used to while disconnected, threw every
  /// browse away before it could resolve, so discovery could only succeed once something else had connected.
  static const Duration _browseRestartAfter = Duration(seconds: 15);
  int _candidateIdx = 0; // round-robin over the fallback endpoints (_fallbackCandidates)
  ({String host, int port})? _lastGood; // the endpoint this session last connected to

  /// Connection log: every discovery result, connect attempt and outcome, with a timestamp, in the app's own
  /// data directory (`scion_connect.log`, ~256 KB then rotated to `.1`), release builds included. 2026-10-30 the
  /// app stayed on "Couldn't find a SCION" while a typed IP connected at once, and nothing recorded why.
  static File? _logFile;
  static void log(String msg) {
    final line = '${DateTime.now().toIso8601String()} $msg';
    if (kDebugMode) debugPrint(line);
    try {
      _logFile ??= File('${Platform.environment['HOME'] ?? Directory.systemTemp.path}/scion_connect.log');
      final f = _logFile!;
      if (f.existsSync() && f.lengthSync() > 256 * 1024) f.renameSync('${f.path}.1');
      f.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  DiscoveryPhase get phase => _phase;
  List<NetworkAddress> get devices => List.unmodifiable(_devices);
  List<String> get recents => List.unmodifiable(_recents);
  bool get connected => network.isConnected;
  bool get demoMode => _demoMode;

  /// Friendly label of the current connection for display. Prefers a discovered
  /// device's mDNS name (e.g. `jorge.local`) for the endpoint we're on — even
  /// when we connected via a recent IP and mDNS surfaced the device only
  /// afterwards — falling back to whatever we dialed. Null when not connected.
  String? get connectedLabel {
    if (!connected) return null;
    final host = _connectedHost;
    if (host != null) {
      for (final d in _devices) {
        if (d.host == host && d.name != null) return d.name;
      }
    }
    return _connectedLabel;
  }

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

  /// Bumped by every browse start and every stop, so a start that is still
  /// awaiting `nsd.startDiscovery` can tell whether it has been superseded by
  /// the time it gets its handle back.
  ///
  /// `_discovery` alone cannot express that: it is null for the whole time a
  /// start is in flight, which made the null-checks below lie. Two bugs came
  /// out of that. Entering demo mode during that window ran `_stopBrowse` with
  /// nothing to stop, and the browse then installed itself *after* demo mode
  /// began — left running, and, because `_discovery` was no longer null,
  /// blocking the `_startBrowse` on the way out of demo mode. Separately, two
  /// callers could both pass the null-check and both start a browse, the
  /// second overwriting the first, orphaning a browse that nothing ever stops.
  int _browseGeneration = 0;

  Future<void> _startBrowse() async {
    if (_discovery != null || _demoMode) return;
    final generation = ++_browseGeneration;
    try {
      final discovery = await nsd.startDiscovery(_serviceType,
          autoResolve: true, ipLookupType: nsd.IpLookupType.any);
      // Anything could have happened while that was in flight: demo mode
      // entered, a stop requested, another browse started. Adopting a browse
      // that is already obsolete is what stranded discovery, so hand it back.
      if (_demoMode || generation != _browseGeneration || _discovery != null) {
        try {
          await nsd.stopDiscovery(discovery);
        } catch (_) {}
        return;
      }
      _discovery = discovery;
      _browseStarted = DateTime.now();
      discovery.addListener(_onServices);
      _onServices();
    } catch (e) {
      log('discovery: mDNS browse unavailable: $e');
    }
  }

  Future<void> _stopBrowse() async {
    // Supersede any start still in flight, so it disposes of its handle rather
    // than installing it behind our back.
    _browseGeneration++;
    final d = _discovery;
    _discovery = null;
    if (d != null) {
      d.removeListener(_onServices);
      try {
        await nsd.stopDiscovery(d);
      } catch (_) {}
    }
  }

  /// Tear down and re-create the browse to force a fresh mDNS query. A browse
  /// created before the network/cable was up won't re-discover the device on
  /// its own once it becomes reachable, so we re-kick it — otherwise we connect
  /// via a recent IP but never learn the device's name (label stuck on the IP).
  Future<void> _restartBrowse() async {
    if (_restartingBrowse || _demoMode) return;
    _restartingBrowse = true;
    try {
      await _stopBrowse();
      await _startBrowse();
    } finally {
      _restartingBrowse = false;
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
      String? host = hostForService(s.addresses, s.host);
      if (host == null || host.isEmpty) continue;
      while (host!.endsWith('.')) {
        host = host.substring(0, host.length - 1);
      }
      // Friendly label for display: the mDNS hostname (e.g. "jorge.local"),
      // falling back to the instance name. Tracks the device's real name even
      // when we connect via its resolved IP.
      String? name = s.host ?? s.name;
      if (name != null) {
        while (name!.endsWith('.')) {
          name = name.substring(0, name.length - 1);
        }
        if (name.isEmpty) name = null;
      }
      if (seen.add('$host:$port')) {
        list.add(NetworkAddress(host: host, port: port, name: name));
      }
    }
    log('discovery: ${d.services.length} service(s) '
        '${d.services.map((x) => '${x.name} host=${x.host} port=${x.port} addrs=${x.addresses}').toList()} '
        '-> devices $list');
    _devices = list;
    _tryReconnect();
    notifyListeners();
  }

  /// Where to dial a discovered service: its best usable address, else its
  /// mDNS hostname.
  ///
  /// Addresses that cannot be dialled are dropped rather than used. mDNS
  /// announces a service as soon as it appears, which can be before its A
  /// record is known — nsd reports that as the unspecified address, 0.0.0.0.
  /// Taking that at face value did not merely waste one connect attempt. A
  /// service at 0.0.0.0 still counts as a discovered device, so [_autoTarget]
  /// locks on to it, [_tryReconnect] returns before it ever reaches
  /// [_fallbackHost], and the retry loop stops re-browsing because the device
  /// list is no longer empty. The app then hunts an address that can never
  /// answer, indefinitely — which is exactly what unplugging the device,
  /// entering demo mode, replugging and leaving demo mode produced.
  ///
  /// Falling back to the mDNS hostname is safe: it is [_fallbackHost] by
  /// another name, and it resolves once the device is up.
  @visibleForTesting
  static String? hostForService(
      List<InternetAddress>? addresses, String? hostname) {
    final usable = (addresses ?? const <InternetAddress>[])
        .where((a) =>
            !a.isLoopback && a.address != '0.0.0.0' && a.address != '::')
        .toList();
    if (usable.isEmpty) return hostname;
    // Several different IPv4 addresses (e.g. an old lease still cached): dial the name, whose addresses
    // Network.connect tries in turn, rather than always the first.
    final distinct = usable
        .where((a) => a.type == InternetAddressType.IPv4 && !isLinkLocalV4(a))
        .map((a) => a.address)
        .toSet();
    if (distinct.length > 1 && hostname != null && hostname.isNotEmpty) return hostname;
    // A device also holding an IPv4 link-local address (169.254/16, autoconf while DHCP was slow at boot) can
    // list it beside its DHCP address; the host is usually not on 169.254, so that one goes last.
    final v4 = usable.where((a) => a.type == InternetAddressType.IPv4).toList()
      ..sort((a, b) => (isLinkLocalV4(a) ? 1 : 0) - (isLinkLocalV4(b) ? 1 : 0));
    return (v4.isNotEmpty ? v4.first : usable.first).address;
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

  /// Try to (re)connect: a discovered auto-target first, then one of the other endpoints we know (this session's
  /// last, every recent, the well-known hostname), a different one each tick, for as long as we are disconnected.
  ///
  /// It used to try only the first recent and, only after the timeout, scion.local; with several devices listed it
  /// tried nothing. Any one of those being dead or unresolvable left the app searching while a typed IP connected
  /// at once (2026-10-30).
  Future<void> _tryReconnect() async {
    if (connected || _busy || _demoMode) return;
    final target = _autoTarget();
    if (target != null) {
      if (await _connect(target.host, target.port,
          label: target.name ?? target.host)) {
        return;
      }
    }
    final cands = _fallbackCandidates();
    if (cands.isEmpty || connected) return;
    final c = cands[_candidateIdx++ % cands.length];
    if (target != null && c.host == target.host && c.port == target.port) return;
    await _connect(c.host, c.port, label: c.host);
  }

  /// Endpoints to fall back on, most likely first. With several devices listed and none of them known, the user
  /// picks: only endpoints we have used before are tried then (never the ambiguous well-known hostname).
  List<({String host, int port})> _fallbackCandidates() {
    final out = <({String host, int port})>[];
    final seen = <String>{};
    void add(String h, int p) {
      if (seen.add('$h:$p')) out.add((host: h, port: p));
    }

    final lg = _lastGood;
    if (lg != null) add(lg.host, lg.port);
    for (final r in _recents) {
      final ep = _parse(r);
      if (ep != null) add(ep.host, ep.port);
    }
    if (_devices.length <= 1) add(_fallbackHost, _defaultPort);
    return out;
  }

  Future<bool> _connect(String host, int port, {String? label}) async {
    if (_busy || connected || _demoMode) return connected;
    _busy = true;
    notifyListeners();
    final t0 = DateTime.now();
    try {
      log('connect $host:$port (phase ${_phase.name}, devices ${_devices.length}, recents $_recents)');
      await network.connect(host, port, userInitiated: false);
      final ok = await _waitConnected(_connectWait);
      log('connect $host:$port ${ok ? 'OK' : 'FAILED'} after ${DateTime.now().difference(t0).inMilliseconds} ms');
      if (ok) {
        _lastGood = (host: host, port: port);
        _connectedLabel = label ?? host;
        _connectedHost = host;
        await _saveRecent(host, port);
      }
      return ok;
    } catch (e) {
      log('connect $host:$port threw $e');
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
    return _connect(host, port, label: host);
  }

  /// Manual re-scan (the demoted "find" button). Discovery already runs
  /// continuously; this just resets the search state and re-evaluates.
  void rescan() {
    if (_demoMode) return;
    _restartTimeout();
    // _restartBrowse, not _startBrowse: pressing "Rescan" while a browse was
    // already up did nothing at all, because _startBrowse returns immediately
    // when one exists. The point of the button is to throw away a browse that
    // has not found the device and ask again.
    _restartBrowse();
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
    _retryTimer = Timer.periodic(_retryInterval, (_) {
      if (connected) return;
      // Until we've found a device, re-query mDNS now and then: a browse started before the network/cable was up
      // won't find the device on its own once it becomes reachable. Not more often than _browseRestartAfter: a
      // fresh browse needs ~5 s to resolve what it finds. The connect is retried every tick.
      if (_devices.isEmpty &&
          DateTime.now().difference(_browseStarted) > _browseRestartAfter) {
        log('discovery: nothing in ${_browseRestartAfter.inSeconds} s, browse restarted');
        _restartBrowse();
      }
      _tryReconnect();
    });
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
      log('connected (${network.destinationLabel})');
      _cancelTimeout();
      // The retry loop keeps running (a tick returns at once while connected): stopping it here left no driver
      // when a later drop was not seen as one.
      // We may have connected via a recent IP before discovery surfaced the
      // device. Re-kick the browse so we learn its mDNS name and connectedLabel
      // can upgrade from the bare IP to e.g. "jorge.local".
      if (_devices.every((d) => d.host != _connectedHost)) _restartBrowse();
    } else if (!now && _wasConnected && !_demoMode) {
      log('disconnected');
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
    await _persistRecents();
  }

  Future<void> _persistRecents() async {
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
