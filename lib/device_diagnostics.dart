import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'grid.dart';
import 'labeled_card.dart';
import 'app_button.dart';
import 'network.dart';
import 'osc_registry.dart';

/// Diagnostics panel for the Setup page.
///
/// Requests `/device/shell_info` (the device runs `diag` + `scion_info` through
/// a dummy shell backend and streams the combined, ANSI-coloured output back in
/// chunks). The text is reassembled, rendered in Courier with ANSI colours
/// preserved, and can be copied to the clipboard (colours stripped) in one tap.
class DeviceDiagnosticsSection extends StatefulWidget {
  /// When false the panel stops polling (the Setup tab isn't visible) so the
  /// device isn't re-running `scion_info` in the background all session.
  final bool isActive;
  const DeviceDiagnosticsSection({super.key, this.isActive = true});

  @override
  State<DeviceDiagnosticsSection> createState() =>
      _DeviceDiagnosticsSectionState();
}

class _DeviceDiagnosticsSectionState extends State<DeviceDiagnosticsSection> {
  static const _oscShellInfo = '/device/shell_info';
  static const _refreshInterval = Duration(seconds: 10);

  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();

  // Chunk reassembly state, keyed on the capture generation so stragglers from
  // an earlier capture are discarded instead of corrupting the current one.
  List<String?>? _chunks;
  int _expectedTotal = 0;
  int _gen = -1;

  String _rawText = '';
  Timer? _refresh;
  Network? _net;
  bool _wasConnected = false;

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress(_oscShellInfo);
    reg.registerListener(_oscShellInfo, _onShellInfo);

    WidgetsBinding.instance.addPostFrameCallback((_) => _request());
    _refresh = Timer.periodic(_refreshInterval, (_) => _request());
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

  // Pull a fresh capture the moment the link comes up — shell_info isn't part
  // of /sync, so without this the panel would sit on "Waiting…" until the next
  // periodic tick.
  void _onNet() {
    final connected = _net?.isConnected ?? false;
    if (connected && !_wasConnected) {
      // A new link may be a rebooted device, whose shell_info gen counter has
      // reset to 0. Forget the old capture so the fresh (lower-gen) one isn't
      // mistaken for a straggler and discarded.
      _gen = -1;
      _chunks = null;
      _expectedTotal = 0;
      _request();
    }
    _wasConnected = connected;
  }

