---
name: formal-differential-verification
description: Verify this RV64 design using assertions, formal proofs, dual-retirement RVFI/Sail differential tests, ACT 4.0, coverage, or regression triage.
---

# Formal and differential verification

- Bind every result to requirement IDs, immutable tool/reference versions, commands, and seeds.
- Compare architectural effects at retirement; never compare speculative internal timing as architectural state.
- Exercise simultaneous retirement, exceptions, interrupts, replay, atomics, floating-point corner cases, and wrong-path side-effect suppression.
- Define interrupt/debug sampling at each architectural retirement boundary. Normalize dual lanes by `rvfi_order`, not lane number or simulator cycle.
- On divergence, preserve the original incident, replay three times, locate the first architectural mismatch, classify RTL/RVFI/generator/adapter/reference-model causes, then minimize while preserving that mismatch predicate.
- Classify each formal property as proven, bounded, failed, or unreachable, with the bound and assumptions recorded.
- ACT failures may be waived only for a referenced upstream-suite defect. Do not claim compliance while unexplained failures remain.
- Preserve minimized failing seeds and add them to regression before closing a defect.
- Record an incident manifest, commands, environment, traces, programs, hashes, proof assumptions/bounds, classification, fix, and independent review. Do not close a critical defect without a passing control and deterministic regression.
