task init_inputs;
    begin
        s_apb_paddr   = {ADDR_WIDTH{1'b0}};
        s_apb_psel    = 1'b0;
        s_apb_penable = 1'b0;
        s_apb_pwrite  = 1'b0;
        s_apb_pwdata  = {DATA_WIDTH{1'b0}};
        s_apb_pstrb   = {STRB_WIDTH{1'b0}};

        m_axi_awready = 1'b0;
        m_axi_wready  = 1'b0;
        m_axi_bid     = {AXI_ID_WIDTH{1'b0}};
        m_axi_bresp   = 2'b00;
        m_axi_bvalid  = 1'b0;

        m_axi_arready = 1'b0;
        m_axi_rid     = {AXI_ID_WIDTH{1'b0}};
        m_axi_rdata   = {DATA_WIDTH{1'b0}};
        m_axi_rresp   = 2'b00;
        m_axi_rlast   = 1'b0;
        m_axi_rvalid  = 1'b0;
    end
endtask

task reset_dut;
    begin
        init_inputs();
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
    end
endtask

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

task expect_axi_read_addr;
    input [ADDR_WIDTH-1:0] exp_addr;
    begin
        wait (m_axi_arvalid === 1'b1);
        #1;
        if (m_axi_araddr !== exp_addr) begin
            $display("ARADDR mismatch exp=0x%08x got=0x%08x", exp_addr, m_axi_araddr);
            $fatal;
        end
        if (m_axi_arlen !== 8'd0) begin
            $display("ARLEN should be 0 for single-beat transfer");
            $fatal;
        end
        if (m_axi_arsize !== EXP_AXI_SIZE) begin
            $display("ARSIZE mismatch exp=0x%0x got=0x%0x", EXP_AXI_SIZE, m_axi_arsize);
            $fatal;
        end

        m_axi_arready = 1'b1;
        @(posedge clk);
        #1;
        m_axi_arready = 1'b0;
    end
endtask

task drive_axi_read_data;
    input [DATA_WIDTH-1:0] data;
    input [1:0]            resp;
    input                  last;
    begin
        wait (m_axi_rready === 1'b1);
        m_axi_rid     = {AXI_ID_WIDTH{1'b0}};
        m_axi_rdata   = data;
        m_axi_rresp   = resp;
        m_axi_rlast   = last;
        m_axi_rvalid  = 1'b1;

        @(posedge clk);
        #1;
        m_axi_rvalid  = 1'b0;
        m_axi_rlast   = 1'b0;
        m_axi_rresp   = 2'b00;
        m_axi_rdata   = {DATA_WIDTH{1'b0}};
    end
endtask

task expect_axi_write_addr;
    input [ADDR_WIDTH-1:0] exp_addr;
    begin
        wait (m_axi_awvalid === 1'b1);
        #1;
        if (m_axi_awaddr !== exp_addr) begin
            $display("AWADDR mismatch exp=0x%08x got=0x%08x", exp_addr, m_axi_awaddr);
            $fatal;
        end
        if (m_axi_awlen !== 8'd0) begin
            $display("AWLEN should be 0 for single-beat transfer");
            $fatal;
        end
        if (m_axi_awsize !== EXP_AXI_SIZE) begin
            $display("AWSIZE mismatch exp=0x%0x got=0x%0x", EXP_AXI_SIZE, m_axi_awsize);
            $fatal;
        end

        m_axi_awready = 1'b1;
        @(posedge clk);
        #1;
        m_axi_awready = 1'b0;
    end
endtask

task expect_axi_write_data_strobe;
    input [DATA_WIDTH-1:0] exp_data;
    input [STRB_WIDTH-1:0] exp_strb;
    integer strobe_idx;
    reg [DATA_WIDTH-1:0] active_lane_mask;
    begin
        wait (m_axi_wvalid === 1'b1);
        #1;

        active_lane_mask = {DATA_WIDTH{1'b0}};
        for (strobe_idx = 0; strobe_idx < STRB_WIDTH; strobe_idx = strobe_idx + 1) begin
            if (exp_strb[strobe_idx]) begin
                active_lane_mask[(strobe_idx*8) +: 8] = 8'hff;
            end
        end

        if (m_axi_wstrb !== exp_strb) begin
            $display("WSTRB mismatch exp=0x%0x got=0x%0x", exp_strb, m_axi_wstrb);
            $fatal;
        end
        if ((m_axi_wdata & active_lane_mask) !== (exp_data & active_lane_mask)) begin
            $display("WDATA active-lane mismatch exp=0x%08x got=0x%08x mask=0x%08x",
                exp_data, m_axi_wdata, active_lane_mask);
            $fatal;
        end
        if (m_axi_wlast !== 1'b1) begin
            $display("WLAST should be asserted for single-beat transfer");
            $fatal;
        end

        m_axi_wready = 1'b1;
        @(posedge clk);
        #1;
        m_axi_wready = 1'b0;
    end
endtask

task expect_axi_write_data;
    input [DATA_WIDTH-1:0] exp_data;
    begin
        expect_axi_write_data_strobe(exp_data, {STRB_WIDTH{1'b1}});
    end
endtask

task drive_axi_write_resp;
    input [1:0] resp;
    begin
        wait (m_axi_bready === 1'b1);
        m_axi_bid    = {AXI_ID_WIDTH{1'b0}};
        m_axi_bresp  = resp;
        m_axi_bvalid = 1'b1;

        @(posedge clk);
        #1;
        m_axi_bvalid = 1'b0;
        m_axi_bresp  = 2'b00;
    end
endtask

task check_no_axi_write_issued;
    begin
        if (m_axi_awvalid !== 1'b0) begin
            $display("AWVALID should remain 0");
            $fatal;
        end
        if (m_axi_wvalid !== 1'b0) begin
            $display("WVALID should remain 0");
            $fatal;
        end
    end
endtask
