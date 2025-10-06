# SCION Controller (Flutter)

A desktop-first Flutter app to control a SCION device over OSC (Open Sound Control). It provides a UI for configuring inputs, sends, return path, and controls over shape, color & texture; shows live system status; logs OSC traffic; and lets you save/load configuration snapshots.

## Highlights

- OSC-first UI: widgets send and receive OSC in real time via a small set of mixins and helpers
- Simple address composition: build hierarchical OSC paths using lightweight `OscPathSegment` wrappers
- Central registry: tracks current values, dispatches listeners, and persists configuration
- Network discovery and connection UX: connect by host/port or discover via mDNS/DNS‑SD
- Rich OSC logging: filter by status/direction with address grouping

## App Structure

- Shell and routing
  - `lib/main.dart:1` Application entry, navigation rail, and page wiring
  - `lib/status_bar.dart:1` Connection status with subtle flashing on disconnect

- Networking
  - `lib/network.dart:16` UDP/OSC client. Sends messages, receives packets, dispatches to the registry, and manages a lightweight `/sync`→`/ack` handshake to mark a connection as “ready”
  - `lib/network_selection.dart:1` Connect UI with recent endpoints, typeahead, and discovery
  - `lib/nsd_client.dart:1` mDNS/DNS‑SD (nsd) discovery wrapper

- OSC plumbing
  - `lib/osc_widget_binding.dart:16` `OscPathSegment` and `OscAddressMixin` for composing addresses and wiring widgets to OSC send/receive and logging
  - `lib/osc_registry.dart:45` `OscRegistry` manages known addresses, current values, and listener callbacks; also handles save/load of nested JSON
  - `lib/osc_log.dart:1` Log viewer with status/direction filters and address grouping
  - `lib/osc_registry_viewer.dart:1` Introspection view of the live registry

- Pages and controls
  - `lib/setup_page.dart:1`, `lib/system_overview.dart:1`, `lib/system_overview_tiles.dart:1` Overview of inputs/sends/return/output with animated field updates
  - `lib/send_page.dart:1` Three “Send” pages composed from OSC‑aware controls
  - `lib/dac_parameters.dart:1` DAC and related parameter panels
  - `lib/video_format_selection.dart:1`, `lib/sync_mode_selection.dart:1` Format and sync controls
  - Common OSC controls: `lib/numeric_slider.dart:1`, `lib/osc_checkbox.dart:1`, `lib/osc_number_field.dart:1`, `lib/osc_dropdown.dart:1`, `lib/osc_value_dropdown.dart:1`, `lib/osc_radiolist.dart:1`
  - Utilities: `lib/labeled_card.dart:1` (section framing and network disabling), plus related helpers

## OSC Architecture

- Address composition with `OscPathSegment`
  - Wrap any subtree with `OscPathSegment(segment: 'part')` to contribute a path segment
  - Nested segments are joined from root to leaf to form the full OSC address prefix
  - Example: in `lib/send_page.dart:27`, a subtree is wrapped with `segment: 'send/<n>'`, and a child control wrapped with `segment: 'brightness'` produces `/send/1/brightness`

- Widget binding with `OscAddressMixin`
  - Add `with OscAddressMixin` to a `State<T>` class to auto‑wire it to OSC
  - On first build, the mixin resolves the full address from surrounding `OscPathSegment`s and registers it in the `OscRegistry` (`lib/osc_widget_binding.dart:47` → `:58`)
  - Implement `OscStatus onOscMessage(List<Object?> args)` to handle inbound values and update widget state (`lib/osc_widget_binding.dart:143`)
  - Use `sendOsc(value, address: 'optional/subpath')` to send; if `address` starts with `/` it is treated as absolute, otherwise it is appended to the widget’s resolved `oscAddress` (`lib/osc_widget_binding.dart:83` → `:87`)

- Central dispatch with `OscRegistry`
  - Maintains a map of `address → OscParam(currentValue, listeners, notifier)`; listeners are invoked on dispatch (`lib/osc_registry.dart:12`, `:26`)
  - New widgets call `registerAddress` once; listeners can be registered before the address exists and are flushed on first registration (`lib/osc_registry.dart:54` → `:69`, `:75` → `:84`)
  - `Network` decodes incoming OSC and calls `OscRegistry.dispatch(address, args)` to fan out to listeners (`lib/network.dart:156`, `lib/osc_registry.dart:92`)

- Logging
  - Outbound sends happen immediately; log emission is coalesced at ~20 Hz to keep the UI responsive (`lib/osc_widget_binding.dart:71` → `:107`)
  - All inbound and outbound messages flow into `OscLogTable` via a global key (`lib/osc_log.dart:9`)

## Saving and Loading Configuration

- Save: `OscRegistry.saveToFile(path)` writes a nested JSON object reflecting the current values at each registered address, splitting on `/` to create nested maps (`lib/osc_registry.dart:126`)
- Load: `OscRegistry.loadFromFile(path)` reads the nested JSON, reconstructs addresses, and dispatches values so bound widgets update (`lib/osc_registry.dart:149`)

## Adding OSC‑Bound Controls

- Place segments for the address prefix where it makes sense:
  - Example: `OscPathSegment(segment: 'send/2')` … then deeper `OscPathSegment(segment: 'color')`
- In your control’s `State`, mix in `OscAddressMixin` and implement `onOscMessage` to parse and apply incoming values
- Call `sendOsc(value)` when the user changes the control
- For nested fields, you can supply a relative subpath: `sendOsc(value, address: 'gain')`
- For absolute paths, bypass segments entirely: see `AbsoluteOscCheckbox` (`lib/send_texture.dart:12`)

## Networking Details

- Connect via the field in the left rail or use discovery
  - Default port is `9000` unless specified in `host:port` form (`lib/network_selection.dart:75`)
- The connection is marked ready after a `/sync`→`/ack` round‑trip; sends are ignored (except `/sync`) until then (`lib/network.dart:33`, `:82`, `:120`)

## Running Locally

- Prereqs: Flutter (see `./startup.sh`), and the local `osc` Dart package referenced in `pubspec.yaml`
- Desktop: `flutter run -d macos` (or `windows`/`linux`), Mobile: `flutter run -d <device>`

## Notes

- The File “Reset to defaults” action is currently a placeholder (`lib/file_selection.dart:66`)
- When adding new widgets, prefer `OscPathSegment` + `OscAddressMixin` for relative paths; use absolute addresses only when the UI element truly maps to a global path
