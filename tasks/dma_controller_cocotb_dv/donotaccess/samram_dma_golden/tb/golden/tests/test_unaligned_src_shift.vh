task run_unaligned_src_csr_single_read_case;
    begin
        reset_dut();

        // SRC byte-offset 1.  ARADDR must align down to 0x9000 and
        // the write data should contain source bytes [9001:9003]
        // packed into destination lanes [2:0].
        apb_write(32'h0000_0000, 32'h0000_9001); // CH0 SRC unaligned +1
        apb_write(32'h0000_0004, 32'h0000_a000); // CH0 DST aligned
        apb_write(32'h0000_0008, 32'h0000_0003); // CH0 LEN = 3 bytes
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_9000);
        drive_axi_read_data(32'h1122_3344, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_a000);
        expect_axi_write_data_strobe(32'h0011_2233, 4'b0111);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
    end
endtask

task run_unaligned_src_csr_cross_read_case;
    begin
        reset_dut();

        // SRC byte-offset 3.  First aligned read contributes only one
        // valid byte, then the next source word contributes the remaining
        // two bytes.  The destination address advances by byte count.
        apb_write(32'h0000_0000, 32'h0000_9103); // CH0 SRC unaligned +3
        apb_write(32'h0000_0004, 32'h0000_a100); // CH0 DST aligned
        apb_write(32'h0000_0008, 32'h0000_0003); // CH0 LEN = 3 bytes
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_9100);
        drive_axi_read_data(32'ha1b2_c3d4, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_a100);
        expect_axi_write_data_strobe(32'h0000_00a1, 4'b0001);
        drive_axi_write_resp(2'b00);

        expect_axi_read_addr(32'h0000_9104);
        drive_axi_read_data(32'h5566_7788, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_a101);
        expect_axi_write_data_strobe(32'h0077_8800, 4'b0110);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
    end
endtask

task run_unaligned_src_desc_case;
    begin
        reset_dut();

        // Descriptor-backed unaligned source.  Descriptor fetch should accept
        // the unaligned source, align ARADDR down, and shift RDATA.
        apb_write(32'h0000_1000, 32'h0000_9202); // DESC SRC unaligned +2
        apb_write(32'h0000_1004, 32'h0000_a200); // DESC DST aligned
        apb_write(32'h0000_1008, 32'h0000_0002); // DESC LEN = 2 bytes
        apb_write(32'h0000_100c, 32'h0000_0001); // DESC CTRL/STATUS
        apb_write(32'h0000_000c, 32'h0000_0008); // CH0 DESC_DOORBELL

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        expect_axi_read_addr(32'h0000_9200);
        drive_axi_read_data(32'haabb_ccdd, 2'b00, 1'b1);
        expect_axi_write_addr(32'h0000_a200);
        expect_axi_write_data_strobe(32'h0000_aabb, 4'b0011);
        drive_axi_write_resp(2'b00);

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE
        apb_read_check(32'h0000_001c, 32'h0000_0005); // HEAD=1, TAIL=1, COUNT=0
    end
endtask

task test_unaligned_src_shift;
    begin
        $display("TEST: unaligned source read alignment and data shift");

        run_unaligned_src_csr_single_read_case();
        run_unaligned_src_csr_cross_read_case();
        run_unaligned_src_desc_case();

        $display("TEST PASS: unaligned source read alignment and data shift");
    end
endtask
