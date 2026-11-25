# MeshHub Linux M1 field-test build

The **Radios** panel can discover/select a paired MeshCore device, perform an authenticated GATT/Companion handshake, display read-only device metadata, receive messages into volatile memory, and prepare guarded channel/direct test sends. The **Inbox** has a simulation toggle and labels live versus sample data. No real history is written to disk; MeshCore RF receipt/delivery still needs a second endpoint. See `../../FIELD-TEST.md` before field use.

## Omarchy setup

The first verified build used Flutter **3.50.1** (Dart **3.14.0**) from the official Linux stable archive, with its SHA-256 checked against Flutter's release metadata. Flutter is installed at `~/.local/share/flutter-sdk`; CMake 4.4.5 and Ninja 1.13.2 were installed under `~/.local/bin` with `uv tool install cmake` and `uv tool install ninja`. GTK 3, Clang and pkg-config were already present.

```bash
export PATH="$HOME/.local/share/flutter-sdk/bin:$HOME/.local/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true
cd ~/MeshHUB/packages/meshhub_domain
flutter pub get
flutter analyze
flutter test
cd ~/MeshHUB/apps/meshhub_flutter
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build linux --release
cd ~/MeshHUB
./run-field-test.sh --check
./run-field-test.sh
```

The built binary is at `build/linux/x64/release/bundle/meshhub_flutter`. The `bundle/` directory (not only the executable) is required to run the release app. For a noninteractive shell on this Omarchy session, `WAYLAND_DISPLAY=wayland-1` and `DISPLAY=:0` were needed to launch a window; normal graphical terminals inherit those automatically.

## Firmware Manager — offline hardware catalog and USB flashing

Open **Radios → Firmware Manager → Open**. The hardware selector is bundled with MeshHub and is populated from snapshots of the official MeshCore and Meshtastic flasher catalogs:

- MeshCore: `meshcore-dev/flasher.meshcore.io/config.json` — only the open-source community MeshCore firmware entries are indexed, not separately licensed third-party firmware.
- Meshtastic: `meshtastic/web-flasher/public/data/hardware-list.json` — actively supported physical-device targets.
- Snapshot: `apps/meshhub_flutter/assets/firmware_hardware_catalog.json` — **152 board entries** at the time of import (58 MeshCore, 94 Meshtastic). These are not refreshed automatically; check the publisher's current site for newly added devices or retired builds.

The manager can **select an exact supported hardware model, inspect a board-matched firmware release, calculate SHA-256, compare a supplied publisher checksum and save the firmware bytes for offline use**. A file-name and ESP image/UF2/ZIP header check are basic safeguards, not firmware signature validation or a guarantee that the board's pinout, LoRa radio or bootloader match. Independently verify model, exact hardware revision, role, frequency variant, official release source, and a trusted checksum/signature when supplied.

### Flashing modes

| Hardware / firmware format | MeshHub operation |
| --- | --- |
| ESP32-family boards with **known chip profiles** and official **merged MeshCore** or **factory Meshtastic** image | Integrated USB `esptool` flashing (explicit confirmation; correct chip/board selection required) |
| nRF52840 boards using board-specific `.uf2` firmware | Offline import/cache plus guided bootloader drag-and-drop instructions; **no automated copy or DFU** yet |
| RP2040 or other UF2 devices | Offline UF2 import/cache plus guided bootloader install instructions |
| nRF52 DFU ZIP images, unsupported chip variants or board bootloaders | Offline import/cache and manual vendor-specific installation guidance; USB flash button disabled |
| App-only `.bin`, update-only images, unsupported devices, ambiguous package formats | Rejected or unavailable; not automatically flashed |

A **supported hardware listing does not mean its automatic flashing backend is validated**. Selection must exactly match the official release's filename profile. Some devices require bootloader entry steps, external tools, UF2 drives, DFU packaging or board-specific partition layouts that cannot safely be inferred from the MCU name alone.

The initially verified hardware case was the owner's Heltec V3 running MeshCore Companion. Other MeshCore roles, Meshtastic factory builds, ESP32 variants and the guided UF2/DFU workflows still need a physical-device acceptance test.

### Linux prerequisites and usage

```bash
uv tool install esptool
esptool version
ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null
```

The executable `esptool` must be on MeshHub's PATH (often `$HOME/.local/bin`). The optional `zenity` picker can select `.bin`, `.uf2` and `.zip` files; otherwise paste an absolute path. Use normal USB serial permissions rather than running MeshHub with `sudo`.

The offline library is `~/.local/share/meshhub/firmware`. It retains content-addressed images, SHA-256 and nonsecret board metadata, and verifies the bytes before displaying them. Previous Heltec V3 cache manifests are still supported. It does not store device identities, channel keys or chat history.

For a supported **ESP32 direct-write target**, select the exact device and firmware file, verify the release and a trusted checksum if available, disconnect MeshHub's Bluetooth radio session, run **Check device (read-only)**, and review the matched chip model. The manager then rechecks the image and USB chip and invokes `esptool --chip CHIP --port PORT --baud 115200 write-flash 0x0 IMAGE` **once**, only after the explicit backup/target checkboxes and typed `FLASH` confirmation.

Optional **Erase all flash** is **off by default**. It may be necessary for some major upgrades or MeshCore ⇄ Meshtastic migrations and permanently deletes the old network identity, channel keys, contacts, pairing, RF configuration and other data. After independently backing up the device's identity/settings, opt in and type `ERASE` in the separate confirmation dialog. MeshHub never auto-erases or automatically retries interrupted writes.

**An accepted USB write is not proof of a successful boot, correct identity, successful node configuration or peer delivery.** After flashing, reconnect via the appropriate project's supported client, confirm firmware and radio settings, and verify restoration of your identity if required. MeshHub can install Meshtastic but does **not yet implement a live Meshtastic messaging transport**.

For UF2 devices, use the official device-specific bootloader instructions to mount the device's firmware drive and manually copy the firmware file from the displayed offline path. For DFU ZIP files, follow the publisher's compatible DFU utility instructions; MeshHub deliberately does not pass an arbitrary ZIP to `esptool`.

Offline operation requires the firmware image and relevant local tools to have been acquired ahead of time. The bundled catalog is a reproducible snapshot, not an always-up-to-date online release browser.

## Architecture

- `packages/meshhub_domain`: protocol identifiers, radio and message models, adapter/transport/repository ports.
- `packages/meshhub_domain/lib/testing.dart`: explicitly simulated adapters, fake byte transport and in-memory sample data.
- `apps/meshhub_flutter`: adaptive Linux UI with theme choices; explicit BLE scan/selection, live read-only firmware/RF panel, guarded send composer, volatile real inbox and simulated examples toggle.
- `apps/meshhub_flutter/lib/field_session.dart`: selected-device Companion handshake, in-memory receive/diagnostics, bounded reconnect, no outbound replay. `meshcore_ble_transport.dart` owns BlueZ GATT, while the domain codec owns Companion frames.
- `docs/BLE-FEASIBILITY.md` and `docs/M1-HARDWARE-RESULTS.md`: Bluetooth baseline and actual hardware evidence.

The mock inbox remains clearly marked. Local radio acceptance is not recipient delivery. Do not store real history until encrypted persistence exists; this build intentionally loses its live inbox on exit.
