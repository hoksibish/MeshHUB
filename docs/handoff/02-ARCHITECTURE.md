# Technical Architecture (proposed, validate before freezing)

## Stack
- Flutter/Dart for shared UI and domain orchestration. Confirm package support and license for all five targets.
- Native platform bridges for BLE and OS-specific background/notification/credential APIs as needed.
- Linux BLE through BlueZ/D-Bus via a maintained Flutter plugin or thin native bridge; perform a spike before selecting library.
- SQLite with audited encryption strategy (e.g., SQLCipher-compatible integration) and secure OS key storage. Verify desktop backends; provide explicit platform-specific security support table.
- Local map renderer with licensed downloadable tiles/vector data and DEM terrain. Do not scrape servers or promise offline datasets before reviewing terms.

## Layers
```
UI: chats | contacts | radios | nodes | map | diagnostics | settings
          ↓
Application: message service | contacts | search | radio selection |
             reconnection scheduler | map planning | security | notifications
          ↓
Domain ports: RadioAdapter | RadioTransport | DeviceRepository |
              MessageRepository | SecureKeyStore | NotificationPort | MapDataStore
          ↓
MeshCore adapter          Meshtastic adapter
          ↓                       ↓
BLE / TCP transport implementations (capabilities vary by device & firmware)
```

## Ports (illustrative)
- `RadioAdapter`: `discover`, `connect`, `disconnect`, `identify`, `capabilities`, `events`, `sendMessage`, `readConfig`, `applyConfig`, `backupConfig` if supported.
- `RadioTransport`: `open`, `close`, `writeFrame`, `frames`, `health`; frame boundaries handled per protocol and transport.
- `ConnectionManager`: per-node lifecycle: unknown → discovered → pairing → connecting → initializing → ready → degraded → disconnected/retry; exponential backoff with jitter; distinguish user-disabled from transient errors.
- `RoutingService`: choose protocol first from conversation; rank compatible available nodes by explicit preferred sender and verified capability; never duplicate a send on uncertain outcome; ask before retry if delivery ambiguous.
- `CapabilityRegistry`: runtime negotiated firmware, supported transports/commands, diagnostics, config and safety flags.

## Minimal local entities
`RadioDevice(id, protocol, firmwareVersion, transportProfiles, identity, preferred, lastSeen, capabilities)`
`TransportProfile(id, deviceId, kind, endpointOrBleIdentifier, preference, pairingMetadataRef)`
`Contact(id, displayName, notes)`
`NetworkIdentity(id, contactId?, protocol, nodeOrPublicKeyId, verificationStatus)`
`Conversation(id, protocol, kind, destinationIdentityOrChannel, radioProfileConstraint?)`
`Message(id, conversationId, protocol, senderIdentity, receivedViaDeviceId?, sentViaDeviceId?, networkMessageId?, localTimestamp, protocolTimestamp?, content, status, ackEvidence?, dedupeKey)`
`NodeObservation(id, protocol, nodeId, observerRadioId, timestamp, rssi?, snr?, location?, locationSource, observedLinkEvidence?)`
`OfflineRegion(id, bounds, mapVersion, demVersion, licenseMetadata, bytes, status)`
`RFPlan(id, siteA, siteB, band, frequency, antennas, terrainSource, results, modelParameters)`

## Device and message identity
- Radio device IDs are stable where demonstrably available; map BLE OS identifiers carefully across reconnects (iOS UUID ≠ public MAC).
- Preserve original protocol identifiers and payload evidence for de-duplication; no cross-protocol dedupe assumption.
- Deduplication must be resilient to multiple radios hearing the same packet. Document collision and reset behavior.
- Message status vocabulary: draft / queued locally / submitted to radio / radio accepted (if supported) / network acknowledged (if supported) / failed / uncertain. Never equate local BLE write with recipient delivery.

## Key edge cases
- Multiple nodes hear same RF message; local event merge without losing provenance.
- Same node available on BLE and TCP; avoid conflicting simultaneous sessions unless firmware explicitly supports it.
- Bluetooth pairing PIN prompt, OS permission denied, adapter off, Linux BlueZ restart.
- Wi-Fi device changes IP address, mDNS discovery unavailable, TCP connected but protocol not initialized.
- OS sleep/suspend, reconnect storm, stale radio queues, battery drain.
- Two apps concurrently opening same node; detect/report exclusive device access where applicable.
- Failover requires compatible identity/key/channel and message dedupe; if unconfirmed, show manual selection.
- Native configuration commands may change identity, channel, or link parameters; gate and prepare recovery.

## Mapping/RF boundaries
- Render real node positions only when known or manually assigned; show provenance and uncertainty.
- Observed telemetry is not a complete topology or coverage measurement.
- Terrain profiles, Fresnel analysis, link budgets, and propagation models must display assumptions. Distinguish predicted results from observed metrics.
- Downloadable maps and DEM need source licensing review, integrity verification, and disk quota controls.

## Future compatibility
Version adapters independently; lock fixtures to known firmware versions; run protocol compatibility matrix by OS, firmware, transport, and function. Do not rely on unofficial clients as sole protocol truth.
