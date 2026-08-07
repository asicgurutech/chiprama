task test_csr;
    begin
        $display("TEST: CSR smoke");

        // CH0 base = 0x00
        apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0040); // CH0 LEN
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0000, 32'h0000_1000);
        apb_read_check(32'h0000_0004, 32'h0000_2000);
        apb_read_check(32'h0000_0008, 32'h0000_0040);
        apb_read_check(32'h0000_000c, 32'h0000_0000); // CTRL command bits self-clear
        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY after START

        // CH1 base = 0x20. Verify independent CSR storage.
        apb_write(32'h0000_0020, 32'h0000_3000); // CH1 SRC
        apb_write(32'h0000_0024, 32'h0000_4000); // CH1 DST
        apb_write(32'h0000_0028, 32'h0000_0080); // CH1 LEN

        apb_read_check(32'h0000_0020, 32'h0000_3000);
        apb_read_check(32'h0000_0024, 32'h0000_4000);
        apb_read_check(32'h0000_0028, 32'h0000_0080);

        if (irq_done !== {NUM_CH{1'b0}}) begin
            $display("irq_done should be zero in CSR smoke test, got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should be zero in CSR smoke test");
            $fatal;
        end

        $display("TEST PASS: CSR smoke");
    end
endtask
