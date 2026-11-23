# MeshHub — Approved Product Specification

## Goal
One intuitive application for MeshCore and Meshtastic, operating both node families through Bluetooth and Wi-Fi where supported, with a unified messaging experience and advanced diagnostics/mapping. Offline-first; no mandatory cloud or server.

## Decisions 1–20 (approved)
1. **Platforms:** iOS, Android, macOS, Linux/Omarchy, Windows, unified experience.
2. **Connectivity:** remember radios; automatic BLE/Wi-Fi reconnect and user-configurable transport preference.
3. **Inbox:** unified chronological conversation list; All / MeshCore / Meshtastic filters.
4. **Multiple radios:** support more than one per network, select preferred sender, compatible failover.
5. **History:** encrypted/protected local history per installation; NO cross-device sync.
6. **Sending:** automatic compatible radio choice; visible manual override; do not silently change network/identity/channel.
7. **Dashboard:** chats, nodes, map, signal/diagnostics, device management.
8. **Management:** supported advanced configuration, diagnostics, backup/restore, minimize use of official apps.
9. **Map:** unified nodes, filters, signal/observed paths where available, terrain-aware RF coverage estimation and repeater planning.
10. **Background:** maximum permitted lock-screen/background reception, notifications, and reconnect; disclose OS constraints.
11. **Contacts:** unified people with separate MeshCore/Meshtastic identities, separate conversations and native encryption.
12. **Security:** optional biometric/PIN lock, protected local storage, encrypted configuration backups.
13. **Themes:** light, dark, optional tactical, responsive UI.
14. **Onboarding:** guided scanning, pairing help, connection test, remember device, actionable troubleshooting, manual fallback.
15. **Maps:** downloadable offline regions and terrain elevation data for mapping/RF estimates.
16. **Delivery:** modular architecture, independently testable milestones.
17. **Development:** Omarchy Linux first; real MeshCore BLE validation on Heltec WiFi LoRa 32 V3, companion firmware 1.18.0.
18. **Source:** private first, open-source ready later.
19. **Distribution:** native installation packages and versioned manual updates.
20. **Handoff:** structured spec, architecture, milestones, coding standards, hardware tests, agent instructions.

## Required screens
- First-run setup / permission guidance / discovery / pairing / connection verification
- Unified inbox with filter, search, unread badges, connection summary
- Conversation view with outgoing-radio selector and message state
- Contacts with multiple network identities
- Radios list and per-device details (state, interface, signal/battery if exposed, capabilities)
- Configuration editor (grouped, capability-aware, staged apply, rollback guidance)
- Nodes directory with discovery metadata, last-seen, protocol-specific details
- Map with location provenance, offline region manager, terrain/link-planning panel
- Diagnostics and redacted event logs
- Security, themes, notifications, and storage settings

## User experience principles
- Messaging is the default landing screen. Desktop sidebar; mobile adaptive bottom navigation.
- Use network badges and device identity wherever ambiguity exists.
- Show unknown/not supported rather than fabricating data.
- Notifications honor privacy lock settings; default to hiding sensitive previews when locked if user selects it.
- Contact linking is manual or requires verifiable identity association. Do not assume matching names mean same person.
- Messages retain source protocol, channel, node, timestamps, raw delivery evidence, and local status.
- Channel broadcasts and direct messages are distinct. Never assert end-to-end delivery without an actual protocol acknowledgment that warrants the label.

## Out of scope without new owner approval
- Automatic cross-protocol message bridging or retransmission
- Cloud account, message sync server, mandatory remote dependencies
- OTA firmware flashing, unless explicitly scoped later
- RF transmissions for tests without owner direction/appropriate operating context
- Public release or app-store submission during initial development

## Success definition
A nondeveloper can install MeshHub, pair supported radios, exchange real messages, find them in local history, understand connection health, and use compatible administration/map features without unclear failures or misrepresented data.
