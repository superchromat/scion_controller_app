// color_lut_actions.dart — Import / Export .cube buttons for the Color card.
//
// Export: queries the device's live colour state (picture knobs, 1D LUT
// control points, grade zones), composes them into a 33^3 .cube (lut_io.dart
// ports the exact firmware maths) and saves it — Resolve-ready.
//
// Import: parses a .cube, resamples to the hardware 17^3 grid, uploads to
// the NOR LUT slot and applies. While an imported LUT is active it owns the
// grade 3D LUT (the firmware gates the grade engine); the wheels still move
// but have no effect until the LUT is cleared here.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'asset_store.dart';
import 'lut_io.dart';
import 'network.dart';

const _lut3dNorOff = 0xFE0000;

class ColorLutActions extends StatefulWidget {
  const ColorLutActions({super.key, this.sendIndex = 1});
  final int sendIndex; // 1-based; LUT import is Send-1-only hardware

  @override
  State<ColorLutActions> createState() => _ColorLutActionsState();
}

class _ColorLutActionsState extends State<ColorLutActions> {
  String? _activeLut; // name of the imported LUT, null if none

  NorClient get _nor => NorClient(context.read<Network>());
  String get _base => '/send/${widget.sendIndex}/color';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pollStatus());
  }

  Future<void> _pollStatus() async {
    if (widget.sendIndex != 1) return;
    try {
      final r = await _nor.call('$_base/lut3d/status', const []);
      if (mounted && r.length >= 2) {
        setState(
            () => _activeLut = (r[0] as int) != 0 ? (r[1] as String) : null);
      }
    } catch (_) {}
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), duration: const Duration(seconds: 3)));
  }

  // ------------------------------------------------------------- export ----

  Future<double> _qf(String addr) async {
    final r = await _nor.call(addr, const []);
    return (r.isNotEmpty && r[0] is num) ? (r[0] as num).toDouble() : 0.5;
  }

  Future<Lut1D> _qlut(String ch) async {
    final r = await _nor.call('$_base/lut/$ch', const []);
    final pts = <(double, double)>[];
    for (var i = 0; i + 1 < r.length; i += 2) {
      pts.add(((r[i] as num).toDouble(), (r[i + 1] as num).toDouble()));
    }
    return Lut1D.fromPoints(pts);
  }

  Future<GradeZone> _qzone(String z) async {
    Future<double> p(String f) => _qf('$_base/grade/$z/$f');
    return GradeZone(
        await p('shift_x'),
        await p('shift_y'),
        await p('lift'),
        await p('contrast'),
        await p('saturation'),
        await p('level'),
        await p('blend'));
  }

  Future<void> _export() async {
    _toast('reading colour state…');
    try {
      final knobs = PictureKnobs(
        await _qf('$_base/brightness'),
        await _qf('$_base/contrast'),
        await _qf('$_base/saturation'),
        await _qf('$_base/hue'),
      );
      final lutR = await _qlut('R');
      final lutG = await _qlut('G');
      final lutB = await _qlut('B');
      final grade = widget.sendIndex == 1
          ? [
              await _qzone('shadows'),
              await _qzone('midtones'),
              await _qzone('highlights')
            ]
          : const [
              GradeZone(0, 0, 0, 0.5, 0.5, 0.25, 0.1),
              GradeZone(0, 0, 0, 0.5, 0.5, 0.75, 0.1),
              GradeZone(0, 0, 0, 0.5, 0.5, 1.0, 0.1),
            ];
      final cube = composeColorCube(
          knobs: knobs,
          lutR: lutR,
          lutG: lutG,
          lutB: lutB,
          grade: grade,
          title: 'SCION send ${widget.sendIndex} color page');
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Export color page as .cube',
          fileName: 'scion-send${widget.sendIndex}.cube');
      if (path == null) return;
      await File(path).writeAsString(cube.format());
      _toast('exported $path');
    } catch (e) {
      _toast('export failed: $e');
    }
  }

  // ------------------------------------------------------------- import ----

  Future<void> _import() async {
    final pick = await FilePicker.platform
        .pickFiles(dialogTitle: 'Import 3D LUT (.cube)', withData: true);
    final data = pick?.files.single.bytes;
    if (data == null) return;
    try {
      final cube = CubeLut.parse(String.fromCharCodes(data));
      final name = pick!.files.single.name.replaceAll('.cube', '');
      final blob = packLut3dBlob(cube, name);
      _toast('uploading "${name}" (${cube.n}^3 → 17^3)…');
      final nor = _nor;
      await nor.call('/assets/fonts/nor/erase', [blob.length, _lut3dNorOff],
          timeout: const Duration(seconds: 20));
      await nor.writeBlob(_lut3dNorOff, blob);
      await nor.call('$_base/lut3d/apply', const [],
          timeout: const Duration(seconds: 20));
      _toast('LUT "$name" active — grade wheels are bypassed');
      _pollStatus();
    } catch (e) {
      _toast('import failed: $e');
    }
  }

  Future<void> _clear() async {
    context.read<Network>().sendOscMessage('$_base/lut3d/enable', [0]);
    _toast('imported LUT cleared — grade wheels re-engaged');
    setState(() => _activeLut = null);
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (_activeLut != null)
        Tooltip(
          message: 'Imported LUT "$_activeLut" active — tap to clear',
          child: InkWell(
            onTap: _clear,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.grain, size: 15, color: Color(0xFFC9B066)),
                const SizedBox(width: 3),
                Text(_activeLut!,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFC9B066))),
              ]),
            ),
          ),
        ),
      IconButton(
        tooltip: 'Export color page as .cube',
        icon: const Icon(Icons.ios_share, size: 15),
        color: Colors.grey[500],
        visualDensity: VisualDensity.compact,
        onPressed: _export,
      ),
      if (widget.sendIndex == 1)
        IconButton(
          tooltip: 'Import .cube 3D LUT',
          icon: const Icon(Icons.download_for_offline_outlined, size: 15),
          color: Colors.grey[500],
          visualDensity: VisualDensity.compact,
          onPressed: _import,
        ),
    ]);
  }
}
