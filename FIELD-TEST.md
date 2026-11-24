# MeshHub M1 Field Test v0.1 (Omarchy Linux)

**Checkpoint:** Development remains on `feature/m1-meshcore-ble`; do not merge M1. This is a field-test build, not a validated over-the-air release. The real Heltec was read back as Heltec V3, MeshCore Companion `v1.18.0-81dbae5`, protocol 14. A local BLE disconnect/reconnect completed a fresh Companion handshake on 2026-11-24 UTC; radio power-cycle, range, BlueZ restart, and real RF messaging remain unverified.

## Build and launch

From `/home/jbarr/MeshHUB`:

```bash
cd apps/meshhub_flutter
flutter pub get
flutter build linux --release
cd ../..
./run-field-test.sh --check
./run-field-test.sh
```

The script launches `apps/meshhub_flutter/build/linux/x64/release/bundle/meshhub_flutter` from its bundle directory. It does not install a system package or edit Omarchy configuration. Run it in your logged-in Omarchy graphical session; if the executable is missing, build first. The Linux runner now provides a draggable GTK title bar with minimize, maximize and close controls; the window remains resizable. No firmware update, radio configuration write, or RF command happens on launch.

## Before going into the field

1. Power the Heltec and ensure Bluetooth is on. Pair it through the local OS Bluetooth dialog if needed; **never type a PIN into MeshHub, a chat, or a log**.
2. Open **Radios** → **Discover MeshCore radios**. Select the owner-confirmed Heltec by name; name and cached service UUID are hints, while the authenticated GATT/Companion handshake and device-reported model/firmware are the actual verification. Tap **Connect**. The app does not pair on your behalf.
3. Confirm the panel says **Companion ready**, Bluetooth **connected, paired**, model **Heltec V3**, firmware **`v1.18.0-81dbae5`** (or record any actual difference), protocol, and RF settings. Previously observed: **910,525 kHz**, **62,500 Hz bandwidth**, **SF7**, **CR5**. The displayed values are read-only; MeshHub does not adjust them.
4. Open **Inbox → Channels** after Companion ready. The app reads every channel slot from the selected radio using read-only `GET_CHANNEL` and shows only configured names, with slot numbers. Tap a channel to open its session-only feed; on a narrow window use **All channels** to go back. The radio returns channel secrets in the protocol response, but MeshHub discards them and exposes only names/slots. **Refresh channels** rereads without changing channel settings. If the read is incomplete, the UI says so rather than inventing channels.
5. **Show simulated examples** is off by default; keep it off for live-only field testing. Simulated data stays visibly separate from real channel feeds. Real messages, channel names and local-post markers are **RAM only**, lost when the process exits. When the radio signals queued messages, the app drains up to 32 responses per event into this volatile inbox. Do not rely on this build as your only archive of a radio's queued messages.
6. Confirm the operating country/region and that the **actual** preset is appropriate there before any RF send. Confirm a second reachable MeshCore endpoint and the intended destination with the peer operator. The app cannot establish RF legality or whether a channel key/contact actually matches; do not check the verification box until you have checked those externally.

## Receive and send with a second endpoint

1. Have the peer send a distinctive small test text on the agreed MeshCore channel or to the agreed contact. Watch **Field diagnostics** for `waiting pushes` and `received`; in **Inbox**, open the named channel and inspect the new post. Channel messages do **not** prove a named sender; direct messages expose only a six-byte prefix, not authenticated full identity. Record peer-side send time and your receive time without publishing private content.
2. To send a channel message, open **Inbox → Channels → [radio-reported name]**. Check the displayed slot number and RF preset. Type in the inline **Post to [channel]** composer; verify region, destination and reachable peer, then check the explicit verification box and tap **Post once to selected channel**. No manual channel number is needed. For direct messages only, use **Radios → Direct test message** and an independently verified **12-character lowercase hexadecimal public-key prefix**. Never paste a private key, channel key or PIN. Validation enforces UTF-8 byte limits and protocol-bound destination format.
3. Compare the displayed preset to the peer's setting and verify RF region, destination, and reachable peer. Only then check the explicit verification box. The inline **Post once** button remains disabled until the Companion handshake and that confirmation; each send clears the confirmation. Neither a GATT write nor local acceptance proves RF delivery.
4. The diagnostic says **Accepted by local radio — recipient delivery unverified** only when the Companion handler accepts the command. Obtain an independent peer-side receipt/ACK and record it separately. If a send is interrupted or times out, treat its outcome as **uncertain**; do not tap again blindly.
5. For duplicate-message testing, ask the peer to resend the *same frame* and note the diagnostic count. In-memory dedupe prevents an identical byte frame from appearing twice, but cross-radio and cold-start dedupe are not validated in v0.1.

