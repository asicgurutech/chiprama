task test_multi_channel_queued_start;
    begin
        $display("TEST: multi-channel queued-start behavior");

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
        // New behavior: CH1 should be accepted and queued as BUSY.
        // ------------------------------------------------------------
        apb_write(32'h0000_0020, 32'h0000_3000); // CH1 SRC
        apb_write(32'h0000_0024, 32'h0000_4000); // CH1 DST
        apb_write(32'h0000_0028, 32'h0000_0004); // CH1 LEN
        apb_write(32'h0000_002c, 32'h0000_0001); // CH1 START while CH0 active

        apb_read_check(32'h0000_0010, 32'h0000_0001); // CH0 BUSY
        apb_read_check(32'h0000_0030, 32'h0000_0001); // CH1 BUSY / queued

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 after valid queued CH1 start");
            $fatal;
        end

        if (irq_done !== 8'b0000_0000) begin
            $display("irq_done should still be zero before CH0 completes, got=0x%02x", irq_done);
            $fatal;
        end

        // ------------------------------------------------------------
        // Complete CH0.
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
        apb_read_check(32'h0000_0030, 32'h0000_0001); // CH1 now active/BUSY

        if (irq_done !== 8'b0000_0001) begin
            $display("irq_done mismatch after CH0 done exp=0x01 got=0x%02x", irq_done);
            $fatal;
        end

        // ------------------------------------------------------------
        // CH1 should now issue its AXI read.
        // ------------------------------------------------------------
        wait (m_axi_arvalid === 1'b1);
        #1;
        if (m_axi_araddr !== 32'h0000_3000) begin
            $display("CH1 ARADDR mismatch exp=0x00003000 got=0x%08x", m_axi_araddr);
            $fatal;
        end

        m_axi_arready = 1'b1;
        @(posedge clk);
        #1;
        m_axi_arready = 1'b0;

        drive_axi_read_data(32'haaaa_5555, 2'b00, 1'b1);

        expect_axi_write_addr(32'h0000_4000);
        expect_axi_write_data(32'haaaa_5555);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // CH0 DONE
        apb_read_check(32'h0000_0030, 32'h0000_0002); // CH1 DONE

        if (irq_done !== 8'b0000_0011) begin
            $display("irq_done mismatch exp=0x03 got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 for queued two-channel transfer");
            $fatal;
        end

        $display("TEST PASS: multi-channel queued-start behavior");
    end
endtask