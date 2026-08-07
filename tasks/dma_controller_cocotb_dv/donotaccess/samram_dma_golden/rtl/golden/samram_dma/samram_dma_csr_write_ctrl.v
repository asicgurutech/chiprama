//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_csr_write_ctrl.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : CSR write/control decoder that generates register write enables,
//               CTRL command pulses, descriptor doorbell controls, start/error
//               qualification, and interrupt-clear masks.
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

// Decodes APB writes into explicit CSR register write enables, CTRL command
// pulses, descriptor doorbell control, and software interrupt-clear masks.
// All APB/CTRL side-effect decode is centralized here; the top-level
// sequential block consumes the output enables and next-value buses directly.

module samram_dma_csr_write_ctrl #(
    parameter NUM_CH          = 8,
    parameter DATA_WIDTH      = 32,
    parameter STRB_WIDTH      = DATA_WIDTH/8,
    parameter [2:0] DESC_RING_DEPTH = 3'd4
)(
    input  wire                         apb_write,
    input  wire                         apb_reg_valid,
    input  wire [2:0]                   apb_ch,
    input  wire [2:0]                   apb_reg,
    input  wire [DATA_WIDTH-1:0]        apb_wdata,
    input  wire [STRB_WIDTH-1:0]        apb_wstrb,

    input  wire                         int_write_valid,
    input  wire [2:0]                   int_reg,
    input  wire [DATA_WIDTH-1:0]        int_wdata,

    input  wire [DATA_WIDTH-1:0]        ch_src_addr_cur,
    input  wire [DATA_WIDTH-1:0]        ch_dst_addr_cur,
    input  wire [DATA_WIDTH-1:0]        ch_len_bytes_cur,
    input  wire                         ch_busy_cur,
    input  wire                         ch_desc_mode_cur,
    input  wire                         ch_pending_cur,
    input  wire                         dma_active,
    input  wire [2:0]                   desc_count_cur,

    output wire [2:0]                   csr_write_ch,
    output wire                         csr_src_write_valid,
    output wire                         csr_dst_write_valid,
    output wire                         csr_len_write_valid,
    output wire                         csr_ctrl_write_valid,
    output wire [DATA_WIDTH-1:0]        csr_src_next,
    output wire [DATA_WIDTH-1:0]        csr_dst_next,
    output wire [DATA_WIDTH-1:0]        csr_len_next,
    output wire [DATA_WIDTH-1:0]        csr_ctrl_next,

    output wire                         csr_ctrl_clear_done,
    output wire                         csr_ctrl_clear_error,
    output wire                         csr_ctrl_desc_doorbell,
    output wire                         csr_ctrl_start,

    output wire                         desc_doorbell_req,
    output wire                         desc_doorbell_full,
    output wire                         desc_doorbell_fire,
    output wire                         desc_doorbell_full_error,
    output wire                         desc_doorbell_first_accept,
    output wire                         desc_doorbell_requeue_accept,

    output wire                         csr_start_duplicate_error,
    output wire                         csr_start_accept,
    output wire                         csr_start_zero_len_error,

    output wire [NUM_CH-1:0]            int_clear_done_mask,
    output wire [NUM_CH-1:0]            int_clear_error_mask,
    output wire [NUM_CH-1:0]            irq_done_clear_mask
);

localparam [2:0] REG_SRC_ADDR         = 3'd0;
localparam [2:0] REG_DST_ADDR         = 3'd1;
localparam [2:0] REG_LEN_BYTES        = 3'd2;
localparam [2:0] REG_CTRL             = 3'd3;

localparam [2:0] INT_REG_CLEAR        = 3'd5;

localparam CTRL_START_BIT             = 0;
localparam CTRL_CLEAR_DONE_BIT        = 1;
localparam CTRL_CLEAR_ERROR_BIT       = 2;
localparam CTRL_DESC_DOORBELL_BIT     = 3;

