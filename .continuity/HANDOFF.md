# Current handoff

Checkpoint `foundation-recovery-012` is `emergency` in phase `foundation`.

Completed: Made TAGE set/way table addresses explicitly sized for pinned Verilator 5.018, added nonzero and maximum address tests, passed 65,779 local checks plus lint/synthesis, and received independent verification READY.

Next actions:

1. Push foundation-recovery-012 and inspect the pinned Nix/OpenLane CI run.
2. Record passing CI evidence or fix any remaining pinned-tool warnings.
3. Seal accepted checkpoint foundation-001, then continue v0.1 fetch integration.

Resume steps:

1. Run `make resume-check`.
2. Read `docs/requirements.md` and `.continuity/CURRENT.yaml`.
3. Continue the recorded next action without relying on chat history.
