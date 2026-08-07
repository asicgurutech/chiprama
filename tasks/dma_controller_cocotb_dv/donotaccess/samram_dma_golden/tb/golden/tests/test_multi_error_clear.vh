task test_multi_error_clear;
    begin
        $display("TEST: multi-error fatal_irq clear behavior");

        // ------------------------------------------------------------
        // Create CH0 ERROR using zero length.
        // ------------------------------------------------------------
        apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0000); // CH0 LEN invalid
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0004); // CH0 ERROR

        if (fatal_irq !== 1'b1) begin
            $display("fatal_irq should be set after CH0 ERROR");
            $fatal;
        end

        // ------------------------------------------------------------
        // Create CH1 ERROR using zero length.
        // ------------------------------------------------------------
        apb_write(32'h0000_0020, 32'h0000_3000); // CH1 SRC
        apb_write(32'h0000_0024, 32'h0000_4000); // CH1 DST
        apb_write(32'h0000_0028, 32'h0000_0000); // CH1 LEN invalid
        apb_write(32'h0000_002c, 32'h0000_0001); // CH1 START

        apb_read_check(32'h0000_0030, 32'h0000_0004); // CH1 ERROR

        if (fatal_irq !== 1'b1) begin
            $display("fatal_irq should remain set after CH1 ERROR");
            $fatal;
        end

        // ------------------------------------------------------------
        // Clear CH0 ERROR only. fatal_irq must remain asserted because
        // CH1 still has ERROR.
        // ------------------------------------------------------------
        apb_write(32'h0000_000c, 32'h0000_0004); // CH0 CLEAR_ERROR

        apb_read_check(32'h0000_0010, 32'h0000_0000); // CH0 clear
        apb_read_check(32'h0000_0030, 32'h0000_0004); // CH1 still ERROR

        if (fatal_irq !== 1'b1) begin
            $display("fatal_irq should remain set while CH1 ERROR is still active");
            $fatal;
        end

        // ------------------------------------------------------------
        // Clear CH1 ERROR. Now fatal_irq should deassert.
        // ------------------------------------------------------------
        apb_write(32'h0000_002c, 32'h0000_0004); // CH1 CLEAR_ERROR

        apb_read_check(32'h0000_0030, 32'h0000_0000); // CH1 clear

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should clear after all ERROR bits are cleared");
            $fatal;
        end

        $display("TEST PASS: multi-error fatal_irq clear behavior");
    end
endtask