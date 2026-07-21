// lib/network_connection_section.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network.dart';
import 'app_button.dart';
import 'discovery.dart';

class NetworkConnectionSection extends StatefulWidget {
  const NetworkConnectionSection({super.key});

  @override
  State<NetworkConnectionSection> createState() =>
      _NetworkConnectionSectionState();
}

class _NetworkConnectionSectionState extends State<NetworkConnectionSection> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  static const _prefKey = 'recent_endpoints';
  static const _maxRecents = 5;
  static const _defaultPort = 9000;

  List<String> _recents = [];
  ScionDiscovery? _discovery;

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disc = context.read<ScionDiscovery>();
    if (!identical(disc, _discovery)) {
      _discovery?.removeListener(_syncFromConnection);
      _discovery = disc;
      _discovery!.addListener(_syncFromConnection);
      _syncFromConnection();
    }
  }

  @override
  void dispose() {
    _discovery?.removeListener(_syncFromConnection);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Keep the field showing the live connection's friendly name (e.g.
  // "jorge.local") instead of a stale recent. Skipped while the user is editing
  // so it never clobbers what they're typing.
  void _syncFromConnection() {
    if (!mounted) return;
    final label = _discovery?.connectedLabel;
    if (label != null && !_focusNode.hasFocus && _controller.text != label) {
      _controller.text = label;
    }
  }

  Future<void> _loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefKey) ?? <String>[];
    if (!mounted) return;
    setState(() {
      _recents = list;
      // Only seed the field if it's empty — never clobber a live connection
      // label that _syncFromConnection may have already written.
      if (_controller.text.isEmpty && _recents.isNotEmpty) {
        _controller.text = _recents.first;
      }
    });
    // Auto-connect (continuous mDNS + last-endpoint fast path) is handled
    // centrally by ScionDiscovery; this field is only for manual entry.
  }

  Future<void> _saveRecent(String host, int port) async {
    final entry = _formatEndpoint(host, port);
    _recents.remove(entry);
    _recents.insert(0, entry);
    if (_recents.length > _maxRecents) _recents.removeLast();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, _recents);
  }

  String _formatEndpoint(String host, int port) {
    if (port == _defaultPort) return host;
    return host.contains(':') ? '[$host]:$port' : '$host:$port';
  }

  ({String host, int port})? _parseEndpoint(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    String host;
    int port = _defaultPort;

    if (text.startsWith('[')) {
      final end = text.indexOf(']');
      if (end <= 1) return null;
      host = text.substring(1, end).trim();
      final tail = text.substring(end + 1).trim();
      if (tail.isNotEmpty) {
        if (!tail.startsWith(':')) return null;
        final p = int.tryParse(tail.substring(1));
        if (p == null || p <= 0 || p > 65535) return null;
        port = p;
      }
    } else {
      final colonCount = ':'.allMatches(text).length;
      if (colonCount == 0) {
        host = text;
      } else if (colonCount == 1) {
        final idx = text.lastIndexOf(':');
        host = text.substring(0, idx).trim();
        final p = int.tryParse(text.substring(idx + 1).trim());
        if (p == null || p <= 0 || p > 65535) return null;
        port = p;
      } else {
        // Bare IPv6 literal without explicit port.
        host = text;
      }
    }

    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.isEmpty) return null;

    return (host: host, port: port);
  }

  Future<void> _connectTo(String input) async {
    final endpoint = _parseEndpoint(input);
    if (endpoint == null) {
      await _showError('Enter a valid host');
      return;
    }
    final host = endpoint.host;
    final port = endpoint.port;

    final net = context.read<Network>();
    try {
      if (net.isConnected) net.disconnect();
      await net.connect(host, port);
      await _saveRecent(host, port);
    } on TimeoutException {
      await _showError('Connection timed out');
    } catch (e) {
      await _showError(e.toString());
    }
  }

  Future<void> _showError(String message) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          AppButton(
            label: 'OK',
            dense: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final network = context.watch<Network>();
    final discovered = context
        .watch<ScionDiscovery>()
        .devices
        .map((d) => _formatEndpoint(d.host, d.port))
        .toList();

    return TypeAheadFormField<String>(
      textFieldConfiguration: TextFieldConfiguration(
        controller: _controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: 'Network address',
          hintText: 'e.g. 192.168.10.27, or server.superchromat.com:9010',
          border: const OutlineInputBorder(),
          suffixIcon: network.isConnecting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Rescan for SCION',
                  onPressed: () => context.read<ScionDiscovery>().rescan(),
                ),
        ),
        style: const TextStyle(fontFamily: 'DINPro', fontSize: 13),
        onSubmitted:
            network.isConnecting ? null : (val) => _connectTo(val.trim()),
      ),
      suggestionsCallback: (pattern) async {
        final suggestions = List<String>.from(discovered);
        suggestions.addAll(
          _recents.where(
            (e) => e.toLowerCase().contains(pattern.toLowerCase()),
          ),
        );
        return suggestions;
      },
      itemBuilder: (context, String suggestion) => ListTile(
        dense: true,
        title: Text(suggestion,
            style: const TextStyle(fontFamily: 'DINPro', fontSize: 13)),
      ),
      onSuggestionSelected: (String suggestion) {
        _controller.text = suggestion;
        _connectTo(suggestion);
      },
      hideOnEmpty: false,
      minCharsForSuggestions: 0,
      noItemsFoundBuilder: (_) => const SizedBox.shrink(),
    );
  }
}
