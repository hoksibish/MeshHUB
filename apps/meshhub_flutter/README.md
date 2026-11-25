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

## Firmware Manager (Heltec V3 / MeshCore Companion)

In **Radios → Firmware Manager → Open**, MeshHub can inspect a previously downloaded **Heltec V3 MeshCore Companion merged ESP32-S3 .bin** file, calculate SHA-256, compare an optional publisher checksum, copy it to a persistent offline library, and use `esptool` over a locally attached USB serial device. **No web browser or network connection is required for the flash step.** MeshHub does not automatically download firmware, manage online releases, or install `esptool`.

Linux host prerequisites:

```bash
python3 -m pip install --user esptool
python3 -m esptool version
ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null
```

Depending on Omarchy's Python packaging, install esptool in a managed environment (for example with `pipx` or `uv tool`), but ensure `python3 -m esptool` is runnable by MeshHub. The UI optionally opens `zenity` for file selection; otherwise paste the absolute file path. Do not add permissive udev rules or use `sudo` on the application as a shortcut to USB permissions. You may need the normal serial-port group/session permissions.

Supported in this initial implementation:

- **Exact target:** Heltec WiFi LoRa 32 V3, ESP32-S3, **MeshCore Companion** role.
- **Package:** matching filename containing `Heltec_v3`, `companion`, and `merged.bin`; an ESP32 image header at `0x0`, minimum/maximum size and local SHA-256 are checked. **Filename and file header are not cryptographic proof of target, role or publisher.** Independently compare the SHA-256 against a trusted release value when available.
- **Offline library:** copies firmware bytes and nonsecret metadata to `~/.local/share/meshhub/firmware`. The copied bytes are rehashed before use; invalid cache files are not shown. Firmware data does not include chat history or radio identity.
- **USB preflight:** requires a Linux serial device (`/dev/ttyACM*`, `/dev/ttyUSB*` or `/dev/serial/by-id/*`), uses read-only `esptool --chip esp32s3 --port PORT flash-id` and requires an ESP32-S3 response.
- **Flashing:** only after selecting an image, a passed preflight, explicit acknowledgment of verified backups and target, and typing **FLASH** in the confirmation dialog. The app rechecks the file digest and USB chip and invokes `python3 -m esptool --chip esp32s3 --port PORT --baud 115200 write-flash 0x0 IMAGE` once. It deliberately does **not** invoke `erase-flash`, automatically back up identity, or retry uncertain writes.

**Important:** Writing a merged image at `0x0` can still rewrite bootloader/partitions and overwrite device identity, Bluetooth pairing information, RF settings or other data. The lack of a separate `erase-flash` command does **not** guarantee configuration preservation. Back up first using a supported trusted method and verify after flashing. Disconnect the MeshHub BLE session before using USB. A successful esptool exit means a local USB operation completed; it is not proof that the node firmware or saved identity works. Do not flash an existing operational node without accepting these risks.

Meshtastic, non-merged application-only images, other Heltec revisions, nRF52/UF2 devices, wireless OTA and automatic firmware updates are **not supported yet**. No real Heltec USB flash has been performed or verified from this feature branch. The `Firmware Manager` UI and service have automated tests, but on-device acceptance remains pending.

## Architecture

- `packages/meshhub_domain`: protocol identifiers, radio and message models, adapter/transport/repository ports.
- `packages/meshhub_domain/lib/testing.dart`: explicitly simulated adapters, fake byte transport and in-memory sample data.
- `apps/meshhub_flutter`: adaptive Linux UI with theme choices; explicit BLE scan/selection, live read-only firmware/RF panel, guarded send composer, volatile real inbox and simulated examples toggle.
- `apps/meshhub_flutter/lib/field_session.dart`: selected-device Companion handshake, in-memory receive/diagnostics, bounded reconnect, no outbound replay. `meshcore_ble_transport.dart` owns BlueZ GATT, while the domain codec owns Companion frames.
- `docs/BLE-FEASIBILITY.md` and `docs/M1-HARDWARE-RESULTS.md`: Bluetooth baseline and actual hardware evidence.

The mock inbox remains clearly marked. Local radio acceptance is not recipient delivery. Do not store real history until encrypted persistence exists; this build intentionally loses its live inbox on exit.
