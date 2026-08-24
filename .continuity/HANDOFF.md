# Current handoff

Checkpoint `foundation-recovery-007` is `emergency` in phase `foundation`.

Completed: Implemented and independently reviewed two-wide speculative history, TAGE-lite direction prediction, and indirect-target prediction; all frontend blocks lint and synthesize warning-clean; 65,777-check smoke passes; CI now preserves the generated Nix lock.

Next actions:

1. Push foundation-recovery-007 and inspect the corrected pinned Nix CI run.
2. Download, verify, and commit the exact CI-generated flake.lock artifact.
3. Pass clean-checkout Nix smoke and seal accepted checkpoint foundation-001 before continuing v0.1 fetch integration.

Resume steps:

1. Run `make resume-check`.
2. Read `docs/requirements.md` and `.continuity/CURRENT.yaml`.
3. Continue the recorded next action without relying on chat history.
