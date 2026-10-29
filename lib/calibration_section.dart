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
/// are left alone, except that the run measures in LOCKED (the primary mode)
/// and switches back afterwards. Only
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

/// What happened to a finished run's result.
enum _Outcome { none, saved, saveFailed, rejected }

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
  final List<_DacLevels?> _dac = [null, null, null];
  List<List<double>>? _model; // 3 rows x 10 terms

  // Run state.
  _Step _step = _Step.connect;
  bool _busy = false;
  String _phase = '';
  int _done = 0, _total = 0;
  String _runState = 'idle';
  CalFitReport? _report;
  int _nData = 0; // colours the fit measured (train + validation); the status total also counts the loop step
  // Progress is weighted by time: the device shows 14 colours at once; a fitted colour costs ~0.15 s, a
  // closed-loop colour ~0.55 s (each group of 14 fills the loop, then is tracked for 6.5 s).
  static const _loopWeight = 3.5;
  DateTime? _runStart;
  double? _eta; // seconds left, smoothed

  double get _fraction {
    if (_total <= 0) return 0;
    final nFit = _nData > 0 ? math.min(_nData, _total) : _total;
    final wTotal = nFit + _loopWeight * (_total - nFit);
    final wDone = math.min(_done, nFit) + _loopWeight * math.max(0, _done - nFit);
    return wTotal > 0 ? (wDone / wTotal).clamp(0.0, 1.0) : 0;
  }

  /// Time left from the time the run has taken so far for the work done, smoothed so one slow or fast colour does
  /// not swing it; null until there is enough to go on.
  void _updateEta() {
    final start = _runStart, f = _fraction;
    if (start == null || f < 0.03) return;
    final elapsed = DateTime.now().difference(start).inMilliseconds / 1000.0;
    final est = elapsed * (1 - f) / f;
    final prev = _eta;
    _eta = prev == null ? est : 0.85 * math.max(0, prev - 1) + 0.15 * est;
  }
  List<CalSample> _samples = const [];
  bool _loadingSamples = false;
  _Outcome _outcome = _Outcome.none;

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
      if (r != null && r.length >= 3 && !_busy) {   // during a run the run loop owns these
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
    for (var i = 0; i < (_nData > 0 ? _nData : _total); i++) {
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
      _outcome = _Outcome.none;
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
        if (s == null || s.length < 3) throw 'could not save ${e.key} as a preset (no reply)';
        final rc = _i(s[2]);
        if (rc == -2) throw 'could not save ${e.key} as a preset: the preset store is full (delete presets in Files)';
        if (rc < 0) throw 'could not save ${e.key} as a preset (error $rc)';
        saved.add(e.key);
      }

      // Measure in LOCKED, the primary mode. (One afternoon the patch readback
      // came back empty or half-empty while in COMPONENT; it did not recur in
      // COMPONENT entered by switch, cold boot or crash reboot, cause unknown.)
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
      if (r.length >= 2) _nData = _i(r[0]) + _i(r[1]);
      _runStart = DateTime.now();
      _eta = null;
      while (mounted) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final st = await _ask('/calibration/self/status');
        if (st == null || st.length < 3) continue;
        setState(() {
          _done = _i(st[0]);
          _total = _i(st[1]);
          _runState = '${st[2]}';
          _updateEta();
        });
        if (_runState != 'running') break;
      }
      if (_runState != 'done') throw 'the measurements did not fit a calibration, so the previous one is still in effect. Check that the loop cable runs from Send 1\'s output to the analog input, then run again';
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
    await _decide();
    await _refreshAll();
  }

  /// Validation rms (colours the fit never saw), worst channel, in 12-bit codes.
  double? get _worst {
    final r = _report;
    if (r == null) return null;
    return r.rms[r.chosen - 1][1].reduce(math.max);
  }

  /// Keep a good run (saved, so it survives a reboot); put back the saved
  /// calibration after a worse one. Good runs today measured 4.3-5.7 codes on
  /// the worst channel (Cb) and broken ones hundreds; [_acceptCodes] sits just
  /// above the good ones.
  static const _acceptCodes = 6.0;
  Future<void> _decide() async {
    final w = _worst;
    if (w == null) return;
    _Outcome o;
    if (w <= _acceptCodes) {
      final r = await _ask('/calibration/save', const [], const Duration(seconds: 5), 1);
      o = r != null ? _Outcome.saved : _Outcome.saveFailed;
    } else {
      await _ask('/calibration/load', const [], const Duration(seconds: 5), 1);
      o = _Outcome.rejected;
    }
    if (mounted) setState(() => _outcome = o);
  }

  void _setPhase(String p) {
    if (mounted) setState(() => _phase = p);
  }

  Future<void> _saveExisting() async {
    final r = await _ask('/calibration/save', const [], const Duration(seconds: 5), 1);
    if (mounted) setState(() => _outcome = r != null ? _Outcome.saved : _Outcome.saveFailed);
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statusStrip(t),
            SizedBox(height: t.md),
            _stepper(t),
            if (_report != null) ...[SizedBox(height: t.lg), _charts(t)],
          ],
        ),
      ),
    );
  }

  /// What is in effect now, on one wrapping line of label/value pairs.
  Widget _statusStrip(GridTokens t) {
    Widget fact(String label, Widget value) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: t.textPanelTitle),
            SizedBox(width: t.xs),
            value,
          ],
        );
    Text val(String s) => Text(s, style: t.textValue);

    // During a run the device holds the identity model it measures through, so
    // its status reads "unsaved"; say what is actually happening instead.
    final (statusText, statusTone) = _busy ? ('Measuring', _Tone.neutral) : switch (_calStatus) {
      'saved' => ('Saved', _Tone.good),
      'unsaved' => ('Not saved', _Tone.warn),
      'defaults' => ('Factory defaults', _Tone.bad),
      _ => ('—', _Tone.neutral),
    };
    final on = _enabled;
    final w = _worst;
    final trims = <String>[];
    for (var n = 0; n < 3; n++) {
      final d = _dac[n];
      if (d == null) continue;
      final parts = <String>[
        for (var k = 0; k < 3; k++)
          if ((d.gain[k] - 1).abs() > 1e-4) '${const ['Y', 'Pb', 'Pr'][k]} ×${d.gain[k].toStringAsFixed(3)}',
        if (d.syncCodes != _nominalSyncCodes) 'sync ${d.syncCodes}',
      ];
      if (parts.isNotEmpty) trims.add('Send ${n + 1} ${parts.join(' ')}');
    }

    return Wrap(
      spacing: 2 * t.lg,
      runSpacing: t.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        fact('CALIBRATION', _Pill(statusText, statusTone)),
        fact(
          'CORRECTION',
          AppButton(
            label: on == null ? '—' : (on ? 'On' : 'Off'),
            sizeToLabels: const ['On', 'Off'],
            dense: true,
            selected: on ?? false,
            accentColor: const Color(0xFF5FD38D),
            tooltip: on == true
                ? 'Turn the correction off to see the uncorrected loop'
                : 'Turn the correction back on',
            onPressed: _busy || on == null ? null : () => _setEnabled(!on),
          ),
        ),
        fact('MODEL', val(_lutOn == null
            ? '—'
            : _lutOn!
                ? (_report == null ? '3D LUT' : '3D LUT · ${_report!.chosen == 2 ? 'quadratic' : 'linear'}')
                : 'gain matrix')),
        if (w != null) fact('ACCURACY', val('${w.toStringAsFixed(1)} codes')),
        Tooltip(
          message: 'Factory trims of each analog output\'s levels (set once per unit)',
          child: fact('OUTPUT TRIMS', val(trims.isEmpty ? 'none' : trims.join(' · '))),
        ),
      ],
    );
  }

  /// The walkthrough: a numbered strip across the top, then the current step.
  Widget _stepper(GridTokens t) {
    const titles = ['Connect', 'Prepare', 'Measure', 'Result'];
    const green = Color(0xFF5FD38D);
    Widget marker(int i) {
      final done = _step.index > i, active = _step.index == i;
      final c = done ? green : active ? Colors.white : const Color(0xFF6E6E76);
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 1.8 * t.u,
          height: 1.8 * t.u,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c, width: 1.4),
            color: done ? c.withValues(alpha: 0.18) : null,
          ),
          child: done
              ? Icon(Icons.check, size: 1.15 * t.u, color: c)
              : Text('${i + 1}', style: t.textCaption.copyWith(color: c)),
        ),
        SizedBox(width: t.xs),
        Text(titles[i], style: t.textLabel.copyWith(color: c)),
      ]);
    }

    final strip = Row(children: [
      for (var i = 0; i < 4; i++) ...[
        marker(i),
        if (i < 3)
          Expanded(
            child: Container(
              height: 1,
              margin: EdgeInsets.symmetric(horizontal: t.sm),
              color: _step.index > i ? green.withValues(alpha: 0.6) : const Color(0xFF3A3A40),
            ),
          ),
      ],
    ]);

    Widget body(String text, List<Widget> actions) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 60 * t.u),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: t.textBody),
            if (actions.isNotEmpty) ...[
              SizedBox(height: t.sm),
              Wrap(spacing: t.sm, runSpacing: t.xs, children: actions),
            ],
          ]),
        );

    final pct = _fraction;
    final eta = _eta;
    final left = eta == null
        ? 'estimating'
        : eta >= 90
            ? '~${(eta / 60).round()} min left'
            : '~${(eta / 10).ceil() * 10} s left';

    final Widget content = switch (_step) {
      _Step.connect => body(
          'Loop Send 1\'s analog output into the analog input and leave it connected. '
          'Clean the front-panel connector if edges show colour fringes, and let the '
          'unit warm up for a few minutes.',
          [AppButton(label: 'Next', onPressed: () => setState(() => _step = _Step.prepare))]),
      _Step.prepare => body(
          'Send 1 shows bands of test colours for about a minute, then loops the Return back '
          'into itself for about two more to measure the feedback loop. Its settings and the '
          'Return\'s colour controls go to defaults for the measurement and are put back '
          'afterwards; sync runs in LOCKED meanwhile.',
          [
            AppButton(label: 'Start calibration', onPressed: _busy ? null : _run),
            AppButton(label: 'Back', onPressed: _busy ? null : () => setState(() => _step = _Step.connect)),
          ]),
      _Step.measure => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 60 * t.u),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(_phase.isEmpty ? 'Starting' : _phase, style: t.textBody)),
              if (_total > 0)
                Text('${(pct * 100).round()} % · $left', style: t.textCaption),
            ]),
            SizedBox(height: t.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _total > 0 ? pct : null,
                minHeight: 0.5 * t.u,
                backgroundColor: const Color(0xFF2A2A30),
                color: const Color(0xFF3BDEFF),
              ),
            ),
          ]),
        ),
      _Step.review => body(_verdict(), [
          // A result this card did not produce (another client's run) is not
          // auto-saved; offer it when it would have passed.
          if (_outcome == _Outcome.none && _calStatus == 'unsaved' && (_worst ?? 1e9) <= _acceptCodes)
            AppButton(label: 'Save', onPressed: _busy ? null : _saveExisting),
          AppButton(label: 'Run again', onPressed: _busy ? null : () => setState(() => _step = _Step.prepare)),
        ]),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      strip,
      SizedBox(height: t.md),
      Padding(padding: EdgeInsets.only(left: 2.3 * t.u), child: content),
    ]);
  }

  /// Plain-language result: what the fit achieved on colours it never saw, and
  /// what was done with it.
  String _verdict() {
    final r = _report;
    final w = _worst;
    if (r == null || w == null) return 'No results yet.';
    final v = r.rms[r.chosen - 1][1];
    final ch = const ['Y', 'Cb', 'Cr'][v.indexOf(w)];
    String pct(double codes) => '${(codes / 4095 * 100).toStringAsFixed(codes < 41 ? 2 : 1)}%';
    final off = '${pct(w)} (${w.toStringAsFixed(1)} of 4095 levels, worst on $ch)';
    switch (_outcome) {
      case _Outcome.saved:
        return '${w <= 3 ? 'Excellent' : 'Good'}. After correction, colours come back within $off. Saved.';
      case _Outcome.saveFailed:
        return 'Good. After correction, colours come back within $off, but saving to the '
            'device failed, so it will be lost at the next reboot. Run again.';
      case _Outcome.rejected:
        return 'Not kept. Colours came back off by $off; a healthy loop is within '
            '${pct(_acceptCodes)}. The previous calibration is still in effect. Check the loop '
            'cable and the front-panel connector, then run again.';
      case _Outcome.none:
        return 'After correction, colours come back within $off. '
            '${_calStatus == 'saved' ? 'Saved.' : 'Not saved yet.'}';
    }
  }

  /// The run's statistics, three equal panels across the card.
  Widget _charts(GridTokens t) {
    return LayoutBuilder(builder: (context, c) {
      final gap = t.lg;
      final w = (c.maxWidth - 2 * gap) / 3;
      final h = math.min(w * 0.72, 18 * t.u);
      Widget panel(String title, String caption, CustomPainter p, {bool square = false}) => SizedBox(
            width: w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.textPanelTitle),
              SizedBox(height: t.xs),
              SizedBox(
                height: h,
                child: square
                    ? Center(child: AspectRatio(aspectRatio: 1, child: CustomPaint(painter: p)))
                    : CustomPaint(painter: p, size: Size.infinite),
              ),
              SizedBox(height: t.xs * 0.6),
              Text(_loadingSamples && p is! CalFitBarsPainter ? 'Loading samples…' : caption,
                  style: t.textCaption, maxLines: 2),
            ]),
          );
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        panel('FIT ERROR', 'rms codes · grey linear, cyan quadratic · solid = unseen colours',
            CalFitBarsPainter(_report!, t.textCaption)),
        SizedBox(width: gap),
        panel('LOOP COLOUR', 'Cb/Cr before correction · ring sent, dot received, error ×5',
            CalVectorscopePainter(_samples, t.textCaption),
            square: true),
        SizedBox(width: gap),
        panel('AFTER CORRECTION', 'residual codes vs luma · Y white, Cb blue, Cr red',
            CalResidualPainter(_samples, _model, t.textCaption)),
      ]);
    });
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

