task test_desc_single_exec;
    reg [ADDR_WIDTH-1:0] ch0_csr_base;
    reg [ADDR_WIDTH-1:0] ch0_desc_base;
    begin
        $display("TEST: descriptor single execution");

        ch0_csr_base  = 32'h0000_0000;
        ch0_desc_base = 32'h0000_1000;

        // Program CH0 slot0 descriptor and ring doorbell.
        apb_write(ch0_desc_base + 32'h0, 32'h0000_1000); // SRC
        apb_write(ch0_desc_base + 32'h4, 32'h0000_2000); // DST
        apb_write(ch0_desc_base + 32'h8, 32'h0000_0004); // LEN = one word
        apb_write(ch0_desc_base + 32'hc, 32'h0000_0001); // CTRL/STATUS valid marker
        apb_write(ch0_csr_base  + 32'hc, 32'h0000_0008); // CTRL[3] DESC_DOORBELL

        apb_read_check(ch0_csr_base + 32'h10, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_1000);
        drive_axi_read_data(32'hd00d_0001, 2'b00, 1'b1);

        expect_axi_write_addr(32'h0000_2000);
        expect_axi_write_data(32'hd00d_0001);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(ch0_csr_base + 32'h10, 32'h0000_0002); // DONE
        apb_read_check(ch0_csr_base + 32'h14, 32'h0000_0001); // HEAD advanced to 1
        apb_read_check(ch0_csr_base + 32'h18, 32'h0000_0001); // TAIL is 1
        apb_read_check(ch0_csr_base + 32'h1c, 32'h0000_0005); // HEAD=1, TAIL=1, COUNT=0

        if (irq_done !== 8'h01) begin
            $display("irq_done mismatch exp=0x01 got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 for descriptor single execution");
            $fatal;
        end

        $display("TEST PASS: descriptor single execution");
    end
endtask
