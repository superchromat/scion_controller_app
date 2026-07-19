// asset_upload_ui.dart
// Upload / delete flows for device fonts and sprites (asset_store.dart does
// the blob work; this is the file-picker + progress-dialog glue).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'asset_store.dart';
import 'font_catalog.dart';
import 'network.dart';

Future<void> _withProgress(BuildContext context, String title,
    Future<void> Function(void Function(double)) job) async {
  final progress = ValueNotifier<double>(0);
  var failed = '';
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF2A2A2E),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, v, __) => LinearProgressIndicator(value: v),
      ),
    ),
  );
  try {
    await job((v) => progress.value = v);
  } catch (e) {
    failed = '$e';
  }
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(failed.isEmpty ? '$title — done' : '$title failed: $failed'),
      backgroundColor: failed.isEmpty ? Colors.green[800] : Colors.red[800],
    ));
  }
}

// -------------------------------------------------------------- sprites ----

/// Pick an image, convert to a 15-colour 4bpp sprite, and append it to the
/// device sprite store. Returns true if the store changed.
Future<bool> uploadSpriteFlow(BuildContext context) async {
  final pick =
      await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
  final f = pick?.files.firstOrNull;
  if (f == null) return false;
  final bytes = f.bytes ?? await File(f.path!).readAsBytes();
  if (!context.mounted) return false;

  // Decode + scale to the firmware budget in one step.
  var codec = await ui.instantiateImageCodec(bytes);
  var img = (await codec.getNextFrame()).image;
  final (tw, th) = fitSpriteSize(img.width, img.height);
  if (tw != img.width) {
    codec = await ui.instantiateImageCodec(bytes,
        targetWidth: tw, targetHeight: th);
    img = (await codec.getNextFrame()).image;
  }
  final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();

  final name = (f.name.split('.').first).replaceAll(RegExp(r'[^\w -]'), '');
  final sprite = convertSprite(
      name.substring(0, name.length.clamp(0, 16)), img.width, img.height, rgba);

  if (!context.mounted) return false;
  final net = context.read<Network>();
  var ok = false;
  await _withProgress(context, 'Upload sprite "${sprite.name}"', (p) async {
    final store = SpriteStore(NorClient(net));
    final sprites = await store.fetch();
    sprites.removeWhere((s) => s.name == sprite.name); // replace same-name
    sprites.add(sprite);
    await store.push(sprites, onProgress: p);
    ok = true;
  });
  return ok;
}

/// Delete sprite [index] from the device store. Returns true if changed.
Future<bool> deleteSpriteFlow(BuildContext context, int index) async {
  final net = context.read<Network>();
  var ok = false;
  await _withProgress(context, 'Delete sprite', (p) async {
    final store = SpriteStore(NorClient(net));
    final sprites = await store.fetch();
    if (index < 0 || index >= sprites.length) throw Exception('bad index');
    sprites.removeAt(index);
    await store.push(sprites, onProgress: p);
    ok = true;
  });
  return ok;
}

// ---------------------------------------------------------------- fonts ----

/// Pick a .ttf and append it to the device font collection. The firmware
/// renderer needs TrueType glyf outlines and a <=48 KiB file (the CLI
/// fontctl subsets big families down to size).
Future<void> uploadFontFlow(BuildContext context) async {
  final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['ttf'], withData: true);
  final f = pick?.files.firstOrNull;
  if (f == null) return;
  final ttf = f.bytes ?? await File(f.path!).readAsBytes();
  if (!context.mounted) return;

  String fail(String why) => why;
  String? err;
  if (ttf.length > fwTtfMax) {
    err = fail('font is ${ttf.length ~/ 1024} KiB — the device holds '
        '${fwTtfMax ~/ 1024} KiB per font. Subset it first with '
        'tools/fonts/fontctl.py add (it strips to ASCII).');
  } else if (!ttfHasGlyf(Uint8List.fromList(ttf))) {
    err = fail('font has no TrueType glyf outlines (OTF/CFF?) — convert '
        'to .ttf first (fontctl rejects these too).');
  }
  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Font upload: $err'),
        backgroundColor: Colors.red[800],
        duration: const Duration(seconds: 8)));
    return;
  }

  // Family / variant names.
  final guess = f.name.replaceAll('.ttf', '').split(RegExp(r'[-_]'));
  final famCtl = TextEditingController(text: guess.first);
  final varCtl = TextEditingController(
      text: guess.length > 1 ? guess.sublist(1).join(' ') : 'Regular');
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: const Color(0xFF2A2A2E),
      title: const Text('Font names',
          style: TextStyle(color: Colors.white, fontSize: 14)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: famCtl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Family')),
        TextField(
            controller: varCtl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Variant')),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Upload')),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return;

  final net = context.read<Network>();
  await _withProgress(context, 'Upload font "${famCtl.text}"', (p) async {
    final store = FontStore(NorClient(net));
    final blob = await store.fetchBlob();
    if (blob == null) throw Exception('device font store unreadable');
    final next = store.appendFont(
        blob, famCtl.text, varCtl.text, Uint8List.fromList(ttf));
    await store.push(next, onProgress: p);
  });
  if (context.mounted) FontCatalog.instance.loadWith(net); // re-query catalog
}
