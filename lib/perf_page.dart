import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'network.dart';
import 'osc_registry.dart';

class PerfPage extends StatefulWidget {
  const PerfPage({super.key});

  @override
  State<PerfPage> createState() => _PerfPageState();
}

class _PerfPageState extends State<PerfPage> {
  Timer? _statsTimer;
  Timer? _resourceTimer;
  DateTime? _startTime;

  // --- Stats endpoint values (13 ints) ---
  int _rxPackets = 0;
  int _txReply = 0;
  int _txOthers = 0;
  int _txAll = 0;
  int _deferredCalls = 0;
  int _hwProcessed = 0;
  int _hwDeferred = 0;
  int _respQueued = 0;
  int _respSent = 0;
  int _respDropped = 0;
  int _pendingHw = 0;
  int _pendingResp = 0;
  double _cpuTemp = 0;

  // Previous values + timestamps for rate computation
  int? _prevRxPackets;
  int? _prevTxReply;
  int? _prevTxOthers;
  int? _prevTxAll;
  int? _prevDeferredCalls;
  int? _prevHwProcessed;
  int? _prevHwDeferred;
  int? _prevRespQueued;
  int? _prevRespSent;
  int? _prevRespDropped;
  DateTime? _prevStatsTime;

  // EMA rates
  double _rateRxPackets = 0;
  double _rateTxReply = 0;
  double _rateTxOthers = 0;
  double _rateTxAll = 0;
  double _rateDeferredCalls = 0;
  double _rateHwProcessed = 0;
  double _rateHwDeferred = 0;
  double _rateRespQueued = 0;
  double _rateRespSent = 0;
  double _rateRespDropped = 0;

  // --- Workload (per channel, 10 ints each) ---
  final List<List<int>> _workload = [
    List.filled(10, 0),
    List.filled(10, 0),
  ];

  // --- IMAP ID (1 int) ---
  int _imapId = 0;

  // --- Framebuf (5 ints) ---
  List<int> _framebuf = List.filled(5, 0);

  // --- Screen off mask (1 int) ---
  int _screenOffMask = 0;

  // --- Frame delay per channel (1 int each) ---
  int _frameDelayCh0 = 0;
  int _frameDelayCh1 = 0;

  // --- IMEM/RMEM per channel (2 ints each) ---
  final List<List<int>> _imemRmem = [
    List.filled(2, 0),
    List.filled(2, 0),
    List.filled(2, 0),
    List.filled(2, 0),
  ];

  static const double _alpha = 0.3;

  static const String _addrStats = '/stats';
  static const String _addrWorkloadCh0 = '/resource/current/workload/ch0';
  static const String _addrWorkloadCh1 = '/resource/current/workload/ch1';
  static const String _addrStatus = '/resource/current/status';
  static const String _addrImapId = '/resource/current/imap/id';
  static const String _addrFramebuf = '/resource/current/framebuf';
  static const String _addrScreenOffMask = '/resource/current/screen_off_mask';
  static const String _addrFrameDelayCh0 = '/resource/current/frame_delay/ch0';
  static const String _addrFrameDelayCh1 = '/resource/current/frame_delay/ch1';
  static const String _addrImemRmemCh0 = '/resource/current/imem_rmem/ch0';
  static const String _addrImemRmemCh1 = '/resource/current/imem_rmem/ch1';
  static const String _addrImemRmemCh2 = '/resource/current/imem_rmem/ch2';
  static const String _addrImemRmemCh3 = '/resource/current/imem_rmem/ch3';

  static const List<String> _allAddresses = [
    _addrStats,
    _addrWorkloadCh0,
    _addrWorkloadCh1,
    _addrStatus,
    _addrImapId,
    _addrFramebuf,
    _addrScreenOffMask,
    _addrFrameDelayCh0,
    _addrFrameDelayCh1,
    _addrImemRmemCh0,
    _addrImemRmemCh1,
    _addrImemRmemCh2,
    _addrImemRmemCh3,
  ];

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _registerCallbacks();

