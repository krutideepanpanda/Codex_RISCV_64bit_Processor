# Architectural parameter decisions

This file explains the non-extension choices in the normative UDB profile. The complete machine-readable values remain in `verification/act/codex-rv64-v1.yaml`; these choices become implementation requirements, not evidence that RTL already satisfies them.

| Area | v1 decision | Rationale |
|---|---|---|
| Endianness | M/S/U are fixed little-endian | Matches ISA-001; big-endian and runtime endianness switching are excluded. |
| Addressing | XLEN=64, SXLEN/UXLEN=64, physical addresses=40 bits, ASIDs=16 bits | Matches the public AXI and Sv39 contract while avoiding a smaller software-visible ASID space. |
| Translation | Bare and Sv39 are implemented; hardware A/D updates are selected | Matches Sv39 plus Svadu. Other page-table modes are excluded. |
| PMP/PMA | 16 PMP entries, 4-byte PMP granularity; PMA granularity is 8 bytes | Matches the 16-entry contract. Exact PMP mode behavior is frozen with the v0.3 PMP RTL and regenerated profile. |
| Misaligned scalar access | Cacheable scalar loads/stores are supported and split in increasing byte order; LR/SC and AMO misalignment raises access fault | Fixes otherwise implementation-defined behavior for Sail/differential comparison. |
| Trap values | Faulting virtual addresses and illegal instruction encodings are reported where the profile flags permit | Improves diagnostics and fixes deterministic ACT expectations. |
| Trap vectors | Direct and vectored M/S modes, 4-byte base alignment; illegal `mtvec` mode writes retain the prior value | Uses the least restrictive architectural alignment without custom modes. |
| Floating state | Precise FS dirty updates and all four standard FS states | Required for precise retirement and Linux context switching. |
| Counters | cycle, time, instret, and HPM counters 3–31 exist; lower-mode enable bits are writable; event 0 is the reset/default selector | Implements Zicntr/Zihpm/Sscofpmf; concrete event assignments are frozen before v0.3 closure. |
| Identity CSRs | `marchid` and `mimpid` are unimplemented/read-only zero; vendor bank/offset are zero | Avoids claiming an unallocated architecture, implementation, or JEDEC vendor identity. |
| Reserved behavior | Reserved/unimplemented instructions and CSRs trap; unsupported WLRL values use their specified legalizing behavior | Provides deterministic precise-exception behavior without inventing nonstandard instructions. |

Changes to these choices require a reviewed UDB regeneration, real `udb validate cfg` pass, profile/evidence hash update, differential-model update, and continuity checkpoint.
