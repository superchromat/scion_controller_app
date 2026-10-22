import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_alert.dart';
import 'app_button.dart';
import 'asset_store.dart';
import 'calibration_charts.dart';
import 'grid.dart';
import 'labeled_card.dart';
import 'network.dart';

/// Calibration card for the Setup page.
///
/// Walks through the on-device loop self-calibration (`/calibration/self/*`):
/// the device draws a solid test patch on Send 1's output, steps it through
/// ~390 colours, reads each back through DAC -> cable -> ADC -> Return, and
/// fits the model the Return channel's 3D LUT inverts. The run measures only
/// Scion's own analog loop, so the result holds whatever the device is later
/// connected to.
///
/// The run needs a known state in the measured path, so the card saves Send 1
/// and the Return's colour controls as temporary presets, resets those two
/// subtrees to defaults, runs, and loads the presets back. Format and sync mode
/// are left alone, except that the run switches the sync mode to LOCKED (and
/// back): the patch readback is unreliable in COMPONENT. Only
/// the two subtrees, not a whole-device preset: loading a "/" preset rebooted
/// the device every time it was tried (fw 20261022.1414), and a reboot drops
/// the unsaved result. A preset is deleted only after its load has replied, so
/// a failed restore leaves it on the device to load by hand from Files.
///
/// Status, the fit's error per channel, the loop's raw colour error on a
/// vectorscope and the corrected residuals are drawn from the run's samples
/// (`/calibration/self/data`), which live in device RAM until the next reboot.
class CalibrationSection extends StatefulWidget {
  /// False while the Setup tab is hidden: status polling stops.
  final bool isActive;
  const CalibrationSection({super.key, this.isActive = true});

  @override
  State<CalibrationSection> createState() => _CalibrationSectionState();
}

enum _Step { connect, prepare, measure, review }

class _DacLevels {
  final List<double> gain; // Y Pb Pr
  final int syncCodes;
  const _DacLevels(this.gain, this.syncCodes);
}

class _CalibrationSectionState extends State<CalibrationSection> {
  /// The subtrees the run resets, and the temporary preset each is kept in.
  static const _neutralised = {'/send/1': '_cal_send1', '/output/color': '_cal_output_color'};
  static const _pollEvery = Duration(seconds: 3);
  static const _nominalSyncCodes = 439; // 300 mV at 700 mV per 1024 codes

  Network? _net;
  bool _wasConnected = false;
  Timer? _poll;

  // Device state.
  String _calStatus = '—'; // saved | unsaved | defaults
  bool? _enabled;
  bool? _lutOn;
  List<int>? _adcOffset;
  final List<_DacLevels?> _dac = [null, null, null];
  List<List<double>>? _model; // 3 rows x 10 terms

  // Run state.
  _Step _step = _Step.connect;
  bool _busy = false;
  String _phase = '';
  int _done = 0, _total = 0;
  String _runState = 'idle';
  CalFitReport? _report;
  List<CalSample> _samples = const [];
  bool _loadingSamples = false;

  NorClient get _rpc => NorClient(context.read<Network>());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
    _poll = Timer.periodic(_pollEvery, (_) => _refreshStatus());
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

