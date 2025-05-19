// osc_registry_viewer.dart

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'osc_widget_binding.dart';

class OscRegistryViewer extends StatefulWidget {
  const OscRegistryViewer({Key? key}) : super(key: key);

  @override
  _OscRegistryViewerState createState() => _OscRegistryViewerState();
}

class _OscRegistryViewerState extends State<OscRegistryViewer> {
  final OscRegistry _registry = OscRegistry();

  @override
  void initState() {
    super.initState();
    _registry.addListener(_onRegistryChanged);
  }

  void _onRegistryChanged() {
    if (!mounted) return;
    // Schedule the rebuild after the current frame so we don't call setState
    // in the middle of a build.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistryChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _registry.allParams.entries.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('OSC Registry')),
      body: ListView.builder(
        itemCount: entries.length,
        itemBuilder: (ctx, i) {
          final address = entries[i].key;
          final p = entries[i].value;
          return ExpansionTile(
            title: Text(address),
            children: [
              ListTile(
                dense: true,
                title: const Text('Default Value'),
                subtitle: Text(p.defaultValue.toString()),
              ),
              ListTile(
                dense: true,
                title: const Text('Current Value'),
                subtitle: Text(p.currentValue.toString()),
              ),
              ListTile(
                dense: true,
                title: const Text('Listener Count'),
                subtitle: Text(p.listeners.length.toString()),
              ),
            ],
          );
        },
      ),
    );
  }
}
