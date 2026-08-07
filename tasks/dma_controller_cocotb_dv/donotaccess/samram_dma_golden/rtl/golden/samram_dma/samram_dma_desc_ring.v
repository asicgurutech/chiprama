//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_desc_ring.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : Per-channel descriptor ring state block for HEAD, TAIL, COUNT,
//               software doorbell acceptance, and hardware descriptor-pop
//               updates.
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

// Owns the per-channel descriptor HEAD/TAIL/COUNT state.
//
// The top-level DMA control decides when a software descriptor doorbell is
// accepted and when a descriptor fetch is successful.  This block updates the
// visible ring state for those two events.
//
// The intentionally simple update ordering mirrors the original monolithic RTL:
//   1. successful descriptor fetch updates HEAD and decrements COUNT
//   2. accepted doorbell updates TAIL and increments COUNT
// If both target the same channel in the same cycle, the doorbell COUNT update
// is the later assignment, matching the old single always-block behavior.

module samram_dma_desc_ring #(
    parameter NUM_CH = 8
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    doorbell_fire,
    input  wire [2:0]              doorbell_ch,

    input  wire                    fetch_pop_valid,
    input  wire [2:0]              fetch_pop_ch,

    output wire [NUM_CH*2-1:0]     desc_head_flat,
    output wire [NUM_CH*2-1:0]     desc_tail_flat,
    output wire [NUM_CH*3-1:0]     desc_count_flat
);

reg [1:0] desc_head_reg  [0:NUM_CH-1];
reg [1:0] desc_tail_reg  [0:NUM_CH-1];
reg [2:0] desc_count_reg [0:NUM_CH-1];

integer i;
genvar g;

generate
    for (g = 0; g < NUM_CH; g = g + 1) begin : gen_flatten_ring
        assign desc_head_flat[(g*2) +: 2]  = desc_head_reg[g];
        assign desc_tail_flat[(g*2) +: 2]  = desc_tail_reg[g];
        assign desc_count_flat[(g*3) +: 3] = desc_count_reg[g];
    end
endgenerate

always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < NUM_CH; i = i + 1) begin
            desc_head_reg[i]  <= 2'd0;
            desc_tail_reg[i]  <= 2'd0;
            desc_count_reg[i] <= 3'd0;
        end
    end else begin
        if (fetch_pop_valid) begin
            desc_head_reg[fetch_pop_ch]  <= desc_head_reg[fetch_pop_ch] + 2'd1;
            desc_count_reg[fetch_pop_ch] <= desc_count_reg[fetch_pop_ch] - 3'd1;
        end

        if (doorbell_fire) begin
            desc_tail_reg[doorbell_ch]  <= desc_tail_reg[doorbell_ch] + 2'd1;
            desc_count_reg[doorbell_ch] <= desc_count_reg[doorbell_ch] + 3'd1;
        end
    end
end

endmodule

`default_nettype wire
