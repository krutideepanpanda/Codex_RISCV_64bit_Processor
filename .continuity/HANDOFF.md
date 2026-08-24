# Current handoff

Checkpoint `foundation-recovery-011` is `emergency` in phase `foundation`.

Completed: Made the smoke flow hermetic by resolving Makefile Bash through PATH and patching repository script shebangs inside the Nix derivation; local 65,777-check smoke and synthesis pass.

Next actions:

1. Push foundation-recovery-011 and inspect the hermetic pinned Nix/OpenLane CI run.
2. Record passing CI evidence and update the foundation gate.
3. Seal accepted checkpoint foundation-001, then continue v0.1 fetch integration.

Resume steps:

1. Run `make resume-check`.
2. Read `docs/requirements.md` and `.continuity/CURRENT.yaml`.
3. Continue the recorded next action without relying on chat history.
