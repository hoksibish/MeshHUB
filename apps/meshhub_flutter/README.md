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

## Firmware Manager — MeshCore ⇄ Meshtastic, offline USB (Heltec V3)

Open **Radios → Firmware Manager → Open**. Choose **MeshCore** or **Meshtastic**, select an independently downloaded firmware image for the Heltec V3, inspect its detected **role and release version**, compare the SHA-256 with the official release value when available, save the image in the offline library, run a read-only USB chip preflight, and explicitly confirm a flash. No network connection is required once the firmware file and tools are available.

The owner confirmed that the original Heltec V3 MeshCore Companion flash worked on real hardware. **The newly added Meshtastic and additional MeshCore-role paths have not been confirmed by a physical flash**; treat them as field-test features.

### Supported target and image formats

| Firmware ecosystem | Roles supported on Heltec V3 | File to extract/download | USB offset |
| --- | --- | --- | --- |
| MeshCore | Companion BLE / USB / Wi-Fi, Repeater, Room Server, Sensor | `Heltec_v3_<role>-v<version>-merged.bin` | `0x0` |
| Meshtastic | Meshtastic node | `firmware-heltec-v3-<version>.factory.bin` | `0x0` |

**Any release version** matching a recognized full-image filename pattern can be imported; the manager does not hardcode one version or automatically install the newest release. The board remains **Heltec WiFi LoRa 32 V3 (ESP32-S3)**. Other Heltec revisions, non-merged/app-only firmware, Meshtastic update-only images, ZIP archives, nRF52/UF2 devices and wireless OTA are intentionally not supported by this operation. For a Meshtastic ESP32-S3 release ZIP, extract the exact Heltec V3 `.factory.bin` before import.

Official sources:
- MeshCore flasher and firmware downloads: https://flasher.meshcore.io/
- Meshtastic web flasher: https://flasher.meshtastic.org/
- Meshtastic release assets: https://github.com/meshtastic/firmware/releases

**A filename and ESP32 header are not proof of image authenticity or compatible pins/partitions.** Use a trustworthy publisher and verify a published checksum or signature out-of-band where available. A locally calculated SHA-256 only verifies byte consistency.

### Linux prerequisites

```bash
uv tool install esptool
esptool version
ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null
```

Ensure `esptool` is on MeshHub's PATH (usually `$HOME/.local/bin`). An optional `zenity` file picker can help select a BIN; otherwise paste its absolute path. Use normal local USB serial permissions, not `sudo` on MeshHub. No firmware is downloaded automatically.

The offline library under `~/.local/share/meshhub/firmware` stores only firmware bytes and a SHA-256 metadata manifest. It rehashes cached files before showing them and supports previously saved MeshCore Companion images. It does not include message history, keys or device identities.

### Flash workflow and destructive erase

1. Back up the device's **network identity, channels/keys, settings and any other important data** using supported external tools, and verify the backup. Ensure the antenna is attached, USB power is stable and you selected the correct Heltec V3 hardware.
2. Disconnect MeshHub's Bluetooth session and any other program holding the serial port. Verify the selected firmware **protocol, role and version**.
3. Press **Check device (read-only)**. MeshHub invokes `esptool --chip esp32s3 --port PORT flash-id` to confirm the ESP32-S3.
4. For a normal full-image install, leave **Erase all flash** unchecked. The manager repeats the image hash/chip preflight, checks Bluetooth state, and invokes `esptool --chip esp32s3 --port PORT --baud 115200 write-flash 0x0 IMAGE` **once** after the backup/target checkboxes and typed `FLASH` confirmation.
5. **Optional, destructive:** Switching between MeshCore and Meshtastic can require clearing incompatible prior settings/partitions. Only if necessary and after independently backed-up data, opt into **Erase all flash** and type `ERASE` in the separate confirmation dialog. This runs a single `erase-flash` before writing the new factory/merged image. It irreversibly deletes the prior device's identity, keys, channels, settings, pairing, and other storage. This is never enabled automatically.
6. After a successful USB write, power-cycle/reconnect using the **correct protocol's app** and verify firmware, identity, configuration, and RF preset before transmitting. Switching protocols does not automatically migrate keys, contacts, or channels.

There is **no automatic erase, retry, backup, firmware download, or recovery**. An interrupted or failed erase/flash must be treated as uncertain and may require manual recovery. The "esptool completed" status only confirms a local USB operation, not successful boot, radio connectivity, or over-the-air message delivery. In particular, MeshHub's **Meshtastic messaging transport is not implemented yet**; the new firmware manager can install Meshtastic without implying that MeshHub can connect to a Meshtastic node afterward.

## Architecture

- `packages/meshhub_domain`: protocol identifiers, radio and message models, adapter/transport/repository ports.
- `packages/meshhub_domain/lib/testing.dart`: explicitly simulated adapters, fake byte transport and in-memory sample data.
- `apps/meshhub_flutter`: adaptive Linux UI with theme choices; explicit BLE scan/selection, live read-only firmware/RF panel, guarded send composer, volatile real inbox and simulated examples toggle.
- `apps/meshhub_flutter/lib/field_session.dart`: selected-device Companion handshake, in-memory receive/diagnostics, bounded reconnect, no outbound replay. `meshcore_ble_transport.dart` owns BlueZ GATT, while the domain codec owns Companion frames.
- `docs/BLE-FEASIBILITY.md` and `docs/M1-HARDWARE-RESULTS.md`: Bluetooth baseline and actual hardware evidence.

The mock inbox remains clearly marked. Local radio acceptance is not recipient delivery. Do not store real history until encrypted persistence exists; this build intentionally loses its live inbox on exit.
