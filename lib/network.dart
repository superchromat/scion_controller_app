import 'dart:async';
import 'dart:io';
import 'package:osc/osc.dart';
import 'package:flutter/foundation.dart';

import 'osc_widget_binding.dart';

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
/// - Automatically sends "/ack" every 2s, and disconnects if no "/ack" received within 5s.
/// - Incoming messages are dispatched via OscRegistry.
class Network extends ChangeNotifier {
  RawDatagramSocket? _socket;
  InternetAddress? _destination;
  int? _port;
  final List<_Pending> _pending = [];

  Timer? _ackTimer;
  Timer? _monitorTimer;
  DateTime? _lastAckReceived;

  bool get isConnected =>
      _socket != null && _destination != null && _port != null;

  /// Binds a UDP socket on an ephemeral port and sets the remote host/port.
  /// Always resolves to an IPv4 address to avoid sending IPv6 via an IPv4 socket.
  Future<void> connect(String host, int txPort,
      {Duration timeout = const Duration(seconds: 5)}) async {
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

    // initialize ack tracking
    _lastAckReceived = DateTime.now();
    // send an immediate ack to prime
    sendOscMessage('/ack', []);
    // every 2 seconds, send /ack
    _ackTimer?.cancel();
    _ackTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      try {
        sendOscMessage('/ack', []);
      } catch (e, st) {
        debugPrint('⚠️ periodic /ack send error: $e\n$st');
      }
    });
    // every 1 second, check for ack timeout
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lastAckReceived != null &&
          DateTime.now().difference(_lastAckReceived!).inSeconds > 5) {
        debugPrint('🔴 No /ack received in 5s; disconnecting');
//        disconnect();
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

    notifyListeners();
  }

  /// Sends an OSC message to the remote host, deferring if the buffer is full.
  void sendOscMessage(String address, List<Object> arguments) {
    if (!isConnected) {
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
          if (msg.address == '/ack') {
            _lastAckReceived = DateTime.now();
          }
          debugPrint('Received OSC ${msg.address} args=${msg.arguments}');
          OscRegistry().dispatch(msg.address, msg.arguments);
        } catch (e) {
          debugPrint(
              'Error parsing packet from ${dg.address.address}:${dg.port}');
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
}

/// Global singleton
final network = Network();
