//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_apb_resp_mux.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : APB response mux for CSR, descriptor SRAM, and interrupt read
//               paths, including read data, ready, and slave-error generation.
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

module samram_dma_apb_resp_mux #(
    parameter DATA_WIDTH = 32
)(
    input  wire                  psel,
    input  wire                  apb_access,
    input  wire                  apb_any_valid,

    input  wire                  int_apb_valid,
    input  wire                  desc_apb_valid,
    input  wire                  apb_reg_valid,

    input  wire [DATA_WIDTH-1:0] int_prdata,
    input  wire [DATA_WIDTH-1:0] desc_prdata,
    input  wire [DATA_WIDTH-1:0] csr_prdata,

    output reg  [DATA_WIDTH-1:0] prdata,
    output wire                  pready,
    output wire                  pslverr
);

always @* begin
    prdata = {DATA_WIDTH{1'b0}};

    if (psel) begin
        if (int_apb_valid) begin
            prdata = int_prdata;
        end else if (desc_apb_valid) begin
            prdata = desc_prdata;
        end else if (apb_reg_valid) begin
            prdata = csr_prdata;
        end
    end
end

assign pready  = 1'b1;
assign pslverr = apb_access && !apb_any_valid;

endmodule

`default_nettype wire
