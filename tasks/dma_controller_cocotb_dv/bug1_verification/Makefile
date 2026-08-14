SIM ?= icarus

TOPLEVEL_LANG ?= verilog

TOPLEVEL = samram_dma_top

COCOTB_TEST_MODULES = test_bug1_desc_sampling

VERILOG_SOURCES = \
    $(PWD)/samram_dma_apb_decode.v \
    $(PWD)/samram_dma_csr_write_ctrl.v \
    $(PWD)/samram_dma_irq_ctrl.v \
    $(PWD)/samram_dma_desc_ring.v \
    $(PWD)/samram_dma_scheduler.v \
    $(PWD)/samram_dma_rr_arbiter.v \
    $(PWD)/samram_dma_desc_sram.v \
    $(PWD)/samram_dma_csr_read_mux.v \
    $(PWD)/samram_dma_align.v \
    $(PWD)/samram_dma_xfer_engine.v \
    $(PWD)/samram_dma_apb_resp_mux.v \
    $(PWD)/samram_dma_axi_master_out.v \
    $(PWD)/samram_dma_top.v

COMPILE_ARGS += -I$(PWD)/include

export PYTHONPATH := $(PWD)/tb:$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim
