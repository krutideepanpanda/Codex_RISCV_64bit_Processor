---
name: project-continuity
description: Checkpoint, hand off, or resume work in this RV64 repository after a reboot, interruption, quota boundary, long EDA run, or task change.
---

# Project continuity

Use Git and `.continuity/CURRENT.yaml` as the source of truth.

1. On resume, run `make resume-check`, read `.continuity/HANDOFF.md`, and inspect—not discard—any reported dirty or interrupted state.
2. Before a boundary, stop active tools, run the required tests, flush logs, and checksum retained artifacts.
3. Use an accepted checkpoint only when the work packet's required checks pass. Use `EMERGENCY=1` to preserve incomplete work without advancing a milestone.
4. Never reset, delete, or overwrite uncommitted work during recovery.
5. Record exact next actions and blockers so a fresh task can continue without chat history.
