//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_xfer_engine.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : DMA transfer engine and channel context/status bank for CSR
//               starts, descriptor-backed transfers, AXI handshakes, DONE/ERROR
//               handling, and descriptor push-back continuation.
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

module samram_dma_xfer_engine #(
    parameter NUM_CH     = 8,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8)
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Decoded CSR/control side effects
    input  wire [2:0]                   csr_write_ch,
    input  wire                         csr_src_write_valid,
    input  wire                         csr_dst_write_valid,
    input  wire                         csr_len_write_valid,
    input  wire                         csr_ctrl_write_valid,
    input  wire [DATA_WIDTH-1:0]        csr_src_next,
    input  wire [DATA_WIDTH-1:0]        csr_dst_next,
    input  wire [DATA_WIDTH-1:0]        csr_len_next,
    input  wire [DATA_WIDTH-1:0]        csr_ctrl_next,
    input  wire                         csr_ctrl_clear_done,
    input  wire                         csr_ctrl_clear_error,
    input  wire                         csr_ctrl_desc_doorbell,
    input  wire                         csr_ctrl_start,
    input  wire                         desc_doorbell_full_error,
    input  wire                         desc_doorbell_first_accept,
    input  wire                         desc_doorbell_requeue_accept,
    input  wire                         csr_start_duplicate_error,
    input  wire                         csr_start_accept,
    input  wire                         csr_start_zero_len_error,
    input  wire [NUM_CH-1:0]            int_clear_done_mask,
    input  wire [NUM_CH-1:0]            int_clear_error_mask,

    // Scheduler/service-start inputs
    input  wire                         pending_valid,
    input  wire [2:0]                   pending_ch_sel,
    input  wire [2:0]                   pending_next_ch_sel,
    input  wire [DATA_WIDTH-1:0]        desc_fetch_src_addr,
    input  wire [DATA_WIDTH-1:0]        desc_fetch_dst_addr,
    input  wire [DATA_WIDTH-1:0]        desc_fetch_len_bytes,
    input  wire [NUM_CH*3-1:0]          desc_count_flat,

    // Alignment datapath feedback
    input  wire [DATA_WIDTH-1:0]        dma_write_bytes_comb,
    input  wire [DATA_WIDTH-1:0]        dma_src_read_bytes_comb,

    // AXI response/handshake inputs
    input  wire                         m_axi_arready,
    input  wire [DATA_WIDTH-1:0]        m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    input  wire                         m_axi_awready,
    input  wire                         m_axi_wready,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,

    // Channel CSR/status state, exported as flat buses for top-level readback/debug
    output wire [NUM_CH*DATA_WIDTH-1:0] ch_src_addr_flat,
    output wire [NUM_CH*DATA_WIDTH-1:0] ch_dst_addr_flat,
    output wire [NUM_CH*DATA_WIDTH-1:0] ch_len_bytes_flat,
    output wire [NUM_CH*DATA_WIDTH-1:0] ch_ctrl_flat,
    output wire [NUM_CH*DATA_WIDTH-1:0] ch_status_flat,
    output wire [NUM_CH*ADDR_WIDTH-1:0] ch_cur_src_addr_flat,
    output wire [NUM_CH*ADDR_WIDTH-1:0] ch_cur_dst_addr_flat,
    output wire [NUM_CH*DATA_WIDTH-1:0] ch_rem_len_flat,

    // Scheduler-visible state
    output reg  [NUM_CH-1:0]            ch_pending_reg,
    output reg  [NUM_CH-1:0]            ch_desc_mode_reg,
    output reg  [NUM_CH-1:0]            ch_desc_need_fetch_reg,
    output reg  [2:0]                   arb_next_ch_reg,

    // Transfer-engine visible/debug state
    output reg  [2:0]                   dma_state_reg,
    output reg                          dma_active_reg,
    output reg  [2:0]                   dma_ch_reg,
    output reg  [ADDR_WIDTH-1:0]        dma_src_addr_reg,
    output reg  [ADDR_WIDTH-1:0]        dma_dst_addr_reg,
    output reg  [DATA_WIDTH-1:0]        dma_len_left_reg,
    output reg  [DATA_WIDTH-1:0]        dma_rdata_reg,
    output reg  [DATA_WIDTH-1:0]        dma_buf_bytes_reg,
    output reg  [DATA_WIDTH-1:0]        dma_src_read_bytes_reg
);

