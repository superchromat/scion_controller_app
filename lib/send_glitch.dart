import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'grid.dart';

/// Glitch effects controls for pixel bus bit and channel ordering.
///
/// Controls:
/// - Channel Swap: Y/Cb/Cr channel swapping with optional MSB/LSB bit swap (0-7)
/// - Bit Swap: Per-component bit order swap for Y, Cb, Cr (0-7 bitmask)
/// - Stride Offset: Diagonal tearing effect via SDRAM column offset
/// - OutMux Mode: Pixel packing format on output bus (0-32)
/// - OutMux Port: Virtual to display port mapping (0-5)
class SendGlitch extends StatefulWidget {
  const SendGlitch({super.key});

  @override
  State<SendGlitch> createState() => _SendGlitchState();
}

class _SendGlitchState extends State<SendGlitch> with OscAddressMixin {
  /// Reset all glitch controls to defaults (no glitch)
  void reset() {
    sendOsc(0, address: 'glitch/channel_swap');
    sendOsc(0, address: 'glitch/bit_swap');
    sendOsc(0, address: 'glitch/stride_offset');
    sendOsc(0, address: 'glitch/frame_delay');
    sendOsc(0, address: 'glitch/row_offset');
    sendOsc(0, address: 'glitch/addr_offset');
    sendOsc(0, address: 'glitch/addr_limit_disable');
    sendOsc(0, address: 'glitch/cb_offset');
    sendOsc(0, address: 'glitch/cr_offset');
    sendOsc(0, address: 'glitch/bit_precision');  // 0 = 8bpp (normal)
    sendOsc(0, address: 'glitch/map_mode');  // 0 = 1D mode (normal)
    sendOsc(0, address: 'glitch/y_freeze');
    sendOsc(0, address: 'glitch/c_freeze');
    sendOsc(0, address: 'glitch/test_pattern');
    sendOsc(0, address: 'glitch/y_buf_type');  // 0 = Y (normal)
    sendOsc(1, address: 'glitch/cb_buf_type');  // 1 = Cb (normal)
    sendOsc(2, address: 'glitch/cr_buf_type');  // 2 = Cr (normal)
    sendOsc(1, address: 'glitch/outmux_mode');  // 1 = single pixel mode
    sendOsc(0, address: 'glitch/outmux_port');
    // MFC structural glitches
    sendOsc(0, address: 'glitch/mfc_in_roi_x');
    sendOsc(0, address: 'glitch/mfc_in_roi_y');
    sendOsc(0, address: 'glitch/valid_lines');
    sendOsc(0, address: 'glitch/rows_per_frame');
    sendOsc(0, address: 'glitch/col_window');
    sendOsc(4, address: 'glitch/buf_id');  // 4 = Out 0 (normal for Send 1)
    // Genlock
    sendOsc(0, address: 'glitch/gen_dlyH');
    sendOsc(0, address: 'glitch/gen_dlyV');
    sendOsc(32, address: 'glitch/gen_hyst');
    sendOsc(2, address: 'glitch/gen_fine');  // 2 = frame-lock
  }

  // Bit precision labels
  static const List<String> _bitPrecisionLabels = [
    '0: 8bpp',
    '1: 10bpp',
    '2: 4/5bpp',
    '3: 12bpp',
  ];

  // Map mode labels
  static const List<String> _mapModeLabels = [
    '0: 1D Map',
    '1: 2D Map',
  ];

  // Test pattern labels
  static const List<String> _testPatternLabels = [
    '0: Off',
    '1: Pattern 1',
    '2: Pattern 2',
    '3: Pattern 3',
  ];

  // Buffer type labels (what buffer type Y/Cb/Cr reads from)
  static const List<String> _bufTypeLabels = [
    '0: Y',
    '1: Cb',
    '2: Cr',
  ];

  // Buffer ID labels (which frame buffer to read from)
  static const List<String> _bufIdLabels = [
    '0: In 0',
    '1: In 1',
    '2: In 2',
    '3: In 3',
    '4: Out 0',
    '5: Out 1',
    '6: Out 2',
    '7: Out 3',
  ];

