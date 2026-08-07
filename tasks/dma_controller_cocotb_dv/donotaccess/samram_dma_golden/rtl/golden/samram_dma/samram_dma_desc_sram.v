//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_desc_sram.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : Descriptor SRAM storage with APB read/write access and a
//               descriptor fetch read port for scheduler/transfer execution.
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

// Descriptor aperture is decoded in samram_dma_apb_decode.v. This module owns
// the descriptor storage array and provides:
//   - APB write/read access for software-visible descriptor SRAM
//   - combinational descriptor fetch read data for the DMA scheduler/executor
//
// Descriptor layout per slot:
//   word0 = SRC_ADDR
//   word1 = DST_ADDR
//   word2 = LEN_BYTES
//   word3 = CTRL_STATUS
//
// Addressing is flattened before entering this block:
//   desc_apb_index   = {channel[2:0], slot[1:0]}
//   desc_fetch_index = {channel[2:0], head[1:0]}
// -----------------------------------------------------------------------------

module samram_dma_desc_sram #(
    parameter NUM_CH            = 8,
    parameter DATA_WIDTH        = 32,
    parameter STRB_WIDTH        = (DATA_WIDTH/8),
    parameter DESC_SLOTS_PER_CH = 4
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // APB descriptor SRAM access after decode
    input  wire                         apb_write,
    input  wire                         desc_apb_valid,
    input  wire [4:0]                   desc_apb_index,
    input  wire [1:0]                   desc_apb_word,
    input  wire [DATA_WIDTH-1:0]        desc_apb_wdata,
    input  wire [STRB_WIDTH-1:0]        desc_apb_wstrb,
    output reg  [DATA_WIDTH-1:0]        desc_apb_rdata,

    // DMA descriptor fetch read port
    input  wire [4:0]                   desc_fetch_index,
    output wire [DATA_WIDTH-1:0]        desc_fetch_src_addr,
    output wire [DATA_WIDTH-1:0]        desc_fetch_dst_addr,
    output wire [DATA_WIDTH-1:0]        desc_fetch_len_bytes
);

localparam integer DESC_COUNT = NUM_CH * DESC_SLOTS_PER_CH;

localparam [1:0] DESC_WORD_SRC_ADDR    = 2'd0;
localparam [1:0] DESC_WORD_DST_ADDR    = 2'd1;
localparam [1:0] DESC_WORD_LEN_BYTES   = 2'd2;
localparam [1:0] DESC_WORD_CTRL_STATUS = 2'd3;

reg [DATA_WIDTH-1:0] desc_src_addr_reg     [0:DESC_COUNT-1];
reg [DATA_WIDTH-1:0] desc_dst_addr_reg     [0:DESC_COUNT-1];
reg [DATA_WIDTH-1:0] desc_len_bytes_reg    [0:DESC_COUNT-1];
reg [DATA_WIDTH-1:0] desc_ctrl_status_reg  [0:DESC_COUNT-1];

integer i;

function [DATA_WIDTH-1:0] apply_pstrb;
    input [DATA_WIDTH-1:0] old_data;
    input [DATA_WIDTH-1:0] new_data;
    input [STRB_WIDTH-1:0] strb;
    integer byte_idx;
    begin
        apply_pstrb = old_data;
        for (byte_idx = 0; byte_idx < STRB_WIDTH; byte_idx = byte_idx + 1) begin
            if (strb[byte_idx]) begin
                apply_pstrb[byte_idx*8 +: 8] = new_data[byte_idx*8 +: 8];
            end
        end
    end
endfunction

always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < DESC_COUNT; i = i + 1) begin
            desc_src_addr_reg[i]     <= {DATA_WIDTH{1'b0}};
            desc_dst_addr_reg[i]     <= {DATA_WIDTH{1'b0}};
            desc_len_bytes_reg[i]    <= {DATA_WIDTH{1'b0}};
            desc_ctrl_status_reg[i]  <= {DATA_WIDTH{1'b0}};
        end
    end else begin
        if (apb_write && desc_apb_valid) begin
            case (desc_apb_word)
                DESC_WORD_SRC_ADDR: begin
                    desc_src_addr_reg[desc_apb_index] <= apply_pstrb(
                        desc_src_addr_reg[desc_apb_index],
                        desc_apb_wdata,
                        desc_apb_wstrb
                    );
                end

                DESC_WORD_DST_ADDR: begin
                    desc_dst_addr_reg[desc_apb_index] <= apply_pstrb(
                        desc_dst_addr_reg[desc_apb_index],
                        desc_apb_wdata,
                        desc_apb_wstrb
                    );
                end

                DESC_WORD_LEN_BYTES: begin
                    desc_len_bytes_reg[desc_apb_index] <= apply_pstrb(
                        desc_len_bytes_reg[desc_apb_index],
                        desc_apb_wdata,
                        desc_apb_wstrb
                    );
                end

                DESC_WORD_CTRL_STATUS: begin
                    desc_ctrl_status_reg[desc_apb_index] <= apply_pstrb(
                        desc_ctrl_status_reg[desc_apb_index],
                        desc_apb_wdata,
                        desc_apb_wstrb
                    );
                end

                default: begin
                    // No action.
                end
            endcase
        end
    end
end

always @* begin
    case (desc_apb_word)
        DESC_WORD_SRC_ADDR: begin
            desc_apb_rdata = desc_src_addr_reg[desc_apb_index];
        end

        DESC_WORD_DST_ADDR: begin
            desc_apb_rdata = desc_dst_addr_reg[desc_apb_index];
        end

        DESC_WORD_LEN_BYTES: begin
            desc_apb_rdata = desc_len_bytes_reg[desc_apb_index];
        end

        DESC_WORD_CTRL_STATUS: begin
            desc_apb_rdata = desc_ctrl_status_reg[desc_apb_index];
        end

        default: begin
            desc_apb_rdata = {DATA_WIDTH{1'b0}};
        end
    endcase
end

assign desc_fetch_src_addr  = desc_src_addr_reg[desc_fetch_index];
assign desc_fetch_dst_addr  = desc_dst_addr_reg[desc_fetch_index];
assign desc_fetch_len_bytes = desc_len_bytes_reg[desc_fetch_index];

endmodule

`default_nettype wire
