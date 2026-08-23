---
name: sky130-signoff
description: Qualify SRAMs or run/review SKY130A power, DVFS, DFT, MBIST, hierarchical OpenLane, STA, DRC/LVS, or GDS release work for this project.
---

# SKY130 signoff

- Use only pinned OpenLane, PDK, standard-cell, OpenRAM, and macro views whose hashes match the lock manifest.
- Validate each SRAM's Verilog, Liberty, LEF, GDS, SPICE, LVS, voltage, timing, and MBIST interface before cache or floorplan freeze.
- Check functional, scan, MBIST, reset, and every admitted OPP across the signed MMMC scenario matrix.
- Require CDC/RDC and power-intent checks, isolation/retention transition tests, chain integrity, fault coverage, synthesis equivalence, STA, antenna, DRC, LVS, IR, and EM evidence.
- Never call a run signed off if any required report is absent, stale, unwaived, or tied to different inputs.
- Keep PDK and large generated artifacts out of Git; publish release artifacts with SHA-256 manifests.
