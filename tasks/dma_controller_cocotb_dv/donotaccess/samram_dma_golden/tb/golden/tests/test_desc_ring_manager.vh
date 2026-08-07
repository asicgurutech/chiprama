task test_desc_ring_manager;
    reg [ADDR_WIDTH-1:0] ch2_csr_base;
    reg [ADDR_WIDTH-1:0] ch2_desc_base;
    reg [ADDR_WIDTH-1:0] ch3_csr_base;
    reg [ADDR_WIDTH-1:0] ch3_desc_base;
    begin
        $display("TEST: descriptor ring manager CSRs");

        ch2_csr_base  = 32'h0000_0040; // CH2 CSR base = 2 * 0x20
        ch2_desc_base = 32'h0000_1000 + (2 * 32'h0000_0040); // CH2 slot0 descriptor base
        ch3_csr_base  = 32'h0000_0060; // CH3 CSR base = 3 * 0x20
        ch3_desc_base = 32'h0000_1000 + (3 * 32'h0000_0040); // CH3 slot0 descriptor base

        // Reset state: HEAD=0, TAIL=0, COUNT=0, READY=0, FULL=0.
        apb_read_check(ch2_csr_base + 32'h0000_0014, 32'h0000_0000); // DESC_HEAD
        apb_read_check(ch2_csr_base + 32'h0000_0018, 32'h0000_0000); // DESC_TAIL
        apb_read_check(ch2_csr_base + 32'h0000_001c, 32'h0000_0000); // DESC_RING_STATUS

        // Program CH2 descriptor slot0, then ring doorbell once.
        // With descriptor execution connected, the channel immediately wins
        // arbitration while the AXI interface is held stalled. The descriptor is
        // sampled into working registers at grant time, so HEAD advances and
        // COUNT drops back to 0 while CH2 remains BUSY.
        apb_write(ch2_desc_base + 32'h0, 32'h0000_3200); // SRC
        apb_write(ch2_desc_base + 32'h4, 32'h0000_4200); // DST
        apb_write(ch2_desc_base + 32'h8, 32'h0000_0010); // LEN
        apb_write(ch2_desc_base + 32'hc, 32'h0000_0001); // CTRL/STATUS valid marker

        apb_write(ch2_csr_base + 32'h0000_000c, 32'h0000_0008); // CTRL[3] DESC_DOORBELL
        repeat (2) @(posedge clk);

        apb_read_check(ch2_csr_base + 32'h0000_000c, 32'h0000_0000); // CTRL command bits self-clear
        apb_read_check(ch2_csr_base + 32'h0000_0010, 32'h0000_0001); // CH2 BUSY
        apb_read_check(ch2_csr_base + 32'h0000_0014, 32'h0000_0001); // HEAD=1, descriptor fetched
        apb_read_check(ch2_csr_base + 32'h0000_0018, 32'h0000_0001); // TAIL=1
        apb_read_check(ch2_csr_base + 32'h0000_001c, 32'h0000_0005); // HEAD=1, TAIL=1, COUNT=0

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 after valid descriptor doorbell");
            $fatal;
        end

        // Ring CH2 four more times while CH2's current descriptor is still
        // stalled on AXI. These four descriptors remain in the ring.
        apb_write(ch2_csr_base + 32'h0000_000c, 32'h0000_0008);
        apb_write(ch2_csr_base + 32'h0000_000c, 32'h0000_0008);
        apb_write(ch2_csr_base + 32'h0000_000c, 32'h0000_0008);
        apb_write(ch2_csr_base + 32'h0000_000c, 32'h0000_0008);

        apb_read_check(ch2_csr_base + 32'h0000_0014, 32'h0000_0001); // HEAD=1
        apb_read_check(ch2_csr_base + 32'h0000_0018, 32'h0000_0001); // TAIL wrapped back to 1
        apb_read_check(ch2_csr_base + 32'h0000_001c, 32'h0000_0345); // FULL=1, READY=1, COUNT=4, TAIL=1, HEAD=1

        // CH3 ring state should be independent of CH2.
        apb_read_check(ch3_csr_base + 32'h0000_001c, 32'h0000_0000);

        apb_write(ch3_desc_base + 32'h0, 32'h0000_3300); // SRC
        apb_write(ch3_desc_base + 32'h4, 32'h0000_4300); // DST
        apb_write(ch3_desc_base + 32'h8, 32'h0000_0020); // LEN
        apb_write(ch3_desc_base + 32'hc, 32'h0000_0001); // CTRL/STATUS valid marker
        apb_write(ch3_csr_base + 32'h0000_000c, 32'h0000_0008); // CH3 doorbell

        // CH2 is still active/stalled, so CH3 remains queued in the ring.
        apb_read_check(ch3_csr_base + 32'h0000_0014, 32'h0000_0000); // HEAD=0
        apb_read_check(ch3_csr_base + 32'h0000_0018, 32'h0000_0001); // TAIL=1
        apb_read_check(ch3_csr_base + 32'h0000_001c, 32'h0000_0114); // READY=1, COUNT=1, TAIL=1

        // CH2 should still be full and unaffected by CH3 doorbell.
        apb_read_check(ch2_csr_base + 32'h0000_001c, 32'h0000_0345);

        if (fatal_irq !== 1'b0) begin
            $display("fatal_irq should remain 0 during descriptor ring manager test");
            $fatal;
        end

        if (irq_done !== 8'h00) begin
            $display("irq_done should remain 0 because AXI is stalled, got=0x%02x", irq_done);
            $fatal;
        end

        $display("TEST PASS: descriptor ring manager CSRs");
    end
endtask