localparam STATUS_BUSY_BIT = 0;
localparam STATUS_DONE_BIT = 1;
localparam STATUS_ERR_BIT  = 2;

localparam [2:0] DMA_ST_IDLE = 3'd0;
localparam [2:0] DMA_ST_AR   = 3'd1;
localparam [2:0] DMA_ST_R    = 3'd2;
localparam [2:0] DMA_ST_AW   = 3'd3;
localparam [2:0] DMA_ST_W    = 3'd4;
localparam [2:0] DMA_ST_B    = 3'd5;

localparam [1:0] AXI_RESP_OKAY = 2'b00;

reg [DATA_WIDTH-1:0] ch_src_addr_reg  [0:NUM_CH-1];
reg [DATA_WIDTH-1:0] ch_dst_addr_reg  [0:NUM_CH-1];
reg [DATA_WIDTH-1:0] ch_len_bytes_reg [0:NUM_CH-1];
reg [DATA_WIDTH-1:0] ch_ctrl_reg      [0:NUM_CH-1];
reg [DATA_WIDTH-1:0] ch_status_reg    [0:NUM_CH-1];

reg [ADDR_WIDTH-1:0] ch_cur_src_addr_reg [0:NUM_CH-1];
reg [ADDR_WIDTH-1:0] ch_cur_dst_addr_reg [0:NUM_CH-1];
reg [DATA_WIDTH-1:0] ch_rem_len_reg      [0:NUM_CH-1];

wire [2:0] desc_count_reg [0:NUM_CH-1];

integer i;
genvar state_g;
generate
    for (state_g = 0; state_g < NUM_CH; state_g = state_g + 1) begin : gen_state_flatten
        assign desc_count_reg[state_g] = desc_count_flat[(state_g*3) +: 3];

        assign ch_src_addr_flat[(state_g*DATA_WIDTH) +: DATA_WIDTH]  = ch_src_addr_reg[state_g];
        assign ch_dst_addr_flat[(state_g*DATA_WIDTH) +: DATA_WIDTH]  = ch_dst_addr_reg[state_g];
        assign ch_len_bytes_flat[(state_g*DATA_WIDTH) +: DATA_WIDTH] = ch_len_bytes_reg[state_g];
        assign ch_ctrl_flat[(state_g*DATA_WIDTH) +: DATA_WIDTH]      = ch_ctrl_reg[state_g];
        assign ch_status_flat[(state_g*DATA_WIDTH) +: DATA_WIDTH]    = ch_status_reg[state_g];
        assign ch_cur_src_addr_flat[(state_g*ADDR_WIDTH) +: ADDR_WIDTH] = ch_cur_src_addr_reg[state_g];
        assign ch_cur_dst_addr_flat[(state_g*ADDR_WIDTH) +: ADDR_WIDTH] = ch_cur_dst_addr_reg[state_g];
        assign ch_rem_len_flat[(state_g*DATA_WIDTH) +: DATA_WIDTH]      = ch_rem_len_reg[state_g];
    end
endgenerate

