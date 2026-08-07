# SPDX-License-Identifier: MIT
"""cocotbext-axi smoke tests for samram_dma_top.

These tests intentionally sit outside the default Verilog regression.  They use
cocotbext-axi as an AXI slave memory model so the DUT drives a real AXI master
interface instead of the hand-written Verilog task model.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout
from cocotbext.axi import AxiBus, AxiRam

CLK_PERIOD_NS = 10

REG_SRC_ADDR = 0x00
REG_DST_ADDR = 0x04
REG_LEN_BYTES = 0x08
REG_CTRL = 0x0C
REG_STATUS = 0x10
REG_DESC_TAIL = 0x18

CTRL_START = 0x1
CTRL_DESC_DOORBELL = 0x8
STATUS_DONE = 0x2
STATUS_ERROR = 0x4

DESC_BASE = 0x1000
DESC_SLOT_STRIDE = 0x10
DESC_CH_STRIDE = 0x40
DESC_WORD_SRC = 0x0
DESC_WORD_DST = 0x4
DESC_WORD_LEN = 0x8
DESC_WORD_CTRL_STATUS = 0xC


def ch_base(ch: int) -> int:
    return ch * 0x20


def desc_addr(ch: int, slot: int, word_offset: int) -> int:
    return DESC_BASE + ch * DESC_CH_STRIDE + slot * DESC_SLOT_STRIDE + word_offset


async def init_dut(dut):
    """Start clock, initialize APB controls, and reset DUT."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())

    dut.s_apb_paddr.value = 0
    dut.s_apb_psel.value = 0
    dut.s_apb_penable.value = 0
    dut.s_apb_pwrite.value = 0
    dut.s_apb_pwdata.value = 0
    dut.s_apb_pstrb.value = 0

    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)


async def apb_write(dut, addr: int, data: int, strb: int = 0xF):
    await RisingEdge(dut.clk)
    dut.s_apb_paddr.value = addr
    dut.s_apb_pwdata.value = data
    dut.s_apb_pstrb.value = strb
    dut.s_apb_pwrite.value = 1
    dut.s_apb_psel.value = 1
    dut.s_apb_penable.value = 0

    await RisingEdge(dut.clk)
    dut.s_apb_penable.value = 1

    await Timer(1, units="ns")
    assert int(dut.s_apb_pready.value) == 1, f"APB write addr=0x{addr:08x} did not return PREADY"
    assert int(dut.s_apb_pslverr.value) == 0, f"APB write addr=0x{addr:08x} returned PSLVERR"

    await RisingEdge(dut.clk)
    dut.s_apb_psel.value = 0
    dut.s_apb_penable.value = 0
    dut.s_apb_pwrite.value = 0
    dut.s_apb_pwdata.value = 0
    dut.s_apb_pstrb.value = 0


async def apb_read(dut, addr: int) -> int:
    await RisingEdge(dut.clk)
    dut.s_apb_paddr.value = addr
    dut.s_apb_pwdata.value = 0
    dut.s_apb_pstrb.value = 0xF
    dut.s_apb_pwrite.value = 0
    dut.s_apb_psel.value = 1
    dut.s_apb_penable.value = 0

    await RisingEdge(dut.clk)
    dut.s_apb_penable.value = 1

    await Timer(1, units="ns")
    assert int(dut.s_apb_pready.value) == 1, f"APB read addr=0x{addr:08x} did not return PREADY"
    assert int(dut.s_apb_pslverr.value) == 0, f"APB read addr=0x{addr:08x} returned PSLVERR"
    value = int(dut.s_apb_prdata.value)

    await RisingEdge(dut.clk)
    dut.s_apb_psel.value = 0
    dut.s_apb_penable.value = 0
    return value


async def wait_done(dut, ch: int, timeout_cycles: int = 500):
    mask = 1 << ch
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if int(dut.irq_done.value) & mask:
            return
    raise AssertionError(f"timeout waiting for irq_done[{ch}]")


