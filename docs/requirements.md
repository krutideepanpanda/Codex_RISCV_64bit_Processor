# v1 normative requirement matrix

Only requirements marked `required` may gate a v1 claim. Evidence paths are populated as milestones close.

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| ISA-001 | One little-endian RV64 hart; XLEN=64, FLEN=64 | required | pending |
| ISA-002 | RV64IMAFDC plus Zicsr, Zifencei, Zicntr, Zihpm, Zba, Zbb, Zbs, Zicbom | required | pending |
| PRIV-001 | Privileged Architecture 1.13 M/S/U, Sv39, 16 PMP entries, RVWMO | required | pending |
| PRIV-002 | Sstc, Svpbmt, Svinval, Svadu, Sscofpmf, Smepmp | required | pending |
| DBG-001 | RISC-V Debug Specification 1.0 over JTAG | required | pending |
| CORE-001 | Two-wide fetch/decode/rename/dispatch/retirement; in-order architectural retirement | required | pending |
| CORE-002 | 64 ROB, 96 integer and 96 FP physical registers, distributed queues | required | pending |
| MEM-001 | 32 KiB four-way parity L1I/L1D and 256 KiB eight-way inclusive SECDED L2 | required | pending |
| SOC-001 | 128-bit AXI4 memory master, 40-bit PA, ACLINT, PLIC, UART, QSPI, GPIO | required | pending |
| VER-001 | Dual-retirement RVFI/Sail differential testing and required formal properties | required | pending |
| ACT-001 | Checked-in UDB profile and ACT 4.0 zero unexplained failures | required | UDB schema/constraint validation passes in `verification/act/udb-validation.json`; DUT ACT execution remains pending |
| SW-001 | OpenSBI, U-Boot, Linux 6.18 LTS, Debian 13.6 repeated boot qualification | required | pending |
| PWR-001 | VDD_CORE 1.6-1.95 V, VDD_SOC 1.8 V, VDD_AON 1.8 V | required | pending |
| PWR-002 | 50 MHz eco, 100 MHz nominal across supported P/T/RC corners, characterized turbo | required | pending |
| DFT-001 | Full eligible-flop scan, <=512 cells/chain, >=95% collapsed stuck-at coverage | required | pending |
| DFT-002 | MBIST for every SRAM with declared algorithms, injection, capture, and JTAG access | required | pending |
| PHY-001 | SKY130A hierarchical OpenLane 2 padless digital macro | required | pending |
| PHY-002 | Clean required STA, equivalence, antenna, DRC/LVS, IR/EM, and GDS checksum evidence | required | pending |
| CONT-001 | Fresh-task recovery using only Git, CURRENT.yaml, HANDOFF.md, and locked artifacts | required | pending |
| V2-001 | PCIe, IOMMU, AIA, ROCm, GPU, and board-specific work | deferred | `docs/v2-rocm.md` |

No v1 document may imply Vector, Hypervisor, external certification, tapeout readiness, or certified speculative side-channel resistance.
