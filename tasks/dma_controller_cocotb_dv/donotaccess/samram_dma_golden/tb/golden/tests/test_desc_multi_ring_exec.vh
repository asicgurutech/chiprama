task test_desc_multi_ring_exec;
    begin
        $display("TEST: descriptor multi-ring execution and push-back");

        // ------------------------------------------------------------
        // CH0 has two descriptors in its ring.
        // CH1 has one descriptor.
        //
        // Expected service order:
        //   CH0 descriptor 0
        //   CH1 descriptor 0
        //   CH0 descriptor 1
        //
        // This proves that after CH0 completes descriptor 0, it is
        // removed from active service and pushed to the back of the
        // active queue when descriptor 1 is ready.
        // ------------------------------------------------------------

        // CH0 slot0 descriptor
        apb_write(32'h0000_1000, 32'h0000_1000); // CH0 slot0 SRC
        apb_write(32'h0000_1004, 32'h0000_2000); // CH0 slot0 DST
        apb_write(32'h0000_1008, 32'h0000_0004); // CH0 slot0 LEN
        apb_write(32'h0000_100c, 32'h0000_0001); // CH0 slot0 CTRL/STATUS

        // CH0 slot1 descriptor
        apb_write(32'h0000_1010, 32'h0000_1100); // CH0 slot1 SRC
        apb_write(32'h0000_1014, 32'h0000_2100); // CH0 slot1 DST
        apb_write(32'h0000_1018, 32'h0000_0004); // CH0 slot1 LEN
        apb_write(32'h0000_101c, 32'h0000_0001); // CH0 slot1 CTRL/STATUS

        // Doorbell CH0 for descriptor 0.
        apb_write(32'h0000_000c, 32'h0000_0008); // CH0 DESC_DOORBELL

        // Wait until CH0 has won arbitration and is holding ARVALID.
        // Do not accept it yet; this leaves CH0 active while we queue
        // CH0 descriptor 1 and CH1 descriptor 0.
        wait (m_axi_arvalid === 1'b1);
        #1;
        if (m_axi_araddr !== 32'h0000_1000) begin
            $display("Initial CH0 descriptor ARADDR mismatch exp=0x00001000 got=0x%08x", m_axi_araddr);
            $fatal;
        end

        // Doorbell CH0 for descriptor 1 while CH0 descriptor 0 is active.
        apb_write(32'h0000_000c, 32'h0000_0008); // CH0 DESC_DOORBELL

        // CH1 slot0 descriptor
        apb_write(32'h0000_1040, 32'h0000_3000); // CH1 slot0 SRC
        apb_write(32'h0000_1044, 32'h0000_4000); // CH1 slot0 DST
        apb_write(32'h0000_1048, 32'h0000_0004); // CH1 slot0 LEN
        apb_write(32'h0000_104c, 32'h0000_0001); // CH1 slot0 CTRL/STATUS

        // Doorbell CH1 while CH0 descriptor 0 is still active.
        apb_write(32'h0000_002c, 32'h0000_0008); // CH1 DESC_DOORBELL

        apb_read_check(32'h0000_0010, 32'h0000_0001); // CH0 BUSY
        apb_read_check(32'h0000_0030, 32'h0000_0001); // CH1 BUSY

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 while descriptor rings are valid");
            $fatal;
        end

        // ------------------------------------------------------------
        // Service CH0 descriptor 0.
        // ------------------------------------------------------------
        expect_axi_read_addr(32'h0000_1000);
        drive_axi_read_data(32'hd000_0000, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_2000);
        expect_axi_write_data(32'hd000_0000);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        // CH0 has another descriptor, so it should not be DONE yet.
        // CH1 should be selected before CH0 descriptor 1.
        apb_read_check(32'h0000_0010, 32'h0000_0001); // CH0 still BUSY
        apb_read_check(32'h0000_0030, 32'h0000_0001); // CH1 still BUSY

        // ------------------------------------------------------------
        // Service CH1 descriptor 0 next. This proves CH0 descriptor 1
        // was pushed behind the already-queued CH1.
        // ------------------------------------------------------------
        expect_axi_read_addr(32'h0000_3000);
        drive_axi_read_data(32'hd000_0001, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_4000);
        expect_axi_write_data(32'hd000_0001);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0030, 32'h0000_0002); // CH1 DONE

        // ------------------------------------------------------------
        // Service CH0 descriptor 1 last.
        // ------------------------------------------------------------
        expect_axi_read_addr(32'h0000_1100);
        drive_axi_read_data(32'hd000_0002, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_2100);
        expect_axi_write_data(32'hd000_0002);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // CH0 DONE
        apb_read_check(32'h0000_0030, 32'h0000_0002); // CH1 DONE

        // CH0 ring: HEAD=2, TAIL=2, COUNT=0, READY=0, FULL=0 => 0x0000000a
        // CH1 ring: HEAD=1, TAIL=1, COUNT=0, READY=0, FULL=0 => 0x00000005
        apb_read_check(32'h0000_001c, 32'h0000_000a);
        apb_read_check(32'h0000_003c, 32'h0000_0005);

        if (irq_done !== 8'b0000_0011) begin
            $display("irq_done mismatch exp=0x03 got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 for multi-descriptor ring execution");
            $fatal;
        end

        $display("TEST PASS: descriptor multi-ring execution and push-back");
    end
endtask
