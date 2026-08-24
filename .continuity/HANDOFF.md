# Current handoff

Checkpoint `foundation-recovery-014` is `emergency` in phase `foundation`.

Completed: Passed the upstream Verilator 5.018 coroutine flag explicitly to every timing-enabled harness build; local timing-unit compilation and execution pass.

Next actions:

1. Push foundation-recovery-014 and inspect the pinned Nix/OpenLane smoke run.
2. Record passing CI evidence or fix any remaining closure-specific issue.
3. Seal accepted checkpoint foundation-001, then continue v0.1 fetch integration.

Resume steps:

1. Run `make resume-check`.
2. Read `docs/requirements.md` and `.continuity/CURRENT.yaml`.
3. Continue the recorded next action without relying on chat history.
