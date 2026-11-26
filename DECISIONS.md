# MeshHub decisions and open proposals

## M0 implementation choices

- Use Flutter 3.50.1 / Dart 3.14.0, a Linux-only generated runner under `apps/meshhub_flutter`, and a separate `packages/meshhub_domain` package. Other platform runners are deferred to M7, not declared supported now.
- Keep protocol-neutral models and `RadioAdapter` / `RadioTransport` / `MessageRepository` ports in the domain package. Testing-only mock adapters, fake byte transport and an in-memory repository live behind a separate `testing.dart` import. MeshCore and Meshtastic fixture identities/capabilities remain distinct; `ConversationTarget` prevents wrong-protocol sends and no cross-protocol bridging exists.
- Use `material_ui` 1.11.1 for the Flutter 3.50 template rather than its deprecated `flutter/material.dart` import. Themes are light/dark/tactical token variants, not final design approval.
- Suppress Flutter/Dart CLI analytics during development commands. No app telemetry is implemented.

## Owner-approved M0 exceptions and future decisions

- **Repository visibility:** The owner explicitly approved keeping MeshHUB **public for now** and authorized pushing `feature/issue-1-handoff` and opening a PR against `main` referencing Issue #1. This supersedes the handoff's private-repository M0 deliverable. Do not merge automatically. Avoid publishing secrets or personal message data.
- **Persistence:** The owner approved the in-memory fixture repository for M0 and deferred encrypted on-disk persistence. **Encryption is mandatory before storing real message history.** `MessageRepository` is a domain port; the fixture is separate in `testing.dart`. An encrypted store should implement the port and be injected at the app composition boundary without rewriting the existing messaging models or adapters. The current UI still uses static demo samples, not the repository: wire it to the port before real history. Design and test encrypted SQLite/key custody before claiming the M3 history gate complete.
- **M1 gate:** Begin real Heltec V3 / MeshCore 1.18.0 Bluetooth work only after the M0 PR is reviewed and merged. Prioritize discovery, pairing/authentication, connection, real device metadata, receive, test send, and automatic reconnection. Simulated results are not hardware proof; stop at M1 acceptance review.
- Choose a maintained BLE bridge only after device-level pairing/GATT/notification evidence. Linux `bluez` D-Bus is a feasible candidate, not an adopted production adapter.


## Encrypted history preview

- Owner explicitly requested encrypted message history, authorizing this persistence milestone. Real message persistence now goes through the domain `MessageHistoryRepository` / `MessageRepository` ports. The desktop composition root injects an AES-256-GCM repository and a Linux Secret Service key store; read-only radio CLI probes and tests do not implicitly persist real data.
- This increment uses a bounded authenticated encrypted snapshot (10,000 records / 16 MiB), not SQLCipher. The proposed SQLite/indexed-history architecture remains future work. The snapshot avoids unencrypted SQL journals/indexes and native database packaging while delivering verified encrypted restart recovery. No claim of completing all M3 search/contact/backup requirements is made.
- The encryption key is generated randomly and kept in the persistent default OS keyring, never beside ciphertext. Missing/locked keys, failed authentication, unsupported files and writer contention fail closed without plaintext fallback or destructive reset. The keyring's security and the OS session remain trust boundaries; application PIN locking and key backup/recovery are separate scope.
- History is a read-only archive separate from the live channel composer. Source radio/protocol/channel-key fingerprints stay in encrypted records; a historical channel slot never becomes a live send target. Local acceptance continues to mean peer delivery unverified. Simulated messages and drafts are excluded; saving/retrying storage never transmits RF.
