// network.dart
import 'dart:async';
import 'dart:io';
import 'package:osc/osc.dart';
import 'OscLog.dart';
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
/// - Incoming UDP messages are printed to stdout.
class Network {
  RawDatagramSocket? _socket;
  InternetAddress? _destination;
  int? _port;
  final List<_Pending> _pending = [];

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
  }

  /// Closes the socket and clears queued messages.
  void disconnect() {
    _socket?.close();
    _socket = null;
    _destination = null;
    _port = null;
    _pending.clear();
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
          print('Received OSC ${msg.address} args=${msg.arguments}');
          final logState = oscLogKey.currentState;

             logState?.logOscMessage(
        address: msg.address,
        arg: msg.arguments,
        status: OscStatus.ok,
        direction: Direction.received,
        binary: dg.data);
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
