# Encrypted history — Linux preview

The desktop app now archives MeshCore incoming messages and outgoing messages explicitly accepted by the local radio. The existing live feed remains a session view. Saved messages can be read offline using the History icon or Settings → Privacy. Archived records cannot send RF or select a live channel. Meshtastic live messaging is still unfinished; no claim of Meshtastic message capture is made.

## Storage and key custody

- `EncryptedMessageRepository` implements the domain `MessageHistoryRepository` / `MessageRepository` ports. The session depends on those ports, not filesystem or keyring APIs.
- Cipher: AES-256-GCM, implemented by `cryptography` 2.9.0. Each committed snapshot has a fresh random 96-bit nonce and a 128-bit authentication tag. A versioned format header is authenticated as additional data. Message text, sender labels, source identity, channel fingerprints, direction, observer timestamps and delivery evidence are all inside the ciphertext.
- Key: random 256-bit key in the persistent default Linux Secret Service collection, under the app-specific `application=org.meshhub.MeshHub` / `purpose=encrypted-message-history-v1` attributes. The key is never a process argument, environment variable, app log, repository artifact or file beside the ciphertext. Only the app's own dedicated item is accessed. A temporary session keyring is rejected.
- Files: `$XDG_DATA_HOME/meshhub/history/messages.mhh`, defaulting to `~/.local/share/meshhub/history/messages.mhh`. Directory mode 0700; vault and writer lock mode 0600. The lock file contains no message data. Symbolic-link vault paths are refused.
- Every write encrypts before touching disk. Only ciphertext is placed in a private temporary file, flushed, then atomically renamed. No plaintext journals, caches, search indexes or message preferences are written. Orphaned temporary files after a crash contain ciphertext. Filesystem metadata, size and modification times remain visible.
- One process owns the advisory writer lock. A second window that cannot acquire it explicitly reports unavailable history and does not overwrite it. Writes within a process are serialized to prevent lost updates.

If an existing vault has a missing/wrong key, invalid format, authentication failure or unsupported size, it is preserved. No replacement key or empty history is silently substituted. New messages remain in memory while saving is unavailable; Settings reports the problem and can retry unsaved storage without RF retransmission. The app does not silently delete old messages when full. Current bounds: 10,000 records and 16 MiB.

## Identity and message evidence

Records retain protocol and source radio public identity. A channel scope includes its slot plus SHA-256 of the radio-reported channel secret; the raw secret is immediately discarded and never persisted. Changed keys or radio identities produce different scopes even when display names and slots match. Direct-message scopes retain the protocol's unverified public-key prefix rather than claiming a verified full peer identity.

Exact repeated received frames within a source scope have a stable SHA-256 archive ID, preventing duplicate stored entries across reconnects/restarts. Accepted outbound attempts have random archive IDs, so deliberate repeated sends are not collapsed. No archive record causes an outbound retry. A local acceptance is always labeled recipient-delivery-unverified, including after reopening history. Failed/uncertain attempts and drafts are not stored as accepted messages. Simulated messages are rejected by the real-history repository.

Messages received while channel discovery is pending are held in memory until the channel fingerprint is verified. If identity cannot be established before disconnection, the app reports that those messages remain in memory rather than assigning them to an unverified historical scope. Historical data is deliberately separate from the live channel list to avoid replaying old slot bindings against a different radio.

## Threat model and limits

This protects archived content against offline disclosure and detects ciphertext tampering when the encryption key is unavailable to the attacker. Protection depends on OS keyring security and disk/session protection. It is not an application lock: another process with access to the unlocked user keyring or the app's running memory may access the key/content. Message plaintext is necessarily present in memory while displayed; swap/crash-dump protection is an OS responsibility. No app PIN, automatic screen-lock key eviction, cloud sync, key export, encrypted backup UI, secure deletion or cryptographic rollback detection is implemented.

Losing the keyring item makes its vault unreadable. Copying only the history file is not a usable backup. The app never resets unreadable history automatically. An abrupt process kill or power loss may lose an in-flight/unflushed save; the last available authenticated snapshot is used, subject to filesystem durability. Unsaved state should be resolved before closing the app.

This milestone uses a bounded encrypted snapshot rather than claiming SQLCipher/SQLite support. It avoids plaintext SQL journals/indexes and native database packaging while providing real authenticated persistence now. Larger-history indexing, retention management, migration to an encrypted database and backup/recovery tooling remain separate work.

## Verification and references

Repository tests use real AES-GCM and synthetic data: ciphertext scans for plaintext/key markers, close/reopen round trips, fresh nonces, tampering/wrong/missing keys, unavailable keyrings, private file permissions, concurrent appends, protocol/radio separation, simulation exclusion, size/retention limits, symlink refusal and cross-process writer locking. Integration tests exercise actual Companion frames with a fake BLE boundary, accepted-vs-uncertain sends, frame deduplication, changing channel/radio identities, keyring recovery without RF replay, and offline archive navigation/search.

The laptop's real persistent default keyring was also verified with `dart run tool/history_keyring_probe.dart`: synthetic encrypted content was saved, the vault closed, and content recovered using the keyring-held key. The probe printed no key or message content and removed only its disposable temporary vault. The dedicated master key remains in the OS keyring for the app. This is local storage evidence, not peer RF delivery evidence.

- Cryptography API and nonce/authentication guidance: https://pub.dev/packages/cryptography and https://pub.dev/documentation/cryptography/2.9.0/cryptography/AesGcm-class.html
- GNOME Secret Service / libsecret: https://gnome.pages.gitlab.gnome.org/libsecret/
- New packages: `cryptography` 2.9.0 (Apache-2.0), `crypto` 3.0.8 and `typed_data` 1.4.0 (BSD-style licenses). `dbus` 0.8.1 was already present through BlueZ and is now a direct runtime dependency for verifying the persistent keyring alias. License texts remain in the installed package distributions; a full release audit remains pending.
