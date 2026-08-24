# Current handoff

Checkpoint `foundation-recovery-015` is `emergency` in phase `foundation`.

Completed: Enabled C++20 together with coroutine support for every timing-enabled Verilator harness; local clean harness build and execution pass.

Next actions:

1. Push foundation-recovery-015 and inspect the pinned Nix/OpenLane smoke run.
2. Record passing CI evidence or fix any remaining closure-specific issue.
3. Seal accepted checkpoint foundation-001, then continue v0.1 fetch integration.

Resume steps:

1. Run `make resume-check`.
2. Read `docs/requirements.md` and `.continuity/CURRENT.yaml`.
3. Continue the recorded next action without relying on chat history.
