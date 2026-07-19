import 'dart:math';

import 'color_wheel_arc.dart';
import 'drag_area.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'color_wheel.dart';
import 'grid.dart';
import 'network.dart';
import 'osc_checkbox.dart';
import 'osc_registry.dart';
import 'osc_rotary_knob.dart';
import 'osc_dropdown.dart';
import 'osc_widget_binding.dart';
import 'panel.dart';

class DacParameters extends StatelessWidget {
  const DacParameters({super.key});

  // Generic knob helper with sensible defaults and integer display support
  Widget _knob(
    BuildContext context, {
    required String label,
    required String segment,
    double min = -32768,
    double max = 32767,
    double initial = 0,
    int precision = 0,
    bool isBipolar = true,
    bool readOnly = false,
  }) {
    final t = GridProvider.maybeOf(context);
    final format = precision == 0 ? '%.0f' : '%.${precision}f';
    return _tip(
      segment,
      OscPathSegment(
        segment: segment,
        child: AbsorbPointer(
          absorbing: readOnly,
          child: OscRotaryKnob(
            label: label,
            minValue: min,
            maxValue: max,
            initialValue: initial,
            defaultValue: initial,
            isBipolar: isBipolar,
            format: format,
            preferInteger: precision == 0,
            size: t?.knobSm ?? 55,
            labelStyle: t?.textLabel,
          ),
        ),
      ),
    );
  }

  // Knob bound to an unsigned N-bit hardware register. Clamps the knob to the
  // register's real range (0..2^bits-1) so the UI can't send out-of-range
  // values. Widths come from the THS8200 register map (ths8200.h).
  Widget _reg(
    BuildContext context, {
    required String label,
    required String segment,
    required int bits,
    bool readOnly = false,
  }) {
    return _knob(
      context,
      label: label,
      segment: segment,
      min: 0,
      max: ((1 << bits) - 1).toDouble(),
      isBipolar: false,
      readOnly: readOnly,
    );
  }

