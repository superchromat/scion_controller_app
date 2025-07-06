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
          _bool(label: 'ARST_FUNC_N', segment: 'system/ctl/arst_func_n'),
          _bool(label: 'Chip MS', segment: 'system/ctl/chip_ms'),
          _bool(label: 'Chip Pwdn', segment: 'system/ctl/chip_pwdn'),
          _bool(label: 'DAC Pwdn', segment: 'system/ctl/dac_pwdn'),
          _bool(label: 'DLL Bypass', segment: 'system/ctl/dll_bypass'),
          _bool(label: 'DLL Freq Sel', segment: 'system/ctl/dll_freq_sel'),
          _bool(label: 'VESA Clk', segment: 'system/ctl/vesa_clk'),
          _bool(label: 'VESA Bars', segment: 'system/ctl/vesa_colorbars'),
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
        _section('Color Space Conversion', [
          _slider(
            label: 'R2R',
            segment: 'csc/r2r',
            range: const RangeValues(-4, 4),
            precision: 2,
          ),
          _slider(
            label: 'G2G',
            segment: 'csc/g2g',
            range: const RangeValues(-4, 4),
            precision: 2,
          ),
          _slider(
            label: 'B2B',
            segment: 'csc/b2b',
            range: const RangeValues(-4, 4),
            precision: 2,
          ),
          _bool(label: 'CSC Bypass', segment: 'csc/csc_bypass'),
          _bool(label: 'CSC UOF', segment: 'csc/csc_uof'),
        ]),
        _section('Test', [
          _bool(label: 'DigBypass', segment: 'test/digbypass'),
          _bool(label: 'Force Off', segment: 'test/force_off'),
          _bool(label: 'Fast Ramp', segment: 'test/fastramp'),
          _bool(label: 'Slow Ramp', segment: 'test/slowramp'),
          _slider(
            label: 'Y Delay',
            segment: 'test/ydelay',
            range: const RangeValues(0, 3),
          ),
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
