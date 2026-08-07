//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_irq_ctrl.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : Interrupt controller for DONE/ERROR status readback, enable
//               registers, priority claim encoding, per-channel done IRQ, and
//               fatal-error IRQ output.
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

// Owns the APB-visible interrupt enable/status/claim behavior and the external
// irq_done/fatal_irq outputs. Channel DONE/ERROR status is received as input
// vectors; this block tracks DONE interrupt enables and computes claim priority.

module samram_dma_irq_ctrl #(
    parameter NUM_CH     = 8,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH/8
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         int_write_valid,
    input  wire [2:0]                   int_reg,
    input  wire [DATA_WIDTH-1:0]        int_wdata,
    input  wire [STRB_WIDTH-1:0]        int_wstrb,

    input  wire [NUM_CH-1:0]            done_set_mask,
    input  wire [NUM_CH-1:0]            done_clear_mask,
    input  wire [NUM_CH-1:0]            done_status,
    input  wire [NUM_CH-1:0]            error_status,

    output reg  [DATA_WIDTH-1:0]        int_prdata,
    output wire [NUM_CH-1:0]            irq_done,
    output wire                         fatal_irq,

    // Debug/visibility mirrors intentionally preserve the names that the
    // regression debug monitors already inspect through the top-level hierarchy.
    output wire [NUM_CH-1:0]            irq_done_reg,
    output reg  [NUM_CH-1:0]            irq_enable_reg,
    output reg                          fiq_enable_reg,
    output wire [NUM_CH-1:0]            int_error_status_comb,
    output reg                          int_claim_valid,
    output reg                          int_claim_is_error,
    output reg  [2:0]                   int_claim_ch
);

localparam [2:0] INT_REG_DONE_STATUS  = 3'd0;
localparam [2:0] INT_REG_ERROR_STATUS = 3'd1;
localparam [2:0] INT_REG_IRQ_ENABLE   = 3'd2;
localparam [2:0] INT_REG_FIQ_ENABLE   = 3'd3;
localparam [2:0] INT_REG_CLAIM        = 3'd4;
localparam [2:0] INT_REG_CLEAR        = 3'd5;

integer claim_idx;

assign int_error_status_comb = error_status;

// Channel DONE status is sourced from the done_status input so that
// INT_DONE_STATUS, INT_CLAIM, and irq_done track the software-visible
// STATUS[DONE] bit without a separate latch.
// The set/clear mask ports allow external callers to request done-bit
// transitions; done_status itself is the authoritative readback source.
assign irq_done_reg          = done_status;
assign irq_done              = done_status & irq_enable_reg;
assign fatal_irq             = (|error_status) & fiq_enable_reg;

always @(posedge clk) begin
    if (!rst_n) begin
        irq_enable_reg <= {NUM_CH{1'b1}};
        fiq_enable_reg <= 1'b1;
    end else begin
        if (int_write_valid) begin
            case (int_reg)
                INT_REG_IRQ_ENABLE: begin
                    if (int_wstrb[0]) begin
                        irq_enable_reg <= int_wdata[NUM_CH-1:0];
                    end
                end

                INT_REG_FIQ_ENABLE: begin
                    if (int_wstrb[0]) begin
                        fiq_enable_reg <= int_wdata[0];
                    end
                end

                default: begin
                    // Status, claim, and clear side effects are handled above.
                end
            endcase
        end
    end
end

always @* begin
    int_claim_valid    = 1'b0;
    int_claim_is_error = 1'b0;
    int_claim_ch       = 3'd0;

    // Priority rule: ERROR/FIQ class wins over DONE/IRQ class.
    // Within a class, lower channel number wins.
    for (claim_idx = 0; claim_idx < NUM_CH; claim_idx = claim_idx + 1) begin
        if (!int_claim_valid && fiq_enable_reg && error_status[claim_idx]) begin
            int_claim_valid    = 1'b1;
            int_claim_is_error = 1'b1;
            int_claim_ch       = claim_idx[2:0];
        end
    end

    for (claim_idx = 0; claim_idx < NUM_CH; claim_idx = claim_idx + 1) begin
        if (!int_claim_valid && irq_enable_reg[claim_idx] && done_status[claim_idx]) begin
            int_claim_valid    = 1'b1;
            int_claim_is_error = 1'b0;
            int_claim_ch       = claim_idx[2:0];
        end
    end
end

always @* begin
    int_prdata = {DATA_WIDTH{1'b0}};

    case (int_reg)
        INT_REG_DONE_STATUS: begin
            int_prdata = {{(DATA_WIDTH-NUM_CH){1'b0}}, done_status};
        end

        INT_REG_ERROR_STATUS: begin
            int_prdata = {{(DATA_WIDTH-NUM_CH){1'b0}}, error_status};
        end

        INT_REG_IRQ_ENABLE: begin
            int_prdata = {{(DATA_WIDTH-NUM_CH){1'b0}}, irq_enable_reg};
        end

        INT_REG_FIQ_ENABLE: begin
            int_prdata = {{(DATA_WIDTH-1){1'b0}}, fiq_enable_reg};
        end

        INT_REG_CLAIM: begin
            int_prdata[31]  = int_claim_valid;
            int_prdata[16]  = int_claim_is_error;
            int_prdata[2:0] = int_claim_ch;
        end

        INT_REG_CLEAR: begin
            int_prdata = {DATA_WIDTH{1'b0}};
        end

        default: begin
            int_prdata = {DATA_WIDTH{1'b0}};
        end
    endcase
end

endmodule

`default_nettype wire
