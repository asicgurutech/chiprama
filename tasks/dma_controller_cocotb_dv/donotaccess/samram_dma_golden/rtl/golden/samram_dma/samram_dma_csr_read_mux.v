//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_csr_read_mux.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : CSR readback mux for per-channel source, destination, length,
//               control, status, descriptor head/tail, and ring-status fields.
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

// Pure combinational readback logic for the per-channel CSR aperture.
// -----------------------------------------------------------------------------

module samram_dma_csr_read_mux #(
    parameter NUM_CH     = 8,
    parameter DATA_WIDTH = 32
)(
    input  wire                         apb_reg_valid,
    input  wire [2:0]                   apb_ch,
    input  wire [2:0]                   apb_reg,

    input  wire [NUM_CH*DATA_WIDTH-1:0] ch_src_addr_flat,
    input  wire [NUM_CH*DATA_WIDTH-1:0] ch_dst_addr_flat,
    input  wire [NUM_CH*DATA_WIDTH-1:0] ch_len_bytes_flat,
    input  wire [NUM_CH*DATA_WIDTH-1:0] ch_ctrl_flat,
    input  wire [NUM_CH*DATA_WIDTH-1:0] ch_status_flat,

    input  wire [NUM_CH*2-1:0]          desc_head_flat,
    input  wire [NUM_CH*2-1:0]          desc_tail_flat,
    input  wire [NUM_CH*3-1:0]          desc_count_flat,

    output reg  [DATA_WIDTH-1:0]        csr_prdata
);

localparam [2:0] REG_SRC_ADDR         = 3'd0;
localparam [2:0] REG_DST_ADDR         = 3'd1;
localparam [2:0] REG_LEN_BYTES        = 3'd2;
localparam [2:0] REG_CTRL             = 3'd3;
localparam [2:0] REG_STATUS           = 3'd4;
localparam [2:0] REG_DESC_HEAD        = 3'd5;
localparam [2:0] REG_DESC_TAIL        = 3'd6;
localparam [2:0] REG_DESC_RING_STATUS = 3'd7;

localparam [2:0] DESC_RING_DEPTH = 3'd4;

integer sel_idx;

reg [DATA_WIDTH-1:0] ch_src_addr_sel;
reg [DATA_WIDTH-1:0] ch_dst_addr_sel;
reg [DATA_WIDTH-1:0] ch_len_bytes_sel;
reg [DATA_WIDTH-1:0] ch_ctrl_sel;
reg [DATA_WIDTH-1:0] ch_status_sel;
reg [1:0]            desc_head_sel;
reg [1:0]            desc_tail_sel;
reg [2:0]            desc_count_sel;

always @* begin
    ch_src_addr_sel  = {DATA_WIDTH{1'b0}};
    ch_dst_addr_sel  = {DATA_WIDTH{1'b0}};
    ch_len_bytes_sel = {DATA_WIDTH{1'b0}};
    ch_ctrl_sel      = {DATA_WIDTH{1'b0}};
    ch_status_sel    = {DATA_WIDTH{1'b0}};
    desc_head_sel    = 2'd0;
    desc_tail_sel    = 2'd0;
    desc_count_sel   = 3'd0;

    for (sel_idx = 0; sel_idx < NUM_CH; sel_idx = sel_idx + 1) begin
        if (apb_ch == sel_idx[2:0]) begin
            ch_src_addr_sel  = ch_src_addr_flat[(sel_idx*DATA_WIDTH) +: DATA_WIDTH];
            ch_dst_addr_sel  = ch_dst_addr_flat[(sel_idx*DATA_WIDTH) +: DATA_WIDTH];
            ch_len_bytes_sel = ch_len_bytes_flat[(sel_idx*DATA_WIDTH) +: DATA_WIDTH];
            ch_ctrl_sel      = ch_ctrl_flat[(sel_idx*DATA_WIDTH) +: DATA_WIDTH];
            ch_status_sel    = ch_status_flat[(sel_idx*DATA_WIDTH) +: DATA_WIDTH];
            desc_head_sel    = desc_head_flat[(sel_idx*2) +: 2];
            desc_tail_sel    = desc_tail_flat[(sel_idx*2) +: 2];
            desc_count_sel   = desc_count_flat[(sel_idx*3) +: 3];
        end
    end
end

always @* begin
    csr_prdata = {DATA_WIDTH{1'b0}};

    if (apb_reg_valid) begin
        case (apb_reg)
            REG_SRC_ADDR: begin
                csr_prdata = ch_src_addr_sel;
            end

            REG_DST_ADDR: begin
                csr_prdata = ch_dst_addr_sel;
            end

            REG_LEN_BYTES: begin
                csr_prdata = ch_len_bytes_sel;
            end

            REG_CTRL: begin
                csr_prdata = ch_ctrl_sel;
            end

            REG_STATUS: begin
                csr_prdata = ch_status_sel;
            end

            REG_DESC_HEAD: begin
                csr_prdata = {{(DATA_WIDTH-2){1'b0}}, desc_head_sel};
            end

            REG_DESC_TAIL: begin
                csr_prdata = {{(DATA_WIDTH-2){1'b0}}, desc_tail_sel};
            end

            REG_DESC_RING_STATUS: begin
                csr_prdata = {
                    {(DATA_WIDTH-10){1'b0}},
                    (desc_count_sel == DESC_RING_DEPTH), // FULL, bit 9
                    (desc_count_sel != 3'd0),             // READY, bit 8
                    1'b0,                                 // reserved, bit 7
                    desc_count_sel,                       // COUNT, bits 6:4
                    desc_tail_sel,                        // TAIL, bits 3:2
                    desc_head_sel                         // HEAD, bits 1:0
                };
            end

            default: begin
                csr_prdata = {DATA_WIDTH{1'b0}};
            end
        endcase
    end
end

endmodule

`default_nettype wire
