//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_top.v
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : Top-level RTL integration for the SAMRAM DMA benchmark block.
//               Instantiates APB decode/response logic, CSR control/readback,
//               descriptor storage/ring, scheduler, transfer engine, AXI output
//               adapter, alignment helper, and interrupt/error handling.
//
// Interfaces  : APB control interface; AXI4 master read/write interface;
//               per-channel done IRQ and fatal IRQ outputs.
// Reset       : rst_n, active-low reset
// Clock       : clk
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

`include "samram_dma_defs.vh"

module samram_dma_top #(
    parameter NUM_CH       = 8,
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter STRB_WIDTH   = (DATA_WIDTH/8),
    parameter AXI_ID_WIDTH = 4
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // APB control interface
    input  wire [ADDR_WIDTH-1:0]        s_apb_paddr,
    input  wire                         s_apb_psel,
    input  wire                         s_apb_penable,
    input  wire                         s_apb_pwrite,
    input  wire [DATA_WIDTH-1:0]        s_apb_pwdata,
    input  wire [STRB_WIDTH-1:0]        s_apb_pstrb,
    output wire [DATA_WIDTH-1:0]        s_apb_prdata,
    output wire                         s_apb_pready,
    output wire                         s_apb_pslverr,

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
    input  wire                         m_axi_awready,

    // AXI master write data channel
    output wire [DATA_WIDTH-1:0]        m_axi_wdata,
    output wire [STRB_WIDTH-1:0]        m_axi_wstrb,
    output wire                         m_axi_wlast,
    output wire                         m_axi_wvalid,
    input  wire                         m_axi_wready,

    // AXI master write response channel
    input  wire [AXI_ID_WIDTH-1:0]      m_axi_bid,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,
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
    input  wire                         m_axi_arready,

    // AXI master read data channel
    input  wire [AXI_ID_WIDTH-1:0]      m_axi_rid,
    input  wire [DATA_WIDTH-1:0]        m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    output wire                         m_axi_rready,

    // Interrupts
    output wire [NUM_CH-1:0]            irq_done,
    output wire                         fatal_irq
);

// -----------------------------------------------------------------------------
// Top-level local constants used only for inter-block glue.
// Full register/descriptor/interrupt encodings are documented in
// include/samram_dma_defs.vh and implemented inside the leaf modules.
// -----------------------------------------------------------------------------
localparam integer DESC_SLOTS_PER_CH = 4;
localparam [2:0] DESC_RING_DEPTH     = 3'd4;

localparam STATUS_BUSY_BIT = `SAMRAM_DMA_STATUS_BUSY_BIT;
localparam STATUS_DONE_BIT = `SAMRAM_DMA_STATUS_DONE_BIT;
localparam STATUS_ERR_BIT  = `SAMRAM_DMA_STATUS_ERR_BIT;

localparam [2:0] DMA_ST_B      = 3'd5;
localparam [1:0] AXI_RESP_OKAY = 2'b00;

// -----------------------------------------------------------------------------
// APB address decode
// -----------------------------------------------------------------------------
wire       apb_access;
wire       apb_write;

wire       apb_csr_region;
wire [2:0] apb_ch;
wire [2:0] apb_reg;
wire       apb_reg_valid;

wire       apb_desc_region;
wire [2:0] desc_apb_ch;
wire [1:0] desc_apb_slot;
wire [1:0] desc_apb_word;
wire [4:0] desc_apb_index;
wire       desc_apb_valid;

wire       apb_int_region;
wire [2:0] int_apb_reg;
wire       int_apb_valid;
wire       apb_any_valid;

