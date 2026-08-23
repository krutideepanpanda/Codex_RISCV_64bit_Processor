# Dependency-complete milestone DAG

Each gate records immutable inputs, commands, outputs, pass/fail results, waivers, and successor prerequisites in `.continuity`.

1. `foundation-001`: repository policy, requirements, agents, skills, continuity, exact dependency locks, draft audit, smoke tests, initial public repository.
2. `v0.1.0`: frontend interfaces, decompression, prediction, fetch, decode, recovery, assertions, unit and randomized tests.
3. `v0.2.0`: rename, PRFs, queues, execution, LSU skeleton, ROB, dual retirement/RVFI, precise rollback, unit/formal/differential evidence.
4. `v0.3.0`: privilege, CSR/traps, interrupts, PMP/PMA, Sv39, atomics, Debug 1.0, frozen UDB and ACT selection.
5. `v0.4.0`: qualified SRAMs, caches, AXI SoC, firmware, device tree, Linux 6.18 LTS and Debian 13.6 repeated boots.
6. `v0.6.0`: UPF/power intent, OPP transitions, CDC/RDC, full scan, MBIST, JTAG, fault injection and post-insertion equivalence.
7. `v0.9.0`: hierarchical block handoffs, top integration, MMMC STA, DRC/LVS, antenna, IR/EM, gate/SDF tests and GDS candidate.
8. `v1.0.0`: clean-checkout release gate, zero unexplained ACT failures, complete evidence bundle, GitHub release and GDS asset.

No milestone may start until all predecessor requirements are either passed or explicitly marked as non-gating discovery work.
