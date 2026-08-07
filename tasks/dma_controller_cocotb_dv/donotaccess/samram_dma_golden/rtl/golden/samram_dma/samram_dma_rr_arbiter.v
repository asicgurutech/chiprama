//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_rr_arbiter.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : Combinational round-robin pending-channel selector with wrap
//               behavior based on the next-channel arbitration pointer.
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

// Chooses the first pending channel starting at arb_next_ch and wrapping around.
// Combinational; pending-channel state is maintained in the caller.

module samram_dma_rr_arbiter #(
    parameter NUM_CH = 8
)(
    input  wire [NUM_CH-1:0] ch_pending,
    input  wire [2:0]        arb_next_ch,
    output wire              pending_valid,
    output reg  [2:0]        pending_ch_sel
);

localparam [3:0] NUM_CH_VALUE = NUM_CH;

integer offset_idx;
reg found;
reg [3:0] scan_ch;
reg [3:0] offset_idx_4;

assign pending_valid = |ch_pending;

always @* begin
    pending_ch_sel = 3'd0;
    found          = 1'b0;
    scan_ch        = 4'd0;
    offset_idx_4   = 4'd0;

    for (offset_idx = 0; offset_idx < NUM_CH; offset_idx = offset_idx + 1) begin
        offset_idx_4 = offset_idx[3:0];
        scan_ch      = {1'b0, arb_next_ch} + offset_idx_4;
        if (scan_ch >= NUM_CH_VALUE) begin
            scan_ch = scan_ch - NUM_CH_VALUE;
        end

        if (!found && ch_pending[scan_ch[2:0]]) begin
            pending_ch_sel = scan_ch[2:0];
            found          = 1'b1;
        end
    end
end

endmodule

`default_nettype wire
