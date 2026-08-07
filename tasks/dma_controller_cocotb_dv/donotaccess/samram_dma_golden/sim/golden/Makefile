#------------------------------------------------------------------------------
#  SAMRAM LLC
#------------------------------------------------------------------------------
# Project     : Chiparama HUD Benchmark Task
# File        : Makefile
# Prepared by : SAMRAM LLC for Chiparama LLC
# Description : Simulation, lint, compile, and regression targets for the
#               SAMRAM DMA golden RTL benchmark and verification collateral.
#
# Confidentiality:
#   Proprietary and confidential. Use only as authorized under the applicable
#   project agreement.
#
# Development Notice:
#   Created independently. No third-party confidential or proprietary
#   information, materials, tools, systems, documents, code, specifications,
#   or resources were used.
#------------------------------------------------------------------------------

BUILD_DIR := ../../build
SAMRAM_RTL_DIR := ../../rtl/golden/samram_dma
SAMRAM_RTL_INC_DIR := $(SAMRAM_RTL_DIR)/include
SAMRAM_DMA_RTL := \
	$(SAMRAM_RTL_DIR)/samram_dma_top.v \
	$(SAMRAM_RTL_DIR)/samram_dma_apb_decode.v \
	$(SAMRAM_RTL_DIR)/samram_dma_apb_resp_mux.v \
	$(SAMRAM_RTL_DIR)/samram_dma_desc_sram.v \
	$(SAMRAM_RTL_DIR)/samram_dma_desc_ring.v \
	$(SAMRAM_RTL_DIR)/samram_dma_csr_read_mux.v \
	$(SAMRAM_RTL_DIR)/samram_dma_csr_write_ctrl.v \
	$(SAMRAM_RTL_DIR)/samram_dma_xfer_engine.v \
	$(SAMRAM_RTL_DIR)/samram_dma_irq_ctrl.v \
	$(SAMRAM_RTL_DIR)/samram_dma_scheduler.v \
	$(SAMRAM_RTL_DIR)/samram_dma_rr_arbiter.v \
	$(SAMRAM_RTL_DIR)/samram_dma_align.v \
	$(SAMRAM_RTL_DIR)/samram_dma_axi_master_out.v
SAMRAM_DMA_RTL_ABS := $(abspath $(SAMRAM_RTL_DIR)/samram_dma_top.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_apb_decode.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_apb_resp_mux.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_desc_sram.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_desc_ring.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_csr_read_mux.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_csr_write_ctrl.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_xfer_engine.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_irq_ctrl.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_scheduler.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_rr_arbiter.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_align.v) $(abspath $(SAMRAM_RTL_DIR)/samram_dma_axi_master_out.v)

IVERILOG := iverilog
VERILATOR := verilator
VVP := vvp

.PHONY: all regression
.PHONY: samram lint_samram samram_csr_tb samram_single_copy_tb samram_multi_word_tb samram_read_error_tb samram_write_error_tb samram_ctrl_clear_tb samram_regression_tb cocotb_axi_vip_smoke cocotb_axi_vip_random bug_desc_sample_early_expected_fail bug_queue_no_pushback_expected_fail bug_interrupt_done_priority_expected_fail bug_bad_wstrb_unaligned_dst_expected_fail bug_done_irq_wrong_channel_expected_fail bug_bad_src_shift_unaligned_src_expected_fail
.PHONY: clean

all: samram
regression: samram lint_samram samram_regression_tb
# -----------------------------------------------------------------------------
# SAMRAM / Chiparama golden DMA compile targets
# -----------------------------------------------------------------------------

samram:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-o $(BUILD_DIR)/samram_dma_top_compile.vvp \
		-s samram_dma_top \
		-I$(SAMRAM_RTL_INC_DIR) \
		$(SAMRAM_DMA_RTL)

lint_samram:
	$(VERILATOR) --lint-only --sv -Wno-fatal \
		-I$(SAMRAM_RTL_INC_DIR) \
		$(SAMRAM_DMA_RTL) \
		--top-module samram_dma_top

