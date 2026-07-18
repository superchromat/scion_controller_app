import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'discovery.dart';
import 'nsd_client.dart' show NetworkAddress;
import 'sc_spinner.dart';

const Color kOnboardAccent = Color(0xFFF0B830);

/// Platform whose direct-connection instructions the help shows. Defaults to the
/// host OS; overridable for tests / previews.
enum OnboardingOS { mac, windows, other }

/// Overlay shown over the page (not the sidebar) while disconnected. It reflects
/// the [ScionDiscovery] state: a "searching" spinner, a device picker when more
/// than one SCION is found, or the connection help once the search times out.
class DisconnectedScrim extends StatelessWidget {
  const DisconnectedScrim({super.key});

  @override
  Widget build(BuildContext context) {
    final discovery = context.watch<ScionDiscovery>();
    final Widget child;
    if (discovery.needsPicker) {
      child = _DevicePicker(devices: discovery.devices);
    } else if (discovery.phase == DiscoveryPhase.timedOut) {
      child = const OnboardingGuide();
    } else {
      child = const _SearchingView();
    }
    return Container(
      color: const Color.fromARGB(255, 22, 22, 26).withValues(alpha: 0.62),
      child: child,
    );
  }
}

class _SearchingView extends StatelessWidget {
  const _SearchingView();

  @override
  Widget build(BuildContext context) {
    final textColor = Colors.white.withValues(alpha: 0.82);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ScSpinner(width: 84),
          const SizedBox(height: 20),
          Text('Searching for SCION…',
              style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2)),
          const SizedBox(height: 18),
          const _DemoModeButton(),
        ],
      ),
    );
  }
}

/// Small button that drops into demo mode (no device required).
class _DemoModeButton extends StatelessWidget {
  const _DemoModeButton();

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => context.read<ScionDiscovery>().enterDemoMode(),
      icon: Icon(Icons.play_circle_outline,
          size: 16, color: Colors.white.withValues(alpha: 0.6)),
      label: Text('Explore in demo mode',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
    );
  }
}

class _DevicePicker extends StatelessWidget {
  final List<NetworkAddress> devices;
  const _DevicePicker({required this.devices});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.lan_outlined, color: kOnboardAccent, size: 24),
                  SizedBox(width: 10),
                  Text('Choose your SCION',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              Text('More than one SCION is on the network.',
                  style:
                      TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
              const SizedBox(height: 14),
              for (final d in devices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(9),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => context
                          .read<ScionDiscovery>()
                          .connectTo(d.host, d.port),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.developer_board,
                                color: Colors.white70, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('${d.host}:${d.port}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontFamily: 'monospace')),
                            ),
                            const Icon(Icons.chevron_right,
                                color: Colors.white38, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Connection help, shown when discovery times out with nothing found.
class OnboardingGuide extends StatelessWidget {
  final OnboardingOS? osOverride;
  const OnboardingGuide({super.key, this.osOverride});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.lan_outlined, color: kOnboardAccent, size: 26),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Connect your SCION',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "Couldn't find a SCION on your network. It'll connect on its "
                  "own the moment it's reachable — here's how to get it there.",
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 18),
                _step(1, Icons.settings_ethernet, 'Connect over Ethernet',
                    'Plug the SCION into your computer or router with an Ethernet cable.'),
                _step(2, Icons.hub_outlined, 'Same network',
                    'The SCION and this computer must be on the same network to find each other.'),
                _step(3, Icons.bolt_outlined, 'It connects automatically',
                    'No need to do anything else — the app keeps looking and links up as soon as the SCION appears. You can also type its IP into “Network address” (top-left).'),
                const SizedBox(height: 12),
                _directBox(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(Colors.white38)),
                    ),
                    const SizedBox(width: 8),
                    Text('Still searching…',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12)),
                    const Spacer(),
                    const _DemoModeButton(),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () =>
                          context.read<ScionDiscovery>().rescan(),
                      child: const Text('Rescan',
                          style: TextStyle(color: kOnboardAccent)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(int n, IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: kOnboardAccent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$n',
                  style: const TextStyle(
                      color: kOnboardAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(body,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 12.5,
                        height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _directBox() {
    final OnboardingOS os = osOverride ??
        (Platform.isMacOS
            ? OnboardingOS.mac
            : Platform.isWindows
                ? OnboardingOS.windows
                : OnboardingOS.other);
    final String label;
    final String body;
    switch (os) {
      case OnboardingOS.mac:
        label = 'macOS — Internet Sharing';
        body = 'No router? Open System Settings → General → Sharing → Internet '
            'Sharing. Set “Share your connection from: Wi-Fi” and “To computers '
            'using: Ethernet” (the adapter the SCION is plugged into), then turn '
            'Internet Sharing on. Your Mac gives the SCION an address on a '
            'shared network.';
        break;
      case OnboardingOS.windows:
        label = 'Windows — Internet Connection Sharing';
        body = 'No router? Open Network Connections (run “ncpa.cpl”). Right-click '
            'your internet adapter (e.g. Wi-Fi) → Properties → Sharing, enable '
            '“Allow other network users to connect…”, and choose the Ethernet '
            'adapter the SCION is on.';
        break;
      case OnboardingOS.other:
        label = 'Direct connection';
        body = 'No router? Share your computer’s internet connection to the '
            'Ethernet port the SCION is plugged into so it gets an address on a '
            'shared network.';
        break;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(os == OnboardingOS.windows ? Icons.window_outlined : Icons.laptop_mac,
                  color: Colors.white70, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(body,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.66),
                  fontSize: 12,
                  height: 1.4)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}
