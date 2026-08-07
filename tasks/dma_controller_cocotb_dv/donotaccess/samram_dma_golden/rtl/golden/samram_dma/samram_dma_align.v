//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_align.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : Combinational byte-alignment helper for unaligned source and
//               destination handling, partial final beats, WSTRB generation,
//               AXI read-address alignment, and write-data lane placement.
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

// Pure combinational alignment helper for unaligned source/destination accesses,
// partial final writes, WSTRB generation, and AXI read-address alignment.

module samram_dma_align #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8)
)(
    input  wire [ADDR_WIDTH-1:0] dma_src_addr,
    input  wire [ADDR_WIDTH-1:0] dma_dst_addr,
    input  wire [DATA_WIDTH-1:0] dma_len_left,
    input  wire [DATA_WIDTH-1:0] dma_rdata,
    input  wire [DATA_WIDTH-1:0] dma_buf_bytes,

    output wire [ADDR_WIDTH-1:0] araddr,
    output wire [DATA_WIDTH-1:0] src_read_bytes_o,
    output wire [DATA_WIDTH-1:0] write_bytes,
    output wire [STRB_WIDTH-1:0] wstrb,
    output wire [DATA_WIDTH-1:0] wdata
);

localparam [DATA_WIDTH-1:0] BUS_BYTES_VALUE =
    (STRB_WIDTH == 1)  ? 32'd1  :
    (STRB_WIDTH == 2)  ? 32'd2  :
    (STRB_WIDTH == 4)  ? 32'd4  :
    (STRB_WIDTH == 8)  ? 32'd8  :
    (STRB_WIDTH == 16) ? 32'd16 :
    (STRB_WIDTH == 32) ? 32'd32 :
                         32'd0;

`include "samram_dma_funcs.vh"

assign araddr         = src_aligned_addr(dma_src_addr);
assign src_read_bytes_o = src_read_bytes(dma_src_addr, dma_len_left);
assign write_bytes    = dst_write_bytes(dma_dst_addr, dma_buf_bytes);
assign wstrb          = dst_wstrb(dma_dst_addr, dma_buf_bytes);
assign wdata          = mask_wdata_by_strb(dst_shift_wdata(dma_rdata, dma_dst_addr), wstrb);

endmodule

`default_nettype wire
