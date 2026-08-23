#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ! -f "$repo_root/config/openlane/config.json" ]]; then
  echo "GDS flow is not enabled yet: config/openlane/config.json is absent." >&2
  echo "Complete RTL, SRAM qualification, and synthesis acceptance first." >&2
  exit 2
fi

if ! command -v nix >/dev/null 2>&1; then
  nix_profile="${HOME}/.nix-profile/etc/profile.d/nix.sh"
  if [[ -r "$nix_profile" ]]; then
    # shellcheck disable=SC1090
    source "$nix_profile"
  fi
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "Nix is not available. Run scripts/bootstrap-tools.sh first." >&2
  exit 2
fi

marker="$repo_root/build/.active-run"
mkdir -p "$(dirname "$marker")"
: > "$marker"
trap 'unlink "$marker" 2>/dev/null || true' EXIT INT TERM

nix --extra-experimental-features "nix-command flakes" develop \
  "$repo_root#default" --command \
  nix --extra-experimental-features "nix-command flakes" run \
  "$repo_root#openlane" -- "$repo_root/config/openlane/config.json"
