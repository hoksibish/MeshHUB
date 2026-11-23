# MeshHub — Local Agent Handoff

Status: approved product definition, implementation not begun. Date: 2026-11-23.

## Mission
Build a reliable, offline-first cross-platform client that operates MeshCore and Meshtastic radios through a unified inbox and dashboard. Start on Omarchy/Arch Linux, validating MeshCore BLE on the owner's Heltec WiFi LoRa 32 V3 running MeshCore Companion 1.18.0. Later target iOS, Android, macOS, and Windows.

## Agent instructions
1. Read **all** documents in this folder, beginning with `01-PRODUCT-SPEC.md` and `02-ARCHITECTURE.md`.
2. Do not interpret approved product scope as a claim that a given firmware/platform supports every operation. Perform capability detection; document gaps.
3. Start with Milestone 0, then Milestone 1. Do not skip real-hardware gate before higher milestones.
4. Work in a **private Git repository**. Never commit device keys, private messages, pairing PINs, logs with secrets, personal coordinates, or production profiles.
5. Make focused commits. Write evidence in `PROGRESS.md` (create it), and update `DECISIONS.md` for any proposed departure from this spec. Pause for owner approval at milestone gates.
6. Use official protocol specifications and permitted upstream libraries where practical. Record exact versions, license obligations, and source URLs. Do not assume upstream APIs are stable.
7. Tests, linting, formatting, error handling, and documentation accompany each milestone. Use mocks/replay fixtures before RF testing.
8. Never automatically bridge MeshCore and Meshtastic. Never transmit a message on another network, identity, channel, or profile without explicit authorization.
9. Avoid destructive operations; back up supported settings before changes, show preview and confirmation, include recovery path.
10. If a platform limitation prevents a feature, surface the limitation, preserve a working fallback, and record it rather than faking success.

## First deliverable (Milestone 0)
Working Flutter Linux shell, project structure, adapter interfaces, mock radio, README with exact setup commands, tests, and Linux BLE feasibility report. Then Milestone 1: real MeshCore BLE link and text message demo with owner-assisted second node/contact as needed.

## Documents
- `01-PRODUCT-SPEC.md` — 20 approved decisions and behavior
- `02-ARCHITECTURE.md` — components, data models, capabilities, failure handling
- `03-MILESTONES.md` — staged implementation and gates
- `04-HARDWARE-TEST-PLAN.md` — objective pass/fail experiments
- `05-SECURITY-AND-PRIVACY.md` — keys, identity, backups, notifications
- `06-ENGINEERING-STANDARDS.md` — tests, packaging, repository policy
- `07-PROTOCOL-RESEARCH.md` — upstream references and verification checklist
- `08-AGENT-FIRST-PROMPT.md` — paste-ready initial work order

## Important boundaries
An offline map is not a verified link map. Predicted coverage is not measured RF performance. Device-to-phone BLE is not LoRa interoperability. Local message history does not synchronize across phone and desktop. Background reception on iOS is best effort, not guaranteed continuous service.