samram_csr_tb:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-o $(BUILD_DIR)/samram_dma_csr_tb.vvp \
		-s samram_dma_csr_tb \
		-I$(SAMRAM_RTL_INC_DIR) \
		$(SAMRAM_DMA_RTL) \
		../../tb/golden/samram_dma_csr_tb.v
	$(VVP) $(BUILD_DIR)/samram_dma_csr_tb.vvp

samram_single_copy_tb:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-o $(BUILD_DIR)/samram_dma_single_copy_tb.vvp \
		-s samram_dma_single_copy_tb \
		-I$(SAMRAM_RTL_INC_DIR) \
		$(SAMRAM_DMA_RTL) \
		../../tb/golden/samram_dma_single_copy_tb.v
	$(VVP) $(BUILD_DIR)/samram_dma_single_copy_tb.vvp

samram_multi_word_tb:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-o $(BUILD_DIR)/samram_dma_multi_word_tb.vvp \
		-s samram_dma_multi_word_tb \
		-I$(SAMRAM_RTL_INC_DIR) \
		$(SAMRAM_DMA_RTL) \
		../../tb/golden/samram_dma_multi_word_tb.v
	$(VVP) $(BUILD_DIR)/samram_dma_multi_word_tb.vvp

samram_read_error_tb:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-o $(BUILD_DIR)/samram_dma_read_error_tb.vvp \
		-s samram_dma_read_error_tb \
		-I$(SAMRAM_RTL_INC_DIR) \
		$(SAMRAM_DMA_RTL) \
		../../tb/golden/samram_dma_read_error_tb.v
	$(VVP) $(BUILD_DIR)/samram_dma_read_error_tb.vvp

samram_write_error_tb:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-o $(BUILD_DIR)/samram_dma_write_error_tb.vvp \
		-s samram_dma_write_error_tb \
		-I$(SAMRAM_RTL_INC_DIR) \
		$(SAMRAM_DMA_RTL) \
		../../tb/golden/samram_dma_write_error_tb.v
	$(VVP) $(BUILD_DIR)/samram_dma_write_error_tb.vvp

samram_ctrl_clear_tb:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-o $(BUILD_DIR)/samram_dma_ctrl_clear_tb.vvp \
		-s samram_dma_ctrl_clear_tb \
		-I$(SAMRAM_RTL_INC_DIR) \
		$(SAMRAM_DMA_RTL) \
		../../tb/golden/samram_dma_ctrl_clear_tb.v
	$(VVP) $(BUILD_DIR)/samram_dma_ctrl_clear_tb.vvp


samram_regression_tb:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-I ../../tb/golden \
		-o $(BUILD_DIR)/samram_dma_regression_tb.vvp \
		-s samram_dma_regression_tb \
		-I$(SAMRAM_RTL_INC_DIR) \
		$(SAMRAM_DMA_RTL) \
		../../tb/golden/samram_dma_regression_tb.v
	$(VVP) $(BUILD_DIR)/samram_dma_regression_tb.vvp


# -----------------------------------------------------------------------------
# cocotb / cocotbext-axi smoke target
# -----------------------------------------------------------------------------

COCOTB_SIM ?= icarus
COCOTB_TOPLEVEL := samram_dma_top
COCOTB_MODULE := test_samram_dma_axi_vip
COCOTB_TEST_DIR := ../../tb/cocotb
COCOTB_BUILD_DIR := $(BUILD_DIR)/cocotb_axi_vip_smoke
COCOTB_RANDOM_MODULE := test_samram_dma_axi_vip_random
COCOTB_RANDOM_BUILD_DIR := $(BUILD_DIR)/cocotb_axi_vip_random