**Thread limit:** This is a per-channel chronological feed, not true nested Reddit replies: Companion channel packets carry a channel slot and text, not a reply-to-post ID or authenticated channel sender. A local outbound card appears only after the radio accepts the command, labeled **peer delivery unverified**; it disappears on app exit.

## Reconnection and troubleshooting

- After a normal connection, the app retries an unexpected BLE disconnect on the **same selected paired device** after bounded delays (1, 2, 4…32 seconds). It repeats only read-only startup/device queries; it does not replay messages. Manual **Disconnect** cancels retry. The diagnostic shows retry attempts. A local OS-level disconnect was tested once with the physical Heltec; out-of-range, reboot, Bluetooth off/on, and BlueZ restart are **not** proven.
- If discovery shows nothing: power/advertise the Heltec nearby, check OS Bluetooth power, retry scanning. BlueZ can return cached candidates; a name/service hit alone is not proof.
- If connect fails: check local pairing and Bluetooth authorization; use the OS's interactive pairing flow. No default PIN is assumed. Restart discovery if BlueZ lost the device. Do not reset/flash/change radio settings as a troubleshooting shortcut.
- If Companion ready but no message: confirm a second endpoint, compatible preset, correct configured channel/key or contact, and whether the peer actually transmitted. An `83` push is only a queue notification, not content. The app's count-only diagnostics do not log payloads, keys, BLE addresses, or PINs.
- If a receive drain is interrupted: note the status; keep the app open and coordinate another small peer message. No real-message history is persisted; a cold restart clears the inbox. Preserve an external peer-side record if you need proof.

## Verified local checkpoint (2026-11-24 UTC)

- Domain: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test` — **26 passed**, no analysis issues.
- App: `dart format --output=none --set-exit-if-changed lib test tool`, `flutter analyze`, `flutter test` — **39 passed**, no analysis issues. `flutter build linux --release` succeeded.
- `./run-field-test.sh --check` found the release executable. Running the script in the logged-in Wayland session created a mapped `MeshHub` Hyprland window. The initial background launch landed on a hidden special workspace and lacked title-bar controls; after moving it to workspace 1, the Linux runner was updated and rebuilt with a GTK header bar. A cropped live Wayland capture of the new 900×650 floating window visually confirmed **minimize, maximize and close** buttons plus readable app content. The previous window remains open behind it to avoid discarding any volatile messages without permission.
- The **same `MeshCoreFieldSession` used by the UI** completed a real read-only handshake via `dart run tool/meshcore_field_probe.dart <owner-confirmed-name>`. Its optional `--disconnect-test` deliberately dropped only the local BLE link, then reported one retry, Companion ready, and matching firmware readback. The pre-test OS connection was restored. This probe disables queue drain and never sends RF.

## Evidence sheet for tomorrow

For each case, record **UTC time | host build/commit | radio firmware | BLE/RF preset | action | expected | observed | pass/fail/blocked | sanitized evidence**. Do not include keys, PINs, BLE addresses, exact private payloads, or personal locations in a public issue/PR.

- BLE-01/02/03: discovery → explicit pair/connection → device identity/firmware readback.
- MSG-01: peer sends; live inbox receives once; peer provenance and limitations noted.
- MSG-02: selected destination, one send, local acceptance **and separately** peer receipt/ACK.
- BLE-04/05/06: out of range, radio reboot, Bluetooth off/on and BlueZ restart; note each transition and whether a fresh handshake succeeds. Do not risk a session with an in-flight send.
- BLE-07: permission denial/wrong PIN only when owner deliberately coordinates it; never record a code.
- MSG-03/04: duplicate inbound and disconnect during outbound; do not repeat an uncertain send.

**Gate:** A launchable app and one local BLE recovery do not complete M1. Without the second endpoint, real send/receive/recipient-delivery cases remain blocked. Stop for owner review; no merge without approval.
