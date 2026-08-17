import cocotb

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, Event
from cocotbext.axi import AxiBus, AxiRam


# ================================================================
# BUG #2 CONFIGURATION
# ================================================================

ADDR_WIDTH = 32
DATA_WIDTH = 32

BYTES_PER_BEAT = DATA_WIDTH // 8

ADDRESS_SPACE = 1 << ADDR_WIDTH
MAX_ADDRESS = ADDRESS_SPACE - 1


# ================================================================
# APB REGISTER MAP
#
# From samram_dma_apb_decode.v:
#
#   REG_SRC_ADDR  = 3'd0 -> 0x00
#   REG_DST_ADDR  = 3'd1 -> 0x04
#   REG_LEN_BYTES = 3'd2 -> 0x08
#   REG_CTRL      = 3'd3 -> 0x0C
#   REG_STATUS    = 3'd4 -> 0x10
#
# CH0 is used, therefore addresses are:
#
#   CH0 SRC    = 0x00
#   CH0 DST    = 0x04
#   CH0 LEN    = 0x08
#   CH0 CTRL   = 0x0C
#   CH0 STATUS = 0x10
# ================================================================

REG_SRC_ADDR  = 0x00
REG_DST_ADDR  = 0x04
REG_LEN_BYTES = 0x08
REG_CTRL      = 0x0C
REG_STATUS    = 0x10


# ================================================================
# CONTROL / STATUS BITS
# ================================================================

CTRL_START = 1 << 0

STATUS_BUSY  = 1 << 0
STATUS_DONE  = 1 << 1
STATUS_ERROR = 1 << 2


# ================================================================
# BUG #2 DIRECTED STIMULUS
# ================================================================
#
# 32-bit address space:
#
#   0x00000000 ---------------------- 0xFFFFFFFF
#
# Start:
#
#   0xFFFFFFFC
#
# Length:
#
#   8 bytes
#
# Required byte addresses:
#
#   FFFFFFFC
#   FFFFFFFD
#   FFFFFFFE
#   FFFFFFFF
#   100000000  <- outside 32-bit address space
#   100000001
#   100000002
#   100000003
#
# Therefore this transfer must NOT be allowed to continue.
# Expected specification behavior:
#
#   ERROR + fatal_irq + transaction terminated
#
# Current RTL is expected to be buggy.
# ================================================================

SRC_ADDR = 0x00001000
DST_ADDR = 0xFFFFFFFC
TRANSFER_LENGTH = 8


# ================================================================
# ADDRESS CALCULATION
# ================================================================

def transfer_end_address(start_address, length):

    return start_address + length - 1


def crosses_boundary(start_address, length):

    end_address = transfer_end_address(
        start_address,
        length
    )

    return end_address > MAX_ADDRESS


# ================================================================
# BUG #2 CHECKER
# ================================================================

