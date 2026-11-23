# MeshHub Linux M0 sample

This is a **simulated** Flutter shell. The inbox and radios are fixtures. It does not scan or connect to a MeshCore/Meshtastic radio, send RF, store messages on disk, or deliver notifications. The Heltec V3 / MeshCore 1.18.0 is the intended M1 device, not an M0 validation claim.

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
flutter run -d linux
```

The built binary is at `build/linux/x64/release/bundle/meshhub_flutter`. The `bundle/` directory (not only the executable) is required to run the release app. For a noninteractive shell on this Omarchy session, `WAYLAND_DISPLAY=wayland-1` and `DISPLAY=:0` were needed to launch a window; normal graphical terminals inherit those automatically.

## Architecture

- `packages/meshhub_domain`: protocol identifiers, radio and message models, adapter/transport/repository ports.
- `packages/meshhub_domain/lib/testing.dart`: explicitly simulated adapters, fake byte transport and in-memory sample data.
- `apps/meshhub_flutter`: adaptive Linux shell with theme choices, sidebar/bottom navigation, network filters, radios placeholder and fixed-code redacted diagnostics helper.
- `docs/BLE-FEASIBILITY.md`: evidence and limitations of the Linux Bluetooth preflight.

Never treat the mock send result as actual radio acceptance or network delivery. The app does not yet have encrypted persistence or a working BLE adapter.
