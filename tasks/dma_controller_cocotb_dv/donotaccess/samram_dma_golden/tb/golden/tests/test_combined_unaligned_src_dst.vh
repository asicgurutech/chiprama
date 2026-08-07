task run_combined_unaligned_csr_multi_boundary_case;
    begin
        reset_dut();

        // Combined unaligned SRC and DST with arbitrary LEN=5.
        //
        // SRC=0xb001 gives 3 valid bytes from first source word:
        //   read 0xb000 data a1_b2_c3_d4 -> bytes c3, b2, a1
        // DST=0xc002 can accept only 2 bytes in first destination word,
        // so the first source word is split into two writes.  The remaining
        // two transfer bytes come from the next aligned source read.
        apb_write(32'h0000_0000, 32'h0000_b001); // CH0 SRC unaligned +1
        apb_write(32'h0000_0004, 32'h0000_c002); // CH0 DST unaligned +2
        apb_write(32'h0000_0008, 32'h0000_0005); // CH0 LEN = 5 bytes
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_b000);
        drive_axi_read_data(32'ha1b2_c3d4, 2'b00, 1'b1);

        expect_axi_write_addr(32'h0000_c002);
        expect_axi_write_data_strobe(32'hb2c3_0000, 4'b1100);
        drive_axi_write_resp(2'b00);

        expect_axi_write_addr(32'h0000_c004);
        expect_axi_write_data_strobe(32'h0000_00a1, 4'b0001);
        drive_axi_write_resp(2'b00);

        expect_axi_read_addr(32'h0000_b004);
        drive_axi_read_data(32'h1122_3344, 2'b00, 1'b1);

        expect_axi_write_addr(32'h0000_c005);
        expect_axi_write_data_strobe(32'h0033_4400, 4'b0110);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
        if (irq_done[0] !== 1'b1) begin
            $display("irq_done[0] should assert after combined unaligned CSR transfer");
            $fatal;
        end
        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain clear after combined unaligned CSR transfer");
            $fatal;
        end
    end
endtask

task run_combined_unaligned_desc_boundary_case;
    begin
        reset_dut();

        // Descriptor-backed combined unaligned case.
        // SRC offset 3 contributes one byte from the first source word,
        // then three bytes from the next source word.  DST offset 3 forces
        // the first byte into lane 3 and the remaining bytes into lanes [2:0]
        // of the next destination word.
        apb_write(32'h0000_1000, 32'h0000_d003); // DESC SRC unaligned +3
        apb_write(32'h0000_1004, 32'h0000_e003); // DESC DST unaligned +3
        apb_write(32'h0000_1008, 32'h0000_0004); // DESC LEN = 4 bytes
        apb_write(32'h0000_100c, 32'h0000_0001); // DESC CTRL/STATUS
        apb_write(32'h0000_000c, 32'h0000_0008); // CH0 DESC_DOORBELL

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_d000);
        drive_axi_read_data(32'haabb_ccdd, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_e003);
        expect_axi_write_data_strobe(32'haa00_0000, 4'b1000);
        drive_axi_write_resp(2'b00);

        expect_axi_read_addr(32'h0000_d004);
        drive_axi_read_data(32'h1122_3344, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_e004);
        expect_axi_write_data_strobe(32'h0022_3344, 4'b0111);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
        apb_read_check(32'h0000_001c, 32'h0000_0005); // HEAD=1, TAIL=1, COUNT=0
        if (irq_done[0] !== 1'b1) begin
            $display("irq_done[0] should assert after combined unaligned descriptor transfer");
            $fatal;
        end
        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain clear after combined unaligned descriptor transfer");
            $fatal;
        end
    end
endtask

task run_combined_unaligned_short_byte_cases;
    begin
        reset_dut();

        // One-byte transfer with both SRC and DST unaligned.
        apb_write(32'h0000_0000, 32'h0000_f002); // CH0 SRC unaligned +2
        apb_write(32'h0000_0004, 32'h0000_f103); // CH0 DST unaligned +3
        apb_write(32'h0000_0008, 32'h0000_0001); // CH0 LEN = 1 byte
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_f000);
        drive_axi_read_data(32'h5566_7788, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_f103);
        expect_axi_write_data_strobe(32'h6600_0000, 4'b1000);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
    end
endtask

task test_combined_unaligned_src_dst;
    begin
        $display("TEST: combined unaligned source/destination arbitrary length");

        run_combined_unaligned_csr_multi_boundary_case();
        run_combined_unaligned_desc_boundary_case();
        run_combined_unaligned_short_byte_cases();

        $display("TEST PASS: combined unaligned source/destination arbitrary length");
    end
endtask