class Bug2Checker:

    def __init__(self):

        self.boundary_violation = False

        self.error_seen = False
        self.irq_seen = False

        # IMPORTANT:
        #
        # This means that the DUT terminated because of the
        # required ERROR/fatal_irq condition.
        #
        # It does NOT mean merely that no more AXI addresses
        # appeared.
        self.transaction_terminated = False

        self.axi_addresses = []

        self.failure_messages = []

    # ------------------------------------------------------------
    # Record AXI address
    # ------------------------------------------------------------

    def record_axi_address(self, address):

        self.axi_addresses.append(address)

        print(
            f"CHECKER: AXI address observed = "
            f"0x{address:08X}"
        )

    # ------------------------------------------------------------
    # Check boundary calculation
    # ------------------------------------------------------------

    def check_boundary(self, start_address, length):

        end_address = transfer_end_address(
            start_address,
            length
        )

        print()
        print("=" * 60)
        print("CHECKER: Boundary calculation")
        print("=" * 60)

        print(
            f"Start address : 0x{start_address:08X}"
        )

        print(
            f"Length        : {length} bytes"
        )

        print(
            f"End address   : 0x{end_address:09X}"
        )

        print(
            f"Maximum legal : 0x{MAX_ADDRESS:08X}"
        )

        self.boundary_violation = (
            end_address > MAX_ADDRESS
        )

        print(
            "Boundary violation: "
            f"{'YES' if self.boundary_violation else 'NO'}"
        )

        if not self.boundary_violation:

            self.failure_messages.append(
                "The directed stimulus does not cross "
                "the 32-bit address boundary."
            )

    # ------------------------------------------------------------
    # Check ERROR status
    # ------------------------------------------------------------

    def check_error_status(self, status):

        if status & STATUS_ERROR:

            self.error_seen = True

            print()
            print(
                f"CHECKER: ERROR status observed "
                f"status=0x{status:08X}"
            )

        elif status & STATUS_DONE:

            print()
            print(
                f"CHECKER: DONE observed without ERROR "
                f"status=0x{status:08X}"
            )

            self.failure_messages.append(
                "DUT completed with DONE instead of "
                "entering ERROR."
            )

        else:

            print()
            print(
                f"CHECKER: No ERROR status observed "
                f"status=0x{status:08X}"
            )

            self.failure_messages.append(
                "DUT did not enter ERROR status."
            )

    # ------------------------------------------------------------
    # Check fatal IRQ
    # ------------------------------------------------------------

    def check_interrupt(self, fatal_irq):

        if fatal_irq:

            self.irq_seen = True

            print(
                "CHECKER: fatal_irq = 1"
            )

        else:

            print(
                "CHECKER: fatal_irq = 0"
            )

            self.failure_messages.append(
                "DUT did not raise fatal_irq."
            )

    # ------------------------------------------------------------
    # Check ERROR-based termination
    # ------------------------------------------------------------
    #
    # Correct behavior requires:
    #
    #   ERROR status = 1
    #   fatal_irq    = 1
    #
    # We intentionally do NOT use:
    #
    #   len(addresses_after) == len(addresses_before)
    #
    # because a normal DONE completion can also stop generating
    # AXI accesses.
    # ------------------------------------------------------------

    def check_error_termination(
        self,
        status,
        fatal_irq
    ):

        print()
        print("=" * 60)
        print("CHECKER: Error termination check")
        print("=" * 60)

        if (
            (status & STATUS_ERROR)
            and fatal_irq
        ):

            self.transaction_terminated = True

            print(
                "CHECKER: ERROR termination = YES"
            )

        else:

            self.transaction_terminated = False

            print(
                "CHECKER: ERROR termination = NO"
            )

            self.failure_messages.append(
                "DUT did not terminate the transaction "
                "through the required ERROR/fatal_irq path."
            )

    # ------------------------------------------------------------
    # Final checker report
    # ------------------------------------------------------------

    def report(self):

        print()
        print("=" * 70)
        print("BUG #2 CHECKER RESULT")
        print("=" * 70)

        checker_failed = False

        # --------------------------------------------------------
        # Boundary violation
        # --------------------------------------------------------

        if not self.boundary_violation:

            checker_failed = True

            print(
                "❌ Boundary violation was not detected."
            )

        else:

            print(
                "✓ Boundary violation detected."
            )

        # --------------------------------------------------------
        # ERROR status
        # --------------------------------------------------------

        if not self.error_seen:

            checker_failed = True

            print(
                "❌ DUT did not enter ERROR status."
            )

        else:

            print(
                "✓ DUT entered ERROR status."
            )

        # --------------------------------------------------------
        # fatal IRQ
        # --------------------------------------------------------

        if not self.irq_seen:

            checker_failed = True

            print(
                "❌ DUT did not raise fatal_irq."
            )

        else:

            print(
                "✓ DUT raised fatal_irq."
            )

        # --------------------------------------------------------
        # Error termination
        # --------------------------------------------------------

        if not self.transaction_terminated:

            checker_failed = True

            print(
                "❌ DUT did not terminate the transaction "
                "through ERROR/fatal_irq."
            )

        else:

            print(
                "✓ DUT terminated through ERROR/fatal_irq."
            )

        # --------------------------------------------------------
        # Observed AXI addresses
        # --------------------------------------------------------

        print()
        print(
            "Observed AXI addresses:"
        )

        if len(self.axi_addresses) == 0:

            print(
                "  NONE"
            )

        else:

            for index, address in enumerate(
                self.axi_addresses
            ):

                print(
                    f"  [{index}] 0x{address:08X}"
                )

        # --------------------------------------------------------
        # Final checker result
        # --------------------------------------------------------

        print()
        print("=" * 70)

        if checker_failed:

            print(
                "❌ CHECKER FAILED"
            )

            print()
            print(
                "BUG #2 CONFIRMED:"
            )

            print(
                "The DUT violated the required "
                "address-boundary/error behavior."
            )

            print()

            if self.failure_messages:

                print(
                    "Failure details:"
                )

                for message in self.failure_messages:

                    print(
                        f"  - {message}"
                    )

            print("=" * 70)

            # IMPORTANT:
            #
            # Return False rather than raising an exception.
            #
            # This means:
            #
            #   Checker = FAIL
            #
            # while the Cocotb test can report:
            #
            #   Testbench = PASS
            #
            # because the testbench successfully detected
            # the RTL bug.

            return False

        else:

            print(
                "✓ CHECKER PASSED"
            )

            print(
                "No Bug #2 violation detected."
            )

            print("=" * 70)

            return True


