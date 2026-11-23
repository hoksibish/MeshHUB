# Draft PR: Milestone 0 — MeshHub Omarchy foundation (Issue #1)

**Owner-authorized for submission.** The repository may remain public for M0. Open against `main` from `feature/issue-1-handoff`; reference Issue #1, request review, and do not merge automatically.

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

See `PROGRESS.md` for the full M0 checklist. The owner explicitly accepted the in-memory repository and public repository as M0 exceptions to the handoff. The `MessageRepository` port keeps the messaging domain independent of the fixture implementation; an encrypted store must replace it before real history is retained. The demo UI still uses static samples and will need repository wiring. A real Heltec GATT notification and send/receive test is M1, not proven here. Remote CI status must be checked after push.

**M1 only after this PR is reviewed and merged:** discover Heltec V3 / MeshCore 1.18.0, pair/authenticate, connect, read real metadata, receive, test send, and reconnect. Stop at M1 acceptance; simulated events are not hardware evidence. **Do not merge automatically.**
