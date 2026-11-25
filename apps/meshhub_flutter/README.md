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

## Architecture

- `packages/meshhub_domain`: protocol identifiers, radio and message models, adapter/transport/repository ports.
- `packages/meshhub_domain/lib/testing.dart`: explicitly simulated adapters, fake byte transport and in-memory sample data.
- `apps/meshhub_flutter`: adaptive Linux UI with theme choices; explicit BLE scan/selection, live read-only firmware/RF panel, guarded send composer, volatile real inbox and simulated examples toggle.
- `apps/meshhub_flutter/lib/field_session.dart`: selected-device Companion handshake, in-memory receive/diagnostics, bounded reconnect, no outbound replay. `meshcore_ble_transport.dart` owns BlueZ GATT, while the domain codec owns Companion frames.
- `docs/BLE-FEASIBILITY.md` and `docs/M1-HARDWARE-RESULTS.md`: Bluetooth baseline and actual hardware evidence.

The mock inbox remains clearly marked. Local radio acceptance is not recipient delivery. Do not store real history until encrypted persistence exists; this build intentionally loses its live inbox on exit.
