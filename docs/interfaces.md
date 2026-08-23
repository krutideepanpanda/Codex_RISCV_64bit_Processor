# Public hardware interfaces

This document freezes the integration boundary, not an implementation-completeness claim. Signal-level RTL must remain compatible with this contract unless a reviewed architecture decision updates both this document and the requirements matrix.

## `rv64_core`

`rv64_core` is the single-hart CPU boundary. It exposes:

- one active-low asynchronous reset input and explicit clocks for the core and uncore-facing logic;
- a 128-bit AXI4 instruction/data memory master with 40-bit physical addresses;
- machine, supervisor, external, timer, software, and non-maskable interrupt inputs;
- a RISC-V Debug Specification 1.0 debug-module interface and halt/reset requests;
- two RVFI retirement lanes, ordered oldest first;
- explicit test, scan, MBIST, isolation, and power-good controls; and
- distinct `VDD_CORE`, `VDD_SOC`, `VDD_AON`, and ground power pins in power-aware views.

The AXI master uses AXI4 INCR bursts, 16-byte data beats, byte strobes, and IDs wide enough to distinguish instruction fills, data fills, writebacks, uncached transactions, and page-table walks. Exact widths and packed channel types are declared in the shared integration package once that package is frozen.

## `codex_rv64_soc`

`codex_rv64_soc` is a padless digital macro containing the core, cache hierarchy, interconnect, boot ROM, ACLINT, PLIC, UART16550, QSPI controller, GPIO controller, and simulation host bridge. Its public boundary exposes:

- external clocks, resets, power-good signals, and the three explicit supply domains;
- the 128-bit, 40-bit-address AXI4 memory master;
- JTAG (`TCK`, `TMS`, `TDI`, `TDO`, and `TRSTn`);
- UART receive/transmit;
- QSPI clock, chip-select, and four bidirectional data signals represented as separate input/output/output-enable ports;
- GPIO input/output/output-enable vectors;
- scan, MBIST, and DVFS controls; and
- dual-lane RVFI for simulation and formal builds.

The reset vector is `0x0000_0000_0000_1000`. The checked-in memory map is normative for software-visible addresses.

## Stability and ownership

The primary architect owns public top-level ports, shared packages, and interface versioning. Workers may propose changes but must not edit these surfaces concurrently. Interface changes require updated assertions, testbench adapters, software descriptions, continuity state, and a reviewed compatibility note.
