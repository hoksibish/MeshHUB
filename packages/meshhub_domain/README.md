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
