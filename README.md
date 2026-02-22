# SCION Controller

Flutter desktop app for controlling SCION video hardware over OSC. 

## What it does

Left nav rail with seven sections: System, Send 1–3, Return, Setup, and OSC Log. The rail also holds network connection controls and file actions (Save, Save As, Load, Reset to defaults).

**System** — hardware status overview, video format selection, sync settings.

**Send 1–3** — three independent send pipelines, all built from the same widget. Each one has source selection, shape/texture/text controls, color grading, glitch, and DAC parameters.

**Return** — output format display, ADC adjustment (DE window, sync, phase/LLC), and color grading for the return path.

**Setup** — network config (DHCP or static IP) and firmware update.

**OSC Log** — live inbound/outbound OSC traffic with filtering and grouping.

## How OSC binding works

Controls bind to OSC addresses through a composable tree of `OscPathSegment` wrappers. Each segment contributes one level of the path, so you can build `/send/1/color/hue` just by nesting widgets. `OscAddressMixin` lets any widget state register, send, and receive on its resolved address. `OscRegistry` holds current values and handles config serialization. `Network` handles the actual UDP send/receive and feeds decoded messages into the registry.

## Networking

Supports both direct host/port entry and automatic device discovery via mDNS/DNS-SD. Connection handshake is `/sync` → `/ack`.

## Config files

Save/load/reset in the sidebar. Reset sends `/config/reset` after a confirmation dialog. The file format is handled by `OscRegistry` — it serializes the full address/value map.

## Running it

You need the Flutter SDK and the local `osc` Dart package (referenced in `pubspec.yaml`, from `https://github.com/i2pi/osc`).

```
flutter run -d macos
flutter run -d windows
flutter run -d linux
flutter run -d <device-id>   # iOS
```

## Docs

Specs and API notes are in `docs/`.
