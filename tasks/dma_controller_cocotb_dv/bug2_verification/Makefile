SIM ?= icarus

TOPLEVEL_LANG ?= verilog

TOPLEVEL = samram_dma_top

COCOTB_TEST_MODULES = test_bug2_boundary_address

PROJECT_ROOT = $(abspath $(PWD)/..)

VERILOG_SOURCES = \
    $(PROJECT_ROOT)/samram_dma_apb_decode.v \
    $(PROJECT_ROOT)/samram_dma_csr_write_ctrl.v \
    $(PROJECT_ROOT)/samram_dma_irq_ctrl.v \
    $(PROJECT_ROOT)/samram_dma_desc_ring.v \
    $(PROJECT_ROOT)/samram_dma_scheduler.v \
    $(PROJECT_ROOT)/samram_dma_rr_arbiter.v \
    $(PROJECT_ROOT)/samram_dma_desc_sram.v \
    $(PROJECT_ROOT)/samram_dma_csr_read_mux.v \
    $(PROJECT_ROOT)/samram_dma_align.v \
    $(PROJECT_ROOT)/samram_dma_xfer_engine.v \
    $(PROJECT_ROOT)/samram_dma_apb_resp_mux.v \
    $(PROJECT_ROOT)/samram_dma_axi_master_out.v \
    $(PROJECT_ROOT)/samram_dma_top.v

COMPILE_ARGS += -I$(PROJECT_ROOT)/include

export PYTHONPATH := $(PWD)/tb:$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim
