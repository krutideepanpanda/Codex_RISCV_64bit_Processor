# ACT 4.0 configuration

`codex-rv64-v1.yaml` is the normative machine-readable architectural profile. It is generated from the pinned ACT 4.0 Sail RV64 configuration by `make udb-profile`, then narrowed to the extensions and parameter values declared for v1.

The file determines which Architectural Certification Tests are selected; it is not evidence that those tests pass. `udb-validation.json` records successful UDB 0.1.9 schema/constraint validation against ACT 4.0. Test generation, DUT execution, and zero-unexplained-failure reports remain separate release gates.

The remaining runnable ACT adapter files (`test_config.yaml`, linker script, `rvmodel_macros.h`, Sail configuration, and simulation command) are added with the v0.3 privilege/MMU DUT harness. Until then, `ACT-001` remains pending.
