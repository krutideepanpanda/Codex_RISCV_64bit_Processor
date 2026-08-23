#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fast, dependency-free validation for repository control files."""

from __future__ import annotations

import json
from pathlib import Path
import sys
import tomllib
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


class ValidationError(RuntimeError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"{path.relative_to(ROOT)}: {exc}") from exc


def null_paths(value: Any, prefix: str = "") -> list[str]:
    result: list[str] = []
    if value is None:
        result.append(prefix or "<root>")
    elif isinstance(value, dict):
        for key, child in value.items():
            result.extend(null_paths(child, f"{prefix}.{key}" if prefix else key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            result.extend(null_paths(child, f"{prefix}[{index}]"))
    return result


def validate_json_control_files() -> None:
    paths = [
        ROOT / ".continuity" / "CURRENT.yaml",
        ROOT / "config" / "dependencies.lock.json",
        ROOT / "config" / "release-manifest.schema.json",
        ROOT / "coordination" / "work-packages.yaml",
    ]
    paths.extend(sorted((ROOT / ".continuity" / "checkpoints").glob("*.yaml")))
    for path in paths:
        value = load_json(path)
        if not isinstance(value, dict):
            raise ValidationError(f"{path.relative_to(ROOT)} must contain an object")

    lock = load_json(ROOT / "config" / "dependencies.lock.json")
    missing = null_paths(lock.get("sources"))
    if missing:
        raise ValidationError("dependency lock contains unresolved values: " + ", ".join(missing))

    dag = load_json(ROOT / "coordination" / "work-packages.yaml")
    packages = dag.get("packages", [])
    ids = [packet.get("id") for packet in packages if isinstance(packet, dict)]
    if len(ids) != len(packages) or len(set(ids)) != len(ids):
        raise ValidationError("work-package IDs must be present and unique")
    known: set[str] = set()
    for packet in packages:
        packet_id = packet["id"]
        unknown = set(packet.get("depends_on", [])) - known
        if unknown:
            raise ValidationError(
                f"{packet_id} depends on unknown or later package(s): {', '.join(sorted(unknown))}"
            )
        known.add(packet_id)


def validate_toml() -> None:
    paths = [ROOT / ".codex" / "config.toml"]
    paths.extend(sorted((ROOT / ".codex" / "agents").glob("*.toml")))
    for path in paths:
        try:
            tomllib.loads(path.read_text(encoding="utf-8"))
        except (OSError, tomllib.TOMLDecodeError) as exc:
            raise ValidationError(f"{path.relative_to(ROOT)}: {exc}") from exc


def validate_skills() -> None:
    skill_root = ROOT / ".agents" / "skills"
    expected = {
        "project-continuity",
        "rtl-block-workflow",
        "formal-differential-verification",
        "linux-soc-bringup",
        "sky130-signoff",
    }
    actual = {path.parent.name for path in skill_root.glob("*/SKILL.md")}
    if actual != expected:
        raise ValidationError(
            "repository skill set differs: expected "
            + ", ".join(sorted(expected))
            + "; found "
            + ", ".join(sorted(actual))
        )
    for name in sorted(expected):
        path = skill_root / name / "SKILL.md"
        lines = path.read_text(encoding="utf-8").splitlines()
        if len(lines) < 5 or lines[0] != "---" or "---" not in lines[1:]:
            raise ValidationError(f"{path.relative_to(ROOT)} has malformed frontmatter")
        end = lines[1:].index("---") + 1
        fields: dict[str, str] = {}
        for line in lines[1:end]:
            key, separator, value = line.partition(":")
            if separator:
                fields[key.strip()] = value.strip()
        if fields.get("name") != name or not fields.get("description"):
            raise ValidationError(f"{path.relative_to(ROOT)} needs matching name and description")


def main() -> int:
    try:
        validate_json_control_files()
        validate_toml()
        validate_skills()
    except ValidationError as exc:
        print(f"project validation error: {exc}", file=sys.stderr)
        return 2
    print("project control files: valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