cocotb_axi_vip_smoke:
	@command -v cocotb-config >/dev/null 2>&1 || \
		(echo "ERROR: cocotb is not installed in this environment."; \
		 echo "Install with: python -m pip install -r requirements-cocotb.txt"; \
		 exit 1)
	mkdir -p $(COCOTB_BUILD_DIR)
	cd $(COCOTB_BUILD_DIR) && \
		PYTHONPATH=$(abspath $(COCOTB_TEST_DIR)):$$PYTHONPATH \
		COCOTB_TEST_MODULES=$(COCOTB_MODULE) \
		COCOTB_TOPLEVEL=$(COCOTB_TOPLEVEL) \
		TOPLEVEL_LANG=verilog \
		SIM=$(COCOTB_SIM) \
		VERILOG_SOURCES="$(SAMRAM_DMA_RTL_ABS)" \
		COMPILE_ARGS="-g2012 -I$(abspath $(SAMRAM_RTL_INC_DIR))" \
		$(MAKE) -f $$(cocotb-config --makefiles)/Makefile.sim


cocotb_axi_vip_random:
	@command -v cocotb-config >/dev/null 2>&1 || \
		(echo "ERROR: cocotb is not installed in this environment."; \
		 echo "Install with: python -m pip install -r requirements-cocotb.txt"; \
		 exit 1)
	mkdir -p $(COCOTB_RANDOM_BUILD_DIR)
	cd $(COCOTB_RANDOM_BUILD_DIR) && \
		PYTHONPATH=$(abspath $(COCOTB_TEST_DIR)):$$PYTHONPATH \
		COCOTB_TEST_MODULES=$(COCOTB_RANDOM_MODULE) \
		COCOTB_TOPLEVEL=$(COCOTB_TOPLEVEL) \
		TOPLEVEL_LANG=verilog \
		SIM=$(COCOTB_SIM) \
		VERILOG_SOURCES="$(SAMRAM_DMA_RTL_ABS)" \
		COMPILE_ARGS="-g2012 -I$(abspath $(SAMRAM_RTL_INC_DIR))" \
		$(MAKE) -f $$(cocotb-config --makefiles)/Makefile.sim




# -----------------------------------------------------------------------------
# HUD/DV bug-package targets
# -----------------------------------------------------------------------------

BUG_DESC_SAMPLE_EARLY_RTL_DIR := ../../rtl/buggy/samram_dma_bug_desc_sample_early
BUG_QUEUE_NO_PUSHBACK_RTL_DIR := ../../rtl/buggy/samram_dma_bug_queue_no_pushback
BUG_INTERRUPT_DONE_PRIORITY_RTL_DIR := ../../rtl/buggy/samram_dma_bug_interrupt_done_priority
BUG_BAD_WSTRB_UNALIGNED_DST_RTL_DIR := ../../rtl/buggy/samram_dma_bug_bad_wstrb_unaligned_dst
BUG_DONE_IRQ_WRONG_CHANNEL_RTL_DIR := ../../rtl/buggy/samram_dma_bug_done_irq_wrong_channel
BUG_BAD_SRC_SHIFT_UNALIGNED_SRC_RTL_DIR := ../../rtl/buggy/samram_dma_bug_bad_src_shift_unaligned_src

bug_desc_sample_early_expected_fail:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-I ../../tb/golden \
		-o $(BUILD_DIR)/bug_desc_sample_early_regression_tb.vvp \
		-s samram_dma_regression_tb \
		$(BUG_DESC_SAMPLE_EARLY_RTL_DIR)/samram_dma_top.v \
		../../tb/golden/samram_dma_regression_tb.v
	@set +e; \
	$(VVP) $(BUILD_DIR)/bug_desc_sample_early_regression_tb.vvp > $(BUILD_DIR)/bug_desc_sample_early.log 2>&1; \
	status=$$?; \
	set -e; \
	if [ $$status -eq 0 ]; then \
		echo "ERROR: buggy descriptor-sampling RTL unexpectedly passed the golden regression."; \
		echo "See $(BUILD_DIR)/bug_desc_sample_early.log"; \
		exit 1; \
	fi; \
	if grep -q "TEST: descriptor sampling at arbitration grant" $(BUILD_DIR)/bug_desc_sample_early.log && \
	   grep -Eq "ARADDR mismatch|FATAL|fatal|FAIL" $(BUILD_DIR)/bug_desc_sample_early.log; then \
		echo "EXPECTED FAIL observed for bug_desc_sample_early."; \
		grep -E "TEST: descriptor sampling at arbitration grant|ARADDR mismatch|FATAL|fatal|FAIL" $(BUILD_DIR)/bug_desc_sample_early.log | tail -20; \
	else \
		echo "ERROR: buggy RTL failed, but not with the expected descriptor-sampling signature."; \
		tail -80 $(BUILD_DIR)/bug_desc_sample_early.log; \
		exit 1; \
	fi



