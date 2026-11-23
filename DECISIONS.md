# MeshHub decisions and open proposals

## M0 implementation choices

- Use Flutter 3.50.1 / Dart 3.14.0, a Linux-only generated runner under `apps/meshhub_flutter`, and a separate `packages/meshhub_domain` package. Other platform runners are deferred to M7, not declared supported now.
- Keep protocol-neutral models and `RadioAdapter` / `RadioTransport` / `MessageRepository` ports in the domain package. Testing-only mock adapters, fake byte transport and an in-memory repository live behind a separate `testing.dart` import. MeshCore and Meshtastic fixture identities/capabilities remain distinct; `ConversationTarget` prevents wrong-protocol sends and no cross-protocol bridging exists.
- Use `material_ui` 1.11.1 for the Flutter 3.50 template rather than its deprecated `flutter/material.dart` import. Themes are light/dark/tactical token variants, not final design approval.
- Suppress Flutter/Dart CLI analytics during development commands. No app telemetry is implemented.

## Owner approval / future decisions

- **Persistence gap:** M0 has a repository boundary but deliberately writes no message content to disk. The handoff's "local persistence skeleton" is therefore only an interface + ephemeral fixture implementation. Before real history at M3, choose and test encrypted SQLite and desktop key custody; do not ship plaintext message history to claim this gate is complete.
- Choose a maintained BLE bridge only after device-level pairing/GATT/notification evidence. Linux `bluez` D-Bus is a feasible candidate, not an adopted production adapter.
- Handoff says repository should be private; it was made public to allow cloning. Confirm visibility before pushing commits or opening a PR. Nothing has been pushed.