  // Channel swap mode labels
  static const List<String> _channelSwapLabels = [
    'Normal',           // 0: Y<=Y, Cb<=Cb, Cr<=Cr
    'Y↔Cb',             // 1: Y<=Cb, Cb<=Y, Cr<=Cr
    'Y↔Cr',             // 2: Y<=Cr, Cb<=Cb, Cr<=Y
    'Cb↔Cr',            // 3: Y<=Y, Cb<=Cr, Cr<=Cb
    'Bit Swap',         // 4: MSB<->LSB + normal
    'Bit + Y↔Cb',       // 5: MSB<->LSB + Y↔Cb
    'Bit + Y↔Cr',       // 6: MSB<->LSB + Y↔Cr
    'Bit + Cb↔Cr',      // 7: MSB<->LSB + Cb↔Cr
  ];

  // OutMux mode labels (subset of most useful modes)
  static const List<String> _outmuxModeLabels = [
    '0: Disable',
    '1: Single 12b',
    '2: Dual 444',
    '3: 444 IO.3',
    '4: 444 DPIO.3',
    '5: 422 Single',
    '6: 422 Dual',
    '7: 422a Single',
    '8: 422 IO.2',
  ];

  // OutMux port labels
  static const List<String> _outmuxPortLabels = [
    '0: 1:1 Single',
    '1: 1:2 Dual',
    '2: Interleave 1',
    '3: Interleave 2',
    '4: 18b Dual',
    '5: All from vp',
  ];

  // Genlock fine mode labels
  static const List<String> _genFineModeLabels = [
    '0: Free-run',
    '1: Frame-sync',
    '2: Frame-lock',
  ];

  Widget _intDropdown({
    required String label,
    required List<String> options,
    required String oscAddress,
    double width = 130,
  }) {
    return OscPathSegment(
      segment: oscAddress,
      child: _IntDropdownWidget(
        label: label,
        options: options,
        width: width,
      ),
    );
  }

  Widget _bitSwapControl() {
    return OscPathSegment(
      segment: 'bit_swap',
      child: const _BitSwapWidget(),
    );
  }

  Widget _knob({
    required String label,
    required String oscAddress,
    required double min,
    required double max,
    double initial = 0,
    double? defaultValue,
    String format = '%d',
    bool isBipolar = false,
  }) {
    final t = GridProvider.maybeOf(context);
    return OscPathSegment(
      segment: oscAddress,
      child: OscRotaryKnob(
        label: label,
        minValue: min,
        maxValue: max,
        initialValue: initial,
        defaultValue: defaultValue ?? initial,
        format: format,
        isBipolar: isBipolar,
        preferInteger: true,
        size: t?.knobMd ?? 60,
      ),
    );
  }

