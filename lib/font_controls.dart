import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'osc_widget_binding.dart';
import 'font_catalog.dart';
import 'grid.dart';

/// Typeface / Variant / Size dropdowns for the text overlay, driven by the
/// device font catalog (/fonts/count + /fonts/info). Resolves the ambient
/// `/send/N/text` path and sends `/font` (the catalog index) and `/size`.
class FontControls extends StatefulWidget {
  const FontControls({super.key});

  @override
  State<FontControls> createState() => _FontControlsState();
}

class _FontControlsState extends State<FontControls> {
  String _base = '';
  int _fontIndex = 0;
  int _size = 64;
  int _osd = 0; // /text/osd: 2=Layer 1 (Font OSD), 1=Layer 2 (Window), 0=Layer 3 (Output)
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
      OscRegistry().registerAddress('$_base/osd');
      OscRegistry().registerListener('$_base/osd', _onOsd);
    }
    // Kick off (or refresh) the catalog fetch.
    final net = context.read<Network>();
    if (!FontCatalog.instance.isLoaded) FontCatalog.instance.loadWith(net);
  }

  @override
  void dispose() {
    if (_base.isNotEmpty) {
      OscRegistry().unregisterListener('$_base/font', _onFont);
      OscRegistry().unregisterListener('$_base/size', _onSize);
      OscRegistry().unregisterListener('$_base/osd', _onOsd);
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

  void _onOsd(List<Object?> args) {
    if (args.isNotEmpty && args.first is int && mounted) {
      setState(() => _osd = (args.first as int).clamp(0, 2));
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

        Widget dd<TT>(String label, TT value, List<TT> items,
            String Function(TT) fmt, ValueChanged<TT?> onCh) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: t.textLabel),
              SizedBox(height: t.xs),
              DropdownButton<TT>(
                value: value,
                isDense: true,
                isExpanded: true,
                dropdownColor: const Color(0xFF2A2A2E),
                style: t.textLabel.copyWith(color: Colors.white),
                underline: Container(height: 1, color: const Color(0xFF55555A)),
                items: [
                  for (final it in items)
                    DropdownMenuItem<TT>(value: it, child: Text(fmt(it))),
                ],
                onChanged: onCh,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: dd<String>('Typeface', cur.family, cat.families, (f) => f,
                  (f) {
                if (f == null) return;
                final vs = cat.variantsOf(f);
                // keep the same variant name if the new family has it, else first
                final match = vs.firstWhere((e) => e.variant == cur.variant,
                    orElse: () => vs.first);
                _send('font', match.index);
                setState(() => _fontIndex = match.index);
              }),
            ),
            SizedBox(width: t.sm),
            Expanded(
              flex: 3,
              child: dd<int>('Variant', cur.index,
                  variants.map((e) => e.index).toList(),
                  (i) => cat.entryByIndex(i)?.variant ?? '?', (i) {
                if (i == null) return;
                _send('font', i);
                setState(() => _fontIndex = i);
              }),
            ),
            SizedBox(width: t.sm),
            Expanded(
              flex: 2,
              child: dd<int>('Size', selSize, sizes, (s) => '$s px', (s) {
                if (s == null) return;
                _send('size', s);
                setState(() => _size = s);
              }),
            ),
            SizedBox(width: t.sm),
            Expanded(
              flex: 2,
              // Which OSD block renders the text. Layer 1 = Font OSD (input
              // stage: text is processed with the video), Layer 2 = Window
              // OSD, Layer 3 = Output OSD (final stage).
              child: dd<int>(
                  'Layer',
                  _osd,
                  const [2, 1, 0],
                  (v) => const {2: 'Layer 1', 1: 'Layer 2', 0: 'Layer 3'}[v]!,
                  (v) {
                if (v == null) return;
                _send('osd', v);
                setState(() => _osd = v);
              }),
            ),
          ],
        );
      },
    );
  }
}
