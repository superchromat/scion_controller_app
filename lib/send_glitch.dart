import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'osc_dropdown.dart';
import 'osc_registry.dart';
import 'grid.dart';
import 'panel.dart';
import 'poster_editor.dart';

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
  /// Reset all glitch controls to defaults (no glitch).
  /// Sends a /glitch/reset command that clears all stored state,
  /// restores hardware registers, and forces a full frame buffer reinit.
  /// Also dispatches default values so all knobs/dropdowns update.
  void reset() {
    // Tell firmware to hard-reset this channel's glitch state
    sendOsc(true, address: 'glitch/reset');

    // Dispatch default values so UI controls update immediately.
    // Uses dispatch() (not dispatchLocal) so knob echo-suppression
    // doesn't filter out the value.
    final reg = OscRegistry();
    final base = '$oscAddress/glitch';

    void _set(String seg, Object? value) {
      final addr = '$base/$seg';
      reg.registerAddress(addr);
      reg.dispatch(addr, <Object?>[value]);
    }

    for (final seg in [
      'channel_swap', 'bit_swap', 'stride_offset', 'frame_delay',
      'row_offset', 'addr_offset', 'addr_limit_disable',
      'write_addr_offset', 'write_phase', 'row_repeat',
      'bit_precision', 'map_mode',
      'y_freeze', 'c_freeze',
      'mfc_in_roi_x', 'mfc_in_roi_y',
      'valid_lines', 'rows_per_frame', 'col_window',
      'gen_dlyH', 'gen_dlyV',
      'outmux_port', 'write_ffc_map', 'mfc_read_buf',
      'y_buf_type',
      'even_odd_swap', 'cbcr_swap',
      'gac_enable', 'gac_shear_src', 'gac_shear_dst',
    ]) {
      _set(seg, 0);
    }
    // Rect Copy defaults (mirror firmware boot state). gac_enable=0 above
    // stops the blit loop; the firmware reset command doesn't know about GAC,
    // so also push the disable explicitly.
    sendOsc(0, address: 'glitch/gac_enable');
    _set('gac_x', 896);
    _set('gac_y', 476);
    _set('gac_size', 128);
    _set('gac_grid', 4);
    // Posterizer off (global endpoint — firmware reset doesn't know it)
    context.read<Network>().sendOscMessage('/poster/enable', [0]);
    // Warp defaults (Send 1 only; firmware reset doesn't know warp)
    sendOsc(0, address: 'glitch/warp_enable');
    for (final seg in ['warp_enable', 'warp_key_h', 'warp_key_v',
                       'warp_shear_x', 'warp_shear_y', 'warp_barrel',
                       'warp_lens_x', 'warp_lens_y', 'warp_radius',
                       'warp_wobble', 'warp_breathe', 'warp_roam']) {
      _set(seg, 0);
    }
    _set('warp_zoom', 1000);
    _set('warp_speed', 250);
    // Color Field defaults (Send 1 only; firmware reset doesn't know UC)
    sendOsc(0, address: 'glitch/uc_enable');
    sendOsc(0, address: 'glitch/uc_fx');
    for (final seg in ['uc_enable', 'uc_fx', 'uc_amp_r', 'uc_amp_g',
                       'uc_amp_b', 'uc_angle', 'uc_speed']) {
      _set(seg, 0);
    }
    _set('uc_amount', 127);
    _set('uc_freq', 100);
    _set('uc_cx', 960);
    _set('uc_cy', 540);
    _set('uc_res', 16);
    _set('uc_bias', 1023);
    _set('cb_buf_type', 1);
    _set('cr_buf_type', 2);
    _set('outmux_mode', 1);
    _set('buf_id', 4);
    _set('gen_hyst', 32);
    _set('gen_fine', 2);
    _set('enable', false);
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
    'Y/Cb',             // 1: Y<=Cb, Cb<=Y, Cr<=Cr
    'Y/Cr',             // 2: Y<=Cr, Cb<=Cb, Cr<=Y
    'Cb/Cr',            // 3: Y<=Y, Cb<=Cr, Cr<=Cb
    'Bit Swap',         // 4: MSB<->LSB + normal
    'Bit + Y/Cb',       // 5: MSB<->LSB + Y↔Cb
    'Bit + Y/Cr',       // 6: MSB<->LSB + Y↔Cr
    'Bit + Cb/Cr',      // 7: MSB<->LSB + Cb↔Cr
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
    return OscDropdown<int>(
      label: label,
      pathSegment: oscAddress,
      items: List.generate(options.length, (i) => i),
      itemLabels: {for (int i = 0; i < options.length; i++) i: options[i]},
      defaultValue: 0,
      width: width,
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
        labelStyle: t?.textLabel,
      ),
    );
  }

  // Basis functions for the uniformity-correction color field (Send 1 only)
  static const List<String> _ucFxLabels = [
    '0: Flat',
    '1: Gradient',
    '2: Rings',
    '3: Plaid',
  ];

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final segs = OscPathSegment.resolvePath(context);
    final isSend1 = segs.length >= 2 && segs[0] == 'send' && segs[1] == '1';

    return OscPathSegment(
      segment: 'glitch',
      child: CardColumn(
        children: [
          // Row 1: Pixel Bus (1/3) | Frame Buffer (2/3)
          GridRow(columns: 3, gutter: t.md, cells: [
            (span: 1, child: Panel(
              title: 'Pixel Bus',
              child: Wrap(
                spacing: t.sm,
                runSpacing: t.sm,
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
            )),
            (span: 2, child: Panel(
              title: 'Frame Buffer',
              child: Row(children: [
                Expanded(child: Center(child: _knob(label: 'Stride',    oscAddress: 'stride_offset',   min: -50,   max: 50,   isBipolar: true))),
                Expanded(child: Center(child: _knob(label: 'Row Ofs',   oscAddress: 'row_offset',      min: -500,  max: 500,  isBipolar: true))),
                Expanded(child: Center(child: _knob(label: 'Addr Ofs',  oscAddress: 'addr_offset',     min: -1000, max: 1000, isBipolar: true))),
                Expanded(child: Center(child: _knob(label: 'FFC Map',   oscAddress: 'write_ffc_map',   min: 0,     max: 7))),
                Expanded(child: Center(child: _knob(label: 'MFC Buf',   oscAddress: 'mfc_read_buf',    min: 0,     max: 7,     initial: 0))),
                Expanded(child: Center(child: _knob(label: 'Wr Addr',   oscAddress: 'write_addr_offset', min: -65535, max: 65535, isBipolar: true))),
                Expanded(child: Center(child: _knob(label: 'Wr Phase',  oscAddress: 'write_phase',     min: 0,     max: 6))),
                Expanded(child: Center(child: _knob(label: 'Row Rpt',   oscAddress: 'row_repeat',      min: 0,     max: 2160))),
              ]),
            )),
          ]),
          // Row 2: MFC (1/3) | Temporal (1/3) | Genlock (1/3)
          GridRow(columns: 3, gutter: t.md, cells: [
            (span: 1, child: Panel(
              title: 'MFC',
              child: Row(children: [
                Expanded(child: Center(child: _knob(label: 'In ROI X',  oscAddress: 'mfc_in_roi_x', min: -500, max: 500, isBipolar: true))),
                Expanded(child: Center(child: _knob(label: 'In ROI Y',  oscAddress: 'mfc_in_roi_y', min: -500, max: 500, isBipolar: true))),
                Expanded(child: Center(child: _knob(label: 'Valid Lns', oscAddress: 'valid_lines',  min: -30,  max: 30,  isBipolar: true))),
              ]),
            )),
            (span: 1, child: Panel(
              title: 'Temporal',
              child: Wrap(
                spacing: t.sm,
                runSpacing: t.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _knob(label: 'Frame Dly', oscAddress: 'frame_delay', min: 0, max: 6),
                  OscPathSegment(
                    segment: 'y_freeze',
                    child: const _ToggleWidget(label: 'Y Freeze'),
                  ),
                  OscPathSegment(
                    segment: 'c_freeze',
                    child: const _ToggleWidget(label: 'C Freeze'),
                  ),
                ],
              ),
            )),
            (span: 1, child: Panel(
              title: 'Genlock',
              child: Wrap(
                spacing: t.sm,
                runSpacing: t.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _knob(label: 'H Delay', oscAddress: 'gen_dlyH', min: -500, max: 500, isBipolar: true),
                  _knob(label: 'V Delay', oscAddress: 'gen_dlyV', min: -100, max: 100, isBipolar: true),
                  _knob(label: 'Hyst',    oscAddress: 'gen_hyst',  min: 0, max: 1000, initial: 32, defaultValue: 32),
                  _intDropdown(label: 'Fine Mode', options: _genFineModeLabels, oscAddress: 'gen_fine', width: 120),
                ],
              ),
            )),
          ]),
          // Row 3: Rect Copy (GAC blitter) — live tile grid from a source rect
          GridRow(columns: 3, gutter: t.md, cells: [
            (span: 3, child: Panel(
              title: 'Rect Copy',
              child: Wrap(
                spacing: t.sm,
                runSpacing: t.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OscPathSegment(
                    segment: 'gac_enable',
                    child: const _ToggleWidget(label: 'Enable'),
                  ),
                  _knob(label: 'From X',  oscAddress: 'gac_x',    min: 0, max: 1912, initial: 896),
                  _knob(label: 'From Y',  oscAddress: 'gac_y',    min: 0, max: 1072, initial: 476),
                  _knob(label: 'Size',    oscAddress: 'gac_size', min: 8, max: 512,  initial: 128),
                  _knob(label: 'Grid',    oscAddress: 'gac_grid', min: 1, max: 16,   initial: 4),
                  _knob(label: 'Shear In',  oscAddress: 'gac_shear_src', min: -192, max: 192, isBipolar: true),
                  _knob(label: 'Shear Out', oscAddress: 'gac_shear_dst', min: -192, max: 192, isBipolar: true),
                ],
              ),
            )),
          ]),
          // Row: Color Field (uniformity-correction grid; hardware exists
          // only on Send 1's output). Animated per-channel gain fields —
          // gains are darken-only (1023 = unity), so amplitudes tint by
          // attenuating the other channels.
          if (isSend1)
            GridRow(columns: 1, gutter: t.md, cells: [
              (span: 1, child: Panel(
                title: 'Color Field',
                child: Wrap(
                  spacing: t.sm,
                  runSpacing: t.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OscPathSegment(
                      segment: 'uc_enable',
                      child: const _ToggleWidget(label: 'Enable'),
                    ),
                    _intDropdown(
                      label: 'Basis',
                      options: _ucFxLabels,
                      oscAddress: 'uc_fx',
                      width: 110,
                    ),
                    _knob(label: 'Amount',  oscAddress: 'uc_amount', min: 0, max: 127,  initial: 127),
                    _knob(label: 'Amp R',   oscAddress: 'uc_amp_r',  min: -1023, max: 1023, isBipolar: true),
                    _knob(label: 'Amp G',   oscAddress: 'uc_amp_g',  min: -1023, max: 1023, isBipolar: true),
                    _knob(label: 'Amp B',   oscAddress: 'uc_amp_b',  min: -1023, max: 1023, isBipolar: true),
                    _knob(label: 'Freq',    oscAddress: 'uc_freq',   min: 10, max: 800,  initial: 100),
                    _knob(label: 'Angle',   oscAddress: 'uc_angle',  min: 0, max: 360),
                    _knob(label: 'Speed',   oscAddress: 'uc_speed',  min: -2000, max: 2000, isBipolar: true),
                    _knob(label: 'Center X', oscAddress: 'uc_cx',    min: 0, max: 1920, initial: 960),
                    _knob(label: 'Center Y', oscAddress: 'uc_cy',    min: 0, max: 1080, initial: 540),
                    _knob(label: 'Res',     oscAddress: 'uc_res',    min: 4, max: 63,   initial: 16),
                    _knob(label: 'Bias',    oscAddress: 'uc_bias',   min: 0, max: 1023, initial: 1023),
                  ],
                ),
              )),
            ]),
          // Row: Warp (MFC geometric distortion; Send 1 only). Keystone/shear
          // run on the homography path (7ms updates, frame-rate animatable);
          // barrel/lens run on the radial-LUT path (~170ms per update). The
          // two families are mutually exclusive — the last-touched knob's
          // family wins. Wobble animates corners (homography); Breathe/Roam
          // animate the lens (radial).
          if (isSend1)
            GridRow(columns: 1, gutter: t.md, cells: [
              (span: 1, child: Panel(
                title: 'Warp',
                child: Wrap(
                  spacing: t.sm,
                  runSpacing: t.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OscPathSegment(
                      segment: 'warp_enable',
                      child: const _ToggleWidget(label: 'Enable'),
                    ),
                    _knob(label: 'Key H',   oscAddress: 'warp_key_h',   min: -600, max: 600, isBipolar: true),
                    _knob(label: 'Key V',   oscAddress: 'warp_key_v',   min: -400, max: 400, isBipolar: true),
                    _knob(label: 'Shear X', oscAddress: 'warp_shear_x', min: -600, max: 600, isBipolar: true),
                    _knob(label: 'Shear Y', oscAddress: 'warp_shear_y', min: -400, max: 400, isBipolar: true),
                    _knob(label: 'Barrel',  oscAddress: 'warp_barrel',  min: -400, max: 400, isBipolar: true),
                    _knob(label: 'Zoom',    oscAddress: 'warp_zoom',    min: 400, max: 1600, initial: 1000),
                    _knob(label: 'Lens X',  oscAddress: 'warp_lens_x',  min: -960, max: 960, isBipolar: true),
                    _knob(label: 'Lens Y',  oscAddress: 'warp_lens_y',  min: -540, max: 540, isBipolar: true),
                    _knob(label: 'Radius',  oscAddress: 'warp_radius',  min: 0, max: 960),
                    _knob(label: 'Wobble',  oscAddress: 'warp_wobble',  min: 0, max: 200),
                    _knob(label: 'Breathe', oscAddress: 'warp_breathe', min: 0, max: 300),
                    _knob(label: 'Roam',    oscAddress: 'warp_roam',    min: 0, max: 500),
                    _knob(label: 'Speed',   oscAddress: 'warp_speed',   min: -2000, max: 2000, initial: 250, defaultValue: 250, isBipolar: true),
                  ],
                ),
              )),
            ]),
          // Row: Posterize (monitor zebra block; Send 1 output only).
          // Band editor: drag dividers to move thresholds, tap a band to
          // select, then set its type/colour below the strip.
          if (isSend1)
            GridRow(columns: 1, gutter: t.md, cells: [
              (span: 1, child: Panel(
                title: 'Posterize',
                child: const PosterEditor(),
              )),
            ]),
          // Row 4: Memory Control (2/3) | Output Mux (1/3)
          GridRow(columns: 3, gutter: t.md, cells: [
            (span: 2, child: Panel(
              title: 'Memory Control',
              child: Wrap(
                spacing: t.sm,
                runSpacing: t.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OscPathSegment(segment: 'addr_limit_disable', child: const _ToggleWidget(label: 'No Limits')),
                  _knob(label: 'Col Win', oscAddress: 'col_window', min: -1000, max: 1000, isBipolar: true),
                  _intDropdown(label: 'Bit Precision', options: _bitPrecisionLabels, oscAddress: 'bit_precision', width: 120),
                  _intDropdown(label: 'Map Mode', options: _mapModeLabels, oscAddress: 'map_mode', width: 120),
                  _intDropdown(label: 'Buf ID', options: _bufIdLabels, oscAddress: 'buf_id', width: 120),
                  _intDropdown(label: 'Y Buf Type', options: _bufTypeLabels, oscAddress: 'y_buf_type', width: 120),
                  _intDropdown(label: 'Cb Buf Type', options: _bufTypeLabels, oscAddress: 'cb_buf_type', width: 120),
                  _intDropdown(label: 'Cr Buf Type', options: _bufTypeLabels, oscAddress: 'cr_buf_type', width: 120),
                ],
              ),
            )),
            (span: 1, child: Panel(
              title: 'Output Mux',
              child: Wrap(
                spacing: t.sm,
                runSpacing: t.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _intDropdown(label: 'OutMux Mode', options: _outmuxModeLabels, oscAddress: 'outmux_mode', width: 130),
                  _intDropdown(label: 'OutMux Port', options: _outmuxPortLabels, oscAddress: 'outmux_port', width: 130),
                ],
              ),
            )),
          ]),
        ],
      ),
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
    final t = GridProvider.of(context);
    final isSet = (_value & (1 << bit)) != 0;
    return GestureDetector(
      onTap: () => _toggleBit(bit),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs),
        decoration: BoxDecoration(
          color: isSet ? const Color(0xFFFFF176) : const Color(0xFF2A2A2C),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSet ? const Color(0xFFFFF176) : Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: t.textLabel.copyWith(
            fontWeight: FontWeight.w700,
            color: isSet ? Colors.black : Colors.grey[300],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: t.xs, bottom: t.xs),
          child: Text(
            'Bit Swap',
            style: t.textLabel,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bitToggle('Y', 0),
            SizedBox(width: t.xs),
            _bitToggle('Cb', 1),
            SizedBox(width: t.xs),
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
    final t = GridProvider.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: t.xs, bottom: t.xs),
          child: Text(
            widget.label,
            style: t.textLabel,
          ),
        ),
        GestureDetector(
          onTap: () {
            final newValue = !_enabled;
            setState(() => _enabled = newValue);
            sendOsc(newValue ? 1 : 0);
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: t.md, vertical: t.xs),
            decoration: BoxDecoration(
              color: _enabled ? const Color(0xFFFF6B6B) : const Color(0xFF2A2A2C),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: _enabled ? const Color(0xFFFF6B6B) : Colors.grey[600]!,
                width: 1,
              ),
            ),
            child: Text(
              _enabled ? 'ON' : 'OFF',
              style: t.textLabel.copyWith(
                fontWeight: FontWeight.w700,
                color: _enabled ? Colors.white : Colors.grey[300],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
