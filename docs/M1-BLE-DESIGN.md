# M1 MeshCore Companion 1.18.0 BLE design notes

These are **source-backed hypotheses**, not validation of the owner's physical Heltec. The tag `companion-v1.18.0` documents the firmware behavior below; compare every assumption with live device evidence before an M1 pass.

## Linux boundary and privacy

- Use `bluez` 0.9.0 (MPL-2.0) for the first Linux-only implementation. It exposes BlueZ discovery, pairing, GATT and notifications on the system D-Bus. Its presence proves no device compatibility. `bluetooth_low_energy` 6.2.1 remains a candidate; its Linux central API does not expose pairing and delegates to `bluez` internally.
- Keep BlueZ and device path/address out of the domain package and logs. A name or advertised UUID is a **candidate**; require explicitly selected device and verified GATT/firmware readback before labeling it ready. Do not auto-pair an arbitrary nearby advertisement. Present PIN requests through an intentional pairing flow, never log or persist them.
- Keep `RadioTransport` responsible for full binary BLE frames and connection lifecycle; a MeshCore-only adapter owns protocol commands and parses responses. Do not reuse it for Meshtastic. Preserve `MessageRepository` independence and do not persist real received text until encrypted storage exists.

## Source protocol details to test on-device

- ESP32 firmware service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`; app writes RX `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`, receives notifications on TX `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`. RX write and TX read require encrypted MITM; the firmware requests Secure Connections, MITM, bonding. The Heltec build has a default PIN constant but may generate a session PIN or use a saved PIN: **do not assume the default**. Source: `src/helpers/esp32/SerialBLEInterface.cpp` and `examples/companion_radio/main.cpp` at tag `companion-v1.18.0`.
- This BLE implementation enqueues one characteristic write as one full frame and emits one notification per frame; maximum firmware frame size is 176 bytes. Validate negotiated write capacity/MTU with the actual device; do not split one MeshCore command into multiple writes. Subscribe before commands; serialize request/reply and distinguish asynchronous pushes. Source: `src/helpers/esp32/SerialBLEInterface.cpp`, `src/helpers/BaseSerialInterface.h`, and `docs/companion_protocol.md` at the same tag.
- Read-only initialization: `APP_START` (`01` + seven reserved bytes, optional name) yields `SELF_INFO` (`05`) with public-key identity and node info; `DEVICE_QUERY` (`16 03`) requests client protocol V3 and yields `DEVICE_INFO` (`0D`) with protocol version, build/model, firmware version **and a sensitive PIN field**. Do not output the PIN; compare returned firmware and identity to the owner-designated Heltec. Protocol version is not the release version. Source: `examples/companion_radio/MyMesh.cpp` tagged `companion-v1.18.0`, command handler around lines 1055–1117.
- Push `83` says messages are waiting; send `0A` to drain until the `0A` no-more response. With V3 receive frames, `10` is a direct message and `11` a channel message, with distinct layouts/offsets. Decode defensively; duplicates and sender provenance need separate tests. The M0 in-memory fixture is for synthetic data, not a store for real private history. Source: `examples/companion_radio/MyMesh.cpp` and `docs/companion_protocol.md` at this tag.
- Sending a direct text (`02`) can yield `06` acceptance plus a later `82` ACK; channel send (`03`) returns `00` on success in the tagged *handler*, contrary to a statement in the tagged guide that it returns `06`. GATT write acknowledgment, radio acceptance, and recipient reception are separate states. Do not automatically replay an uncertain send on reconnection. Test an explicitly selected destination and region-legal RF configuration with a second real endpoint. Source: `examples/companion_radio/MyMesh.cpp` around lines 1132–1197; compare `docs/companion_protocol.md` around lines 274–295.

## Primary sources

- https://github.com/meshcore-dev/MeshCore/blob/companion-v1.18.0/src/helpers/esp32/SerialBLEInterface.cpp
- https://github.com/meshcore-dev/MeshCore/blob/companion-v1.18.0/examples/companion_radio/MyMesh.cpp
- https://github.com/meshcore-dev/MeshCore/blob/companion-v1.18.0/docs/companion_protocol.md
- https://github.com/canonical/bluez.dart/tree/0.9.0/lib/src
- https://github.com/bluez/bluez/tree/master/doc

## Acceptance blocker

Earlier scans found no candidate; a later read-only BlueZ scan found **one fresh service-UUID candidate**. This is not device identity proof: the name and BlueZ-known UUID are hints, and the candidate is unpaired with no firmware readback. Confirm with the owner before pairing; authenticated GATT and device info must match the designated Heltec. A second MeshCore endpoint is required for over-air proof. Record actual test IDs/results in `docs/M1-HARDWARE-RESULTS.md` and stop for review rather than merging M1.
