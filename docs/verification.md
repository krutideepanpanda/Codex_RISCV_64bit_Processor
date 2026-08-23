# Verification and release evidence

## Required layers

1. Lint and structural checks: Verilator warnings-as-errors, clock/reset checks,
   inferred-latch checks, CDC review, and Yosys synthesis.
2. Unit verification: self-checking directed tests for decode, integer/bitmanip,
   multiply/divide, floating point, CSR/traps, PMP, page-table walking, TLB,
   cache refill/writeback, atomics, misalignment, predictor recovery, rename,
   issue, ROB, and load/store replay.
3. Differential verification: randomized legal instruction streams compared at
   retirement through RVFI against the pinned Sail RISC-V reference model.
4. Formal verification: bounded and inductive properties for FIFOs/arbiters,
   rename-map recovery, ROB ordering, no double retirement, precise exceptions,
   LR/SC reservation invalidation, PMP priority, and AXI protocol behavior.
5. Certification: ACT 4.0 generated from the checked-in UDB configuration. Every
   selected test must pass; the selected profile must equal all required ISA and
   privileged extensions in `docs/requirements.md`; waivers require an
   upstream-suite defect reference.
6. Software: OpenSBI boot, Linux 6.18 LTS selftests, and Debian 13.6 riscv64 to a
   systemd multi-user shell with storage, networking, time, and package smoke
   tests through simulation devices.
7. DFT/power: full scan/MBIST inclusion, injected-fault detection, chain
   integrity, post-insertion equivalence, CDC/RDC, power-aware OPP transitions,
   reset/brownout recovery, and per-OPP functional regressions.
8. Physical: post-synthesis and SDF gate smoke tests, DRC/LVS/antenna clean,
   signed MMMC STA, static/dynamic IR and EM, and reproducible GDS/report
   checksums.

## Quantitative closure

- Planned functional bins: 100%; line, branch, and toggle coverage: at least
  90%, with reviewed exclusions.
- Dual issue/retirement, younger-before-older execution with in-order commit,
  simultaneous exceptions/interrupts/debug boundaries, and replay are explicit
  cover/test targets.
- Sv39 tests include 4 KiB, 2 MiB, and 1 GiB pages, permission/A-D behavior,
  invalidation, and page/PMP/device-boundary faults without partial side effects.
- PMP tests cover all 16 entries, priority, locking, TOR, NA4, NAPOT, Smepmp,
  and M/S/U interactions.
- No critical correctness issue may remain open at a milestone gate.

## Evidence policy

Generated work directories remain untracked. A release bundle contains tool and
dependency versions, UDB config, ACT report, benchmark results, coverage summary,
OpenLane metrics, DRC/LVS/antenna reports, STA reports, netlists, LEF, GDSII, and
SHA-256 checksums. README badges may only reflect jobs that actually run in
GitHub Actions; local physical results are identified as release artifacts.
