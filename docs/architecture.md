# v1 architecture contract

This document is normative for v1. A release cannot describe itself as
compliant unless every mandatory acceptance item is backed by a published test
or signoff artifact.

## Architectural state

- One little-endian RV64 hart; XLEN=64 and FLEN=64.
- ISA: RV64IMAFDC_Zicsr_Zifencei_Zicntr_Zihpm_Zba_Zbb_Zbs_Zicbom.
- Privileged Architecture 1.13 with M, S, and U modes; no H mode and no
  vector extension in v1.
- Sstc, Svpbmt, Svinval, Svadu, Sscofpmf, and Smepmp are mandatory v1
  extensions and are represented in the checked-in UDB profile.
- Sv39 virtual memory, 16-bit ASIDs, 40-bit implemented physical addresses,
  4 KiB base pages, and architecturally correct 2 MiB/1 GiB superpages.
- Sixteen naturally aligned PMP entries implementing TOR, NA4, and NAPOT.
- Hardware completion of ordinary misaligned cacheable accesses. Accesses that
  cross a page, PMP boundary, or device region trap before any visible partial
  side effect.
- RVWMO ordering, LR/SC, all RV64 A-extension AMOs, FENCE/FENCE.I, and Zicbom.
- IEEE-754 binary32/binary64 with all rounding modes, accrued exceptions,
  subnormals, NaN boxing, and precise floating-point exceptions.
- At least 29 programmable 64-bit HPM counters plus cycle, time, and instret.

The implementation is described in a RISC-V Unified Database configuration and
tested with ACT 4.0. ACT is a certification suite, not the only verification
method.

## Pipeline and speculation

- Up to two instructions are fetched, decoded, renamed, dispatched, and retired
  each cycle. Architectural retirement is strictly in order.
- 64-entry reorder buffer; 96 integer and 96 floating-point physical registers;
  separate 32-entry integer, 16-entry memory, and 16-entry floating-point issue
  capacity; 16 load and 16 store queue entries.
- Two integer ALUs, one branch unit, one pipelined multiplier, one iterative
  divider, two address-generation lanes, and one pipelined F/D unit. Structural
  hazards are represented in issue eligibility, never by dropping operations.
- A compact tagged-history predictor with bimodal fallback, 128-entry BTB,
  32-entry indirect target cache, and 16-entry return-address stack. Every
  speculative state update has a checkpoint or reconstructable recovery path.
- Loads may bypass unresolved stores under a memory-dependence predictor.
  Address violations trigger selective replay; exceptions, interrupts,
  mispredictions, and replays cannot retire wrong-path state.
- Architectural correctness is required under speculation. v1 provides fence
  and predictor/cache flush controls but makes no certified Spectre-class
  side-channel-resistance claim.

## Memory hierarchy

- 32 KiB, four-way, 64-byte-line VIPT L1I and write-back/write-allocate L1D.
- Non-blocking L1D with at least four MSHRs, store-to-load forwarding, and two
  banked access lanes. L1I has at least two refill MSHRs.
- Unified 256 KiB, eight-way, 64-byte-line inclusive L2 with at least eight
  MSHRs. Inclusion supplies the future coherent expansion snoop point.
- Cache data arrays use qualified OpenRAM hard macros in ASIC builds and inferred
  block RAM in FPGA builds. Small highly multiported arrays may use standard
  cells when that is faster and demonstrably routable.
- One-cycle L1 hit latency is the design goal; correctness must not depend on a
  fixed SRAM latency, and wrappers expose request/response handshakes.

## SoC boundary

- Padless digital macro with externally supplied functional clocks, active-low
  asynchronous input reset synchronized per domain, and separate JTAG
  clock/reset. The physical view exposes `VDD_CORE`, `VDD_SOC`, and `VDD_AON`.
- `VDD_CORE` powers the core, L1 caches, and physical register files at admitted
  1.6-1.95 V operating points. `VDD_SOC` powers L2/interconnect/peripherals at
  1.8 V. `VDD_AON` powers reset, debug, DVFS, scan, and MBIST control at 1.8 V.
- The macro contains no PLL or regulator. Isolation, level shifting, retention,
  clock switching, reset sequencing, and OPP transitions are explicit in the
  power intent and verified before physical release.
- 128-bit AXI4 memory master with 40-bit addresses and burst support.
- AXI4-Lite peripheral fabric with ACLINT, PLIC, 16550-compatible UART, QSPI,
  GPIO, boot ROM, and simulation host bridge.
- A versioned coherent-expansion placeholder is reserved but tied off in v1.
  PCIe, IOMMU, AIA/IMSIC GPU plumbing, and ROCm are v2 work.
- Reset vector `0x0000_0000_0000_1000`; boot ROM at `0x0000_1000`;
  CLINT/PLIC/peripheral and DRAM regions are defined in `docs/memory-map.md`.

## Performance and physical acceptance

- RTL benchmarks track CoreMark, Dhrystone, and Embench instruction counts,
  cycles, IPC, and score/MHz. Once a correct baseline is published, unexplained
  statistically significant regressions fail the release gate.
- The v1 physical top must complete OpenLane stream-out and pass top-level DRC,
  LVS, antenna, synthesis-equivalence, and gate-level smoke checks.
- Setup and hold must close at 100 MHz at all configured SKY130A SS/TT/FF PVT and
  min/nom/max interconnect corners admitted for the 1.8 V nominal OPP, including
  SRAM boundary timing.
- The eco OPP is 50 MHz at 1.6 V. Turbo is an Fmax characterized at 1.95 V and
  becomes an admitted OPP only after its complete PVT/RC matrix passes.
- Full eligible-flop scan, MBIST for every SRAM, and their functional/test-mode
  timing and power scenarios are mandatory v1 release gates.
