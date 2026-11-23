# Milestones and Acceptance Gates

## M0 — Foundation and feasibility
Deliver: private Git repo, Flutter Linux shell, light/dark/tactical theme tokens, navigation skeleton, ports/interfaces, mock adapter, sample dataset, local persistence skeleton, CI/test workflow, Linux Bluetooth plugin proof-of-concept. Research firmware 1.18.0 specifics.
**Gate:** clean build on Omarchy; unit tests pass; mock messages shown; BLE scan demonstrated or blocker documented with fallback plan. Owner reviews before M1.

## M1 — MeshCore BLE vertical slice (first real hardware)
Deliver: Heltec discovery, pairing, protocol initialization, device details, live incoming messages, text outbound via correct channel/recipient, safe logging, disconnect/reconnect flow.
**Gate:** hardware test plan M1 cases signed off; logs redacted; successful real send/receive with suitable second endpoint; no fabricated success states.

## M2 — Meshtastic protocol integration
Deliver: separate Meshtastic adapter and transport; protocol version negotiation; receive/send using a real Meshtastic radio when available; simulated fixture path until owner provides hardware.
**Gate:** replay tests pass; real-hardware claims only when tested; both adapters coexist without cross-transmission.

## M3 — Unified inbox, contacts, secure history
Deliver: local encrypted message repository, search, network filters, unread, per-protocol conversation identity, unified contact grouping, manual outgoing radio override.
**Gate:** repeated events deduped, cold restart history intact, no cross-device sync, sensitive data not in plaintext logs.

## M4 — Connection resilience and multiple radios
Deliver: per-device BLE/TCP transport profiles, prioritized reconnect, telemetry, multiple active devices, compatibility-checked failover, message uncertain-state handling.
**Gate:** scripted disconnect/suspend tests pass; automatic sending never crosses protocols or identities without consent.

## M5 — Advanced device management
Deliver: capability-aware settings UI, safe config reads/writes, backups and encrypted export/restore where supported, diagnostics and recovery flows.
**Gate:** backup round-trip test on supported fields, dangerous changes require confirmation, unsupported operations visibly disabled.

## M6 — Maps and node dashboard
Deliver: unified node map, provenance labels, offline regions, licensed terrain DEM, distance/profile/Fresnel/link-budget estimates, repeater candidates and measured-vs-predicted distinction.
**Gate:** offline test with network disabled, model math unit tests, unknown-location handling and legal dataset checks.

## M7 — Cross-platform support and background behavior
Deliver: platform-specific BLE bridges or compatible packages, secure storage/biometrics, notification capabilities, reconnect rules, background matrix for iOS/Android/macOS/Windows.
**Gate:** real devices validated individually; unsupported background states documented; lock-screen privacy tests.

## M8 — Packaging and release readiness
Deliver: reproducible Arch packaging, versioned artifacts/checksums, install/uninstall and manual update instructions; other native packages as platform implementation becomes ready; license/dependency audit; docs.
**Gate:** clean installation on test machine, migration and rollback test, no secrets in packages or repo, owner acceptance.

## Each milestone report
Include: delivered files, commands used, automated test output, hardware environment and firmware, screenshots only if non-sensitive, known defects, acceptance checklist, next gated tasks. No autonomous advancement past owner approval.
