# Draft PR: Milestone 0 — MeshHub Omarchy foundation (Issue #1)

**Not submitted.** The branch is local and the repository is public despite the handoff's private-first rule. Owner must confirm visibility and authorize the push/PR.

## What changed

- Import nine approved handoff Markdown files unchanged from the ZIP (archive is local only).
- Add Flutter 3.50.1 Linux app with protocol-filtered simulated inbox, responsive navigation, theme tokens and no-radio screen.
- Add protocol-neutral domain ports, protocol-guarded mock fixtures, a fake byte transport, and a fixed-code redacted diagnostic logger; no RF operations or on-disk private data.
- Add headless Linux CI workflow, setup/run instructions, BLE feasibility evidence, decisions and progress report.

## Local evidence

- `unzip -t MeshHub-Agent-Handoff.zip` — nine entries OK; extracted bytes match.
- `dart format --output=none --set-exit-if-changed lib test` — clean in app and domain.
- `flutter analyze` — no issues in both packages.
- `flutter test` — domain 9 passed, app 2 passed.
- `flutter build linux --release` — succeeded; Linux Wayland app window observed.
- `git diff --check` — passed.
- `bluetoothctl --timeout 8 scan le` — scan started/completed, no MeshCore name/service observed; Dart `bluez` 0.9.0 D-Bus probe connected with one adapter. No pairing or radio I/O.

## Acceptance and known gaps

See `PROGRESS.md` for the full M0 checklist. The local persistence **boundary** exists, but encrypted on-disk storage does not. A real Heltec GATT notification and send/receive test is M1, not proven here. Remote CI and PR status remain unverified until owner-authorized push.

**Do not merge/advance to M1 without owner approval.**
