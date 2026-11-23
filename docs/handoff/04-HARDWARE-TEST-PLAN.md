# Hardware and Functional Test Plan

## Baseline
- Host: Omarchy (Arch-based Linux), exact OS/kernel/BlueZ/Flutter versions to record.
- Primary test radio: Heltec WiFi LoRa 32 V3, MeshCore Companion 1.18.0.
- Previously reported RF preset: 910.525 MHz, SF7, BW 62.5 kHz, CR 5; **read actual settings rather than overwrite**. Region/legal compliance to be verified before RF testing.
- Second reachable MeshCore endpoint/contact required to verify real over-the-air exchange; owner coordinates test. Never confuse local command acknowledgment with an end-to-end message.

## M1 test cases
| ID | Test | Pass condition |
|---|---|---|
| BLE-01 | Power radio, discover via Linux Bluetooth | Identifies actual device and advertised compatible service; does not assume based on name alone |
| BLE-02 | Pair and connect | Handles OS pairing/PIN correctly; explicit ready state after protocol handshake |
| BLE-03 | Read identity and firmware | Displays device-reported values with version/capability evidence |
| MSG-01 | Receive message from second radio | Content and sender stored once with valid network provenance |
| MSG-02 | Send a direct or channel test message | Device accepts command; separately log over-air/recipient confirmation if available |
| BLE-04 | Walk out of range, return | State indicates disconnect; recovery succeeds with reasonable retry behavior |
| BLE-05 | Reboot radio | Reconnects safely; incomplete sends remain uncertain until reconciled |
| BLE-06 | Bluetooth off/on; BlueZ service restart | Clear status; can recover without corrupting local DB |
| BLE-07 | Wrong PIN/permission denial | Actionable error and retry path; no secret leakage in logs |
| MSG-03 | Repeated same incoming frame | Deduped locally while retaining multiple radio observations |
| MSG-04 | Disconnect during outbound message | No silent duplicate retransmission; pending/uncertain state shown |

## Later hardware matrix
Test on Meshtastic hardware with known firmware; one BLE radio per protocol; two radios per protocol; Wi-Fi/TCP radios where firmware allows; laptop sleep/resume; Android lock/background; iPhone lock/background; cross-platform local-history independence; battery/performance impact. Log tested firmware, transport, OS, and exact result per case.

## Evidence template
`Test ID | UTC time | host build | radio firmware | transport | action | expected | observed | pass/fail | sanitized log or screenshot | follow-up`.

## Cautions
Do not reset or reflash owner's Heltec as an automated troubleshooting step. Ask before modifying operational radio presets, keys, channels, identity, or backup/export scope. No fabricated GPS points, RSSI, coverage, or relay paths.
