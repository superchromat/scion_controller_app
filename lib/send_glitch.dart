import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'osc_dropdown.dart';
import 'osc_registry.dart';
import 'grid.dart';
import 'panel.dart';

/// Glitch effects controls for pixel bus bit and channel ordering.
///
/// Controls:
/// - Channel Swap: Y/Cb/Cr channel swapping with optional MSB/LSB bit swap (0-7)
/// - Bit Swap: Per-component bit order swap for Y, Cb, Cr (0-7 bitmask)
/// - Stride Offset: Diagonal tearing effect via SDRAM column offset
/// - OutMux Mode: Pixel packing format on output bus (0-32)
/// - OutMux Port: Virtual to display port mapping (0-5)
class SendGlitch extends StatefulWidget {
  /// Which send page this instance lives on (1-3). The Rect Copy, Color
  /// Field and Warp panels only exist for Send 1's hardware.
  final int pageNumber;

  const SendGlitch({super.key, this.pageNumber = 0});

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
      'valid_lines', 'rows_per_frame', 'col_window',
      'gen_dlyH', 'gen_dlyV',
      'outmux_port', 'write_ffc_map', 'mfc_read_buf',
      'y_buf_type',
      'even_odd_swap', 'cbcr_swap',
      'gac_enable', 'gac_shear_src', 'gac_shear_dst',
      // WMC / frame-pointer corruption glitches
      'mirror_x', 'mirror_y', 'mirror_off_x', 'mirror_off_y', 'shear_x',
      'line_jump', 'line_init', 'dmem_y', 'dmem_cb', 'dmem_cr',
      'fid_inv', 'fid_force', 'si2_h', 'si2_hoff', 'si2_v', 'si2_voff',
      'cap_x', 'cap_y', 'wr_delay_v', 'wr_delay_h', 'skip_mode', 'skip_count',
    ]) {
      _set(seg, 0);
    }
    _set('mirror_mask', 8191);
    _set('mirror_clamp', 8191);
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
    for (final seg in [
      'warp_enable',
      'warp_key_h',
      'warp_key_v',
      'warp_shear_x',
      'warp_shear_y',
      'warp_barrel',
      'warp_lens_x',
      'warp_lens_y',
      'warp_radius',
      'warp_wobble',
      'warp_breathe',
      'warp_roam',
      'warp_field',
      'warp_famp'
    ]) {
      _set(seg, 0);
    }
    _set('warp_zoom', 1000);
    _set('warp_speed', 250);
    _set('warp_ffreq', 300);
    // Color Field defaults (Send 1 only; firmware reset doesn't know UC)
    sendOsc(0, address: 'glitch/uc_enable');
    sendOsc(0, address: 'glitch/uc_fx');
    for (final seg in [
      'uc_enable',
      'uc_fx',
      'uc_amp_r',
      'uc_amp_g',
      'uc_amp_b',
      'uc_angle',
      'uc_speed'
    ]) {
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
    'Normal', // 0: Y<=Y, Cb<=Cb, Cr<=Cr
    'Y/Cb', // 1: Y<=Cb, Cb<=Y, Cr<=Cr
    'Y/Cr', // 2: Y<=Cr, Cb<=Cb, Cr<=Y
    'Cb/Cr', // 3: Y<=Y, Cb<=Cr, Cr<=Cb
    'Bit Swap', // 4: MSB<->LSB + normal
    'Bit + Y/Cb', // 5: MSB<->LSB + Y↔Cb
    'Bit + Y/Cr', // 6: MSB<->LSB + Y↔Cr
    'Bit + Cb/Cr', // 7: MSB<->LSB + Cb↔Cr
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
    final def = defaultValue ?? initial;
    return OscPathSegment(
      segment: oscAddress,
      child: OscRotaryKnob(
        label: label,
        minValue: min,
        maxValue: max,
        initialValue: initial,
        defaultValue: def,
        format: format,
        isBipolar: isBipolar,
        preferInteger: true,
        size: t?.knobMd ?? 60,
        labelStyle: t?.textLabel,
        // Detent at the default position (region scales with the knob range).
        snapConfig: SnapConfig(
          snapPoints: [def],
          snapRegionHalfWidth: (max - min) * 0.02,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    return OscPathSegment(
      segment: 'glitch',
      child: CardColumn(
        children: [
          // A 12-column grid with spans matched to each panel's control count,
          // so every panel fills its width in ~1 row. equalHeight:false keeps
          // panels at natural height (no stretching into dead space).
          // Row 1: Frame Buffer | MFC — the two widest panels.
          GridRow(columns: 12, equalHeight: false, cells: [
            (
              span: 5,
              child: Panel(
                title: 'Frame Buffer',
                // Wrap (not a fixed 8-wide Row) so it flows to 2 rows at this
                // span, matching MFC's height — no dead space beneath it.
                child: Wrap(
                  spacing: t.sm,
                  runSpacing: t.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _knob(
                        label: 'Stride',
                        oscAddress: 'stride_offset',
                        min: -50,
                        max: 50,
                        isBipolar: true),
                    _knob(
                        label: 'Row Ofs',
                        oscAddress: 'row_offset',
                        min: -500,
                        max: 500,
                        isBipolar: true),
                    _knob(
                        label: 'Addr Ofs',
                        oscAddress: 'addr_offset',
                        min: -1000,
                        max: 1000,
                        isBipolar: true),
                    _knob(
                        label: 'FFC Map',
                        oscAddress: 'write_ffc_map',
                        min: 0,
                        max: 7),
                    _knob(
                        label: 'MFC Buf',
                        oscAddress: 'mfc_read_buf',
                        min: 0,
                        max: 7,
                        initial: 0),
                    _knob(
                        label: 'Wr Addr',
                        oscAddress: 'write_addr_offset',
                        min: -65535,
                        max: 65535,
                        isBipolar: true),
                    _knob(
                        label: 'Wr Phase',
                        oscAddress: 'write_phase',
                        min: 0,
                        max: 6),
                    _knob(
                        label: 'Row Rpt',
                        oscAddress: 'row_repeat',
                        min: 0,
                        max: 2160),
                  ],
                ),
              )
            ),
            (
              span: 7,
              child: Panel(
                title: 'MFC',
                // Write-offset corruption: Off X/Y shift where each captured line
                // lands in DDR (works with the flip OFF — tearing/wrap). Shear =
                // sub-word horizontal shear; Line Jump = vertical decimation
                // (venetian-blind). Mask/Clamp shape the offset.
                child: Wrap(
                  spacing: t.sm,
                  runSpacing: t.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _knob(
                        label: 'Valid Lns',
                        oscAddress: 'valid_lines',
                        min: -30,
                        max: 30,
                        isBipolar: true),
                    OscPathSegment(
                        segment: 'mirror_x',
                        child: const _ToggleWidget(label: 'Mirror X')),
                    OscPathSegment(
                        segment: 'mirror_y',
                        child: const _ToggleWidget(label: 'Mirror Y')),
                    _knob(
                        label: 'Off X',
                        oscAddress: 'mirror_off_x',
                        min: -8191,
                        max: 8191,
                        isBipolar: true),
                    _knob(
                        label: 'Off Y',
                        oscAddress: 'mirror_off_y',
                        min: -8191,
                        max: 8191,
                        isBipolar: true),
                    _knob(
                        label: 'Shear', oscAddress: 'shear_x', min: 0, max: 15),
                    _knob(
                        label: 'Line Jump',
                        oscAddress: 'line_jump',
                        min: 0,
                        max: 31),
                    _knob(
                        label: 'Line Init',
                        oscAddress: 'line_init',
                        min: 0,
                        max: 31),
                    _knob(
                        label: 'Mask',
                        oscAddress: 'mirror_mask',
                        min: 0,
                        max: 8191,
                        initial: 8191,
                        defaultValue: 8191),
                    _knob(
                        label: 'Clamp',
                        oscAddress: 'mirror_clamp',
                        min: 0,
                        max: 8191,
                        initial: 8191,
                        defaultValue: 8191),
                  ],
                ),
              )
            ),
          ]),
          // Row 2: Memory Control | Genlock + Temporal (merged timing panel).
          // Equal height so Memory Control matches Genlock / Temporal.
          GridRow(columns: 12, equalHeight: true, cells: [
            (
              span: 6,
              child: Panel(
                title: 'Memory Control',
                child: Wrap(
                  spacing: t.sm,
                  runSpacing: t.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OscPathSegment(
                        segment: 'addr_limit_disable',
                        child: const _ToggleWidget(label: 'No Limits')),
                    _knob(
                        label: 'Col Win',
                        oscAddress: 'col_window',
                        min: -1000,
                        max: 1000,
                        isBipolar: true),
                    _intDropdown(
                        label: 'Bit Precision',
                        options: _bitPrecisionLabels,
                        oscAddress: 'bit_precision',
                        width: 110),
                    _intDropdown(
                        label: 'Map Mode',
                        options: _mapModeLabels,
                        oscAddress: 'map_mode',
                        width: 110),
                    _intDropdown(
                        label: 'Buf ID',
                        options: _bufIdLabels,
                        oscAddress: 'buf_id',
                        width: 90),
                    // Buf-type dropdowns show short values ("0: Y"), so they pack
                    // narrow — keeps Memory Control at 2 rows to match Genlock.
                    _intDropdown(
                        label: 'Y Buf Type',
                        options: _bufTypeLabels,
                        oscAddress: 'y_buf_type',
                        width: 74),
                    _intDropdown(
                        label: 'Cb Buf Type',
                        options: _bufTypeLabels,
                        oscAddress: 'cb_buf_type',
                        width: 78),
                    _intDropdown(
                        label: 'Cr Buf Type',
                        options: _bufTypeLabels,
                        oscAddress: 'cr_buf_type',
                        width: 78),
                  ],
                ),
              )
            ),
            (
              span: 6,
              child: Panel(
                // Genlock + both former "Temporal" panels merged into one.
                title: 'Genlock / Temporal',
                child: Wrap(
                  spacing: t.sm,
                  runSpacing: t.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _knob(
                        label: 'H Delay',
                        oscAddress: 'gen_dlyH',
                        min: -500,
                        max: 500,
                        isBipolar: true),
                    _knob(
                        label: 'V Delay',
                        oscAddress: 'gen_dlyV',
                        min: -100,
                        max: 100,
                        isBipolar: true),
                    _knob(
                        label: 'Hyst',
                        oscAddress: 'gen_hyst',
                        min: 0,
                        max: 1000,
                        initial: 32,
                        defaultValue: 32),
                    _intDropdown(
                        label: 'Fine Mode',
                        options: _genFineModeLabels,
                        oscAddress: 'gen_fine',
                        width: 120),
                    _knob(
                        label: 'Frame Dly',
                        oscAddress: 'frame_delay',
                        min: 0,
                        max: 6),
                    // Y Freeze only: the chip can't chroma-freeze scaled (2D-mapped)
                    // video, so a "C Freeze" toggle would be a dead control.
                    OscPathSegment(
                        segment: 'y_freeze',
                        child: const _ToggleWidget(label: 'Freeze')),
                    _intDropdown(
                        label: 'Skip',
                        options: const ['Off', 'Overwrite', 'Skip'],
                        oscAddress: 'skip_mode',
                        width: 120),
                    _knob(
                        label: 'Skip Count',
                        oscAddress: 'skip_count',
                        min: 0,
                        max: 255),
                  ],
                ),
              )
            ),
          ]),
          // Row 3: Planar / Field | Roll / Tear | Output Mux | Pixel Bus.
          // Equal height so Output Mux & Pixel Bus match Roll / Tear &
          // Planar / Field.
          GridRow(columns: 12, equalHeight: true, cells: [
            (
              span: 5,
              child: Panel(
                title: 'Planar / Field',
                child: Wrap(
                  spacing: t.sm,
                  runSpacing: t.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OscPathSegment(
                        segment: 'dmem_y',
                        child: const _ToggleWidget(label: 'Y Bank')),
                    OscPathSegment(
                        segment: 'dmem_cb',
                        child: const _ToggleWidget(label: 'Cb Bank')),
                    OscPathSegment(
                        segment: 'dmem_cr',
                        child: const _ToggleWidget(label: 'Cr Bank')),
                    OscPathSegment(
                        segment: 'fid_inv',
                        child: const _ToggleWidget(label: 'Field Inv')),
                    _knob(
                        label: 'Field Force',
                        oscAddress: 'fid_force',
                        min: 0,
                        max: 3),
                    _knob(label: '2SI H', oscAddress: 'si2_h', min: 0, max: 3),
                    OscPathSegment(
                        segment: 'si2_hoff',
                        child: const _ToggleWidget(label: '2SI HOff')),
                    _knob(label: '2SI V', oscAddress: 'si2_v', min: 0, max: 3),
                    OscPathSegment(
                        segment: 'si2_voff',
                        child: const _ToggleWidget(label: '2SI VOff')),
                  ],
                ),
              )
            ),
            (
              span: 3,
              child: Panel(
                title: 'Roll / Tear',
                child: Wrap(
                  spacing: t.sm,
                  runSpacing: t.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _knob(
                        label: 'Cap X', oscAddress: 'cap_x', min: 0, max: 8191),
                    _knob(
                        label: 'Cap Y', oscAddress: 'cap_y', min: 0, max: 8191),
                    _knob(
                        label: 'Wr Dly V',
                        oscAddress: 'wr_delay_v',
                        min: 0,
                        max: 31),
                    _knob(
                        label: 'Wr Dly H',
                        oscAddress: 'wr_delay_h',
                        min: 0,
                        max: 255),
                  ],
                ),
              )
            ),
            (
              span: 2,
              child: Panel(
                title: 'Output Mux',
                child: Wrap(
                  spacing: t.sm,
                  runSpacing: t.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _intDropdown(
                        label: 'OutMux Mode',
                        options: _outmuxModeLabels,
                        oscAddress: 'outmux_mode',
                        width: 120),
                    _intDropdown(
                        label: 'OutMux Port',
                        options: _outmuxPortLabels,
                        oscAddress: 'outmux_port',
                        width: 120),
                  ],
                ),
              )
            ),
            (
              span: 2,
              child: Panel(
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
                        width: 120),
                    _bitSwapControl(),
                  ],
                ),
              )
            ),
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
              color:
                  _enabled ? const Color(0xFFFF6B6B) : const Color(0xFF2A2A2C),
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