samram_dma_apb_decode #(
    .ADDR_WIDTH(ADDR_WIDTH)
) u_apb_decode (
    .paddr           (s_apb_paddr),
    .psel            (s_apb_psel),
    .penable         (s_apb_penable),
    .pwrite          (s_apb_pwrite),
    .apb_access      (apb_access),
    .apb_write       (apb_write),
    .apb_csr_region  (apb_csr_region),
    .apb_ch          (apb_ch),
    .apb_reg         (apb_reg),
    .apb_reg_valid   (apb_reg_valid),
    .apb_desc_region (apb_desc_region),
    .desc_apb_ch     (desc_apb_ch),
    .desc_apb_slot   (desc_apb_slot),
    .desc_apb_word   (desc_apb_word),
    .desc_apb_index  (desc_apb_index),
    .desc_apb_valid  (desc_apb_valid),
    .apb_int_region  (apb_int_region),
    .int_apb_reg     (int_apb_reg),
    .int_apb_valid   (int_apb_valid),
    .apb_any_valid   (apb_any_valid)
);

wire [DATA_WIDTH-1:0] ch_src_addr_reg  [0:NUM_CH-1];
wire [DATA_WIDTH-1:0] ch_dst_addr_reg  [0:NUM_CH-1];
wire [DATA_WIDTH-1:0] ch_len_bytes_reg [0:NUM_CH-1];
wire [DATA_WIDTH-1:0] ch_ctrl_reg      [0:NUM_CH-1];
wire [DATA_WIDTH-1:0] ch_status_reg    [0:NUM_CH-1];
wire [ADDR_WIDTH-1:0] ch_cur_src_addr_reg [0:NUM_CH-1];
wire [ADDR_WIDTH-1:0] ch_cur_dst_addr_reg [0:NUM_CH-1];
wire [DATA_WIDTH-1:0] ch_rem_len_reg      [0:NUM_CH-1];
wire [NUM_CH*DATA_WIDTH-1:0] ch_src_addr_flat;
wire [NUM_CH*DATA_WIDTH-1:0] ch_dst_addr_flat;
wire [NUM_CH*DATA_WIDTH-1:0] ch_len_bytes_flat;
wire [NUM_CH*DATA_WIDTH-1:0] ch_ctrl_flat;
wire [NUM_CH*DATA_WIDTH-1:0] ch_status_flat;
wire [NUM_CH*ADDR_WIDTH-1:0] ch_cur_src_addr_flat;
wire [NUM_CH*ADDR_WIDTH-1:0] ch_cur_dst_addr_flat;
wire [NUM_CH*DATA_WIDTH-1:0] ch_rem_len_flat;
wire [DATA_WIDTH-1:0]        csr_apb_prdata;

wire [DATA_WIDTH-1:0] desc_apb_prdata;
wire [DATA_WIDTH-1:0] desc_fetch_src_addr;
wire [DATA_WIDTH-1:0] desc_fetch_dst_addr;
wire [DATA_WIDTH-1:0] desc_fetch_len_bytes;

wire [1:0]           desc_head_reg         [0:NUM_CH-1];
wire [1:0]           desc_tail_reg         [0:NUM_CH-1];
wire [2:0]           desc_count_reg        [0:NUM_CH-1];
wire [NUM_CH*2-1:0]  desc_head_flat;
wire [NUM_CH*2-1:0]  desc_tail_flat;
wire [NUM_CH*3-1:0]  desc_count_flat;
wire                 desc_doorbell_req_comb;
wire                 desc_doorbell_full_comb;
wire                 desc_doorbell_fire_comb;
wire                 pending_desc_fetch_valid_comb;
wire                 desc_fetch_pop_valid_comb;

wire [NUM_CH-1:0]    irq_enable_reg;
wire                 fiq_enable_reg;
wire [NUM_CH-1:0]    int_error_status_comb;
wire                 int_claim_valid;
wire                 int_claim_is_error;
wire [2:0]           int_claim_ch;
wire [NUM_CH-1:0]    irq_done_reg;
wire [NUM_CH-1:0]    ch_error_status_vec;
wire [NUM_CH-1:0]    ch_done_status_vec;
wire [NUM_CH-1:0]    irq_done_set_mask_comb;
wire [NUM_CH-1:0]    irq_done_clear_mask_comb;
wire [DATA_WIDTH-1:0] int_apb_prdata;

