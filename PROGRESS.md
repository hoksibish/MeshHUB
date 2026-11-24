# MeshHub progress — Issue #1 / Milestone 0

## Scope and provenance

- Branch: `feature/issue-1-handoff`, created from `main` at `61d2902`. Handoff import `2f9abc0`, M0 implementation `dbe2a0c`, and owner-decision documentation `b6cd1d6` were pushed. PR **#2** is open against `main`, referencing Issue #1; do not merge automatically.
- `MeshHub-Agent-Handoff.zip` was copied to the repository root **before** extraction. `unzip -t` passed; all nine imported `docs/handoff/0*.md` files match the archive members byte-for-byte. The ZIP remains untracked locally, not part of the source commit.
- Read `AGENTS.md`, `README.md`, all nine handoff files, and GitHub Issue #1. Issue #1 requires an Omarchy Flutter sample, checks, environment/hardware report, and a PR; no real RF claim is allowed.

## Environment and setup

- Omarchy 4.5.0; kernel `7.2.15-1-omarchy`; x86_64 Intel Core i9-12900H; Git 2.56.0; user `jbarr` in `uucp` and `wheel` groups. Bluetooth service active, one powered controller, BlueZ 5.87; `/dev/rfkill` is root:rfkill mode 664. No radio pairing or Heltec firmware read was performed.
- Official Flutter Linux stable archive 3.50.1 / Dart 3.14.0 downloaded and checked against release SHA-256 `4ad17fc8462fbcef2ba19ff4a78c0a16b7147fde1add8578e267ea62cdb92678`. Installed in `~/.local/share/flutter-sdk`. CMake 4.4.5 and Ninja 1.13.2 installed under `~/.local/bin` with `uv tool install`; Clang, GTK 3, pkg-config were already available. All Flutter/Dart commands used `FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true`.
- `flutter doctor -v`: Linux desktop toolchain ✓, Linux desktop device ✓; Android SDK and Chrome missing (not required for Linux M0); `eglinfo` unavailable warning.

## M0 implementation and actual checks

- `apps/meshhub_flutter`: Linux release sample with adaptive sidebar/bottom navigation, light/dark/tactical themes, a clearly labeled **SIMULATED** inbox with protocol filters, and an honest no-real-radio screen. Built release binary launched as a Wayland window (Hyprland listed the `meshhub_flutter` client); a screenshot could not be captured from this tool session.
- `packages/meshhub_domain`: protocol-distinct models, `RadioAdapter` / `RadioTransport` / `MessageRepository` ports, a protocol-guarded simulation-only mock radio with incoming stream, an in-memory fake byte transport, and synthetic sample store. No BLE connection, disk persistence or RF transmission implemented.
- `apps/meshhub_flutter/lib/diagnostics.dart`: fixed-code diagnostic logger; no identifiers or payload arguments accepted. The test verifies a redacted disconnect event. It is not yet wired to real radio events.
- `.github/workflows/ci.yml`: headless Linux format, analyze, unit/widget test, release build workflow; GitHub Actions checks are running on PR #2 (no passing remote result claimed yet).
- Local check command from repo root: `flutter pub get`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test` in each package; `flutter build linux --release` in the app; `git diff --check`.
- Exact latest local results (rerun before commit): domain **9 tests passed**, app **2 widget/unit tests passed**, both analyzers **No issues found**, both format checks unchanged, Linux release **Built build/linux/x64/release/bundle/meshhub_flutter**, diff check passed. Test-first RED failures were observed before implementing the protocol-boundary, incoming-stream, fake-transport and close/reopen lifecycle, diagnostic-logger, repository and inbox behaviors.
- Linux BLE evidence: OS LE scan started and completed; no MeshCore UUID/name observed. A throwaway Dart `bluez` 0.9.0 probe connected to BlueZ D-Bus, counted one adapter and three known device records, and closed. No pairing, GATT subscription, or live Heltec connection; details in `docs/BLE-FEASIBILITY.md`.

## M0 acceptance checklist and gaps

- [x] Nine handoff files version-controlled on a feature branch and read before coding.
- [x] OS/CPU/toolchain/Bluetooth permissions/hardware prerequisites documented.
- [x] Protocol-separated interfaces and a mock Linux Flutter inbox sample built and tested.
- [x] BLE scan / D-Bus feasibility demonstrated without pairing or claimed RF messaging.
- [x] Local formatting, static analysis, tests and Linux release build pass.
- [x] Owner approved keeping the repository public for now, the in-memory M0 fixture, and the feature-branch push/PR. The handoff's private-repo and local-persistence M0 deliverables are explicitly waived/deferred for this gate.
- [ ] Encrypted on-disk persistence **not implemented**; no real message history may be stored until encryption is implemented and tested. The domain depends on the `MessageRepository` port rather than the in-memory implementation, allowing a future encrypted implementation to replace it without rewriting the domain. Demo UI still needs repository wiring before real history.
- [x] PR #2 opened against `main`, referencing Issue #1; merge remains manual. Remote GitHub Actions checks were in progress at submission and must be checked before review/merge.
- [ ] M0 PR review and merge required before starting M1. M1 real-hardware tests require the Heltec powered nearby and a second MeshCore endpoint/contact; stop at the M1 acceptance gate.

No real radio message was sent or received. No device settings, keys, channels or firmware were changed. No M1 work had begun **at this M0 snapshot**.

## M1 Field Test v0.1 checkpoint — 2026-11-24 UTC

- M0 PR #2 was subsequently merged. M1 is on `feature/m1-meshcore-ble`, not merged. See `docs/M1-HARDWARE-RESULTS.md` and `FIELD-TEST.md` for chronological, sanitized evidence and the procedure.
- The app now has explicit MeshCore BlueZ discovery/selection, authenticated GATT and Companion handshake, device-reported model/version/identity/RF readback, in-memory incoming-event pipeline and exact-frame dedupe, default live-only Inbox with labeled simulation toggle, guarded channel/direct send, count-only diagnostics, and bounded no-replay BLE reconnection. Meshtastic remains simulated and protocol-isolated. The radio queue is drained into volatile RAM only; no real history is persisted.
- A physical Heltec V3 reported `v1.18.0-81dbae5`, protocol 14 and 910.525 MHz / 62.5 kHz / SF7 / CR5 via the same session class used by the UI. One deliberate local BLE disconnect recovered with one retry and fresh firmware readback; the initial OS connection was restored. No RF send, peer receive, radio reboot, out-of-range, or BlueZ restart was claimed.
- Final local checks: domain **26 tests passed**, app **39 tests passed**, both format checks unchanged and analyzers clean, Linux release build passed. `run-field-test.sh --check` found the executable and actual launch created a mapped Hyprland window; the screenshot driver had no DISPLAY, so visual contents were not inspected through it. `git diff --check` passed before the final review.
- Field Test v0.1 is a **readiness checkpoint, not M1 completion**. A second MeshCore endpoint plus operating-region/destination verification is required for RF send/receive evidence. No M1 merge without owner approval.
