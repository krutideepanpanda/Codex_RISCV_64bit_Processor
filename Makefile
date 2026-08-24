SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

BUILD_DIR ?= build
VERILATOR ?= verilator
YOSYS ?= yosys
SV2V ?= sv2v
RTL_PACKAGE_FILES := $(shell find rtl/pkg -type f \( -name '*.sv' -o -name '*.v' \) | sort)
RTL_DESIGN_FILES := $(shell find rtl -path rtl/pkg -prune -o -type f \( -name '*.sv' -o -name '*.v' \) -print | sort)
RTL_FILES := $(RTL_PACKAGE_FILES) $(RTL_DESIGN_FILES)
SYNTH_FILES := $(RTL_PACKAGE_FILES) rtl/core/rv64_alu.sv

.PHONY: help validate udb-profile lint unit frontend-unit test synth smoke smoke-components recovery-inspect recovery-drill checkpoint checkpoint-check resume-check release-gate gds clean

help:
	@echo "Codex RV64 processor targets"
	@echo "  lint   - lint all SystemVerilog with Verilator"
	@echo "  validate - validate control files, agent config, skills, and dependency locks"
	@echo "  udb-profile - regenerate the normative profile from pinned ACT data"
	@echo "  unit   - compile and run fast RTL unit tests"
	@echo "  frontend-unit - run decompressor and predictor unit tests"
	@echo "  test   - run lint and unit targets"
	@echo "  synth  - synthesize the current implementation top with Yosys"
	@echo "  smoke  - run foundation lint, unit, and synthesis checks"
	@echo "  recovery-inspect - inspect interrupted state without mutation"
	@echo "  recovery-drill   - record a checksummed clean-tree recovery smoke run"
	@echo "  checkpoint-check - validate durable project state"
	@echo "  resume-check     - validate state and rerun deterministic smoke tests"
	@echo "  checkpoint       - commit/tag an accepted boundary (requires checkpoint variables)"
	@echo "  gds    - run the pinned local OpenRAM/OpenLane signoff flow"
	@echo "  clean  - remove generated build output"

validate:
	python3 scripts/validate-project.py
	bash -n scripts/*.sh
	python3 -m py_compile scripts/*.py

udb-profile:
	python3 scripts/generate-udb-profile.py

lint:
	$(VERILATOR) --lint-only --timing -Wall -Wno-DECLFILENAME \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		--top-module rv64_alu $(RTL_FILES)

unit: $(BUILD_DIR)/alu_unit $(BUILD_DIR)/decoder_unit frontend-unit
	$(BUILD_DIR)/alu_unit
	$(BUILD_DIR)/decoder_unit

frontend-unit: $(BUILD_DIR)/decompress_unit $(BUILD_DIR)/ras_unit $(BUILD_DIR)/btb_unit
	$(BUILD_DIR)/decompress_unit
	$(BUILD_DIR)/ras_unit
	$(BUILD_DIR)/btb_unit

$(BUILD_DIR)/alu_unit: $(RTL_FILES) tests/unit/alu_tb.sv
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --assert --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
		--top-module alu_tb -Mdir $(BUILD_DIR)/obj_alu \
		-o ../alu_unit $(RTL_FILES) tests/unit/alu_tb.sv

$(BUILD_DIR)/decoder_unit: $(RTL_FILES) tests/unit/decoder_tb.sv
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --assert --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		--top-module decoder_tb -Mdir $(BUILD_DIR)/obj_decoder \
		-o ../decoder_unit $(RTL_FILES) tests/unit/decoder_tb.sv

$(BUILD_DIR)/decompress_unit: $(RTL_FILES) tests/frontend/decompress/rv64c_decompress_tb.sv
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --assert --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		--top-module rv64c_decompress_tb -Mdir $(BUILD_DIR)/obj_decompress \
		-o ../decompress_unit $(RTL_FILES) tests/frontend/decompress/rv64c_decompress_tb.sv

$(BUILD_DIR)/ras_unit: $(RTL_FILES) tests/frontend/predictor/ras_tb.sv
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --assert --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		--top-module ras_tb -Mdir $(BUILD_DIR)/obj_ras \
		-o ../ras_unit $(RTL_FILES) tests/frontend/predictor/ras_tb.sv

$(BUILD_DIR)/btb_unit: $(RTL_FILES) tests/frontend/predictor/btb_tb.sv
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --assert --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		--top-module btb_tb -Mdir $(BUILD_DIR)/obj_btb \
		-o ../btb_unit $(RTL_FILES) tests/frontend/predictor/btb_tb.sv

test: validate lint unit

synth:
	mkdir -p $(BUILD_DIR)
	$(SV2V) --write=$(BUILD_DIR)/rtl-yosys.v $(SYNTH_FILES)
	$(YOSYS) -q -e '.*' -p 'read_verilog $(BUILD_DIR)/rtl-yosys.v; hierarchy -check -top rv64_alu; proc; opt; check; stat' \
		-l $(BUILD_DIR)/synth.log

smoke:
	./scripts/run-smoke.sh

smoke-components: test synth

recovery-inspect:
	python3 scripts/continuity.py inspect

checkpoint-check:
	python3 scripts/continuity.py check

resume-check:
	python3 scripts/continuity.py resume

recovery-drill:
	@test -n "$(DRILL_ID)" || (echo "DRILL_ID is required" >&2; exit 2)
	python3 scripts/continuity.py recovery-drill --id "$(DRILL_ID)"

checkpoint:
	@test -n "$(CHECKPOINT_ID)" || (echo "CHECKPOINT_ID is required" >&2; exit 2)
	@test -n "$(PHASE)" || (echo "PHASE is required" >&2; exit 2)
	@test -n "$(SUMMARY)" || (echo "SUMMARY is required" >&2; exit 2)
	@test -n "$(NEXT)" || (echo "NEXT is required" >&2; exit 2)
	python3 scripts/continuity.py checkpoint \
		--id "$(CHECKPOINT_ID)" --phase "$(PHASE)" \
		--summary "$(SUMMARY)" --next-action "$(NEXT)" \
		$(if $(NEXT2),--next-action "$(NEXT2)") \
		$(if $(NEXT3),--next-action "$(NEXT3)") \
		$(if $(filter 1,$(EMERGENCY)),--emergency,)

release-gate: checkpoint-check smoke
	python3 scripts/continuity.py release-gate

gds:
	./scripts/run-gds.sh

clean:
	rm -rf -- $(BUILD_DIR)
