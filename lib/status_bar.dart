import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'network.dart';

class StatusBarRow extends StatefulWidget {
  final String rightText;
  const StatusBarRow({
    Key? key,
    this.rightText = "Status Right",
  }) : super(key: key);

  @override
  _StatusBarRowState createState() => _StatusBarRowState();
}

class _StatusBarRowState extends State<StatusBarRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _flashController;
  late VoidCallback _netListener;
  bool _connected = false;
  Timer? _flashStopTimer;

  @override
  void initState() {
    super.initState();
    final network = context.read<Network>();
    _connected = network.isConnected;

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), 
    )
      ..addListener(() {
      if (!_connected) setState(() {});
    });

    _netListener = () {
      final nowConn = context.read<Network>().isConnected;
      if (nowConn != _connected) {
        setState(() => _connected = nowConn);
        if (nowConn) {
          _stopFlashing();
        } else {
          _startFlashing();
        }
      }
    };
    network.addListener(_netListener);
  }

  void _startFlashing() {
    _flashStopTimer?.cancel();
    _flashController.repeat(reverse: true);
    _flashStopTimer = Timer(const Duration(seconds: 3), () {
      _stopFlashing();
    });
  }

  void _stopFlashing() {
    _flashStopTimer?.cancel();
    _flashController.stop();
    _flashController.value = 0.0;
  }

  @override
  void dispose() {
    context.read<Network>().removeListener(_netListener);
    _flashStopTimer?.cancel();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Choose text + color
    final leftText = _connected ? "Connected" : "DISCONNECTED";
    Color leftColor;
    if (_connected) {
      leftColor = Colors.green;
    } else if (_flashController.isAnimating) {
      leftColor = Color.lerp(
          Colors.red.shade900, Colors.yellow, _flashController.value)!;
    } else {
      leftColor = Colors.red;
    }

    return Container(
      color: const Color.fromARGB(255, 20, 20, 20),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            leftText,
            style: TextStyle(
              fontFamily: 'courier',
              fontSize: 12,
              letterSpacing: 1.0,
              color: leftColor,
            ),
          ),
          Text(
            widget.rightText,
            style: const TextStyle(
              fontFamily: 'courier',
              fontSize: 12,
              letterSpacing: 1.0,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
