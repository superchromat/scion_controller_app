import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firmware_update.dart';
import 'grid.dart';
import 'labeled_card.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'panel.dart';

/// Device card for the Setup page.
///
/// Read-only identity reported by the firmware (model, firmware version,
/// hardware revision, serial, uptime) in an inset panel, followed by the
/// firmware-update controls ([FirmwareUpdateSection]) in the same card.
class DeviceSettingsSection extends StatefulWidget {
  const DeviceSettingsSection({super.key});

  @override
  State<DeviceSettingsSection> createState() => _DeviceSettingsSectionState();
}

class _DeviceSettingsSectionState extends State<DeviceSettingsSection> {
  static const _oscModel = '/device/model';
  static const _oscFwVersion = '/device/fw_version';
  static const _oscHwRevision = '/device/hw_revision';
  static const _oscSerial = '/device/serial';
  static const _oscUptime = '/device/uptime';

  static const _readAddresses = [
    _oscModel,
    _oscFwVersion,
    _oscHwRevision,
    _oscSerial,
    _oscUptime,
  ];

  String? _model;
  String? _fwVersion;
  String? _hwRevision;
  String? _serial;
  int? _uptimeSec;

  Timer? _uptimePoll;

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    for (final addr in _readAddresses) {
      reg.registerAddress(addr);
    }
    reg.registerListener(_oscModel, _onModel);
    reg.registerListener(_oscFwVersion, _onFwVersion);
    reg.registerListener(_oscHwRevision, _onHwRevision);
    reg.registerListener(_oscSerial, _onSerial);
    reg.registerListener(_oscUptime, _onUptime);
    _hydrateFromRegistry(reg);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queryStatic();
      _pollUptime();
    });
    _uptimePoll = Timer.periodic(const Duration(seconds: 1), (_) => _pollUptime());
  }

  @override
  void dispose() {
    _uptimePoll?.cancel();
    final reg = OscRegistry();
    reg.unregisterListener(_oscModel, _onModel);
    reg.unregisterListener(_oscFwVersion, _onFwVersion);
    reg.unregisterListener(_oscHwRevision, _onHwRevision);
    reg.unregisterListener(_oscSerial, _onSerial);
    reg.unregisterListener(_oscUptime, _onUptime);
    super.dispose();
  }

  void _hydrateFromRegistry(OscRegistry reg) {
    void push(String addr, void Function(List<Object?>) cb) {
      final args = reg.allParams[addr]?.currentValue;
      if (args == null || args.isEmpty) return;
      cb(List<Object?>.from(args));
    }

    push(_oscModel, _onModel);
    push(_oscFwVersion, _onFwVersion);
    push(_oscHwRevision, _onHwRevision);
    push(_oscSerial, _onSerial);
    push(_oscUptime, _onUptime);
  }

  void _queryStatic() {
    final net = context.read<Network>();
    if (!net.isConnected) return;
    // Pull identity in case /sync already happened before this page mounted.
    for (final addr in const [
      _oscModel,
      _oscFwVersion,
      _oscHwRevision,
      _oscSerial,
    ]) {
      net.sendOscMessage(addr, const []);
    }
  }

  void _pollUptime() {
    final net = context.read<Network>();
    if (!net.isConnected) return;
    net.sendOscMessage(_oscUptime, const []);
  }

  String? _asString(List<Object?> args) {
    if (args.isEmpty) return null;
    return args.first?.toString().trim();
  }

  void _onModel(List<Object?> args) {
    if (!mounted) return;
    setState(() => _model = _asString(args));
  }

  void _onFwVersion(List<Object?> args) {
    if (!mounted) return;
    setState(() => _fwVersion = _asString(args));
  }

  void _onHwRevision(List<Object?> args) {
    if (!mounted) return;
    setState(() => _hwRevision = _asString(args));
  }

  void _onSerial(List<Object?> args) {
    if (!mounted) return;
    setState(() => _serial = _asString(args));
  }

  void _onUptime(List<Object?> args) {
    if (!mounted || args.isEmpty) return;
    final v = args.first;
    int? secs;
    if (v is int) {
      secs = v;
    } else if (v is num) {
      secs = v.toInt();
    } else if (v is String) {
      secs = int.tryParse(v);
    }
    if (secs == null) return;
    setState(() => _uptimeSec = secs);
  }

  static String _formatUptime(int totalSeconds) {
    if (totalSeconds < 0) return '—';
    final d = totalSeconds ~/ 86400;
    final h = (totalSeconds % 86400) ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final parts = <String>[];
    if (d > 0) parts.add('${d}d');
    if (h > 0 || d > 0) parts.add('${h}h');
    if (m > 0 || h > 0 || d > 0) parts.add('${m}m');
    parts.add('${s}s');
    return parts.join(' ');
  }

  TextStyle _valueStyle(GridTokens t) => TextStyle(
        fontFamily: 'Courier',
        fontFamilyFallback: const ['Courier New', 'monospace'],
        fontSize: (t.u * 1.15).clamp(13.0, 17.0),
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: const Color(0xFFE9E9EC),
      );

  Widget _infoRow(GridTokens t, double labelW, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.xs * 0.55),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: labelW,
            child: Text(label.toUpperCase(), style: t.textCaption),
          ),
          Expanded(
            child: Text(
              value,
              style: _valueStyle(t),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context, defaultWidth: 1000);
    final labelW = (t.u * 7.5).clamp(86.0, 120.0);

    String orDash(String? v) => (v == null || v.isEmpty) ? '—' : v;

    final identity = Panel(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.xs, vertical: t.xs * 0.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _infoRow(t, labelW, 'Model', orDash(_model)),
            _infoRow(t, labelW, 'Firmware', orDash(_fwVersion)),
            _infoRow(t, labelW, 'Hardware', orDash(_hwRevision)),
            _infoRow(t, labelW, 'Serial', orDash(_serial)),
            _infoRow(t, labelW, 'Uptime',
                _uptimeSec == null ? '—' : _formatUptime(_uptimeSec!)),
          ],
        ),
      ),
    );

    return LabeledCard(
      title: 'Device',
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.md, t.xs, t.md, t.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            SizedBox(height: t.md),
            const FirmwareUpdateSection(),
          ],
        ),
      ),
    );
  }
}