  @override
  void didUpdateWidget(DeviceDiagnosticsSection old) {
    super.didUpdateWidget(old);
    // Refresh immediately when the Setup tab becomes visible again.
    if (widget.isActive && !old.isActive) _request();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _net?.removeListener(_onNet);
    OscRegistry().unregisterListener(_oscShellInfo, _onShellInfo);
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  void _request() {
    if (!widget.isActive) return;
    final net = context.read<Network>();
    if (!net.isConnected) return;
    net.sendOscMessage(_oscShellInfo, const []);
  }

  // The chunk arrives as an OSC blob (List<int>) — decode to text and drop any
  // stray NUL bytes the shell capture may have left in. Tolerates a plain
  // String too, in case the device sends one.
  String _decodeChunk(Object? raw) {
    if (raw is List<int>) {
      return String.fromCharCodes(raw.where((b) => b != 0));
    }
    final s = (raw is String) ? raw : (raw?.toString() ?? '');
    return String.fromCharCodes(s.codeUnits.where((c) => c != 0));
  }

  void _onShellInfo(List<Object?> args) {
    if (!mounted || args.length < 4) return;
    final gen = (args[0] is num) ? (args[0] as num).toInt() : -1;
    final seq = (args[1] is num) ? (args[1] as num).toInt() : -1;
    final total = (args[2] is num) ? (args[2] as num).toInt() : -1;
    final chunk = _decodeChunk(args[3]);
    if (total <= 0 || seq < 0 || seq >= total) return;

    // Ignore late stragglers from the immediately-preceding capture. But a large
    // backwards jump means the device rebooted (its gen counter resets to 0 on
    // boot), so adopt that capture instead of discarding it forever.
    if (gen < _gen && (_gen - gen) < 16) return;
    if (gen != _gen || _chunks == null || _expectedTotal != total) {
      _gen = gen;
      _chunks = List<String?>.filled(total, null);
      _expectedTotal = total;
    }
    _chunks![seq] = chunk;

    if (_chunks!.every((c) => c != null)) {
      final full = _chunks!.map((c) => c!).join();
      setState(() => _rawText = full);
    }
  }

  Future<void> _copy() async {
    final plain = _stripAnsi(_rawText);
    await Clipboard.setData(ClipboardData(text: plain));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostics copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context, defaultWidth: 1000);
    final fontSize = (t.u * 0.92).clamp(11.0, 14.0);
    final baseStyle = TextStyle(
      fontFamily: 'Courier',
      fontFamilyFallback: const ['Courier New', 'monospace'],
      fontSize: fontSize,
      height: 1.3,
      color: const Color(0xFFCBCDD3),
    );

    final spans = _parseAnsi(_rawText, baseStyle);

    final terminal = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 80, maxHeight: 460),
      child: NeumorphicInset(
        baseColor: const Color(0xFF202023),
        borderRadius: 6.0,
        padding: EdgeInsets.all(t.sm),
        child: _rawText.isEmpty
            ? Center(
                child: Text(
                  'Waiting for device…',
                  style: baseStyle.copyWith(color: const Color(0xFF6E6E76)),
                ),
              )
            : Scrollbar(
                controller: _vScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _vScroll,
                  primary: false,
                  child: Scrollbar(
                    controller: _hScroll,
                    thumbVisibility: true,
                    notificationPredicate: (n) => n.depth == 1,
                    child: SingleChildScrollView(
                      controller: _hScroll,
                      primary: false,
                      scrollDirection: Axis.horizontal,
                      child: SelectableText.rich(
                        TextSpan(style: baseStyle, children: spans),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );

    return LabeledCard(
      title: 'Diagnostics',
      child: GridRow(
        columns: 12,
        gutter: t.md,
        cells: [
          (
            span: 12,
            // Copy floats in the terminal's top-right corner so it stays put
            // as the log scrolls — always reachable, never pushed off-screen.
            child: Stack(
              children: [
                terminal,
                Positioned(
                  top: t.sm * 1.5,
                  right: t.sm * 1.5,
                  child: AppButton(
                    icon: Icons.content_copy,
                    label: 'Copy',
                    dense: true,
                    tooltip: 'Copy diagnostics to clipboard',
                    onPressed: _rawText.isEmpty ? null : _copy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ANSI SGR parsing
// ─────────────────────────────────────────────────────────────────────────────

final RegExp _ansiSgr = RegExp(r'\x1B\[([0-9;]*)m');
final RegExp _ansiAny = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

/// Standard 8 ANSI colours, tuned for a dark background (One Dark-ish palette).
const List<Color> _ansiNormal = [
  Color(0xFF5C6370), // 30 black/grey
  Color(0xFFE06C75), // 31 red
  Color(0xFF98C379), // 32 green
  Color(0xFFE5C07B), // 33 yellow
  Color(0xFF61AFEF), // 34 blue
  Color(0xFFC678DD), // 35 magenta
  Color(0xFF56B6C2), // 36 cyan
  Color(0xFFCBCDD3), // 37 white
];
const List<Color> _ansiBright = [
  Color(0xFF7F8694), // 90
  Color(0xFFFF7B86), // 91
  Color(0xFFB5E08F), // 92
  Color(0xFFF5D08C), // 93
  Color(0xFF7CC2FF), // 94
  Color(0xFFD68BF0), // 95
  Color(0xFF6FD3DF), // 96
  Color(0xFFF0F1F5), // 97
];

String _stripAnsi(String input) =>
    input.replaceAll(_ansiAny, '').replaceAll('\r', '');

List<TextSpan> _parseAnsi(String input, TextStyle base) {
  if (input.isEmpty) return const [];
  final text = input.replaceAll('\r', '');
  final spans = <TextSpan>[];
  final buf = StringBuffer();

  Color? fg;
  bool bold = false;
  bool dim = false;

  void flush() {
    if (buf.isEmpty) return;
    var color = fg ?? base.color;
    if (dim && color != null) color = color.withValues(alpha: 0.6);
    spans.add(TextSpan(
      text: buf.toString(),
      style: base.copyWith(
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    ));
    buf.clear();
  }

  int last = 0;
  for (final m in _ansiSgr.allMatches(text)) {
    buf.write(text.substring(last, m.start));
    flush();
    final params = m.group(1) ?? '';
    final codes = params.isEmpty
        ? <int>[0]
        : params.split(';').map((s) => int.tryParse(s) ?? 0).toList();
    for (final c in codes) {
      if (c == 0) {
        fg = null;
        bold = false;
        dim = false;
      } else if (c == 1) {
        bold = true;
      } else if (c == 2) {
        dim = true;
      } else if (c == 22) {
        bold = false;
        dim = false;
      } else if (c >= 30 && c <= 37) {
        fg = _ansiNormal[c - 30];
      } else if (c == 39) {
        fg = null;
      } else if (c >= 90 && c <= 97) {
        fg = _ansiBright[c - 90];
      }
    }
    last = m.end;
  }
  buf.write(text.substring(last));
  flush();
  return spans;
}
