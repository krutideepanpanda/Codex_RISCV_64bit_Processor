---
name: sky130-signoff
description: Qualify SRAMs or run/review SKY130A power, DVFS, DFT, MBIST, hierarchical OpenLane, STA, DRC/LVS, or GDS release work for this project.
---

# SKY130 signoff

- Use only pinned OpenLane, PDK, standard-cell, OpenRAM, and macro views whose hashes match the lock manifest.
- Classify every SRAM as variable-voltage `VDD_CORE` or fixed 1.8 V `VDD_SOC`; validate its Verilog, Liberty, LEF, GDS, SPICE, LVS, level-shift/isolation, voltage, timing, and MBIST interface before cache or floorplan freeze.
- Check functional, scan, MBIST, reset, eco, nominal, and mandatory 1.95 V turbo characterization across `config/signoff/scenarios.json`.
- Require CDC/RDC and power-intent checks, isolation/retention transition tests, chain integrity, fault coverage, synthesis equivalence, STA, antenna, DRC, LVS, IR, and EM evidence.
- Never waive a genuine timing, DRC, LVS, scan-integrity, IR, or EM violation. A modeling/tool waiver needs a referenced upstream defect, integrator approval, and a corrected passing rerun.
- Never call a run signed off if any required report is absent, stale, fails its numeric PDK/library limit, or is tied to different inputs, netlist, constraints, macro views, power intent, or GDS.
- Keep PDK and large generated artifacts out of Git; publish release artifacts with SHA-256 manifests.