# ================================================================
# RESET DUT
# ================================================================

async def reset_dut(dut):

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


# ================================================================
# APB WRITE
# ================================================================

async def apb_write(
    dut,
    addr,
    data,
    strb=0xF
):

    # ------------------------------------------------------------
    # SETUP phase
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_paddr.value = addr
    dut.s_apb_pwdata.value = data
    dut.s_apb_pstrb.value = strb

    dut.s_apb_pwrite.value = 1
    dut.s_apb_psel.value = 1
    dut.s_apb_penable.value = 0

    # ------------------------------------------------------------
    # ACCESS phase
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_penable.value = 1

    await Timer(
        1,
        unit="ns"
    )

    assert int(dut.s_apb_pready.value) == 1, (
        f"APB WRITE failed: PREADY=0 "
        f"addr=0x{addr:08X}"
    )

    assert int(dut.s_apb_pslverr.value) == 0, (
        f"APB WRITE returned PSLVERR "
        f"addr=0x{addr:08X}"
    )

    # ------------------------------------------------------------
    # Finish transaction
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_psel.value = 0
    dut.s_apb_penable.value = 0
    dut.s_apb_pwrite.value = 0

    dut.s_apb_paddr.value = 0
    dut.s_apb_pwdata.value = 0
    dut.s_apb_pstrb.value = 0


# ================================================================
# APB READ
# ================================================================

async def apb_read(
    dut,
    addr
):

    # ------------------------------------------------------------
    # SETUP phase
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_paddr.value = addr
    dut.s_apb_pwdata.value = 0
    dut.s_apb_pstrb.value = 0xF

    dut.s_apb_pwrite.value = 0
    dut.s_apb_psel.value = 1
    dut.s_apb_penable.value = 0

    # ------------------------------------------------------------
    # ACCESS phase
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_penable.value = 1

    await Timer(
        1,
        unit="ns"
    )

    assert int(dut.s_apb_pready.value) == 1, (
        f"APB READ failed: PREADY=0 "
        f"addr=0x{addr:08X}"
    )

    assert int(dut.s_apb_pslverr.value) == 0, (
        f"APB READ returned PSLVERR "
        f"addr=0x{addr:08X}"
    )

    value = int(
        dut.s_apb_prdata.value
    )

    # ------------------------------------------------------------
    # Finish transaction
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)

    dut.s_apb_psel.value = 0
    dut.s_apb_penable.value = 0

    dut.s_apb_paddr.value = 0

    return value


