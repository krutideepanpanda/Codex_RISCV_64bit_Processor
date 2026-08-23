#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fast validation for repository control files and the normative UDB profile."""

from __future__ import annotations

import json
import hashlib
from pathlib import Path
import sys
import tomllib
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[1]


class ValidationError(RuntimeError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"{path.relative_to(ROOT)}: {exc}") from exc


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


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


def validate_udb_profile() -> None:
    path = ROOT / "verification" / "act" / "codex-rv64-v1.yaml"
    try:
        profile = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        raise ValidationError(f"{path.relative_to(ROOT)}: {exc}") from exc
    if not isinstance(profile, dict) or profile.get("type") != "fully configured":
        raise ValidationError("normative UDB profile must be a fully configured object")
    required = {
        "I", "M", "A", "F", "D", "C", "Zicsr", "Zifencei", "Zicntr",
        "Zihpm", "Zba", "Zbb", "Zbs", "Zicbom", "U", "S", "Sm",
        "Sv39", "Sstc", "Svpbmt", "Svinval", "Svadu", "Sscofpmf", "Smepmp",
    }
    entries = profile.get("implemented_extensions", [])
    names = [entry.get("name") for entry in entries if isinstance(entry, dict)]
    if len(names) != len(entries) or len(names) != len(set(names)):
        raise ValidationError("UDB implemented extensions must be named and unique")
    missing = sorted(required - set(names))
    forbidden = sorted({"H", "V"} & set(names))
    if missing or forbidden:
        raise ValidationError(
            "UDB profile mismatch; missing=" + ",".join(missing)
            + " forbidden=" + ",".join(forbidden)
        )
    params = profile.get("params", {})
    expected = {"MXLEN": 64, "PHYS_ADDR_WIDTH": 40, "NUM_PMP_ENTRIES": 16,
                "CACHE_BLOCK_SIZE": 64, "MISALIGNED_LDST": True}
    wrong = [name for name, value in expected.items() if params.get(name) != value]
    if wrong:
        raise ValidationError("UDB architectural parameters differ: " + ", ".join(wrong))
    for mode in ("M", "S", "U"):
        if params.get(f"{mode}_MODE_ENDIANNESS") != "little":
            raise ValidationError(f"UDB {mode}-mode endianness must be little")
    evidence_path = ROOT / "verification" / "act" / "udb-validation.json"
    evidence = load_json(evidence_path)
    if evidence.get("status") != "pass" or evidence.get("profile_sha256") != sha256(path):
        raise ValidationError("UDB validation evidence is absent, failed, or stale")


def main() -> int:
    try:
        validate_json_control_files()
        validate_toml()
        validate_skills()
        validate_udb_profile()
    except ValidationError as exc:
        print(f"project validation error: {exc}", file=sys.stderr)
        return 2
    print("project control files: valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
