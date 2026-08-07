task run_unaligned_dst_csr_fit_case;
    begin
        reset_dut();

        // SRC is aligned.  DST is byte-offset 1.  LEN=3 fits in one
        // destination beat and should use lanes [3:1].
        apb_write(32'h0000_0000, 32'h0000_5000); // CH0 SRC aligned
        apb_write(32'h0000_0004, 32'h0000_6001); // CH0 DST unaligned +1
        apb_write(32'h0000_0008, 32'h0000_0003); // CH0 LEN = 3 bytes
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_5000);
        drive_axi_read_data(32'h00bb_ccdd, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_6001);
        expect_axi_write_data_strobe(32'hbbcc_dd00, 4'b1110);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
    end
endtask

task run_unaligned_dst_csr_cross_case;
    begin
        reset_dut();

        // DST is byte-offset 1.  LEN=4 crosses the destination aligned
        // word boundary.  One source word is split into two writes.
        apb_write(32'h0000_0000, 32'h0000_5100); // CH0 SRC aligned
        apb_write(32'h0000_0004, 32'h0000_6101); // CH0 DST unaligned +1
        apb_write(32'h0000_0008, 32'h0000_0004); // CH0 LEN = 4 bytes
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_5100);
        drive_axi_read_data(32'h1122_3344, 2'b00, 1'b1);

        expect_axi_write_addr(32'h0000_6101);
        expect_axi_write_data_strobe(32'h2233_4400, 4'b1110);
        drive_axi_write_resp(2'b00);

        expect_axi_write_addr(32'h0000_6104);
        expect_axi_write_data_strobe(32'h0000_0011, 4'b0001);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
    end
endtask

task run_unaligned_dst_csr_multiread_case;
    begin
        reset_dut();

        // DST is byte-offset 2.  LEN=6 uses two source reads and three
        // destination writes: 2 bytes, 2 bytes, then 2 bytes.
        apb_write(32'h0000_0000, 32'h0000_5200); // CH0 SRC aligned
        apb_write(32'h0000_0004, 32'h0000_6202); // CH0 DST unaligned +2
        apb_write(32'h0000_0008, 32'h0000_0006); // CH0 LEN = 6 bytes
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_5200);
        drive_axi_read_data(32'ha1b2_c3d4, 2'b00, 1'b1);

        expect_axi_write_addr(32'h0000_6202);
        expect_axi_write_data_strobe(32'hc3d4_0000, 4'b1100);
        drive_axi_write_resp(2'b00);

        expect_axi_write_addr(32'h0000_6204);
        expect_axi_write_data_strobe(32'h0000_a1b2, 4'b0011);
        drive_axi_write_resp(2'b00);

        expect_axi_read_addr(32'h0000_5204);
        drive_axi_read_data(32'h5566_7788, 2'b00, 1'b1);

        expect_axi_write_addr(32'h0000_6206);
        expect_axi_write_data_strobe(32'h7788_0000, 4'b1100);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
    end
endtask

task run_unaligned_dst_desc_case;
    begin
        reset_dut();

        // Descriptor-backed version of the boundary-crossing case.
        apb_write(32'h0000_1000, 32'h0000_7000); // DESC SRC aligned
        apb_write(32'h0000_1004, 32'h0000_8001); // DESC DST unaligned +1
        apb_write(32'h0000_1008, 32'h0000_0004); // DESC LEN = 4 bytes
        apb_write(32'h0000_100c, 32'h0000_0001); // DESC CTRL/STATUS
        apb_write(32'h0000_000c, 32'h0000_0008); // CH0 DESC_DOORBELL

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_7000);
        drive_axi_read_data(32'h0102_0304, 2'b00, 1'b1);

        expect_axi_write_addr(32'h0000_8001);
        expect_axi_write_data_strobe(32'h0203_0400, 4'b1110);
        drive_axi_write_resp(2'b00);

        expect_axi_write_addr(32'h0000_8004);
        expect_axi_write_data_strobe(32'h0000_0001, 4'b0001);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
        apb_read_check(32'h0000_001c, 32'h0000_0005); // HEAD=1, TAIL=1, COUNT=0
    end
endtask

task run_unaligned_src_now_supported_case;
    begin
        reset_dut();

        // M16C supports unaligned source.  With SRC byte-offset 1 and
        // DST byte-offset 1, the source read is aligned down and the
        // returned data is shifted before destination-lane placement.
        apb_write(32'h0000_0000, 32'h0000_9001); // CH0 SRC unaligned +1
        apb_write(32'h0000_0004, 32'h0000_a001); // CH0 DST unaligned +1
        apb_write(32'h0000_0008, 32'h0000_0001); // CH0 LEN = 1 byte
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_9000);
        drive_axi_read_data(32'h1122_3344, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_a001);
        expect_axi_write_data_strobe(32'h0000_3300, 4'b0010);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
    end
endtask

task test_unaligned_dst_wstrb;
    begin
        $display("TEST: unaligned destination WSTRB/data alignment");

        run_unaligned_dst_csr_fit_case();
        run_unaligned_dst_csr_cross_case();
        run_unaligned_dst_csr_multiread_case();
        run_unaligned_dst_desc_case();
        run_unaligned_src_now_supported_case();

        $display("TEST PASS: unaligned destination WSTRB/data alignment");
    end
endtask
