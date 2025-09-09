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
  // When true, send a full "/sync" right after a successful auto-reconnect
  bool _pendingSyncAfterAutoReconnect = false;
  DateTime? _lastMsgReceived;
  bool _hasSynced = false;

  String? _lastHost;
  int? _lastPort;

  bool get isConnected =>
      _socket != null && _destination != null && _port != null && _hasSynced;

  bool get isConnecting => _socket != null && !_hasSynced;

  /// Binds a UDP socket on an ephemeral port and sets the remote host/port.
  /// Prefers IPv4 but falls back to IPv6 if necessary, and binds a socket that
  /// matches the destination address family.
  Future<void> connect(String host, int txPort,
      {Duration timeout = const Duration(seconds: 5)}) async {
    // remember target for auto-reconnect attempts
    _lastHost = host;
    _lastPort = txPort;
    // resolve remote address; prefer IPv4, fall back to IPv6
    InternetAddress dest;
    final parsed = InternetAddress.tryParse(host);
    if (parsed != null) {
      dest = parsed;
    } else {
      List<InternetAddress> addrs = [];
      try {
        addrs = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
      } catch (_) {
        addrs = const [];
      }
      if (addrs.isEmpty) {
        // fall back to IPv6 lookup
        addrs = await InternetAddress.lookup(host, type: InternetAddressType.IPv6);
      }
      if (addrs.isEmpty) {
        throw SocketException('No IP address found for $host');
      }
      dest = addrs.first;
    }
    _destination = dest;
    _port = txPort;

    // bind locally on port 0 (ephemeral), matching destination IP family
    final bindAddr = (dest.type == InternetAddressType.IPv6)
        ? InternetAddress.anyIPv6
        : InternetAddress.anyIPv4;
    _socket = await RawDatagramSocket.bind(bindAddr, 0).timeout(timeout);

    final localPort = _socket!.port;
    if (kDebugMode) debugPrint('Network bound locally on port $localPort');

    _socket!
      ..writeEventsEnabled = false
      ..listen((event) {
        try {
          _onSocketEvent(event);
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
      if (_lastMsgReceived != null &&
          DateTime.now().difference(_lastMsgReceived!).inSeconds > 10) {
        debugPrint('No msg received in 10s; disconnecting');
        disconnect();
      }
    });

    notifyListeners();
  }

  /// Closes the socket, stops timers, and clears queued messages.
  void disconnect() {
    _ackTimer?.cancel();
    _monitorTimer?.cancel();
    _heartbeatTimer?.cancel();
    _socket?.close();
    _socket = null;
    _destination = null;
    _port = null;
    _pending.clear();
    _hasSynced = false;

    notifyListeners();

    // kick off auto-reconnect attempts to the last target
    _scheduleReconnect();
  }

  /// Sends an OSC message to the remote host, deferring if the buffer is full.
  void sendOscMessage(String address, List<Object> arguments) {
    // Hard block: never send Y LUT over the network
    // Matches any address ending with "/lut/Y" (e.g., "/send/1/lut/Y")
    final segs = address.split('/').where((s) => s.isNotEmpty).toList();
    final isYLut = segs.length >= 2 && segs[segs.length - 2] == 'lut' && segs.last == 'Y';
    if (isYLut) {
      if (kDebugMode) debugPrint('Skipping send for Y LUT at "$address"');
      return;
    }

    if (!isConnected && (address != "/sync" && address != "/ack")) {
      debugPrint('Not connected');
      return;
    }
    final message = OSCMessage(address, arguments: arguments);
    final data = message.toBytes();

    try {
      final sent = _socket!.send(data, _destination!, _port!);
      if (sent != data.length) {
        _pending.add(_Pending(data, _destination!, _port!));
        _socket!.writeEventsEnabled = true;
      }
    } on SocketException catch (e) {
      debugPrint('Deferred OSC send failed: $e');
      _pending.clear();
      _socket!.writeEventsEnabled = false;
    } on OSError catch (e) {
      debugPrint('OSC send failed (OSError): $e');
      _pending.clear();
      _socket!.writeEventsEnabled = false;
    } catch (e) {
      debugPrint('OSC send failed: $e');
      _pending.clear();
      _socket!.writeEventsEnabled = false;
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

  void _onSocketEvent(RawSocketEvent event) {
    if (_socket == null) return;
    if (event == RawSocketEvent.read) {
      Datagram? dg = _socket!.receive();
      while (dg != null) {
        try {
          final msg = OSCMessage.fromBytes(dg.data);
          _lastMsgReceived = DateTime.now();
          if (msg.address != '/ack') {
            debugPrint('Received OSC ${msg.address} args=${msg.arguments}');
            OscRegistry().dispatch(msg.address, msg.arguments);
        } else {
            _hasSynced = true;
            // on successful sync, stop any reconnect attempts
            _reconnectTimer?.cancel();
            // stop waiting-for-ack timer
            _ackTimer?.cancel();
            // start heartbeat to keep link healthy without full syncs
            _heartbeatTimer?.cancel();
            _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
              try { sendOscMessage('/ack', []); } catch (_) {}
            });
            // If this ACK finalized an auto-reconnect, issue a full sync now
            if (_pendingSyncAfterAutoReconnect) {
              try { sendOscMessage('/sync', []); } catch (_) {}
              _pendingSyncAfterAutoReconnect = false;
            }
            notifyListeners();
          }
        } catch (e) {
          debugPrint(
              'Error parsing packet ($e) from ${dg.address.address}:${dg.port}');
        }
        dg = _socket!.receive();
      }
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

  void _scheduleReconnect() {
    if (_lastHost == null || _lastPort == null) return;
    // prevent multiple timers
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (isConnected || isConnecting) return;
      try {
        if (kDebugMode) {
          debugPrint('Attempting auto-reconnect to $_lastHost:$_lastPort');
        }
        // Mark that we should perform a full sync after this auto-reconnect
        _pendingSyncAfterAutoReconnect = true;
        await connect(_lastHost!, _lastPort!);
      } catch (e, st) {
        if (kDebugMode) debugPrint('Auto-reconnect failed: $e\n$st');
        // keep timer running; will retry on next tick
      }
    });
  }
}
