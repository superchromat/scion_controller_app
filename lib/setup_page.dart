import 'package:SCION_Controller/system_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'grid.dart';
import 'video_format_selection.dart';
import 'sync_mode_selection.dart';
import 'firmware_update.dart';
import 'labeled_card.dart';
import 'osc_checkbox.dart';

/// System page - contains system overview, video format, and sync settings
class SystemPage extends StatefulWidget {
  const SystemPage({super.key});

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pageGutter = constraints.maxWidth * AppGrid.gutterFraction;
          return GridGutterProvider(
            gutter: pageGutter,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(pageGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GridRow(cells: [(span: 12, child: SystemOverview())]),
                  const GridGap(),
                  GridRow(cells: [
                    (span: 7, child: VideoFormatSelectionSection()),
                    (span: 5, child: SyncSettingsSection()),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Setup page - contains firmware update
class SetupPage extends StatelessWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final t = GridTokens(constraints.maxWidth);
          return GridProvider(
            tokens: t,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(t.md),
              child: GridRow(
                gutter: t.md,
                cells: const [
                  (
                    span: 6,
                    child: LabeledCard(
                      title: 'Network Setup',
                      child: _NetworkSetupSection(),
                    ),
                  ),
                  (
                    span: 6,
                    child: FirmwareUpdateSection(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NetworkSetupSection extends StatefulWidget {
  const _NetworkSetupSection();

  @override
  State<_NetworkSetupSection> createState() => _NetworkSetupSectionState();
}

class _NetworkSetupSectionState extends State<_NetworkSetupSection> {
  final _formKey = GlobalKey<FormState>();
  final _hostnameController = TextEditingController(text: 'scion.local');
  final _ipController = TextEditingController(text: '192.168.2.75');
  final _maskController = TextEditingController(text: '255.255.255.0');
  final _routerController = TextEditingController(text: '192.168.2.1');
  bool _dhcpEnabled = true;
  bool _showValidation = false;

  ButtonStyle _actionButtonStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ElevatedButton.styleFrom(
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      backgroundColor: const Color(0xFF2A2A30),
      disabledBackgroundColor: const Color(0xFF57575E),
      foregroundColor: scheme.primary,
      disabledForegroundColor: const Color(0xFFB5B5BA),
      textStyle: const TextStyle(
        fontFamily: 'DINPro',
        fontWeight: FontWeight.w600,
        fontSize: 15,
        letterSpacing: 0.05,
      ),
    );
  }

  @override
  void dispose() {
    _hostnameController.dispose();
    _ipController.dispose();
    _maskController.dispose();
    _routerController.dispose();
    super.dispose();
  }

  static final _ipv4Allowed = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));
  static final _hostnameAllowed =
      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9.-]'));

  String? _validateHostname(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Hostname is required';
    if (text.length > 253) return 'Hostname is too long';
    final labels = text.split('.');
    for (final label in labels) {
      if (label.isEmpty) return 'Enter a valid hostname';
      if (label.length > 63) return 'Hostname label is too long';
      if (label.startsWith('-') || label.endsWith('-')) {
        return 'Hostname labels cannot start/end with -';
      }
      if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(label)) {
        return 'Enter a valid hostname';
      }
    }
    return null;
  }

  String? _requiredIfStatic(String? value, String label) {
    if (_dhcpEnabled) return null;
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  String? _validateIpv4(String? value, String label) {
    final requiredErr = _requiredIfStatic(value, label);
    if (requiredErr != null) return requiredErr;
    if (_dhcpEnabled) return null;

    final text = value!.trim();
    final parts = text.split('.');
    if (parts.length != 4) return 'Enter a valid IPv4 address';
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return 'Enter a valid IPv4 address';
      if (p.length > 1 && p.startsWith('0')) return 'Avoid leading zeros';
    }
    return null;
  }

  String? _validateNetmask(String? value) {
    final requiredErr = _requiredIfStatic(value, 'Netmask');
    if (requiredErr != null) return requiredErr;
    if (_dhcpEnabled) return null;
    final ipv4Err = _validateIpv4(value, 'Netmask');
    if (ipv4Err != null) return ipv4Err;

    final parts = value!.trim().split('.').map(int.parse).toList();
    final mask = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
    if (mask == 0 || mask == 0xFFFFFFFF) return 'Use a valid subnet mask';

    // Valid masks are contiguous 1s followed by 0s.
    final inv = (~mask) & 0xFFFFFFFF;
    if (((inv + 1) & inv) != 0) return 'Netmask must be contiguous';
    return null;
  }

  void _apply() {
    setState(() => _showValidation = true);
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    final msg = _dhcpEnabled
        ? 'DHCP enabled'
        : 'Static network settings validated';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _maybeError(String? Function() compute) {
    if (!_showValidation) return null;
    return compute();
  }

  Widget _networkField({
    required GridTokens t,
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    bool enabled = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final error = _maybeError(() => validator(controller.text));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: t.xs * 0.25, bottom: t.xs * 0.3),
          child: Text(
            label,
            style: t.textLabel.copyWith(
              color: error == null
                  ? const Color(0xFFD7D7DC)
                  : const Color(0xFFE46F86),
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: (_) {
            if (_showValidation) setState(() {});
          },
          validator: validator,
          autovalidateMode: _showValidation
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          style: TextStyle(
            fontFamily: 'Courier',
            fontFamilyFallback: const ['Courier New', 'monospace'],
            fontSize: (t.u * 1.15).clamp(13.0, 17.0),
            color: enabled
                ? const Color(0xFFF0F0F3)
                : const Color(0xFF9A9AA1),
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: t.sm * 0.9, vertical: t.xs * 0.9),
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                width: 1.2,
              ),
            ),
            errorBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFE46F86), width: 1.0),
            ),
            focusedErrorBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFE46F86), width: 1.2),
            ),
            errorStyle: const TextStyle(fontSize: 0, height: 0),
          ),
        ),
        SizedBox(
          height: _showValidation ? 16 : 6,
          child: Padding(
            padding: EdgeInsets.only(left: t.xs * 0.25, top: t.xs * 0.15),
            child: Text(
              error ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textCaption.copyWith(
                color: const Color(0xFFE46F86),
                fontSize: (t.textCaption.fontSize ?? 11),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context, defaultWidth: 1000);
    final buttonStyle = _actionButtonStyle(context);

    return Form(
      key: _formKey,
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.md, t.xs, t.md, t.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                _networkField(
                  t: t,
                  label: 'Hostname',
                  controller: _hostnameController,
                  validator: _validateHostname,
                  enabled: true,
                  keyboardType: TextInputType.text,
                  inputFormatters: [_hostnameAllowed],
                ),
              ],
            ),
            SizedBox(height: t.xs * 0.5),
            Padding(
              padding: EdgeInsets.only(
                left: t.xs * 0.25,
                right: t.xs * 0.25,
                bottom: t.xs * 0.25,
              ),
              child: Row(
                children: [
                  OscCheckbox(
                    initialValue: _dhcpEnabled,
                    onChanged: (v) => setState(() => _dhcpEnabled = v),
                  ),
                  SizedBox(width: t.sm),
                  Text(
                    'DHCP',
                    style: t.textLabel.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: t.sm),
            Column(
              children: [
                _networkField(
                  t: t,
                  label: 'IP Address',
                  controller: _ipController,
                  validator: (v) => _validateIpv4(v, 'IP Address'),
                  enabled: !_dhcpEnabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_ipv4Allowed],
                ),
                _networkField(
                  t: t,
                  label: 'Netmask',
                  controller: _maskController,
                  validator: _validateNetmask,
                  enabled: !_dhcpEnabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_ipv4Allowed],
                ),
                _networkField(
                  t: t,
                  label: 'Router',
                  controller: _routerController,
                  validator: (v) => _validateIpv4(v, 'Router'),
                  enabled: !_dhcpEnabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_ipv4Allowed],
                ),
              ],
            ),
            SizedBox(height: t.xs),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                style: buttonStyle,
                onPressed: _apply,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