  Widget _sectionHeader(String title) {
    final t = GridProvider.maybeOf(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(top: t?.md ?? 12, bottom: t?.xs ?? 4),
      child: Text(
        title,
        style: t?.textHeading ?? TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.maybeOf(context);
    final wrapSpacing = t?.lg ?? 24.0;
    final wrapRunSpacing = t?.sm ?? 12.0;
    return OscPathSegment(
      segment: 'glitch',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pixel Bus section
          _sectionHeader('PIXEL BUS'),
          Wrap(
            spacing: wrapSpacing,
            runSpacing: wrapRunSpacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _intDropdown(
                label: 'Channel Swap',
                options: _channelSwapLabels,
                oscAddress: 'channel_swap',
                width: 130,
              ),
              _bitSwapControl(),
            ],
          ),

          // Frame Buffer section
          _sectionHeader('FRAME BUFFER'),
          Wrap(
            spacing: wrapSpacing,
            runSpacing: wrapRunSpacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _knob(
                label: 'Stride',
                oscAddress: 'stride_offset',
                min: -50,
                max: 50,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
              _knob(
                label: 'Row Ofs',
                oscAddress: 'row_offset',
                min: -500,
                max: 500,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
              _knob(
                label: 'Addr Ofs',
                oscAddress: 'addr_offset',
                min: -1000,
                max: 1000,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
              _knob(
                label: 'Rows/Frm',
                oscAddress: 'rows_per_frame',
                min: -500,
                max: 500,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
              _knob(
                label: 'Cb Ofs',
                oscAddress: 'cb_offset',
                min: -5000,
                max: 5000,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
              _knob(
                label: 'Cr Ofs',
                oscAddress: 'cr_offset',
                min: -5000,
                max: 5000,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
            ],
          ),

          // Memory Control section
          _sectionHeader('MEMORY CONTROL'),
          Wrap(
            spacing: wrapSpacing,
            runSpacing: wrapRunSpacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OscPathSegment(
                segment: 'addr_limit_disable',
                child: const _ToggleWidget(label: 'No Limits'),
              ),
              _knob(
                label: 'Col Win',
                oscAddress: 'col_window',
                min: -1000,
                max: 1000,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
              _intDropdown(
                label: 'Bit Precision',
                options: _bitPrecisionLabels,
                oscAddress: 'bit_precision',
                width: 100,
              ),
              _intDropdown(
                label: 'Map Mode',
                options: _mapModeLabels,
                oscAddress: 'map_mode',
                width: 100,
              ),
              _intDropdown(
                label: 'Buf ID',
                options: _bufIdLabels,
                oscAddress: 'buf_id',
                width: 80,
              ),
              _intDropdown(
                label: 'Y Buf Type',
                options: _bufTypeLabels,
                oscAddress: 'y_buf_type',
                width: 80,
              ),
              _intDropdown(
                label: 'Cb Buf Type',
                options: _bufTypeLabels,
                oscAddress: 'cb_buf_type',
                width: 80,
              ),
              _intDropdown(
                label: 'Cr Buf Type',
                options: _bufTypeLabels,
                oscAddress: 'cr_buf_type',
                width: 80,
              ),
            ],
          ),

          // MFC section
          _sectionHeader('MFC'),
          Wrap(
            spacing: wrapSpacing,
            runSpacing: wrapRunSpacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _knob(
                label: 'In ROI X',
                oscAddress: 'mfc_in_roi_x',
                min: -500,
                max: 500,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
              _knob(
                label: 'In ROI Y',
                oscAddress: 'mfc_in_roi_y',
                min: -500,
                max: 500,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
              _knob(
                label: 'Valid Lns',
                oscAddress: 'valid_lines',
                min: -30,
                max: 30,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
            ],
          ),

          // Temporal section
          _sectionHeader('TEMPORAL'),
          Wrap(
            spacing: wrapSpacing,
            runSpacing: wrapRunSpacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _knob(
                label: 'Frame Dly',
                oscAddress: 'frame_delay',
                min: 0,
                max: 6,
                initial: 0,
                defaultValue: 0,
              ),
              OscPathSegment(
                segment: 'y_freeze',
                child: const _ToggleWidget(label: 'Y Freeze'),
              ),
              OscPathSegment(
                segment: 'c_freeze',
                child: const _ToggleWidget(label: 'C Freeze'),
              ),
              _intDropdown(
                label: 'Test Pattern',
                options: _testPatternLabels,
                oscAddress: 'test_pattern',
                width: 100,
              ),
            ],
          ),

          // Genlock section
          _sectionHeader('GENLOCK'),
          Wrap(
            spacing: wrapSpacing,
            runSpacing: wrapRunSpacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _knob(
                label: 'H Delay',
                oscAddress: 'gen_dlyH',
                min: -500,
                max: 500,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
              _knob(
                label: 'V Delay',
                oscAddress: 'gen_dlyV',
                min: -100,
                max: 100,
                initial: 0,
                defaultValue: 0,
                isBipolar: true,
              ),
              _knob(
                label: 'Hyst',
                oscAddress: 'gen_hyst',
                min: 0,
                max: 1000,
                initial: 32,
                defaultValue: 32,
              ),
              _intDropdown(
                label: 'Fine Mode',
                options: _genFineModeLabels,
                oscAddress: 'gen_fine',
                width: 120,
              ),
            ],
          ),

          // Output Mux section
          _sectionHeader('OUTPUT MUX'),
          Wrap(
            spacing: wrapSpacing,
            runSpacing: wrapRunSpacing,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _intDropdown(
                label: 'OutMux Mode',
                options: _outmuxModeLabels,
                oscAddress: 'outmux_mode',
                width: 130,
              ),
              _intDropdown(
                label: 'OutMux Port',
                options: _outmuxPortLabels,
                oscAddress: 'outmux_port',
                width: 130,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Integer dropdown widget for glitch controls
class _IntDropdownWidget extends StatefulWidget {
  final String label;
  final List<String> options;
  final double width;

  const _IntDropdownWidget({
    required this.label,
    required this.options,
    this.width = 130,
  });

  @override
  State<_IntDropdownWidget> createState() => _IntDropdownWidgetState();
}

class _IntDropdownWidgetState extends State<_IntDropdownWidget> with OscAddressMixin {
  int _value = 0;

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isNotEmpty && args.first is int) {
      final v = args.first as int;
      if (v >= 0 && v < widget.options.length) {
        setState(() => _value = v);
        return OscStatus.ok;
      }
    }
    return OscStatus.error;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[400],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          width: widget.width,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF3A3A3C),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[700]!, width: 1),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _value.clamp(0, widget.options.length - 1),
              isExpanded: true,
              dropdownColor: const Color(0xFF3A3A3C),
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Colors.white,
              ),
              items: List.generate(widget.options.length, (i) {
                return DropdownMenuItem(
                  value: i,
                  child: Text(widget.options[i]),
                );
              }),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _value = v);
                  sendOsc(v);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Bit swap control with individual toggles for Y, Cb, Cr
class _BitSwapWidget extends StatefulWidget {
  const _BitSwapWidget();

  @override
  State<_BitSwapWidget> createState() => _BitSwapWidgetState();
}

class _BitSwapWidgetState extends State<_BitSwapWidget> with OscAddressMixin {
  int _value = 0;

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isNotEmpty && args.first is int) {
      final v = (args.first as int) & 0x07;
      setState(() => _value = v);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  void _toggleBit(int bit) {
    final newValue = _value ^ (1 << bit);
    setState(() => _value = newValue);
    sendOsc(newValue);
  }

  Widget _bitToggle(String label, int bit) {
    final isSet = (_value & (1 << bit)) != 0;
    return GestureDetector(
      onTap: () => _toggleBit(bit),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSet ? const Color(0xFFFFF176) : const Color(0xFF2A2A2C),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSet ? const Color(0xFFFFF176) : Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isSet ? Colors.black : Colors.grey[400],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            'Bit Swap',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[400],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bitToggle('Y', 0),
            const SizedBox(width: 4),
            _bitToggle('Cb', 1),
            const SizedBox(width: 4),
            _bitToggle('Cr', 2),
          ],
        ),
      ],
    );
  }
}

/// Simple toggle widget for boolean glitch controls
class _ToggleWidget extends StatefulWidget {
  final String label;

  const _ToggleWidget({required this.label});

  @override
  State<_ToggleWidget> createState() => _ToggleWidgetState();
}

class _ToggleWidgetState extends State<_ToggleWidget> with OscAddressMixin {
  bool _enabled = false;

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isNotEmpty && args.first is int) {
      setState(() => _enabled = (args.first as int) != 0);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[400],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            final newValue = !_enabled;
            setState(() => _enabled = newValue);
            sendOsc(newValue ? 1 : 0);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _enabled ? const Color(0xFFFF6B6B) : const Color(0xFF2A2A2C),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _enabled ? const Color(0xFFFF6B6B) : Colors.grey[600]!,
                width: 1,
              ),
            ),
            child: Text(
              _enabled ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _enabled ? Colors.white : Colors.grey[400],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