function [DATA_WIDTH-1:0] addr_byte_offset;
    input [ADDR_WIDTH-1:0] addr;
    begin
        addr_byte_offset = {DATA_WIDTH{1'b0}};

        case (STRB_WIDTH)
            1:  addr_byte_offset = {DATA_WIDTH{1'b0}};
            2:  addr_byte_offset[0]   = addr[0];
            4:  addr_byte_offset[1:0] = addr[1:0];
            8:  addr_byte_offset[2:0] = addr[2:0];
            16: addr_byte_offset[3:0] = addr[3:0];
            32: addr_byte_offset[4:0] = addr[4:0];
            default: addr_byte_offset = {DATA_WIDTH{1'b0}};
        endcase
    end
endfunction

function [DATA_WIDTH-1:0] src_shift_rdata;
    input [DATA_WIDTH-1:0] data;
    input [ADDR_WIDTH-1:0] addr;
    integer shift_bits;
    begin
        shift_bits      = addr_byte_offset(addr) * 8;
        src_shift_rdata = data >> shift_bits;
    end
endfunction

always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < NUM_CH; i = i + 1) begin
            ch_src_addr_reg[i]  <= {DATA_WIDTH{1'b0}};
            ch_dst_addr_reg[i]  <= {DATA_WIDTH{1'b0}};
            ch_len_bytes_reg[i] <= {DATA_WIDTH{1'b0}};
            ch_ctrl_reg[i]      <= {DATA_WIDTH{1'b0}};
            ch_status_reg[i]    <= {DATA_WIDTH{1'b0}};
            ch_cur_src_addr_reg[i] <= {ADDR_WIDTH{1'b0}};
            ch_cur_dst_addr_reg[i] <= {ADDR_WIDTH{1'b0}};
            ch_rem_len_reg[i]      <= {DATA_WIDTH{1'b0}};
            ch_desc_mode_reg[i]    <= 1'b0;
            ch_desc_need_fetch_reg[i] <= 1'b0;
        end

        ch_pending_reg  <= {NUM_CH{1'b0}};
        arb_next_ch_reg <= 3'd0;

        dma_state_reg    <= DMA_ST_IDLE;
        dma_active_reg   <= 1'b0;
        dma_ch_reg       <= 3'd0;
        dma_src_addr_reg <= {ADDR_WIDTH{1'b0}};
        dma_dst_addr_reg <= {ADDR_WIDTH{1'b0}};
        dma_len_left_reg <= {DATA_WIDTH{1'b0}};
        dma_rdata_reg    <= {DATA_WIDTH{1'b0}};
        dma_buf_bytes_reg <= {DATA_WIDTH{1'b0}};
        dma_src_read_bytes_reg <= {DATA_WIDTH{1'b0}};

    end else begin
        // ---------------------------------------------------------------------
        // DMA single-channel, single-beat-per-transaction datapath skeleton
        // ---------------------------------------------------------------------
        case (dma_state_reg)
            DMA_ST_IDLE: begin
                if (pending_valid) begin
                    ch_pending_reg[pending_ch_sel] <= 1'b0;

                    if (ch_desc_mode_reg[pending_ch_sel] && ch_desc_need_fetch_reg[pending_ch_sel]) begin
                        // Descriptor-backed channel: sample descriptor only when the channel wins arbitration.
                        if (desc_fetch_len_bytes != {DATA_WIDTH{1'b0}}) begin

                            dma_active_reg    <= 1'b1;
                            dma_ch_reg        <= pending_ch_sel;
                            dma_src_addr_reg  <= desc_fetch_src_addr[ADDR_WIDTH-1:0];
                            dma_dst_addr_reg  <= desc_fetch_dst_addr[ADDR_WIDTH-1:0];
                            dma_len_left_reg  <= desc_fetch_len_bytes;
                            dma_state_reg     <= DMA_ST_AR;
                            arb_next_ch_reg   <= pending_next_ch_sel;

                            ch_cur_src_addr_reg[pending_ch_sel] <= desc_fetch_src_addr[ADDR_WIDTH-1:0];
                            ch_cur_dst_addr_reg[pending_ch_sel] <= desc_fetch_dst_addr[ADDR_WIDTH-1:0];
                            ch_rem_len_reg[pending_ch_sel]      <= desc_fetch_len_bytes;
                            ch_desc_need_fetch_reg[pending_ch_sel] <= 1'b0;

                        end else begin
                            ch_status_reg[pending_ch_sel] <= {{(DATA_WIDTH-3){1'b0}}, 3'b100}; // ERROR
                            ch_desc_mode_reg[pending_ch_sel] <= 1'b0;
                            ch_desc_need_fetch_reg[pending_ch_sel] <= 1'b0;
                            dma_active_reg <= 1'b0;
                            dma_state_reg  <= DMA_ST_IDLE;
                        end
                    end else begin
                        // CSR-backed channel or descriptor channel continuing an in-flight descriptor.
                        dma_active_reg    <= 1'b1;
                        dma_ch_reg        <= pending_ch_sel;
                        dma_src_addr_reg  <= ch_cur_src_addr_reg[pending_ch_sel];
                        dma_dst_addr_reg  <= ch_cur_dst_addr_reg[pending_ch_sel];
                        dma_len_left_reg  <= ch_rem_len_reg[pending_ch_sel];
                        dma_state_reg     <= DMA_ST_AR;
                        arb_next_ch_reg   <= pending_next_ch_sel;
                    end
                end
            end

            DMA_ST_AR: begin
                if (m_axi_arready) begin
                    dma_state_reg <= DMA_ST_R;
                end
            end

            DMA_ST_R: begin
                if (m_axi_rvalid) begin
                    if ((m_axi_rresp != AXI_RESP_OKAY) || !m_axi_rlast) begin
                        ch_status_reg[dma_ch_reg] <= {{(DATA_WIDTH-3){1'b0}}, 3'b100}; // ERROR
                        dma_active_reg            <= 1'b0;
                        dma_state_reg             <= DMA_ST_IDLE;
                    end else begin
                        dma_rdata_reg          <= src_shift_rdata(m_axi_rdata, dma_src_addr_reg);
                        dma_buf_bytes_reg      <= dma_src_read_bytes_comb;
                        dma_src_read_bytes_reg <= dma_src_read_bytes_comb;
                        dma_state_reg          <= DMA_ST_AW;
                    end
                end
            end

            DMA_ST_AW: begin
                if (m_axi_awready) begin
                    dma_state_reg <= DMA_ST_W;
                end
            end

            DMA_ST_W: begin
                if (m_axi_wready) begin
                    dma_state_reg <= DMA_ST_B;
                end
            end

            DMA_ST_B: begin
                if (m_axi_bvalid) begin
                    if (m_axi_bresp != AXI_RESP_OKAY) begin
                        ch_status_reg[dma_ch_reg] <= {{(DATA_WIDTH-3){1'b0}}, 3'b100}; // ERROR
                        dma_active_reg            <= 1'b0;
                        dma_buf_bytes_reg         <= {DATA_WIDTH{1'b0}};
                        dma_state_reg             <= DMA_ST_IDLE;
                    end else if (dma_buf_bytes_reg > dma_write_bytes_comb) begin
                        // Destination is unaligned and this source word does not fit
                        // into the remaining destination byte lanes.  Write the
                        // remaining buffered bytes before reading the next source word.
                        dma_rdata_reg     <= dma_rdata_reg >> (dma_write_bytes_comb * 8);
                        dma_buf_bytes_reg <= dma_buf_bytes_reg - dma_write_bytes_comb;
                        dma_dst_addr_reg  <= dma_dst_addr_reg + dma_write_bytes_comb[ADDR_WIDTH-1:0];
                        dma_len_left_reg  <= dma_len_left_reg - dma_write_bytes_comb;
                        dma_state_reg     <= DMA_ST_AW;
                    end else if (dma_len_left_reg <= dma_write_bytes_comb) begin
                        dma_buf_bytes_reg <= {DATA_WIDTH{1'b0}};

                        if (ch_desc_mode_reg[dma_ch_reg] && (desc_count_reg[dma_ch_reg] != 3'd0)) begin
                            // Descriptor-backed channel has another descriptor available.
                            // Remove current descriptor from active service and push channel to back of queue.
                            ch_desc_need_fetch_reg[dma_ch_reg] <= 1'b1;
                            ch_pending_reg[dma_ch_reg]         <= 1'b1;
                            ch_status_reg[dma_ch_reg]          <= {{(DATA_WIDTH-3){1'b0}}, 3'b001}; // BUSY

                            if (pending_valid) begin
                                ch_pending_reg[pending_ch_sel] <= 1'b0;

                                dma_active_reg    <= 1'b1;
                                dma_ch_reg        <= pending_ch_sel;
                                dma_buf_bytes_reg <= {DATA_WIDTH{1'b0}};
                                if (ch_desc_mode_reg[pending_ch_sel] && ch_desc_need_fetch_reg[pending_ch_sel]) begin
                                    if (desc_fetch_len_bytes != {DATA_WIDTH{1'b0}}) begin
                                        dma_src_addr_reg  <= desc_fetch_src_addr[ADDR_WIDTH-1:0];
                                        dma_dst_addr_reg  <= desc_fetch_dst_addr[ADDR_WIDTH-1:0];
                                        dma_len_left_reg  <= desc_fetch_len_bytes;
                                        ch_cur_src_addr_reg[pending_ch_sel] <= desc_fetch_src_addr[ADDR_WIDTH-1:0];
                                        ch_cur_dst_addr_reg[pending_ch_sel] <= desc_fetch_dst_addr[ADDR_WIDTH-1:0];
                                        ch_rem_len_reg[pending_ch_sel]      <= desc_fetch_len_bytes;
                                        ch_desc_need_fetch_reg[pending_ch_sel] <= 1'b0;
                                        dma_state_reg     <= DMA_ST_AR;
                                    end else begin
                                        ch_status_reg[pending_ch_sel] <= {{(DATA_WIDTH-3){1'b0}}, 3'b100}; // ERROR
                                        ch_desc_mode_reg[pending_ch_sel] <= 1'b0;
                                        ch_desc_need_fetch_reg[pending_ch_sel] <= 1'b0;
                                        dma_active_reg <= 1'b0;
                                        dma_state_reg <= DMA_ST_IDLE;
                                    end
                                end else begin
                                    dma_src_addr_reg  <= ch_cur_src_addr_reg[pending_ch_sel];
                                    dma_dst_addr_reg  <= ch_cur_dst_addr_reg[pending_ch_sel];
                                    dma_len_left_reg  <= ch_rem_len_reg[pending_ch_sel];
                                    dma_state_reg     <= DMA_ST_AR;
                                end
                                arb_next_ch_reg   <= pending_next_ch_sel;
                            end else begin
                                dma_active_reg <= 1'b0;
                                dma_state_reg  <= DMA_ST_IDLE;
                            end
                        end else begin
                            ch_status_reg[dma_ch_reg] <= {{(DATA_WIDTH-3){1'b0}}, 3'b010}; // DONE
                            ch_desc_mode_reg[dma_ch_reg] <= 1'b0;
                            ch_desc_need_fetch_reg[dma_ch_reg] <= 1'b0;

                            if (pending_valid) begin
                                ch_pending_reg[pending_ch_sel] <= 1'b0;

                                dma_active_reg    <= 1'b1;
                                dma_ch_reg        <= pending_ch_sel;
                                dma_buf_bytes_reg <= {DATA_WIDTH{1'b0}};
                                if (ch_desc_mode_reg[pending_ch_sel] && ch_desc_need_fetch_reg[pending_ch_sel]) begin
                                    if (desc_fetch_len_bytes != {DATA_WIDTH{1'b0}}) begin
                                        dma_src_addr_reg  <= desc_fetch_src_addr[ADDR_WIDTH-1:0];
                                        dma_dst_addr_reg  <= desc_fetch_dst_addr[ADDR_WIDTH-1:0];
                                        dma_len_left_reg  <= desc_fetch_len_bytes;
                                        ch_cur_src_addr_reg[pending_ch_sel] <= desc_fetch_src_addr[ADDR_WIDTH-1:0];
                                        ch_cur_dst_addr_reg[pending_ch_sel] <= desc_fetch_dst_addr[ADDR_WIDTH-1:0];
                                        ch_rem_len_reg[pending_ch_sel]      <= desc_fetch_len_bytes;
                                        ch_desc_need_fetch_reg[pending_ch_sel] <= 1'b0;
                                        dma_state_reg     <= DMA_ST_AR;
                                    end else begin
                                        ch_status_reg[pending_ch_sel] <= {{(DATA_WIDTH-3){1'b0}}, 3'b100}; // ERROR
                                        ch_desc_mode_reg[pending_ch_sel] <= 1'b0;
                                        ch_desc_need_fetch_reg[pending_ch_sel] <= 1'b0;
                                        dma_active_reg <= 1'b0;
                                        dma_state_reg <= DMA_ST_IDLE;
                                    end
                                end else begin
                                    dma_src_addr_reg  <= ch_cur_src_addr_reg[pending_ch_sel];
                                    dma_dst_addr_reg  <= ch_cur_dst_addr_reg[pending_ch_sel];
                                    dma_len_left_reg  <= ch_rem_len_reg[pending_ch_sel];
                                    dma_state_reg     <= DMA_ST_AR;
                                end
                                arb_next_ch_reg   <= pending_next_ch_sel;
                            end else begin
                                dma_active_reg <= 1'b0;
                                dma_state_reg  <= DMA_ST_IDLE;
                            end
                        end
                    end else begin
                        dma_buf_bytes_reg <= {DATA_WIDTH{1'b0}};

                        if (pending_valid) begin
                            ch_cur_src_addr_reg[dma_ch_reg] <= dma_src_addr_reg + dma_src_read_bytes_reg[ADDR_WIDTH-1:0];
                            ch_cur_dst_addr_reg[dma_ch_reg] <= dma_dst_addr_reg + dma_write_bytes_comb[ADDR_WIDTH-1:0];
                            ch_rem_len_reg[dma_ch_reg]      <= dma_len_left_reg - dma_write_bytes_comb;
                            ch_pending_reg[dma_ch_reg]      <= 1'b1;

                            ch_pending_reg[pending_ch_sel] <= 1'b0;

                            dma_ch_reg        <= pending_ch_sel;
                            if (ch_desc_mode_reg[pending_ch_sel] && ch_desc_need_fetch_reg[pending_ch_sel]) begin
                                if (desc_fetch_len_bytes != {DATA_WIDTH{1'b0}}) begin
                                    dma_src_addr_reg  <= desc_fetch_src_addr[ADDR_WIDTH-1:0];
                                    dma_dst_addr_reg  <= desc_fetch_dst_addr[ADDR_WIDTH-1:0];
                                    dma_len_left_reg  <= desc_fetch_len_bytes;
                                    ch_cur_src_addr_reg[pending_ch_sel] <= desc_fetch_src_addr[ADDR_WIDTH-1:0];
                                    ch_cur_dst_addr_reg[pending_ch_sel] <= desc_fetch_dst_addr[ADDR_WIDTH-1:0];
                                    ch_rem_len_reg[pending_ch_sel]      <= desc_fetch_len_bytes;
                                    ch_desc_need_fetch_reg[pending_ch_sel] <= 1'b0;
                                    dma_state_reg     <= DMA_ST_AR;
                                end else begin
                                    ch_status_reg[pending_ch_sel] <= {{(DATA_WIDTH-3){1'b0}}, 3'b100}; // ERROR
                                    ch_desc_mode_reg[pending_ch_sel] <= 1'b0;
                                    ch_desc_need_fetch_reg[pending_ch_sel] <= 1'b0;
                                    dma_state_reg <= DMA_ST_IDLE;
                                end
                            end else begin
                                dma_src_addr_reg  <= ch_cur_src_addr_reg[pending_ch_sel];
                                dma_dst_addr_reg  <= ch_cur_dst_addr_reg[pending_ch_sel];
                                dma_len_left_reg  <= ch_rem_len_reg[pending_ch_sel];
                                dma_state_reg     <= DMA_ST_AR;
                            end
                            arb_next_ch_reg   <= pending_next_ch_sel;
                        end else begin
                            dma_src_addr_reg <= dma_src_addr_reg + dma_src_read_bytes_reg[ADDR_WIDTH-1:0];
                            dma_dst_addr_reg <= dma_dst_addr_reg + dma_write_bytes_comb[ADDR_WIDTH-1:0];
                            dma_len_left_reg <= dma_len_left_reg - dma_write_bytes_comb;
                            dma_state_reg    <= DMA_ST_AR;
                        end
                    end
                end
            end

            default: begin
                dma_state_reg  <= DMA_ST_IDLE;
                dma_active_reg <= 1'b0;
            end
        endcase

        // ---------------------------------------------------------------------
        // APB CSR writes and software-visible status clears
        // ---------------------------------------------------------------------
        if (csr_src_write_valid) begin
            ch_src_addr_reg[csr_write_ch] <= csr_src_next;
        end

        if (csr_dst_write_valid) begin
            ch_dst_addr_reg[csr_write_ch] <= csr_dst_next;
        end

        if (csr_len_write_valid) begin
            ch_len_bytes_reg[csr_write_ch] <= csr_len_next;
        end

        if (csr_ctrl_write_valid) begin
            // CTRL is a command register. Command bits are write-only pulses.
            // Reads of CTRL return the stored ch_ctrl_reg value, which remains
            // zero for the command bits implemented so far.
            ch_ctrl_reg[csr_write_ch] <= csr_ctrl_next;

            if (csr_ctrl_clear_done) begin
                ch_status_reg[csr_write_ch][STATUS_DONE_BIT] <= 1'b0;
            end

            if (csr_ctrl_clear_error) begin
                ch_status_reg[csr_write_ch][STATUS_ERR_BIT] <= 1'b0;
            end

            if (csr_ctrl_desc_doorbell) begin
                if (desc_doorbell_full_error) begin
                    ch_status_reg[csr_write_ch] <= {{(DATA_WIDTH-3){1'b0}}, 3'b100}; // ERROR
                end else begin
                    // Descriptor doorbell makes the channel ready. The descriptor
                    // itself is sampled later, only when the channel wins arbitration.
                    if (desc_doorbell_first_accept) begin
                        ch_status_reg[csr_write_ch] <= {{(DATA_WIDTH-3){1'b0}}, 3'b001}; // BUSY
                        ch_desc_mode_reg[csr_write_ch] <= 1'b1;
                        ch_desc_need_fetch_reg[csr_write_ch] <= 1'b1;
                        ch_pending_reg[csr_write_ch] <= 1'b1;
                    end else if (desc_doorbell_requeue_accept) begin
                        ch_desc_need_fetch_reg[csr_write_ch] <= 1'b1;
                        ch_pending_reg[csr_write_ch] <= 1'b1;
                    end
                end
            end

            if (csr_ctrl_start) begin
                if (csr_start_duplicate_error) begin
                    // Duplicate START on an already busy or pending channel is an error.
                    ch_status_reg[csr_write_ch] <= {{(DATA_WIDTH-3){1'b0}}, 3'b100}; // ERROR
                end else if (csr_start_accept) begin
                    ch_status_reg[csr_write_ch] <= {{(DATA_WIDTH-3){1'b0}}, 3'b001}; // BUSY

                    ch_cur_src_addr_reg[csr_write_ch] <= ch_src_addr_reg[csr_write_ch][ADDR_WIDTH-1:0];
                    ch_cur_dst_addr_reg[csr_write_ch] <= ch_dst_addr_reg[csr_write_ch][ADDR_WIDTH-1:0];
                    ch_rem_len_reg[csr_write_ch]      <= ch_len_bytes_reg[csr_write_ch];

                    if (dma_active_reg) begin
                        // Another channel is active. Queue this channel for later.
                        ch_pending_reg[csr_write_ch] <= 1'b1;
                    end else begin
                        // DMA is idle. Start immediately.
                        dma_active_reg    <= 1'b1;
                        dma_ch_reg        <= csr_write_ch;
                        dma_src_addr_reg  <= ch_src_addr_reg[csr_write_ch][ADDR_WIDTH-1:0];
                        dma_dst_addr_reg  <= ch_dst_addr_reg[csr_write_ch][ADDR_WIDTH-1:0];
                        dma_len_left_reg  <= ch_len_bytes_reg[csr_write_ch];
                        dma_state_reg     <= DMA_ST_AR;
                        arb_next_ch_reg   <= (csr_write_ch == 3'd7) ? 3'd0 : csr_write_ch + 3'd1;
                    end
                end else if (csr_start_zero_len_error) begin
                    ch_status_reg[csr_write_ch] <= {{(DATA_WIDTH-3){1'b0}}, 3'b100}; // ERROR
                end
            end
        end

        if ((|int_clear_done_mask) || (|int_clear_error_mask)) begin
            for (i = 0; i < NUM_CH; i = i + 1) begin
                if (int_clear_done_mask[i]) begin
                    ch_status_reg[i][STATUS_DONE_BIT] <= 1'b0;
                end

                if (int_clear_error_mask[i]) begin
                    ch_status_reg[i][STATUS_ERR_BIT] <= 1'b0;
                end
            end
        end
    end
end

endmodule

`default_nettype wire
