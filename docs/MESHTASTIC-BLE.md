# Meshtastic BLE connection preview

Scope: Linux BlueZ discovery, in-app six-digit PIN pairing, local configuration handshake, device identity/firmware/hardware readback and manual disconnect. Separate from MeshCore transport, messaging and identities. No MeshPacket/admin encoder, RF test send, configuration write, firmware operation or plaintext persistence is added.

## Protocol sources

- Firmware 2.7.26 UUIDs: https://github.com/meshtastic/firmware/blob/v2.7.26.54e0d8d/src/BluetoothCommon.h
- Official BLE reference: https://github.com/meshtastic/python/blob/master/meshtastic/ble_interface.py
- Official schema: https://github.com/meshtastic/protobufs/blob/master/meshtastic/mesh.proto
- Bluetooth PIN modes: https://meshtastic.org/docs/configuration/radio/bluetooth/
- Installed `bluez` 0.9.0 agent/client/device/characteristic APIs inspected locally.

The bounded codec implements only `ToRadio.want_config_id` (3), `FromRadio.my_info` (3) / `MyNodeInfo.my_node_num` (1), `FromRadio.config_complete_id` (7), `FromRadio.rebooted` (8), and `FromRadio.metadata` (13) / firmware_version (1), hw_model (9). Unknown fields are skipped with length/wire validation. Each BLE read is one protobuf envelope; UART/serial framing is not used. Frame limit: 512 bytes. A configuration request is sent once with a fresh nonce; stale completion IDs cannot establish readiness. Session notifications and fallback polling drain one serialized FIFO with bounded work per wake.

The app registers a KeyboardOnly BlueZ agent on the connection's own bus. Only the selected device may request a PIN; it does not become the system default agent or automatically approve confirmations. PIN input is limited to six decimal digits, including leading zeros. Cancellation, timeout and shutdown clear the pending request. The PIN lives only in memory during authentication, while the OS retains its normal Bluetooth bond. Pairing timeout: 90 seconds; PIN timeout: 60 seconds; configuration timeout: 45 seconds. No automatic reconnect or send replay.

## Verification

Automated tests use synthetic protobuf envelopes and an injectable BLE boundary. They cover service filtering, modern/legacy chip preflight, PIN validation and selected-device scoping, successful config nonce/readback, malformed protobufs, stale/missing config evidence, cancel while PIN entry is pending, notification bursts, disconnect cleanup and the actual pairing widget. These do not establish physical BLE interoperability.

Before testing, the laptop's BlueZ inventory showed a Meshtastic service on the owner's flashed Heltec V3, with no current bond or connection. On 2026-11-25 the owner reported **"Connected and shows firmware"** after following the new in-app discovery/pairing flow. This is owner-confirmed physical connection and firmware readback evidence; it does not individually validate PIN cancellation, wrong-PIN recovery, reconnect, power-loss handling or messaging. No PIN, private identifier, channel secret or message content is copied here.

## Physical acceptance

1. Disconnect the phone's Meshtastic app; ensure the node is powered and its screen is visible.
2. Open Radios, scroll to Meshtastic connection, discover, and select the intended node.
3. Pair & connect should show the PIN input within MeshHub. Enter the six digits displayed by the node.
4. Confirm Connected appears only after config completion, and verify reported firmware and Heltec V3 hardware model.
5. Disconnect and reconnect; an existing valid bond should avoid requesting another PIN.
6. Cancel during PIN entry and repeat discovery/connection. Wrong PIN or timeout must leave the app disconnected and allow a manual retry.
7. Power down the node while connected; the app must clear readiness. No automatic reconnect, RF send or settings changes should occur.
8. Confirm Firmware Manager refuses USB preflight/flash while the Meshtastic session is connecting or connected.

Meshtastic messaging, config editing and peer RF acceptance remain separate future work.
