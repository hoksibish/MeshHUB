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
- Final local checks: domain **26 tests passed**, app **39 tests passed**, both format checks unchanged and analyzers clean, Linux release build passed. `run-field-test.sh --check` found the executable. The native Linux runner was subsequently rebuilt with a GTK header bar; the app suite and release build passed again. A live cropped Wayland capture confirmed the new 900×650 floating window's minimize/maximize/close controls and readable content. The older borderless process was left running behind it to preserve any volatile inbox data.
- Field Test v0.1 is a **readiness checkpoint, not M1 completion**. A second MeshCore endpoint plus operating-region/destination verification is required for RF send/receive evidence. No M1 merge without owner approval.

## M1 channel-feed field iteration — 2026-11-24 UTC

- Added read-only MeshCore `GET_CHANNEL` queries across all 40 device-reported slots. The codec discards returned 16-byte secrets; only named slot metadata is held in memory. The first strict parser incorrectly assumed bytes after a NUL-terminated name must be zero, while the physical Heltec returned nonzero tail bytes. A new synthetic regression test reproduces that case; parsing now stops at NUL without decoding the tail.
- A bounded read-only probe using the same `MeshCoreFieldSession` identified the previously authenticated Heltec V3 firmware `v1.18.0-81dbae5`, received all 40 channel responses and found **4 named channel slots**. The probe did not print names, keys, BLE IDs or payloads; it disabled receive queue drain and sent no RF. A live cropped view of the app subsequently showed four named channel cards from the connected radio; no secret or name was copied into this report. The owner has not yet confirmed sending from the new inline composer.
- Inbox now shows configured channel names/slots, lets a user open a session-only chronological feed and compose inside that channel. Explicit preset/region/peer verification still gates a single send; an outbound card appears only on local acceptance and says peer delivery is unverified. Direct-contact test send remains in Radios. True nested post replies and verified channel sender IDs are not supplied by Companion packets. No plaintext history is persisted.
- This iteration does **not** establish RF recipient delivery; the owner's report that a test appeared successful has not been reconciled with peer-side evidence. M1 remains on `feature/m1-meshcore-ble`, unmerged.
- Final checks after the physical readback parser fix and a screenshot-detected low-contrast heading regression: domain **29 tests passed**, app **50 tests passed**, both format checks unchanged, analyzers clean, `git diff --check` clean, and Linux release build succeeded. The previous running app was not restarted during the readback; one new release window later mapped on workspace 1 (floating, not fullscreen). A screenshot of the final contrast correction was blocked by the desktop capture timing out; widget-level color assertion passed. Do not infer peer delivery from these checks.

## M1 owner RF regression report — 2026-11-24

- Owner confirmed a channel message sent through the earlier pre-channel-UI field-test build was received by two network participants.
- After the channel-based UI change, the owner attempted another channel message **while still within repeater range**, but it did not reach the intended participants. Cause **unresolved**; do not attribute this attempt to being out of coverage. A successful local-radio acceptance, if observed, would not demonstrate RF delivery.
- Owner has since moved out of repeater range and cannot repeat the peer-confirmation test right now. **Do not mark the new inline channel composer end-to-end verified or approve/merge M1 on the strength of the older transmission.**
- A follow-up UI change adds connection/send status in the open channel feed, explicitly explaining that MeshHub does not establish repeater coverage or recipient delivery. This change does not modify the transmit path or resolve the regression.
- Pending next opportunity in range: compare pre-UI and inline channel send path; record exact channel slot, connected/Companion state, local send result and recipient confirmation without publishing any message content, secrets, identities or BLE identifiers. Inspect the receive path independently. No automatic replay of uncertain sends.


## Meshtastic BLE connection and pairing preview — 2026-11-24

