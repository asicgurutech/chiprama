task test_single_copy;
    begin
        $display("TEST: single-copy");

        apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0004); // CH0 LEN = one 32-bit word
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_1000);
        drive_axi_read_data(32'hdead_beef, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_2000);
        expect_axi_write_data(32'hdead_beef);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE

        if (irq_done !== 8'b0000_0001) begin
            $display("irq_done mismatch exp=0x01 got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 for successful transfer");
            $fatal;
        end

        $display("TEST PASS: single-copy");
    end
endtask
