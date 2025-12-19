# OSC Endpoint Reference

## Overview
The Scion firmware exposes its runtime controls via Open Sound Control (OSC) messages over UDP. Three program outputs ("sends") can be configured independently, input signal status is monitored in real time, and video pipeline parameters are driven directly from OSC writes. This document describes the public OSC surface so controller applications can interoperate reliably.

## Transport & Discovery
- **Protocol**: UDP on port `9000`. Each OSC datagram is processed immediately by the firmware.
- **Service discovery**: The firmware registers a DNS-SD/mDNS service of type `_scion._udp` in the `local` domain (see `scion_firmware/src/App/Src/osc_udp.c:12`). The instance name matches `CONFIG_NET_HOSTNAME` (default `scion`), so most networks will resolve the target as `scion.local:9000` without manual configuration.
- **IP addressing**: `setup_network()` requests a DHCP lease on the default interface. If no lease is obtained within 30 s, the interface falls back to `192.168.2.75/16` with gateway `192.168.2.1` (see `scion_firmware/src/App/Src/network.c:8`).
- **Client tracking**: Every inbound OSC datagram registers the sender as a client. Replies to read requests go back to the most recent sender; change notifications use the stored client list so multiple controllers stay in sync.

## OSC Conventions
- **Indexing**: Paths that contain `/input/{n}/…` and `/send/{n}/…` use 1-based indices (`n = 1‥3`).
- **Reads vs. writes**: Sending an address with no arguments performs a read. The firmware responds on the same address with the documented type tags. Supplying arguments writes into the live configuration, queues any necessary deferred hardware work, and echoes the new value to every other known client.
- **Booleans**: Boolean values are encoded as OSC typetags `T` (true) and `F` (false). Integer-backed switches use typetag `i` with values 0/1 when the hardware register expects numeric data.
- **Errors**: Invalid paths, type mismatches, or read/write violations emit `/error` with a descriptive string. Callers should subscribe to `/error` during development.
- **State dumps**: `/ack` returns an empty message immediately. `/sync` triggers a full refresh of every endpoint (except `/dac/*` and internal helpers); use it after connecting to hydrate a UI.
- **Notifications**: Background polling broadcasts link-status changes for inputs and output. Most setters publish to "other" clients after the write succeeds so multi-controller setups stay coherent.

## Endpoint Reference
The tables below list the active endpoints. "R" indicates read-only; "RW" permits writes. Unless noted otherwise, string values are case-insensitive.

### System & Timing
| Path | Dir | Type | Notes |
| --- | --- | --- | --- |
| `/ack` | R | `` | Presence check; replies immediately with an empty message. |
| `/sync` | R | `` | Broadcasts the current value of every endpoint to all clients, then emits `/ack`. |
| `/sync_mode` | RW | `s` | Select ADV7842 clocking: `LOCKED`, `COMPONENT`, or `EXTERNAL`. Writes are ignored if the requested mode matches the current setting. |
| `/clock_offset` | RW | `i` | Phase-offset applied to the MDIN video clock. Integer count as programmed in `config.clock_offset`. |
| `/block_nr` | RW | `i` | Enables block noise reduction (`0` = off, non-zero = on). The handler clamps to 0/1 before programming MDIN. |

### Input Monitoring (`/input/{1‥3}`)
All input endpoints are read-only snapshots maintained by the notifier poller.

| Path | Type | Meaning |
| --- | --- | --- |
| `/input/{n}/connected` | `T/F` | True when the ADV7842 receiver reports a stable clock. |
| `/input/{n}/resolution` | `s` | Active resolution as `HxV` (e.g. `1920x1080`). |
| `/input/{n}/framerate` | `f` | Frame rate in Hz (e.g. `59.94`). |
| `/input/{n}/colorspace` | `s` | Either `RGB` or `YUV`. |
| `/input/{n}/bit_depth` | `i` | Effective bit depth (8/10/12). |
| `/input/{n}/chroma_subsampling` | `s` | One of `4:4:4`, `4:2:2`, or `4:2:0`. |

### Output Format (`/output`)
The HDMI transmitter (MDIN_IO3) mirrors the analog path for timing. `/output/*` reports the active state and only the transmitter mode (colorspace/subsampling/bit depth) can be adjusted; resolution and frame rate always track the analog pipeline.

| Path | Dir | Type | Notes |
| --- | --- | --- | --- |
| `/output/connected` | R | `T/F` | Mirrors the live HDMI transmitter state. |
| `/output/resolution` | R | `s` | Current HDMI resolution (`WxH`). Reflects the active MDIN preset; writes are ignored. |
| `/output/framerate` | R | `f` | Current progressive frame rate in Hz. Mirrors the active transmitter timing. |
| `/output/colorspace` | RW | `s` | `RGB` or `YUV`. Selecting `RGB` forces `4:4:4` sampling. |
| `/output/bit_depth` | RW | `i` | TMDS bit depth request; values are clamped to 8/10/12 before applying deep-color settings. |
| `/output/chroma_subsampling` | RW | `s` | `4:4:4`, `4:2:2`, or `4:2:0`. Invalid strings raise `/error`; RGB output is always normalized to `4:4:4`. |

