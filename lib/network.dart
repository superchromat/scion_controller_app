// network.dart
import 'dart:async';
import 'dart:io';
import 'package:osc/osc.dart';
import 'package:flutter/foundation.dart';

import 'OscWidgetBinding.dart';

/// Internal class to hold deferred sends
class _Pending {
  final List<int> data;
  final InternetAddress dest;
  final int port;
  _Pending(this.data, this.dest, this.port);
}

/// A singleton UDP/OSC network handler.
///
/// - `connect(host, txPort, {rxPort})` binds a socket on rxPort (or ephemeral) and
///   sets the send-destination to host:txPort.
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

  /// Binds a UDP socket to receive on [rxPort] (or ephemeral port if null),
  /// and sets destination to [host]:[txPort].
  Future<void> connect(String host, int txPort,
      {int? rxPort, Duration timeout = const Duration(seconds: 5)}) async {
    final dest = InternetAddress.tryParse(host) ??
        (await InternetAddress.lookup(host)).first;
    _destination = dest;
    _port = txPort;

    final bindPort = rxPort ?? 0;
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      bindPort,
    ).timeout(timeout);

    _socket!
      ..writeEventsEnabled = false
      ..listen(_onSocketEvent);

    // initialize ack tracking
    _lastAckReceived = DateTime.now();
    // send an immediate ack to prime
    sendOscMessage('/ack', []);
    // every 2 seconds, send /ack
    _ackTimer?.cancel();
    _ackTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      sendOscMessage('/ack', []);
    });
    // every 1 second, check for ack timeout
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lastAckReceived != null &&
          DateTime.now().difference(_lastAckReceived!).inSeconds > 5) {
        // no ack in 5 seconds → disconnect
        print ("DISABLED DISCONNECT FOR DEBUGGING");
       // disconnect();
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

  /// Sends an OSC message to the remote host, deferring if the socket buffer is full.
  void sendOscMessage(String address, List<Object> arguments) {
    if (!isConnected) {
      print('Not connected');
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
      print('OSC send failed: $e');
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      Datagram? dg = _socket!.receive();
      while (dg != null) {
        try {
          final msg = OSCMessage.fromBytes(dg.data);
          // track acks
          if (msg.address == '/ack') {
            _lastAckReceived = DateTime.now();
          }
          print('Received OSC ${msg.address} args=${msg.arguments}');
          OscRegistry().dispatch(msg.address, msg.arguments);
        } catch (e) {
          print('Received UDP ${dg.address.address}:${dg.port} ${dg.data}');
        }
        dg = _socket!.receive();
      }
    } else if (event == RawSocketEvent.write && _pending.isNotEmpty) {
      final p = _pending.first;
      try {
        final sent = _socket!.send(p.data, p.dest, p.port);
        if (sent == p.data.length) {
          _pending.removeAt(0);
          if (_pending.isEmpty) {
            _socket!.writeEventsEnabled = false;
          }
        }
      } on SocketException catch (e) {
        print('Deferred OSC send failed: $e');
        _pending.clear();
        _socket!.writeEventsEnabled = false;
      }
    }
  }
}

/// Global singleton
final network = Network();
