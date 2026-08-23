#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${BUILD_DIR:-build}
marker="$repo_root/$build_dir/.active-run"

mkdir -p "$(dirname "$marker")"
: > "$marker"
trap 'unlink "$marker" 2>/dev/null || true' EXIT INT TERM

exec make -C "$repo_root" smoke-components BUILD_DIR="$build_dir"