### Analog Output Format (`/analog_format`)
Analog settings drive the ADC and DAC pipeline only. HDMI output state remains untouched when these values change.

| Path | Dir | Type | Notes |
| --- | --- | --- | --- |
| `/analog_format/resolution` | RW | `s` | Parsed as `WxH`. Unknown formats select the closest supported MDIN preset and emit an `/error` warning. |
| `/analog_format/framerate` | RW | `f` | Frame rate in Hz; programs the ADC/DAC pipeline. |
| `/analog_format/colorspace` | RW | `s` | Accepts `YUV`, `RGB`, or `CUSTOM`. `CUSTOM` enables manual color-matrix programming. |
| `/analog_format/color_matrix` | RW | `9 × f` | Nine floats representing a 3×3 matrix in row-major order. Only applied when colorspace is `CUSTOM`; other modes ignore writes but still echo them to peers. |

### Send Routing & Geometry (`/send/{1‥3}`)
Each send corresponds to one MDIN channel. Geometry updates are deferred to the video task; expect a single-frame latency after writes.

| Path | Dir | Type | Notes |
| --- | --- | --- | --- |
| `/send/{n}/input` | RW | `i` | Selects which physical input feeds the send. Values are 1-based and are clamped to valid sources. |
| `/send/{n}/scaleX` | RW | `f` | Horizontal zoom factor. Values > 10 are treated as percentages (e.g. 125 → 1.25). ≤ 0 snaps back to 1.0. |
| `/send/{n}/scaleY` | RW | `f` | Vertical zoom factor with the same semantics as `scaleX`. |
| `/send/{n}/posX` | RW | `f` | Horizontal center position expressed as a normalized fraction of the source width (`0` = left, `1` = right). Values outside `[0,1]` are clamped by the scaler window logic. |
| `/send/{n}/posY` | RW | `f` | Vertical center position (`0` = top, `1` = bottom). |
| `/send/{n}/rotation` | RW | `f` | Rotation in degrees around the RPIVOT pivot. Only one send may maintain a non-zero rotation at a time; changing another send automatically clears the previous rotation. |

*(Texture controls are intentionally omitted.)*

### Send Picture Controls
Brightness, contrast, saturation, and hue are normalized floats stored in `config.send[{n}]`. Hardware programming multiplies brightness/contrast/saturation by 255 and converts hue to 0–255 MDIN units.

| Path | Dir | Type | Notes |
| --- | --- | --- | --- |
| `/send/{n}/brightness` | RW | `f` | 0.0 → darkest, 1.0 → brightest. Default 0.5. |
| `/send/{n}/contrast` | RW | `f` | 0.0 → flat, 1.0 → full contrast. Default 0.5. |
| `/send/{n}/saturation` | RW | `f` | 0.0 → grayscale, 1.0 → nominal saturation. Default 0.5. |
| `/send/{n}/hue` | RW | `f` | Degrees offset, mapped to MDIN hue space (−180° to +180° recommended). |
| `/send/{n}/lti` | RW | `T/F` | Toggle Luma Transient Improvement. |
| `/send/{n}/cti` | RW | `T/F` | Toggle Chroma Transient Improvement. |
| `/send/{n}/color_enhance` | RW | `T/F` | Enables the MDIN color enhancement block for that send. |

### Send Filters
Front NR, horizontal peaking, and vertical peaking expose the MDIN fixed-point coefficient registers. Values are translated to floats for convenience; refer to `docs/VideoFiltering.md` for design guidance.

**Front NR (noise reduction)**

| Path | Dir | Type | Notes |
| --- | --- | --- | --- |
| `/send/{n}/filter/front_nr/y/{0‥7}` | RW | `f` | 8-tap luma FIR coefficients. Round-trips through signed Q2.14. |
| `/send/{n}/filter/front_nr/c/{0‥3}` | RW | `f` | 4-tap chroma FIR coefficients (signed Q2.14). |
| `/send/{n}/filter/front_nr/enable_y` | RW | `T/F` | Enable Y channel filtering (bit 6 of `frontnr_reg`). |
| `/send/{n}/filter/front_nr/enable_c` | RW | `T/F` | Enable C channel filtering (bit 5). |
| `/send/{n}/filter/front_nr/bypass_y` | RW | `T/F` | Bypass Y filtering. |
| `/send/{n}/filter/front_nr/bypass_cb` | RW | `T/F` | Bypass Cb. |
| `/send/{n}/filter/front_nr/bypass_cr` | RW | `T/F` | Bypass Cr. |

**Horizontal peaking**

