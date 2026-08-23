# Codex RV64 project instructions

## Mission and claims

- Build a new single-hart, two-wide out-of-order RV64 processor and Linux-capable SoC.
- Treat `docs/requirements.md` and the checked-in UDB profile as the normative v1 contract.
- Do not describe the design as compliant until the declared ACT 4.0 selection has zero unexplained failures and the evidence is published.
- v1 excludes Vector, Hypervisor, PCIe, IOMMU, AIA, ROCm, and certified speculative side-channel resistance.
- Preserve third-party license and lock data. Reuse is limited to the SoC support dependencies listed in the lock manifest.

## Ownership and delegation

- The primary architect/integrator owns shared packages, public interfaces, manifests, requirement matrices, top-level integration, checkpoints, and releases.
- Give parallel writers disjoint path ownership. Do not allow two agents to edit the same file set concurrently.
- Critical RTL changes require independent verification review before integration.
- Subagents must not spawn additional agents.
- Return patches and evidence, not broad repository summaries.

## Engineering rules

- Use synthesizable SystemVerilog and explicit widths. No behavioral delays in design RTL.
- Every stateful block needs reset behavior, assertions for its invariants, a self-checking test, and a documented clock/power domain.
- Speculative state must have a checkpoint, undo path, or deterministic reconstruction path.
- No wrong-path store, MMIO transaction, CSR write, exception, interrupt acknowledgement, or debug side effect may become externally visible.
- Keep generated output under ignored build or artifact directories. Never commit PDK content or restricted artifacts.
- Pin every external source by immutable commit, tag plus content hash, or Nix lock entry.

## Required validation

- Run `make smoke` before an accepted checkpoint.
- Run the narrowest relevant unit and formal tests while developing.
- Record commands, seeds, pass/fail status, waivers, and artifact hashes in `.continuity/CURRENT.yaml`.
- Never hide failing tests or convert a failure into a waiver without an upstream defect reference and integrator approval.

## Continuity protocol

- Start every resumed task with `make resume-check` and read `.continuity/HANDOFF.md`.
- Create accepted boundaries with `make checkpoint CHECKPOINT_ID=<id> PHASE=<phase> SUMMARY='<summary>' NEXT='<next action>'`.
- Use `EMERGENCY=1` only when preserving incomplete or failing work; emergency checkpoints cannot advance a milestone or release tag.
- Before a reboot, external authentication, long EDA run, or likely quota exhaustion, stop at a bounded point and checkpoint.
- After interruption, preserve uncommitted files. Do not reset, delete, or promote incomplete generated runs automatically.

## Release policy

- `main` may contain clearly identified work in progress.
- Milestone and release tags require their documented gate; v1.0 additionally requires clean-checkout `make release-gate` and `make gds` evidence.
- GitHub Actions does not run GDS. Large GDS/signoff artifacts belong in GitHub release assets with SHA-256 manifests.
