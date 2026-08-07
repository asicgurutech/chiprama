task test_8_channel_one_beat_rr;
    integer ch;
    reg [ADDR_WIDTH-1:0] base;
    reg [ADDR_WIDTH-1:0] exp_src;
    reg [ADDR_WIDTH-1:0] exp_dst;
    reg [DATA_WIDTH-1:0] exp_data;
    begin
        $display("TEST: 8-channel one-beat round-robin");

        // ------------------------------------------------------------
        // Start CH0 first and hold its AR unaccepted so CH1-CH7 can
        // be queued behind it.
        // ------------------------------------------------------------
        apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0004); // CH0 LEN = 4 bytes
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // CH0 BUSY

        wait (m_axi_arvalid === 1'b1);
        #1;
        if (m_axi_araddr !== 32'h0000_1000) begin
            $display("Initial CH0 ARADDR mismatch exp=0x00001000 got=0x%08x", m_axi_araddr);
            $fatal;
        end

        // ------------------------------------------------------------
        // Queue CH1 through CH7.
        // Channel base address = channel * 0x20.
        // SRC = 0x1000 + channel * 0x100.
        // DST = 0x2000 + channel * 0x100.
        // ------------------------------------------------------------
        for (ch = 1; ch < 8; ch = ch + 1) begin
            base    = ch * 32'h0000_0020;
            exp_src = 32'h0000_1000 + (ch * 32'h0000_0100);
            exp_dst = 32'h0000_2000 + (ch * 32'h0000_0100);

            apb_write(base + 32'h0000_0000, exp_src);
            apb_write(base + 32'h0000_0004, exp_dst);
            apb_write(base + 32'h0000_0008, 32'h0000_0004);
            apb_write(base + 32'h0000_000c, 32'h0000_0001);
        end

        // All channels should now be BUSY: CH0 active, CH1-CH7 queued.
        for (ch = 0; ch < 8; ch = ch + 1) begin
            base = ch * 32'h0000_0020;
            apb_read_check(base + 32'h0000_0010, 32'h0000_0001);
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 after valid 8-channel queue");
            $fatal;
        end

        if (irq_done !== 8'h00) begin
            $display("irq_done should be zero before transfers complete, got=0x%02x", irq_done);
            $fatal;
        end

        // ------------------------------------------------------------
        // Expected servicing order:
        // CH0, CH1, CH2, CH3, CH4, CH5, CH6, CH7
        // Each is one beat.
        // ------------------------------------------------------------
        for (ch = 0; ch < 8; ch = ch + 1) begin
            exp_src  = 32'h0000_1000 + (ch * 32'h0000_0100);
            exp_dst  = 32'h0000_2000 + (ch * 32'h0000_0100);
            exp_data = 32'he000_0000 + ch;

            expect_axi_read_addr(exp_src);
            drive_axi_read_data(exp_data, 2'b00, 1'b1);

            expect_axi_write_addr(exp_dst);
            expect_axi_write_data(exp_data);
            drive_axi_write_resp(2'b00);
        end

        repeat (2) @(posedge clk);

        // All channels should be DONE.
        for (ch = 0; ch < 8; ch = ch + 1) begin
            base = ch * 32'h0000_0020;
            apb_read_check(base + 32'h0000_0010, 32'h0000_0002);
        end

        if (irq_done !== 8'hff) begin
            $display("irq_done mismatch exp=0xff got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 for 8-channel one-beat round-robin");
            $fatal;
        end

        $display("TEST PASS: 8-channel one-beat round-robin");
    end
endtask