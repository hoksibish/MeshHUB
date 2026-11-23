# MeshHUB

Development repository for a unified **Meshtastic + MeshCore** messaging, radio management, and mapping application. The owner explicitly approved keeping this repository **public for now** for M0 development and its pull request. Never commit secrets, personal message history, or radio credentials.

## Product goals
- Cross-platform Flutter application: Omarchy Linux first; eventually iOS, Android, macOS, and Windows.
- Unified inbox with Meshtastic/MeshCore filters, locally stored message history, and per-protocol encryption/identity boundaries.
- Multiple connected radios per network with smart Bluetooth/Wi-Fi reconnection, preferred sending radios and manual override.
- Advanced radio configuration, encrypted backups, guided onboarding, node diagnostics.
- Offline maps with terrain-aware coverage estimation and repeater planning.
- Three themes: light, dark, tactical.
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

## Current implementation — Milestone 0 only
- [Linux Flutter sample](apps/meshhub_flutter/README.md): simulated inbox, MeshCore/Meshtastic filters, radio status placeholder and three theme choices. No real radio integration or persistent message history yet.
- [Domain package](packages/meshhub_domain): protocol-separated models and adapter/transport/repository interfaces, with clearly labeled mock fixtures and a fake byte transport.
- [BLE feasibility report](docs/BLE-FEASIBILITY.md), [progress and test output](PROGRESS.md), and [decisions/open gaps](DECISIONS.md).
- Repository CI runs format, analysis, tests and Linux release build without radio hardware. The local M0 build passed; remote CI status must be checked after the authorized push.
- The M0 in-memory `MessageRepository` fixture is owner-approved. The messaging domain depends only on the `MessageRepository` interface (`forProtocol`), not the fixture class or a database, so a future encrypted implementation can replace it at the composition boundary without rewriting the existing domain models or protocol-specific adapters. The demo UI still reads static samples directly and must be wired to the repository when real history is added. **Do not store real message history until encrypted at rest.**

Follow the app README for exact Omarchy setup and run commands. Obtain owner approval at the M0 gate before starting M1.
