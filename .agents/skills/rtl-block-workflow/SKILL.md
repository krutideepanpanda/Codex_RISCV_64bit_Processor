---
name: rtl-block-workflow
description: Implement or modify a synthesizable RTL block in this RV64 CPU while preserving ownership, interface, assertion, and unit-test requirements.
---

# RTL block workflow

- Confirm the assigned write set and the relevant requirement IDs before editing.
- Keep public shared types and top-level interfaces integrator-owned.
- Use explicit-width synthesizable SystemVerilog; document reset, clock, and power domain behavior.
- Encode non-obvious correctness invariants as assertions and add self-checking normal, boundary, illegal, and recovery tests.
- Run the narrow unit target, Verilator lint, and Yosys synthesis check for the changed block.
- Return changed paths, commands, results, seeds, and unresolved risks. Do not spawn subagents.
