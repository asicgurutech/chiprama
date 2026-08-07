task test_multi_word;
    integer beat;
    reg [ADDR_WIDTH-1:0] exp_araddr;
    reg [ADDR_WIDTH-1:0] exp_awaddr;
    reg [DATA_WIDTH-1:0] exp_data;
    begin
        $display("TEST: multi-word");

        apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0010); // CH0 LEN = 16 bytes
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // BUSY

        for (beat = 0; beat < 4; beat = beat + 1) begin
            exp_araddr = 32'h0000_1000 + (beat * 4);
            exp_awaddr = 32'h0000_2000 + (beat * 4);
            exp_data   = 32'ha000_0000 + beat;

            expect_axi_read_addr(exp_araddr);
            drive_axi_read_data(exp_data, 2'b00, 1'b1);
            expect_axi_write_addr(exp_awaddr);
            expect_axi_write_data(exp_data);
            drive_axi_write_resp(2'b00);
        end

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // DONE

        if (irq_done !== 8'b0000_0001) begin
            $display("irq_done mismatch exp=0x01 got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 for successful multi-word transfer");
            $fatal;
        end

        $display("TEST PASS: multi-word");
    end
endtask
