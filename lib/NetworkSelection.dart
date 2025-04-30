import 'package:flutter/material.dart';

class NetworkConnectionSection extends StatefulWidget {
  const NetworkConnectionSection({super.key});

  @override
  State<NetworkConnectionSection> createState() =>
      _NetworkConnectionSectionState();
}

class _NetworkConnectionSectionState extends State<NetworkConnectionSection> {
  final TextEditingController addressController = TextEditingController();
  final TextEditingController txPortController =
      TextEditingController(text: '8000');
  final TextEditingController rxPortController =
      TextEditingController(text: '9000');

  bool discovering = false;
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

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Network Connection',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
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
                  icon: const Icon(Icons.network_ping),
                  label: const Text('Connect'),
                  onPressed: () {},
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
      ),
    );
  }
}
