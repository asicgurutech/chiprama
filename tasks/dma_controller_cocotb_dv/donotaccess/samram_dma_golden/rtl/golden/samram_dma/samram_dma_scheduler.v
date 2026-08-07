//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_scheduler.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : DMA scheduler helper that selects pending channels, qualifies
//               descriptor fetches, generates descriptor pop events, and
//               computes the next arbitration pointer.
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

module samram_dma_scheduler #(
    parameter NUM_CH     = 8,
    parameter DATA_WIDTH = 32
)(
    input  wire [NUM_CH-1:0]        ch_pending,
    input  wire [NUM_CH-1:0]        ch_desc_mode,
    input  wire [NUM_CH-1:0]        ch_desc_need_fetch,
    input  wire [NUM_CH*2-1:0]      desc_head_flat,
    input  wire [2:0]               arb_next_ch,

    input  wire [2:0]               dma_state,
    input  wire                     m_axi_bvalid,
    input  wire [1:0]               m_axi_bresp,
    input  wire [DATA_WIDTH-1:0]    dma_buf_bytes,
    input  wire [DATA_WIDTH-1:0]    dma_write_bytes,
    input  wire [DATA_WIDTH-1:0]    desc_fetch_len_bytes,

    output wire                     pending_valid,
    output wire [2:0]               pending_ch_sel,
    output wire                     pending_desc_fetch_valid,
    output wire                     desc_fetch_pop_valid,
    output wire [4:0]               desc_fetch_index,
    output wire [2:0]               pending_next_ch
);

localparam [2:0] DMA_ST_IDLE = 3'd0;
localparam [2:0] DMA_ST_B    = 3'd5;
localparam [1:0] AXI_RESP_OKAY = 2'b00;

reg  [1:0] pending_desc_head;
wire       pending_is_desc_fetch;

samram_dma_rr_arbiter #(
    .NUM_CH(NUM_CH)
) u_rr_arbiter (
    .ch_pending    (ch_pending),
    .arb_next_ch   (arb_next_ch),
    .pending_valid (pending_valid),
    .pending_ch_sel(pending_ch_sel)
);

always @* begin
    case (pending_ch_sel)
        3'd0: pending_desc_head = desc_head_flat[1:0];
        3'd1: pending_desc_head = desc_head_flat[3:2];
        3'd2: pending_desc_head = desc_head_flat[5:4];
        3'd3: pending_desc_head = desc_head_flat[7:6];
        3'd4: pending_desc_head = desc_head_flat[9:8];
        3'd5: pending_desc_head = desc_head_flat[11:10];
        3'd6: pending_desc_head = desc_head_flat[13:12];
        3'd7: pending_desc_head = desc_head_flat[15:14];
        default: pending_desc_head = 2'd0;
    endcase
end

assign pending_is_desc_fetch =
    pending_valid &&
    ch_desc_mode[pending_ch_sel] &&
    ch_desc_need_fetch[pending_ch_sel];

assign pending_desc_fetch_valid =
    pending_is_desc_fetch &&
    (desc_fetch_len_bytes != {DATA_WIDTH{1'b0}});

assign desc_fetch_pop_valid =
    pending_desc_fetch_valid &&
    ((dma_state == DMA_ST_IDLE) ||
     ((dma_state == DMA_ST_B) &&
      m_axi_bvalid &&
      (m_axi_bresp == AXI_RESP_OKAY) &&
      !(dma_buf_bytes > dma_write_bytes)));

assign desc_fetch_index = {pending_ch_sel, pending_desc_head};

assign pending_next_ch = (pending_ch_sel == 3'd7) ? 3'd0 : (pending_ch_sel + 3'd1);

endmodule

`default_nettype wire
