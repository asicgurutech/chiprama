task m15_start_and_complete_csr;
    input [2:0]            ch;
    input [ADDR_WIDTH-1:0] src;
    input [ADDR_WIDTH-1:0] dst;
    input [DATA_WIDTH-1:0] data;
    reg [ADDR_WIDTH-1:0] base;
    begin
        base = ch * 32'h0000_0020;

        apb_write(base + 32'h0000_0000, src);
        apb_write(base + 32'h0000_0004, dst);
        apb_write(base + 32'h0000_0008, 32'h0000_0004);
        apb_write(base + 32'h0000_000c, 32'h0000_0001);

        apb_read_check(base + 32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(src);
        drive_axi_read_data(data, 2'b00, 1'b1);
        expect_axi_write_addr(dst);
        expect_axi_write_data(data);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);
        apb_read_check(base + 32'h0000_0010, 32'h0000_0002); // DONE
    end
endtask

task test_interrupt_status_priority;
    begin
        dbg_intr_active = 1'b1;
        $display("TEST: interrupt status priority and claim");

        // Defaults: done IRQs and fatal/error interrupt are enabled.
        apb_read_check(32'h0000_0200, 32'h0000_0000); // INT_DONE_STATUS
        apb_read_check(32'h0000_0204, 32'h0000_0000); // INT_ERROR_STATUS
        apb_read_check(32'h0000_0208, 32'h0000_00ff); // INT_IRQ_ENABLE
        apb_read_check(32'h0000_020c, 32'h0000_0001); // INT_FIQ_ENABLE
        apb_read_check(32'h0000_0210, 32'h0000_0000); // INT_CLAIM

        // ------------------------------------------------------------
        // Create two done interrupts. Claim should choose the lower
        // channel number among DONE-class interrupts.
        // ------------------------------------------------------------
        m15_start_and_complete_csr(3'd1, 32'h0000_1100, 32'h0000_2100, 32'h1111_0001);
        m15_start_and_complete_csr(3'd0, 32'h0000_1000, 32'h0000_2000, 32'h1111_0000);

        apb_read_check(32'h0000_0200, 32'h0000_0003); // DONE_STATUS[1:0]
        apb_read_check(32'h0000_0204, 32'h0000_0000); // no errors
        apb_read_check(32'h0000_0210, 32'h8000_0000); // valid, done class, CH0

        // Clear CH0 done through INT_CLEAR bit 0. CH1 should remain.
        apb_write(32'h0000_0214, 32'h0000_0001);
        apb_read_check(32'h0000_0200, 32'h0000_0002);
        apb_read_check(32'h0000_0210, 32'h8000_0001); // valid, done class, CH1

        // Clear CH1 done through INT_CLEAR bit 1.
        apb_write(32'h0000_0214, 32'h0000_0002);
        apb_read_check(32'h0000_0200, 32'h0000_0000);
        apb_read_check(32'h0000_0210, 32'h0000_0000); // nothing pending

        // ------------------------------------------------------------
        // Create one DONE and two ERROR conditions. ERROR class must
        // win over DONE class. Within ERROR class, lower channel wins.
        // ------------------------------------------------------------
        m15_start_and_complete_csr(3'd3, 32'h0000_1300, 32'h0000_2300, 32'h3333_0003);

        // CH2 ERROR from zero-length invalid start.
        apb_write(32'h0000_0040, 32'h0000_3000); // CH2 SRC
        apb_write(32'h0000_0044, 32'h0000_4000); // CH2 DST
        apb_write(32'h0000_0048, 32'h0000_0000); // CH2 LEN invalid
        apb_write(32'h0000_004c, 32'h0000_0001); // CH2 START
        apb_read_check(32'h0000_0050, 32'h0000_0004); // CH2 ERROR

        // CH0 ERROR from zero-length invalid start.
        apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0000); // CH0 LEN invalid
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START
        apb_read_check(32'h0000_0010, 32'h0000_0004); // CH0 ERROR

        apb_read_check(32'h0000_0200, 32'h0000_0008); // DONE_STATUS CH3
        apb_read_check(32'h0000_0204, 32'h0000_0005); // ERROR_STATUS CH0 + CH2

        if (fatal_irq !== 1'b1) begin
            $display("fatal_irq should assert with channel errors pending");
            $fatal;
        end

        apb_read_check(32'h0000_0210, 32'h8001_0000); // valid, error class, CH0

        // Clear CH0 ERROR through INT_CLEAR bit 8. CH2 ERROR still wins.
        apb_write(32'h0000_0214, 32'h0000_0100);
        apb_read_check(32'h0000_0204, 32'h0000_0004);
        apb_read_check(32'h0000_0210, 32'h8001_0002); // valid, error class, CH2

        if (fatal_irq !== 1'b1) begin
            $display("fatal_irq should remain asserted while CH2 error remains");
            $fatal;
        end

        // Clear CH2 ERROR through INT_CLEAR bit 10. DONE CH3 should now claim.
        apb_write(32'h0000_0214, 32'h0000_0400);
        apb_read_check(32'h0000_0204, 32'h0000_0000);
        apb_read_check(32'h0000_0210, 32'h8000_0003); // valid, done class, CH3

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should clear after all error bits are cleared");
            $fatal;
        end

        // Disable done IRQs. Raw DONE_STATUS remains, but irq_done output
        // and INT_CLAIM should ignore DONE-class interrupts.
        apb_write(32'h0000_0208, 32'h0000_0000);
        apb_read_check(32'h0000_0200, 32'h0000_0008);
        apb_read_check(32'h0000_0208, 32'h0000_0000);
        apb_read_check(32'h0000_0210, 32'h0000_0000);

        if (irq_done !== 8'h00) begin
            $display("irq_done output should be masked when IRQ_ENABLE=0, got=0x%02x", irq_done);
            $fatal;
        end

        // Re-enable and clear CH3 done before leaving the test.
        apb_write(32'h0000_0208, 32'h0000_00ff);
        apb_write(32'h0000_0214, 32'h0000_0008);
        apb_read_check(32'h0000_0200, 32'h0000_0000);
        apb_read_check(32'h0000_0210, 32'h0000_0000);

        $display("TEST PASS: interrupt status priority and claim");
        dbg_intr_active = 1'b0;
    end
endtask