wire ctrl_byte0_write;
wire [NUM_CH-1:0] csr_ctrl_clear_done_mask;
wire [NUM_CH-1:0] csr_start_accept_mask;
wire [NUM_CH-1:0] csr_doorbell_first_accept_mask;

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

assign csr_write_ch = apb_ch;

assign csr_src_write_valid  = apb_write && apb_reg_valid && (apb_reg == REG_SRC_ADDR);
assign csr_dst_write_valid  = apb_write && apb_reg_valid && (apb_reg == REG_DST_ADDR);
assign csr_len_write_valid  = apb_write && apb_reg_valid && (apb_reg == REG_LEN_BYTES);
assign csr_ctrl_write_valid = apb_write && apb_reg_valid && (apb_reg == REG_CTRL);

assign csr_src_next  = apply_pstrb(ch_src_addr_cur,  apb_wdata, apb_wstrb);
assign csr_dst_next  = apply_pstrb(ch_dst_addr_cur,  apb_wdata, apb_wstrb);
assign csr_len_next  = apply_pstrb(ch_len_bytes_cur, apb_wdata, apb_wstrb);
assign csr_ctrl_next = {DATA_WIDTH{1'b0}};

assign ctrl_byte0_write = csr_ctrl_write_valid && apb_wstrb[0];

assign csr_ctrl_clear_done    = ctrl_byte0_write && apb_wdata[CTRL_CLEAR_DONE_BIT];
assign csr_ctrl_clear_error   = ctrl_byte0_write && apb_wdata[CTRL_CLEAR_ERROR_BIT];
assign csr_ctrl_desc_doorbell = ctrl_byte0_write && apb_wdata[CTRL_DESC_DOORBELL_BIT];
assign csr_ctrl_start         = ctrl_byte0_write && apb_wdata[CTRL_START_BIT];

assign desc_doorbell_req   = csr_ctrl_desc_doorbell;
assign desc_doorbell_full  = (desc_count_cur == DESC_RING_DEPTH);
assign desc_doorbell_fire  = desc_doorbell_req && !desc_doorbell_full;

assign desc_doorbell_full_error = desc_doorbell_req && desc_doorbell_full;
assign desc_doorbell_first_accept =
    desc_doorbell_req && !desc_doorbell_full && !ch_busy_cur;
assign desc_doorbell_requeue_accept =
    desc_doorbell_req && !desc_doorbell_full && ch_busy_cur &&
    ch_desc_mode_cur && !ch_pending_cur && !dma_active;

assign csr_start_duplicate_error = csr_ctrl_start && ch_busy_cur;
assign csr_start_accept =
    csr_ctrl_start && !ch_busy_cur && (ch_len_bytes_cur != {DATA_WIDTH{1'b0}});
assign csr_start_zero_len_error =
    csr_ctrl_start && !ch_busy_cur && (ch_len_bytes_cur == {DATA_WIDTH{1'b0}});

assign int_clear_done_mask =
    (int_write_valid && (int_reg == INT_REG_CLEAR))
        ? int_wdata[NUM_CH-1:0]
        : {NUM_CH{1'b0}};

assign int_clear_error_mask =
    (int_write_valid && (int_reg == INT_REG_CLEAR))
        ? int_wdata[8 +: NUM_CH]
        : {NUM_CH{1'b0}};

assign csr_ctrl_clear_done_mask =
    csr_ctrl_clear_done ? ({{(NUM_CH-1){1'b0}}, 1'b1} << apb_ch) : {NUM_CH{1'b0}};

assign csr_start_accept_mask =
    csr_start_accept ? ({{(NUM_CH-1){1'b0}}, 1'b1} << apb_ch) : {NUM_CH{1'b0}};

assign csr_doorbell_first_accept_mask =
    desc_doorbell_first_accept ? ({{(NUM_CH-1){1'b0}}, 1'b1} << apb_ch) : {NUM_CH{1'b0}};

assign irq_done_clear_mask =
    csr_ctrl_clear_done_mask |
    csr_start_accept_mask |
    csr_doorbell_first_accept_mask |
    int_clear_done_mask;

endmodule

`default_nettype wire