bug_queue_no_pushback_expected_fail:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-I ../../tb/golden \
		-o $(BUILD_DIR)/bug_queue_no_pushback_regression_tb.vvp \
		-s samram_dma_regression_tb \
		$(BUG_QUEUE_NO_PUSHBACK_RTL_DIR)/samram_dma_top.v \
		../../tb/golden/samram_dma_regression_tb.v
	@set +e; \
	$(VVP) $(BUILD_DIR)/bug_queue_no_pushback_regression_tb.vvp > $(BUILD_DIR)/bug_queue_no_pushback.log 2>&1; \
	status=$$?; \
	set -e; \
	if [ $$status -eq 0 ]; then \
		echo "ERROR: buggy queue/no-pushback RTL unexpectedly passed the golden regression."; \
		echo "See $(BUILD_DIR)/bug_queue_no_pushback.log"; \
		exit 1; \
	fi; \
	if grep -q "TEST: descriptor multi-ring execution and push-back" $(BUILD_DIR)/bug_queue_no_pushback.log && \
	   grep -Eq "ARADDR mismatch|Initial CH0 descriptor ARADDR mismatch|FATAL|fatal|FAIL" $(BUILD_DIR)/bug_queue_no_pushback.log; then \
		echo "EXPECTED FAIL observed for bug_queue_no_pushback."; \
		grep -E "TEST: descriptor multi-ring execution and push-back|ARADDR mismatch|Initial CH0 descriptor ARADDR mismatch|FATAL|fatal|FAIL" $(BUILD_DIR)/bug_queue_no_pushback.log | tail -20; \
	else \
		echo "ERROR: buggy RTL failed, but not with the expected queue/no-pushback signature."; \
		tail -80 $(BUILD_DIR)/bug_queue_no_pushback.log; \
		exit 1; \
	fi



bug_interrupt_done_priority_expected_fail:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-I ../../tb/golden \
		-o $(BUILD_DIR)/bug_interrupt_done_priority_regression_tb.vvp \
		-s samram_dma_regression_tb \
		$(BUG_INTERRUPT_DONE_PRIORITY_RTL_DIR)/samram_dma_top.v \
		../../tb/golden/samram_dma_regression_tb.v
	@set +e; \
	$(VVP) $(BUILD_DIR)/bug_interrupt_done_priority_regression_tb.vvp > $(BUILD_DIR)/bug_interrupt_done_priority.log 2>&1; \
	status=$$?; \
	set -e; \
	if [ $$status -eq 0 ]; then \
		echo "ERROR: buggy interrupt-priority RTL unexpectedly passed the golden regression."; \
		echo "See $(BUILD_DIR)/bug_interrupt_done_priority.log"; \
		exit 1; \
	fi; \
	if grep -q "TEST: interrupt status priority and claim" $(BUILD_DIR)/bug_interrupt_done_priority.log && \
	   grep -Eq "APB READ FAIL addr=0x00000210|FATAL|fatal|FAIL" $(BUILD_DIR)/bug_interrupt_done_priority.log; then \
		echo "EXPECTED FAIL observed for bug_interrupt_done_priority."; \
		grep -E "TEST: interrupt status priority and claim|APB READ FAIL addr=0x00000210|FATAL|fatal|FAIL" $(BUILD_DIR)/bug_interrupt_done_priority.log | tail -20; \
	else \
		echo "ERROR: buggy RTL failed, but not with the expected interrupt-priority signature."; \
		tail -80 $(BUILD_DIR)/bug_interrupt_done_priority.log; \
		exit 1; \
	fi



