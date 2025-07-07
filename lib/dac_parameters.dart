import 'package:flutter/material.dart';

import 'labeled_card.dart';
import 'osc_checkbox.dart';
import 'osc_number_field.dart';
import 'osc_value_dropdown.dart';
import 'osc_widget_binding.dart';

class DacParameters extends StatelessWidget {
  const DacParameters({super.key});

  Widget _numField(
    String label,
    String segment, {
    int precision = 0,
    bool readOnly = false,
  }) {
    return SizedBox(
      width: 150,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 80, child: Text(label)),
          SizedBox(
            width: 60,
            height: 24,
            child: OscPathSegment(
              segment: segment,
              child: OscNumberField(precision: precision, readOnly: readOnly),
            ),
          ),
        ],
      ),
    );
  }

  Widget _boolField(String label, String segment) {
    return SizedBox(
      width: 150,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 80, child: Text(label)),
          OscPathSegment(segment: segment, child: const OscCheckbox()),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LabeledCard(
        title: title,
        child: Wrap(spacing: 12, runSpacing: 8, children: children),

      ),
    );
  }

  Widget _cscMatrix() {
    const labels = [
      ['r2r', 'r2g', 'r2b'],
      ['g2r', 'g2g', 'g2b'],
      ['b2r', 'b2g', 'b2b'],
    ];
    return Table(
      border: TableBorder.all(color: Colors.grey, width: 0.5),
              child: OscPathSegment(
                segment: seg,
                child: OscNumberField(precision: 2),
              ),
            );
          }),
        );
      }),
    );
  }

  Widget _dtg2Table() {
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
    return Table(
      border: TableBorder.all(color: Colors.grey, width: 0.5),
      defaultColumnWidth: const FixedColumnWidth(140),
      children: List.generate(16, (i) {
        return TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: OscPathSegment(
                segment: 'dtg2/bp/$i',
                child: OscNumberField(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: OscPathSegment(
                segment: 'dtg2/linetype/$i',
                child: OscValueDropdown<int>(
                  values: List.generate(16, (j) => j),
                  labels: modes,
                  initialValue: 0,
                ),
              ),
            ),
          ],
        );
      }),

    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('System Control', [
          _numField('Version', 'system/version', readOnly: true),
          _boolField('ARST_FUNC_N', 'system/ctl/arst_func_n'),
          _boolField('Chip MS', 'system/ctl/chip_ms'),
          _boolField('Chip Pwdn', 'system/ctl/chip_pwdn'),
          _boolField('DAC Pwdn', 'system/ctl/dac_pwdn'),
          _boolField('DLL Bypass', 'system/ctl/dll_bypass'),
          _boolField('DLL Freq Sel', 'system/ctl/dll_freq_sel'),
          _boolField('VESA Clk', 'system/ctl/vesa_clk'),
          _boolField('VESA Bars', 'system/ctl/vesa_colorbars'),
        ]),
        _section('Color Space Conversion', [
          _cscMatrix(),
          _numField('Y Off', 'csc/yoff', precision: 2),
          _numField('CbCr Off', 'csc/cboff', precision: 2),
          _boolField('CSC Bypass', 'csc/csc_bypass'),
          _boolField('CSC UOF', 'csc/csc_uof'),
        ]),
        _section('Test Control', [
          _boolField('DigBypass', 'test/digbypass'),
          _boolField('Force Off', 'test/force_off'),
          _numField('Y Delay', 'test/ydelay'),
          _boolField('Fast Ramp', 'test/fastramp'),
          _boolField('Slow Ramp', 'test/slowramp'),
        ]),
        _section('Data Path', [
          _boolField('CLK656 On', 'datapath/clk656_on'),
          _boolField('FS Adjust', 'datapath/fsadj'),
          _boolField('IFIR12 Bypass', 'datapath/ifir12_bypass'),
          _boolField('IFIR35 Bypass', 'datapath/ifir35_bypass'),
          _boolField('Tristate656', 'datapath/tristate656'),
          _numField('DMAN Cntl', 'datapath/dman_cntl'),
        ]),
        _section('DAC Control', [
          _numField('DAC1', 'dac/dac1'),
          _numField('DAC2', 'dac/dac2'),
          _numField('DAC3', 'dac/dac3'),
          _boolField('I2C Control', 'dac/i2c_cntl'),
        ]),
        _section('Clip/Scale/Multiplier', [
          _numField('Clip GY Lo', 'csm/clip_gy_lo'),
          _numField('Clip CB Lo', 'csm/clip_cb_lo'),
          _numField('Clip CR Lo', 'csm/clip_cr_lo'),
          _numField('Clip GY Hi', 'csm/clip_gy_hi'),
          _numField('Clip CB Hi', 'csm/clip_cb_hi'),
          _numField('Clip CR Hi', 'csm/clip_cr_hi'),
          _numField('Shift GY', 'csm/shift_gy'),
          _numField('Shift CB', 'csm/shift_cb'),
          _numField('Shift CR', 'csm/shift_cr'),
          _numField('Mult GY', 'csm/mult_gy'),
          _numField('Mult CB', 'csm/mult_cb'),
          _numField('Mult CR', 'csm/mult_cr'),
          _numField('CSM Ctrl', 'csm/csm_ctrl'),
        ]),
        _section('DTG1', [
          _numField('Y Blank', 'dtg1/y_blank'),
          _numField('Y Sync Lo', 'dtg1/y_sync_lo'),
          _numField('Y Sync Hi', 'dtg1/y_sync_hi'),
          _numField('CbCr Blank', 'dtg1/cbcr_blank'),
          _numField('CbCr Sync Lo', 'dtg1/cbcr_sync_lo'),
          _numField('CbCr Sync Hi', 'dtg1/cbcr_sync_hi'),
          _boolField('DTG1 On', 'dtg1/dtg1_on'),
          _boolField('Pass Thru', 'dtg1/pass_thru'),
          _numField('Mode', 'dtg1/mode'),
          _numField('Spec A', 'dtg1/spec_a'),
          _numField('Spec B', 'dtg1/spec_b'),
          _numField('Spec C', 'dtg1/spec_c'),
          _numField('Spec D', 'dtg1/spec_d'),
          _numField('Spec D1', 'dtg1/spec_d1'),
          _numField('Spec E', 'dtg1/spec_e'),
          _numField('Spec H', 'dtg1/spec_h'),
          _numField('Spec I', 'dtg1/spec_i'),
          _numField('Spec K', 'dtg1/spec_k'),
          _numField('Spec K1', 'dtg1/spec_k1'),
          _numField('Spec G', 'dtg1/spec_g'),
          _numField('Total Pixels', 'dtg1/total_pixels'),
          _boolField('Field Flip', 'dtg1/field_flip'),
          _numField('Line Cnt', 'dtg1/line_cnt'),
          _numField('Frame Size', 'dtg1/frame_size'),
          _numField('Field Size', 'dtg1/field_size'),
          _numField('CBar Size', 'dtg1/cbar_size'),
        ]),
        _section('DTG2', [
          _dtg2Table(),
          _numField('HLength', 'dtg2/hlength'),
          _numField('HDly', 'dtg2/hdly'),
          _numField('VLength1', 'dtg2/vlength1'),
          _numField('VDly1', 'dtg2/vdly1'),
          _numField('VLength2', 'dtg2/vlength2'),
          _numField('VDly2', 'dtg2/vdly2'),
          _numField('HS In Dly', 'dtg2/hs_in_dly'),
          _numField('VS In Dly', 'dtg2/vs_in_dly'),
          _numField('Pixel Cnt', 'dtg2/pixel_cnt'),
          _boolField('IP Fmt', 'dtg2/ctrl/ip_fmt'),
          _numField('Line Cnt', 'dtg2/ctrl/line_cnt'),
          _boolField('FID DE', 'dtg2/ctrl/fid_de'),
          _boolField('RGB Mode', 'dtg2/ctrl/rgb_mode'),
          _boolField('Emb Timing', 'dtg2/ctrl/emb_timing'),
          _boolField('VSOut Pol', 'dtg2/ctrl/vsout_pol'),
          _boolField('HSOut Pol', 'dtg2/ctrl/hsout_pol'),
          _boolField('FID Pol', 'dtg2/ctrl/fid_pol'),
          _boolField('VS Pol', 'dtg2/ctrl/vs_pol'),
          _boolField('HS Pol', 'dtg2/ctrl/hs_pol'),
        ]),
        _section('CGMS', [
          _boolField('Enable', 'cgms/enable'),
          _numField('Header', 'cgms/header'),
          _numField('Payload', 'cgms/payload'),
        ]),
        _section('Readback', [
          _numField('PPL', 'readback/ppl', readOnly: true),
          _numField('LPF', 'readback/lpf', readOnly: true),

        ]),
      ],
    );
  }
}
