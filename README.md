# MeshHUB

Private development repository for a unified **Meshtastic + MeshCore** messaging, radio management, and mapping application.

## Product goals
- Cross-platform Flutter application: Omarchy Linux first; eventually iOS, Android, macOS, and Windows.
- Unified inbox with Meshtastic/MeshCore filters, locally stored message history, and per-protocol encryption/identity boundaries.
- Multiple connected radios per network with smart Bluetooth/Wi-Fi reconnection, preferred sending radios and manual override.
- Advanced radio configuration, encrypted backups, guided onboarding, node diagnostics.
- Offline maps with terrain-aware coverage estimation and repeater planning.
- Three themes: light, dark, tactical.
- Native installation packages with versioned manual updates.
- Privately developed until ready for an open-source review.

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
See [docs/handoff](docs/handoff) for the structured development handoff (the nine source documents must be added before implementation).