# ================================================================
# AXI ADDRESS MONITOR
# ================================================================
#
# Monitor both:
#
#   AR handshake -> read address
#   AW handshake -> write address
#
# This allows the checker to observe the actual addresses generated
# by the DUT.
# ================================================================

async def axi_address_monitor(
    dut,
    checker,
    stop_event
):

    while not stop_event.is_set():

        await RisingEdge(dut.clk)

        # --------------------------------------------------------
        # AXI READ ADDRESS
        # --------------------------------------------------------

        try:

            arvalid = int(
                dut.m_axi_arvalid.value
            )

            arready = int(
                dut.m_axi_arready.value
            )

            if arvalid and arready:

                address = int(
                    dut.m_axi_araddr.value
                )

                checker.record_axi_address(
                    address
                )

        except Exception:

            pass

        # --------------------------------------------------------
        # AXI WRITE ADDRESS
        # --------------------------------------------------------

        try:

            awvalid = int(
                dut.m_axi_awvalid.value
            )

            awready = int(
                dut.m_axi_awready.value
            )

            if awvalid and awready:

                address = int(
                    dut.m_axi_awaddr.value
                )

                checker.record_axi_address(
                    address
                )

        except Exception:

            pass


# ================================================================
# WAIT FOR DMA RESULT
# ================================================================

async def wait_for_dma_result(
    dut,
    checker,
    max_cycles=100
):

    status = 0

    for cycle in range(max_cycles):

        await RisingEdge(dut.clk)

        status = await apb_read(
            dut,
            REG_STATUS
        )

        # --------------------------------------------------------
        # ERROR
        # --------------------------------------------------------

        if status & STATUS_ERROR:

            checker.check_error_status(
                status
            )

            return status

        # --------------------------------------------------------
        # DONE
        # --------------------------------------------------------

        if status & STATUS_DONE:

            checker.check_error_status(
                status
            )

            return status

    # ------------------------------------------------------------
    # Timeout
    # ------------------------------------------------------------

    print()
    print(
        "CHECKER: DMA status timeout."
    )

    checker.failure_messages.append(
        "DMA did not reach DONE or ERROR within "
        f"{max_cycles} cycles."
    )

    return status


# ================================================================
# BUG #2 TEST
# ================================================================

