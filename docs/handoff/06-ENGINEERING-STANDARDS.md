# Engineering Standards and Repository Plan

## Proposed tree
```
meshhub/
  README.md
  LICENSE-REVIEW.md
  docs/ (copy of approved spec + ADRs + progress reports)
  apps/meshhub_flutter/
  packages/meshhub_domain/
  packages/meshcore_adapter/
  packages/meshtastic_adapter/
  packages/radio_transports/
  packages/local_storage/
  packages/maps_rf/
  test/fixtures/ (synthetic/anonymized only)
  packaging/arch/
  scripts/
```
Agent may adjust to Flutter/Dart workspace conventions only after documenting rationale.

## Quality bar
- Dart format, static analysis, explicit error types, unit tests and adapter contract tests required.
- Protocol parsing must validate lengths, enum ranges, checksums or authentication where present; guard against oversized and malformed packets.
- Use deterministic offline fixtures to test data and UI without a radio; retain binary fixture provenance with no private data.
- Repository CI must not require owner hardware; hardware tests run as a separately labeled suite.
- Mock/simulator data must be clearly flagged in UI and test artifacts.
- No silent background transmissions, retry floods, or message duplication.
- UI accessible by keyboard/screen readers where supported; network labels not color alone; adaptive layouts.
- Document all dependency licenses before any public release; do not copy incompatible code directly from upstream apps.

## Versioning and packaging
- Semantic version tags (pre-release `0.x.y` until stable); changelog and migration notes.
- Omarchy/Arch package first; package metadata, clean user permissions, desktop entry, icons, checksums; no root-running app process.
- Other Linux, macOS, Windows, Android, iOS packaging added as platform work reaches supported status.
- Manual updates must preserve encrypted history and support schema migration/backup and documented rollback.

## Definition of done per PR
Source + tests + updated docs + no secret scan findings + reproducible build + acceptance evidence + clear limitations.