bug_bad_wstrb_unaligned_dst_expected_fail:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-I ../../tb/golden \
		-o $(BUILD_DIR)/bug_bad_wstrb_unaligned_dst_regression_tb.vvp \
		-s samram_dma_regression_tb \
		$(BUG_BAD_WSTRB_UNALIGNED_DST_RTL_DIR)/samram_dma_top.v \
		../../tb/golden/samram_dma_regression_tb.v
	@set +e; \
	$(VVP) $(BUILD_DIR)/bug_bad_wstrb_unaligned_dst_regression_tb.vvp > $(BUILD_DIR)/bug_bad_wstrb_unaligned_dst.log 2>&1; \
	status=$$?; \
	set -e; \
	if [ $$status -eq 0 ]; then \
		echo "ERROR: buggy bad-WSTRB RTL unexpectedly passed the golden regression."; \
		echo "See $(BUILD_DIR)/bug_bad_wstrb_unaligned_dst.log"; \
		exit 1; \
	fi; \
	if grep -q "TEST: unaligned destination WSTRB/data alignment" $(BUILD_DIR)/bug_bad_wstrb_unaligned_dst.log && \
	   grep -Eq "WSTRB mismatch|WDATA active-lane mismatch|FATAL|fatal|FAIL" $(BUILD_DIR)/bug_bad_wstrb_unaligned_dst.log; then \
		echo "EXPECTED FAIL observed for bug_bad_wstrb_unaligned_dst."; \
		grep -E "TEST: unaligned destination WSTRB/data alignment|WSTRB mismatch|WDATA active-lane mismatch|FATAL|fatal|FAIL" $(BUILD_DIR)/bug_bad_wstrb_unaligned_dst.log | tail -20; \
	else \
		echo "ERROR: buggy RTL failed, but not with the expected unaligned-destination WSTRB signature."; \
		tail -80 $(BUILD_DIR)/bug_bad_wstrb_unaligned_dst.log; \
		exit 1; \
	fi


bug_done_irq_wrong_channel_expected_fail:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-I ../../tb/golden \
		-o $(BUILD_DIR)/bug_done_irq_wrong_channel_regression_tb.vvp \
		-s samram_dma_regression_tb \
		$(BUG_DONE_IRQ_WRONG_CHANNEL_RTL_DIR)/samram_dma_top.v \
		../../tb/golden/samram_dma_regression_tb.v
	@set +e; \
	$(VVP) $(BUILD_DIR)/bug_done_irq_wrong_channel_regression_tb.vvp > $(BUILD_DIR)/bug_done_irq_wrong_channel.log 2>&1; \
	status=$$?; \
	set -e; \
	if [ $$status -eq 0 ]; then \
		echo "ERROR: buggy wrong-channel DONE IRQ RTL unexpectedly passed the golden regression."; \
		echo "See $(BUILD_DIR)/bug_done_irq_wrong_channel.log"; \
		exit 1; \
	fi; \
	if grep -Eq "TEST: single-copy|TEST: descriptor single execution|TEST: multi-word" $(BUILD_DIR)/bug_done_irq_wrong_channel.log && \
	   grep -Eq "irq_done mismatch|irq_done should|APB READ FAIL addr=0x00000200|FATAL|fatal|FAIL" $(BUILD_DIR)/bug_done_irq_wrong_channel.log; then \
		echo "EXPECTED FAIL observed for bug_done_irq_wrong_channel."; \
		grep -E "TEST: single-copy|TEST: descriptor single execution|TEST: multi-word|irq_done mismatch|irq_done should|APB READ FAIL addr=0x00000200|FATAL|fatal|FAIL" $(BUILD_DIR)/bug_done_irq_wrong_channel.log | tail -20; \
	else \
		echo "ERROR: buggy RTL failed, but not with the expected wrong-channel DONE IRQ signature."; \
		tail -80 $(BUILD_DIR)/bug_done_irq_wrong_channel.log; \
		exit 1; \
	fi