@cocotb.test()
async def test_bug2_boundary_address(dut):

    print()
    print("=" * 70)
    print("BUG #2: 32-BIT ADDRESS BOUNDARY TEST")
    print("=" * 70)

    # ------------------------------------------------------------
    # Start clock
    # ------------------------------------------------------------

    cocotb.start_soon(
        Clock(
            dut.clk,
            10,
            unit="ns"
        ).start()
    )

    # ------------------------------------------------------------
    # Create checker
    # ------------------------------------------------------------

    checker = Bug2Checker()

    # ------------------------------------------------------------
    # Check directed stimulus mathematically
    # ------------------------------------------------------------

    checker.check_boundary(
        DST_ADDR,
        TRANSFER_LENGTH
    )

    # ------------------------------------------------------------
    # Reset
    # ------------------------------------------------------------

    await reset_dut(dut)

    # ------------------------------------------------------------
    # AXI RAM
    # ------------------------------------------------------------

    axi_ram = AxiRam(
        AxiBus.from_prefix(
            dut,
            "m_axi"
        ),
        dut.clk,
        dut.rst_n,
        size=0x20000
    )

    # ------------------------------------------------------------
    # Put known source data into AXI RAM
    # ------------------------------------------------------------

    source_data = bytes([
        0x11,
        0x22,
        0x33,
        0x44,
        0x55,
        0x66,
        0x77,
        0x88
    ])

    axi_ram.write(
        SRC_ADDR,
        source_data
    )

    # ------------------------------------------------------------
    # Start AXI monitor
    # ------------------------------------------------------------

    stop_monitor = Event()

    cocotb.start_soon(
        axi_address_monitor(
            dut,
            checker,
            stop_monitor
        )
    )

    # ------------------------------------------------------------
    # Display stimulus
    # ------------------------------------------------------------

    print()
    print(
        f"SRC = 0x{SRC_ADDR:08X}"
    )

    print(
        f"DST = 0x{DST_ADDR:08X}"
    )

    print(
        f"LEN = {TRANSFER_LENGTH}"
    )

    print()
    print(
        "Starting DMA..."
    )

    # ------------------------------------------------------------
    # Configure source address
    # ------------------------------------------------------------

    await apb_write(
        dut,
        REG_SRC_ADDR,
        SRC_ADDR
    )

    # ------------------------------------------------------------
    # Configure destination address
    # ------------------------------------------------------------

    await apb_write(
        dut,
        REG_DST_ADDR,
        DST_ADDR
    )

    # ------------------------------------------------------------
    # Configure transfer length
    # ------------------------------------------------------------

    await apb_write(
        dut,
        REG_LEN_BYTES,
        TRANSFER_LENGTH
    )

    # ------------------------------------------------------------
    # START DMA
    # ------------------------------------------------------------

    await apb_write(
        dut,
        REG_CTRL,
        CTRL_START
    )

    # ------------------------------------------------------------
    # Wait for DUT result
    # ------------------------------------------------------------

    status = await wait_for_dma_result(
        dut,
        checker,
        max_cycles=100
    )

    # ------------------------------------------------------------
    # Check fatal IRQ
    # ------------------------------------------------------------

    fatal_irq_value = int(
        dut.fatal_irq.value
    )

    checker.check_interrupt(
        fatal_irq_value
    )

    # ------------------------------------------------------------
    # Check ERROR-based termination
    # ------------------------------------------------------------
    #
    # IMPORTANT:
    #
    # We do NOT check whether the AXI address list stopped growing.
    #
    # A normal DONE completion also stops AXI activity.
    #
    # Instead, required error termination is defined by:
    #
    #   ERROR status + fatal_irq
    # ------------------------------------------------------------

    checker.check_error_termination(
        status,
        fatal_irq_value
    )

    # ------------------------------------------------------------
    # Stop AXI monitor
    # ------------------------------------------------------------

    stop_monitor.set()

    await Timer(
        10,
        unit="ns"
    )

    # ------------------------------------------------------------
    # Final checker report
    # ------------------------------------------------------------

    checker_passed = checker.report()

    # ------------------------------------------------------------
    # TESTBENCH RESULT
    # ------------------------------------------------------------
    #
    # For the CURRENT BUGGY RTL:
    #
    #   checker_passed = False
    #
    # That is EXPECTED.
    #
    # The Cocotb test itself therefore passes because it successfully
    # detected Bug #2.
    # ------------------------------------------------------------

    print()
    print("=" * 70)

    if checker_passed is False:

        print(
            "BUG #2 TESTBENCH PASSED"
        )

        print(
            "The checker successfully detected "
            "the RTL boundary violation."
        )

    else:

        print(
            "BUG #2 TESTBENCH FAILED"
        )

        print(
            "The checker did not detect the expected "
            "Bug #2 violation."
        )

    print("=" * 70)

    # ------------------------------------------------------------
    # The directed test is specifically designed to detect the
    # existing bug.
    #
    # Therefore:
    #
    #   checker FAIL = expected
    #   testbench PASS = expected
    #
    # If the RTL is later fixed, checker should PASS and this
    # regression test should fail, indicating that the expected
    # bug is no longer present.
    # ------------------------------------------------------------

    assert checker_passed is False, (
        "Bug #2 was NOT detected. "
        "The current RTL did not reproduce the expected violation."
    )
