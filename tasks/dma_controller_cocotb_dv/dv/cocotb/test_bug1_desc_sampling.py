# SPDX-License-Identifier: MIT
#
# Bug 1:
# Descriptor must be sampled when the channel wins arbitration.
#
# Test scenario:
#
#   CH0 is running
#       |
#       v
#   CH1 descriptor is programmed:
#       SRC = 0x5000
#       DST = 0x8000
#       LEN = 16
#       |
#       v
#   CH1 becomes pending through descriptor doorbell
#       |
#       v
#   CH1 is waiting for arbitration
#       |
#       v
#   Software changes CH1 LEN from 16 -> 0
#       |
#       v
#   CH1 wins arbitration
#       |
#       v
#   DUT must sample CURRENT descriptor
#       |
#       v
#   LEN = 0
#       |
#       v
#   CH1 must enter ERROR
#
# Buggy behavior:
#   DUT sampled LEN=16 before arbitration
#   -> CH1 executes stale descriptor
#   -> AXI transfer occurs
#
# Correct behavior:
#   DUT samples descriptor after arbitration
#   -> LEN=0
#   -> CH1 ERROR
#   -> no stale AXI transfer


import cocotb

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout

from cocotbext.axi import AxiBus, AxiRam


# ================================================================
# Clock
# ================================================================

CLK_PERIOD_NS = 10


# ================================================================
# CSR register offsets
# ================================================================

REG_SRC_ADDR = 0x00
REG_DST_ADDR = 0x04
REG_LEN_BYTES = 0x08
REG_CTRL = 0x0C
REG_STATUS = 0x10
REG_DESC_HEAD = 0x14
REG_DESC_TAIL = 0x18
REG_DESC_RING_STATUS = 0x1C


# ================================================================
# CTRL bits
# ================================================================

CTRL_START = 1 << 0
CTRL_CLEAR_DONE = 1 << 1
CTRL_CLEAR_ERROR = 1 << 2
CTRL_DESC_DOORBELL = 1 << 3


# ================================================================
# STATUS bits
# ================================================================

STATUS_BUSY = 1 << 0
STATUS_DONE = 1 << 1
STATUS_ERROR = 1 << 2


# ================================================================
# Descriptor memory map
#
# Descriptor aperture:
#       0x1000 - 0x11FF
#
# Per channel:
#       0x40 bytes
#
# Per descriptor slot:
#       0x10 bytes
#
# Word 0 = SRC
# Word 1 = DST
# Word 2 = LEN
# Word 3 = CTRL/STATUS
# ================================================================

DESC_BASE = 0x1000

DESC_CH_STRIDE = 0x40
DESC_SLOT_STRIDE = 0x10

DESC_WORD_SRC = 0x00
DESC_WORD_DST = 0x04
DESC_WORD_LEN = 0x08
DESC_WORD_CTRL_STATUS = 0x0C


# ================================================================
# Address helper functions
# ================================================================

def ch_base(ch: int) -> int:
    """
    Return CSR base address for a DMA channel.

    CH0 -> 0x00
    CH1 -> 0x20
    CH2 -> 0x40
    ...
    """

    return ch * 0x20


def desc_addr(ch: int, slot: int, word_offset: int) -> int:
    """
    Calculate descriptor word APB address.

    Example:

        CH1 slot0 LEN

        0x1000
        + 1 * 0x40
        + 0 * 0x10
        + 0x08

        = 0x1048
    """

    return (
        DESC_BASE
        + ch * DESC_CH_STRIDE
        + slot * DESC_SLOT_STRIDE
        + word_offset
    )


# ================================================================
# DUT initialization
# ================================================================

async def init_dut(dut):

    # Start clock
    cocotb.start_soon(
        Clock(
            dut.clk,
            CLK_PERIOD_NS,
            units="ns"
        ).start()
    )

    # ------------------------------------------------------------
    # APB initial values
    # ------------------------------------------------------------

    dut.s_apb_paddr.value = 0
    dut.s_apb_psel.value = 0
    dut.s_apb_penable.value = 0
    dut.s_apb_pwrite.value = 0
    dut.s_apb_pwdata.value = 0
    dut.s_apb_pstrb.value = 0

    # ------------------------------------------------------------
    # Reset
    # ------------------------------------------------------------

    dut.rst_n.value = 0

    for _ in range(5):
        await RisingEdge(dut.clk)

    dut.rst_n.value = 1

    for _ in range(2):
        await RisingEdge(dut.clk)


