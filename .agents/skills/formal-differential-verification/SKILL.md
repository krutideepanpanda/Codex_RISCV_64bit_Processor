---
name: formal-differential-verification
description: Verify this RV64 design using assertions, formal proofs, dual-retirement RVFI/Sail differential tests, ACT 4.0, coverage, or regression triage.
---

# Formal and differential verification

- Bind every result to requirement IDs, immutable tool/reference versions, commands, and seeds.
- Compare architectural effects at retirement; never compare speculative internal timing as architectural state.
- Exercise simultaneous retirement, exceptions, interrupts, replay, atomics, floating-point corner cases, and wrong-path side-effect suppression.
- Classify each formal property as proven, bounded, failed, or unreachable, with the bound and assumptions recorded.
- ACT failures may be waived only for a referenced upstream-suite defect. Do not claim compliance while unexplained failures remain.
- Preserve minimized failing seeds and add them to regression before closing a defect.
