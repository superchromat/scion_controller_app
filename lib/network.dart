/// network.dart
import 'dart:async';
import 'dart:io';
import 'package:osc/osc.dart';

/// Internal class to hold deferred sends
class _Pending {
  final List<int> data;
  final InternetAddress dest;
  final int port;
  _Pending(this.data, this.dest, this.port);
}

class Network {
  RawDatagramSocket? _socket;
  InternetAddress? _destination;
  int? _port;
  final List<_Pending> _pending = [];

  /// True only when socket is bound and destination/port are valid
  bool get isReady =>
      _socket != null &&
      _destination != null &&
      _port != null &&
      _port! > 0 &&
      _destination!.address != InternetAddress.anyIPv4.address;

  bool get isConnected => isReady;

  /// Bind socket and resolve host
  Future<void> connect(String host, int txPort,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final dest = InternetAddress.tryParse(host) ??
        (await InternetAddress.lookup(host)).first;
    _destination = dest;
    _port = txPort;

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
    ).timeout(timeout);
    _socket!
      ..writeEventsEnabled = false
      ..listen(_onSocketEvent);
  }

  /// Close socket and clear queued messages
  void disconnect() {
    _socket?.close();
    _socket = null;
    _destination = null;
    _port = null;
    _pending.clear();
  }

  /// Send an OSC message, queue if buffer is full
  void sendOscMessage(String address, List<Object> arguments) {
    if (!isReady) {
      print('Not connected or not ready');
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
      print('OSC send failed: \$e');
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.write && _pending.isNotEmpty) {
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
        print('Deferred OSC send failed: \$e');
        _pending.clear();
        _socket!.writeEventsEnabled = false;
      }
    }
  }
}

/// Global singleton
final network = Network();
