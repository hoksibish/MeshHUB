# meshhub_domain

Protocol-neutral data types and adapter/repository ports for MeshHub. MeshCore and Meshtastic remain distinct protocols; a matching contact name never implies shared identity or channel compatibility.

`lib/testing.dart` contains **simulation-only** adapters, fake byte transport and ephemeral fixture messages. It neither opens a radio connection nor persists private messages. `SendStatus.simulated` is not RF transmission or delivery evidence; `ConversationTarget` binds sends to a protocol.

Run tests:

```bash
export PATH="$HOME/.local/share/flutter-sdk/bin:$HOME/.local/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true
flutter pub get
flutter analyze
flutter test
```

Encrypted on-disk storage, real transport implementations and capability negotiation are later milestone work; see `../../DECISIONS.md`.

## MeshCore Companion codec (v1.18.0, bytes only)

Import `package:meshhub_domain/meshcore_protocol.dart` separately. `MeshCoreCompanionCodec` encodes APP_START (`01` + seven reserved zero bytes + UTF-8 app name) and DEVICE_QUERY (`16 03`), and parses `DEVICE_INFO` (`0D`). The public result contains firmware code, doubled contact capacity, channel capacity, build, model and version. **Bytes 4–7 contain the BLE PIN and are discarded, not exposed by the API.** For v3+ the fixed fields end at byte 79; later trailing bytes are ignored. Legacy (<3), truncated and malformed frames are rejected.

Incoming text only accepts v3 channel `11` (slot at byte 4, path at 5, text type at 6, LE timestamp at 7–10, text at 11+) or direct `10` (six-byte contact prefix at 4–9, path at 10, text type at 11, LE timestamp at 12–15, optional four-byte signed-plain metadata at 16–19, text at 16/20+). SNR is signed byte 1 divided by four; bytes 2–3 are reserved. Only plain channel and plain/signed-plain direct text are accepted. The caller must pass `maxChannels` from a valid device-info response; the parser validates slot, encoded path length, byte ranges, UTF-8, text type, frame bounds (176 bytes), and rejects empty/NUL text. The result labels `MeshProtocol.meshCore` and channel vs direct origin. A channel slot is **not** a verified sender; a direct six-byte prefix is **not** a full authenticated identity. Path length is receive metadata, not a route to reuse (`0xff` means direct on receive).

Outbound `ConversationTarget` is required to be MeshCore: channel `id` is a canonical decimal slot index in `[0, maxChannels)`, direct `id` is exactly 12 lowercase hexadecimal digits (the firmware's six-byte contact lookup prefix). Callers must resolve the intended contact and channel independently before encoding; a prefix alone does not prove identity or eliminate collisions. Timestamps are unsigned 32-bit Unix seconds, little-endian. Text is capped conservatively at **133 UTF-8 bytes** (not characters), and empty/NUL text is rejected; no automatic splitting or retry. Channel command `03 00 <slot> <time> <text>` expects local `OK` (`00`), while direct command `02 00 00 <time> <prefix> <text>` expects `SENT` (`06` + nine bytes). This distinction follows the tagged firmware implementation, despite the docs' channel-send section calling the response `MSG_SENT`. `parseSendResponse` returns only **local radio acceptance/rejection**; a BLE write, `OK`, or `SENT` never proves recipient delivery. Unmatched responses, ACK pushes and malformed replies are rejected; the caller must serialize commands and match the pending operation. No device control, hardware transport, persistence or RF verification is implemented here.

Source: [tagged `MyMesh.cpp`](https://github.com/meshcore-dev/MeshCore/blob/companion-v1.18.0/examples/companion_radio/MyMesh.cpp), particularly lines 9–92, 440–465, 558–583, 1055–1075, 1132–1196; [tagged `Packet.cpp`](https://github.com/meshcore-dev/MeshCore/blob/companion-v1.18.0/src/Packet.cpp#L13-L18) and [tagged `MeshCore.h`](https://github.com/meshcore-dev/MeshCore/blob/companion-v1.18.0/src/MeshCore.h#L22) for encoded path bounds; [tagged companion protocol](https://github.com/meshcore-dev/MeshCore/blob/companion-v1.18.0/docs/companion_protocol.md), especially commands and incoming v3 layout. Fixtures are synthetic, with no personal PINs, keys or messages. Run `flutter test test/meshcore_protocol_test.dart`; this is codec validation only, **not** the M1 hardware send/receive gate.
