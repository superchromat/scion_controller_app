import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'osc_widget_binding.dart';
import 'font_catalog.dart';
import 'asset_upload_ui.dart';
import 'grid.dart';

/// Typeface / Variant / Size selector for the text overlay, driven by the
/// device font catalog (/fonts/count + /fonts/info). Resolves the ambient
/// `/send/N/text/region/M` path and sends `/font` (the catalog index) and
/// `/size`. Typeface is the primary dropdown with a compact Variant dropdown
/// nested to its right; the Layer (osd) control lives separately in
/// [TextLayerDropdown].
class FontControls extends StatefulWidget {
  const FontControls({super.key});

  @override
  State<FontControls> createState() => _FontControlsState();
}

class _FontControlsState extends State<FontControls> {
  String _base = '';
  int _fontIndex = 0;
  int _size = 64;
  bool _wired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final segs = OscPathSegment.resolvePath(context);
    _base = segs.isEmpty ? '' : '/${segs.join('/')}';
    if (_base.isNotEmpty) {
      OscRegistry().registerAddress('$_base/font');
      OscRegistry().registerListener('$_base/font', _onFont);
      OscRegistry().registerAddress('$_base/size');
      OscRegistry().registerListener('$_base/size', _onSize);
    }
    final net = context.read<Network>();
    if (!FontCatalog.instance.isLoaded) FontCatalog.instance.loadWith(net);
  }

  @override
  void dispose() {
    if (_base.isNotEmpty) {
      OscRegistry().unregisterListener('$_base/font', _onFont);
      OscRegistry().unregisterListener('$_base/size', _onSize);
    }
    super.dispose();
  }

  void _onFont(List<Object?> args) {
    if (args.isNotEmpty && args.first is int && mounted) {
      setState(() => _fontIndex = args.first as int);
    }
  }

  void _onSize(List<Object?> args) {
    if (args.isNotEmpty && args.first is int && mounted) {
      setState(() => _size = args.first as int);
    }
  }

  void _send(String seg, int value) {
    context.read<Network>().sendOscMessage('$_base/$seg', [value]);
    OscRegistry().registerAddress('$_base/$seg');
    OscRegistry().dispatch('$_base/$seg', [value]); // local echo
  }

  int _nearest(List<int> xs, int v) {
    if (xs.isEmpty) return v;
    int best = xs.first;
    for (final x in xs) {
      if ((x - v).abs() < (best - v).abs()) best = x;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return ListenableBuilder(
      listenable: FontCatalog.instance,
      builder: (context, _) {
        final cat = FontCatalog.instance;
        if (cat.entries.isEmpty) {
          return Text(cat.isLoaded ? 'No fonts on device' : 'Loading fonts…',
              style: t.textLabel);
        }
        final cur = cat.entryByIndex(_fontIndex) ?? cat.entries.first;
        final variants = cat.variantsOf(cur.family);
        final sizes = cur.sizes.isNotEmpty ? cur.sizes : const [32, 64, 96];
        final selSize = _nearest(sizes, _size);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Typeface (primary) with the Variant as a little dropdown to its
            // right — one nested font picker rather than two peer dropdowns.
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Expanded(
                    child: fontDropdown<String>(
                        t, cur.family, cat.families, (f) => f, (f) {
                      if (f == null) return;
                      final vs = cat.variantsOf(f);
                      final match = vs.firstWhere(
                          (e) => e.variant == cur.variant,
                          orElse: () => vs.first);
                      _send('font', match.index);
                      setState(() => _fontIndex = match.index);
                    }),
                  ),
                  SizedBox(width: t.sm),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: t.u * 9),
                    child: fontDropdown<int>(
                        t,
                        cur.index,
                        variants.map((e) => e.index).toList(),
                        (i) => cat.entryByIndex(i)?.variant ?? '?', (i) {
                      if (i == null) return;
                      _send('font', i);
                      setState(() => _fontIndex = i);
                    }, expand: false),
                  ),
                ],
              ),
            ),
            SizedBox(width: t.md),
            fontDropdown<int>(t, selSize, sizes, (s) => '$s px', (s) {
              if (s == null) return;
              _send('size', s);
              setState(() => _size = s);
            }, expand: false),
            SizedBox(width: t.xs),
            // Upload a .ttf into the device font store (<=48 KiB, glyf
            // outlines; fontctl.py subsets larger families).
            IconButton(
              icon: Icon(Icons.upload_file, size: 18, color: Colors.grey[400]),
              tooltip: 'Upload font (.ttf)…',
              visualDensity: VisualDensity.compact,
              onPressed: () => uploadFontFlow(context),
            ),
          ],
        );
      },
    );
  }
}

/// A bare (label-less) neumorphic-underlined dropdown matching the text card's
/// font selectors.
Widget fontDropdown<TT>(GridTokens t, TT value, List<TT> items,
    String Function(TT) fmt, ValueChanged<TT?> onCh,
    {bool expand = true}) {
  return DropdownButton<TT>(
    value: value,
    isDense: true,
    isExpanded: expand,
    dropdownColor: const Color(0xFF2A2A2E),
    style: t.textLabel.copyWith(color: Colors.white),
    underline: Container(height: 1, color: const Color(0xFF55555A)),
    items: [
      for (final it in items)
        DropdownMenuItem<TT>(value: it, child: Text(fmt(it))),
    ],
    onChanged: onCh,
  );
}

/// Which OSD block renders the text. "In" = Font OSD (input stage: text is
/// processed WITH the video — scales, rotates, warps like picture content).
/// "Above" = Output OSD (fixed overlay on the final raster). The Window OSD
/// (osd=1) is parked pending MFC-block bring-up. Binds `/osd` under the ambient
/// `/send/N/text/region/M` path.
class TextLayerDropdown extends StatefulWidget {
  const TextLayerDropdown({super.key});

  @override
  State<TextLayerDropdown> createState() => _TextLayerDropdownState();
}

class _TextLayerDropdownState extends State<TextLayerDropdown> {
  String _base = '';
  int _osd = 0;
  bool _wired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final segs = OscPathSegment.resolvePath(context);
    _base = segs.isEmpty ? '' : '/${segs.join('/')}';
    if (_base.isNotEmpty) {
      OscRegistry().registerAddress('$_base/osd');
      OscRegistry().registerListener('$_base/osd', _onOsd);
    }
  }

  @override
  void dispose() {
    if (_base.isNotEmpty) {
      OscRegistry().unregisterListener('$_base/osd', _onOsd);
    }
    super.dispose();
  }

  void _onOsd(List<Object?> args) {
    if (args.isNotEmpty && args.first is int && mounted) {
      setState(() => _osd = (args.first as int).clamp(0, 2));
    }
  }

  void _send(int v) {
    context.read<Network>().sendOscMessage('$_base/osd', [v]);
    OscRegistry().registerAddress('$_base/osd');
    OscRegistry().dispatch('$_base/osd', [v]);
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Layer', style: t.textLabel),
        SizedBox(width: t.sm),
        DropdownButton<int>(
          value: _osd == 1 ? 0 : _osd,
          isDense: true,
          dropdownColor: const Color(0xFF2A2A2E),
          style: t.textLabel.copyWith(color: Colors.white),
          underline: Container(height: 1, color: const Color(0xFF55555A)),
          items: const [
            DropdownMenuItem(value: 2, child: Text('In')),
            DropdownMenuItem(value: 0, child: Text('Above')),
          ],
          onChanged: (v) {
            if (v == null) return;
            _send(v);
            setState(() => _osd = v);
          },
        ),
      ],
    );
  }
}
