task run_partial_wstrb_csr_case;
    input [DATA_WIDTH-1:0] len_bytes;
    input integer          beats;
    input [STRB_WIDTH-1:0] beat0_strb;
    input [STRB_WIDTH-1:0] beat1_strb;
    begin
        reset_dut();

        apb_write(32'h0000_0000, 32'h0000_5000); // CH0 SRC, aligned
        apb_write(32'h0000_0004, 32'h0000_6000); // CH0 DST, aligned
        apb_write(32'h0000_0008, len_bytes);     // CH0 LEN, may be partial
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_5000);
        drive_axi_read_data(32'haa55_0000 | len_bytes, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_6000);
        expect_axi_write_data_strobe(32'haa55_0000 | len_bytes, beat0_strb);
        drive_axi_write_resp(2'b00);

        if (beats == 2) begin
            expect_axi_read_addr(32'h0000_5004);
            drive_axi_read_data(32'h55aa_0000 | len_bytes, 2'b00, 1'b1);
            expect_axi_write_addr(32'h0000_6004);
            expect_axi_write_data_strobe(32'h55aa_0000 | len_bytes, beat1_strb);
            drive_axi_write_resp(2'b00);
        end

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE

        if (irq_done !== 8'b0000_0001) begin
            $display("irq_done mismatch exp=0x01 got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 for partial WSTRB CSR transfer");
            $fatal;
        end
    end
endtask

task run_partial_wstrb_desc_case;
    begin
        reset_dut();

        // CH0 descriptor slot0, LEN=6.  This proves descriptor-backed
        // transfers use the same partial-final-beat WSTRB behavior.
        apb_write(32'h0000_1000, 32'h0000_7000); // DESC SRC, aligned
        apb_write(32'h0000_1004, 32'h0000_8000); // DESC DST, aligned
        apb_write(32'h0000_1008, 32'h0000_0006); // DESC LEN = 6 bytes
        apb_write(32'h0000_100c, 32'h0000_0001); // DESC CTRL/STATUS
        apb_write(32'h0000_000c, 32'h0000_0008); // CH0 DESC_DOORBELL

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_7000);
        drive_axi_read_data(32'hcafe_0000, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_8000);
        expect_axi_write_data_strobe(32'hcafe_0000, 4'b1111);
        drive_axi_write_resp(2'b00);

        expect_axi_read_addr(32'h0000_7004);
        drive_axi_read_data(32'hcafe_0001, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_8004);
        expect_axi_write_data_strobe(32'hcafe_0001, 4'b0011);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
        apb_read_check(32'h0000_001c, 32'h0000_0005); // HEAD=1, TAIL=1, COUNT=0

        if (irq_done !== 8'b0000_0001) begin
            $display("irq_done mismatch exp=0x01 got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 for partial WSTRB descriptor transfer");
            $fatal;
        end
    end
endtask

task test_partial_wstrb_aligned;
    begin
        $display("TEST: partial final beat aligned WSTRB");

        run_partial_wstrb_csr_case(32'h0000_0001, 1, 4'b0001, 4'b0000);
        run_partial_wstrb_csr_case(32'h0000_0002, 1, 4'b0011, 4'b0000);
        run_partial_wstrb_csr_case(32'h0000_0003, 1, 4'b0111, 4'b0000);
        run_partial_wstrb_csr_case(32'h0000_0006, 2, 4'b1111, 4'b0011);
        run_partial_wstrb_desc_case();

        $display("TEST PASS: partial final beat aligned WSTRB");
    end
endtask
