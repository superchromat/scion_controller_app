import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:osc/osc.dart';
import 'package:flutter/foundation.dart';

import 'osc_registry.dart';

/// Internal class to hold deferred sends
class _Pending {
  final List<int> data;
  final InternetAddress dest;
  final int port;
  _Pending(this.data, this.dest, this.port);
}

/// A singleton UDP/OSC network handler.
///
/// - `connect(host, txPort)` binds a socket on an ephemeral local port
///   and sets the send-destination to host:txPort.
/// - `sendOscMessage(address, args)` sends an OSC packet, queuing if needed.
/// - Incoming messages are dispatched via OscRegistry.
class Network extends ChangeNotifier {
  RawDatagramSocket? _socket;
  InternetAddress? _destination;
  int? _port;
  final List<_Pending> _pending = [];

  Timer? _ackTimer;
  Timer? _monitorTimer;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _drainResumeTimer;
  DateTime? _suppressUntil; // suppress inactivity disconnect until this time
  DateTime? _lastAckTime;   // last time we received an /ack
  bool _manualConnectInProgress = false;
  bool _connectInFlight = false;
  int _connectGeneration = 0;
  // When true, send a full "/sync" right after a successful auto-reconnect
  bool _pendingSyncAfterAutoReconnect = false;
  DateTime? _lastMsgReceived;
  bool _hasSynced = false;

  bool get _handshakeInProgress => _socket != null && !_hasSynced;

  static const int _maxDatagramsPerDrain = 64;

  String? _lastHost;
  int? _lastPort;

  bool get isConnected =>
      _socket != null && _destination != null && _port != null && _hasSynced;

  /// When true, the inactivity monitor will not disconnect even if no
  /// messages are received. Useful while waiting for a controlled reboot
  /// during firmware upgrade.
  bool get _timeoutsSuppressed =>
      _suppressUntil != null && DateTime.now().isBefore(_suppressUntil!);

  DateTime? get lastAckTime => _lastAckTime;

  bool get isConnecting => _manualConnectInProgress && _handshakeInProgress;

