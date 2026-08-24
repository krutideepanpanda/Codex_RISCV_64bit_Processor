# Current handoff

Checkpoint `frontend-001c-b` is `accepted` in phase `v0.1.0`.

Completed: Accepted bounded predictor-state integration with fault-safe speculative history, complete x1/x5 RAS hint handling including coroutine recovery, indirect-confidence and alias checks, 136 state checks, 93,267-check locked smoke/synthesis, and independent verification READY; the v0.1.0 milestone remains incomplete.

Next actions:

1. Freeze the two-wide fetch-to-decode bundle, exception metadata, and predictor checkpoint/recovery ownership.
2. Expand decode coverage toward the declared RV64GC and selected Z-extension profile with randomized reference checks.
3. Close remaining frontend assertions and obtain independent gate review before tagging v0.1.0.

Resume steps:

1. Run `make resume-check`.
2. Read `docs/requirements.md` and `.continuity/CURRENT.yaml`.
3. Continue the recorded next action without relying on chat history.
