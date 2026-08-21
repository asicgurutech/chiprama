SHELL := /bin/bash

PYTHON ?= python3
RTL ?= donotaccess/samram_dma_golden/rtl/golden/samram_dma/samram_dma_top.v
FILELIST ?= filelist.f
TESTS ?= dv/cocotb/test_bug1_desc_sampling.py
TESTS ?= dv/cocotb/test_bug2_boundary_address.py
#TESTS ?= dv/cocotb/test_bug1_desc_sampling.py dv/cocotb/test_bug2_boundary_address.py
COCOTB_TEST_MODULES = dv/cocotb/test_bug1_desc_sampling.py,dv/cocotb/test_bug2_boundary_address.py
BUILD_DIR ?= build/cocotb
REPORT_DIR ?= reports
COVERAGE_FILE ?= $(REPORT_DIR)/coverage.json
RTL_DIR ?= donotaccess/samram_dma_golden/rtl/golden/samram_dma/

.PHONY: test clean

test:
	mkdir -p $(BUILD_DIR) $(REPORT_DIR)
	$(PYTHON) scripts/run_cocotb.py \
		--rtl $(RTL) \
		--tests $(TESTS) \
		--filelist $(FILELIST) \
		--build-dir $(BUILD_DIR) \
		--coverage-file $(COVERAGE_FILE) \
		--results-xml $(REPORT_DIR)/results.xml \
		--top samram_dma_top

clean:
	rm -rf build reports