wire [2:0]            csr_write_ch;
wire                  csr_src_write_valid;
wire                  csr_dst_write_valid;
wire                  csr_len_write_valid;
wire                  csr_ctrl_write_valid;
wire [DATA_WIDTH-1:0] csr_src_next;
wire [DATA_WIDTH-1:0] csr_dst_next;
wire [DATA_WIDTH-1:0] csr_len_next;
wire [DATA_WIDTH-1:0] csr_ctrl_next;
wire                  csr_ctrl_clear_done;
wire                  csr_ctrl_clear_error;
wire                  csr_ctrl_desc_doorbell;
wire                  csr_ctrl_start;
wire                  desc_doorbell_full_error;
wire                  desc_doorbell_first_accept;
wire                  desc_doorbell_requeue_accept;
wire                  csr_start_duplicate_error;
wire                  csr_start_accept;
wire                  csr_start_zero_len_error;
wire [NUM_CH-1:0]     int_clear_done_mask;
wire [NUM_CH-1:0]     int_clear_error_mask;
wire                  pending_valid;
wire [2:0]            pending_ch_sel;
wire [2:0]            pending_next_ch_sel;

wire [2:0]            dma_state_reg;
wire                  dma_active_reg;
wire [2:0]            dma_ch_reg;
wire [ADDR_WIDTH-1:0] dma_src_addr_reg;
wire [ADDR_WIDTH-1:0] dma_dst_addr_reg;
wire [DATA_WIDTH-1:0] dma_len_left_reg;
wire [DATA_WIDTH-1:0] dma_rdata_reg;
wire [DATA_WIDTH-1:0] dma_buf_bytes_reg;
wire [DATA_WIDTH-1:0] dma_src_read_bytes_reg;
wire [NUM_CH-1:0]     ch_pending_reg;
wire [NUM_CH-1:0]     ch_desc_mode_reg;
wire [NUM_CH-1:0]     ch_desc_need_fetch_reg;
wire [2:0]            arb_next_ch_reg;

genvar desc_ring_g;
generate
    for (desc_ring_g = 0; desc_ring_g < NUM_CH; desc_ring_g = desc_ring_g + 1) begin : gen_desc_ring_status
        assign desc_head_reg[desc_ring_g]  = desc_head_flat[(desc_ring_g*2) +: 2];
        assign desc_tail_reg[desc_ring_g]  = desc_tail_flat[(desc_ring_g*2) +: 2];
        assign desc_count_reg[desc_ring_g] = desc_count_flat[(desc_ring_g*3) +: 3];

        assign ch_src_addr_reg[desc_ring_g]  = ch_src_addr_flat[(desc_ring_g*DATA_WIDTH) +: DATA_WIDTH];
        assign ch_dst_addr_reg[desc_ring_g]  = ch_dst_addr_flat[(desc_ring_g*DATA_WIDTH) +: DATA_WIDTH];
        assign ch_len_bytes_reg[desc_ring_g] = ch_len_bytes_flat[(desc_ring_g*DATA_WIDTH) +: DATA_WIDTH];
        assign ch_ctrl_reg[desc_ring_g]      = ch_ctrl_flat[(desc_ring_g*DATA_WIDTH) +: DATA_WIDTH];
        assign ch_status_reg[desc_ring_g]    = ch_status_flat[(desc_ring_g*DATA_WIDTH) +: DATA_WIDTH];
        assign ch_cur_src_addr_reg[desc_ring_g] = ch_cur_src_addr_flat[(desc_ring_g*ADDR_WIDTH) +: ADDR_WIDTH];
        assign ch_cur_dst_addr_reg[desc_ring_g] = ch_cur_dst_addr_flat[(desc_ring_g*ADDR_WIDTH) +: ADDR_WIDTH];
        assign ch_rem_len_reg[desc_ring_g]      = ch_rem_len_flat[(desc_ring_g*DATA_WIDTH) +: DATA_WIDTH];
    end
endgenerate

wire [ADDR_WIDTH-1:0] dma_araddr_comb;
wire [DATA_WIDTH-1:0] dma_write_bytes_comb;
wire [DATA_WIDTH-1:0] dma_src_read_bytes_comb;
wire [STRB_WIDTH-1:0] dma_wstrb_comb;
wire [DATA_WIDTH-1:0] dma_wdata_comb;

