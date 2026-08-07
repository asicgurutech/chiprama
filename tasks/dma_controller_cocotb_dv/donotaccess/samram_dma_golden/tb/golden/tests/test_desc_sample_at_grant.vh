task test_desc_sample_at_grant;
    reg [ADDR_WIDTH-1:0] ch1_csr_base;
    reg [ADDR_WIDTH-1:0] ch1_desc_base;
    begin
        $display("TEST: descriptor sampling at arbitration grant");

        ch1_csr_base  = 32'h0000_0020;
        ch1_desc_base = 32'h0000_1000 + 32'h0000_0040;

        // Start CH0 using direct CSR mode and hold its AR unaccepted.
        apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0004); // CH0 LEN
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        wait (m_axi_arvalid === 1'b1);
        #1;
        if (m_axi_araddr !== 32'h0000_1000) begin
            $display("CH0 ARADDR mismatch exp=0x00001000 got=0x%08x", m_axi_araddr);
            $fatal;
        end

        // Queue CH1 descriptor while CH0 owns the DMA.
        apb_write(ch1_desc_base + 32'h0, 32'h0000_3000); // original SRC
        apb_write(ch1_desc_base + 32'h4, 32'h0000_4000); // original DST
        apb_write(ch1_desc_base + 32'h8, 32'h0000_0004); // LEN
        apb_write(ch1_desc_base + 32'hc, 32'h0000_0001); // valid marker
        apb_write(ch1_csr_base  + 32'hc, 32'h0000_0008); // CH1 DESC_DOORBELL

        apb_read_check(ch1_csr_base + 32'h10, 32'h0000_0001); // CH1 BUSY / queued

        // Modify CH1 descriptor before CH1 wins arbitration.
        // Correct golden behavior samples descriptor SRAM at grant time, so
        // CH1 must use these modified SRC/DST values.
        apb_write(ch1_desc_base + 32'h0, 32'h0000_5000); // modified SRC
        apb_write(ch1_desc_base + 32'h4, 32'h0000_6000); // modified DST

        // Complete CH0.
        m_axi_arready = 1'b1;
        @(posedge clk);
        #1;
        m_axi_arready = 1'b0;

        drive_axi_read_data(32'h1111_2222, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_2000);
        expect_axi_write_data(32'h1111_2222);
        drive_axi_write_resp(2'b00);

        // CH1 now wins arbitration and must sample the modified descriptor.
        expect_axi_read_addr(32'h0000_5000);
        drive_axi_read_data(32'h3333_4444, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_6000);
        expect_axi_write_data(32'h3333_4444);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // CH0 DONE
        apb_read_check(ch1_csr_base + 32'h10, 32'h0000_0002); // CH1 DONE
        apb_read_check(ch1_csr_base + 32'h14, 32'h0000_0001); // CH1 HEAD advanced
        apb_read_check(ch1_csr_base + 32'h18, 32'h0000_0001); // CH1 TAIL
        apb_read_check(ch1_csr_base + 32'h1c, 32'h0000_0005); // HEAD=1, TAIL=1, COUNT=0

        if (irq_done !== 8'h03) begin
            $display("irq_done mismatch exp=0x03 got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 for descriptor sample-at-grant test");
            $fatal;
        end

        $display("TEST PASS: descriptor sampling at arbitration grant");
    end
endtask
