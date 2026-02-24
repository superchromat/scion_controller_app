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
                  maxValue: 4096,
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

  Widget _csmColumn(
    BuildContext context,
    String label, {
    required String clipLo,
    required String clipHi,
    required String shift,
    required String mult,
  }) {
    final t = GridProvider.maybeOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: t?.xs ?? 4),
          child: Text(label, style: t?.textLabel),
        ),
        _knob(context, label: 'Clip Lo', segment: clipLo),
        _knob(context, label: 'Clip Hi', segment: clipHi),
        _knob(context, label: 'Shift', segment: shift),
        _knob(context, label: 'Mult', segment: mult),
      ],
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
                  _knob(context, label: 'Y Delay', segment: 'test/ydelay', min: -1024, max: 1024),
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
                  _knob(context, label: 'DMAN Cntl', segment: 'datapath/dman_cntl', min: 0, max: 1023, isBipolar: false),
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
                  _knob(context, label: 'DAC1', segment: 'dac/dac1', min: 0, max: 1023, isBipolar: false),
                  _knob(context, label: 'DAC2', segment: 'dac/dac2', min: 0, max: 1023, isBipolar: false),
                  _knob(context, label: 'DAC3', segment: 'dac/dac3', min: 0, max: 1023, isBipolar: false),
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
                  Panel(
                    title: 'Y',
                    child: _horizontalKnobRow(context, [
                      _knob(context, label: 'Y Off', segment: 'csc/yoff', precision: 2, min: -512, max: 512),
                      _knob(context, label: 'Clip Lo', segment: 'csm/clip_gy_lo'),
                      _knob(context, label: 'Clip Hi', segment: 'csm/clip_gy_hi'),
                      _knob(context, label: 'Shift', segment: 'csm/shift_gy'),
                      _knob(context, label: 'Mult', segment: 'csm/mult_gy'),
                    ]),
                  ),
                  SizedBox(height: t.sm),
                  Panel(
                    title: 'Cb',
                    child: _horizontalKnobRow(context, [
                      _knob(context, label: 'CbCr Off', segment: 'csc/cboff', precision: 2, min: -512, max: 512),
                      _knob(context, label: 'Clip Lo', segment: 'csm/clip_cb_lo'),
                      _knob(context, label: 'Clip Hi', segment: 'csm/clip_cb_hi'),
                      _knob(context, label: 'Shift', segment: 'csm/shift_cb'),
                      _knob(context, label: 'Mult', segment: 'csm/mult_cb'),
                    ]),
                  ),
                  SizedBox(height: t.sm),
                  Panel(
                    title: 'Cr',
                    child: _horizontalKnobRow(context, [
                      _knob(context, label: 'Clip Lo', segment: 'csm/clip_cr_lo'),
                      _knob(context, label: 'Clip Hi', segment: 'csm/clip_cr_hi'),
                      _knob(context, label: 'Shift', segment: 'csm/shift_cr'),
                      _knob(context, label: 'Mult', segment: 'csm/mult_cr'),
                      _knob(context, label: 'CSM Ctrl', segment: 'csm/csm_ctrl'),
                    ]),
                  ),
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
                  _knob(context, label: 'Y Blank', segment: 'dtg1/y_blank'),
                  _knob(context, label: 'Y Sync Lo', segment: 'dtg1/y_sync_lo'),
                  _knob(context, label: 'Y Sync Hi', segment: 'dtg1/y_sync_hi'),
                  _knob(context, label: 'CbCr Blank', segment: 'dtg1/cbcr_blank'),
                  _knob(context, label: 'CbCr Sync Lo', segment: 'dtg1/cbcr_sync_lo'),
                  _knob(context, label: 'CbCr Sync Hi', segment: 'dtg1/cbcr_sync_hi'),
                  _toggle(context, 'DTG1 On', 'dtg1/dtg1_on'),
                  _toggle(context, 'Pass Thru', 'dtg1/pass_thru'),
                  _knob(context, label: 'Mode', segment: 'dtg1/mode', min: 0, max: 15, isBipolar: false),
                  _knob(context, label: 'Spec A', segment: 'dtg1/spec_a'),
                  _knob(context, label: 'Spec B', segment: 'dtg1/spec_b'),
                  _knob(context, label: 'Spec C', segment: 'dtg1/spec_c'),
                  _knob(context, label: 'Spec D', segment: 'dtg1/spec_d'),
                  _knob(context, label: 'Spec D1', segment: 'dtg1/spec_d1'),
                  _knob(context, label: 'Spec E', segment: 'dtg1/spec_e'),
                  _knob(context, label: 'Spec H', segment: 'dtg1/spec_h'),
                  _knob(context, label: 'Spec I', segment: 'dtg1/spec_i'),
                  _knob(context, label: 'Spec K', segment: 'dtg1/spec_k'),
                  _knob(context, label: 'Spec K1', segment: 'dtg1/spec_k1'),
                  _knob(context, label: 'Spec G', segment: 'dtg1/spec_g'),
                  _knob(context, label: 'Total Pixels', segment: 'dtg1/total_pixels', min: 0, max: 8192, isBipolar: false),
                  _toggle(context, 'Field Flip', 'dtg1/field_flip'),
                  _knob(context, label: 'Line Cnt', segment: 'dtg1/line_cnt', min: 0, max: 8192, isBipolar: false),
                  _knob(context, label: 'Frame Size', segment: 'dtg1/frame_size', min: 0, max: 16384, isBipolar: false),
                  _knob(context, label: 'Field Size', segment: 'dtg1/field_size', min: 0, max: 16384, isBipolar: false),
                  _knob(context, label: 'CBar Size', segment: 'dtg1/cbar_size', min: 0, max: 8192, isBipolar: false),
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
                      _knob(context, label: 'HLength', segment: 'dtg2/hlength', min: 0, max: 8192, isBipolar: false),
                      _knob(context, label: 'HDly', segment: 'dtg2/hdly'),
                      _knob(context, label: 'VLength1', segment: 'dtg2/vlength1', min: 0, max: 8192, isBipolar: false),
                      _knob(context, label: 'VDly1', segment: 'dtg2/vdly1'),
                      _knob(context, label: 'VLength2', segment: 'dtg2/vlength2', min: 0, max: 8192, isBipolar: false),
                      _knob(context, label: 'VDly2', segment: 'dtg2/vdly2'),
                      _knob(context, label: 'HS In Dly', segment: 'dtg2/hs_in_dly'),
                      _knob(context, label: 'VS In Dly', segment: 'dtg2/vs_in_dly'),
                      _knob(context, label: 'Pixel Cnt', segment: 'dtg2/pixel_cnt', min: 0, max: 16384, isBipolar: false),
                      _toggle(context, 'IP Fmt', 'dtg2/ctrl/ip_fmt'),
                      _knob(context, label: 'Line Cnt', segment: 'dtg2/ctrl/line_cnt', min: 0, max: 16384, isBipolar: false),
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