genvar irq_status_g;
generate
    for (irq_status_g = 0; irq_status_g < NUM_CH; irq_status_g = irq_status_g + 1) begin : gen_irq_error_status
        assign ch_error_status_vec[irq_status_g] = ch_status_reg[irq_status_g][STATUS_ERR_BIT];
        assign ch_done_status_vec[irq_status_g]  = ch_status_reg[irq_status_g][STATUS_DONE_BIT];
    end
endgenerate

assign irq_done_set_mask_comb =
    ((dma_state_reg == DMA_ST_B) &&
     m_axi_bvalid &&
     (m_axi_bresp == AXI_RESP_OKAY) &&
     (dma_len_left_reg <= dma_write_bytes_comb))
        ? ({{(NUM_CH-1){1'b0}}, 1'b1} << dma_ch_reg)
        : {NUM_CH{1'b0}};

samram_dma_csr_write_ctrl #(
    .NUM_CH(NUM_CH),
    .DATA_WIDTH(DATA_WIDTH),
    .STRB_WIDTH(STRB_WIDTH),
    .DESC_RING_DEPTH(DESC_RING_DEPTH)
) u_csr_write_ctrl (
    .apb_write                    (apb_write),
    .apb_reg_valid                (apb_reg_valid),
    .apb_ch                       (apb_ch),
    .apb_reg                      (apb_reg),
    .apb_wdata                    (s_apb_pwdata),
    .apb_wstrb                    (s_apb_pstrb),
    .int_write_valid              (apb_write && int_apb_valid),
    .int_reg                      (int_apb_reg),
    .int_wdata                    (s_apb_pwdata),
    .ch_src_addr_cur              (ch_src_addr_reg[apb_ch]),
    .ch_dst_addr_cur              (ch_dst_addr_reg[apb_ch]),
    .ch_len_bytes_cur             (ch_len_bytes_reg[apb_ch]),
    .ch_busy_cur                  (ch_status_reg[apb_ch][STATUS_BUSY_BIT]),
    .ch_desc_mode_cur             (ch_desc_mode_reg[apb_ch]),
    .ch_pending_cur               (ch_pending_reg[apb_ch]),
    .dma_active                   (dma_active_reg),
    .desc_count_cur               (desc_count_reg[apb_ch]),
    .csr_write_ch                 (csr_write_ch),
    .csr_src_write_valid          (csr_src_write_valid),
    .csr_dst_write_valid          (csr_dst_write_valid),
    .csr_len_write_valid          (csr_len_write_valid),
    .csr_ctrl_write_valid         (csr_ctrl_write_valid),
    .csr_src_next                 (csr_src_next),
    .csr_dst_next                 (csr_dst_next),
    .csr_len_next                 (csr_len_next),
    .csr_ctrl_next                (csr_ctrl_next),
    .csr_ctrl_clear_done          (csr_ctrl_clear_done),
    .csr_ctrl_clear_error         (csr_ctrl_clear_error),
    .csr_ctrl_desc_doorbell       (csr_ctrl_desc_doorbell),
    .csr_ctrl_start               (csr_ctrl_start),
    .desc_doorbell_req            (desc_doorbell_req_comb),
    .desc_doorbell_full           (desc_doorbell_full_comb),
    .desc_doorbell_fire           (desc_doorbell_fire_comb),
    .desc_doorbell_full_error     (desc_doorbell_full_error),
    .desc_doorbell_first_accept   (desc_doorbell_first_accept),
    .desc_doorbell_requeue_accept (desc_doorbell_requeue_accept),
    .csr_start_duplicate_error    (csr_start_duplicate_error),
    .csr_start_accept             (csr_start_accept),
    .csr_start_zero_len_error     (csr_start_zero_len_error),
    .int_clear_done_mask          (int_clear_done_mask),
    .int_clear_error_mask         (int_clear_error_mask),
    .irq_done_clear_mask          (irq_done_clear_mask_comb)
);

samram_dma_irq_ctrl #(
    .NUM_CH(NUM_CH),
    .DATA_WIDTH(DATA_WIDTH),
    .STRB_WIDTH(STRB_WIDTH)
) u_irq_ctrl (
    .clk                 (clk),
    .rst_n               (rst_n),
    .int_write_valid     (apb_write && int_apb_valid),
    .int_reg             (int_apb_reg),
    .int_wdata           (s_apb_pwdata),
    .int_wstrb           (s_apb_pstrb),
    .done_set_mask       (irq_done_set_mask_comb),
    .done_clear_mask     (irq_done_clear_mask_comb),
    .done_status         (ch_done_status_vec),
    .error_status        (ch_error_status_vec),
    .int_prdata          (int_apb_prdata),
    .irq_done            (irq_done),
    .fatal_irq           (fatal_irq),
    .irq_done_reg        (irq_done_reg),
    .irq_enable_reg      (irq_enable_reg),
    .fiq_enable_reg      (fiq_enable_reg),
    .int_error_status_comb(int_error_status_comb),
    .int_claim_valid     (int_claim_valid),
    .int_claim_is_error  (int_claim_is_error),
    .int_claim_ch        (int_claim_ch)
);

samram_dma_desc_ring #(
    .NUM_CH(NUM_CH)
) u_desc_ring (
    .clk                 (clk),
    .rst_n               (rst_n),
    .doorbell_fire       (desc_doorbell_fire_comb),
    .doorbell_ch         (apb_ch),
    .fetch_pop_valid     (desc_fetch_pop_valid_comb),
    .fetch_pop_ch        (pending_ch_sel),
    .desc_head_flat      (desc_head_flat),
    .desc_tail_flat      (desc_tail_flat),
    .desc_count_flat     (desc_count_flat)
);

wire [4:0] desc_fetch_index;

samram_dma_scheduler #(
    .NUM_CH    (NUM_CH),
    .DATA_WIDTH(DATA_WIDTH)
) u_scheduler (
    .ch_pending              (ch_pending_reg),
    .ch_desc_mode            (ch_desc_mode_reg),
    .ch_desc_need_fetch      (ch_desc_need_fetch_reg),
    .desc_head_flat          (desc_head_flat),
    .arb_next_ch             (arb_next_ch_reg),
    .dma_state               (dma_state_reg),
    .m_axi_bvalid            (m_axi_bvalid),
    .m_axi_bresp             (m_axi_bresp),
    .dma_buf_bytes           (dma_buf_bytes_reg),
    .dma_write_bytes         (dma_write_bytes_comb),
    .desc_fetch_len_bytes    (desc_fetch_len_bytes),
    .pending_valid           (pending_valid),
    .pending_ch_sel          (pending_ch_sel),
    .pending_desc_fetch_valid(pending_desc_fetch_valid_comb),
    .desc_fetch_pop_valid    (desc_fetch_pop_valid_comb),
    .desc_fetch_index        (desc_fetch_index),
    .pending_next_ch         (pending_next_ch_sel)
);

