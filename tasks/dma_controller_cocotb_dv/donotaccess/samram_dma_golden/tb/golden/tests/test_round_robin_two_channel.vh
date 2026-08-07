task test_round_robin_two_channel;
    integer beat;
    reg [DATA_WIDTH-1:0] ch0_data;
    reg [DATA_WIDTH-1:0] ch1_data;
    begin
        $display("TEST: round-robin two-channel beat scheduling");

        // CH0: 16-byte transfer
        apb_write(32'h0000_0000, 32'h0000_1000); // CH0 SRC
        apb_write(32'h0000_0004, 32'h0000_2000); // CH0 DST
        apb_write(32'h0000_0008, 32'h0000_0010); // CH0 LEN = 16 bytes
        apb_write(32'h0000_000c, 32'h0000_0001); // CH0 START

        apb_read_check(32'h0000_0010, 32'h0000_0001); // CH0 BUSY

        // Wait for CH0 first AR and leave it unaccepted so CH1 can be queued.
        wait (m_axi_arvalid === 1'b1);
        #1;
        if (m_axi_araddr !== 32'h0000_1000) begin
            $display("Initial CH0 ARADDR mismatch exp=0x00001000 got=0x%08x", m_axi_araddr);
            $fatal;
        end

        // CH1: 16-byte transfer queued behind CH0
        apb_write(32'h0000_0020, 32'h0000_3000); // CH1 SRC
        apb_write(32'h0000_0024, 32'h0000_4000); // CH1 DST
        apb_write(32'h0000_0028, 32'h0000_0010); // CH1 LEN = 16 bytes
        apb_write(32'h0000_002c, 32'h0000_0001); // CH1 START while CH0 active

        apb_read_check(32'h0000_0010, 32'h0000_0001); // CH0 BUSY
        apb_read_check(32'h0000_0030, 32'h0000_0001); // CH1 BUSY / queued

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 after valid CH1 queue");
            $fatal;
        end

        for (beat = 0; beat < 4; beat = beat + 1) begin
            ch0_data = 32'hc000_0000 + beat;
            ch1_data = 32'hd000_0000 + beat;

            // CH0 beat
            expect_axi_read_addr(32'h0000_1000 + (beat * 4));
            drive_axi_read_data(ch0_data, 2'b00, 1'b1);
            expect_axi_write_addr(32'h0000_2000 + (beat * 4));
            expect_axi_write_data(ch0_data);
            drive_axi_write_resp(2'b00);

            // CH1 beat
            expect_axi_read_addr(32'h0000_3000 + (beat * 4));
            drive_axi_read_data(ch1_data, 2'b00, 1'b1);
            expect_axi_write_addr(32'h0000_4000 + (beat * 4));
            expect_axi_write_data(ch1_data);
            drive_axi_write_resp(2'b00);
        end

        repeat (2) @(posedge clk);

        apb_read_check(32'h0000_0010, 32'h0000_0002); // CH0 DONE
        apb_read_check(32'h0000_0030, 32'h0000_0002); // CH1 DONE

        if (irq_done !== 8'b0000_0011) begin
            $display("irq_done mismatch exp=0x03 got=0x%02x", irq_done);
            $fatal;
        end

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 for round-robin two-channel transfer");
            $fatal;
        end

        $display("TEST PASS: round-robin two-channel beat scheduling");
    end
endtask
