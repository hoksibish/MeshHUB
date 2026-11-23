# AGENTS.md — MeshHUB local development agent

## Mission
Build the MeshHUB Flutter application incrementally on Omarchy Linux using the project documentation as the source of truth. Keep Meshtastic and MeshCore protocol integrations isolated behind tested interfaces.

## Mandatory startup
- Read `README.md` and all files in `docs/handoff/`, especially `00-START-HERE.md`, `02-ARCHITECTURE.md`, `03-MILESTONES.md`, `04-HARDWARE-TEST-PLAN.md`, and `08-AGENT-FIRST-PROMPT.md`.
- If the handoff files are missing, stop and request them; do not invent requirements.
- Inspect environment, Flutter/Dart availability, Linux Bluetooth stack, hardware access and repository status.
- Create a feature branch for each milestone, never force-push `main`.

## Work policy
- Complete one independently testable milestone at a time.
- Write code, tests, and developer documentation; run relevant checks.
- Record exact commands, test outcomes, unverified assumptions, platform limitations and blockers.
- Use mocks for UI and logic, but clearly distinguish mocks from working radio integrations.
- Obtain owner approval before advancing to the next milestone or making breaking architectural changes.
- Never claim radio transmission or background connectivity is validated without real hardware proof.

## Safety and privacy
- Keep protocol identity and encrypted-channel boundaries intact.
- Never silently bridge Meshtastic with MeshCore.
- Do not commit message databases, private keys, device PINs, radio credentials, .env files or personal logs.
- Require explicit user approval for destructive device changes and credential exports.
- Reconnection must not create duplicate sends.

## Deliverables per milestone
- A working demonstration where possible.
- Automated test results and manual test checklist.
- Updated docs and decision log.
- A pull request with acceptance criteria and known gaps.

## Hardware first
The initial validation device is a Heltec WiFi LoRa 32 V3 with MeshCore Companion 1.18.0. Begin with Linux BLE discovery, pairing, connection, read-only device metadata, message receive/send, then reconnection testing. Verify actual protocol capabilities rather than guessing characteristic IDs or APIs.
