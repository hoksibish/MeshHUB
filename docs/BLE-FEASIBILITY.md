# Milestone 0 — Linux BLE feasibility

**Environment:** Omarchy 4.5.0 / Linux 7.2.15-1-omarchy, BlueZ 5.87, one powered Bluetooth controller. No Heltec was paired, configured, or transmitted through MeshCore.

## Reproducible observations

- `bluetoothctl --version` → `5.87`; `systemctl is-active bluetooth` → `active`; `bluetoothctl list` → one controller.
- `bluetoothctl --timeout 8 scan le` completed successfully and started discovery. The redacted scan output did **not** show a MeshCore service UUID or name. Nearby device identifiers were not recorded in this report. This proves a Linux BLE scan works, **not** that the owner's Heltec is connected or even powered nearby.
- A temporary Dart probe using `bluez: 0.9.0` connected to the system BlueZ D-Bus service, counted one adapter and three known device records, and closed cleanly. It did not pair, discover GATT services, subscribe to notifications, or access message payloads. Probe code was discarded from the repository after the experiment.
- The official MeshCore `companion-v1.18.0` tag documents BLE service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`, RX `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`, and TX `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` characteristics. Those are **source-documented**, not confirmed on this physical Heltec. The upstream guide warns that it may contain inaccuracies; validate against the device and firmware before M1 integration.

## Candidate integration and remaining gate

- `bluez` 0.9.0 (MPL-2.0) works as a Linux-only D-Bus client in a Dart process here; assess discovery, pairing, GATT notification streams, and licensing obligations before selecting it for the app.
- `bluetooth_low_energy` 6.2.1 (MIT) declares Linux plus iOS/Android/macOS/Windows plugin platforms; cross-platform declaration is **not** proof of MeshCore pairing/notification behavior. Compare on real hardware at M1.
- No BLE plugin is wired into MeshHub's UI yet. Fallback for M1: keep the mock app functional while validating a thin Linux BlueZ bridge. Do not assert send/receive or automatic reconnection until hardware tests BLE-01 through BLE-07 and MSG-01 through MSG-04 pass.

## Primary sources

- MeshCore 1.18.0 protocol: https://github.com/meshcore-dev/MeshCore/blob/companion-v1.18.0/docs/companion_protocol.md
- BlueZ package and license: https://pub.dev/packages/bluez ; https://pub.dev/packages/bluez/license
- Cross-platform candidate: https://pub.dev/packages/bluetooth_low_energy ; https://pub.dev/packages/bluetooth_low_energy/license
- Flutter Linux setup: https://docs.flutter.dev/get-started/install/linux/desktop
