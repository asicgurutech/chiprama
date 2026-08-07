# SPDX-License-Identifier: MIT
"""Randomized cocotbext-axi regression tests for samram_dma_top.

These tests are intentionally optional and run outside the default Verilog
regression.  They stress the golden RTL with many byte-offset/length
combinations using cocotbext-axi AxiRam as the AXI slave memory model.
"""

import random

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

CTRL_START = 0x1
CTRL_CLEAR_DONE = 0x2
CTRL_CLEAR_ERROR = 0x4
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
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

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

    await Timer(1, unit="ns")
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

    await Timer(1, unit="ns")
    assert int(dut.s_apb_pready.value) == 1, f"APB read addr=0x{addr:08x} did not return PREADY"
    assert int(dut.s_apb_pslverr.value) == 0, f"APB read addr=0x{addr:08x} returned PSLVERR"
    value = int(dut.s_apb_prdata.value)

    await RisingEdge(dut.clk)
    dut.s_apb_psel.value = 0
    dut.s_apb_penable.value = 0
    return value


async def wait_done(dut, ch: int, timeout_cycles: int = 1000):
    mask = 1 << ch
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if int(dut.irq_done.value) & mask:
            return
    raise AssertionError(f"timeout waiting for irq_done[{ch}]")


async def check_done_status(dut, ch: int):
    status = await apb_read(dut, ch_base(ch) + REG_STATUS)
    assert status & STATUS_DONE, f"CH{ch} did not report DONE, status=0x{status:08x}"
    assert not (status & STATUS_ERROR), f"CH{ch} reported ERROR, status=0x{status:08x}"


async def check_copy_window(axi_ram: AxiRam, dst_addr: int, payload: bytes, sentinel: int, case_name: str):
    got = bytes(axi_ram.read(dst_addr, len(payload)))
    assert got == payload, f"{case_name}: copy mismatch exp={payload.hex()} got={got.hex()}"

    before = bytes(axi_ram.read(dst_addr - 1, 1))
    after = bytes(axi_ram.read(dst_addr + len(payload), 1))
    assert before == bytes([sentinel]), f"{case_name}: byte before destination corrupted: {before.hex()}"
    assert after == bytes([sentinel]), f"{case_name}: byte after destination corrupted: {after.hex()}"


@cocotb.test()
async def test_axi_vip_random_csr_unaligned_copies(dut):
    """Random CSR-backed unaligned SRC/DST/length copies through AxiRam."""
    await init_dut(dut)

    axi_ram = AxiRam(
        AxiBus.from_prefix(dut, "m_axi"),
        dut.clk,
        dut.rst_n,
        reset_active_level=False,
        size=2**18,
    )

    rng = random.Random(0x5A17_C001)

    for case_idx in range(24):
        src_addr = 0x1000 + case_idx * 0x100 + rng.randrange(0, 4)
        dst_addr = 0x9000 + case_idx * 0x100 + rng.randrange(0, 4)
        length = rng.randrange(1, 33)
        sentinel = 0xA0 + (case_idx & 0x0F)
        payload = bytes(rng.randrange(0, 256) for _ in range(length))
        case_name = f"CSR random case {case_idx} src=0x{src_addr:08x} dst=0x{dst_addr:08x} len={length}"

        axi_ram.write(dst_addr - 8, bytes([sentinel] * (length + 16)))
        axi_ram.write(src_addr, payload)

        await apb_write(dut, ch_base(0) + REG_SRC_ADDR, src_addr)
        await apb_write(dut, ch_base(0) + REG_DST_ADDR, dst_addr)
        await apb_write(dut, ch_base(0) + REG_LEN_BYTES, length)
        await apb_write(dut, ch_base(0) + REG_CTRL, CTRL_START)

        await with_timeout(wait_done(dut, 0), 20_000, "ns")
        await check_done_status(dut, 0)
        await check_copy_window(axi_ram, dst_addr, payload, sentinel, case_name)

        await apb_write(dut, ch_base(0) + REG_CTRL, CTRL_CLEAR_DONE | CTRL_CLEAR_ERROR)


@cocotb.test()
async def test_axi_vip_random_descriptor_unaligned_copies(dut):
    """Random descriptor-backed unaligned SRC/DST/length copies through AxiRam."""
    await init_dut(dut)

    axi_ram = AxiRam(
        AxiBus.from_prefix(dut, "m_axi"),
        dut.clk,
        dut.rst_n,
        reset_active_level=False,
        size=2**18,
    )

    rng = random.Random(0xD35C_C0DE)
    ch = 2

    for case_idx in range(16):
        slot = case_idx % 4
        src_addr = 0x3000 + case_idx * 0x100 + rng.randrange(0, 4)
        dst_addr = 0xC000 + case_idx * 0x100 + rng.randrange(0, 4)
        length = rng.randrange(1, 29)
        sentinel = 0x50 + (case_idx & 0x0F)
        payload = bytes(rng.randrange(0, 256) for _ in range(length))
        case_name = f"DESC random case {case_idx} slot={slot} src=0x{src_addr:08x} dst=0x{dst_addr:08x} len={length}"

        axi_ram.write(dst_addr - 8, bytes([sentinel] * (length + 16)))
        axi_ram.write(src_addr, payload)

        await apb_write(dut, desc_addr(ch, slot, DESC_WORD_SRC), src_addr)
        await apb_write(dut, desc_addr(ch, slot, DESC_WORD_DST), dst_addr)
        await apb_write(dut, desc_addr(ch, slot, DESC_WORD_LEN), length)
        await apb_write(dut, desc_addr(ch, slot, DESC_WORD_CTRL_STATUS), 1)
        await apb_write(dut, ch_base(ch) + REG_CTRL, CTRL_DESC_DOORBELL)

        await with_timeout(wait_done(dut, ch), 20_000, "ns")
        await check_done_status(dut, ch)
        await check_copy_window(axi_ram, dst_addr, payload, sentinel, case_name)

        await apb_write(dut, ch_base(ch) + REG_CTRL, CTRL_CLEAR_DONE | CTRL_CLEAR_ERROR)