bug_bad_src_shift_unaligned_src_expected_fail:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall \
		-I ../../tb/golden \
		-o $(BUILD_DIR)/bug_bad_src_shift_unaligned_src_regression_tb.vvp \
		-s samram_dma_regression_tb \
		$(BUG_BAD_SRC_SHIFT_UNALIGNED_SRC_RTL_DIR)/samram_dma_top.v \
		../../tb/golden/samram_dma_regression_tb.v
	@set +e; \
	$(VVP) $(BUILD_DIR)/bug_bad_src_shift_unaligned_src_regression_tb.vvp > $(BUILD_DIR)/bug_bad_src_shift_unaligned_src.log 2>&1; \
	status=$$?; \
	set -e; \
	if [ $$status -eq 0 ]; then \
		echo "ERROR: buggy unaligned-source shift RTL unexpectedly passed the golden regression."; \
		echo "See $(BUILD_DIR)/bug_bad_src_shift_unaligned_src.log"; \
		exit 1; \
	fi; \
	if grep -Eq "TEST: unaligned source read alignment and data shift|TEST: unaligned destination WSTRB/data alignment" $(BUILD_DIR)/bug_bad_src_shift_unaligned_src.log && \
	   grep -Eq "WDATA mismatch|WDATA active-lane mismatch" $(BUILD_DIR)/bug_bad_src_shift_unaligned_src.log; then \
		echo "EXPECTED FAIL observed for bug_bad_src_shift_unaligned_src."; \
		grep -E "TEST: unaligned source read alignment and data shift|TEST: unaligned destination WSTRB/data alignment|WDATA mismatch|WDATA active-lane mismatch|FATAL|fatal|FAIL" $(BUILD_DIR)/bug_bad_src_shift_unaligned_src.log | tail -20; \
	else \
		echo "ERROR: buggy RTL failed, but not with the expected unaligned-source shift signature."; \
		tail -80 $(BUILD_DIR)/bug_bad_src_shift_unaligned_src.log; \
		exit 1; \
	fi

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------

clean:
	rm -f $(BUILD_DIR)/samram_dma_top_compile.vvp
	rm -f $(BUILD_DIR)/samram_dma_csr_tb.vvp
	rm -f $(BUILD_DIR)/samram_dma_single_copy_tb.vvp
	rm -f $(BUILD_DIR)/samram_dma_multi_word_tb.vvp
	rm -f $(BUILD_DIR)/samram_dma_read_error_tb.vvp
	rm -f $(BUILD_DIR)/samram_dma_write_error_tb.vvp
	rm -f $(BUILD_DIR)/samram_dma_ctrl_clear_tb.vvp
	rm -f $(BUILD_DIR)/samram_dma_regression_tb.vvp
	rm -rf $(BUILD_DIR)/cocotb_axi_vip_smoke
	rm -rf $(BUILD_DIR)/cocotb_axi_vip_random
	rm -f $(BUILD_DIR)/bug_desc_sample_early_regression_tb.vvp
	rm -f $(BUILD_DIR)/bug_desc_sample_early.log
	rm -f $(BUILD_DIR)/bug_queue_no_pushback_regression_tb.vvp
	rm -f $(BUILD_DIR)/bug_queue_no_pushback.log
	rm -f $(BUILD_DIR)/bug_interrupt_done_priority_regression_tb.vvp
	rm -f $(BUILD_DIR)/bug_interrupt_done_priority.log
	rm -f $(BUILD_DIR)/bug_bad_wstrb_unaligned_dst_regression_tb.vvp
	rm -f $(BUILD_DIR)/bug_bad_wstrb_unaligned_dst.log
	rm -f $(BUILD_DIR)/bug_done_irq_wrong_channel_regression_tb.vvp
	rm -f $(BUILD_DIR)/bug_done_irq_wrong_channel.log
	rm -f $(BUILD_DIR)/bug_bad_src_shift_unaligned_src_regression_tb.vvp
	rm -f $(BUILD_DIR)/bug_bad_src_shift_unaligned_src.log
