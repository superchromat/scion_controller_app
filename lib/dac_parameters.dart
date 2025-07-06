import 'package:flutter/material.dart';
import 'numeric_slider.dart';
import 'osc_dropdown.dart';
import 'osc_widget_binding.dart';

/// Widget for editing THS8200 DAC registers.
///
/// The layout mirrors the C data structure with sections for each register
/// block (System, CSC, Test, etc.). Only a subset of the many fields are
/// exposed here to keep the UI manageable.
class DacParameters extends StatelessWidget {
  const DacParameters({super.key});

  Widget _slider({
    required String label,
    required String segment,
    RangeValues range = const RangeValues(0, 1023),
    int precision = 0,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 80, child: Text(label)),
        SizedBox(
          height: 24,
          width: 60,
          child: OscPathSegment(
            segment: segment,
            child: NumericSlider(
              value: range.start,
              onChanged: (v) {},
              range: range,
              precision: precision,
              hardDetents: precision == 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _matrixCell(String segment) {
    return SizedBox(
      width: 60,
      height: 20,
      child: OscPathSegment(
        segment: segment,
        child: NumericSlider(
          value: 0,
          onChanged: (_) {},
          range: const RangeValues(-4, 4),
          precision: 2,
        ),
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
      defaultColumnWidth: const FixedColumnWidth(60),
      children: List.generate(3, (row) {
        return TableRow(
          children: List.generate(3, (col) {
            final seg = 'csc/${labels[row][col]}';
            return Padding(
              padding: const EdgeInsets.all(2),
              child: _matrixCell(seg),
            );
          }),
        );
      }),
    );
  }

  Widget _bool({required String label, required String segment}) {
    return OscPathSegment(
      segment: segment,
      child: OscDropdown<bool>(
        label: label,
        items: const [false, true],
        defaultValue: false,
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LabeledCard(
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('System Control', [
          _slider(
            label: 'Version',
            segment: 'system/version',
            range: const RangeValues(0, 255),
          ),
          _bool(label: 'ARST_FUNC_N', segment: 'system/ctl/arst_func_n'),
          _bool(label: 'Chip MS', segment: 'system/ctl/chip_ms'),
          _bool(label: 'Chip Pwdn', segment: 'system/ctl/chip_pwdn'),
          _bool(label: 'DAC Pwdn', segment: 'system/ctl/dac_pwdn'),
          _bool(label: 'DLL Bypass', segment: 'system/ctl/dll_bypass'),
          _bool(label: 'DLL Freq Sel', segment: 'system/ctl/dll_freq_sel'),
          _bool(label: 'VESA Clk', segment: 'system/ctl/vesa_clk'),
          _bool(label: 'VESA Bars', segment: 'system/ctl/vesa_colorbars'),
        ]),

        _section('Color Space Conversion', [
          _cscMatrix(),
          const SizedBox(height: 8),
          _slider(
            label: 'Y Off',
            segment: 'csc/yoff',
            range: const RangeValues(-4, 4),
            precision: 2,
          ),
          _slider(
            label: 'CbCr Off',
            segment: 'csc/cboff',
            range: const RangeValues(-4, 4),
            precision: 2,
          ),
          _bool(label: 'CSC Bypass', segment: 'csc/csc_bypass'),
          _bool(label: 'CSC UOF', segment: 'csc/csc_uof'),
        ]),

        _section('Test Control', [
          _bool(label: 'DigBypass', segment: 'test/digbypass'),
          _bool(label: 'Force Off', segment: 'test/force_off'),
          _slider(
            label: 'Y Delay',
            segment: 'test/ydelay',
            range: const RangeValues(0, 3),
          ),
          _bool(label: 'Fast Ramp', segment: 'test/fastramp'),
          _bool(label: 'Slow Ramp', segment: 'test/slowramp'),
        ]),

        _section('Data Path', [
          _bool(label: 'CLK656 On', segment: 'datapath/clk656_on'),
          _bool(label: 'FS Adjust', segment: 'datapath/fsadj'),
          _bool(label: 'IFIR12 Bypass', segment: 'datapath/ifir12_bypass'),
          _bool(label: 'IFIR35 Bypass', segment: 'datapath/ifir35_bypass'),
          _bool(label: 'Tristate656', segment: 'datapath/tristate656'),
          _slider(
            label: 'DMAN Cntl',
            segment: 'datapath/dman_cntl',
            range: const RangeValues(0, 7),
          ),
        ]),

        _section('DAC Control', [
          _slider(label: 'DAC1', segment: 'dac/dac1'),
          const SizedBox(height: 8),
          _slider(label: 'DAC2', segment: 'dac/dac2'),
          const SizedBox(height: 8),
          _slider(label: 'DAC3', segment: 'dac/dac3'),
          const SizedBox(height: 12),
          _bool(label: 'I2C Control', segment: 'dac/i2c_cntl'),
        ]),

        _section('Clip/Scale/Multiplier', [
          _slider(
            label: 'Clip GY Lo',
            segment: 'csm/clip_gy_lo',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Clip CB Lo',
            segment: 'csm/clip_cb_lo',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Clip CR Lo',
            segment: 'csm/clip_cr_lo',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Clip GY Hi',
            segment: 'csm/clip_gy_hi',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Clip CB Hi',
            segment: 'csm/clip_cb_hi',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Clip CR Hi',
            segment: 'csm/clip_cr_hi',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Shift GY',
            segment: 'csm/shift_gy',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Shift CB',
            segment: 'csm/shift_cb',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Shift CR',
            segment: 'csm/shift_cr',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Mult GY',
            segment: 'csm/mult_gy',
            range: const RangeValues(0, 2047),
          ),
          _slider(
            label: 'Mult CB',
            segment: 'csm/mult_cb',
            range: const RangeValues(0, 2047),
          ),
          _slider(
            label: 'Mult CR',
            segment: 'csm/mult_cr',
            range: const RangeValues(0, 2047),
          ),
          _slider(
            label: 'CSM Ctrl',
            segment: 'csm/csm_ctrl',
            range: const RangeValues(0, 255),
          ),
        ]),

        _section('DTG1', [
          _slider(
            label: 'Y Blank',
            segment: 'dtg1/y_blank',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'Y Sync Lo',
            segment: 'dtg1/y_sync_lo',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'Y Sync Hi',
            segment: 'dtg1/y_sync_hi',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'CbCr Blank',
            segment: 'dtg1/cbcr_blank',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'CbCr Sync Lo',
            segment: 'dtg1/cbcr_sync_lo',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'CbCr Sync Hi',
            segment: 'dtg1/cbcr_sync_hi',
            range: const RangeValues(0, 65535),
          ),
          _bool(label: 'DTG1 On', segment: 'dtg1/dtg1_on'),
          _bool(label: 'Pass Thru', segment: 'dtg1/pass_thru'),
          _slider(
            label: 'Mode',
            segment: 'dtg1/mode',
            range: const RangeValues(0, 15),
          ),
          _slider(
            label: 'Spec A',
            segment: 'dtg1/spec_a',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Spec B',
            segment: 'dtg1/spec_b',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Spec C',
            segment: 'dtg1/spec_c',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Spec D',
            segment: 'dtg1/spec_d',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Spec D1',
            segment: 'dtg1/spec_d1',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Spec E',
            segment: 'dtg1/spec_e',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Spec H',
            segment: 'dtg1/spec_h',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'Spec I',
            segment: 'dtg1/spec_i',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'Spec K',
            segment: 'dtg1/spec_k',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'Spec K1',
            segment: 'dtg1/spec_k1',
            range: const RangeValues(0, 255),
          ),
          _slider(
            label: 'Spec G',
            segment: 'dtg1/spec_g',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'Total Pixels',
            segment: 'dtg1/total_pixels',
            range: const RangeValues(0, 65535),
          ),
          _bool(label: 'Field Flip', segment: 'dtg1/field_flip'),
          _slider(
            label: 'Line Cnt',
            segment: 'dtg1/line_cnt',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'Frame Size',
            segment: 'dtg1/frame_size',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'Field Size',
            segment: 'dtg1/field_size',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'CBar Size',
            segment: 'dtg1/cbar_size',
            range: const RangeValues(0, 255),
          ),
        ]),

        _section('DTG2', [
          ...List.generate(
            16,
            (i) => _slider(
              label: 'BP$i',
              segment: 'dtg2/bp/$i',
              range: const RangeValues(0, 2047),
            ),
          ),
          ...List.generate(
            16,
            (i) => _slider(
              label: 'Type$i',
              segment: 'dtg2/linetype/$i',
              range: const RangeValues(0, 255),
            ),
          ),
          _slider(
            label: 'HLength',
            segment: 'dtg2/hlength',
            range: const RangeValues(0, 1023),
          ),
          _slider(
            label: 'HDly',
            segment: 'dtg2/hdly',
            range: const RangeValues(0, 8191),
          ),
          _slider(
            label: 'VLength1',
            segment: 'dtg2/vlength1',
            range: const RangeValues(0, 1023),
          ),
          _slider(
            label: 'VDly1',
            segment: 'dtg2/vdly1',
            range: const RangeValues(0, 2047),
          ),
          _slider(
            label: 'VLength2',
            segment: 'dtg2/vlength2',
            range: const RangeValues(0, 1023),
          ),
          _slider(
            label: 'VDly2',
            segment: 'dtg2/vdly2',
            range: const RangeValues(0, 2047),
          ),
          _slider(
            label: 'HS In Dly',
            segment: 'dtg2/hs_in_dly',
            range: const RangeValues(0, 8191),
          ),
          _slider(
            label: 'VS In Dly',
            segment: 'dtg2/vs_in_dly',
            range: const RangeValues(0, 2047),
          ),
          _slider(
            label: 'Pixel Cnt',
            segment: 'dtg2/pixel_cnt',
            range: const RangeValues(0, 65535),
          ),
          _bool(label: 'IP Fmt', segment: 'dtg2/ctrl/ip_fmt'),
          _slider(
            label: 'Line Cnt',
            segment: 'dtg2/ctrl/line_cnt',
            range: const RangeValues(0, 2047),
          ),
          _bool(label: 'FID DE', segment: 'dtg2/ctrl/fid_de'),
          _bool(label: 'RGB Mode', segment: 'dtg2/ctrl/rgb_mode'),
          _bool(label: 'Emb Timing', segment: 'dtg2/ctrl/emb_timing'),
          _bool(label: 'VSOut Pol', segment: 'dtg2/ctrl/vsout_pol'),
          _bool(label: 'HSOut Pol', segment: 'dtg2/ctrl/hsout_pol'),
          _bool(label: 'FID Pol', segment: 'dtg2/ctrl/fid_pol'),
          _bool(label: 'VS Pol', segment: 'dtg2/ctrl/vs_pol'),
          _bool(label: 'HS Pol', segment: 'dtg2/ctrl/hs_pol'),
        ]),

        _section('CGMS', [
          _bool(label: 'Enable', segment: 'cgms/enable'),
          _slider(
            label: 'Header',
            segment: 'cgms/header',
            range: const RangeValues(0, 63),
          ),
          _slider(
            label: 'Payload',
            segment: 'cgms/payload',
            range: const RangeValues(0, 1023),
          ),
        ]),

        _section('Readback', [
          _slider(
            label: 'PPL',
            segment: 'readback/ppl',
            range: const RangeValues(0, 65535),
          ),
          _slider(
            label: 'LPF',
            segment: 'readback/lpf',
            range: const RangeValues(0, 65535),
          ),
        ]),
      ],
    );
  }
}
