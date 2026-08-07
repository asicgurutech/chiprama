task test_desc_sram_apb;
    integer ch;
    reg [ADDR_WIDTH-1:0] desc_base;
    reg [DATA_WIDTH-1:0] exp_src;
    reg [DATA_WIDTH-1:0] exp_dst;
    reg [DATA_WIDTH-1:0] exp_len;
    reg [DATA_WIDTH-1:0] exp_ctrl;
    begin
        $display("TEST: descriptor SRAM APB access");

        // ------------------------------------------------------------
        // Basic CH0 slot0 descriptor write/read.
        // Descriptor address:
        //   0x1000 + ch*0x40 + slot*0x10 + word*0x4
        // ------------------------------------------------------------
        desc_base = 32'h0000_1000;

        apb_write(desc_base + 32'h0, 32'h0000_1000); // SRC
        apb_write(desc_base + 32'h4, 32'h0000_2000); // DST
        apb_write(desc_base + 32'h8, 32'h0000_0040); // LEN
        apb_write(desc_base + 32'hc, 32'h0000_0001); // CTRL/STATUS

        apb_read_check(desc_base + 32'h0, 32'h0000_1000);
        apb_read_check(desc_base + 32'h4, 32'h0000_2000);
        apb_read_check(desc_base + 32'h8, 32'h0000_0040);
        apb_read_check(desc_base + 32'hc, 32'h0000_0001);

        // ------------------------------------------------------------
        // CH3 slot2 descriptor write/read.
        // base = 0x1000 + 3*0x40 + 2*0x10 = 0x10e0
        // ------------------------------------------------------------
        desc_base = 32'h0000_1000 + (3 * 32'h40) + (2 * 32'h10);

        apb_write(desc_base + 32'h0, 32'h0000_3300);
        apb_write(desc_base + 32'h4, 32'h0000_4400);
        apb_write(desc_base + 32'h8, 32'h0000_0080);
        apb_write(desc_base + 32'hc, 32'h0000_00a5);

        apb_read_check(desc_base + 32'h0, 32'h0000_3300);
        apb_read_check(desc_base + 32'h4, 32'h0000_4400);
        apb_read_check(desc_base + 32'h8, 32'h0000_0080);
        apb_read_check(desc_base + 32'hc, 32'h0000_00a5);

        // ------------------------------------------------------------
        // Write slot0 for all 8 channels and verify no cross-channel
        // descriptor corruption.
        // ------------------------------------------------------------
        for (ch = 0; ch < 8; ch = ch + 1) begin
            desc_base = 32'h0000_1000 + (ch * 32'h40);

            exp_src  = 32'h0000_1000 + (ch * 32'h100);
            exp_dst  = 32'h0000_2000 + (ch * 32'h100);
            exp_len  = 32'h0000_0010 + ch;
            exp_ctrl = 32'h0000_0100 + ch;

            apb_write(desc_base + 32'h0, exp_src);
            apb_write(desc_base + 32'h4, exp_dst);
            apb_write(desc_base + 32'h8, exp_len);
            apb_write(desc_base + 32'hc, exp_ctrl);
        end

        for (ch = 0; ch < 8; ch = ch + 1) begin
            desc_base = 32'h0000_1000 + (ch * 32'h40);

            exp_src  = 32'h0000_1000 + (ch * 32'h100);
            exp_dst  = 32'h0000_2000 + (ch * 32'h100);
            exp_len  = 32'h0000_0010 + ch;
            exp_ctrl = 32'h0000_0100 + ch;

            apb_read_check(desc_base + 32'h0, exp_src);
            apb_read_check(desc_base + 32'h4, exp_dst);
            apb_read_check(desc_base + 32'h8, exp_len);
            apb_read_check(desc_base + 32'hc, exp_ctrl);
        end

        $display("TEST PASS: descriptor SRAM APB access");
    end
endtask