  String _normalizeHost(String host) {
    var out = host.trim();
    while (out.endsWith('.')) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  /// Binds a UDP socket on an ephemeral port and sets the remote host/port.
  /// Prefers IPv4 but falls back to IPv6 if necessary, and binds a socket that
  /// matches the destination address family.
  Future<void> connect(String host, int txPort,
      {Duration timeout = const Duration(seconds: 5),
      bool userInitiated = true}) async {
    final normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      throw SocketException('Host is empty');
    }

    final int generation = ++_connectGeneration;
    _connectInFlight = true;
    // remember target for auto-reconnect attempts
    _lastHost = normalizedHost;
    _lastPort = txPort;
    if (userInitiated) {
      _manualConnectInProgress = true;
      _reconnectTimer?.cancel();
      notifyListeners();
    }

    _ackTimer?.cancel();
    _monitorTimer?.cancel();
    _heartbeatTimer?.cancel();
    _drainResumeTimer?.cancel();
    _drainResumeTimer = null;
    _pending.clear();
    _hasSynced = false;

    _closeCurrentSocket();

    try {
      // resolve remote address; prefer IPv4, fall back to IPv6
      InternetAddress dest;
      final parsed = InternetAddress.tryParse(normalizedHost);
      if (parsed != null) {
        dest = parsed;
      } else {
        List<InternetAddress> addrs = [];
        try {
          addrs = await InternetAddress.lookup(normalizedHost,
              type: InternetAddressType.IPv4);
        } catch (_) {
          addrs = const [];
        }
        if (addrs.isEmpty) {
          // fall back to IPv6 lookup
          addrs = await InternetAddress.lookup(normalizedHost,
              type: InternetAddressType.IPv6);
        }
        if (addrs.isEmpty) {
          throw SocketException('No IP address found for $normalizedHost');
        }
        dest = addrs.first;
      }
      if (generation != _connectGeneration) {
        return;
      }

      _destination = dest;
      _port = txPort;

      // bind locally on port 0 (ephemeral), matching destination IP family
      final bindAddr = (dest.type == InternetAddressType.IPv6)
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4;
      final socket = await RawDatagramSocket.bind(bindAddr, 0).timeout(timeout);

      if (generation != _connectGeneration) {
        socket.close();
        return;
      }

      _socket = socket;

      final localPort = socket.port;
      if (kDebugMode) debugPrint('Network bound locally on port $localPort');

      socket
        ..writeEventsEnabled = false
        ..listen((event) {
          try {
            _onSocketEvent(socket, event);
          } catch (e, st) {
            debugPrint('⚠️ _onSocketEvent error: $e\n$st');
          }
        });

      // initialize response tracking
      _lastMsgReceived = DateTime.now();
      // send an immediate sync
      sendOscMessage('/sync', []);
      // While waiting for /ack, ping with /ack (lightweight) to elicit a reply
      _ackTimer?.cancel();
      _ackTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        try {
          sendOscMessage('/ack', []);
        } catch (e, st) {
          debugPrint('Periodic /sync send error: $e\n$st');
          // Do not force disconnect here; monitor handles timeouts.
        }
      });
      // Monitor timeout
      _monitorTimer?.cancel();
      _monitorTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_timeoutsSuppressed) return;
        if (_lastMsgReceived != null &&
            DateTime.now().difference(_lastMsgReceived!).inSeconds > 10) {
          debugPrint('No msg received in 10s; disconnecting');
          disconnect();
        }
      });

      notifyListeners();
    } catch (e) {
      if (userInitiated && generation == _connectGeneration) {
        _manualConnectInProgress = false;
        notifyListeners();
      }
      rethrow;
    } finally {
      if (generation == _connectGeneration) {
        _connectInFlight = false;
      }
    }
  }

  /// Closes the socket, stops timers, and clears queued messages.
  void disconnect() {
    _ackTimer?.cancel();
    _monitorTimer?.cancel();
    _heartbeatTimer?.cancel();
    _drainResumeTimer?.cancel();
    _drainResumeTimer = null;
    _manualConnectInProgress = false;
    _connectGeneration++;
    _closeCurrentSocket();
    _destination = null;
    _port = null;
    _pending.clear();
    _hasSynced = false;
    _connectInFlight = false;

    notifyListeners();

    // kick off auto-reconnect attempts to the last target
    _scheduleReconnect();
  }

  /// Sends an OSC message to the remote host, deferring if the buffer is full.
  /// Returns true when the message was accepted for transmit (sent or queued).
  bool sendOscMessage(String address, List<Object> arguments) {
    // Hard block: never send Y LUT over the network
    // Matches any address ending with "/lut/Y" (e.g., "/send/1/lut/Y")
    final segs = address.split('/').where((s) => s.isNotEmpty).toList();
    final isYLut =
        segs.length >= 2 && segs[segs.length - 2] == 'lut' && segs.last == 'Y';
    if (isYLut) {
      if (kDebugMode) debugPrint('Skipping send for Y LUT at "$address"');
      return false;
    }

    if (!isConnected && (address != "/sync" && address != "/ack")) {
      debugPrint('Not connected');
      return false;
    }
    final message = OSCMessage(address, arguments: arguments);
    final data = message.toBytes();

    try {
      final sent = _socket!.send(data, _destination!, _port!);
      if (sent != data.length) {
        _pending.add(_Pending(data, _destination!, _port!));
        _socket!.writeEventsEnabled = true;
      }
      return true;
    } on SocketException catch (e) {
      debugPrint('Deferred OSC send failed: $e');
      _pending.clear();
      _socket!.writeEventsEnabled = false;
      return false;
    } on OSError catch (e) {
      debugPrint('OSC send failed (OSError): $e');
      _pending.clear();
      _socket!.writeEventsEnabled = false;
      return false;
    } catch (e) {
      debugPrint('OSC send failed: $e');
      _pending.clear();
      _socket!.writeEventsEnabled = false;
      return false;
    }
  }

  /// Sends an OSC bundle containing multiple messages in a single datagram.
  /// Applies same connection checks and deferred send handling as single send.
  void sendOscBundle(List<OSCMessage> messages) {
    if (!isConnected) {
      debugPrint('Not connected');
      return;
    }
    // Build OSC bundle: '#bundle\0' + 8-byte timetag + N elements
    // Each element: 4-byte big-endian size + message bytes
    final bb = BytesBuilder();
    bb.add(utf8.encode('#bundle'));
    bb.add([0]); // null terminator to make 8-byte header
    // timetag: immediate (0,1) big-endian
    final tt = ByteData(8);
    tt.setUint32(0, 0, Endian.big); // seconds
    tt.setUint32(4, 1, Endian.big); // fractional, 'immediate'
    bb.add(tt.buffer.asUint8List());

    for (final m in messages) {
      final mb = m.toBytes();
      final sz = ByteData(4)..setUint32(0, mb.length, Endian.big);
      bb.add(sz.buffer.asUint8List());
      bb.add(mb);
    }

    final data = bb.toBytes();
    try {
      final sent = _socket!.send(data, _destination!, _port!);
      if (sent != data.length) {
        _pending.add(_Pending(data, _destination!, _port!));
        _socket!.writeEventsEnabled = true;
      }
    } on SocketException catch (e) {
      debugPrint('Deferred OSC bundle send failed: $e');
      _pending.clear();
      _socket!.writeEventsEnabled = false;
    } on OSError catch (e) {
      debugPrint('OSC bundle send failed (OSError): $e');
      _pending.clear();
      _socket!.writeEventsEnabled = false;
    } catch (e) {
      debugPrint('OSC bundle send failed: $e');
      _pending.clear();
      _socket!.writeEventsEnabled = false;
    }
  }

  void _onSocketEvent(RawDatagramSocket socket, RawSocketEvent event) {
    if (!identical(_socket, socket)) {
      if (event == RawSocketEvent.read) {
        while (socket.receive() != null) {
          // drain stale socket
        }
      }
      return;
    }
    if (event == RawSocketEvent.read) {
      _drainIncomingDatagrams(socket);
    } else if (event == RawSocketEvent.write && _pending.isNotEmpty) {
      final p = _pending.first;
      try {
        final sent = _socket!.send(p.data, p.dest, p.port);
        if (sent == p.data.length) {
          _pending.removeAt(0);
          if (_pending.isEmpty) _socket!.writeEventsEnabled = false;
        }
      } on SocketException catch (e) {
        debugPrint('Deferred OSC send failed: $e');
        _pending.clear();
        _socket!.writeEventsEnabled = false;
      } on OSError catch (e) {
        debugPrint('Deferred send OSError: $e');
        _pending.clear();
        _socket!.writeEventsEnabled = false;
      } catch (e) {
        debugPrint('Deferred send failed: $e');
        _pending.clear();
        _socket!.writeEventsEnabled = false;
      }
    }
  }

  void _drainIncomingDatagrams(RawDatagramSocket socket) {
    if (!identical(_socket, socket)) return;
    var processed = 0;
    Datagram? dg = socket.receive();
    while (dg != null) {
      _handleDatagram(dg);
      processed++;

      if (processed >= _maxDatagramsPerDrain) {
        _scheduleDatagramDrain(socket);
        return;
      }

      dg = socket.receive();
    }
  }

  void _handleDatagram(Datagram dg) {
    try {
      final msg = OSCMessage.fromBytes(dg.data);
      _lastMsgReceived = DateTime.now();
      if (msg.address != '/ack') {
        debugPrint('Received OSC ${msg.address} args=${msg.arguments}');
        OscRegistry().dispatch(msg.address, msg.arguments);
      } else {
        _hasSynced = true;
        _lastAckTime = DateTime.now();
        _manualConnectInProgress = false;
        // on successful sync, stop any reconnect attempts
        _reconnectTimer?.cancel();
        // stop waiting-for-ack timer
        _ackTimer?.cancel();
        // start heartbeat to keep link healthy without full syncs
        _heartbeatTimer?.cancel();
        _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          try {
            sendOscMessage('/ack', []);
          } catch (_) {}
        });
        // If this ACK finalized an auto-reconnect, issue a full sync now
        if (_pendingSyncAfterAutoReconnect) {
          try {
            sendOscMessage('/sync', []);
          } catch (_) {}
          _pendingSyncAfterAutoReconnect = false;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint(
          'Error parsing packet ($e) from ${dg.address.address}:${dg.port}');
    }
  }

  void _scheduleDatagramDrain(RawDatagramSocket socket) {
    _drainResumeTimer ??= Timer(Duration.zero, () {
      _drainResumeTimer = null;
      if (!identical(_socket, socket)) return;
      _drainIncomingDatagrams(socket);
    });
  }

  void _scheduleReconnect() {
    if (_lastHost == null || _lastPort == null) return;
    // prevent multiple timers
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (isConnected || _handshakeInProgress || _connectInFlight) return;
      try {
        if (kDebugMode) {
          debugPrint('Attempting auto-reconnect to $_lastHost:$_lastPort');
        }
        // Mark that we should perform a full sync after this auto-reconnect
        _pendingSyncAfterAutoReconnect = true;
        await connect(_lastHost!, _lastPort!, userInitiated: false);
      } catch (e, st) {
        if (kDebugMode) debugPrint('Auto-reconnect failed: $e\n$st');
        // keep timer running; will retry on next tick
      }
    });
  }

  void _closeCurrentSocket() {
    _socket?.close();
    _socket = null;
  }

  /// Suppress inactivity-based disconnects for [duration]. Use when a device
  /// is expected to reboot (e.g., after firmware upgrade), so we don't tear
  /// down the connection preemptively.
  void suppressTimeoutsFor(Duration duration) {
    _suppressUntil = DateTime.now().add(duration);
  }
}
