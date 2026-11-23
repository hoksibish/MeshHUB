# Security and Privacy Requirements

## Principles
No cloud requirement, no account, no telemetry by default, no cross-device synchronization. Maintain per-device independent local history. Minimize credential lifetime in memory and logging. Threat model includes stolen laptop/phone, accidental configuration export, untrusted BLE devices, malformed protocol frames, and shared-screen notifications.

## Secrets and storage
- Store encryption keys, pairing tokens and app-lock secrets in appropriate OS credential stores. Assess Linux desktop keyring availability; fail safely and disclose if unavailable.
- Encrypt message database where supported; verify actual on-disk encryption with a test (not just file permissions).
- Prefer authenticated encrypted backups with a modern KDF, salt, nonce and versioned manifest. Backup should list precisely which secrets are included/excluded; default to excluding credentials unless necessary and explicitly selected.
- Never place credentials, private payloads, contacts, exact location, or unredacted BLE traces in issue reports/commits/CI artifacts.

## App locking
Optional biometric or PIN. OS biometrics only when supported; build a secure PIN fallback. Lock screen must not accidentally show decrypted previews. Background radio capture may proceed only as permitted by OS and with stored keys appropriately protected; app-lock UI is not a claim of full disk encryption.

## Messaging security
Native MeshCore/Meshtastic encryption/identity remains protocol-specific. Do not invent a universal encryption layer or auto-bridge private traffic. Separate contact grouping from network cryptographic identity. Protect against wrong-recipient/radio selection; require confirmation on ambiguity.

## Administration
Preview config writes with changes and expected reconnect impact; maintain signed/verified or authenticated backup integrity. Include recovery guidance if a setting disables network access. Firmware flashing excluded unless future explicit approval.

## Logs and crash reports
Opt-in export, redacted by default. Document retention and deletion behaviors. No third-party analytics required. Review map tiles/DEM provider network requests for privacy and license compliance.

## Threat-model gate
Before M5/M7, document assets, adversaries, trust boundaries, attack vectors, mitigations, and remaining risks per target platform.