samram_dma_desc_sram #(
    .NUM_CH           (NUM_CH),
    .DATA_WIDTH       (DATA_WIDTH),
    .STRB_WIDTH       (STRB_WIDTH),
    .DESC_SLOTS_PER_CH(DESC_SLOTS_PER_CH)
) u_desc_sram (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .apb_write             (apb_write),
    .desc_apb_valid        (desc_apb_valid),
    .desc_apb_index        (desc_apb_index),
    .desc_apb_word         (desc_apb_word),
    .desc_apb_wdata        (s_apb_pwdata),
    .desc_apb_wstrb        (s_apb_pstrb),
    .desc_apb_rdata        (desc_apb_prdata),
    .desc_fetch_index      (desc_fetch_index),
    .desc_fetch_src_addr   (desc_fetch_src_addr),
    .desc_fetch_dst_addr   (desc_fetch_dst_addr),
    .desc_fetch_len_bytes  (desc_fetch_len_bytes)
);


samram_dma_csr_read_mux #(
    .NUM_CH    (NUM_CH),
    .DATA_WIDTH(DATA_WIDTH)
) u_csr_read_mux (
    .apb_reg_valid     (apb_reg_valid),
    .apb_ch            (apb_ch),
    .apb_reg           (apb_reg),
    .ch_src_addr_flat  (ch_src_addr_flat),
    .ch_dst_addr_flat  (ch_dst_addr_flat),
    .ch_len_bytes_flat (ch_len_bytes_flat),
    .ch_ctrl_flat      (ch_ctrl_flat),
    .ch_status_flat    (ch_status_flat),
    .desc_head_flat    (desc_head_flat),
    .desc_tail_flat    (desc_tail_flat),
    .desc_count_flat   (desc_count_flat),
    .csr_prdata        (csr_apb_prdata)
);