async def wait_status_done(dut, ch: int, timeout_cycles: int = 500):
    for _ in range(timeout_cycles):
        status = await apb_read(dut, ch_base(ch) + REG_STATUS)
        if status & STATUS_DONE:
            assert (status & STATUS_ERROR) == 0, f"CH{ch} completed with ERROR status=0x{status:08x}"
            return status
    raise AssertionError(f"timeout waiting for CH{ch} STATUS.DONE")


@cocotb.test()
async def test_axi_vip_csr_unaligned_copy(dut):
    """CSR-backed unaligned copy through cocotbext-axi AxiRam."""
    await init_dut(dut)

    axi_ram = AxiRam(
        AxiBus.from_prefix(dut, "m_axi"),
        dut.clk,
        dut.rst_n,
        reset_active_level=False,
        size=2**16,
    )

    src_addr = 0x1003
    dst_addr = 0x2001
    payload = bytes([0x10, 0x21, 0x32, 0x43, 0x54, 0x65, 0x76, 0x87, 0x98])
    sentinel = bytes([0xA5] * 24)

    axi_ram.write(dst_addr - 4, sentinel)
    axi_ram.write(src_addr, payload)

    await apb_write(dut, ch_base(0) + REG_SRC_ADDR, src_addr)
    await apb_write(dut, ch_base(0) + REG_DST_ADDR, dst_addr)
    await apb_write(dut, ch_base(0) + REG_LEN_BYTES, len(payload))
    await apb_write(dut, ch_base(0) + REG_CTRL, CTRL_START)

    await with_timeout(wait_done(dut, 0), 10_000, "ns")
    status = await apb_read(dut, ch_base(0) + REG_STATUS)
    assert status & STATUS_DONE, f"CH0 did not report DONE, status=0x{status:08x}"
    assert not (status & STATUS_ERROR), f"CH0 reported ERROR, status=0x{status:08x}"

    got = bytes(axi_ram.read(dst_addr, len(payload)))
    assert got == payload, f"CSR AXI RAM copy mismatch exp={payload.hex()} got={got.hex()}"

    before = bytes(axi_ram.read(dst_addr - 1, 1))
    after = bytes(axi_ram.read(dst_addr + len(payload), 1))
    assert before == bytes([0xA5]), f"byte before destination was corrupted: {before.hex()}"
    assert after == bytes([0xA5]), f"byte after destination was corrupted: {after.hex()}"


@cocotb.test()
async def test_axi_vip_descriptor_copy(dut):
    """Descriptor-backed copy through cocotbext-axi AxiRam."""
    await init_dut(dut)

    axi_ram = AxiRam(
        AxiBus.from_prefix(dut, "m_axi"),
        dut.clk,
        dut.rst_n,
        reset_active_level=False,
        size=2**16,
    )

    src_addr = 0x3102
    dst_addr = 0x4103
    payload = bytes([0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6])

    axi_ram.write(dst_addr - 4, bytes([0x5A] * 24))
    axi_ram.write(src_addr, payload)

    await apb_write(dut, desc_addr(1, 0, DESC_WORD_SRC), src_addr)
    await apb_write(dut, desc_addr(1, 0, DESC_WORD_DST), dst_addr)
    await apb_write(dut, desc_addr(1, 0, DESC_WORD_LEN), len(payload))
    await apb_write(dut, desc_addr(1, 0, DESC_WORD_CTRL_STATUS), 1)
    await apb_write(dut, ch_base(1) + REG_DESC_TAIL, 1)
    await apb_write(dut, ch_base(1) + REG_CTRL, CTRL_DESC_DOORBELL)

    await with_timeout(wait_done(dut, 1), 10_000, "ns")
    status = await apb_read(dut, ch_base(1) + REG_STATUS)
    assert status & STATUS_DONE, f"CH1 did not report DONE, status=0x{status:08x}"
    assert not (status & STATUS_ERROR), f"CH1 reported ERROR, status=0x{status:08x}"

    got = bytes(axi_ram.read(dst_addr, len(payload)))
    assert got == payload, f"descriptor AXI RAM copy mismatch exp={payload.hex()} got={got.hex()}"
