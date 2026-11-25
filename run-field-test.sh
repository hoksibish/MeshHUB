#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bundle="$repo/apps/meshhub_flutter/build/linux/x64/release/bundle"
app="$bundle/meshhub_flutter"
if [[ ! -x "$app" ]]; then
  printf 'MeshHub release not found. Build with: cd %s/apps/meshhub_flutter && flutter build linux --release\n' "$repo" >&2
  exit 1
fi
if [[ "${1:-}" == '--check' ]]; then
  printf 'MeshHub release executable: %s\n' "$app"
  exit 0
fi
cd -- "$bundle"
exec ./meshhub_flutter "$@"