- Owner authorized Meshtastic Bluetooth connection/pairing for the Heltec V3 now flashed with Meshtastic. Implemented locally on `feature/meshtastic-ble-pairing`, preserving the previous esptool detection fix. No merge or push performed.
- Added separate Meshtastic service discovery, selected-device BlueZ KeyboardOnly pairing agent, six-digit PIN entry inside MeshHub, read-only config nonce handshake, device identity/firmware/hardware readback and manual disconnect. Config completion and node identity are required before readiness. No MeshCore frames, RF messages, settings writes, automatic retries or plaintext persistence are added.
- Firmware Manager now blocks USB operations while either protocol is connecting or connected. Pairing cancellation/disposal closes the owned BLE resources; existing bonds are reused rather than silently deleted.
- Verified commands in `apps/meshhub_flutter`: `flutter pub get --offline`; Dart formatting; `flutter analyze --no-pub` (no issues); `flutter test --no-pub --reporter expanded` (**100 passed**); `flutter build linux --release --no-pub` (passed). Updated scrolling in existing UI tests to wait for layout before tapping controls, including the previously failing erase-option test.
- Hardware evidence: BlueZ sees the Meshtastic service on the flashed Heltec V3; it was unpaired and disconnected at inspection. On 2026-11-25 the owner reported **"Connected and shows firmware"** after following the new in-app discovery/pairing flow, confirming a physical Meshtastic connection and firmware readback. Reconnect, cancellation, wrong-PIN recovery and power-loss cases still need individual physical acceptance. No firmware, RF preset, channel key or radio setting changed during this implementation.
- Protocol references, limitations and physical acceptance steps: `docs/MESHTASTIC-BLE.md`. Meshtastic chat/settings remain outside this connection milestone.


## Four replacement themes — 2026-11-25

- Owner requested removal of all existing themes and four replacements inspired by the named Omarchy Themes references. Implemented locally on `feature/four-new-themes`, preserving the Meshtastic connection/pairing and esptool fixes. No merge or push performed.
- Removed Light, Dark, Tactical and `tactical_hud.dart`. Added central Firesky, Cyberpunk, Retro 82 and Bliss palettes, component styling, palette-menu labels/swatches and Settings choices. Firesky is the default. Retro 82 instrumentation now uses palette-driven square panels and link readouts; the retired fixed-color HUD/grid/reticle painters are removed.
- Referenced all four previews on omarchythemes.com. Styling includes distinct backgrounds, typography, radii, button shapes, forms and navigation. Sources/credits and session-only preference behavior: `docs/THEMES.md`. No upstream wallpapers or theme code bundled, and no desktop configuration changed.
- Verification: formatter clean, `flutter analyze --no-pub` clean, full app suite **103 passed**, and `flutter build linux --release --no-pub` passed. Added 4.5:1 contrast checks and theme switching/render checks at 1200×900 and 390×844; reviewed offline preview captures. Fixed a Material ancestor issue in the new instrument panel caught by the existing erase-option widget test.
- Radio/firmware command behavior was not changed by this appearance work. Physical radio acceptance evidence remains as previously recorded.


## Modern shared app layout — 2026-11-25

- Owner approved the four theme palettes and requested a more modern app. Implemented locally on `feature/modern-app-layout`, retaining all four palettes and the existing connection/firmware work. No merge or push performed.
- Added a floating rounded sidebar with persistent text labels at laptop widths, an updated brand header, a gradient welcome panel, primary connection/channel actions, three responsive session summaries and a calmer activity empty state. Phones use a floating rounded bottom navigation bar and compact side-by-side summaries. Centered large-window content and increased card/form radii across themes.
- Removed the separate console-style Retro 82 dashboard, uppercase headings and instrument sections from the app's primary screens. All four palettes share the modern layout and readable app typography. The brand artwork is decorative, not measured radio topology.
- Header connection status now observes both protocol sessions. Full-suite scrolling uncovered synchronous status notification during pairing-panel disposal; status refresh is scheduled after the frame and cancelling an absent PIN no longer emits an unnecessary change event.
- Verification: formatter and `git diff --check` clean; `flutter analyze --no-pub` clean; full app suite **103 passed**; existing contrast and four-theme switch/render checks pass at 1200×900 and 390×844. Reviewed offline preview renders. `flutter build linux --release --no-pub` passed. No RF send, settings change or physical radio acceptance test performed as part of this appearance update.
