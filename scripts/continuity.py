#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Deterministic checkpoint and recovery utility for the project."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
STATE_PATH = ROOT / ".continuity" / "CURRENT.yaml"
HANDOFF_PATH = ROOT / ".continuity" / "HANDOFF.md"
CHECKPOINT_DIR = ROOT / ".continuity" / "checkpoints"
LOCK_PATH = ROOT / "config" / "dependencies.lock.json"
ACTIVE_RUN_MARKER = ROOT / "build" / ".active-run"
REQUIRED_STATE_KEYS = {
    "schema_version", "checkpoint_id", "checkpoint_ref", "mode", "phase",
    "work_packet", "owners", "completed", "next_actions", "blockers",
    "tests", "seeds", "waivers", "tool_lock_sha256", "runs", "artifacts",
}


class ContinuityError(RuntimeError):
    pass


def run(args: list[str], *, capture: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args, cwd=ROOT, check=True, text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ContinuityError(f"cannot read {path.relative_to(ROOT)}: {exc}") from exc
    if not isinstance(value, dict):
        raise ContinuityError(f"{path.relative_to(ROOT)} must contain an object")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def null_paths(value: Any, prefix: str = "") -> list[str]:
    missing: list[str] = []
    if value is None:
        missing.append(prefix or "<root>")
    elif isinstance(value, dict):
        for key, child in value.items():
            missing.extend(null_paths(child, f"{prefix}.{key}" if prefix else key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            missing.extend(null_paths(child, f"{prefix}[{index}]"))
    return missing


def git_status() -> list[str]:
    output = run(["git", "status", "--porcelain=v1", "--untracked-files=all"]).stdout
    return [line for line in output.splitlines() if line]


def validate_state(*, require_clean: bool | None = None, require_locked: bool = False) -> dict[str, Any]:
    state = read_json(STATE_PATH)
    absent = sorted(REQUIRED_STATE_KEYS - state.keys())
    if absent:
        raise ContinuityError(f"CURRENT.yaml is missing keys: {', '.join(absent)}")
    lock = read_json(LOCK_PATH)
    actual_lock_hash = sha256(LOCK_PATH)
    recorded = state.get("tool_lock_sha256")
    if recorded is not None and recorded != actual_lock_hash:
        raise ContinuityError("dependency lock hash differs from CURRENT.yaml")
    if require_locked:
        missing = null_paths(lock.get("sources", {}))
        if missing:
            raise ContinuityError("unresolved dependency lock fields: " + ", ".join(missing))
    accepted = state.get("mode") == "accepted"
    if require_clean is None:
        require_clean = accepted
    dirty = git_status()
    if require_clean and dirty:
        raise ContinuityError("worktree is dirty:\n" + "\n".join(dirty))
    if accepted:
        checkpoint_ref = state.get("checkpoint_ref")
        if not checkpoint_ref:
            raise ContinuityError("accepted state has no checkpoint_ref")
        head = run(["git", "rev-parse", "HEAD"]).stdout.strip()
        tagged = run(["git", "rev-list", "-n", "1", checkpoint_ref]).stdout.strip()
        if head != tagged:
            raise ContinuityError(f"HEAD {head} is not {checkpoint_ref} ({tagged})")
    return state


def command_check() -> None:
    state = validate_state()
    print(f"continuity state: {state['mode']} {state['checkpoint_id']} ({state['phase']})")
    dirty = git_status()
    if dirty and state.get("mode") != "accepted":
        print(f"working state contains {len(dirty)} uncommitted path(s); preserved for inspection")


def command_resume() -> None:
    state = validate_state(require_clean=False)
    print(HANDOFF_PATH.read_text(encoding="utf-8").rstrip())
    dirty = git_status()
    if dirty:
        print(f"\nNOTICE: preserving {len(dirty)} uncommitted path(s); no recovery mutation was performed")
    print("\nRunning deterministic smoke regression...")
    run(["make", "smoke"], capture=False)
    print(f"resume check passed for {state['work_packet']}")


def command_checkpoint(args: argparse.Namespace) -> None:
    if ACTIVE_RUN_MARKER.exists():
        raise ContinuityError(f"active run marker exists: {ACTIVE_RUN_MARKER.relative_to(ROOT)}")
    if run(["git", "tag", "--list", f"checkpoint/{args.id}"]).stdout.strip():
        raise ContinuityError(f"checkpoint/{args.id} already exists")
    mode = "emergency" if args.emergency else "accepted"
    if not args.emergency:
        validate_state(require_clean=False, require_locked=True)
        run(["make", "smoke"], capture=False)
    lock_hash = sha256(LOCK_PATH)
    prior_changes = git_status()
    state = read_json(STATE_PATH)
    state.update({
        "checkpoint_id": args.id,
        "checkpoint_ref": None if args.emergency else f"checkpoint/{args.id}",
        "mode": mode,
        "phase": args.phase,
        "work_packet": args.id,
        "completed": [args.summary],
        "next_actions": [args.next_action],
        "tool_lock_sha256": lock_hash,
        "tests": {"make smoke": "not-run (emergency)" if args.emergency else "pass"},
        "runs": [],
        "artifacts": [],
    })
    write_json(STATE_PATH, state)
    HANDOFF_PATH.write_text(
        "# Current handoff\n\n"
        f"Checkpoint `{args.id}` is `{mode}` in phase `{args.phase}`.\n\n"
        f"Completed: {args.summary}\n\n"
        f"Next action: {args.next_action}\n\n"
        "Resume steps:\n\n"
        "1. Run `make resume-check`.\n"
        "2. Read `docs/requirements.md` and `.continuity/CURRENT.yaml`.\n"
        "3. Continue the recorded next action without relying on chat history.\n",
        encoding="utf-8",
    )
    write_json(CHECKPOINT_DIR / f"{args.id}.yaml", {
        "schema_version": 1, "id": args.id, "mode": mode,
        "phase": args.phase, "summary": args.summary,
        "next_action": args.next_action,
        "dependency_lock_sha256": lock_hash,
        "pre_checkpoint_changes": prior_changes,
        "tests": state["tests"],
    })
    run(["git", "add", "-A"])
    subject = ("wip checkpoint: " if args.emergency else "checkpoint: ") + args.id
    run(["git", "commit", "-m", subject], capture=False)
    if not args.emergency:
        run(["git", "tag", "-a", f"checkpoint/{args.id}", "-m", args.summary])
    if git_status():
        raise ContinuityError("checkpoint commit did not leave a clean worktree")
    print(f"created {mode} checkpoint {args.id}")


def command_release_gate() -> None:
    state = validate_state(require_clean=True, require_locked=True)
    if state.get("phase") != "v1.0.0":
        raise ContinuityError("release gate requires phase v1.0.0")
    required = [
        ROOT / "artifacts/signoff/v1.0.0/SHA256SUMS",
        ROOT / "artifacts/compliance/v1.0.0/act-report.json",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        raise ContinuityError("release evidence missing: " + ", ".join(missing))
    print("v1.0 release evidence gate passed")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("check")
    subparsers.add_parser("resume")
    checkpoint = subparsers.add_parser("checkpoint")
    checkpoint.add_argument("--id", required=True)
    checkpoint.add_argument("--phase", required=True)
    checkpoint.add_argument("--summary", required=True)
    checkpoint.add_argument("--next-action", required=True)
    checkpoint.add_argument("--emergency", action="store_true")
    subparsers.add_parser("release-gate")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "check": command_check()
        elif args.command == "resume": command_resume()
        elif args.command == "checkpoint": command_checkpoint(args)
        elif args.command == "release-gate": command_release_gate()
    except (ContinuityError, subprocess.CalledProcessError) as exc:
        print(f"continuity error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
