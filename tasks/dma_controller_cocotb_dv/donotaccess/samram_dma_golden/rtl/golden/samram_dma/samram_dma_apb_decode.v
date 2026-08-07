//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_apb_decode.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : APB address decoder for the DMA CSR aperture, descriptor SRAM
//               aperture, and interrupt-control aperture.
//
// Confidentiality:
//   Proprietary and confidential. Use only as authorized under the applicable
//   project agreement.
//
// Development Notice:
//   Created independently. No third-party confidential or proprietary
//   information, materials, tools, systems, documents, code, specifications,
//   or resources were used.
//------------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

// Pure decode block.  This module intentionally has no storage.  It separates
// the software-visible address map from the DMA datapath/state machines.

module samram_dma_apb_decode #(
    parameter ADDR_WIDTH = 32
)(
    input  wire [ADDR_WIDTH-1:0] paddr,
    input  wire                  psel,
    input  wire                  penable,
    input  wire                  pwrite,

    output wire                  apb_access,
    output wire                  apb_write,

    output wire                  apb_csr_region,
    output wire [2:0]            apb_ch,
    output wire [2:0]            apb_reg,
    output wire                  apb_reg_valid,

    output wire                  apb_desc_region,
    output wire [2:0]            desc_apb_ch,
    output wire [1:0]            desc_apb_slot,
    output wire [1:0]            desc_apb_word,
    output wire [4:0]            desc_apb_index,
    output wire                  desc_apb_valid,

    output wire                  apb_int_region,
    output wire [2:0]            int_apb_reg,
    output wire                  int_apb_valid,

    output wire                  apb_any_valid
);

localparam [2:0] REG_SRC_ADDR         = 3'd0;
localparam [2:0] REG_DST_ADDR         = 3'd1;
localparam [2:0] REG_LEN_BYTES        = 3'd2;
localparam [2:0] REG_CTRL             = 3'd3;
localparam [2:0] REG_STATUS           = 3'd4;
localparam [2:0] REG_DESC_HEAD        = 3'd5;
localparam [2:0] REG_DESC_TAIL        = 3'd6;
localparam [2:0] REG_DESC_RING_STATUS = 3'd7;

localparam [2:0] INT_REG_DONE_STATUS  = 3'd0;
localparam [2:0] INT_REG_ERROR_STATUS = 3'd1;
localparam [2:0] INT_REG_IRQ_ENABLE   = 3'd2;
localparam [2:0] INT_REG_FIQ_ENABLE   = 3'd3;
localparam [2:0] INT_REG_CLAIM        = 3'd4;
localparam [2:0] INT_REG_CLEAR        = 3'd5;

assign apb_access = psel && penable;
assign apb_write  = apb_access && pwrite;

// CSR aperture: 0x0000 - 0x00ff
assign apb_csr_region = (paddr[15:8] == 8'h00);
assign apb_ch         = paddr[7:5];
assign apb_reg        = paddr[4:2];

assign apb_reg_valid =
    apb_csr_region &&
    ((apb_reg == REG_SRC_ADDR)         ||
     (apb_reg == REG_DST_ADDR)         ||
     (apb_reg == REG_LEN_BYTES)        ||
     (apb_reg == REG_CTRL)             ||
     (apb_reg == REG_STATUS)           ||
     (apb_reg == REG_DESC_HEAD)        ||
     (apb_reg == REG_DESC_TAIL)        ||
     (apb_reg == REG_DESC_RING_STATUS));

// Descriptor SRAM aperture: 0x1000 - 0x11ff
assign apb_desc_region = (paddr[15:9] == 7'b0001000);
assign desc_apb_ch     = paddr[8:6];
assign desc_apb_slot   = paddr[5:4];
assign desc_apb_word   = paddr[3:2];
assign desc_apb_index  = {desc_apb_ch, desc_apb_slot};
assign desc_apb_valid  = apb_desc_region;

// Interrupt aperture: 0x0200 - 0x02ff
assign apb_int_region = (paddr[15:8] == 8'h02);
assign int_apb_reg    = paddr[4:2];

assign int_apb_valid =
    apb_int_region &&
    ((int_apb_reg == INT_REG_DONE_STATUS)  ||
     (int_apb_reg == INT_REG_ERROR_STATUS) ||
     (int_apb_reg == INT_REG_IRQ_ENABLE)   ||
     (int_apb_reg == INT_REG_FIQ_ENABLE)   ||
     (int_apb_reg == INT_REG_CLAIM)        ||
     (int_apb_reg == INT_REG_CLEAR));

assign apb_any_valid = apb_reg_valid || desc_apb_valid || int_apb_valid;

endmodule

`default_nettype wire
