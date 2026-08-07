`resetall
`timescale 1ns/1ps
`default_nettype none

module samram_dma_csr_tb;

localparam NUM_CH       = 8;
localparam ADDR_WIDTH   = 32;
localparam DATA_WIDTH   = 32;
localparam STRB_WIDTH   = DATA_WIDTH/8;
localparam AXI_ID_WIDTH = 4;

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
reg                     m_axi_awready = 1'b1;

wire [DATA_WIDTH-1:0]   m_axi_wdata;
wire [STRB_WIDTH-1:0]   m_axi_wstrb;
wire                    m_axi_wlast;
wire                    m_axi_wvalid;
reg                     m_axi_wready = 1'b1;

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
reg                     m_axi_arready = 1'b1;

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

task apb_write;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] data;
    begin
        @(posedge clk);
        s_apb_paddr   <= addr;
        s_apb_pwdata  <= data;
        s_apb_pstrb   <= {STRB_WIDTH{1'b1}};
        s_apb_pwrite  <= 1'b1;
        s_apb_psel    <= 1'b1;
        s_apb_penable <= 1'b0;

        @(posedge clk);
        s_apb_penable <= 1'b1;

        @(posedge clk);
        s_apb_psel    <= 1'b0;
        s_apb_penable <= 1'b0;
        s_apb_pwrite  <= 1'b0;
    end
endtask

task apb_read_check;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] exp;
    begin
        @(posedge clk);
        s_apb_paddr   <= addr;
        s_apb_pwdata  <= {DATA_WIDTH{1'b0}};
        s_apb_pstrb   <= {STRB_WIDTH{1'b1}};
        s_apb_pwrite  <= 1'b0;
        s_apb_psel    <= 1'b1;
        s_apb_penable <= 1'b0;

        @(posedge clk);
        s_apb_penable <= 1'b1;

        #1;
        if (s_apb_prdata !== exp) begin
            $display("APB READ FAIL addr=0x%08x exp=0x%08x got=0x%08x",
                addr, exp, s_apb_prdata);
            $fatal;
        end

        @(posedge clk);
        s_apb_psel    <= 1'b0;
        s_apb_penable <= 1'b0;
    end
endtask

initial begin
    s_apb_paddr   = {ADDR_WIDTH{1'b0}};
    s_apb_psel    = 1'b0;
    s_apb_penable = 1'b0;
    s_apb_pwrite  = 1'b0;
    s_apb_pwdata  = {DATA_WIDTH{1'b0}};
    s_apb_pstrb   = {STRB_WIDTH{1'b0}};

    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
    repeat (2) @(posedge clk);

    // CH0 base = 0x00
    apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
    apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
    apb_write(32'h0000_0008, 32'h0000_0040); // CH0 LEN
    apb_write(32'h0000_000c, 32'h0000_0001); // CH0 CTRL

    apb_read_check(32'h0000_0000, 32'h0000_1000);
    apb_read_check(32'h0000_0004, 32'h0000_2000);
    apb_read_check(32'h0000_0008, 32'h0000_0040);
    apb_read_check(32'h0000_000c, 32'h0000_0000); // CTRL command bits self-clear
    apb_read_check(32'h0000_0010, 32'h0000_0001); // CH0 STATUS: BUSY after valid START

    // CH1 base = 0x20
    apb_write(32'h0000_0020, 32'h0000_3000); // CH1 SRC
    apb_write(32'h0000_0024, 32'h0000_4000); // CH1 DST
    apb_write(32'h0000_0028, 32'h0000_0080); // CH1 LEN

    apb_read_check(32'h0000_0020, 32'h0000_3000);
    apb_read_check(32'h0000_0024, 32'h0000_4000);
    apb_read_check(32'h0000_0028, 32'h0000_0080);

    if (irq_done !== {NUM_CH{1'b0}}) begin
        $display("IRQ_DONE should be zero in CSR-only skeleton");
        $fatal;
    end

    if (fatal_irq !== 1'b0) begin
        $display("fatal_irq should be zero before invalid start");
        $fatal;
    end

    // CH2 base = 0x40. Use unaligned SRC_ADDR to force fatal error.
    apb_write(32'h0000_0040, 32'h0000_3001); // CH2 SRC, intentionally unaligned
    apb_write(32'h0000_0044, 32'h0000_4000); // CH2 DST
    apb_write(32'h0000_0048, 32'h0000_0040); // CH2 LEN
    apb_write(32'h0000_004c, 32'h0000_0001); // CH2 CTRL START

    apb_read_check(32'h0000_0050, 32'h0000_0004); // CH2 STATUS: ERROR

    if (fatal_irq !== 1'b1) begin
        $display("fatal_irq should be set after invalid start");
        $fatal;
    end

    $display("SAMRAM DMA CSR smoke test PASSED");
    $finish;
end

endmodule

`resetall