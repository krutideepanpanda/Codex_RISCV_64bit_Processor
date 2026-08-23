SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

BUILD_DIR ?= build
VERILATOR ?= verilator
YOSYS ?= yosys
SV2V ?= sv2v
RTL_PACKAGE_FILES := $(shell find rtl/pkg -type f \( -name '*.sv' -o -name '*.v' \) | sort)
RTL_DESIGN_FILES := $(shell find rtl -path rtl/pkg -prune -o -type f \( -name '*.sv' -o -name '*.v' \) -print | sort)
RTL_FILES := $(RTL_PACKAGE_FILES) $(RTL_DESIGN_FILES)

.PHONY: help lint unit test synth smoke smoke-components recovery-inspect checkpoint checkpoint-check resume-check release-gate gds clean

help:
	@echo "Codex RV64 processor targets"
	@echo "  lint   - lint all SystemVerilog with Verilator"
	@echo "  unit   - compile and run fast RTL unit tests"
	@echo "  test   - run lint and unit targets"
	@echo "  synth  - synthesize the current implementation top with Yosys"
	@echo "  smoke  - run foundation lint, unit, and synthesis checks"
	@echo "  recovery-inspect - inspect interrupted state without mutation"
	@echo "  checkpoint-check - validate durable project state"
	@echo "  resume-check     - validate state and rerun deterministic smoke tests"
	@echo "  checkpoint       - commit/tag an accepted boundary (requires checkpoint variables)"
	@echo "  gds    - run the pinned local OpenRAM/OpenLane signoff flow"
	@echo "  clean  - remove generated build output"

lint:
	$(VERILATOR) --lint-only --timing -Wall -Wno-DECLFILENAME \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		--top-module rv64_alu $(RTL_FILES)

unit: $(BUILD_DIR)/alu_unit $(BUILD_DIR)/decoder_unit
	$(BUILD_DIR)/alu_unit
	$(BUILD_DIR)/decoder_unit

$(BUILD_DIR)/alu_unit: $(RTL_FILES) tests/unit/alu_tb.sv
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
		--top-module alu_tb -Mdir $(BUILD_DIR)/obj_alu \
		-o ../alu_unit $(RTL_FILES) tests/unit/alu_tb.sv

$(BUILD_DIR)/decoder_unit: $(RTL_FILES) tests/unit/decoder_tb.sv
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		--top-module decoder_tb -Mdir $(BUILD_DIR)/obj_decoder \
		-o ../decoder_unit $(RTL_FILES) tests/unit/decoder_tb.sv

test: lint unit

synth:
	mkdir -p $(BUILD_DIR)
	$(SV2V) --write=$(BUILD_DIR)/rtl-yosys.v $(RTL_FILES)
	$(YOSYS) -q -p 'read_verilog $(BUILD_DIR)/rtl-yosys.v; hierarchy -check -top rv64_alu; proc; opt; check; stat' \
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

checkpoint:
	@test -n "$(CHECKPOINT_ID)" || (echo "CHECKPOINT_ID is required" >&2; exit 2)
	@test -n "$(PHASE)" || (echo "PHASE is required" >&2; exit 2)
	@test -n "$(SUMMARY)" || (echo "SUMMARY is required" >&2; exit 2)
	@test -n "$(NEXT)" || (echo "NEXT is required" >&2; exit 2)
	python3 scripts/continuity.py checkpoint \
		--id "$(CHECKPOINT_ID)" --phase "$(PHASE)" \
		--summary "$(SUMMARY)" --next-action "$(NEXT)" \
		$(if $(filter 1,$(EMERGENCY)),--emergency,)

release-gate: checkpoint-check smoke
	python3 scripts/continuity.py release-gate

gds:
	./scripts/run-gds.sh

clean:
	rm -rf -- $(BUILD_DIR)
