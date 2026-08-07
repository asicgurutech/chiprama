// -----------------------------------------------------------------------------
// AXI backpressure and valid-payload stability
// -----------------------------------------------------------------------------

function [DATA_WIDTH-1:0] bp_active_lane_mask;
    input [STRB_WIDTH-1:0] strb;
    integer lane_idx;
    begin
        bp_active_lane_mask = {DATA_WIDTH{1'b0}};
        for (lane_idx = 0; lane_idx < STRB_WIDTH; lane_idx = lane_idx + 1) begin
            if (strb[lane_idx]) begin
                bp_active_lane_mask[(lane_idx*8) +: 8] = 8'hff;
            end
        end
    end
endfunction

task bp_check_ar_payload;
    input [ADDR_WIDTH-1:0] exp_addr;
    begin
        #1;
        if (m_axi_arvalid !== 1'b1) begin
            $display("ARVALID dropped while ARREADY was low");
            $fatal;
        end
        if (m_axi_araddr !== exp_addr) begin
            $display("ARADDR changed under backpressure exp=0x%08x got=0x%08x", exp_addr, m_axi_araddr);
            $fatal;
        end
        if (m_axi_arlen !== 8'd0) begin
            $display("ARLEN changed under backpressure exp=0 got=%0d", m_axi_arlen);
            $fatal;
        end
        if (m_axi_arsize !== EXP_AXI_SIZE) begin
            $display("ARSIZE changed under backpressure exp=0x%0x got=0x%0x", EXP_AXI_SIZE, m_axi_arsize);
            $fatal;
        end
        if (m_axi_arburst !== 2'b01) begin
            $display("ARBURST changed under backpressure exp=INCR got=0x%0x", m_axi_arburst);
            $fatal;
        end
    end
endtask

task expect_axi_read_addr_backpressure;
    input [ADDR_WIDTH-1:0] exp_addr;
    input integer          stall_cycles;
    integer                cycle_idx;
    begin
        wait (m_axi_arvalid === 1'b1);
        m_axi_arready = 1'b0;

        for (cycle_idx = 0; cycle_idx < stall_cycles; cycle_idx = cycle_idx + 1) begin
            bp_check_ar_payload(exp_addr);
            @(posedge clk);
        end

        bp_check_ar_payload(exp_addr);
        m_axi_arready = 1'b1;
        @(posedge clk);
        #1;
        m_axi_arready = 1'b0;
    end
endtask

task drive_axi_read_data_delayed;
    input [DATA_WIDTH-1:0] data;
    input [1:0]            resp;
    input                  last;
    input integer          delay_cycles;
    integer                cycle_idx;
    begin
        wait (m_axi_rready === 1'b1);
        m_axi_rvalid = 1'b0;

        for (cycle_idx = 0; cycle_idx < delay_cycles; cycle_idx = cycle_idx + 1) begin
            #1;
            if (m_axi_rready !== 1'b1) begin
                $display("RREADY dropped while waiting for delayed RVALID");
                $fatal;
            end
            @(posedge clk);
        end

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

task bp_check_aw_payload;
    input [ADDR_WIDTH-1:0] exp_addr;
    begin
        #1;
        if (m_axi_awvalid !== 1'b1) begin
            $display("AWVALID dropped while AWREADY was low");
            $fatal;
        end
        if (m_axi_awaddr !== exp_addr) begin
            $display("AWADDR changed under backpressure exp=0x%08x got=0x%08x", exp_addr, m_axi_awaddr);
            $fatal;
        end
        if (m_axi_awlen !== 8'd0) begin
            $display("AWLEN changed under backpressure exp=0 got=%0d", m_axi_awlen);
            $fatal;
        end
        if (m_axi_awsize !== EXP_AXI_SIZE) begin
            $display("AWSIZE changed under backpressure exp=0x%0x got=0x%0x", EXP_AXI_SIZE, m_axi_awsize);
            $fatal;
        end
        if (m_axi_awburst !== 2'b01) begin
            $display("AWBURST changed under backpressure exp=INCR got=0x%0x", m_axi_awburst);
            $fatal;
        end
    end
endtask

task expect_axi_write_addr_backpressure;
    input [ADDR_WIDTH-1:0] exp_addr;
    input integer          stall_cycles;
    integer                cycle_idx;
    begin
        wait (m_axi_awvalid === 1'b1);
        m_axi_awready = 1'b0;

        for (cycle_idx = 0; cycle_idx < stall_cycles; cycle_idx = cycle_idx + 1) begin
            bp_check_aw_payload(exp_addr);
            @(posedge clk);
        end

        bp_check_aw_payload(exp_addr);
        m_axi_awready = 1'b1;
        @(posedge clk);
        #1;
        m_axi_awready = 1'b0;
    end
endtask

task bp_check_w_payload;
    input [DATA_WIDTH-1:0] exp_data;
    input [STRB_WIDTH-1:0] exp_strb;
    reg [DATA_WIDTH-1:0]   active_mask;
    begin
        #1;
        active_mask = bp_active_lane_mask(exp_strb);

        if (m_axi_wvalid !== 1'b1) begin
            $display("WVALID dropped while WREADY was low");
            $fatal;
        end
        if (m_axi_wstrb !== exp_strb) begin
            $display("WSTRB changed under backpressure exp=0x%0x got=0x%0x", exp_strb, m_axi_wstrb);
            $fatal;
        end
        if ((m_axi_wdata & active_mask) !== (exp_data & active_mask)) begin
            $display("WDATA active lanes changed under backpressure exp=0x%08x got=0x%08x mask=0x%08x",
                exp_data, m_axi_wdata, active_mask);
            $fatal;
        end
        if (m_axi_wlast !== 1'b1) begin
            $display("WLAST changed under backpressure");
            $fatal;
        end
    end
endtask

task expect_axi_write_data_backpressure;
    input [DATA_WIDTH-1:0] exp_data;
    input [STRB_WIDTH-1:0] exp_strb;
    input integer          stall_cycles;
    integer                cycle_idx;
    begin
        wait (m_axi_wvalid === 1'b1);
        m_axi_wready = 1'b0;

        for (cycle_idx = 0; cycle_idx < stall_cycles; cycle_idx = cycle_idx + 1) begin
            bp_check_w_payload(exp_data, exp_strb);
            @(posedge clk);
        end

        bp_check_w_payload(exp_data, exp_strb);
        m_axi_wready = 1'b1;
        @(posedge clk);
        #1;
        m_axi_wready = 1'b0;
    end
endtask

task drive_axi_write_resp_delayed;
    input [1:0]   resp;
    input integer delay_cycles;
    integer       cycle_idx;
    begin
        wait (m_axi_bready === 1'b1);
        m_axi_bvalid = 1'b0;

        for (cycle_idx = 0; cycle_idx < delay_cycles; cycle_idx = cycle_idx + 1) begin
            #1;
            if (m_axi_bready !== 1'b1) begin
                $display("BREADY dropped while waiting for delayed BVALID");
                $fatal;
            end
            @(posedge clk);
        end

        m_axi_bid    = {AXI_ID_WIDTH{1'b0}};
        m_axi_bresp  = resp;
        m_axi_bvalid = 1'b1;

        @(posedge clk);
        #1;
        m_axi_bvalid = 1'b0;
        m_axi_bresp  = 2'b00;
    end
endtask

task test_axi_backpressure_stability;
    begin
        $display("TEST: AXI backpressure and valid-payload stability");

        // Aligned SRC/DST, LEN=6.  This keeps the expected transfer simple while
        // exercising two read transactions, two write transactions, and a partial
        // final WSTRB under deliberate ready/valid backpressure.
        apb_write(32'h0000_0000, 32'h0000_9000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_a000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0006); // CH0 LEN = 6 bytes
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr_backpressure(32'h0000_9000, 3);
        drive_axi_read_data_delayed(32'hdead_beef, 2'b00, 1'b1, 2);
        expect_axi_write_addr_backpressure(32'h0000_a000, 4);
        expect_axi_write_data_backpressure(32'hdead_beef, 4'b1111, 5);
        drive_axi_write_resp_delayed(2'b00, 3);

        expect_axi_read_addr_backpressure(32'h0000_9004, 2);
        drive_axi_read_data_delayed(32'h1122_3344, 2'b00, 1'b1, 1);
        expect_axi_write_addr_backpressure(32'h0000_a004, 3);
        expect_axi_write_data_backpressure(32'h1122_3344, 4'b0011, 4);
        drive_axi_write_resp_delayed(2'b00, 2);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE

        if (irq_done !== 8'b0000_0001) begin
            $display("irq_done mismatch exp=0x01 got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 after AXI backpressure test");
            $fatal;
        end

        $display("TEST PASS: AXI backpressure and valid-payload stability");
    end
endtask
