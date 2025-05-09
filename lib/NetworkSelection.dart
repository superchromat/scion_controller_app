// NetworkSelection.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'network.dart';
import 'LabeledCard.dart';

class NetworkConnectionSection extends StatefulWidget {
  const NetworkConnectionSection({super.key});

  @override
  State<NetworkConnectionSection> createState() => _NetworkConnectionSectionState();
}

class _NetworkConnectionSectionState extends State<NetworkConnectionSection> {
  final TextEditingController addressController =
      TextEditingController(text: '127.0.0.1');
  final TextEditingController txPortController =
      TextEditingController(text: '9000');
  final TextEditingController rxPortController =
      TextEditingController(text: '9010');

  bool discovering = false;
  bool connecting = false;
  List<String> discoveredAddresses = [];

  void startDiscovery() {
    setState(() {
      discovering = true;
      discoveredAddresses = [];
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        discovering = false;
        discoveredAddresses = [
          '192.168.10.10',
          'device.local',
          '192.168.1.5',
        ];
      });
    });
  }

  Future<void> _connect() async {
    final host = addressController.text;
    final txPort = int.tryParse(txPortController.text);
    final rxPort = int.tryParse(rxPortController.text);

    if (txPort == null) return;
    if (rxPort == null) return;

    setState(() => connecting = true);

    try {
      await network.connect(host, txPort, rxPort: rxPort);
      network.sendOscMessage('/ack', []);
    } on TimeoutException {
      await _showError('Connection timeout exceeded');
    } catch (e) {
      await _showError(e.toString());
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  void _disconnect() {
    network.disconnect();
    setState(() {});
  }

  Future<void> _showError(String msg) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = network.isConnected;

    return LabeledCard(
      title: 'Network Connection',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: addressController,
            decoration: const InputDecoration(labelText: 'Network Address'),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: txPortController,
                  decoration: const InputDecoration(labelText: 'Transmit Port'),
                  style: const TextStyle(fontFamily: 'monospace'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: rxPortController,
                  decoration: const InputDecoration(labelText: 'Receive Port'),
                  style: const TextStyle(fontFamily: 'monospace'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                icon: connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(isConnected ? Icons.link_off : Icons.network_ping),
                label: Text(isConnected ? 'Disconnect' : 'Connect'),
                onPressed:
                    connecting ? null : (isConnected ? _disconnect : _connect),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: discovering
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: const Text('Zeroconf'),
                onPressed: discovering ? null : startDiscovery,
              ),
            ],
          ),
          if (discoveredAddresses.isNotEmpty) ...[
            const SizedBox(height: 16),
            DropdownButton<String>(
              isExpanded: true,
              value: discoveredAddresses.first,
              items: discoveredAddresses
                  .map((address) => DropdownMenuItem(
                        value: address,
                        child: Text(address),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    addressController.text = value;
                  });
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

