# Current handoff

Checkpoint `foundation-recovery-016` is `emergency` in phase `foundation`.

Completed: Removed the non-portable PROCASSINIT warning suppression rejected by pinned Verilator 5.018; RAS and BTB tests, frontend lint, and validation pass.

Next actions:

1. Push foundation-recovery-016 and inspect the pinned Nix/OpenLane smoke run.
2. Record passing CI evidence or fix any remaining closure-specific issue.
3. Seal accepted checkpoint foundation-001, then continue v0.1 fetch integration.

Resume steps:

1. Run `make resume-check`.
2. Read `docs/requirements.md` and `.continuity/CURRENT.yaml`.
3. Continue the recorded next action without relying on chat history.
