# Current handoff

Checkpoint `foundation-recovery-009` is `emergency` in phase `foundation`.

Completed: Replaced failing callCabal2nix sv2v packaging with a SHA-256-pinned upstream x86_64 release artifact and Nix autoPatchelf runtime closure; manifest bindings validate URL, digest, version, and platform.

Next actions:

1. Push foundation-recovery-009 and inspect the pinned Nix/OpenLane CI run.
2. Record passing CI evidence or diagnose the next exact closure failure.
3. Seal accepted checkpoint foundation-001 after reproducible Nix smoke qualification, then continue v0.1 fetch integration.

Resume steps:

1. Run `make resume-check`.
2. Read `docs/requirements.md` and `.continuity/CURRENT.yaml`.
3. Continue the recorded next action without relying on chat history.
