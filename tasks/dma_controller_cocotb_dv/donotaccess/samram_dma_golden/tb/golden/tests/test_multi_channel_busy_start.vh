task test_multi_channel_busy_start;
    begin
        $display("TEST: multi-channel busy-start behavior");

        // ------------------------------------------------------------
        // Start CH0 and intentionally leave AXI AR unaccepted so DMA
        // remains active.
        // ------------------------------------------------------------
        apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0004); // CH0 LEN
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // CH0 BUSY

        wait (m_axi_arvalid === 1'b1);
        #1;
        if (m_axi_araddr !== 32'h0000_1000) begin
            $display("CH0 ARADDR mismatch exp=0x00001000 got=0x%08x", m_axi_araddr);
            $fatal;
        end

        // ------------------------------------------------------------
        // Start CH1 while CH0 is still active.
        // Current RTL should reject this because only one channel can
        // be active before arbitration is implemented.
        // ------------------------------------------------------------
        apb_write(32'h0000_0020, 32'h0000_3000); // CH1 SRC
        apb_write(32'h0000_0024, 32'h0000_4000); // CH1 DST
        apb_write(32'h0000_0028, 32'h0000_0004); // CH1 LEN
        apb_write(32'h0000_002c, 32'h0000_0001); // CH1 START while CH0 active

        apb_read_check(32'h0000_0010, 32'h0000_0001); // CH0 still BUSY
        apb_read_check(32'h0000_0030, 32'h0000_0004); // CH1 ERROR

        if (fatal_irq !== 1'b1) begin
            $display("fatal_irq should be set after CH1 busy-start rejection");
            $fatal;
        end

        if (irq_done !== 8'b0000_0000) begin
            $display("irq_done should still be zero before CH0 completes, got=0x%02x", irq_done);
            $fatal;
        end

        // ------------------------------------------------------------
        // Now allow CH0 transfer to complete.
        // CH1 error must not corrupt CH0 progress.
        // ------------------------------------------------------------
        m_axi_arready = 1'b1;
        @(posedge clk);
        #1;
        m_axi_arready = 1'b0;

        drive_axi_read_data(32'h5555_aaaa, 2'b00, 1'b1);

        expect_axi_write_addr(32'h0000_2000);
        expect_axi_write_data(32'h5555_aaaa);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // CH0 DONE
        apb_read_check(32'h0000_0030, 32'h0000_0004); // CH1 ERROR still sticky

        if (irq_done !== 8'b0000_0001) begin
            $display("irq_done mismatch exp=0x01 got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b1) begin
            $display("fatal_irq should remain set because CH1 ERROR is still sticky");
            $fatal;
        end

        $display("TEST PASS: multi-channel busy-start behavior");
    end
endtask