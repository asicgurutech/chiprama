task test_read_error;
    begin
        $display("TEST: read-error");

        apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0004); // CH0 LEN
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_1000);
        drive_axi_read_data(32'hbad0_bad0, 2'b10, 1'b1); // SLVERR

        repeat (3) @(posedge clk);

        check_no_axi_write_issued();
        apb_read_check(32'h0000_0010, 32'h0000_0004); // ERROR

        if (irq_done !== {NUM_CH{1'b0}}) begin
            $display("irq_done should remain zero after read error, got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b1) begin
            $display("fatal_irq should be set after read error");
            $fatal;
        end

        $display("TEST PASS: read-error");
    end
endtask