  Widget _toggle(BuildContext context, String label, String segment) {
    final t = GridProvider.maybeOf(context);
    // Reserve two label lines so single- and double-line labels leave the
    // checkbox at the same height — keeps every row of checkboxes aligned
    // across the card.
    final labelStyle =
        (t?.textLabel ?? const TextStyle(fontSize: 11)).copyWith(height: 1.15);
    final labelBoxHeight = (labelStyle.fontSize ?? 12) * 1.15 * 2;
    return _tip(
      segment,
      OscPathSegment(
        segment: segment,
        child: SizedBox(
          width: t?.knobSm ?? 55,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: labelBoxHeight,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(label, style: labelStyle, maxLines: 2),
                ),
              ),
              SizedBox(height: t?.xs ?? 4),
              const OscCheckbox(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dtg2Table(BuildContext context) {
    const modes = [
      'ACTIVE_VIDEO',
      'FULL_NTSP',
      'FULL_BTSP',
      'NTSP_NTSP',
      'BTSP_BTSP',
      'NTSP_BTSP',
      'BTSP_NTSP',
      'ACTIVE_NEQ',
      'NSP_ACTIVE',
      'FULL_NSP',
      'FULL_BSP',
      'FULL_NEQ',
      'NEQ_NEQ',
      'BSP_BSP',
      'BSP_NEQ',
      'NEQ_BSP',
    ];
    final t = GridProvider.maybeOf(context);
    return Table(
      border:
          TableBorder.all(color: Colors.grey[700] ?? Colors.grey, width: 0.5),
      columnWidths: const {
        0: FixedColumnWidth(110),
        1: FixedColumnWidth(220),
      },
      children: List.generate(16, (i) {
        return TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: _tip(
                'dtg2/bp/$i',
                OscPathSegment(
                  segment: 'dtg2/bp/$i',
                  child: OscRotaryKnob(
                    label: 'BP $i',
                    minValue: 0,
                    maxValue: 2047, // dtg2 breakpoint: 11-bit
                    initialValue: 0,
                    format: '%.0f',
                    preferInteger: true,
                    size: t?.knobSm ?? 55,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: _tip(
                'dtg2/linetype/$i',
                OscDropdown<int>(
                  label: 'LineType',
                  pathSegment: 'dtg2/linetype/$i',
                  items: List.generate(16, (j) => j),
                  itemLabels: {
                    for (int j = 0; j < modes.length; j++) j: modes[j]
                  },
                  defaultValue: 0,
                  width: 180,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  // CSM per-channel controls stacked vertically to sit under a colour wheel.
  // Clip Lo/Hi and Shift are 0.0-1.0 (mapped to the 8-bit registers in
  // firmware); Mult is 0.0-1.999 with unity at 1.0. The firmware auto-manages
  // each function's enable bit from the value (non-zero clip/shift, non-unity
  // mult), so there are no manual enable checkboxes here.
  Widget _csmColumn(BuildContext context, {required String valPrefix}) {
    final t = GridProvider.maybeOf(context);
    final gap = t?.xs ?? 4.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _knob(context,
            label: 'Clip Lo',
            segment: 'csm/clip_${valPrefix}_lo',
            min: 0,
            max: 1,
            precision: 2,
            isBipolar: false),
        SizedBox(height: gap),
        _knob(context,
            label: 'Clip Hi',
            segment: 'csm/clip_${valPrefix}_hi',
            min: 0,
            max: 1,
            precision: 2,
            isBipolar: false),
        SizedBox(height: gap),
        _knob(context,
            label: 'Shift',
            segment: 'csm/shift_$valPrefix',
            min: 0,
            max: 1,
            precision: 2,
            isBipolar: false),
        SizedBox(height: gap),
        _knob(context,
            label: 'Mult',
            segment: 'csm/mult_$valPrefix',
            min: 0,
            max: 1.999,
            initial: 1.0,
            precision: 2,
            isBipolar: false),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    return CardColumn(
      children: [
        // Row 1
        GridRow(columns: 4, cells: [
          (
            span: 1,
            child: Panel(
              title: 'System Control',
              child: Wrap(
                spacing: t.sm,
                runSpacing: t.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _toggle(context, 'ARST_FUNC_N', 'system/ctl/arst_func_n'),
                  _toggle(context, 'Chip MS', 'system/ctl/chip_ms'),
                  _toggle(context, 'Chip Pwdn', 'system/ctl/chip_pwdn'),
                  _toggle(context, 'DAC Pwdn', 'system/ctl/dac_pwdn'),
                  _toggle(context, 'DLL Bypass', 'system/ctl/dll_bypass'),
                  _toggle(context, 'DLL Freq Sel', 'system/ctl/dll_freq_sel'),
                  _toggle(context, 'VESA Clk', 'system/ctl/vesa_clk'),
                  _toggle(context, 'VESA Bars', 'system/ctl/vesa_colorbars'),
                ],
              ),
            ),
          ),
          (
            span: 1,
            child: Panel(
              title: 'Test Control',
              child: Wrap(
                spacing: t.sm,
                runSpacing: t.sm,
                children: [
                  _toggle(context, 'DigBypass', 'test/digbypass'),
                  _toggle(context, 'Force Off', 'test/force_off'),
                  _reg(context,
                      label: 'Y Delay', segment: 'test/ydelay', bits: 2),
                  _toggle(context, 'Fast Ramp', 'test/fastramp'),
                  _toggle(context, 'Slow Ramp', 'test/slowramp'),
                ],
              ),
            ),
          ),
          (
            span: 1,
            child: Panel(
              title: 'Data Path',
              child: Wrap(
                spacing: t.sm,
                runSpacing: t.sm,
                children: [
                  _toggle(context, 'CLK656 On', 'datapath/clk656_on'),
                  _toggle(context, 'FS Adjust', 'datapath/fsadj'),
                  _toggle(context, 'IFIR12 Bypass', 'datapath/ifir12_bypass'),
                  _toggle(context, 'IFIR35 Bypass', 'datapath/ifir35_bypass'),
                  _toggle(context, 'Tristate656', 'datapath/tristate656'),
                  // DMAN control is a 3-bit *mode* enum (not independent bit
                  // flags), so a labelled dropdown makes the values meaningful
                  // rather than a bare 0-4 knob.
                  _tip(
                      'datapath/dman_cntl',
                      Padding(
                        padding: EdgeInsets.only(top: t.xs),
                        child: OscDropdown<int>(
                          label: 'DMAN Mode',
                          pathSegment: 'datapath/dman_cntl',
                          items: const [0, 1, 2, 3, 4],
                          itemLabels: const {
                            0: '30b YCbCr/RGB 4:4:4',
                            1: '16b RGB 4:4:4',
                            2: '15b RGB 4:4:4',
                            3: '20b YCbCr 4:2:2',
                            4: '10b YCbCr 4:2:2 (ITU)',
                          },
                          defaultValue: 0,
                          width: 170,
                        ),
                      )),
                ],
              ),
            ),
          ),
          (
            span: 1,
            child: Panel(
              title: 'DAC Control',
              child: Wrap(
                spacing: t.sm,
                runSpacing: t.sm,
                children: [
                  _reg(context, label: 'DAC1', segment: 'dac/dac1', bits: 10),
                  _reg(context, label: 'DAC2', segment: 'dac/dac2', bits: 10),
                  _reg(context, label: 'DAC3', segment: 'dac/dac3', bits: 10),
                  _toggle(context, 'I2C Control', 'dac/i2c_cntl'),
                ],
              ),
            ),
          ),
        ]),

        // Row 2: CSC + CSM as one tall column on the left; DTG1 over DTG2 on
        // the right. GridRow (equalHeight) stretches both cells to match.
        GridRow(columns: 5, cells: [
          (
            span: 2,
            child: Panel(
              title: 'Color Space Conversion',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Three input-primary wheels, each with its CSM channel
                  // (Clip Lo/Hi, Shift, Mult) stacked directly underneath.
                  _CscWheels(below: [
                    _csmColumn(context, valPrefix: 'cr'), // R/Pr  → Cr channel
                    _csmColumn(context, valPrefix: 'gy'), // G/Y   → Y channel
                    _csmColumn(context, valPrefix: 'cb'), // B/Pb  → Cb channel
                  ]),
                  SizedBox(height: t.sm),
                  // CSC output offsets + global CSC/CSM control bits.
                  Wrap(
                    spacing: t.md,
                    runSpacing: t.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _knob(context,
                          label: 'Y Off',
                          segment: 'csc/yoff',
                          precision: 2,
                          min: -128,
                          max: 128),
                      _knob(context,
                          label: 'CbCr Off',
                          segment: 'csc/cboff',
                          precision: 2,
                          min: -128,
                          max: 128),
                      _toggle(context, 'CSC Bypass', 'csc/csc_bypass'),
                      _toggle(context, 'CSC UOF', 'csc/csc_uof'),
                      _toggle(context, 'CSM OF Ctrl', 'csm/csm_of_control'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          (
            span: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(
                  title: 'DTG1',
                  child: Wrap(
                    spacing: t.sm,
                    runSpacing: t.sm,
                    children: [
                      // Mode dropdown first, then the checkboxes, then the knobs.
                      _tip(
                          'dtg1/mode',
                          Padding(
                            padding: EdgeInsets.only(top: t.xs),
                            child: OscDropdown<int>(
                              label: 'Mode',
                              pathSegment: 'dtg1/mode',
                              items: const [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
                              itemLabels: const {
                                0: '1080P (SMPTE 274M)',
                                1: '1080I (SMPTE 274M)',
                                2: '720P (SMPTE 296M)',
                                3: 'Generic HDTV',
                                4: '480I (525 interlaced)',
                                5: '480P (525 progressive)',
                                6: 'VESA master',
                                7: 'VESA slave',
                                8: '576I (625 interlaced)',
                                9: 'Generic SDTV',
                              },
                              defaultValue: 6,
                              width: 175,
                            ),
                          )),
                      _toggle(context, 'DTG1 On', 'dtg1/dtg1_on'),
                      _toggle(context, 'Pass Thru', 'dtg1/pass_thru'),
                      _toggle(context, 'Field Flip', 'dtg1/field_flip'),
                      _reg(context,
                          label: 'Y Blank', segment: 'dtg1/y_blank', bits: 10),
                      _reg(context,
                          label: 'Y Sync Lo',
                          segment: 'dtg1/y_sync_lo',
                          bits: 10),
                      _reg(context,
                          label: 'Y Sync Hi',
                          segment: 'dtg1/y_sync_hi',
                          bits: 10),
                      _reg(context,
                          label: 'CbCr Blank',
                          segment: 'dtg1/cbcr_blank',
                          bits: 10),
                      _reg(context,
                          label: 'CbCr Sync Lo',
                          segment: 'dtg1/cbcr_sync_lo',
                          bits: 10),
                      _reg(context,
                          label: 'CbCr Sync Hi',
                          segment: 'dtg1/cbcr_sync_hi',
                          bits: 10),
                      _reg(context,
                          label: 'Spec A', segment: 'dtg1/spec_a', bits: 8),
                      _reg(context,
                          label: 'Spec B', segment: 'dtg1/spec_b', bits: 8),
                      _reg(context,
                          label: 'Spec C', segment: 'dtg1/spec_c', bits: 8),
                      _reg(context,
                          label: 'Spec D', segment: 'dtg1/spec_d', bits: 9),
                      _reg(context,
                          label: 'Spec D1', segment: 'dtg1/spec_d1', bits: 8),
                      _reg(context,
                          label: 'Spec E', segment: 'dtg1/spec_e', bits: 9),
                      _reg(context,
                          label: 'Spec H', segment: 'dtg1/spec_h', bits: 10),
                      _reg(context,
                          label: 'Spec I', segment: 'dtg1/spec_i', bits: 12),
                      _reg(context,
                          label: 'Spec K', segment: 'dtg1/spec_k', bits: 11),
                      _reg(context,
                          label: 'Spec K1', segment: 'dtg1/spec_k1', bits: 8),
                      _reg(context,
                          label: 'Spec G', segment: 'dtg1/spec_g', bits: 12),
                      _reg(context,
                          label: 'Total Pixels',
                          segment: 'dtg1/total_pixels',
                          bits: 13),
                      _reg(context,
                          label: 'Line Cnt',
                          segment: 'dtg1/line_cnt',
                          bits: 11),
                      _reg(context,
                          label: 'Frame Size',
                          segment: 'dtg1/frame_size',
                          bits: 11),
                      _reg(context,
                          label: 'Field Size',
                          segment: 'dtg1/field_size',
                          bits: 11),
                      _reg(context,
                          label: 'CBar Size',
                          segment: 'dtg1/cbar_size',
                          bits: 8),
                    ],
                  ),
                ),
                SizedBox(height: t.panelGap),
                // DTG2 fills the leftover height so its card bottom lines up
                // with the taller CSC/CSM column (DTG1 + padding + DTG2 == CSC).
                Expanded(
                    child: Panel(
                  title: 'DTG2',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Checkboxes first, then knobs; line-type table behind a button.
                      Wrap(
                        spacing: t.sm,
                        runSpacing: t.sm,
                        children: [
                          _toggle(context, 'IP Fmt', 'dtg2/ctrl/ip_fmt'),
                          _toggle(context, 'FID DE', 'dtg2/ctrl/fid_de'),
                          _toggle(context, 'RGB Mode', 'dtg2/ctrl/rgb_mode'),
                          _toggle(
                              context, 'Emb Timing', 'dtg2/ctrl/emb_timing'),
                          _toggle(context, 'VSOut Pol', 'dtg2/ctrl/vsout_pol'),
                          _toggle(context, 'HSOut Pol', 'dtg2/ctrl/hsout_pol'),
                          _toggle(context, 'FID Pol', 'dtg2/ctrl/fid_pol'),
                          _toggle(context, 'VS Pol', 'dtg2/ctrl/vs_pol'),
                          _toggle(context, 'HS Pol', 'dtg2/ctrl/hs_pol'),
                          _reg(context,
                              label: 'HLength',
                              segment: 'dtg2/hlength',
                              bits: 10),
                          _reg(context,
                              label: 'HDly', segment: 'dtg2/hdly', bits: 13),
                          _reg(context,
                              label: 'VLength1',
                              segment: 'dtg2/vlength1',
                              bits: 10),
                          _reg(context,
                              label: 'VDly1', segment: 'dtg2/vdly1', bits: 11),
                          _reg(context,
                              label: 'VLength2',
                              segment: 'dtg2/vlength2',
                              bits: 10),
                          _reg(context,
                              label: 'VDly2', segment: 'dtg2/vdly2', bits: 11),
                          _reg(context,
                              label: 'HS In Dly',
                              segment: 'dtg2/hs_in_dly',
                              bits: 13),
                          _reg(context,
                              label: 'VS In Dly',
                              segment: 'dtg2/vs_in_dly',
                              bits: 11),
                          _reg(context,
                              label: 'Pixel Cnt',
                              segment: 'dtg2/pixel_cnt',
                              bits: 16,
                              readOnly: true),
                          _reg(context,
                              label: 'Line Cnt',
                              segment: 'dtg2/ctrl/line_cnt',
                              bits: 11,
                              readOnly: true),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _Dtg2LineTypes(builder: _dtg2Table),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ]),
      ],
    );
  }
}

/// DTG2 per-line line-type table, hidden behind a reveal button so it doesn't
/// dominate the DTG2 panel.
class _Dtg2LineTypes extends StatefulWidget {
  final WidgetBuilder builder;
  const _Dtg2LineTypes({required this.builder});

  @override
  State<_Dtg2LineTypes> createState() => _Dtg2LineTypesState();
}

class _Dtg2LineTypesState extends State<_Dtg2LineTypes> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: () => setState(() => _show = !_show),
          icon: Icon(_show ? Icons.expand_less : Icons.expand_more, size: 18),
          label: Text(_show ? 'Hide Line Types' : 'Line Types'),
        ),
        if (_show) ...[
          const SizedBox(height: 8),
          // Built lazily so 16 knobs + dropdowns aren't constructed while hidden.
          widget.builder(context),
        ],
      ],
    );
  }
}

/// Colour-space-conversion matrix as three plain colour wheels — one per source
/// primary. Wheel i edits the CSC row [i->r, i->g, i->b]; identity = pure R/G/B.
/// Dragging the disk sets chromaticity, the outer arc sets intensity. No gamut
/// or invertibility overlays (unlike the System-page analog-format wheels).
class _CscWheels extends StatefulWidget {
  /// Optional widget rendered directly under each wheel (0=R/Pr, 1=G/Y, 2=B/Pb),
  /// used to hang each channel's CSM column beneath its wheel.
  final List<Widget>? below;
  const _CscWheels({this.below});

  @override
  State<_CscWheels> createState() => _CscWheelsState();
}

class _CscWheelsState extends State<_CscWheels> {
  // One RGB triple per source primary (the three CSC-matrix rows).
  final List<List<double>> _prim = [
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
  ];

  // OSC leaf names for each wheel's ->r/->g/->b contributions.
  static const List<List<String>> _segs = [
    ['r2r', 'r2g', 'r2b'],
    ['g2r', 'g2g', 'g2b'],
    ['b2r', 'b2g', 'b2b'],
  ];

  static const double _wheelSize = 96.0;

  String _base = '';
  bool _wired = false;
  int _dragMode = 1; // 1 = wheel (chroma), 2 = arc (intensity)
  final Map<String, void Function(List<Object?>)> _subs = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final segs = OscPathSegment.resolvePath(context);
    _base = segs.isEmpty ? '' : '/${segs.join('/')}';
    if (_base.isEmpty) return;
    final reg = OscRegistry();
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        final addr = '$_base/csc/${_segs[i][j]}';
        final ii = i, jj = j;
        void listener(List<Object?> args) {
          if (!mounted || args.isEmpty || args.first is! num) return;
          final v = (args.first as num).toDouble();
          final nl = List<double>.from(_prim[ii]);
          nl[jj] = v;
          setState(() => _prim[ii] = nl);
        }

        reg.registerAddress(addr);
        reg.registerListener(addr, listener);
        _subs[addr] = listener;
        final seed = reg.allParams[addr]?.currentValue;
        if (seed != null && seed.isNotEmpty && seed.first is num) {
          _prim[i][j] = (seed.first as num).toDouble();
        }
      }
    }
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    _subs.forEach(reg.unregisterListener);
    super.dispose();
  }

  void _send(int i, List<double> rgb) {
    if (_base.isEmpty) return;
    final net = context.read<Network>();
    final reg = OscRegistry();
    for (int j = 0; j < 3; j++) {
      final addr = '$_base/csc/${_segs[i][j]}';
      net.sendOscMessage(addr, [rgb[j]]);
      reg.registerAddress(addr);
      reg.dispatchLocal(addr, [rgb[j]]);
    }
  }

  void _onDrag(Offset pos, int i, {required bool isStart}) {
    const arcW = 6.0, arcGap = 2.0;
    final total = _wheelSize;
    final center = Offset(total / 2, total / 2);
    final off = pos - center;
    final dist = off.distance;
    final outerR = total / 2;
    final innerR = outerR - arcW - arcGap;
    if (isStart) _dragMode = dist > innerR ? 2 : 1;

    final coords = rgbToWheelCoords(_prim[i]); // [a, b, s]
    List<double> rgb;
    if (_dragMode == 2) {
      // Arc → intensity (s), matching the rotary-knob 270° sweep.
      const startAngle = 0.75 * pi;
      const sweepAngle = 1.5 * pi;
      final angle = atan2(off.dy, off.dx);
      var rel = angle - startAngle;
      while (rel < 0) {
        rel += 2 * pi;
      }
      while (rel >= 2 * pi) {
        rel -= 2 * pi;
      }
      if (rel > sweepAngle) {
        rel = rel < (sweepAngle + (2 * pi - sweepAngle) / 2) ? sweepAngle : 0;
      }
      final s = (-2.0 + (rel / sweepAngle) * 4.0).clamp(-2.0, 2.0);
      rgb = wheelCoordsToRgb(coords[0], coords[1], s.toDouble());
    } else {
      // Inner disk → chromaticity (a, b), keeping current intensity.
      final wheelSize = innerR * 2;
      final wheelPos = Offset(
        (off.dx / innerR) * (wheelSize / 2) + wheelSize / 2,
        (off.dy / innerR) * (wheelSize / 2) + wheelSize / 2,
      );
      rgb = wheelPositionToRgb(wheelPos, wheelSize, coords[2]);
    }
    setState(() => _prim[i] = rgb);
    _send(i, rgb);
  }

  // Wheel labels use the analog primary names: R/Pr (Cr input), G/Y (Y input),
  // B/Pb (Cb input).
  static const List<String> _wheelLabels = ['R/Pr', 'G/Y', 'B/Pb'];

  static const List<String> _wheelTips = [
    'R/Pr input primary → output RGB mix (CSC coefficients r2r/r2g/r2b). '
        'Drag the disk for hue/saturation, the outer arc for gain. Identity = pure red.',
    'G/Y input primary → output RGB mix (CSC coefficients g2r/g2g/g2b). '
        'Drag the disk for hue/saturation, the outer arc for gain. Identity = pure green.',
    'B/Pb input primary → output RGB mix (CSC coefficients b2r/b2g/b2b). '
        'Drag the disk for hue/saturation, the outer arc for gain. Identity = pure blue.',
  ];

  Widget _wheel(int i) {
    final rgb = _prim[i];
    final below = widget.below;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Primary name, always white, above the wheel.
        Text(_wheelLabels[i],
            style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Tooltip(
          message: _wheelTips[i],
          waitDuration: const Duration(milliseconds: 400),
          // DragArea so the wheel drag wins over the scrolling page on touch.
          child: DragArea(
            onPointerDown: (p, _) => _onDrag(p, i, isStart: true),
            onDragUpdate: (p, _) => _onDrag(p, i, isStart: false),
            child: CustomPaint(
              size: const Size(_wheelSize, _wheelSize),
              painter: _CscArcPainter(rgb: rgb, index: i),
            ),
          ),
        ),
        if (below != null) ...[
          const SizedBox(height: 8),
          below[i],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // spaceEvenly distributes slack but cannot take it away: at iPad-portrait
    // widths three fixed 96px wheels need more room than the panel has, which
    // overflowed. scaleDown shrinks the group instead. Pointer coordinates stay
    // in the child's own space, so the drag maths below is unaffected.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_wheel(0), _wheel(1), _wheel(2)],
      ),
    );
  }
}

/// Neumorphic wheel + bipolar intensity arc for [_CscWheels]. Reuses
/// [ColorWheelPainter] for the disk/selection dot with overlays disabled.
class _CscArcPainter extends CustomPainter {
  final List<double> rgb;
  final int index;

  static const double arcWidth = 9.0;
  static const double arcGap = 2.0;

  _CscArcPainter({required this.rgb, required this.index});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final arcRadius = outerRadius - arcWidth / 2;
    final slotInnerRadius = outerRadius - arcWidth;
    final wheelRadius = slotInnerRadius - arcGap;
    final sliderValue = rgbToWheelCoords(rgb)[2];

    // Neumorphic slot + bipolar intensity arc, using the shared treatment
    // (rounded slot ends, groove-wall lip, value-colour glow, rounded fill at
    // the extremes) — matching the rotary knobs and luma slot.
    paintArcSlot(canvas, center, outerRadius, arcRadius, slotInnerRadius);
    const Color activeColor = Color(0xFFF0B830);
    final normalized = (sliderValue + 2.0) / 4.0;
    paintBipolarArc(
        canvas, center, arcRadius, outerRadius, normalized, activeColor);

    // Inner colour disk (no gamut/danger overlays).
    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: wheelRadius)));
    final wheelPainter = ColorWheelPainter(
      rgb,
      const [0.0, 0.0, 0.0],
      const [0.0, 0.0, 0.0],
      index,
      sliderValue: sliderValue,
      isCompact: true,
      showOverlays: false,
    );
    final wheelDiameter = wheelRadius * 2;
    final scale = wheelDiameter / size.width;
    canvas.translate(center.dx - wheelRadius, center.dy - wheelRadius);
    canvas.scale(scale);
    wheelPainter.paint(canvas, Size(size.width, size.height));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CscArcPainter old) =>
      old.rgb[0] != rgb[0] || old.rgb[1] != rgb[1] || old.rgb[2] != rgb[2];
}

/// Wraps [child] in a hover Tooltip if a datasheet description exists for
/// [segment]. Segments with a trailing numeric index (e.g. the 16 DTG2
/// breakpoints 'dtg2/bp/3') fall back to the un-indexed key ('dtg2/bp').
Widget _tip(String segment, Widget child) {
  final m = RegExp(r'^(.*)/\d+$').firstMatch(segment);
  final key = m != null ? m.group(1)! : segment;
  final msg = _dacTooltips[key];
  if (msg == null) return child;
  return Tooltip(
    message: msg,
    waitDuration: const Duration(milliseconds: 400),
    child: child,
  );
}

/// THS8200 datasheet field definitions, keyed by OSC segment, used as control
/// mouseover text. Condensed from docs/ths8200-ep.txt and ths8200-registers.md.
const Map<String, String> _dacTooltips = {
  // System Control
  'system/ctl/arst_func_n':
      'Active-low software reset: 0 holds functional blocks in reset (I2C values kept), 1 is normal; reissue after a video format change to resync the timing generator.',
  'system/ctl/chip_ms':
      'Chip mode select: 0 slave (syncs to incoming video sync signals), 1 master (requests data and generates input timing; only valid in VESA/DTG mode).',
  'system/ctl/chip_pwdn':
      'Chip power down: powers down all digital logic except the I2C interface.',
  'system/ctl/dac_pwdn':
      'DAC power down: puts the DAC channels into power-down while digital logic stays active.',
  'system/ctl/dll_bypass':
      'DLL bypass: uses the CLKIN pin directly as the 2x clock instead of the DLL-generated one. Intended for test purposes only.',
  'system/ctl/dll_freq_sel':
      'Sets the DLL 2x clock frequency range: 0 high range (40-80 MHz pixel clock), 1 low range (10-40 MHz).',
  'system/ctl/vesa_clk':
      'Clock mode: 1 makes all clocks identical and bypasses the DLL for a direct >80 MSPS (e.g. 205 MHz VESA) input; no internal 2x interpolation.',
  'system/ctl/vesa_colorbars':
      'Generates an internal color-bar test pattern (external video inputs ignored); only supported in VESA PC-graphics master mode.',
  // Test Control
  'test/digbypass':
      'Bypasses the digital logic to drive the DACs directly from the input bus.',
  'test/force_off':
      'Bypass for DAC offsets: when set, programmed offsets are always added to DAC codes regardless of mode or dtg_state.',
  'test/ydelay': 'Adjusts the delay of the Y channel during YCbCr modes.',
  'test/fastramp': 'DAC test: outputs a ramp at the 2x clock rate.',
  'test/slowramp':
      'DAC test: outputs a ramp at the 2x clock rate divided by 64,000; takes priority over fastramp.',
  // Data Path
  'datapath/clk656_on':
      'ITU-R BT.656 output clock control: turns the D1CLKO output on or off.',
  'datapath/fsadj':
      'Full-scale adjust select: 0 uses the resistor on FSADJ2, 1 uses the resistor on FSADJ1, setting DAC output full-scale range.',
  'datapath/ifir12_bypass':
      'Bypasses the pre-CSC 4:2:2-to-4:4:4 interpolation filters. Off for 4:2:2 input, on for 4:4:4 input.',
  'datapath/ifir35_bypass':
      'Bypasses the post-CSC 1x-to-2x interpolation filters. Set on when 1x DAC operation is desired.',
  'datapath/tristate656':
      'ITU-R BT.656 output bus: when set, the output bus goes to high-impedance (tri-state).',
  'datapath/dman_cntl':
      'Data manager control: selects input data format (0 30-bit 4:4:4, 1 16-bit RGB, 2 15-bit RGB, 3 20-bit YCbCr 4:2:2, 4 10-bit ITU 4:2:2).',
  // DAC Control
  'dac/dac1':
      'Direct 10-bit input value to the G/Y DAC (used when DAC I2C control is enabled).',
  'dac/dac2':
      'Direct 10-bit input value to the B/Cb DAC (used when DAC I2C control is enabled).',
  'dac/dac3':
      'Direct 10-bit input value to the R/Cr DAC (used when DAC I2C control is enabled).',
  'dac/i2c_cntl':
      'DAC I2C control: when set, DAC inputs are fixed to the dac_cntl register values instead of normal video.',
  // Color Space Conversion (offsets + bypass; the matrix itself is the wheels)
  'csc/r2r':
      'CSC coefficient R input → R output (register csc_ric3, 0x08-09), signed-magnitude 6-bit int + 10-bit frac.',
  'csc/r2g':
      'CSC coefficient R input → G output (register csc_ric1, 0x04-05), signed-magnitude 6-bit int + 10-bit frac.',
  'csc/r2b':
      'CSC coefficient R input → B output (register csc_ric2, 0x06-07), signed-magnitude 6-bit int + 10-bit frac.',
  'csc/g2r':
      'CSC coefficient G input → R output (register csc_gic3, 0x0E-0F), signed-magnitude 6-bit int + 10-bit frac.',
  'csc/g2g':
      'CSC coefficient G input → G output (register csc_gic1, 0x0A-0B), signed-magnitude 6-bit int + 10-bit frac.',
  'csc/g2b':
      'CSC coefficient G input → B output (register csc_gic2, 0x0C-0D), signed-magnitude 6-bit int + 10-bit frac.',
  'csc/b2r':
      'CSC coefficient B input → R output (register csc_bic3, 0x14-15), signed-magnitude 6-bit int + 10-bit frac.',
  'csc/b2g':
      'CSC coefficient B input → G output (register csc_bic1, 0x10-11), signed-magnitude 6-bit int + 10-bit frac.',
  'csc/b2b':
      'CSC coefficient B input → B output (register csc_bic2, 0x12-13), signed-magnitude 6-bit int + 10-bit frac.',
  'csc/yoff':
      'CSC offset for the G/Y (DAC channel 1) output, 10-bit signed-magnitude (0x16-17); program 1/4 of the desired digital offset value.',
  'csc/cboff':
      'CSC offset for the B/Cb (DAC channel 2) output, 10-bit signed-magnitude (0x17-18); program 1/4 of the desired digital offset value.',
  'csc/csc_bypass':
      'Bypasses the color-space converter (0x19 bit 1): 0 = CSC active, 1 = CSC bypassed (default).',
  'csc/csc_uof':
      'CSC under/overflow control (0x19 bit 0): enables saturation logic to avoid over-/underflow on the CSC result.',
  // Clip / Scale / Multiplier
  'csm/clip_gy_lo':
      'G/Y low clip (0.0-1.0 → 8-bit 0x41): code below which the G/Y channel is clipped. Auto-enables the clip when non-zero.',
  'csm/clip_gy_hi':
      'G/Y high clip (0.0-1.0 → 8-bit 0x44): high-end clip on the G/Y channel (level = 1023 - reg). Auto-enables when non-zero.',
  'csm/shift_gy':
      'G/Y downward shift (0.0-1.0 → 8-bit 0x47): codes the G/Y data is shifted down. Auto-enables the shift when non-zero.',
  'csm/mult_gy':
      'G/Y scaling factor 0.0-1.999 (unity 1.0; 11-bit 0x4A/0x4C, code = scale/1.999·2047). Auto-enables the multiplier when ≠ 1.0.',
  'csm/clip_cb_lo':
      'B/Cb low clip (0.0-1.0 → 8-bit 0x42): code below which the B/Cb channel is clipped. Auto-enables the clip when non-zero.',
  'csm/clip_cb_hi':
      'B/Cb high clip (0.0-1.0 → 8-bit 0x45): high-end clip on the B/Cb channel (level = 1023 - reg). Auto-enables when non-zero.',
  'csm/shift_cb':
      'B/Cb downward shift (0.0-1.0 → 8-bit 0x48): codes the B/Cb data is shifted down. Auto-enables the shift when non-zero.',
  'csm/mult_cb':
      'B/Cb scaling factor 0.0-1.999 (unity 1.0; 11-bit 0x4B/0x4D, code = scale/1.999·2047). Auto-enables the multiplier when ≠ 1.0.',
  'csm/clip_cr_lo':
      'R/Cr low clip (0.0-1.0 → 8-bit 0x43): code below which the R/Cr channel is clipped. Auto-enables the clip when non-zero.',
  'csm/clip_cr_hi':
      'R/Cr high clip (0.0-1.0 → 8-bit 0x46): high-end clip on the R/Cr channel (level = 1023 - reg). Auto-enables when non-zero.',
  'csm/shift_cr':
      'R/Cr downward shift (0.0-1.0 → 8-bit 0x49): codes the R/Cr data is shifted down. Auto-enables the shift when non-zero.',
  'csm/mult_cr':
      'R/Cr scaling factor 0.0-1.999 (unity 1.0; 11-bit 0x4B/0x4E, code = scale/1.999·2047). Auto-enables the multiplier when ≠ 1.0.',
  'csm/clip_gy_lo_on':
      'Enables low-end clipping on the G/Y channel (0x4A bit 4).',
  'csm/clip_gy_hi_on':
      'Enables high-end clipping on the G/Y channel (0x4A bit 5).',
  'csm/shift_gy_on':
      'Enables downward shifting of the G/Y channel (0x4A bit 6).',
  'csm/mult_gy_on':
      'Enables scaling (multiplier) on the G/Y channel (0x4A bit 7).',
  'csm/clip_bcb_lo_on':
      'Enables low-end clipping on the B/Cb channel (0x4F bit 0).',
  'csm/clip_bcb_hi_on':
      'Enables high-end clipping on the B/Cb channel (0x4F bit 1).',
  'csm/shift_bcb_on':
      'Enables downward shifting of the B/Cb channel (0x4F bit 4).',
  'csm/mult_bcb_on':
      'Enables scaling (multiplier) on the B/Cb channel (0x4F bit 6).',
  'csm/clip_rcr_lo_on':
      'Enables low-end clipping on the R/Cr channel (0x4F bit 2).',
  'csm/clip_rcr_hi_on':
      'Enables high-end clipping on the R/Cr channel (0x4F bit 3).',
  'csm/shift_rcr_on':
      'Enables downward shifting of the R/Cr channel (0x4F bit 5).',
  'csm/mult_rcr_on':
      'Enables scaling (multiplier) on the R/Cr channel (0x4F bit 7).',
  'csm/csm_of_control':
      'CSM overflow control (0x4A bit 3): enables overflow protection of the CSM multiplier.',
  // DTG1
  'dtg1/y_blank':
      '10-bit Y-channel blanking level amplitude (sets the amplitude of the blanking level for the Y channel).',
  'dtg1/y_sync_lo':
      '10-bit Y-channel low sync level; sets the amplitude of the negative sync and equalization/serration/broad pulses for the Y channel.',
  'dtg1/y_sync_hi':
      '10-bit Y-channel high sync level; sets the amplitude of the positive sync for the Y channel.',
  'dtg1/cbcr_blank':
      '10-bit Cb/Cr channel blanking level amplitude (sets the blanking level for the Cb and Cr channels).',
  'dtg1/cbcr_sync_lo':
      '10-bit Cb/Cr low sync level; sets the amplitude of the negative sync and equalization/serration/broad pulses for Cb and Cr.',
  'dtg1/cbcr_sync_hi':
      '10-bit Cb/Cr high sync level; sets the amplitude of the positive sync for the Cb and Cr channels.',
  'dtg1/dtg1_on':
      'DTG on/off: 0 holds the DTG output at the Y blank value, 1 enables the timing generator.',
  'dtg1/pass_thru':
      'DTG pass-through: 0 blocks video data during certain line types, 1 passes it through (see DTG Line Types).',
  'dtg1/mode':
      '4-bit DTG mode select; picks the output format: 1080P/1080I/720P/generic HDTV, 480I/480P/625I/generic SDTV, or VESA master/slave.',
  'dtg1/spec_a':
      'Negative HSync width: width of the negative excursion of tri-level (HDTV) or bi-level (SDTV) sync.',
  'dtg1/spec_b':
      'End of active video to 0H: distance from end of active video to start of negative sync (SDTV) or to the tri-level neg-to-pos transition (HDTV).',
  'dtg1/spec_c':
      'Positive HSync width (HDTV) / equalization pulse width (SDTV): width of the tri-level positive excursion or of SDTV equalization pulses.',
  'dtg1/spec_d':
      '9-bit sync-to-active: distance from HSync leading edge to start of active video (SDTV) or from tri-level transition to start of broad pulse (HDTV).',
  'dtg1/spec_d1':
      'Center equalization pulse to active video: distance from the equalization pulse at center of line to active video (SDTV mode).',
  'dtg1/spec_e':
      '9-bit sync-to-active (HDTV): distance from tri-level transition to start of active video; in VESA mode sets color-bar start vs. horizontal sync.',
  'dtg1/spec_h':
      '10-bit broad pulse duration: duration of the broad pulse (SDTV mode).',
  'dtg1/spec_i':
      '12-bit full-line broad pulse: duration of the full-line broad pulse (SDTV mode).',
  'dtg1/spec_k':
      '11-bit end-of-active to sync: distance from end of active video to sync leading edge (SDTV) or from end of broad pulse to tri-level transition (HDTV).',
  'dtg1/spec_k1':
      'End of active video in first half of line to center equalization pulse, for SDTV line type ACTIVE_NEQ.',
  'dtg1/spec_g':
      '12-bit half-line length: half the line length; used only in the calculation of SDTV line types.',
  'dtg1/total_pixels':
      '13-bit total number of pixels per line; used in all DTG modes (SDTV/HDTV/VESA).',
  'dtg1/field_flip':
      'FID/F polarity select: chooses whether the DTG initializes to field 1 at the active VS edge on a 0 or a 1 from the FID signal / F bit.',
  'dtg1/line_cnt':
      '11-bit DTG start line number: sets the starting line number for the DTG when Vsync input or V-bit is asserted.',
  'dtg1/frame_size':
      '11-bit generic-mode frame size: number of lines per frame when in generic mode.',
  'dtg1/field_size':
      '11-bit generic-mode field size: number of lines in field 1 in generic mode (program higher than frame_size for progressive formats).',
  'dtg1/cbar_size':
      'Sets the width of each color bar in the color-bar test pattern; only available when the DTG is in VESA mode.',
  // DTG2
  'dtg2/hlength':
      'Duration of the HS_OUT output sync signal (10-bit, in pixels).',
  'dtg2/hdly':
      'Pixel value on which HS_OUT is asserted (13-bit HS_OUT delay); above the pixels-per-line count yields no HS_OUT.',
  'dtg2/vlength1':
      'Duration of VS_OUT during progressive modes or the field-1 vertical blank interval of interlaced modes (10-bit).',
  'dtg2/vdly1':
      'Line number on which VS_OUT is asserted for progressive modes or field 1 of interlaced modes (11-bit); above lines-per-frame yields no VS_OUT.',
  'dtg2/vlength2':
      'Duration of VS_OUT during the field-2 vertical blank interval of interlaced modes (10-bit); set to 0 for progressive modes.',
  'dtg2/vdly2':
      'Line number on which VS_OUT is asserted for field 2 of interlaced modes (11-bit); set to all 1s for progressive modes.',
  'dtg2/hs_in_dly':
      'Pixels that DTG startup is horizontally delayed vs. HS input (dedicated timing) or EAV (embedded timing); 13-bit, may exceed a line.',
  'dtg2/vs_in_dly':
      'Lines that DTG startup is vertically delayed vs. VS input (dedicated timing) or the line-counter value (embedded timing); 11-bit, may exceed a frame.',
  'dtg2/pixel_cnt':
      'Read-only: number of 1x-clock rising edges counted between consecutive Hsync input pulses (16-bit).',
  'dtg2/ctrl/ip_fmt':
      'Read-only indicator of current frame scan format: 0 = progressive, 1 = interlaced.',
  'dtg2/ctrl/line_cnt':
      'Read-only: number of Hsync input pulses between consecutive DTG start signals, i.e. over one frame (11-bit).',
  'dtg2/ctrl/fid_de':
      'Interpretation of the FID pin: 0 = FieldID; 1 = data-enable input in VESA mode, or internal FID from HS/VS alignment in SDTV/HDTV.',
  'dtg2/ctrl/rgb_mode':
      'Output color mode / DAC blanking offset: 0 = YPbPr (Y bottom, Pb/Pr mid-range), 1 = RGB (all channels blank at bottom range).',
  'dtg2/ctrl/emb_timing':
      'Video sync input source: 0 = dedicated HS, VS, FID inputs; 1 = timing embedded in video data via SAV/EAV codes.',
  'dtg2/ctrl/vsout_pol': 'VS_OUT output polarity: 0 = positive, 1 = negative.',
  'dtg2/ctrl/hsout_pol': 'HS_OUT output polarity: 0 = negative, 1 = positive.',
  'dtg2/ctrl/fid_pol': 'FID polarity: 0 = negative, 1 = positive.',
  'dtg2/ctrl/vs_pol': 'VS_IN input polarity: 0 = negative, 1 = positive.',
  'dtg2/ctrl/hs_pol': 'HS_IN input polarity: 0 = negative, 1 = positive.',
  'dtg2/bp':
      'Breakpoint line number (11-bit): the DTG outputs this region\'s line type until the next breakpoint\'s line number is reached.',
  'dtg2/linetype':
      'Selects the line format (4-bit, e.g. ACTIVE_VIDEO, FULL_NTSP, sync codes) that the DTG outputs for this breakpoint region until the next breakpoint.',
};