  @override
  void didUpdateWidget(CalibrationSection old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) _refreshAll();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _net?.removeListener(_onNet);
    super.dispose();
  }

  void _onNet() {
    final connected = _net?.isConnected ?? false;
    if (connected && !_wasConnected) _refreshAll();
    _wasConnected = connected;
  }

  bool get _connected => _net?.isConnected ?? false;

  /// One request/reply; null on timeout or when offline.
  /// [tries] 1 for anything that must not run twice (preset save/load/reset).
  Future<List<Object?>?> _ask(String addr, [List<Object> args = const [],
      Duration timeout = const Duration(seconds: 2), int tries = 2]) async {
    if (!_connected) return null;
    try {
      return await _rpc.call(addr, args, timeout: timeout, tries: tries);
    } on TimeoutException {
      return null;
    }
  }

  static double _d(Object? v) => (v is num) ? v.toDouble() : double.nan;
  static int _i(Object? v) => (v is num) ? v.toInt() : -1;

  // ---- reads -----------------------------------------------------------------

  Future<void> _refreshStatus() async {
    if (!widget.isActive || !_connected || !mounted) return;
    final s = await _ask('/calibration/status');
    final r = await _ask('/calibration/self/status');
    if (!mounted) return;
    setState(() {
      if (s != null && s.isNotEmpty && s.first is String) _calStatus = s.first as String;
      if (r != null && r.length >= 3) {
        _done = _i(r[0]);
        _total = _i(r[1]);
        _runState = '${r[2]}';
      }
    });
  }

  Future<void> _refreshAll() async {
    if (!_connected || !mounted) return;
    await _refreshStatus();
    final en = await _ask('/calibration/enable');
    final lut = await _ask('/calibration/return/lut');
    final adc = await _ask('/calibration/adc/offset');
    final dac = <_DacLevels?>[];
    for (var n = 1; n <= 3; n++) {
      final g = await _ask('/calibration/dac/$n/gain');
      final s = await _ask('/calibration/dac/$n/sync');
      dac.add(g != null && g.length >= 3 && s != null && s.isNotEmpty
          ? _DacLevels([_d(g[0]), _d(g[1]), _d(g[2])], _i(s[0]))
          : null);
    }
    final model = await _readModel();
    if (!mounted) return;
    setState(() {
      if (en != null && en.isNotEmpty) _enabled = _i(en[0]) != 0;
      if (lut != null && lut.isNotEmpty) _lutOn = _i(lut[0]) != 0;
      if (adc != null && adc.length >= 2) _adcOffset = [_i(adc[0]), _i(adc[1])];
      for (var k = 0; k < 3; k++) {
        _dac[k] = dac[k];
      }
      _model = model;
    });
    // A run done earlier this boot (here or from another client) still has its
    // samples on the device: show them.
    if (_runState == 'done' && _samples.isEmpty && !_busy) await _loadResults();
  }

  Future<List<List<double>>?> _readModel() async {
    final rows = <List<double>>[];
    for (final r in const ['y', 'cb', 'cr']) {
      final v = await _ask('/calibration/return/model/$r');
      if (v == null || v.length < 10) return null;
      rows.add([for (final x in v.take(10)) _d(x)]);
    }
    return rows;
  }

  Future<void> _loadResults() async {
    final rep = await _ask('/calibration/self/result');
    if (rep == null || rep.length < 13 || _i(rep[0]) <= 0) return;
    final rms = List.generate(
        2, (m) => List.generate(2, (s) => List.generate(3, (c) => _d(rep[1 + m * 6 + s * 3 + c]))));
    setState(() {
      _report = CalFitReport(_i(rep[0]), rms);
      _loadingSamples = true;
      _step = _Step.review;
    });
    final out = <CalSample>[];
    for (var i = 0; i < _total; i++) {
      final d = await _ask('/calibration/self/data', [i], const Duration(seconds: 1));
      if (d == null || d.length < 7) continue;
      out.add(CalSample(_i(d[0]) == 1, [_d(d[1]), _d(d[2]), _d(d[3])],
          [_d(d[4]), _d(d[5]), _d(d[6])]));
    }
    final model = await _readModel();
    if (!mounted) return;
    setState(() {
      _samples = out;
      _model = model ?? _model;
      _loadingSamples = false;
    });
  }

  // ---- the run ---------------------------------------------------------------

  Future<void> _run() async {
    if (!_connected) {
      showAppAlert(context, 'Connect to a device to calibrate', tone: AppAlertTone.error);
      return;
    }
    setState(() {
      _busy = true;
      _step = _Step.measure;
      _samples = const [];
      _report = null;
      _done = 0;
      _total = 0;
    });
    const long = Duration(seconds: 30);
    String? syncWas; // sync mode to put back, when the run had to change it
    final saved = <String>[]; // subtrees whose preset was written
    final stranded = <String>[]; // presets left on the device after a failed restore
    String? error;
    try {
      _setPhase('Saving your Send 1 and Return colour settings');
      for (final e in _neutralised.entries) {
        final s = await _ask('/assets/presets/save', [e.key, e.value], long, 1);
        if (s == null || s.length < 3 || _i(s[2]) < 0) throw 'could not save ${e.key} as a preset';
        saved.add(e.key);
      }

      // The patch readback is only stable with the ADC in LOCKED (in COMPONENT the
      // same patch read 11, 1100 and 2200 codes on successive reads), and LOCKED
      // is the primary mode the calibration is meant for.
      final sm = await _ask('/sync_mode');
      final mode = (sm != null && sm.isNotEmpty) ? '${sm.first}'.toUpperCase() : '';
      if (mode != 'LOCKED') {
        _setPhase('Switching sync to LOCKED for the measurement');
        await _ask('/sync_mode', ['LOCKED'], const Duration(seconds: 2), 1);
        syncWas = mode.isEmpty ? null : mode;
        await Future<void>.delayed(const Duration(seconds: 12)); // relock + AGC
      }

      _setPhase('Resetting Send 1 and Return colour to defaults');
      for (final p in _neutralised.keys) {
        final r = await _ask('/assets/presets/reset', [p], long, 1);
        if (r == null || r.length < 2 || _i(r[1]) < 0) throw 'could not reset $p';
      }
      await Future<void>.delayed(const Duration(seconds: 2)); // let the picture settle

      _setPhase('Measuring the analog loop');
      final r = await _ask('/calibration/self/run', [1], const Duration(seconds: 5), 1);
      if (r == null) throw 'the device did not start the run';
      while (mounted) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final st = await _ask('/calibration/self/status');
        if (st == null || st.length < 3) continue;
        setState(() {
          _done = _i(st[0]);
          _total = _i(st[1]);
          _runState = '${st[2]}';
        });
        if (_runState != 'running') break;
      }
      if (_runState != 'done') throw 'the fit failed; the previous calibration is still in effect';
    } catch (e) {
      error = '$e';
    } finally {
      _setPhase('Restoring your setup');
      for (final p in saved) {
        final name = _neutralised[p]!;
        final l = await _ask('/assets/presets/load', [name], long, 1);
        if (l != null && l.length >= 2 && _i(l[1]) >= 0) {
          await _ask('/assets/presets/delete', [name], const Duration(seconds: 10), 1);
        } else {
          stranded.add(name);
        }
      }
    }
    if (syncWas != null) {
      _setPhase('Switching sync back to $syncWas');
      await _ask('/sync_mode', [syncWas], const Duration(seconds: 2), 1);
    }
    if (stranded.isNotEmpty && mounted) {
      showAppAlert(
          context,
          'Could not restore part of your setup. Load ${stranded.join(' and ')} '
          'from Setup > Files to get it back.',
          tone: AppAlertTone.error);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _phase = '';
    });
    if (error != null) {
      setState(() => _step = _Step.prepare);
      showAppAlert(context, 'Calibration stopped: $error', tone: AppAlertTone.error);
      return;
    }
    await _loadResults();
    await _refreshAll();
  }

  void _setPhase(String p) {
    if (mounted) setState(() => _phase = p);
  }

  Future<void> _save() async {
    final r = await _ask('/calibration/save', const [], const Duration(seconds: 5));
    if (!mounted) return;
    showAppAlert(context, r != null ? 'Calibration saved' : 'Saving the calibration failed',
        tone: r != null ? AppAlertTone.success : AppAlertTone.error);
    await _refreshAll();
  }

  Future<void> _discard() async {
    final r = await _ask('/calibration/load', const [], const Duration(seconds: 5));
    if (!mounted) return;
    showAppAlert(context, r != null ? 'Back to the saved calibration' : 'Reverting failed',
        tone: r != null ? AppAlertTone.success : AppAlertTone.error);
    await _refreshAll();
  }

  Future<void> _setEnabled(bool on) async {
    await _ask('/calibration/enable', [on ? 1 : 0]);
    await _refreshAll();
  }

  // ---- layout ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context, defaultWidth: 1000);
    return LabeledCard(
      title: 'Calibration',
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.cardBodyInset, t.xs, t.md, t.md),
        child: LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 900;
          final status = _statusColumn(t);
          final steps = _stepsColumn(t);
          final charts = _chartsColumn(t);
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [status, SizedBox(height: t.md), steps, SizedBox(height: t.md), charts],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: c.maxWidth * 0.24, child: status),
              SizedBox(width: t.lg),
              SizedBox(width: c.maxWidth * 0.30, child: steps),
              SizedBox(width: t.lg),
              Expanded(child: charts),
            ],
          );
        }),
      ),
    );
  }

  // Status: what is in effect now.
  Widget _statusColumn(GridTokens t) {
    final statusTone = switch (_calStatus) {
      'saved' => _Tone.good,
      'unsaved' => _Tone.warn,
      'defaults' => _Tone.bad,
      _ => _Tone.neutral,
    };
    final statusText = switch (_calStatus) {
      'saved' => 'Saved',
      'unsaved' => 'Not saved',
      'defaults' => 'Factory defaults',
      _ => '—',
    };
    Widget kv(String k, Widget v) => Padding(
          padding: EdgeInsets.only(bottom: t.xs),
          child: Row(children: [
            Expanded(child: Text(k, style: t.textLabel)),
            v,
          ]),
        );
    Text val(String s) => Text(s, style: t.textValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STATUS', style: t.textPanelTitle),
        SizedBox(height: t.sm),
        kv('Calibration', _Pill(statusText, statusTone)),
        kv('Correction', _Pill(
            _enabled == null ? '—' : (_enabled! ? 'On' : 'Off'),
            _enabled == null ? _Tone.neutral : (_enabled! ? _Tone.good : _Tone.bad))),
        kv('Return model', val(_lutOn == null ? '—' : (_lutOn! ? '3D LUT' : 'Gain matrix'))),
        kv('Last fit', val(_report == null
            ? 'none this boot'
            : (_report!.chosen == 2 ? 'Quadratic' : 'Linear'))),
        kv('ADC window', val(_adcOffset == null ? '—' : 'H ${_adcOffset![0]}  V ${_adcOffset![1]}')),
        SizedBox(height: t.sm),
        Text('ANALOG OUTPUT LEVELS', style: t.textPanelTitle),
        SizedBox(height: t.xs),
        for (var n = 0; n < 3; n++) _dacRow(t, n),
        SizedBox(height: t.xs),
        Text(
            'Set once per unit with an oscilloscope on the terminated output '
            '(/calibration/dac/N/gain and /sync). Sync 439 codes is the 300 mV design value.',
            style: t.textCaption),
        SizedBox(height: t.sm),
        AppButton(
          label: (_enabled ?? true) ? 'Turn correction off' : 'Turn correction on',
          sizeToLabels: const ['Turn correction off', 'Turn correction on'],
          onPressed: _busy || _enabled == null ? null : () => _setEnabled(!_enabled!),
        ),
      ],
    );
  }

  Widget _dacRow(GridTokens t, int n) {
    final d = _dac[n];
    String g(double v) => v.isNaN ? '—' : '×${v.toStringAsFixed(3)}';
    final trimmed = d != null &&
        (d.gain.any((v) => (v - 1).abs() > 1e-4) || d.syncCodes != _nominalSyncCodes);
    return Padding(
      padding: EdgeInsets.only(bottom: t.xs * 0.6),
      child: Row(children: [
        SizedBox(width: 4.5 * t.u, child: Text('Send ${n + 1}', style: t.textLabel)),
        Expanded(
          child: Text(
            d == null
                ? '—'
                : 'Y ${g(d.gain[0])}  Pb ${g(d.gain[1])}  Pr ${g(d.gain[2])}  sync ${d.syncCodes}',
            style: t.textCaption.copyWith(
                color: trimmed ? const Color(0xFFF2F2F2) : const Color(0xFFACACB2)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  // The walkthrough.
  Widget _stepsColumn(GridTokens t) {
    Widget step(_Step s, int n, String title, Widget body) {
      final active = _step == s;
      final done = _step.index > s.index;
      final c = done
          ? const Color(0xFF5FD38D)
          : active
              ? Colors.white
              : const Color(0xFF6E6E76);
      return Padding(
        padding: EdgeInsets.only(bottom: t.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 2.0 * t.u,
            height: 2.0 * t.u,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c, width: 1.4),
              color: done ? c.withValues(alpha: 0.18) : null,
            ),
            child: done
                ? Icon(Icons.check, size: 1.3 * t.u, color: c)
                : Text('$n', style: t.textCaption.copyWith(color: c)),
          ),
          SizedBox(width: t.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.textLabel.copyWith(color: c)),
              if (active) ...[SizedBox(height: t.xs), body],
            ]),
          ),
        ]),
      );
    }

    final pct = _total > 0 ? _done / _total : 0.0;
    final remain = _total > 0 ? ((_total - _done) * 0.57).round() : 0; // ~0.57 s per colour

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SELF-CALIBRATION', style: t.textPanelTitle),
        SizedBox(height: t.sm),
        step(
          _Step.connect,
          1,
          'Connect the loop',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'Cable Send 1\'s analog output to the analog input (Return) and leave it '
                'connected. A dirty front-panel connector shows as colour fringes on edges: '
                'clean it first. Let the unit warm up for a few minutes.',
                style: t.textBody),
            SizedBox(height: t.sm),
            AppButton(label: 'Next', onPressed: () => setState(() => _step = _Step.prepare)),
          ]),
        ),
        step(
          _Step.prepare,
          2,
          'Prepare',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'Send 1\'s settings and the Return\'s colour controls are saved as temporary '
                'presets and set to defaults while the device measures, then put back. Send 1 '
                'shows a flat test patch for about four minutes. The format stays as it is; '
                'sync switches to LOCKED for the measurement and back afterwards.',
                style: t.textBody),
            SizedBox(height: t.sm),
            Row(children: [
              AppButton(label: 'Start calibration', onPressed: _busy ? null : _run),
              SizedBox(width: t.sm),
              AppButton(label: 'Back', onPressed: _busy ? null : () => setState(() => _step = _Step.connect)),
            ]),
          ]),
        ),
        step(
          _Step.measure,
          3,
          'Measure',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_phase.isEmpty ? 'Starting' : _phase, style: t.textBody),
            SizedBox(height: t.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _total > 0 ? pct : null,
                minHeight: 0.6 * t.u,
                backgroundColor: const Color(0xFF2A2A30),
                color: const Color(0xFF3BDEFF),
              ),
            ),
            SizedBox(height: t.xs),
            Text(
                _total > 0 ? '$_done of $_total colours · about ${remain ~/ 60}:${(remain % 60).toString().padLeft(2, '0')} left' : '',
                style: t.textCaption),
          ]),
        ),
        step(
          _Step.review,
          4,
          'Review and save',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_verdict(), style: t.textBody),
            SizedBox(height: t.sm),
            Row(children: [
              AppButton(
                label: 'Save calibration',
                onPressed: _busy || _calStatus == 'saved' ? null : _save,
              ),
              SizedBox(width: t.sm),
              AppButton(
                label: 'Discard',
                tooltip: 'Go back to the calibration saved on the device',
                onPressed: _busy || _calStatus == 'saved' ? null : _discard,
              ),
            ]),
            SizedBox(height: t.xs),
            AppButton(
              label: 'Run again',
              onPressed: _busy ? null : () => setState(() => _step = _Step.prepare),
            ),
          ]),
        ),
      ],
    );
  }

  /// Plain-language verdict on the validation error (colours the fit never saw).
  String _verdict() {
    final r = _report;
    if (r == null) return 'No results yet.';
    final v = r.rms[r.chosen - 1][1];
    final worst = v.reduce(math.max);
    final model = r.chosen == 2 ? 'quadratic' : 'linear';
    final q = worst <= 3
        ? 'Excellent'
        : worst <= 6
            ? 'Good'
            : worst <= 10
                ? 'Marginal: check the loop cable and connector, then run again'
                : 'Poor: the loop is probably not connected properly';
    return '$q. The $model model reproduces colours it was not fitted to within '
        '${worst.toStringAsFixed(1)} codes rms (of 4095) on the worst channel. '
        'The new calibration is already in effect; save it to keep it after a reboot.';
  }

  // Graphics.
  Widget _chartsColumn(GridTokens t) {
    if (_report == null) {
      return SizedBox(
        height: 18 * t.u,
        child: Center(
          child: Text(
              _busy ? 'Results appear when the run finishes.' : 'Run a calibration to see its statistics here.',
              style: t.textCaption),
        ),
      );
    }
    final h = 17 * t.u;
    Widget panel(String title, String caption, CustomPainter p) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.textPanelTitle),
            SizedBox(height: t.xs),
            SizedBox(height: h, child: CustomPaint(painter: p, size: Size.infinite)),
            SizedBox(height: t.xs * 0.6),
            Text(caption, style: t.textCaption),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        panel('FIT ERROR', 'rms codes per channel · faint = training, solid = validation',
            CalFitBarsPainter(_report!, t.textCaption)),
        SizedBox(width: t.md),
        panel(
            'RAW LOOP COLOUR',
            _loadingSamples ? 'Loading samples…' : 'Cb/Cr: ring = sent, dot = received before correction, error ×5',
            CalVectorscopePainter(_samples, t.textCaption)),
        SizedBox(width: t.md),
        panel(
            'AFTER CORRECTION',
            _loadingSamples ? 'Loading samples…' : 'residual codes vs luma · Y white, Cb blue, Cr red',
            CalResidualPainter(_samples, _model, t.textCaption)),
      ]),
    ]);
  }
}

// ---- small widgets ---------------------------------------------------------------

enum _Tone { good, warn, bad, neutral }

class _Pill extends StatelessWidget {
  final String text;
  final _Tone tone;
  const _Pill(this.text, this.tone);

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context, defaultWidth: 1000);
    final c = switch (tone) {
      _Tone.good => const Color(0xFF5FD38D),
      _Tone.warn => const Color(0xFFF2B84B),
      _Tone.bad => const Color(0xFFE46F86),
      _Tone.neutral => const Color(0xFF9A9AA1),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 0.6 * t.u, vertical: 0.15 * t.u),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(t.u),
        border: Border.all(color: c.withValues(alpha: 0.7), width: 1),
      ),
      child: Text(text, style: t.textCaption.copyWith(color: c)),
    );
  }
}

