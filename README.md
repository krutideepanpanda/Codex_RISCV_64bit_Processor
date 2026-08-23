# Codex RISC-V 64-bit Processor

`Codex_RISCV_64bit_Processor` is a clean-room SystemVerilog implementation of
a single-hart, dual-issue, out-of-order 64-bit RISC-V application processor and
Linux-capable SoC. The physical target is a padless SKY130A digital macro built
with OpenLane 2 and qualified OpenRAM cache macros.

> **Project status:** early implementation. Compliance, Linux boot, timing, and
> physical-signoff claims become valid only when the corresponding checked
> release artifacts exist. The repository does not currently claim tapeout
> readiness or ROCm compatibility.

## v1 target

- RV64GC plus Zicsr, Zifencei, Zicntr, Zihpm, Zba, Zbb, Zbs, and Zicbom.
- Privileged Architecture 1.13 M/S/U, Sv39, 16-entry PMP, precise traps,
  RVWMO, Sstc, Svpbmt, Svinval, Svadu, Sscofpmf, and Smepmp.
- Two-wide fetch/decode/rename/dispatch/commit with a 64-entry ROB.
- Speculative TAGE-lite frontend and speculative load/store execution with
  violation detection and replay.
- 32 KiB four-way L1 instruction and data caches and a 256 KiB shared L2.
- 128-bit AXI4 external memory and AXI4-Lite peripheral interfaces.
- RISC-V Debug Specification 1.0 over JTAG, UART, ACLINT, PLIC, QSPI, GPIO,
  and a simulation host bridge.
- Debian 13.6 riscv64 boot using Linux 6.18 LTS and OpenSBI.
- ACT 4.0 architectural tests, differential randomized testing, formal unit
  properties, and benchmark regression tracking.
- OpenLane 2 SKY130A GDS with DRC/LVS/antenna clean and 100 MHz closure across
  the supported SS/TT/FF timing set.
- Three explicit power domains, eco/nominal/turbo OPPs, full eligible-flop scan,
  and MBIST for every SRAM.

ROCm, PCIe, a RISC-V IOMMU, and physical FPGA/GPU validation are explicitly
deferred to v2, when an exact FPGA board and AMD GPU are available.

## Build entry points

```sh
make lint          # SystemVerilog lint
make unit          # fast unit tests
make test          # lint and unit tests
make synth         # generic Yosys synthesis check
make smoke         # foundation lint, unit, and synthesis regression
make resume-check  # validate checkpoint state after interruption
make gds           # local pinned OpenLane/OpenRAM signoff flow (v1 release gate)
make help
```

The local `openlane` command currently installed on the development machine is
incomplete. `scripts/bootstrap-tools.sh` will provision pinned project-local
tooling rather than depend on that launcher.

See [docs/architecture.md](docs/architecture.md),
[docs/verification.md](docs/verification.md), and
[docs/physical-design.md](docs/physical-design.md) for the binding v1 contract.

## License

Apache License 2.0. Third-party dependencies retain their own licenses and are
pinned by manifests under `third_party/`.
