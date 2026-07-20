import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_button.dart';
import 'grid.dart';
import 'labeled_card.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'osc_rotary_knob.dart';
import 'osc_widget_binding.dart';

/// Front Panel card for the Setup page: LED brightness (rotary knob bound to
/// /device/led_brightness) and a button-lock toggle (/device/buttons_locked)
/// that stops the physical front-panel buttons from acting on an accidental bump.
class FrontPanelSection extends StatefulWidget {
  const FrontPanelSection({super.key});

  @override
  State<FrontPanelSection> createState() => _FrontPanelSectionState();
}

class _FrontPanelSectionState extends State<FrontPanelSection> {
  static const _oscLocked = '/device/buttons_locked';
  static const _oscLedBrightness = '/device/led_brightness';

  bool _locked = false;
  Network? _net;
  bool _wasConnected = false;

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress(_oscLocked);
    reg.registerListener(_oscLocked, _onLocked);
    final args = reg.allParams[_oscLocked]?.currentValue;
    if (args != null && args.isNotEmpty) _onLocked(List<Object?>.from(args));
    WidgetsBinding.instance.addPostFrameCallback((_) => _query());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final net = context.read<Network>();
    if (!identical(_net, net)) {
      _net?.removeListener(_onNet);
      _net = net;
      _wasConnected = net.isConnected;
      _net!.addListener(_onNet);
    }
  }

  // The rotary knob doesn't self-hydrate from the registry, so explicitly pull
  // led_brightness (and the lock) on connect — otherwise a page opened after
  // /sync would show stale defaults until the next sync.
  void _onNet() {
    final connected = _net?.isConnected ?? false;
    if (connected && !_wasConnected) _query();
    _wasConnected = connected;
  }

  void _query() {
    final net = context.read<Network>();
    if (!net.isConnected) return;
    net.sendOscMessage(_oscLedBrightness, const []);
    net.sendOscMessage(_oscLocked, const []);
  }

  @override
  void dispose() {
    _net?.removeListener(_onNet);
    OscRegistry().unregisterListener(_oscLocked, _onLocked);
    super.dispose();
  }

  void _onLocked(List<Object?> args) {
    if (!mounted || args.isEmpty) return;
    final v = args.first;
    bool? locked;
    if (v is bool) {
      locked = v;
    } else if (v is int) {
      locked = v != 0;
    } else if (v is String) {
      locked = v == 'T' || v == 'true' || v == '1';
    }
    if (locked == null) return;
    setState(() => _locked = locked!);
  }

  void _setLock(bool next) {
    if (next == _locked) return;
    setState(() => _locked = next);

    final net = context.read<Network>();
    final sent = net.sendOscMessage(_oscLocked, <Object>[next]);
    if (sent) {
      final reg = OscRegistry();
      reg.registerAddress(_oscLocked);
      reg.dispatchLocal(_oscLocked, <Object?>[next]);
    }
    // Network logs the send centrally.
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context, defaultWidth: 1000);

    final labelStyle = t.textLabel.copyWith(color: Colors.white);

    // The label takes the leftover width rather than a fixed column: this card
    // is now a quarter of the page wide, and a fixed label column plus the knob
    // overflowed it.
    Widget row(String label, Widget control) => Row(
          children: [
            Expanded(child: Text(label, style: labelStyle)),
            control,
          ],
        );

    return LabeledCard(
      title: 'Front Panel',
      fillChild: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.cardBodyInset, t.xs, t.md, t.md),
        child: Column(
          // Top-aligned, NOT centred. This card and Firmware Update sit side by
          // side and are stretched to a shared height, but their contents are
          // different heights — centring each one put their first rows on
          // different lines.
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(
              'LED Brightness',
              const OscPathSegment(
                segment: 'device',
                child: OscPathSegment(
                  segment: 'led_brightness',
                  child: OscRotaryKnob(
                    minValue: 0,
                    maxValue: 100,
                    initialValue: 50,
                    defaultValue: 50,
                    format: '%.0f',
                    label: '',
                    size: 48,
                  ),
                ),
              ),
            ),
            SizedBox(height: t.md),
            // A plain labelled AppButton, like every other action on this page
            // (Save / Load / Firmware Update) — no separate row label and no
            // checkbox. It carries its own label, and `selected` sinks the key
            // in when the panel is locked. OSC is sent manually via _setLock.
            AppButton(
              label: 'Lock Buttons',
              icon: _locked ? Icons.lock : Icons.lock_open,
              selected: _locked,
              onPressed: () => _setLock(!_locked),
            ),
          ],
        ),
      ),
    );
  }
}
