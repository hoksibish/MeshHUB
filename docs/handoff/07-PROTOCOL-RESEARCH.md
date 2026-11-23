# Protocol Research and Open Verification Tasks

## Primary references (checked 2026-11-23)
- MeshCore companion protocol: https://github.com/meshcore-dev/MeshCore/blob/main/docs/companion_protocol.md
- MeshCore upstream source: https://github.com/meshcore-dev/MeshCore
- Meshtastic API and Python reference: https://python.meshtastic.org/
- Meshtastic SDK protocol notes: https://github.com/meshtastic/meshtastic-sdk/blob/main/docs/protocol.md
- Meshtastic firmware/docs: https://meshtastic.org/
- Flutter BLE package options (evaluate, do not preselect): https://pub.dev/packages/flutter_blue_plus ; https://pub.dev/packages/open_blue_plus ; https://pub.dev/packages/bluetooth_low_energy
- BlueZ Linux baseline: https://www.bluez.org/

## Verification order
1. Confirm exact current MeshCore 1.18.0 Companion BLE service/characteristic UUIDs, framing, command queue and asynchronous message dequeue behavior from source/spec.
2. Determine whether owner's Heltec build advertises Wi-Fi or is BLE-only; hardware Wi-Fi support does **not** guarantee firmware Wi-Fi companion mode.
3. Establish source-backed MeshCore command/response support matrix for settings, identity, channels, backups, GPS, diagnostics, message status, version.
4. Confirm Meshtastic BLE/TCP framing and protobuf schema versions; version adapters and test with firmware.
5. Test candidate Flutter Linux BLE stacks with BlueZ, pairing/PIN, discovery, notification, and reconnect. Review platform coverage and maintenance before choosing.
6. Establish single-owner connection constraints, multi-node concurrency and OS BLE background limits through evidence.
7. Confirm map data licensing for offline vector/raster tiles and DEM; specify size/expiry/caching policy.
8. Evaluate libraries for RF line-of-sight, Fresnel, link budget and propagation modeling; define accuracy caveats and reference test vectors.

## Capability matrix to maintain
Rows: adapter API feature. Columns: MeshCore BLE, MeshCore TCP, Meshtastic BLE, Meshtastic TCP, and per-OS platform status. Each cell: supported / unavailable / untested, minimum firmware, cited code/docs/test evidence.

## Technical caveats
- Generic BLE characteristic writes do not imply RF delivery.
- iOS BLE discovery and background scanning have OS limitations; guarantee only best-effort behavior.
- Firmware command availability changes by release; do not assume everything in upstream main exists on 1.18.0.
- Wi-Fi network availability and TCP service must be separately validated for each firmware build.
- Configuration backup formats may not be portable across protocols, devices, or firmware versions.
