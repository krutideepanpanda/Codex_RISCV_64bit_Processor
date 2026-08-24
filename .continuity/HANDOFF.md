# Current handoff

Checkpoint `frontend-001a` is `accepted` in phase `v0.1.0`.

Completed: Accepted two-wide RV64C/native fetch alignment with attributable terminal faults, frozen frontend semantics, 26,768-check seeded outcome coverage, locked Nix smoke, and independent verification READY.

Next actions:

1. Implement the one-outstanding-request fetch controller with redirect and flush stale-response suppression.
2. Integrate BTB, TAGE-lite, 32-entry indirect prediction, and full RAS/history recovery metadata.
3. Add recovery and backpressure assertions and obtain independent review before the v0.1.0 milestone gate.

Resume steps:

1. Run `make resume-check`.
2. Read `docs/requirements.md` and `.continuity/CURRENT.yaml`.
3. Continue the recorded next action without relying on chat history.
