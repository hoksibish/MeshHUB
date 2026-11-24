# Dependency and license review — M0

- Project source: **no project license selected**. Public visibility does **not** grant permission to reuse or redistribute the code; owner must choose a license before an open-source release. The generated package's `TODO` license placeholder was removed rather than presented as a real license.
- Flutter 3.50.1 / Dart 3.14.0 and `material_ui` 1.11.1: Flutter/BSD-style license; confirm bundled notices before redistribution. https://github.com/flutter/flutter/blob/stable/LICENSE ; https://pub.dev/packages/material_ui/license
- `flutter_lints` 6.0.0 and `flutter_test` from Flutter SDK: development/test dependencies only; review transitive notices at packaging time.
- `bluez` 0.9.0 (MPL-2.0) is an M1 Linux app dependency for read-only discovery and future pairing/GATT research. Its transitive `dbus` dependency is also included; review resolved dependency licenses and MPL notice/source obligations before distributing an app bundle. No Heltec connection has yet been validated. https://pub.dev/packages/bluez/license
- `bluetooth_low_energy` 6.2.1 (MIT) is a research candidate only, **not** an app dependency. https://pub.dev/packages/bluetooth_low_energy/license

Before an open-source release, audit the exact resolved `pubspec.lock`, native bundle licenses, attribution and copyleft obligations. The owner explicitly approved public repository visibility and this M0 push/PR, overriding the handoff's private-first preference; source remains unlicensed pending a separate owner decision.
