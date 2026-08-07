//------------------------------------------------------------------------------
//  SAMRAM LLC
//------------------------------------------------------------------------------
// Project     : Chiparama HUD Benchmark Task
// File        : samram_dma_funcs.vh
// Prepared by : SAMRAM LLC for Chiparama LLC
// Description : Shared helper functions for APB strobe merge, bus alignment,
//               WSTRB generation, source/destination byte shifting, and final
//               beat masking for the SAMRAM DMA benchmark block.
//
// Confidentiality:
//   Proprietary and confidential. Use only as authorized under the applicable
//   project agreement.
//------------------------------------------------------------------------------

`ifndef SAMRAM_DMA_FUNCS_VH
`define SAMRAM_DMA_FUNCS_VH

// This file is intended to be included inside a module that defines
// ADDR_WIDTH, DATA_WIDTH, STRB_WIDTH, and BUS_BYTES_VALUE.

function [DATA_WIDTH-1:0] apply_pstrb;
    input [DATA_WIDTH-1:0] old_data;
    input [DATA_WIDTH-1:0] new_data;
    input [STRB_WIDTH-1:0] strb;
    integer byte_idx;
    begin
        apply_pstrb = old_data;
        for (byte_idx = 0; byte_idx < STRB_WIDTH; byte_idx = byte_idx + 1) begin
            if (strb[byte_idx]) begin
                apply_pstrb[byte_idx*8 +: 8] = new_data[byte_idx*8 +: 8];
            end
        end
    end
endfunction

function is_bus_aligned;
    input [ADDR_WIDTH-1:0] value;
    begin
        case (STRB_WIDTH)
            1:  is_bus_aligned = 1'b1;
            2:  is_bus_aligned = (value[0]   == 1'b0);
            4:  is_bus_aligned = (value[1:0] == 2'b00);
            8:  is_bus_aligned = (value[2:0] == 3'b000);
            16: is_bus_aligned = (value[3:0] == 4'b0000);
            32: is_bus_aligned = (value[4:0] == 5'b00000);
            default: is_bus_aligned = 1'b0;
        endcase
    end
endfunction

function [STRB_WIDTH-1:0] len_to_wstrb;
    input [DATA_WIDTH-1:0] len_bytes;
    integer strobe_idx;
    begin
        len_to_wstrb = {STRB_WIDTH{1'b0}};
        for (strobe_idx = 0; strobe_idx < STRB_WIDTH; strobe_idx = strobe_idx + 1) begin
            if (len_bytes > strobe_idx[DATA_WIDTH-1:0]) begin
                len_to_wstrb[strobe_idx] = 1'b1;
            end
        end
    end
endfunction

function [DATA_WIDTH-1:0] addr_byte_offset;
    input [ADDR_WIDTH-1:0] addr;
    begin
        addr_byte_offset = {DATA_WIDTH{1'b0}};
        case (STRB_WIDTH)
            1:  addr_byte_offset = {DATA_WIDTH{1'b0}};
            2:  addr_byte_offset[0]   = addr[0];
            4:  addr_byte_offset[1:0] = addr[1:0];
            8:  addr_byte_offset[2:0] = addr[2:0];
            16: addr_byte_offset[3:0] = addr[3:0];
            32: addr_byte_offset[4:0] = addr[4:0];
            default: addr_byte_offset = {DATA_WIDTH{1'b0}};
        endcase
    end
endfunction

function [ADDR_WIDTH-1:0] src_aligned_addr;
    input [ADDR_WIDTH-1:0] addr;
    begin
        case (STRB_WIDTH)
            1:  src_aligned_addr = addr;
            2:  src_aligned_addr = {addr[ADDR_WIDTH-1:1], 1'b0};
            4:  src_aligned_addr = {addr[ADDR_WIDTH-1:2], 2'b00};
            8:  src_aligned_addr = {addr[ADDR_WIDTH-1:3], 3'b000};
            16: src_aligned_addr = {addr[ADDR_WIDTH-1:4], 4'b0000};
            32: src_aligned_addr = {addr[ADDR_WIDTH-1:5], 5'b00000};
            default: src_aligned_addr = addr;
        endcase
    end
endfunction

function [DATA_WIDTH-1:0] src_read_bytes;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] len_left;
    reg [DATA_WIDTH-1:0] offset;
    reg [DATA_WIDTH-1:0] capacity;
    begin
        offset   = addr_byte_offset(addr);
        capacity = BUS_BYTES_VALUE - offset;
        if (len_left < capacity) begin
            src_read_bytes = len_left;
        end else begin
            src_read_bytes = capacity;
        end
    end
endfunction

function [DATA_WIDTH-1:0] src_shift_rdata;
    input [DATA_WIDTH-1:0] data;
    input [ADDR_WIDTH-1:0] addr;
    reg [DATA_WIDTH-1:0] shift_bits;
    begin
        shift_bits      = addr_byte_offset(addr) * 8;
        src_shift_rdata = data >> shift_bits;
    end
endfunction

function [DATA_WIDTH-1:0] dst_write_bytes;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] valid_bytes;
    reg [DATA_WIDTH-1:0] offset;
    reg [DATA_WIDTH-1:0] capacity;
    begin
        offset   = addr_byte_offset(addr);
        capacity = BUS_BYTES_VALUE - offset;
        if (valid_bytes < capacity) begin
            dst_write_bytes = valid_bytes;
        end else begin
            dst_write_bytes = capacity;
        end
    end
endfunction

function [STRB_WIDTH-1:0] dst_wstrb;
    input [ADDR_WIDTH-1:0] addr;
    input [DATA_WIDTH-1:0] valid_bytes;
    reg [DATA_WIDTH-1:0] offset;
    reg [DATA_WIDTH-1:0] byte_count;
    integer strobe_idx;
    begin
        offset     = addr_byte_offset(addr);
        byte_count = dst_write_bytes(addr, valid_bytes);
        dst_wstrb  = {STRB_WIDTH{1'b0}};

        for (strobe_idx = 0; strobe_idx < STRB_WIDTH; strobe_idx = strobe_idx + 1) begin
            if ((strobe_idx[DATA_WIDTH-1:0] >= offset) &&
                (strobe_idx[DATA_WIDTH-1:0] < (offset + byte_count))) begin
                dst_wstrb[strobe_idx] = 1'b1;
            end
        end
    end
endfunction

function [DATA_WIDTH-1:0] dst_shift_wdata;
    input [DATA_WIDTH-1:0] data;
    input [ADDR_WIDTH-1:0] addr;
    reg [DATA_WIDTH-1:0] shift_bits;
    begin
        shift_bits      = addr_byte_offset(addr) * 8;
        dst_shift_wdata = data << shift_bits;
    end
endfunction

function [DATA_WIDTH-1:0] mask_wdata_by_strb;
    input [DATA_WIDTH-1:0] data;
    input [STRB_WIDTH-1:0] strb;
    integer mask_idx;
    begin
        mask_wdata_by_strb = {DATA_WIDTH{1'b0}};
        for (mask_idx = 0; mask_idx < STRB_WIDTH; mask_idx = mask_idx + 1) begin
            if (strb[mask_idx]) begin
                mask_wdata_by_strb[(mask_idx*8) +: 8] = data[(mask_idx*8) +: 8];
            end
        end
    end
endfunction

`endif // SAMRAM_DMA_FUNCS_VH
