import 'dart:async';
import 'dart:io';
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
  Timer? _reconnectTimer;
  DateTime? _lastMsgReceived;
  bool _hasSynced = false;

  String? _lastHost;
  int? _lastPort;

  bool get isConnected =>
      _socket != null && _destination != null && _port != null && _hasSynced;

  bool get isConnecting => _socket != null && !_hasSynced;

  /// Binds a UDP socket on an ephemeral port and sets the remote host/port.
  /// Always resolves to an IPv4 address to avoid sending IPv6 via an IPv4 socket.
  Future<void> connect(String host, int txPort,
      {Duration timeout = const Duration(seconds: 5)}) async {
    // remember target for auto-reconnect attempts
    _lastHost = host;
    _lastPort = txPort;
    // resolve remote address as IPv4
    InternetAddress dest;
    final parsed = InternetAddress.tryParse(host);
    if (parsed != null && parsed.type == InternetAddressType.IPv4) {
      dest = parsed;
    } else {
      final addrs = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      );
      if (addrs.isEmpty) {
        throw SocketException('No IPv4 address found for \$host');
      }
      dest = addrs.first;
    }
    _destination = dest;
    _port = txPort;

    // bind locally on port 0 (ephemeral)
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
    ).timeout(timeout);

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
    // Send /sync frequently while waiting for /ack
    _ackTimer?.cancel();
    _ackTimer = Timer.periodic(const Duration(seconds: 10), (t) {
      try {
        sendOscMessage('/sync', []);
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
    if (!isConnected && (address != "/sync")) {
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
        await connect(_lastHost!, _lastPort!);
      } catch (e, st) {
        if (kDebugMode) debugPrint('Auto-reconnect failed: $e\n$st');
        // keep timer running; will retry on next tick
      }
    });
  }
}