# ================================================================
# APB WRITE
# ================================================================

async def apb_write(dut, addr: int, data: int, strb: int = 0xF):

    # ------------------------------------------------------------
    # APB SETUP phase
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_paddr.value = addr
    dut.s_apb_pwdata.value = data
    dut.s_apb_pstrb.value = strb

    dut.s_apb_pwrite.value = 1
    dut.s_apb_psel.value = 1
    dut.s_apb_penable.value = 0

    # ------------------------------------------------------------
    # APB ACCESS phase
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_penable.value = 1

    await Timer(1, units="ns")

    # PREADY must be asserted
    assert int(dut.s_apb_pready.value) == 1, (
        f"APB WRITE failed: PREADY=0 "
        f"addr=0x{addr:08x}"
    )

    # PSLVERR must be 0
    assert int(dut.s_apb_pslverr.value) == 0, (
        f"APB WRITE returned PSLVERR "
        f"addr=0x{addr:08x}"
    )

    # ------------------------------------------------------------
    # Finish APB transaction
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_psel.value = 0
    dut.s_apb_penable.value = 0
    dut.s_apb_pwrite.value = 0

    dut.s_apb_pwdata.value = 0
    dut.s_apb_pstrb.value = 0


# ================================================================
# APB READ
# ================================================================

async def apb_read(dut, addr: int) -> int:

    # ------------------------------------------------------------
    # APB SETUP phase
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_paddr.value = addr
    dut.s_apb_pwdata.value = 0
    dut.s_apb_pstrb.value = 0xF

    dut.s_apb_pwrite.value = 0
    dut.s_apb_psel.value = 1
    dut.s_apb_penable.value = 0

    # ------------------------------------------------------------
    # APB ACCESS phase
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_penable.value = 1

    await Timer(1, units="ns")

    assert int(dut.s_apb_pready.value) == 1, (
        f"APB READ failed: PREADY=0 "
        f"addr=0x{addr:08x}"
    )

    assert int(dut.s_apb_pslverr.value) == 0, (
        f"APB READ returned PSLVERR "
        f"addr=0x{addr:08x}"
    )

    value = int(dut.s_apb_prdata.value)

    # ------------------------------------------------------------
    # Finish APB transaction
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_psel.value = 0
    dut.s_apb_penable.value = 0

    return value


# ================================================================
# Wait for channel DONE interrupt
# ================================================================

async def wait_done(
    dut,
    ch: int,
    timeout_cycles: int = 1000
):

    mask = 1 << ch

    for _ in range(timeout_cycles):

        await RisingEdge(dut.clk)

        irq_done = int(dut.irq_done.value)

        if irq_done & mask:
            return

    raise AssertionError(
        f"Timeout waiting for irq_done[{ch}]"
    )


# ================================================================
# Wait until channel becomes BUSY
# ================================================================

async def wait_busy(
    dut,
    ch: int,
    timeout_cycles: int = 200
):

    for _ in range(timeout_cycles):

        status = await apb_read(
            dut,
            ch_base(ch) + REG_STATUS
        )

        if status & STATUS_BUSY:
            return

    raise AssertionError(
        f"CH{ch} never became BUSY"
    )


# ================================================================
# BUG 1 TEST
# ================================================================

