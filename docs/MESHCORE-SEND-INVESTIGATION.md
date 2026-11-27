# MeshCore channel-send investigation — 2026-11-27

## Report and scope

The owner reported that an earlier build's channel message reached two participants, while a later inline-composer attempt did not, despite remaining within repeater coverage. This remains an unresolved peer-delivery regression. The earlier success is not acceptance evidence for the current build.

This investigation uses synthetic BLE responses and a disposable encrypted vault. It does not connect to, reconfigure or transmit from a physical radio, and cannot validate GATT/MTU behavior, RF propagation, peer keys, routing or recipient receipt.

## Source comparison

Compared the pre-channel-feed implementation (`82eb7fb`), channel-feed change (`99af379`), and current history baseline (`bcdd2a5`). The UI changed from a manually entered slot to a radio-reported selected slot. `encodeChannelText` remained unchanged. Current bytes are command `3`, plain text type `0`, the selected numeric slot, four little-endian Unix seconds, then UTF-8 text. There is no added terminator, list-position substitution or extra retry byte.

Verified against upstream Companion 1.18.0 [`MyMesh.cpp`, CMD_SEND_CHANNEL_TXT_MSG handler](https://github.com/meshcore-dev/MeshCore/blob/companion-v1.18.0/examples/companion_radio/MyMesh.cpp): the handler reads those fields and passes the remaining byte length to `sendGroupMessage`. It returns one-byte OK on local success or an error response otherwise. This supports the encoder and local acceptance parser; it does not prove recipient delivery.

Command exchanges are serialized with channel discovery and receive-queue drains. The transport submits one complete GATT write request without app-level retries. A software fake does not establish that the physical Bluetooth stack accepts every payload length. No demonstrated cause for the original RF nonreceipt was found; no speculative encoder/routing change was made.

## Reproduced and fixed defect

A delayed local acceptance unconditionally cleared the shared composer. If the user switched from Trail to Public and started another draft while the response was pending, the Trail result erased the new Public draft. The new full-path test failed with an empty draft before the fix. The completion handler now clears text only when the selected slot, channel name and submitted text still match. An edited draft in the same channel is also retained. History retains the original submitted message and channel.

This draft-loss bug is independently established. It does **not** explain or resolve the earlier reported RF failure.

## Composer-to-history coverage

`apps/meshhub_flutter/test/composer_history_test.dart` taps the actual app's Send button. It uses the real `MeshCoreFieldSession`, protocol encoder/response parser, AES-256-GCM repository and archive screen. Only the BLE boundary and key custody are synthetic; no send method is overridden. Disposable files contain synthetic messages only.

- Sparse channel list: select Trail at slot 2, independently assert `[3, 0, 2]`, little-endian current timestamp and unaltered multibyte UTF-8; exactly one send and disabled Send while pending.
- Delayed acceptance: no outgoing card/history before ACK; an interleaved waiting notification is not an ACK. Local acceptance creates one correctly scoped MeshCore record, retaining recipient-delivery-unverified evidence.
- Real ciphertext scan, vault close/reopen and offline archive rendering; no send control or retransmission on archive access.
- Explicit radio rejection, response timeout and physical-style drop: no accepted card/history, late ACK cannot create acceptance, reconnect/history retry never replay the send. Rejection/timeout preserve the current draft.
- Changing channels or editing text while waiting cannot let a late acceptance erase the newer draft.

Widget callbacks that start filesystem work run through `tester.runAsync`; tests coordinate actual IO with widget pumps rather than replacing the session send method. Existing smaller UI and session tests remain useful, but are not a substitute for this combined path.

## Next physical test

Use two compatible MeshCore endpoints within direct reach, or a known working repeated route. Independently confirm presets/channel compatibility outside public logs. On the same test channel, compare one uniquely labeled official-client message and one MeshHub message; do not share a BLE connection between clients. Record app commit, firmware, selected slot, sanitized local counters/outcome and independent recipient result. Do not retry uncertain sends blindly.

Then test inbound receipt and encrypted archive readback after closing/reopening the app. If MeshHub is accepted locally but the peer receives only the reference client's message, investigate actual transmitted fields, timestamp/deduplication behavior, GATT payload length, radio queue and routing/channel configuration. Local acceptance alone cannot distinguish these causes. No M1 acceptance or merge is justified by synthetic tests.