    _statsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final network = context.read<Network>();
      network.sendOscMessage(_addrStats, []);
    });

    _resourceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final network = context.read<Network>();
      for (final addr in _allAddresses) {
        if (addr == _addrStats) continue;
        network.sendOscMessage(addr, []);
      }
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _resourceTimer?.cancel();
    _unregisterCallbacks();
    super.dispose();
  }

  void _onStats(List<Object?> args) {
    if (args.length < 15) return;
    final ints = args.sublist(0, 14).map((a) => (a as num).toInt()).toList();
    final temp = (args[14] as num).toDouble();

    final now = DateTime.now();
    if (_prevStatsTime != null) {
      final elapsed = now.difference(_prevStatsTime!).inMilliseconds / 1000.0;
      if (elapsed > 0) {
        _rateRxPackets = _ema(_rateRxPackets, (ints[0] - _prevRxPackets!) / elapsed);
        _rateTxReply = _ema(_rateTxReply, (ints[1] - _prevTxReply!) / elapsed);
        _rateTxOthers = _ema(_rateTxOthers, (ints[2] - _prevTxOthers!) / elapsed);
        _rateTxAll = _ema(_rateTxAll, (ints[3] - _prevTxAll!) / elapsed);
        _rateDeferredCalls = _ema(_rateDeferredCalls, (ints[5] - _prevDeferredCalls!) / elapsed);
        _rateHwProcessed = _ema(_rateHwProcessed, (ints[6] - _prevHwProcessed!) / elapsed);
        _rateHwDeferred = _ema(_rateHwDeferred, (ints[7] - _prevHwDeferred!) / elapsed);
        _rateRespQueued = _ema(_rateRespQueued, (ints[8] - _prevRespQueued!) / elapsed);
        _rateRespSent = _ema(_rateRespSent, (ints[9] - _prevRespSent!) / elapsed);
        _rateRespDropped = _ema(_rateRespDropped, (ints[10] - _prevRespDropped!) / elapsed);
      }
    }

    _prevRxPackets = ints[0];
    _prevTxReply = ints[1];
    _prevTxOthers = ints[2];
    _prevTxAll = ints[3];
    _prevDeferredCalls = ints[5];
    _prevHwProcessed = ints[6];
    _prevHwDeferred = ints[7];
    _prevRespQueued = ints[8];
    _prevRespSent = ints[9];
    _prevRespDropped = ints[10];
    _prevStatsTime = now;

    if (!mounted) return;
    setState(() {
      _rxPackets = ints[0];
      _txReply = ints[1];
      _txOthers = ints[2];
      _txAll = ints[3];
      _deferredCalls = ints[5];
      _hwProcessed = ints[6];
      _hwDeferred = ints[7];
      _respQueued = ints[8];
      _respSent = ints[9];
      _respDropped = ints[10];
      _pendingHw = ints[11];
      _pendingResp = ints[12];
      _cpuTemp = temp;
    });
  }

  void _onWorkload(int ch, List<Object?> args) {
    if (args.length < 10) return;
    final ints = args.map((a) => (a as num).toInt()).toList();
    if (!mounted) return;
    setState(() {
      _workload[ch] = ints;
    });
  }

  void _onImapId(List<Object?> args) {
    if (args.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _imapId = (args[0] as num).toInt();
    });
  }

  void _onFramebuf(List<Object?> args) {
    if (args.length < 5) return;
    final ints = args.map((a) => (a as num).toInt()).toList();
    if (!mounted) return;
    setState(() {
      _framebuf = ints;
    });
  }

  void _onScreenOffMask(List<Object?> args) {
    if (args.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _screenOffMask = (args[0] as num).toInt();
    });
  }

  void _onFrameDelay(int ch, List<Object?> args) {
    if (args.isEmpty) return;
    if (!mounted) return;
    setState(() {
      if (ch == 0) {
        _frameDelayCh0 = (args[0] as num).toInt();
      } else {
        _frameDelayCh1 = (args[0] as num).toInt();
      }
    });
  }

  void _onImemRmem(int ch, List<Object?> args) {
    if (args.length < 2) return;
    final ints = args.map((a) => (a as num).toInt()).toList();
    if (!mounted) return;
    setState(() {
      _imemRmem[ch] = ints;
    });
  }

  double _ema(double prev, double current) {
    return prev == 0 ? current : _alpha * current + (1 - _alpha) * prev;
  }

  final Map<String, OscCallback> _callbacks = {};

  void _registerCallbacks() {
    final registry = OscRegistry();

    _callbacks[_addrStats] = _onStats;
    _callbacks[_addrWorkloadCh0] = (args) => _onWorkload(0, args);
    _callbacks[_addrWorkloadCh1] = (args) => _onWorkload(1, args);
    _callbacks[_addrStatus] = (_) {};
    _callbacks[_addrImapId] = _onImapId;
    _callbacks[_addrFramebuf] = _onFramebuf;
    _callbacks[_addrScreenOffMask] = _onScreenOffMask;
    _callbacks[_addrFrameDelayCh0] = (args) => _onFrameDelay(0, args);
    _callbacks[_addrFrameDelayCh1] = (args) => _onFrameDelay(1, args);
    _callbacks[_addrImemRmemCh0] = (args) => _onImemRmem(0, args);
    _callbacks[_addrImemRmemCh1] = (args) => _onImemRmem(1, args);
    _callbacks[_addrImemRmemCh2] = (args) => _onImemRmem(2, args);
    _callbacks[_addrImemRmemCh3] = (args) => _onImemRmem(3, args);

    for (final entry in _callbacks.entries) {
      registry.registerAddress(entry.key);
      registry.registerListener(entry.key, entry.value);
    }
  }

  void _unregisterCallbacks() {
    final registry = OscRegistry();
    for (final entry in _callbacks.entries) {
      registry.unregisterListener(entry.key, entry.value);
    }
    _callbacks.clear();
  }

  String _formatUptime() {
    final elapsed = DateTime.now().difference(_startTime!);
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes % 60;
    final seconds = elapsed.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  String _fmtCount(int v, int width) {
    return v.toString().padLeft(width);
  }

  String _fmtRate(double v) {
    return v.toStringAsFixed(1).padLeft(7);
  }

  String _workloadBar(int work, int limit) {
    if (limit <= 0) {
      final filled = work > 0 ? 10 : 0;
      final bar = '\u2593' * filled + '\u2591' * (10 - filled);
      return '$bar ${work > 0 ? "!!" : ""}';
    }
    final pct = (work / limit * 100).round();
    final filledCount = (work / limit * 10).round().clamp(0, 10);
    final bar = '\u2593' * filledCount + '\u2591' * (10 - filledCount);
    final warn = work > limit ? ' !!' : '';
    return '$bar $pct%$warn';
  }

  String _screenOffStr(int mask) {
    final buf = StringBuffer();
    for (int i = 0; i < 4; i++) {
      buf.write((mask & (1 << i)) != 0 ? 'X' : '-');
    }
    return buf.toString();
  }

  String _transModeName(int mode) {
    switch (mode) {
      case 0: return 'RECT';
      case 1: return 'ORISHFT';
      case 2: return 'WARP';
      case 3: return 'LUT';
      case 4: return 'PIVOT';
      case 5: return 'RPIVOT';
      case 8: return 'LUT_RE';
      case 12: return 'PIVOT90';
      case 13: return 'RPIVOT90';
      default: return 'mode$mode';
    }
  }

  String _channelLabel(int ch) {
    switch (ch) {
      case 0:
        return 'Return';
      case 1:
        return 'Send 1';
      case 2:
        return 'Send 2';
      case 3:
        return 'Send 3';
      default:
        return 'CH$ch';
    }
  }

  String _buildDisplay() {
    final buf = StringBuffer();
    final line = '\u2550' * 65;
    final thinLine = '\u2500' * 61;

    final tempStr = _cpuTemp > -900 ? '${_cpuTemp.toStringAsFixed(1)}°C' : '---';
    buf.writeln('SCION Performance Monitor            CPU: $tempStr   uptime: ${_formatUptime()}');
    buf.writeln(line);
    buf.writeln();

    // OSC Transport
    buf.writeln(' OSC Transport');
    buf.writeln(' $thinLine');
    buf.writeln('  RX packets:  ${_fmtCount(_rxPackets, 10)}    (${_fmtRate(_rateRxPackets)} /s)');
    buf.writeln('  TX reply:    ${_fmtCount(_txReply, 10)}    (${_fmtRate(_rateTxReply)} /s)');
    buf.writeln('  TX others:   ${_fmtCount(_txOthers, 10)}    (${_fmtRate(_rateTxOthers)} /s)');
    buf.writeln('  TX all:      ${_fmtCount(_txAll, 10)}    (${_fmtRate(_rateTxAll)} /s)');
    buf.writeln();

    // Deferred Queue
    final hwPerFrame = _deferredCalls > 0
        ? (_hwProcessed / _deferredCalls).toStringAsFixed(1)
        : '0.0';
    final overrunPct = _deferredCalls > 0
        ? (_hwDeferred / _deferredCalls * 100).toStringAsFixed(2)
        : '0.00';
    buf.writeln(' Deferred Queue');
    buf.writeln(' $thinLine');
    buf.writeln('  Vsync frames:${_fmtCount(_deferredCalls, 10)}    (${_fmtRate(_rateDeferredCalls)} /s)');
    buf.writeln('  HW writes:   ${_fmtCount(_hwProcessed, 10)}    (${_fmtRate(_rateHwProcessed)} /s)   avg $hwPerFrame/frame');
    buf.writeln('  Vsync overruns:${_fmtCount(_hwDeferred, 8)}    (${_fmtRate(_rateHwDeferred)} /s)   $overrunPct%');
    buf.writeln('  Pending HW:  ${_fmtCount(_pendingHw, 10)}');
    buf.writeln('  Pending responses:${_fmtCount(_pendingResp, 4)}');
    buf.writeln();

    // Response Relay
    final dropPct = _respQueued > 0
        ? (_respDropped / _respQueued * 100).toStringAsFixed(2)
        : '0.00';
    buf.writeln(' Response Relay');
    buf.writeln(' $thinLine');
    buf.writeln('  Queued:       ${_fmtCount(_respQueued, 10)}    Sent: ${_fmtCount(_respSent, 6)}    Dropped: $_respDropped ($dropPct%)');
    buf.writeln();

    // MDIN Workload
    buf.writeln(' MDIN Workload');
    buf.writeln(' $thinLine');
    for (int ch = 0; ch < 2; ch++) {
      final w = _workload[ch];
      final label = _channelLabel(ch).padRight(8);
      final total = w[4]; // total workload
      final limit = w[5]; // workload limit
      final transMode = _transModeName(w[7]).padRight(9);
      final bar = _workloadBar(total, limit);
      buf.writeln('  CH$ch ($label):  $transMode  pclk=${w[0].toString().padLeft(5)}/${w[1].toString().padLeft(5)}  work=$total/$limit  $bar');
    }
    buf.writeln();

    // Memory & Scheduling
    buf.writeln(' Memory & Scheduling');
    buf.writeln(' $thinLine');
    buf.writeln('  IMAP: $_imapId    Framebuf mode: ${_framebuf[0]}    Screen off: ${_screenOffStr(_screenOffMask)}');
    buf.writeln('  CH0: imem=${_imemRmem[0][0].toString().padLeft(2)} rmem=${_imemRmem[0][1].toString().padLeft(2)}  delay=$_frameDelayCh0    CH2: imem=${_imemRmem[2][0].toString().padLeft(2)} rmem=${_imemRmem[2][1].toString().padLeft(2)}  delay=0');
    buf.writeln('  CH1: imem=${_imemRmem[1][0].toString().padLeft(2)} rmem=${_imemRmem[1][1].toString().padLeft(2)}  delay=$_frameDelayCh1    CH3: imem=${_imemRmem[3][0].toString().padLeft(2)} rmem=${_imemRmem[3][1].toString().padLeft(2)}  delay=0');

    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: SelectableText(
          _buildDisplay(),
          style: const TextStyle(
            fontFamily: 'Courier',
            fontFamilyFallback: ['Courier New', 'monospace'],
            fontSize: 13,
            color: Color(0xFF00FF00),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
