# Dependency and license review — M0

- Project source: **no project license selected**; owner decision required before public distribution. The generated package's `TODO` license placeholder was removed rather than presented as a real license.
- Flutter 3.50.1 / Dart 3.14.0 and `material_ui` 1.11.1: Flutter/BSD-style license; confirm bundled notices before redistribution. https://github.com/flutter/flutter/blob/stable/LICENSE ; https://pub.dev/packages/material_ui/license
- `flutter_lints` 6.0.0 and `flutter_test` from Flutter SDK: development/test dependencies only; review transitive notices at packaging time.
- `bluez` 0.9.0 (MPL-2.0) used in a throwaway local feasibility probe, **not** an app dependency. MPL obligations must be assessed if adopted. https://pub.dev/packages/bluez/license
- `bluetooth_low_energy` 6.2.1 (MIT) is a research candidate only, **not** an app dependency. https://pub.dev/packages/bluetooth_low_energy/license

Before public release, audit the exact resolved `pubspec.lock`, native bundle licenses, attribution and copyleft obligations. The remote repository currently appears public, contrary to the private-first handoff; do not push new source until visibility is confirmed.
