import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'osc_widget_binding.dart'; // for OscRegistry & OscPathSegment

class LabeledCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool networkIndependent;

  const LabeledCard({
    super.key,
    required this.title,
    required this.child,
    this.networkIndependent = false,
  });

  @override
  Widget build(BuildContext context) {
    // rebuild on network status
    final connected = context.watch<Network>().isConnected;
    final disabled = !networkIndependent && !connected;

    // compute OSC namespace prefix for this card
    final prefix = '/${OscPathSegment.resolvePath(context).join('/')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: IgnorePointer(
        ignoring: disabled,
        child: Opacity(
          opacity: disabled ? 0.2 : 1.0,
          child: Card(
            color: Colors.grey[800],
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // title row with reset button
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (!networkIndependent)
                        IconButton(
                          icon: const Icon(Symbols.source_notes),
                          tooltip: 'Reset from file',
                          onPressed: () {
                            OscRegistry().resetToFile(prefix);
                          },
                        ),
                      if (!networkIndependent)
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          color: Colors.yellow,
                          tooltip: 'Reset to defaults',
                          onPressed: () {
                            // reset all OSC params under this card
                            OscRegistry().resetToDefaults(prefix);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
