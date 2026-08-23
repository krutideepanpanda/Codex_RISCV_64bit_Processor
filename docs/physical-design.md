# SKY130A physical-design policy

The v1 deliverable is a reusable padless digital SoC macro, not a packaged chip.
It targets `sky130A` and `sky130_fd_sc_hd` using a pinned OpenLane 2 environment.

## SRAM methodology

Cache arrays are hardened macros. This matches normal ASIC practice and
OpenLane's macro-integration flow; synthesizing hundreds of KiB as flip-flops is
not acceptable. OpenRAM and its SKY130 technology/library commits are pinned.
Each selected shape must produce and retain:

- behavioral and powered Verilog views;
- GDSII, LEF, extracted SPICE, and LVS netlist;
- Liberty timing at the project SS/TT/FF PVT set;
- DRC/LVS logs, datasheet, generator config, and SHA-256 manifest;
- qualified 1.6 V, 1.8 V, and 1.95 V timing/power coverage for every admitted
  OPP, or an explicit rejection that prevents use at that OPP;
- MBIST access, fault-injection, parity/ECC, isolation, retention, and test-mode
  views required by its wrapper.

Cache wrappers are technology-neutral. Qualified macros are generated once,
stored as a versioned local/release bundle, and referenced through OpenLane's
`MACROS` configuration. Macro placement and the power grid are explicit and
reviewed for channel congestion and SRAM boundary timing.

## Power, scan, and MBIST methodology

The checked-in power intent defines `VDD_CORE`, `VDD_SOC`, and `VDD_AON`, all
crossings, legal power states, isolation values, retained state, reset sequence,
and glitch-free clock transitions. CDC/RDC and power-aware simulation cover eco,
nominal, turbo characterization, reset, brownout recovery, scan, and MBIST.

All eligible sequential cells are scanned by clock/power domain with no chain
longer than 512 cells. DFT DRC, chain integrity, shift/capture SDF simulation,
post-insertion equivalence, and at least 95% collapsed stuck-at coverage are
required; every exclusion and residual fault is classified.

The memory inventory maps every SRAM to an MBIST controller and algorithm set:
March C-, checkerboard, solid patterns, address tests, byte-write tests, and
parity/ECC injection. Tests verify detection, fail address/data capture,
isolation/reset interaction, and JTAG access.

## Release gate

`make gds` provisions/validates the pinned PDK and tools, verifies macro
checksums, runs hierarchical OpenLane, and writes `artifacts/signoff/<version>`.
The v1 run occurs locally on the development workstation. GitHub Actions runs
ISA/RTL checks only. The release script refuses to package a result with required
timing, DRC, LVS, antenna, equivalence, gate-smoke, CDC/RDC, power-intent, scan,
MBIST, IR, or EM failures or missing/stale reports.
