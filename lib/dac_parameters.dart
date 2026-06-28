import 'package:flutter/material.dart';

import 'grid.dart';
import 'osc_checkbox.dart';
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
    return OscPathSegment(
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

  Widget _horizontalKnobRow(BuildContext context, List<Widget> knobs) {
    final t = GridProvider.maybeOf(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < knobs.length; i++) ...[
            if (i > 0) SizedBox(width: t?.sm ?? 8),
            knobs[i],
          ],
        ],
      ),
    );
  }

  Widget _toggle(BuildContext context, String label, String segment) {
    final t = GridProvider.maybeOf(context);
    return OscPathSegment(
      segment: segment,
      child: SizedBox(
        width: t?.knobSm ?? 55,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: t?.xs ?? 4),
              child: Text(label, style: t?.textLabel),
            ),
            const OscCheckbox(),
          ],
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
      border: TableBorder.all(color: Colors.grey[700] ?? Colors.grey, width: 0.5),
      columnWidths: const {
        0: FixedColumnWidth(110),
        1: FixedColumnWidth(220),
      },
      children: List.generate(16, (i) {
        return TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: OscPathSegment(
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
            Padding(
              padding: const EdgeInsets.all(4),
              child: OscDropdown<int>(
                label: 'LineType',
                pathSegment: 'dtg2/linetype/$i',
                items: List.generate(16, (j) => j),
                itemLabels: {for (int j = 0; j < modes.length; j++) j: modes[j]},
                defaultValue: 0,
                width: 180,
              ),
            ),
          ],
        );
      }),
    );
  }

  // CSM per-channel controls: value knobs clamped to each register's real range
  // (clip/shift are 8-bit 0..255, mult is 11-bit 0..2047) plus the enable
  // toggles for that channel's clip/shift/mult functions. The enable-bit
  // segment names differ from the value-register prefix (gy/cb/cr vs
  // gy/bcb/rcr), so they are passed explicitly.
  Widget _csmChannel(
    BuildContext context, {
    required String title,
    Widget? leading,
    required String valPrefix, // gy/cb/cr -> clip_<p>_lo/hi, shift_<p>, mult_<p>
    required String multOn,
    required String shiftOn,
    required String clipHiOn,
    required String clipLoOn,
  }) {
    final t = GridProvider.maybeOf(context);
    return Panel(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _horizontalKnobRow(context, [
            if (leading != null) leading,
            _knob(context,
                label: 'Clip Lo',
                segment: 'csm/clip_${valPrefix}_lo',
                min: 0,
                max: 255,
                isBipolar: false),
            _knob(context,
                label: 'Clip Hi',
                segment: 'csm/clip_${valPrefix}_hi',
                min: 0,
                max: 255,
                isBipolar: false),
            _knob(context,
                label: 'Shift',
                segment: 'csm/shift_$valPrefix',
                min: 0,
                max: 255,
                isBipolar: false),
            _knob(context,
                label: 'Mult',
                segment: 'csm/mult_$valPrefix',
                min: 0,
                max: 2047,
                isBipolar: false),
          ]),
          SizedBox(height: t?.xs ?? 4),
          // Per-function enable bits (independent — checkboxes, not radios).
          _horizontalKnobRow(context, [
            _toggle(context, 'Clip Lo', 'csm/$clipLoOn'),
            _toggle(context, 'Clip Hi', 'csm/$clipHiOn'),
            _toggle(context, 'Shift', 'csm/$shiftOn'),
            _toggle(context, 'Mult', 'csm/$multOn'),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    return CardColumn(
      children: [
        // Row 1
        GridRow(columns: 4, gutter: t.md, cells: [
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
                  _reg(context, label: 'Y Delay', segment: 'test/ydelay', bits: 2),
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
                  _reg(context, label: 'DMAN Cntl', segment: 'datapath/dman_cntl', bits: 3),
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

        // Row 2
        GridRow(columns: 2, gutter: t.md, cells: [
          (
            span: 1,
            child: Panel(
              title: 'Color Space Conversion',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Table(
                      defaultColumnWidth: const FixedColumnWidth(90),
                      children: [
                        TableRow(children: [
                          _knob(context, label: 'r2r', segment: 'csc/r2r', min: -4, max: 4, precision: 2),
                          _knob(context, label: 'r2g', segment: 'csc/r2g', min: -4, max: 4, precision: 2),
                          _knob(context, label: 'r2b', segment: 'csc/r2b', min: -4, max: 4, precision: 2),
                        ]),
                        TableRow(children: [
                          _knob(context, label: 'g2r', segment: 'csc/g2r', min: -4, max: 4, precision: 2),
                          _knob(context, label: 'g2g', segment: 'csc/g2g', min: -4, max: 4, precision: 2),
                          _knob(context, label: 'g2b', segment: 'csc/g2b', min: -4, max: 4, precision: 2),
                        ]),
                        TableRow(children: [
                          _knob(context, label: 'b2r', segment: 'csc/b2r', min: -4, max: 4, precision: 2),
                          _knob(context, label: 'b2g', segment: 'csc/b2g', min: -4, max: 4, precision: 2),
                          _knob(context, label: 'b2b', segment: 'csc/b2b', min: -4, max: 4, precision: 2),
                        ]),
                      ],
                    ),
                  ),
                  SizedBox(width: t.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _toggle(context, 'CSC Bypass', 'csc/csc_bypass'),
                      SizedBox(height: t.xs),
                      _toggle(context, 'CSC UOF', 'csc/csc_uof'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          (
            span: 1,
            child: Panel(
              title: 'Clip / Scale / Multiplier',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _csmChannel(context,
                      title: 'Y',
                      leading: _knob(context,
                          label: 'Y Off',
                          segment: 'csc/yoff',
                          precision: 2,
                          min: -128, // Q2.8 signed offset
                          max: 128),
                      valPrefix: 'gy',
                      multOn: 'mult_gy_on',
                      shiftOn: 'shift_gy_on',
                      clipHiOn: 'clip_gy_hi_on',
                      clipLoOn: 'clip_gy_lo_on'),
                  SizedBox(height: t.sm),
                  _csmChannel(context,
                      title: 'Cb',
                      leading: _knob(context,
                          label: 'CbCr Off',
                          segment: 'csc/cboff',
                          precision: 2,
                          min: -128, // Q2.8 signed offset
                          max: 128),
                      valPrefix: 'cb',
                      multOn: 'mult_bcb_on',
                      shiftOn: 'shift_bcb_on',
                      clipHiOn: 'clip_bcb_hi_on',
                      clipLoOn: 'clip_bcb_lo_on'),
                  SizedBox(height: t.sm),
                  _csmChannel(context,
                      title: 'Cr',
                      valPrefix: 'cr',
                      multOn: 'mult_rcr_on',
                      shiftOn: 'shift_rcr_on',
                      clipHiOn: 'clip_rcr_hi_on',
                      clipLoOn: 'clip_rcr_lo_on'),
                  SizedBox(height: t.sm),
                  // Global CSM overflow control (0x4A[3]). Replaces the raw
                  // 'CSM Ctrl' knob, which just exposed the packed Cb/Cr enable
                  // byte (0x4F) now broken out into the per-channel toggles above.
                  Row(children: [
                    _toggle(context, 'CSM OF Control', 'csm/csm_of_control'),
                  ]),
                ],
              ),
            ),
          ),
        ]),

        // Row 3
        GridRow(columns: 2, gutter: t.md, cells: [
          (
            span: 1,
            child: Panel(
              title: 'DTG1',
              child: Wrap(
                spacing: t.sm,
                runSpacing: t.sm,
                children: [
                  _reg(context, label: 'Y Blank', segment: 'dtg1/y_blank', bits: 10),
                  _reg(context, label: 'Y Sync Lo', segment: 'dtg1/y_sync_lo', bits: 10),
                  _reg(context, label: 'Y Sync Hi', segment: 'dtg1/y_sync_hi', bits: 10),
                  _reg(context, label: 'CbCr Blank', segment: 'dtg1/cbcr_blank', bits: 10),
                  _reg(context, label: 'CbCr Sync Lo', segment: 'dtg1/cbcr_sync_lo', bits: 10),
                  _reg(context, label: 'CbCr Sync Hi', segment: 'dtg1/cbcr_sync_hi', bits: 10),
                  _toggle(context, 'DTG1 On', 'dtg1/dtg1_on'),
                  _toggle(context, 'Pass Thru', 'dtg1/pass_thru'),
                  _reg(context, label: 'Mode', segment: 'dtg1/mode', bits: 4),
                  _reg(context, label: 'Spec A', segment: 'dtg1/spec_a', bits: 8),
                  _reg(context, label: 'Spec B', segment: 'dtg1/spec_b', bits: 8),
                  _reg(context, label: 'Spec C', segment: 'dtg1/spec_c', bits: 8),
                  _reg(context, label: 'Spec D', segment: 'dtg1/spec_d', bits: 9),
                  _reg(context, label: 'Spec D1', segment: 'dtg1/spec_d1', bits: 8),
                  _reg(context, label: 'Spec E', segment: 'dtg1/spec_e', bits: 9),
                  _reg(context, label: 'Spec H', segment: 'dtg1/spec_h', bits: 10),
                  _reg(context, label: 'Spec I', segment: 'dtg1/spec_i', bits: 12),
                  _reg(context, label: 'Spec K', segment: 'dtg1/spec_k', bits: 11),
                  _reg(context, label: 'Spec K1', segment: 'dtg1/spec_k1', bits: 8),
                  _reg(context, label: 'Spec G', segment: 'dtg1/spec_g', bits: 12),
                  _reg(context, label: 'Total Pixels', segment: 'dtg1/total_pixels', bits: 13),
                  _toggle(context, 'Field Flip', 'dtg1/field_flip'),
                  _reg(context, label: 'Line Cnt', segment: 'dtg1/line_cnt', bits: 11),
                  _reg(context, label: 'Frame Size', segment: 'dtg1/frame_size', bits: 11),
                  _reg(context, label: 'Field Size', segment: 'dtg1/field_size', bits: 11),
                  _reg(context, label: 'CBar Size', segment: 'dtg1/cbar_size', bits: 8),
                ],
              ),
            ),
          ),
          (
            span: 1,
            child: Panel(
              title: 'DTG2',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dtg2Table(context),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: t.sm,
                    runSpacing: t.sm,
                    children: [
                      _reg(context, label: 'HLength', segment: 'dtg2/hlength', bits: 10),
                      _reg(context, label: 'HDly', segment: 'dtg2/hdly', bits: 13),
                      _reg(context, label: 'VLength1', segment: 'dtg2/vlength1', bits: 10),
                      _reg(context, label: 'VDly1', segment: 'dtg2/vdly1', bits: 11),
                      _reg(context, label: 'VLength2', segment: 'dtg2/vlength2', bits: 10),
                      _reg(context, label: 'VDly2', segment: 'dtg2/vdly2', bits: 11),
                      _reg(context, label: 'HS In Dly', segment: 'dtg2/hs_in_dly', bits: 13),
                      _reg(context, label: 'VS In Dly', segment: 'dtg2/vs_in_dly', bits: 11),
                      _reg(context, label: 'Pixel Cnt', segment: 'dtg2/pixel_cnt', bits: 16, readOnly: true),
                      _toggle(context, 'IP Fmt', 'dtg2/ctrl/ip_fmt'),
                      _reg(context, label: 'Line Cnt', segment: 'dtg2/ctrl/line_cnt', bits: 11, readOnly: true),
                      _toggle(context, 'FID DE', 'dtg2/ctrl/fid_de'),
                      _toggle(context, 'RGB Mode', 'dtg2/ctrl/rgb_mode'),
                      _toggle(context, 'Emb Timing', 'dtg2/ctrl/emb_timing'),
                      _toggle(context, 'VSOut Pol', 'dtg2/ctrl/vsout_pol'),
                      _toggle(context, 'HSOut Pol', 'dtg2/ctrl/hsout_pol'),
                      _toggle(context, 'FID Pol', 'dtg2/ctrl/fid_pol'),
                      _toggle(context, 'VS Pol', 'dtg2/ctrl/vs_pol'),
                      _toggle(context, 'HS Pol', 'dtg2/ctrl/hs_pol'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ]),

        // Row 5
      ],
    );
  }
}
