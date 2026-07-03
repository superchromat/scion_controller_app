// Files page — asset file manager.
//
// Lists the device's stored assets as files: font faces (SCTF blob), sprites
// (SPRT catalog), per-card snapshots (path-keyed 4 KB slots) and named
// full-system configs (256 KB slots). Sortable by name / type / size, with a
// per-region usage bar, rename / delete / download / upload, config
// save / load.
//
// Rename + delete for fonts and sprites are CLIENT-side blob rebuilds (both
// stores are client-managed, same as upload). Snapshots and configs use the
// /assets/{snapshots,configs}/* endpoints. Downloads read raw bytes over the
// /assets/fonts/nor/read transport; sprites are reconstructed to PNG.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'asset_store.dart';
import 'asset_upload_ui.dart';
import 'grid.dart';
import 'labeled_card.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'panel.dart';

// Preset slots: 24 x 16 KB small @ +0xC80000, 12 x 256 KB large @ +0xCE0000.
// Header: "PRST" + u32 len + name[32] + path[64] = 104 B.
const _prstSmallOff = 0xC80000;
const _prstSmallSize = 0x4000;
const _prstNSmall = 24;
const _prstLargeOff = 0xCE0000;
const _prstLargeSize = 0x40000;
const _prstHdrSize = 104;

int _prstSlotOff(int i) => i < _prstNSmall
    ? _prstSmallOff + i * _prstSmallSize
    : _prstLargeOff + (i - _prstNSmall) * _prstLargeSize;
int _prstSlotSize(int i) => i < _prstNSmall ? _prstSmallSize : _prstLargeSize;

enum AssetType { font, sprite, preset }

extension on AssetType {
  String get label => switch (this) {
        AssetType.font => 'Font',
        AssetType.sprite => 'Sprite',
        AssetType.preset => 'Preset',
      };
  IconData get icon => switch (this) {
        AssetType.font => Icons.text_fields,
        AssetType.sprite => Icons.image_outlined,
        AssetType.preset => Icons.bookmark_outline,
      };
}

class AssetFile {
  final AssetType type;
  final String name;
  final int size;
  final int index; // font/sprite index, snapshot/config raw slot
  final String detail; // variant, WxH, subtree path...
  const AssetFile(this.type, this.name, this.size, this.index, this.detail);
}

class RegionUsage {
  final String name;
  final int used, capacity;
  const RegionUsage(this.name, this.used, this.capacity);
}

class AssetFilesPage extends StatefulWidget {
  const AssetFilesPage({super.key, this.isActive = true});
  final bool isActive;

  @override
  State<AssetFilesPage> createState() => _AssetFilesPageState();
}

class _AssetFilesPageState extends State<AssetFilesPage> {
  List<AssetFile> _files = [];
  List<RegionUsage> _usage = [];
  bool _loading = false;
  String? _error;
  int _sortCol = 0; // 0 name, 1 type, 2 size
  bool _sortAsc = true;
  bool _loadedOnce = false;

