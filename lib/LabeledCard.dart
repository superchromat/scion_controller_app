// LabeledCard.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'network.dart';

class LabeledCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool networkIndependent;

  const LabeledCard({
    Key? key,
    required this.title,
    required this.child,
    this.networkIndependent = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // rebuilds whenever network.isConnected changes
    final connected = context.watch<Network>().isConnected;
    final disabled = !networkIndependent && !connected;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: IgnorePointer(
        ignoring: disabled,
        child: Opacity(
          opacity: disabled ? 0.2 : 1.0,
          child: Card(
            color: Colors.grey[800],
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
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
