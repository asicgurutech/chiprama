`resetall
`timescale 1ns/1ps
`default_nettype none

module samram_dma_regression_tb;

localparam NUM_CH       = 8;
localparam ADDR_WIDTH   = 32;
localparam DATA_WIDTH   = 32;
localparam STRB_WIDTH   = DATA_WIDTH/8;
localparam AXI_ID_WIDTH = 4;
localparam [2:0] EXP_AXI_SIZE = 3'd2;

reg clk = 1'b0;
reg rst_n = 1'b0;

always #5 clk = ~clk;

// APB
reg  [ADDR_WIDTH-1:0] s_apb_paddr;
reg                   s_apb_psel;
reg                   s_apb_penable;
reg                   s_apb_pwrite;
reg  [DATA_WIDTH-1:0] s_apb_pwdata;
reg  [STRB_WIDTH-1:0] s_apb_pstrb;
wire [DATA_WIDTH-1:0] s_apb_prdata;
wire                  s_apb_pready;
wire                  s_apb_pslverr;

// AXI wires
wire [AXI_ID_WIDTH-1:0] m_axi_awid;
wire [ADDR_WIDTH-1:0]   m_axi_awaddr;
wire [7:0]              m_axi_awlen;
wire [2:0]              m_axi_awsize;
wire [1:0]              m_axi_awburst;
wire                    m_axi_awlock;
wire [3:0]              m_axi_awcache;
wire [2:0]              m_axi_awprot;
wire [3:0]              m_axi_awqos;
wire                    m_axi_awvalid;
reg                     m_axi_awready = 1'b0;

wire [DATA_WIDTH-1:0]   m_axi_wdata;
wire [STRB_WIDTH-1:0]   m_axi_wstrb;
wire                    m_axi_wlast;
wire                    m_axi_wvalid;
reg                     m_axi_wready = 1'b0;

reg  [AXI_ID_WIDTH-1:0] m_axi_bid = {AXI_ID_WIDTH{1'b0}};
reg  [1:0]              m_axi_bresp = 2'b00;
reg                     m_axi_bvalid = 1'b0;
wire                    m_axi_bready;

wire [AXI_ID_WIDTH-1:0] m_axi_arid;
wire [ADDR_WIDTH-1:0]   m_axi_araddr;
wire [7:0]              m_axi_arlen;
wire [2:0]              m_axi_arsize;
wire [1:0]              m_axi_arburst;
wire                    m_axi_arlock;
wire [3:0]              m_axi_arcache;
wire [2:0]              m_axi_arprot;
wire [3:0]              m_axi_arqos;
wire                    m_axi_arvalid;
reg                     m_axi_arready = 1'b0;

reg  [AXI_ID_WIDTH-1:0] m_axi_rid = {AXI_ID_WIDTH{1'b0}};
reg  [DATA_WIDTH-1:0]   m_axi_rdata = {DATA_WIDTH{1'b0}};
reg  [1:0]              m_axi_rresp = 2'b00;
reg                     m_axi_rlast = 1'b0;
reg                     m_axi_rvalid = 1'b0;
wire                    m_axi_rready;

wire [NUM_CH-1:0]       irq_done;
wire                    fatal_irq;

samram_dma_top #(
    .NUM_CH(NUM_CH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .STRB_WIDTH(STRB_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH)
)
dut (
    .clk(clk),
    .rst_n(rst_n),

    .s_apb_paddr(s_apb_paddr),
    .s_apb_psel(s_apb_psel),
    .s_apb_penable(s_apb_penable),
    .s_apb_pwrite(s_apb_pwrite),
    .s_apb_pwdata(s_apb_pwdata),
    .s_apb_pstrb(s_apb_pstrb),
    .s_apb_prdata(s_apb_prdata),
    .s_apb_pready(s_apb_pready),
    .s_apb_pslverr(s_apb_pslverr),

    .m_axi_awid(m_axi_awid),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awlock(m_axi_awlock),
    .m_axi_awcache(m_axi_awcache),
    .m_axi_awprot(m_axi_awprot),
    .m_axi_awqos(m_axi_awqos),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),

    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),

    .m_axi_bid(m_axi_bid),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),

    .m_axi_arid(m_axi_arid),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arlock(m_axi_arlock),
    .m_axi_arcache(m_axi_arcache),
    .m_axi_arprot(m_axi_arprot),
    .m_axi_arqos(m_axi_arqos),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),

    .m_axi_rid(m_axi_rid),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),

    .irq_done(irq_done),
    .fatal_irq(fatal_irq)
);


// Optional targeted debug for interrupt-priority regressions.
// Enable with: vvp ../../build/samram_dma_regression_tb.vvp +DBG_INTR
// The monitor is active only while test_interrupt_status_priority is running,
// and it prints only when the sampled signature changes.
reg         dbg_intr_active;
reg [511:0] dbg_intr_sig;
reg [511:0] dbg_intr_prev_sig;

initial begin
    dbg_intr_active   = 1'b0;
    dbg_intr_prev_sig = {512{1'bx}};
end

always @* begin
    dbg_intr_sig = {
        s_apb_psel,
        s_apb_penable,
        s_apb_pwrite,
        s_apb_paddr,
        s_apb_pwdata,
        s_apb_prdata,
        s_apb_pslverr,
        irq_done,
        fatal_irq,
        dut.irq_done_reg,
        dut.irq_enable_reg,
        dut.fiq_enable_reg,
        dut.int_claim_valid,
        dut.int_claim_is_error,
        dut.int_claim_ch,
        dut.dma_state_reg,
        dut.dma_active_reg,
        dut.dma_ch_reg,
        dut.ch_pending_reg,
        dut.ch_desc_mode_reg,
        dut.ch_desc_need_fetch_reg,
        dut.ch_status_reg[0],
        dut.ch_status_reg[1],
        dut.ch_status_reg[2],
        dut.ch_status_reg[3],
        m_axi_arvalid,
        m_axi_arready,
        m_axi_araddr,
        m_axi_rvalid,
        m_axi_rready,
        m_axi_rresp,
        m_axi_rlast,
        m_axi_awvalid,
        m_axi_awready,
        m_axi_awaddr,
        m_axi_wvalid,
        m_axi_wready,
        m_axi_wdata,
        m_axi_wstrb,
        m_axi_bvalid,
        m_axi_bready,
        m_axi_bresp
    };
end

always @(posedge clk) begin
    if (dbg_intr_active && $test$plusargs("DBG_INTR")) begin
        if (dbg_intr_sig !== dbg_intr_prev_sig) begin
            $display("DBG_INTR t=%0t apb={sel=%0b en=%0b wr=%0b addr=%h wdata=%h rdata=%h err=%0b} irq={out=%02x raw=%02x en=%02x fiq_en=%0b fatal=%0b claim_v=%0b claim_err=%0b claim_ch=%0d} dma={state=%0d active=%0b ch=%0d pend=%02x desc=%02x need_fetch=%02x} st={ch0=%h ch1=%h ch2=%h ch3=%h} axi={ar_vr=%0b%0b araddr=%h r_vr=%0b%0b rresp=%0b rlast=%0b aw_vr=%0b%0b awaddr=%h w_vr=%0b%0b wdata=%h wstrb=%b b_vr=%0b%0b bresp=%0b}",
                $time,
                s_apb_psel,
                s_apb_penable,
                s_apb_pwrite,
                s_apb_paddr,
                s_apb_pwdata,
                s_apb_prdata,
                s_apb_pslverr,
                irq_done,
                dut.irq_done_reg,
                dut.irq_enable_reg,
                dut.fiq_enable_reg,
                fatal_irq,
                dut.int_claim_valid,
                dut.int_claim_is_error,
                dut.int_claim_ch,
                dut.dma_state_reg,
                dut.dma_active_reg,
                dut.dma_ch_reg,
                dut.ch_pending_reg,
                dut.ch_desc_mode_reg,
                dut.ch_desc_need_fetch_reg,
                dut.ch_status_reg[0],
                dut.ch_status_reg[1],
                dut.ch_status_reg[2],
                dut.ch_status_reg[3],
                m_axi_arvalid,
                m_axi_arready,
                m_axi_araddr,
                m_axi_rvalid,
                m_axi_rready,
                m_axi_rresp,
                m_axi_rlast,
                m_axi_awvalid,
                m_axi_awready,
                m_axi_awaddr,
                m_axi_wvalid,
                m_axi_wready,
                m_axi_wdata,
                m_axi_wstrb,
                m_axi_bvalid,
                m_axi_bready,
                m_axi_bresp
            );
            dbg_intr_prev_sig <= dbg_intr_sig;
        end
    end else begin
        dbg_intr_prev_sig <= {512{1'bx}};
    end
end

// Optional targeted debug for unaligned-source regressions.
// Enable with: vvp ../../build/samram_dma_regression_tb.vvp +DBG_SRC
// or for the combined unaligned test:
//   vvp ../../build/samram_dma_regression_tb.vvp +DBG_ALIGN
// The monitor is active only while the selected unaligned-source/alignment test is running,
// and it prints only when the sampled signature changes.
reg         dbg_src_active;
reg [1023:0] dbg_src_sig;
reg [1023:0] dbg_src_prev_sig;

initial begin
    dbg_src_active   = 1'b0;
    dbg_src_prev_sig = {1024{1'bx}};
end

always @* begin
    dbg_src_sig = {
        s_apb_psel,
        s_apb_penable,
        s_apb_pwrite,
        s_apb_paddr,
        s_apb_pwdata,
        s_apb_prdata,
        irq_done,
        fatal_irq,
        dut.dma_state_reg,
        dut.dma_active_reg,
        dut.dma_ch_reg,
        dut.dma_src_addr_reg,
        dut.dma_dst_addr_reg,
        dut.dma_len_left_reg,
        dut.dma_rdata_reg,
        dut.dma_buf_bytes_reg,
        dut.dma_src_read_bytes_reg,
        dut.dma_src_read_bytes_comb,
        dut.dma_write_bytes_comb,
        dut.dma_wstrb_comb,
        dut.dma_wdata_comb,
        dut.ch_pending_reg,
        dut.ch_status_reg[0],
        m_axi_arvalid,
        m_axi_arready,
        m_axi_araddr,
        m_axi_rvalid,
        m_axi_rready,
        m_axi_rdata,
        m_axi_rresp,
        m_axi_rlast,
        m_axi_awvalid,
        m_axi_awready,
        m_axi_awaddr,
        m_axi_wvalid,
        m_axi_wready,
        m_axi_wdata,
        m_axi_wstrb,
        m_axi_bvalid,
        m_axi_bready,
        m_axi_bresp
    };
end

always @(posedge clk) begin
    if (dbg_src_active && ($test$plusargs("DBG_SRC") || $test$plusargs("DBG_ALIGN"))) begin
        if (dbg_src_sig !== dbg_src_prev_sig) begin
            $display("DBG_ALIGN_SRC t=%0t apb={sel=%0b en=%0b wr=%0b addr=%h wdata=%h rdata=%h} irq={done=%02x fatal=%0b} dma={state=%0d active=%0b ch=%0d src=%h dst=%h len=%h rdata=%h buf=%h src_read_reg=%h src_read_comb=%h wr_bytes=%h wstrb_comb=%b wdata_comb=%h pend=%02x st0=%h} axi={ar_vr=%0b%0b araddr=%h r_vr=%0b%0b rdata=%h rresp=%0b rlast=%0b aw_vr=%0b%0b awaddr=%h w_vr=%0b%0b wdata=%h wstrb=%b b_vr=%0b%0b bresp=%0b}",
                $time,
                s_apb_psel,
                s_apb_penable,
                s_apb_pwrite,
                s_apb_paddr,
                s_apb_pwdata,
                s_apb_prdata,
                irq_done,
                fatal_irq,
                dut.dma_state_reg,
                dut.dma_active_reg,
                dut.dma_ch_reg,
                dut.dma_src_addr_reg,
                dut.dma_dst_addr_reg,
                dut.dma_len_left_reg,
                dut.dma_rdata_reg,
                dut.dma_buf_bytes_reg,
                dut.dma_src_read_bytes_reg,
                dut.dma_src_read_bytes_comb,
                dut.dma_write_bytes_comb,
                dut.dma_wstrb_comb,
                dut.dma_wdata_comb,
                dut.ch_pending_reg,
                dut.ch_status_reg[0],
                m_axi_arvalid,
                m_axi_arready,
                m_axi_araddr,
                m_axi_rvalid,
                m_axi_rready,
                m_axi_rdata,
                m_axi_rresp,
                m_axi_rlast,
                m_axi_awvalid,
                m_axi_awready,
                m_axi_awaddr,
                m_axi_wvalid,
                m_axi_wready,
                m_axi_wdata,
                m_axi_wstrb,
                m_axi_bvalid,
                m_axi_bready,
                m_axi_bresp
            );
            dbg_src_prev_sig <= dbg_src_sig;
        end
    end else begin
        dbg_src_prev_sig <= {1024{1'bx}};
    end
end


// Optional targeted debug for AXI backpressure regressions.
// Enable with: vvp ../../build/samram_dma_regression_tb.vvp +DBG_AXI
// The monitor is active only while test_axi_backpressure_stability is running,
// and it prints only when the sampled signature changes.
reg          dbg_axi_active;
reg [1023:0] dbg_axi_sig;
reg [1023:0] dbg_axi_prev_sig;

initial begin
    dbg_axi_active   = 1'b0;
    dbg_axi_prev_sig = {1024{1'bx}};
end

always @* begin
    dbg_axi_sig = {
        s_apb_psel,
        s_apb_penable,
        s_apb_pwrite,
        s_apb_paddr,
        s_apb_pwdata,
        s_apb_prdata,
        irq_done,
        fatal_irq,
        dut.dma_state_reg,
        dut.dma_active_reg,
        dut.dma_ch_reg,
        dut.dma_src_addr_reg,
        dut.dma_dst_addr_reg,
        dut.dma_len_left_reg,
        dut.dma_rdata_reg,
        dut.dma_buf_bytes_reg,
        dut.dma_src_read_bytes_reg,
        dut.dma_src_read_bytes_comb,
        dut.dma_write_bytes_comb,
        dut.dma_wstrb_comb,
        dut.dma_wdata_comb,
        dut.ch_pending_reg,
        dut.ch_status_reg[0],
        m_axi_arvalid,
        m_axi_arready,
        m_axi_araddr,
        m_axi_arlen,
        m_axi_arsize,
        m_axi_rvalid,
        m_axi_rready,
        m_axi_rdata,
        m_axi_rresp,
        m_axi_rlast,
        m_axi_awvalid,
        m_axi_awready,
        m_axi_awaddr,
        m_axi_awlen,
        m_axi_awsize,
        m_axi_wvalid,
        m_axi_wready,
        m_axi_wdata,
        m_axi_wstrb,
        m_axi_wlast,
        m_axi_bvalid,
        m_axi_bready,
        m_axi_bresp
    };
end

always @(posedge clk) begin
    if (dbg_axi_active && $test$plusargs("DBG_AXI")) begin
        if (dbg_axi_sig !== dbg_axi_prev_sig) begin
            $display("DBG_AXI t=%0t apb={sel=%0b en=%0b wr=%0b addr=%h wdata=%h rdata=%h} irq={done=%02x fatal=%0b} dma={state=%0d active=%0b ch=%0d src=%h dst=%h len=%h rdata=%h buf=%h src_read_reg=%h src_read_comb=%h wr_bytes=%h wstrb_comb=%b wdata_comb=%h pend=%02x st0=%h} axi={ar_vr=%0b%0b araddr=%h arlen=%0d arsize=%0d r_vr=%0b%0b rdata=%h rresp=%0b rlast=%0b aw_vr=%0b%0b awaddr=%h awlen=%0d awsize=%0d w_vr=%0b%0b wdata=%h wstrb=%b wlast=%0b b_vr=%0b%0b bresp=%0b}",
                $time,
                s_apb_psel,
                s_apb_penable,
                s_apb_pwrite,
                s_apb_paddr,
                s_apb_pwdata,
                s_apb_prdata,
                irq_done,
                fatal_irq,
                dut.dma_state_reg,
                dut.dma_active_reg,
                dut.dma_ch_reg,
                dut.dma_src_addr_reg,
                dut.dma_dst_addr_reg,
                dut.dma_len_left_reg,
                dut.dma_rdata_reg,
                dut.dma_buf_bytes_reg,
                dut.dma_src_read_bytes_reg,
                dut.dma_src_read_bytes_comb,
                dut.dma_write_bytes_comb,
                dut.dma_wstrb_comb,
                dut.dma_wdata_comb,
                dut.ch_pending_reg,
                dut.ch_status_reg[0],
                m_axi_arvalid,
                m_axi_arready,
                m_axi_araddr,
                m_axi_arlen,
                m_axi_arsize,
                m_axi_rvalid,
                m_axi_rready,
                m_axi_rdata,
                m_axi_rresp,
                m_axi_rlast,
                m_axi_awvalid,
                m_axi_awready,
                m_axi_awaddr,
                m_axi_awlen,
                m_axi_awsize,
                m_axi_wvalid,
                m_axi_wready,
                m_axi_wdata,
                m_axi_wstrb,
                m_axi_wlast,
                m_axi_bvalid,
                m_axi_bready,
                m_axi_bresp
            );
            dbg_axi_prev_sig <= dbg_axi_sig;
        end
    end else begin
        dbg_axi_prev_sig <= {1024{1'bx}};
    end
end

`include "common/samram_dma_common_tasks.vh"
`include "tests/test_csr.vh"
`include "tests/test_desc_sram_apb.vh"
`include "tests/test_desc_ring_manager.vh"
`include "tests/test_desc_single_exec.vh"
`include "tests/test_desc_sample_at_grant.vh"
`include "tests/test_desc_multi_ring_exec.vh"
`include "tests/test_single_copy.vh"
`include "tests/test_multi_word.vh"
`include "tests/test_partial_wstrb_aligned.vh"
`include "tests/test_unaligned_dst_wstrb.vh"
`include "tests/test_unaligned_src_shift.vh"
`include "tests/test_combined_unaligned_src_dst.vh"
`include "tests/test_axi_backpressure_stability.vh"
`include "tests/test_read_error.vh"
`include "tests/test_write_error.vh"
`include "tests/test_ctrl_clear.vh"
`include "tests/test_multi_channel_queued_start.vh"
`include "tests/test_round_robin_two_channel.vh"
`include "tests/test_8_channel_one_beat_rr.vh"
`include "tests/test_8_channel_two_beat_rr.vh"
`include "tests/test_multi_error_clear.vh"
`include "tests/test_interrupt_status_priority.vh"

