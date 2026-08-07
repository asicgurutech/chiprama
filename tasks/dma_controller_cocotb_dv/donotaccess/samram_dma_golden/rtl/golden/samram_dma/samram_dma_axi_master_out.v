//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_axi_master_out.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : AXI master output adapter that maps transfer-engine state and
//               aligned datapath signals onto AXI read and write channels.
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

module samram_dma_axi_master_out #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter STRB_WIDTH   = (DATA_WIDTH/8),
    parameter AXI_ID_WIDTH = 4
)(
    input  wire [2:0]                   dma_state,
    input  wire [ADDR_WIDTH-1:0]        dma_dst_addr,
    input  wire [ADDR_WIDTH-1:0]        dma_araddr,
    input  wire [DATA_WIDTH-1:0]        dma_wdata,
    input  wire [STRB_WIDTH-1:0]        dma_wstrb,

    // AXI master write address channel
    output wire [AXI_ID_WIDTH-1:0]      m_axi_awid,
    output wire [ADDR_WIDTH-1:0]        m_axi_awaddr,
    output wire [7:0]                   m_axi_awlen,
    output wire [2:0]                   m_axi_awsize,
    output wire [1:0]                   m_axi_awburst,
    output wire                         m_axi_awlock,
    output wire [3:0]                   m_axi_awcache,
    output wire [2:0]                   m_axi_awprot,
    output wire [3:0]                   m_axi_awqos,
    output wire                         m_axi_awvalid,

    // AXI master write data channel
    output wire [DATA_WIDTH-1:0]        m_axi_wdata,
    output wire [STRB_WIDTH-1:0]        m_axi_wstrb,
    output wire                         m_axi_wlast,
    output wire                         m_axi_wvalid,

    // AXI master write response channel
    output wire                         m_axi_bready,

    // AXI master read address channel
    output wire [AXI_ID_WIDTH-1:0]      m_axi_arid,
    output wire [ADDR_WIDTH-1:0]        m_axi_araddr,
    output wire [7:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output wire [1:0]                   m_axi_arburst,
    output wire                         m_axi_arlock,
    output wire [3:0]                   m_axi_arcache,
    output wire [2:0]                   m_axi_arprot,
    output wire [3:0]                   m_axi_arqos,
    output wire                         m_axi_arvalid,

    // AXI master read data channel
    output wire                         m_axi_rready
);

localparam [2:0] AXI_SIZE =
    (STRB_WIDTH == 1)  ? 3'd0 :
    (STRB_WIDTH == 2)  ? 3'd1 :
    (STRB_WIDTH == 4)  ? 3'd2 :
    (STRB_WIDTH == 8)  ? 3'd3 :
    (STRB_WIDTH == 16) ? 3'd4 :
    (STRB_WIDTH == 32) ? 3'd5 :
                         3'd0;

localparam [2:0] DMA_ST_AR = 3'd1;
localparam [2:0] DMA_ST_R  = 3'd2;
localparam [2:0] DMA_ST_AW = 3'd3;
localparam [2:0] DMA_ST_W  = 3'd4;
localparam [2:0] DMA_ST_B  = 3'd5;

// AXI master output defaults / single-beat datapath
assign m_axi_awid    = {AXI_ID_WIDTH{1'b0}};
assign m_axi_awaddr  = dma_dst_addr;
assign m_axi_awlen   = 8'd0;
assign m_axi_awsize  = AXI_SIZE;
assign m_axi_awburst = 2'b01; // INCR
assign m_axi_awlock  = 1'b0;
assign m_axi_awcache = 4'b0011;
assign m_axi_awprot  = 3'b010;
assign m_axi_awqos   = 4'd0;
assign m_axi_awvalid = (dma_state == DMA_ST_AW);

assign m_axi_wdata   = dma_wdata;
assign m_axi_wstrb   = dma_wstrb;
assign m_axi_wlast   = (dma_state == DMA_ST_W);
assign m_axi_wvalid  = (dma_state == DMA_ST_W);
assign m_axi_bready  = (dma_state == DMA_ST_B);

assign m_axi_arid    = {AXI_ID_WIDTH{1'b0}};
assign m_axi_araddr  = dma_araddr;
assign m_axi_arlen   = 8'd0;
assign m_axi_arsize  = AXI_SIZE;
assign m_axi_arburst = 2'b01; // INCR
assign m_axi_arlock  = 1'b0;
assign m_axi_arcache = 4'b0011;
assign m_axi_arprot  = 3'b010;
assign m_axi_arqos   = 4'd0;
assign m_axi_arvalid = (dma_state == DMA_ST_AR);
assign m_axi_rready  = (dma_state == DMA_ST_R);

endmodule

`default_nettype wire