| Path | Dir | Type | Notes |
| --- | --- | --- | --- |
| `/send/{n}/filter/h_peak/coef/{0‥7}` | RW | `f` | Peaking coefficients (signed Q3.13). |
| `/send/{n}/filter/h_peak/gain` | RW | `f` | Gain scalar stored as (value × 64) in register bits 8..15. |
| `/send/{n}/filter/h_peak/gain_level_en` | RW | `T/F` | Level-dependent gain enable. |
| `/send/{n}/filter/h_peak/hact_sep` | RW | `T/F` | Separate handling across active video. |
| `/send/{n}/filter/h_peak/no_add` | RW | `T/F` | Disable additive blending. |
| `/send/{n}/filter/h_peak/reverse` | RW | `T/F` | Reverse peaking polarity. |
| `/send/{n}/filter/h_peak/cor_val` | RW | `i` | Coring value (stored in low bits of `hpeak_ctrl`). |
| `/send/{n}/filter/h_peak/sat_val` | RW | `i` | Saturation limit. |
| `/send/{n}/filter/h_peak/cor_half` | RW | `T/F` | Halve coring threshold. |
| `/send/{n}/filter/h_peak/cor_en` | RW | `T/F` | Enable coring. |
| `/send/{n}/filter/h_peak/sat_en` | RW | `T/F` | Enable saturation limiter. |
| `/send/{n}/filter/h_peak/enable` | RW | `T/F` | Toggle the horizontal peaking block. |
| `/send/{n}/filter/h_peak/gain_slope` | RW | `i` | Gain slope register (0–255). |
| `/send/{n}/filter/h_peak/gain_thres` | RW | `i` | Gain threshold register. |
| `/send/{n}/filter/h_peak/gain_offset` | RW | `i` | Gain offset register. |

**Vertical peaking**

| Path | Dir | Type | Notes |
| --- | --- | --- | --- |
| `/send/{n}/filter/v_peak/enable` | RW | `T/F` | Toggle the vertical peaking block. |
| `/send/{n}/filter/v_peak/gain` | RW | `f` | Gain value (stored as gain × 64 in `vpeak_ctrl`). |
| `/send/{n}/filter/v_peak/gain_div` | RW | `i` | Gain divisor bits 0..3. |
| `/send/{n}/filter/v_peak/v_dly` | RW | `i` | Vertical delay (0–255). |
| `/send/{n}/filter/v_peak/h_dly` | RW | `i` | Horizontal delay (0–255). |
| `/send/{n}/filter/v_peak/gain_clip_low` | RW | `f` | Lower clip threshold (unsigned Q0.12). |
| `/send/{n}/filter/v_peak/gain_clip_high` | RW | `f` | Upper clip threshold (unsigned Q0.12). |
| `/send/{n}/filter/v_peak/out_clip_low` | RW | `f` | Output clamp low (unsigned Q0.12). |
| `/send/{n}/filter/v_peak/out_clip_high` | RW | `f` | Output clamp high (unsigned Q0.12). |

### Send LUTs
| Path | Dir | Type | Notes |
| --- | --- | --- | --- |
| `/send/{n}/lut/R` | RW | `32 × f` | 16 control points (x,y pairs) for the red channel. Reads always return 32 floats (16 pairs) with inactive points reported as `-1`. Writes accept any even number of floats up to 32; unspecified points are cleared. Values are clamped to `[0,1]` before building the 16-bit LUT. |
| `/send/{n}/lut/G` | RW | `32 × f` | Green channel LUT, same rules. |
| `/send/{n}/lut/B` | RW | `32 × f` | Blue channel LUT, same rules. |

Y-channel LUTs are not supported; attempting to access `/send/{n}/lut/Y` returns `/error`.

### Output LUT
| Path | Dir | Type | Notes |
| --- | --- | --- | --- |
| `/output/lut/R` | RW | `32 × f` | 16 control points (x,y pairs) for the red channel feeding the ADC (MDIN_IO4) → HDMI (MDIN_IO3) path via MDIN_CH3. Reads always return 32 floats with inactive points as `-1`; writes accept even counts up to 32 and clamp to `[0,1]` before building the 16-bit LUT. |
| `/output/lut/G` | RW | `32 × f` | Green channel LUT, same semantics as the red channel. |
| `/output/lut/B` | RW | `32 × f` | Blue channel LUT, same semantics as the red channel. |

### Send Histograms
| Path | Dir | Type | Notes |
| --- | --- | --- | --- |
| `/send/{n}/histogram/Y` | R | `b` | Returns a 512-byte OSC blob containing 256 big-endian uint16 bins for the Y waveform monitor.
| `/send/{n}/histogram/R` | R | `b` | Histogram of the red channel.
| `/send/{n}/histogram/G` | R | `b` | Histogram of the green channel.
| `/send/{n}/histogram/B` | R | `b` | Histogram of the blue channel.

Histograms are read-only and drive the waveform processor automatically on first access. Subsequent reads within the same session update in place.

## Discovery & Integration Checklist
1. Resolve the board via mDNS (`_scion._udp`) and open a UDP socket to port 9000.
2. Send `/ack` to confirm connectivity, then send `/sync` to hydrate controller state.
3. Subscribe to `/error` and any `/input/*` notifications required by the UI. The notifier broadcasts link-state changes automatically.
4. Issue configuration writes as needed. Remember that writes are echoed only to *other* clients; the writer already knows the new value.
5. Re-run `/sync` after reconnecting or if you suspect desynchronization.

## Omitted Controls
Texture operations and the `/dac/*` tree are intentionally excluded from this reference. Those endpoints remain internal/experimental and may change without notice.
