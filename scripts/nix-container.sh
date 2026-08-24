#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

readonly nix_image="docker.io/nixos/nix@sha256:617d914dba5384bf75adf17081583b69371031ec7defce36c34c5fa14fc819b0"
readonly nix_store_volume="codex-rv64-nix-store"
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
action=${1:-check}

if ! command -v podman >/dev/null 2>&1; then
  echo "Podman is required for the immutable-host Nix environment." >&2
  exit 2
fi

case "$action" in
  pull)
    exec podman pull "$nix_image"
    ;;
  check)
    if ! podman image exists "$nix_image"; then
      echo "Pinned Nix image is absent; run 'make nix-pull' first." >&2
      exit 2
    fi
    exec podman run --rm --pull=never --security-opt label=disable \
      --volume "$nix_store_volume:/nix" \
      --volume "$repo_root:/workspace:ro" --workdir /workspace \
      "$nix_image" \
      nix --extra-experimental-features "nix-command flakes" \
      flake check --no-update-lock-file --accept-flake-config --print-build-logs
    ;;
  shell)
    if ! podman image exists "$nix_image"; then
      echo "Pinned Nix image is absent; run 'make nix-pull' first." >&2
      exit 2
    fi
    exec podman run --rm --interactive --tty --pull=never \
      --security-opt label=disable --volume "$nix_store_volume:/nix" \
      --volume "$repo_root:/workspace" \
      --workdir /workspace "$nix_image" \
      nix --extra-experimental-features "nix-command flakes" \
      develop --no-update-lock-file --accept-flake-config
    ;;
  gds)
    if ! podman image exists "$nix_image"; then
      echo "Pinned Nix image is absent; run 'make nix-pull' first." >&2
      exit 2
    fi
    exec podman run --rm --pull=never --security-opt label=disable \
      --volume "$nix_store_volume:/nix" \
      --volume "$repo_root:/workspace" --workdir /workspace \
      --env CODEX_RV64_PINNED_NIX=1 \
      "$nix_image" ./scripts/run-gds.sh
    ;;
  *)
    echo "usage: $0 {pull|check|shell|gds}" >&2
    exit 2
    ;;
esac