  NorClient get _nor => NorClient(context.read<Network>());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedOnce && widget.isActive) {
      _loadedOnce = true;
      _refresh();
    }
  }

  @override
  void didUpdateWidget(AssetFilesPage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) _refresh();
  }

  // ---------------------------------------------------------- loading ----

  /// Send one query and collect every reply on the path until [quiet] passes
  /// with no new messages (usage sends four replies to one query).
  Future<List<List<Object?>>> _collect(String addr,
      {Duration quiet = const Duration(milliseconds: 700)}) async {
    final net = context.read<Network>();
    final got = <List<Object?>>[];
    var last = DateTime.now();
    void listener(List<Object?> a) {
      got.add(a);
      last = DateTime.now();
    }

    OscRegistry().registerAddress(addr);
    OscRegistry().registerListener(addr, listener);
    try {
      net.sendOscMessage(addr, const []);
      while (DateTime.now().difference(last) < quiet) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      OscRegistry().unregisterListener(addr, listener);
    }
    return got;
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final nor = _nor;
      final files = <AssetFile>[];

      // usage (one query, four replies)
      final usage = <RegionUsage>[
        for (final u in await _collect('/assets/usage'))
          if (u.length >= 3)
            RegionUsage(u[0] as String, u[1] as int, u[2] as int),
      ];

      // fonts
      final fc = await nor.call('/assets/fonts/count', const []);
      final nFonts = (fc.isNotEmpty ? fc[0] as int : 0);
      for (var i = 0; i < nFonts; i++) {
        final e = await nor.call('/assets/fonts/entry', [i]);
        if (e.length >= 5 && (e[1] as String).isNotEmpty) {
          files.add(AssetFile(AssetType.font, e[1] as String, e[4] as int, i,
              e[2] as String));
        }
      }

      // sprites (catalog only — no pixel reads)
      final store = SpriteStore(nor);
      final cat = await store.catalog();
      for (var i = 0; i < cat.length; i++) {
        final (name, w, h, len) = cat[i];
        files.add(AssetFile(AssetType.sprite, name, len, i, '$w x $h'));
      }

      // presets — info: (ord, slot, name, path, len)
      final pc = await nor.call('/assets/presets/count', const []);
      final nPresets = (pc.isNotEmpty ? pc[0] as int : 0);
      for (var i = 0; i < nPresets; i++) {
        final e = await nor.call('/assets/presets/info', [i]);
        if (e.length >= 5 && (e[1] as int) >= 0) {
          final path = e[3] as String;
          files.add(AssetFile(AssetType.preset, e[2] as String, e[4] as int,
              e[1] as int, path == '/' ? 'full system' : path));
        }
      }

      setState(() {
        _files = files;
        _usage = usage;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ----------------------------------------------------------- actions ----

  Future<String?> _nameDialog(String title, {String initial = ''}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 31,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<bool> _confirm(String what) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(what),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK')),
        ],
      ),
    );
    return r ?? false;
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 3)));
  }

  Future<void> _rename(AssetFile f) async {
    switch (f.type) {
      case AssetType.font:
        final fam = await _nameDialog('Rename font family', initial: f.name);
        if (fam == null || fam.isEmpty) return;
        final store = FontStore(_nor);
        final blob = await store.fetchBlob();
        if (blob == null) return _toast('font store unreadable');
        await store.push(store.renameFont(blob, f.index, fam, f.detail));
        break;
      case AssetType.sprite:
        final name = await _nameDialog('Rename sprite', initial: f.name);
        if (name == null || name.isEmpty) return;
        final store = SpriteStore(_nor);
        final sprites = await store.fetch();
        if (f.index >= sprites.length) return;
        final s = sprites[f.index];
        sprites[f.index] = SpriteAsset(name, s.w, s.h, s.palette, s.pixels);
        await store.push(sprites);
        break;
      case AssetType.preset:
        final name = await _nameDialog('Rename preset', initial: f.name);
        if (name == null || name.isEmpty || name == f.name) return;
        final r = await _nor.call('/assets/presets/rename', [f.name, name],
            timeout: const Duration(seconds: 20));
        if (r.length >= 3 && (r[2] as int) != 0) {
          return _toast('rename failed (${r[2]})');
        }
    }
    _refresh();
  }

  Future<void> _delete(AssetFile f) async {
    if (!await _confirm('Delete ${f.type.label.toLowerCase()} "${f.name}"?')) {
      return;
    }
    switch (f.type) {
      case AssetType.font:
        final store = FontStore(_nor);
        final blob = await store.fetchBlob();
        if (blob == null) return _toast('font store unreadable');
        await store.push(store.removeFont(blob, f.index));
      case AssetType.sprite:
        if (!mounted) return;
        await deleteSpriteFlow(context, f.index);
      case AssetType.preset:
        await _nor.call('/assets/presets/delete', [f.name],
            timeout: const Duration(seconds: 20));
    }
    _refresh();
  }

  Future<void> _download(AssetFile f) async {
    final nor = _nor;
    Uint8List bytes;
    String suggested;
    switch (f.type) {
      case AssetType.font:
        final e = await nor.call('/assets/fonts/entry', [f.index]);
        final off = e[3] as int, len = e[4] as int;
        bytes = await nor.read(off, len);
        suggested = '${f.name}-${f.detail}.ttf'.replaceAll(' ', '');
      case AssetType.sprite:
        final store = SpriteStore(nor);
        final sprites = await store.fetch();
        if (f.index >= sprites.length) return;
        bytes = _spriteToPng(sprites[f.index]);
        suggested = '${f.name}.png';
      case AssetType.preset:
        bytes =
            await nor.read(_prstSlotOff(f.index), _prstHdrSize + f.size);
        suggested = '${f.name}.spre';
    }
    final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${f.type.label.toLowerCase()}',
        fileName: suggested);
    if (path == null) return;
    await File(path).writeAsBytes(bytes);
    _toast('saved $path (${bytes.length} bytes)');
  }

  /// Decode a 4bpp + [Cr, alpha, Cb, Y] palette sprite back to PNG.
  Uint8List _spriteToPng(SpriteAsset s) {
    final out = img.Image(width: s.w, height: s.h, numChannels: 4);
    final bpr = (s.w + 1) ~/ 2;
    for (var y = 0; y < s.h; y++) {
      for (var x = 0; x < s.w; x++) {
        final b = s.pixels[y * bpr + x ~/ 2];
        final pi = (x & 1) == 0 ? (b >> 4) & 0xF : b & 0xF;
        final cr = s.palette[pi * 4 + 0].toDouble();
        final a = s.palette[pi * 4 + 1];
        final cb = s.palette[pi * 4 + 2].toDouble();
        final yy = s.palette[pi * 4 + 3].toDouble();
        // Inverse of the BT.709 limited-range forward transform.
        final yl = (yy - 16) / 219 * 255;
        final pb = (cb - 128) / 224 * 255;
        final pr = (cr - 128) / 224 * 255;
        final r = (yl + 1.5748 * pr).round().clamp(0, 255);
        final g = (yl - 0.1873 * pb - 0.4681 * pr).round().clamp(0, 255);
        final bl = (yl + 1.8556 * pb).round().clamp(0, 255);
        out.setPixelRgba(x, y, r, g, bl, pi == 0 ? 0 : (a * 255 ~/ 15));
      }
    }
    return Uint8List.fromList(img.encodePng(out));
  }

  Future<void> _saveSystemPreset() async {
    final name = await _nameDialog('Save full-system preset as');
    if (name == null || name.isEmpty) return;
    final r = await _nor.call('/assets/presets/save', ['/', name],
        timeout: const Duration(seconds: 60));
    if (r.length >= 3) {
      final n = r[2] as int;
      _toast(n >= 0 ? 'saved "$name" ($n bytes)' : 'save failed ($n)');
    }
    _refresh();
  }

  Future<void> _loadPreset(AssetFile f) async {
    final whole = f.detail == 'full system';
    if (whole &&
        !await _confirm(
            'Load "${f.name}"?\nThis overwrites the ENTIRE device state.')) {
      return;
    }
    final r = await _nor.call('/assets/presets/load', [f.name],
        timeout: const Duration(seconds: 60));
    if (r.length >= 2) {
      final n = r[1] as int;
      _toast(n >= 0 ? 'loaded "${f.name}" ($n messages)' : 'load failed ($n)');
    }
  }

  Future<void> _uploadPreset() async {
    final pick = await FilePicker.platform.pickFiles(
        dialogTitle: 'Upload preset (.spre)', withData: true);
    final data = pick?.files.single.bytes;
    if (data == null || data.length < _prstHdrSize) return;
    if (String.fromCharCodes(data.sublist(0, 4)) != 'PRST') {
      return _toast('not a .spre file');
    }
    final name = String.fromCharCodes(
        data.sublist(8, 40).takeWhile((c) => c != 0));
    // Pick a slot: same-name slot, else first free of the right size class.
    final nor = _nor;
    final needsLarge = data.length > _prstSmallSize;
    var slot = -1, free = -1;
    for (var i = 0; i < _prstNSmall + 12; i++) {
      if (needsLarge && i < _prstNSmall) continue;
      final h = await nor.read(_prstSlotOff(i), 40);
      final used = String.fromCharCodes(h.sublist(0, 4)) == 'PRST';
      if (used &&
          String.fromCharCodes(h.sublist(8, 40).takeWhile((c) => c != 0)) ==
              name) {
        slot = i;
        break;
      }
      if (!used && free < 0) free = i;
    }
    if (slot < 0) slot = free;
    if (slot < 0) return _toast('no free preset slot');
    if (!await _confirm('Upload preset "$name"?')) return;
    await nor.call('/assets/fonts/nor/erase',
        [_prstSlotSize(slot), _prstSlotOff(slot)]);
    await nor.writeBlob(_prstSlotOff(slot), Uint8List.fromList(data));
    _toast('uploaded "$name"');
    _refresh();
  }

  // ---------------------------------------------------------------- UI ----

  List<AssetFile> get _sorted {
    final l = [..._files];
    l.sort((a, b) {
      final r = switch (_sortCol) {
        0 => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        1 => a.type.index.compareTo(b.type.index),
        _ => a.size.compareTo(b.size),
      };
      final tie = r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return _sortAsc ? tie : -tie;
    });
    return l;
  }

  static String _fmtSize(int b) {
    if (b >= 1024 * 1024) return '${(b / 1048576).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '$b B';
  }

  Widget _usageBars(BuildContext context) {
    final t = GridProvider.of(context);
    final scheme = Theme.of(context).colorScheme;
    const colors = {
      'fonts': Color(0xFFC9B066),
      'sprites': Color(0xFF83A6C9),
      'presets': Color(0xFF7FBF7F),
    };
    // One stacked bar across the whole assets partition (16 MB): a segment
    // per type's USED bytes, remainder = free.
    const total = 16 * 1024 * 1024;
    final used = {for (final u in _usage) u.name: u.used};
    final segs = <(String, int, Color)>[
      for (final e in colors.entries)
        if ((used[e.key] ?? 0) > 0) (e.key, used[e.key]!, e.value),
    ];
    final sumUsed = segs.fold(0, (a, s) => a + s.$2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 22,
            child: Row(children: [
              for (final (_, sz, col) in segs)
                Flexible(
                  flex: (sz * 1000 / total).ceil().clamp(1, 1000000),
                  child: Container(color: col),
                ),
              Flexible(
                flex: (((total - sumUsed) * 1000) / total).round(),
                child: Container(color: scheme.surfaceContainerHighest),
              ),
            ]),
          ),
        ),
        SizedBox(height: t.sm),
        Wrap(
          spacing: t.md,
          runSpacing: t.xs,
          children: [
            for (final (name, sz, col) in segs)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, color: col),
                SizedBox(width: t.xs),
                Text('$name ${_fmtSize(sz)}', style: t.textLabel),
              ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 10,
                  height: 10,
                  color: scheme.surfaceContainerHighest),
              SizedBox(width: t.xs),
              Text('free ${_fmtSize(total - sumUsed)}', style: t.textLabel),
            ]),
          ],
        ),
      ],
    );
  }

  DataColumn _col(String label, int i) => DataColumn(
        label: Text(label),
        onSort: (_, __) => setState(() {
          if (_sortCol == i) {
            _sortAsc = !_sortAsc;
          } else {
            _sortCol = i;
            _sortAsc = true;
          }
        }),
      );

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(t.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledCard(
            title: 'Storage',
            child: Padding(
              padding: EdgeInsets.all(t.sm),
              child: _usageBars(context),
            ),
          ),
          SizedBox(height: t.md),
          LabeledCard(
            title: 'Files',
            action: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Upload font (.ttf)',
                icon: const Icon(Icons.text_fields),
                onPressed: () async {
                  await uploadFontFlow(context);
                  _refresh();
                },
              ),
              IconButton(
                tooltip: 'Upload sprite (.png)',
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onPressed: () async {
                  if (await uploadSpriteFlow(context)) _refresh();
                },
              ),
              IconButton(
                tooltip: 'Upload preset (.spre)',
                icon: const Icon(Icons.upload_file),
                onPressed: _uploadPreset,
              ),
              IconButton(
                tooltip: 'Save full-system preset',
                icon: const Icon(Icons.save_outlined),
                onPressed: _saveSystemPreset,
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                onPressed: _refresh,
              ),
            ]),
            child: _error != null
                ? Padding(
                    padding: EdgeInsets.all(t.md),
                    child: Text('load failed: $_error',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      sortColumnIndex: _sortCol,
                      sortAscending: _sortAsc,
                      columns: [
                        _col('Name', 0),
                        _col('Type', 1),
                        _col('Size', 2),
                        const DataColumn(label: Text('Details')),
                        const DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final f in _sorted)
                          DataRow(cells: [
                            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(f.type.icon, size: 16),
                              SizedBox(width: t.xs),
                              Text(f.name),
                            ])),
                            DataCell(Text(f.type.label)),
                            DataCell(Text(_fmtSize(f.size))),
                            DataCell(Text(f.detail)),
                            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                              if (f.type == AssetType.preset)
                                IconButton(
                                  tooltip: 'Load onto device',
                                  icon: const Icon(Icons.play_arrow, size: 18),
                                  onPressed: () => _loadPreset(f),
                                ),
                              IconButton(
                                tooltip: 'Rename',
                                icon: const Icon(Icons.drive_file_rename_outline,
                                    size: 18),
                                onPressed: () => _rename(f),
                              ),
                              IconButton(
                                tooltip: 'Download',
                                icon: const Icon(Icons.download, size: 18),
                                onPressed: () => _download(f),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () => _delete(f),
                              ),
                            ])),
                          ]),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
