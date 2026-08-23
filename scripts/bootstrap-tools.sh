#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if ! command -v nix >/dev/null 2>&1; then
  nix_profile="${HOME}/.nix-profile/etc/profile.d/nix.sh"
  if [[ -r "$nix_profile" ]]; then
    # shellcheck disable=SC1090
    source "$nix_profile"
  fi
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "Nix is unavailable. Install the pinned Nix version recorded in" >&2
  echo "config/dependencies.lock.json, then rerun this script." >&2
  exit 2
fi

cd "$repo_root"
exec nix --extra-experimental-features "nix-command flakes" flake check --print-build-logs
