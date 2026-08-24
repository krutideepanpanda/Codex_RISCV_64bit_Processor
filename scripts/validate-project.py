#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fast validation for repository control files and the normative UDB profile."""

from __future__ import annotations

import base64
import json
import hashlib
from pathlib import Path
import re
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


def repository_path(value: Any, *, field: str) -> Path:
    if not isinstance(value, str) or not value or Path(value).is_absolute():
        raise ValidationError(f"{field} must be a non-empty repository-relative path")
    path = (ROOT / value).resolve()
    try:
        path.relative_to(ROOT.resolve())
    except ValueError as exc:
        raise ValidationError(f"{field} escapes the repository") from exc
    return path


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
    paths.extend(sorted((ROOT / ".continuity" / "ci").glob("*.json")))
    paths.extend(sorted((ROOT / ".continuity" / "recovery-drills").glob("*.json")))
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


def validate_dependency_lock() -> None:
    dependency_lock = load_json(ROOT / "config" / "dependencies.lock.json")
    flake_lock = load_json(ROOT / "flake.lock")
    if flake_lock.get("version") != 7 or flake_lock.get("root") != "root":
        raise ValidationError("flake.lock must use the expected v7 root schema")

    nodes = flake_lock.get("nodes")
    if not isinstance(nodes, dict):
        raise ValidationError("flake.lock nodes must be an object")
    root_node = nodes.get(flake_lock["root"], {})
    root_inputs = root_node.get("inputs", {})
    nixpkgs_name = root_inputs.get("nixpkgs")
    openlane_name = root_inputs.get("openlane")
    if not isinstance(nixpkgs_name, str) or not isinstance(openlane_name, str):
        raise ValidationError("flake.lock root must directly select nixpkgs and OpenLane nodes")
    openlane_node = nodes.get(openlane_name, {})
    nix_eda_name = openlane_node.get("inputs", {}).get("nix-eda")
    if not isinstance(nix_eda_name, str):
        raise ValidationError("selected OpenLane node must directly select a nix-eda node")

    sources = dependency_lock.get("sources", {})
    comparisons = {
        "nixpkgs revision": (
            nodes.get(nixpkgs_name, {}).get("locked", {}).get("rev"),
            sources.get("nixpkgs", {}).get("revision"),
        ),
        "nixpkgs NAR hash": (
            nodes.get(nixpkgs_name, {}).get("locked", {}).get("narHash"),
            sources.get("nixpkgs", {}).get("nar_hash"),
        ),
        "OpenLane revision": (
            openlane_node.get("locked", {}).get("rev"),
            sources.get("efabless/openlane2", {}).get("revision"),
        ),
        "nix-eda revision": (
            nodes.get(nix_eda_name, {}).get("locked", {}).get("rev"),
            sources.get("efabless/openlane2", {}).get("nix_eda_revision"),
        ),
    }
    mismatches = [name for name, (actual, expected) in comparisons.items()
                  if not actual or actual != expected]
    if mismatches:
        raise ValidationError("flake/dependency lock mismatch: " + ", ".join(mismatches))

    sv2v = dependency_lock.get("local_tools", {}).get("sv2v", {})
    try:
        source_bytes = bytes.fromhex(sv2v["artifact_sha256"])
        expected_sri = "sha256-" + base64.b64encode(source_bytes).decode("ascii")
        expected_url = sv2v["artifact_url"]
    except (KeyError, TypeError, ValueError) as exc:
        raise ValidationError("sv2v dependency requires a valid URL and SHA-256") from exc
    if len(source_bytes) != 32:
        raise ValidationError("sv2v artifact_sha256 must encode exactly 32 bytes")
    flake_text = (ROOT / "flake.nix").read_text(encoding="utf-8")
    package = re.search(
        r'sv2vPackage\s*=\s*pkgs\.stdenv\.mkDerivation\s*\{(?P<body>.*?)\n\s*\};\n\s*in\s*\{',
        flake_text,
        flags=re.DOTALL,
    )
    if not package:
        raise ValidationError("flake.nix has no recognizable sv2v derivation")
    package_body = package.group("body")
    fetch = re.search(
        r'src\s*=\s*pkgs\.fetchurl\s*\{(?P<body>.*?)\};',
        package_body,
        flags=re.DOTALL,
    )
    if not fetch:
        raise ValidationError("flake.nix has no recognizable sv2v artifact fetch")
    body = fetch.group("body")
    if f'url = "{expected_url}";' not in body or f'hash = "{expected_sri}";' not in body:
        raise ValidationError("flake.nix sv2v source differs from dependency lock")
    version = sv2v.get("version")
    platform = sv2v.get("artifact_platform")
    if (not isinstance(version, str) or f'version = "{version}";' not in package_body
            or not isinstance(platform, str)
            or f'platforms = [ "{platform}" ];' not in package_body):
        raise ValidationError("flake.nix sv2v version/platform differs from dependency lock")


def validate_recovery_drills() -> None:
    state = load_json(ROOT / ".continuity" / "CURRENT.yaml")
    run_by_id = {
        run.get("id"): run for run in state.get("runs", [])
        if isinstance(run, dict) and isinstance(run.get("id"), str)
    }
    for record_path in sorted((ROOT / ".continuity" / "recovery-drills").glob("*.json")):
        record = load_json(record_path)
        drill_id = record.get("id")
        if record.get("schema_version") != 1 or record.get("status") != "pass":
            raise ValidationError(f"{record_path.relative_to(ROOT)} is not a passing v1 record")
        if drill_id != record_path.stem:
            raise ValidationError(f"{record_path.relative_to(ROOT)} id does not match its filename")
        log_path = repository_path(record.get("log"), field=f"{drill_id}.log")
        if not log_path.is_file() or sha256(log_path) != record.get("log_sha256"):
            raise ValidationError(f"{record_path.relative_to(ROOT)} log is missing or stale")
        run = run_by_id.get(drill_id)
        if not run or run.get("status") != "pass" or run.get("log") != record.get("log"):
            raise ValidationError(f"CURRENT.yaml does not reference recovery drill {drill_id}")
        if run.get("sha256") != record.get("log_sha256"):
            raise ValidationError(f"CURRENT.yaml has a stale log hash for {drill_id}")
    test = state.get("tests", {}).get("fresh-task recovery smoke")
    if test:
        record_path = repository_path(test.get("record"), field="fresh-task recovery record")
        if not record_path.is_file() or sha256(record_path) != test.get("sha256"):
            raise ValidationError("CURRENT.yaml has stale fresh-task recovery evidence")


def validate_ci_evidence() -> None:
    state = load_json(ROOT / ".continuity" / "CURRENT.yaml")
    run_by_id = {
        run.get("id"): run for run in state.get("runs", [])
        if isinstance(run, dict) and isinstance(run.get("id"), str)
    }
    for record_path in sorted((ROOT / ".continuity" / "ci").glob("*.json")):
        record = load_json(record_path)
        record_id = record.get("id")
        if record.get("schema_version") != 1 or record.get("status") != "pass":
            raise ValidationError(f"{record_path.relative_to(ROOT)} is not a passing v1 record")
        if record_id != record_path.stem:
            raise ValidationError(f"{record_path.relative_to(ROOT)} id does not match its filename")
        if not re.fullmatch(r"[0-9a-f]{40}", str(record.get("head_sha", ""))):
            raise ValidationError(f"{record_path.relative_to(ROOT)} has an invalid head SHA")
        run = run_by_id.get(record_id)
        relative = str(record_path.relative_to(ROOT))
        if not run or run.get("status") != "pass" or run.get("record") != relative:
            raise ValidationError(f"CURRENT.yaml does not reference CI evidence {record_id}")
        if run.get("sha256") != sha256(record_path):
            raise ValidationError(f"CURRENT.yaml has a stale CI evidence hash for {record_id}")


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
        validate_dependency_lock()
        validate_toml()
        validate_skills()
        validate_udb_profile()
        validate_recovery_drills()
        validate_ci_evidence()
    except ValidationError as exc:
        print(f"project validation error: {exc}", file=sys.stderr)
        return 2
    print("project control files: valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
