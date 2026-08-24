#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ! -f "$repo_root/config/openlane/config.json" ]]; then
  echo "GDS flow is not enabled yet: config/openlane/config.json is absent." >&2
  echo "Complete RTL, SRAM qualification, and synthesis acceptance first." >&2
  exit 2
fi

if [[ ${CODEX_RV64_PINNED_NIX:-0} != 1 ]]; then
  exec "$repo_root/scripts/nix-container.sh" gds
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "Pinned Nix container marker is set but nix is unavailable." >&2
  exit 2
fi

marker="$repo_root/build/.active-run"
mkdir -p "$(dirname "$marker")"
: > "$marker"
trap 'unlink "$marker" 2>/dev/null || true' EXIT INT TERM

nix --extra-experimental-features "nix-command flakes" develop \
  --no-update-lock-file --accept-flake-config "$repo_root#default" --command \
  nix --extra-experimental-features "nix-command flakes" run \
  --no-update-lock-file --accept-flake-config \
  "$repo_root#openlane" -- "$repo_root/config/openlane/config.json"
