//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_defs.vh
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : Shared parameters, macros, register offsets, descriptor word
//               encodings, control/status bit positions, and interrupt register
//               definitions for the SAMRAM DMA benchmark block.
//
// Confidentiality:
//   Proprietary and confidential. Use only as authorized under the applicable
//   project agreement.
//------------------------------------------------------------------------------

// This file documents shared register offsets and bit definitions.
// Parameter-local localparams in samram_dma_top.v are kept for
// Icarus/Verilator compatibility; this include provides a single canonical
// reference for all shared constants.

`ifndef SAMRAM_DMA_DEFS_VH
`define SAMRAM_DMA_DEFS_VH

`define SAMRAM_DMA_NUM_CH_DEFAULT              8
`define SAMRAM_DMA_ADDR_WIDTH_DEFAULT          32
`define SAMRAM_DMA_DATA_WIDTH_DEFAULT          32
`define SAMRAM_DMA_AXI_ID_WIDTH_DEFAULT        4
`define SAMRAM_DMA_DESC_SLOTS_PER_CH_DEFAULT   4

`define SAMRAM_DMA_REG_SRC_ADDR                3'd0
`define SAMRAM_DMA_REG_DST_ADDR                3'd1
`define SAMRAM_DMA_REG_LEN_BYTES               3'd2
`define SAMRAM_DMA_REG_CTRL                    3'd3
`define SAMRAM_DMA_REG_STATUS                  3'd4
`define SAMRAM_DMA_REG_DESC_HEAD               3'd5
`define SAMRAM_DMA_REG_DESC_TAIL               3'd6
`define SAMRAM_DMA_REG_DESC_RING_STATUS        3'd7

`define SAMRAM_DMA_STATUS_BUSY_BIT             0
`define SAMRAM_DMA_STATUS_DONE_BIT             1
`define SAMRAM_DMA_STATUS_ERR_BIT              2

`define SAMRAM_DMA_CTRL_START_BIT              0
`define SAMRAM_DMA_CTRL_CLEAR_DONE_BIT         1
`define SAMRAM_DMA_CTRL_CLEAR_ERROR_BIT        2
`define SAMRAM_DMA_CTRL_DESC_DOORBELL_BIT      3

`define SAMRAM_DMA_INT_REG_DONE_STATUS         3'd0
`define SAMRAM_DMA_INT_REG_ERROR_STATUS        3'd1
`define SAMRAM_DMA_INT_REG_IRQ_ENABLE          3'd2
`define SAMRAM_DMA_INT_REG_FIQ_ENABLE          3'd3
`define SAMRAM_DMA_INT_REG_CLAIM               3'd4
`define SAMRAM_DMA_INT_REG_CLEAR               3'd5

`define SAMRAM_DMA_DESC_WORD_SRC_ADDR          2'd0
`define SAMRAM_DMA_DESC_WORD_DST_ADDR          2'd1
`define SAMRAM_DMA_DESC_WORD_LEN_BYTES         2'd2
`define SAMRAM_DMA_DESC_WORD_CTRL_STATUS       2'd3

`endif // SAMRAM_DMA_DEFS_VH
