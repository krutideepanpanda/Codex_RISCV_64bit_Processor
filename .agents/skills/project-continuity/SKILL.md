---
name: project-continuity
description: Checkpoint, hand off, or resume work in this RV64 repository after a reboot, interruption, quota boundary, long EDA run, or task change.
---

# Project continuity

Use Git and `.continuity/CURRENT.yaml` as the source of truth.

1. On resume, run the read-only `make recovery-inspect`, then read `.continuity/HANDOFF.md` and inspect—not discard—dirty files, diffs, logs, or run markers.
2. Only after preserving and attributing interrupted evidence, run `make resume-check`; it uses a separate ignored build directory.
3. Before a boundary, stop active tools, run the required tests, flush logs, and checksum retained artifacts.
4. Explicitly stage reviewed paths before an accepted checkpoint. Use `EMERGENCY=1` to preserve all incomplete work without advancing a milestone.
5. Never reset, delete, or overwrite uncommitted work during recovery.
6. Record exact next actions and blockers so a fresh task can continue without chat history.