@cocotb.test()
async def test_bug1_descriptor_sampled_at_arbitration(dut):

    """
    Bug #1 directed test.

    The descriptor initially contains:

        SRC = 0x5000
        DST = 0x8000
        LEN = 16

    CH1 becomes pending.

    BEFORE CH1 wins arbitration:

        LEN 16 -> LEN 0

    Correct RTL behavior:

        CH1 wins
            |
            v
        descriptor sampled
            |
            v
        LEN = 0
            |
            v
        ERROR
            |
            v
        no AXI transfer

    Buggy behavior:

        CH1 sampled LEN=16 too early
            |
            v
        CH1 executes stale descriptor
            |
            v
        AXI transfer occurs
    """

    print("\n")
    print("=" * 70)
    print("BUG 1: DESCRIPTOR SAMPLING AT ARBITRATION")
    print("=" * 70)

    # ============================================================
    # Initialize DUT
    # ============================================================

    await init_dut(dut)

    # ============================================================
    # AXI RAM
    #
    # This acts as the external memory connected to the DMA AXI
    # master.
    # ============================================================

    axi_ram = AxiRam(
        AxiBus.from_prefix(dut, "m_axi"),
        dut.clk,
        dut.rst_n,
        reset_active_level=False,
        size=2**16,
    )

    # ============================================================
    # CHANNEL 0
    #
    # CH0 will occupy the DMA while CH1 is pending.
    # ============================================================

    ch0 = 0

    ch0_src = 0x1000
    ch0_dst = 0x3000

    # Long enough transfer to give us the Bug-1 window.
    ch0_payload = bytes(range(64))

    # Put CH0 source data in AXI RAM.
    axi_ram.write(
        ch0_src,
        ch0_payload
    )

    # ============================================================
    # CHANNEL 1 DESCRIPTOR
    # ============================================================

    ch1 = 1
    slot = 0

    old_src = 0x5000
    old_dst = 0x8000

    old_len = 16

    old_payload = bytes([
        0x10,
        0x21,
        0x32,
        0x43,
        0x54,
        0x65,
        0x76,
        0x87,
        0x98,
        0xA9,
        0xBA,
        0xCB,
        0xDC,
        0xED,
        0xFE,
        0xEF,
    ])

    # ============================================================
    # Sentinel around CH1 destination
    #
    # If stale LEN=16 executes, these checks help detect memory
    # corruption.
    # ============================================================

    sentinel = bytes([0xA5] * 32)

    axi_ram.write(
        old_dst - 4,
        sentinel
    )

    # Put old descriptor source data into memory.
    axi_ram.write(
        old_src,
        old_payload
    )

    # ============================================================
    # PROGRAM CH1 DESCRIPTOR
    # ============================================================

    print("\nProgramming CH1 descriptor...")

    # SRC = 0x5000
    await apb_write(
        dut,
        desc_addr(
            ch1,
            slot,
            DESC_WORD_SRC
        ),
        old_src
    )

    # DST = 0x8000
    await apb_write(
        dut,
        desc_addr(
            ch1,
            slot,
            DESC_WORD_DST
        ),
        old_dst
    )

    # LEN = 16
    await apb_write(
        dut,
        desc_addr(
            ch1,
            slot,
            DESC_WORD_LEN
        ),
        old_len
    )

    # CTRL/STATUS = 1
    #
    # Descriptor is marked valid/ready.
    await apb_write(
        dut,
        desc_addr(
            ch1,
            slot,
            DESC_WORD_CTRL_STATUS
        ),
        1
    )

    print(
        f"CH1 descriptor: "
        f"SRC=0x{old_src:08x}, "
        f"DST=0x{old_dst:08x}, "
        f"LEN={old_len}"
    )

    # ============================================================
    # START CH0
    # ============================================================

    print("\nStarting CH0...")

    await apb_write(
        dut,
        ch_base(ch0) + REG_SRC_ADDR,
        ch0_src
    )

    await apb_write(
        dut,
        ch_base(ch0) + REG_DST_ADDR,
        ch0_dst
    )

    await apb_write(
        dut,
        ch_base(ch0) + REG_LEN_BYTES,
        len(ch0_payload)
    )

    await apb_write(
        dut,
        ch_base(ch0) + REG_CTRL,
        CTRL_START
    )

    # Verify CH0 actually became busy.
    await wait_busy(
        dut,
        ch0
    )

    print("CH0 is BUSY.")

    # ============================================================
    # MAKE CH1 PENDING
    # ============================================================

    print("\nMaking CH1 descriptor pending...")

    # TAIL = 1
    await apb_write(
        dut,
        ch_base(ch1) + REG_DESC_TAIL,
        1
    )

    # CTRL.DESC_DOORBELL = 1
    await apb_write(
        dut,
        ch_base(ch1) + REG_CTRL,
        CTRL_DESC_DOORBELL
    )

    print("CH1 descriptor doorbell sent.")
    print("CH1 is now pending.")

    # ============================================================
    # *************** BUG WINDOW *******************************
    #
    # CH1 is pending.
    #
    # Change descriptor LEN:
    #
    #       16 -> 0
    #
    # BEFORE CH1 wins arbitration.
    # ============================================================

    print("\n")
    print("BUG WINDOW")
    print("-" * 70)
    print("CH1 was programmed with LEN = 16")
    print("CH1 is pending.")
    print("Changing CH1 LEN from 16 -> 0 BEFORE arbitration...")
    print("-" * 70)

    await Timer(
        1,
        units="ns"
    )

    await apb_write(
        dut,
        desc_addr(
            ch1,
            slot,
            DESC_WORD_LEN
        ),
        0
    )

    print("CH1 descriptor LEN is now 0.")

    # ============================================================
    # WAIT FOR CH0
    # ============================================================

    print("\nWaiting for CH0 to complete...")

    await with_timeout(
        wait_done(
            dut,
            ch0
        ),
        20_000,
        "ns"
    )

    print("CH0 completed.")

    # ============================================================
    # WAIT FOR CH1 ERROR
    # ============================================================

    print("\nWaiting for CH1 ERROR...")

    ch1_error_seen = False

    for _ in range(200):

        status = await apb_read(
            dut,
            ch_base(ch1) + REG_STATUS
        )

        if status & STATUS_ERROR:

            ch1_error_seen = True

            print(
                f"CH1 ERROR detected: "
                f"STATUS=0x{status:08x}"
            )

            break

        await RisingEdge(dut.clk)

    # ============================================================
    # CHECK #1
    #
    # CH1 MUST ENTER ERROR.
    # ============================================================

    assert ch1_error_seen, (
        "BUG 1 FAILURE: CH1 did not enter ERROR after "
        "LEN was changed to zero before arbitration."
    )

    ch1_status = await apb_read(
        dut,
        ch_base(ch1) + REG_STATUS
    )

    assert ch1_status & STATUS_ERROR, (
        f"CH1 ERROR bit not set. "
        f"STATUS=0x{ch1_status:08x}"
    )

    # ============================================================
    # CHECK #2
    #
    # CH1 must NOT report DONE.
    #
    # If the stale LEN=16 descriptor was executed, DONE would
    # normally be observed.
    # ============================================================

    assert not (ch1_status & STATUS_DONE), (
        f"CH1 incorrectly completed stale descriptor. "
        f"STATUS=0x{ch1_status:08x}"
    )

    # ============================================================
    # CHECK #3
    #
    # CH1 destination must NOT contain old_payload.
    # ============================================================

    got = bytes(
        axi_ram.read(
            old_dst,
            old_len
        )
    )

    assert got != old_payload, (
        "BUG 1 FAILURE: CH1 executed the stale LEN=16 "
        "descriptor."
    )

    # ============================================================
    # CHECK #4
    #
    # Memory immediately before destination unchanged.
    # ============================================================

    before = bytes(
        axi_ram.read(
            old_dst - 4,
            4
        )
    )

    assert before == bytes([0xA5] * 4), (
        "Memory before CH1 destination was corrupted."
    )

    # ============================================================
    # CHECK #5
    #
    # Memory immediately after expected transfer unchanged.
    # ============================================================

    after = bytes(
        axi_ram.read(
            old_dst + old_len,
            4
        )
    )

    assert after == bytes([0xA5] * 4), (
        "Memory after CH1 destination was corrupted."
    )

    # ============================================================
    # CHECK CH0
    #
    # CH0 must complete normally.
    # ============================================================

    ch0_status = await apb_read(
        dut,
        ch_base(ch0) + REG_STATUS
    )

    assert ch0_status & STATUS_DONE, (
        f"CH0 did not complete. "
        f"STATUS=0x{ch0_status:08x}"
    )

    assert not (ch0_status & STATUS_ERROR), (
        f"CH0 unexpectedly reported ERROR. "
        f"STATUS=0x{ch0_status:08x}"
    )

    # ============================================================
    # Verify CH0 data
    # ============================================================

    ch0_got = bytes(
        axi_ram.read(
            ch0_dst,
            len(ch0_payload)
        )
    )

    assert ch0_got == ch0_payload, (
        "CH0 AXI data mismatch."
    )

    # ============================================================
    # FINAL RESULT
    # ============================================================

    print("\n")
    print("=" * 70)
    print("BUG 1 TEST PASSED")
    print("=" * 70)

    print("CH0 completed normally.")
    print("CH1 became pending with LEN = 16.")
    print("CH1 LEN changed to 0 before arbitration.")
    print("CH1 sampled the current descriptor.")
    print("CH1 correctly entered ERROR.")
    print("CH1 did not execute the stale descriptor.")
    print("CH1 destination remained unchanged.")

    print("=" * 70)
