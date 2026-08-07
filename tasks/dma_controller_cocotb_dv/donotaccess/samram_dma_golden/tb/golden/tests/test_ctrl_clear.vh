task test_ctrl_clear;
    begin
        $display("TEST: ctrl-clear");

        // Part 1: START should self-clear, then DONE should be clearable.
        apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0004); // CH0 LEN
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_000c, 32'h0000_0000); // CTRL command bits self-clear

        expect_axi_read_addr(32'h0000_1000);
        drive_axi_read_data(32'h1234_5678, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_2000);
        expect_axi_write_data(32'h1234_5678);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE

        if (irq_done !== 8'b0000_0001) begin
            $display("irq_done should be set after successful transfer, got=0x%02x", irq_done);
            $fatal;
        end

        apb_write(32'h0000_000c, 32'h0000_0002); // CTRL[1] CLEAR_DONE

        apb_read_check(32'h0000_000c, 32'h0000_0000); // CTRL still reads zero
        apb_read_check(32'h0000_0010, 32'h0000_0000); // DONE cleared

        if (irq_done !== 8'b0000_0000) begin
            $display("irq_done should clear after CLEAR_DONE, got=0x%02x", irq_done);
            $fatal;
        end

        // Part 2: ERROR should be clearable.
        // CH1 base = 0x20. Use zero length to force invalid-start ERROR.
        apb_write(32'h0000_0020, 32'h0000_3000); // CH1 SRC
        apb_write(32'h0000_0024, 32'h0000_4000); // CH1 DST
        apb_write(32'h0000_0028, 32'h0000_0000); // CH1 LEN invalid
        apb_write(32'h0000_002c, 32'h0000_0001); // CH1 START

        apb_read_check(32'h0000_0030, 32'h0000_0004); // ERROR

        if (fatal_irq !== 1'b1) begin
            $display("fatal_irq should be set after invalid start");
            $fatal;
        end

        apb_write(32'h0000_002c, 32'h0000_0004); // CTRL[2] CLEAR_ERROR

        apb_read_check(32'h0000_002c, 32'h0000_0000); // CTRL still reads zero
        apb_read_check(32'h0000_0030, 32'h0000_0000); // ERROR cleared

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should clear after CLEAR_ERROR");
            $fatal;
        end

        $display("TEST PASS: ctrl-clear");
    end
endtask
