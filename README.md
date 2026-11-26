# MeshHUB

Development repository for a unified **Meshtastic + MeshCore** messaging, radio management, and mapping application. The owner explicitly approved keeping this repository **public for now** for M0 development and its pull request. Never commit secrets, personal message history, or radio credentials.

## Product goals
- Cross-platform Flutter application: Omarchy Linux first; eventually iOS, Android, macOS, and Windows.
- Unified inbox with Meshtastic/MeshCore filters, locally stored message history, and per-protocol encryption/identity boundaries.
- Multiple connected radios per network with smart Bluetooth/Wi-Fi reconnection, preferred sending radios and manual override.
- Advanced radio configuration, encrypted backups, guided onboarding, node diagnostics.
- Offline maps with terrain-aware coverage estimation and repeater planning.
- Four themes inspired by Omarchy: Firesky, Cyberpunk, Retro 82 and Bliss. See [theme references and behavior](docs/THEMES.md).
- Native installation packages with versioned manual updates.
- Public repository during development as explicitly approved by the owner for M0; revisit open-source licensing and release readiness before publishing software releases.

## Working approach
1. Read [AGENTS.md](AGENTS.md).
2. Copy the nine Markdown files from **MeshHub-Agent-Handoff.zip** into `docs/handoff/` (retain original filenames).
3. Follow `docs/handoff/00-START-HERE.md` and `docs/handoff/08-AGENT-FIRST-PROMPT.md`.
4. Build on branches with tests and milestone-based pull requests.
5. Require owner approval at each milestone checkpoint.

## First hardware milestone
On Omarchy Linux, connect via Bluetooth to **Heltec WiFi LoRa 32 V3 with MeshCore Companion firmware 1.18.0**; establish a working receive/send cycle and prove reliable reconnection.

Actual capabilities vary by firmware/transport and must be validated. Never silently bridge the two radio networks or bypass protocol-specific encryption and identity restrictions.

## Documents
See [docs/handoff](docs/handoff) for the nine imported source documents. The original ZIP is kept locally at the repository root but is not committed.

## Current implementation — M1 Field Test v0.1 checkpoint
- [Linux Flutter app](apps/meshhub_flutter/README.md): the M0 simulated inbox remains opt-in, while the radio panel now integrates a real MeshCore BLE/Companion session, live volatile inbox, guarded send composer, diagnostics, and retry flow. [Field instructions](FIELD-TEST.md) describe the exact release launch and tomorrow's tests.
- [Domain package](packages/meshhub_domain): protocol-separated models and adapter/transport/repository ports with a Companion v1.18.0 codec and synthetic fixture tests. Meshtastic remains simulated, isolated from MeshCore.
- [BLE feasibility](docs/BLE-FEASIBILITY.md), [M1 hardware results](docs/M1-HARDWARE-RESULTS.md), [progress](PROGRESS.md), and [decisions](DECISIONS.md) separate real device evidence from unverified RF cases.
- M0 PR #2 was merged; M1 is on `feature/m1-meshcore-ble` and has **not** been merged. Real peer send/receive proof remains blocked until a second endpoint is available.
- The M0 in-memory `MessageRepository` fixture was owner-approved; the field-test real inbox is also volatile and intentionally **not persisted**. The messaging domain depends on the `MessageRepository` port so encrypted storage can replace the fixture without rewriting messaging models. Do not store real message history on disk until encryption is implemented and tested.