// Byte-alignment helper logic lives in samram_dma_align.v.


samram_dma_align #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .STRB_WIDTH(STRB_WIDTH)
) u_align (
    .dma_src_addr   (dma_src_addr_reg),
    .dma_dst_addr   (dma_dst_addr_reg),
    .dma_len_left   (dma_len_left_reg),
    .dma_rdata      (dma_rdata_reg),
    .dma_buf_bytes  (dma_buf_bytes_reg),
    .araddr         (dma_araddr_comb),
    .src_read_bytes_o(dma_src_read_bytes_comb),
    .write_bytes    (dma_write_bytes_comb),
    .wstrb          (dma_wstrb_comb),
    .wdata          (dma_wdata_comb)
);

samram_dma_xfer_engine #(
    .NUM_CH    (NUM_CH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .STRB_WIDTH(STRB_WIDTH)
) u_xfer_engine (
    .clk                         (clk),
    .rst_n                       (rst_n),

    .csr_write_ch                (csr_write_ch),
    .csr_src_write_valid         (csr_src_write_valid),
    .csr_dst_write_valid         (csr_dst_write_valid),
    .csr_len_write_valid         (csr_len_write_valid),
    .csr_ctrl_write_valid        (csr_ctrl_write_valid),
    .csr_src_next                (csr_src_next),
    .csr_dst_next                (csr_dst_next),
    .csr_len_next                (csr_len_next),
    .csr_ctrl_next               (csr_ctrl_next),
    .csr_ctrl_clear_done         (csr_ctrl_clear_done),
    .csr_ctrl_clear_error        (csr_ctrl_clear_error),
    .csr_ctrl_desc_doorbell      (csr_ctrl_desc_doorbell),
    .csr_ctrl_start              (csr_ctrl_start),
    .desc_doorbell_full_error    (desc_doorbell_full_error),
    .desc_doorbell_first_accept  (desc_doorbell_first_accept),
    .desc_doorbell_requeue_accept(desc_doorbell_requeue_accept),
    .csr_start_duplicate_error   (csr_start_duplicate_error),
    .csr_start_accept            (csr_start_accept),
    .csr_start_zero_len_error    (csr_start_zero_len_error),
    .int_clear_done_mask         (int_clear_done_mask),
    .int_clear_error_mask        (int_clear_error_mask),

    .pending_valid               (pending_valid),
    .pending_ch_sel              (pending_ch_sel),
    .pending_next_ch_sel         (pending_next_ch_sel),
    .desc_fetch_src_addr         (desc_fetch_src_addr),
    .desc_fetch_dst_addr         (desc_fetch_dst_addr),
    .desc_fetch_len_bytes        (desc_fetch_len_bytes),
    .desc_count_flat             (desc_count_flat),

    .dma_write_bytes_comb        (dma_write_bytes_comb),
    .dma_src_read_bytes_comb     (dma_src_read_bytes_comb),

    .m_axi_arready               (m_axi_arready),
    .m_axi_rdata                 (m_axi_rdata),
    .m_axi_rresp                 (m_axi_rresp),
    .m_axi_rlast                 (m_axi_rlast),
    .m_axi_rvalid                (m_axi_rvalid),
    .m_axi_awready               (m_axi_awready),
    .m_axi_wready                (m_axi_wready),
    .m_axi_bresp                 (m_axi_bresp),
    .m_axi_bvalid                (m_axi_bvalid),

    .ch_src_addr_flat            (ch_src_addr_flat),
    .ch_dst_addr_flat            (ch_dst_addr_flat),
    .ch_len_bytes_flat           (ch_len_bytes_flat),
    .ch_ctrl_flat                (ch_ctrl_flat),
    .ch_status_flat              (ch_status_flat),
    .ch_cur_src_addr_flat        (ch_cur_src_addr_flat),
    .ch_cur_dst_addr_flat        (ch_cur_dst_addr_flat),
    .ch_rem_len_flat             (ch_rem_len_flat),
    .ch_pending_reg              (ch_pending_reg),
    .ch_desc_mode_reg            (ch_desc_mode_reg),
    .ch_desc_need_fetch_reg      (ch_desc_need_fetch_reg),
    .arb_next_ch_reg             (arb_next_ch_reg),
    .dma_state_reg               (dma_state_reg),
    .dma_active_reg              (dma_active_reg),
    .dma_ch_reg                  (dma_ch_reg),
    .dma_src_addr_reg            (dma_src_addr_reg),
    .dma_dst_addr_reg            (dma_dst_addr_reg),
    .dma_len_left_reg            (dma_len_left_reg),
    .dma_rdata_reg               (dma_rdata_reg),
    .dma_buf_bytes_reg           (dma_buf_bytes_reg),
    .dma_src_read_bytes_reg      (dma_src_read_bytes_reg)
);

