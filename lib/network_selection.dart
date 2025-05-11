// lib/network_connection_section.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network.dart';
import 'labeled_card.dart';
import 'nsd_client.dart';

class NetworkConnectionSection extends StatefulWidget {
  const NetworkConnectionSection({Key? key}) : super(key: key);

  @override
  State<NetworkConnectionSection> createState() =>
      _NetworkConnectionSectionState();
}

class _NetworkConnectionSectionState
    extends State<NetworkConnectionSection> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _connecting = false;
  bool _discovering = false;

  static const _prefKey = 'recent_endpoints';
  static const _maxRecents = 5;

  List<String> _recents = [];
  List<String> _discovered = [];

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefKey) ?? <String>[];
    setState(() {
      _recents = list;
      _controller.text =
          _recents.isNotEmpty ? _recents.first : '127.0.0.1';
    });
  }

  Future<void> _saveRecent(String host, int port) async {
    final entry = port == 9000 ? host : '$host:$port';
    _recents.remove(entry);
    _recents.insert(0, entry);
    if (_recents.length > _maxRecents) _recents.removeLast();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, _recents);
  }

  Future<void> _connect() async {
    final input = _controller.text.trim();
    final parts = input.split(':');
    if (parts.isEmpty || parts[0].isEmpty) {
      await _showError('Enter a valid host');
      return;
    }
    final host = parts[0];
    int port = 9000;
    if (parts.length == 2) {
      port = int.tryParse(parts[1]) ?? 9000;
    }

    setState(() => _connecting = true);
    try {
      final net = context.read<Network>(); 
      await net.connect(host, port);
      await _saveRecent(host, port);
      net.sendOscMessage('/ack', []);
    } on TimeoutException {
      await _showError('Connection timed out');
    } catch (e) {
      await _showError(e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _disconnect() {
    final net = context.read<Network>(); 
    net.disconnect();
  }

  Future<void> _findServices() async {
    setState(() => _discovering = true);

    List<NetworkAddress> services = [];
    try {
      services = await NSDClient()
          .discover()
          .timeout(
            NSDClient().scanDuration + const Duration(seconds: 1),
            onTimeout: () => <NetworkAddress>[],
          );
    } catch (e) {
      if (mounted) setState(() => _discovering = false);
      await _showError('Discovery failed: $e');
      return;
    }

    if (!mounted) return;
    setState(() => _discovering = false);

    if (services.isEmpty) {
      await _showError('No devices found on your local network');
      return;
    }

    final addresses = services.map((s) => '${s.host}:${s.port}').toList();
    setState(() {
      _controller.text = addresses.first;
      _discovered = addresses.length > 1 ? addresses.sublist(1) : [];
    });
    if (_discovered.isNotEmpty) _focusNode.requestFocus();
  }

  Future<void> _showError(String message) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
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
    final isConnected = context.watch<Network>().isConnected;

    return LabeledCard(
      title: 'Network Connection',
      networkIndependent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TypeAheadFormField<String>(
            textFieldConfiguration: TextFieldConfiguration(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                labelText: 'Network address',
                hintText:
                    'e.g. 192.168.10.27, or server.superchromat.com:9010',
                border: const OutlineInputBorder(),
                suffixIcon: _discovering
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.search),
                        onPressed:
                            _discovering ? null : _findServices,
                      ),
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            suggestionsCallback: (pattern) async {
              final lower = pattern.toLowerCase();
              final fromDiscovered = _discovered.where(
                  (e) => e.toLowerCase().contains(lower));
              final fromRecents = _recents.where(
                  (e) => e.toLowerCase().contains(lower));
              return [...fromDiscovered, ...fromRecents];
            },
            itemBuilder: (context, String suggestion) {
              return ListTile(title: Text(suggestion));
            },
            onSuggestionSelected: (String suggestion) {
              _controller.text = suggestion;
            },
            hideOnEmpty: false,
            minCharsForSuggestions: 0,
            noItemsFoundBuilder: (_) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: _connecting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(isConnected
                    ? Icons.link_off
                    : Icons.network_ping),
            label: Text(
                isConnected ? 'Disconnect' : 'Connect'),
            onPressed: _connecting
                ? null
                : (isConnected
                    ? _disconnect
                    : _connect),
          ),
        ],
      ),
    );
  }
}
