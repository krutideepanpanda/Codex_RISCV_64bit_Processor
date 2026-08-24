# Current handoff

Checkpoint `frontend-001b` is `accepted` in phase `v0.1.0`.

Completed: Accepted the one-outstanding-window RV64 fetch controller with reset-safe handshakes, stable backpressure behavior, flush-over-redirect recovery, stale-response draining, buffered-window assertions, 538 independent-model checks, locked Nix smoke, and independent verification review.

Next actions:

1. Integrate BTB, TAGE-lite, 32-entry indirect prediction, RAS, and speculative-history recovery metadata.
2. Compose the fetch controller, aligner, decompressor, and predictor blocks behind the frozen two-wide frontend packet interface.
3. Close recovery, backpressure, and prediction assertions plus independent review before the v0.1.0 milestone gate.

Resume steps:

1. Run `make resume-check`.
2. Read `docs/requirements.md` and `.continuity/CURRENT.yaml`.
3. Continue the recorded next action without relying on chat history.