samram_dma_apb_resp_mux #(
    .DATA_WIDTH(DATA_WIDTH)
) u_apb_resp_mux (
    .psel          (s_apb_psel),
    .apb_access    (apb_access),
    .apb_any_valid (apb_any_valid),
    .int_apb_valid (int_apb_valid),
    .desc_apb_valid(desc_apb_valid),
    .apb_reg_valid (apb_reg_valid),
    .int_prdata    (int_apb_prdata),
    .desc_prdata   (desc_apb_prdata),
    .csr_prdata    (csr_apb_prdata),
    .prdata        (s_apb_prdata),
    .pready        (s_apb_pready),
    .pslverr       (s_apb_pslverr)
);

samram_dma_axi_master_out #(
    .ADDR_WIDTH  (ADDR_WIDTH),
    .DATA_WIDTH  (DATA_WIDTH),
    .STRB_WIDTH  (STRB_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH)
) u_axi_master_out (
    .dma_state    (dma_state_reg),
    .dma_dst_addr (dma_dst_addr_reg),
    .dma_araddr   (dma_araddr_comb),
    .dma_wdata    (dma_wdata_comb),
    .dma_wstrb    (dma_wstrb_comb),

    .m_axi_awid   (m_axi_awid),
    .m_axi_awaddr (m_axi_awaddr),
    .m_axi_awlen  (m_axi_awlen),
    .m_axi_awsize (m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awlock (m_axi_awlock),
    .m_axi_awcache(m_axi_awcache),
    .m_axi_awprot (m_axi_awprot),
    .m_axi_awqos  (m_axi_awqos),
    .m_axi_awvalid(m_axi_awvalid),

    .m_axi_wdata  (m_axi_wdata),
    .m_axi_wstrb  (m_axi_wstrb),
    .m_axi_wlast  (m_axi_wlast),
    .m_axi_wvalid (m_axi_wvalid),

    .m_axi_bready (m_axi_bready),

    .m_axi_arid   (m_axi_arid),
    .m_axi_araddr (m_axi_araddr),
    .m_axi_arlen  (m_axi_arlen),
    .m_axi_arsize (m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arlock (m_axi_arlock),
    .m_axi_arcache(m_axi_arcache),
    .m_axi_arprot (m_axi_arprot),
    .m_axi_arqos  (m_axi_arqos),
    .m_axi_arvalid(m_axi_arvalid),

    .m_axi_rready (m_axi_rready)
);

endmodule

`default_nettype wire