initial begin
    reset_dut();
    test_csr();

    reset_dut();
    test_desc_sram_apb();

    reset_dut();
    test_desc_ring_manager();

    reset_dut();
    test_desc_single_exec();

    reset_dut();
    test_desc_sample_at_grant();

    reset_dut();
    test_desc_multi_ring_exec();

    reset_dut();
    test_single_copy();

    reset_dut();
    test_multi_word();

    reset_dut();
    test_partial_wstrb_aligned();

    reset_dut();
    test_unaligned_dst_wstrb();

    reset_dut();
    dbg_src_active = 1'b1;
    test_unaligned_src_shift();
    dbg_src_active = 1'b0;

    reset_dut();
    dbg_src_active = 1'b1;
    test_combined_unaligned_src_dst();
    dbg_src_active = 1'b0;

    reset_dut();
    dbg_axi_active = 1'b1;
    test_axi_backpressure_stability();
    dbg_axi_active = 1'b0;

    reset_dut();
    test_read_error();

    reset_dut();
    test_write_error();

    reset_dut();
    test_ctrl_clear();

    reset_dut();
    test_multi_channel_queued_start();

    reset_dut();
    test_round_robin_two_channel();
    reset_dut();
    test_8_channel_one_beat_rr();

    reset_dut();
    test_8_channel_two_beat_rr();

    reset_dut();
    test_multi_error_clear();

    reset_dut();
    test_interrupt_status_priority();
    
    $display("SAMRAM DMA consolidated regression PASSED");
    $finish;
end

endmodule

`resetall
