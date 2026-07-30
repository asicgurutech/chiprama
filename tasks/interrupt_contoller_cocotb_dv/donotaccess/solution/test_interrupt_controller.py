
# =============================================================
# Reference solution testbench for interrupt_controller_apb.
# Scores 1.0: passes golden RTL, kills every hidden mutant, and
# marks all required coverage points.
#
# Coverage points (see grade.py REQUIRED_COVERAGE):
#   reset, line_interrupt, messaged_apb, pwdata_equals_isr,
#   paddr_config, pslverr_sticky, apb_err_w1c, sw_interrupt,
#   pending_irq_during_apb
# =============================================================

import json
import logging
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# ─────────────────────────────────────────────────────────────
# Register Address Map (must match RTL)
# ─────────────────────────────────────────────────────────────
ADDR_IMR      = 0x0
ADDR_IPR      = 0x1
ADDR_ISR      = 0x2
ADDR_TRIG     = 0x3
ADDR_SWIR     = 0x4
ADDR_GCR      = 0x5
ADDR_VECT     = 0x6
ADDR_STAT     = 0x7
ADDR_MICR     = 0x8
ADDR_MADDR_LO = 0x9
ADDR_MADDR_HI = 0xA

COVERAGE_POINTS = [
    "reset",
    "line_interrupt",
    "messaged_apb",
    "pwdata_equals_isr",
    "paddr_config",
    "pslverr_sticky",
    "apb_err_w1c",
    "sw_interrupt",
    "pending_irq_during_apb",
    "apb_delayed_reset",
    "apb_no_response_reset",
    "irq_priority_order",
    "irq_masking",
    "edge_level_trigger",
    "ipr_set_ack_race",
    "apb_threshold_boundary",
]


def mark_coverage(point: str) -> None:
    if point not in COVERAGE_POINTS:
        raise AssertionError(f"unknown coverage point {point!r}")
    raw = os.environ.get("INTC_COVERAGE_FILE")
    if not raw:
        return
    path = Path(raw)
    path.parent.mkdir(parents=True, exist_ok=True)
    data: dict[str, bool] = {}
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
    data[point] = True
    path.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")


# ─────────────────────────────────────────────────────────────
# APB Slave Model — background coroutine that ACKs APB writes.
# ─────────────────────────────────────────────────────────────
class APBSlaveModel:
    def __init__(self, dut, ready_latency=1, inject_error=False):
        self.dut = dut
        self.ready_latency = ready_latency
        self.inject_error = inject_error
        self.transactions = []
        self.log = logging.getLogger("APBSlave")
        self._running = False

    async def start(self):
        self._running = True
        dut = self.dut
        dut.PREADY.value = 0
        dut.PSLVERR.value = 0
        while self._running:
            await RisingEdge(dut.clk)
            if dut.PSEL.value == 1 and dut.PENABLE.value == 0:
                await RisingEdge(dut.clk)  # SETUP -> ACCESS
                for _ in range(self.ready_latency - 1):
                    await RisingEdge(dut.clk)
                dut.PREADY.value = 1
                dut.PSLVERR.value = 1 if self.inject_error else 0
                txn = {
                    "addr": int(dut.PADDR.value),
                    "data": int(dut.PWDATA.value),
                    "write": int(dut.PWRITE.value),
                    "error": self.inject_error,
                }
                self.transactions.append(txn)
                self.log.info(
                    f"APB TXN | ADDR=0x{txn['addr']:04X} DATA=0x{txn['data']:02X} PSLVERR={txn['error']}"
                )
                await RisingEdge(dut.clk)
                dut.PREADY.value = 0
                dut.PSLVERR.value = 0
                self.inject_error = False

    def stop(self):
        self._running = False

    def last_transaction(self):
        return self.transactions[-1] if self.transactions else None

    def transaction_count(self):
        return len(self.transactions)


# ─────────────────────────────────────────────────────────────
# CPU register / helper tasks
# ─────────────────────────────────────────────────────────────
async def cpu_write(dut, addr, data):
    await RisingEdge(dut.clk)
    dut.cpu_wr.value = 1
    dut.cpu_rd.value = 0
    dut.cpu_addr.value = addr
    dut.cpu_wdata.value = data
    await RisingEdge(dut.clk)
    dut.cpu_wr.value = 0
    dut.cpu_wdata.value = 0


async def cpu_read(dut, addr):
    await RisingEdge(dut.clk)
    dut.cpu_rd.value = 1
    dut.cpu_wr.value = 0
    dut.cpu_addr.value = addr
    await Timer(1, unit="ns")
    val = int(dut.cpu_rdata.value)
    await RisingEdge(dut.clk)
    dut.cpu_rd.value = 0
    return val


async def cpu_ack(dut):
    await RisingEdge(dut.clk)
    dut.cpu_ack.value = 1
    await RisingEdge(dut.clk)
    dut.cpu_ack.value = 0


async def reset_dut(dut, cycles=4):
    dut.rst_n.value = 0
    dut.irq.value = 0
    dut.cpu_ack.value = 0
    dut.cpu_wr.value = 0
    dut.cpu_rd.value = 0
    dut.cpu_addr.value = 0
    dut.cpu_wdata.value = 0
    dut.PREADY.value = 0
    dut.PSLVERR.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def wait_apb_idle(dut, timeout=50):
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if int(dut.apb_busy.value) == 0:
            return
    raise AssertionError("Timeout waiting for APB to become idle")


async def wait_for_txns(dut, slave, n, timeout=100):
    """Robustly wait until `n` APB transactions have been observed. Polls the transaction
    count instead of racing apb_busy (which can read 0 in the gap before a txn starts)."""
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if slave.transaction_count() >= n:
            return
    raise AssertionError(f"Timeout waiting for {n} APB txns; got {slave.transaction_count()}")


async def fire_irq_edge(dut, irq_mask, cycles=2):
    await RisingEdge(dut.clk)
    dut.irq.value = irq_mask
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.irq.value = 0


# ─────────────────────────────────────────────────────────────
# T1: Reset state
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_01_reset_state(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)

    assert (await cpu_read(dut, ADDR_IMR)) == 0xFF, "IMR should reset to 0xFF"
    assert (await cpu_read(dut, ADDR_GCR)) == 0x00, "GCR should reset to 0x00"
    assert (await cpu_read(dut, ADDR_IPR)) == 0x00, "IPR should reset to 0x00"
    assert (await cpu_read(dut, ADDR_MICR)) == 0x00, "MICR should reset to 0x00"
    assert int(dut.PSEL.value) == 0, "PSEL should be 0 at reset"
    assert int(dut.PENABLE.value) == 0, "PENABLE should be 0 at reset"
    assert int(dut.INT.value) == 0, "INT should be 0 at reset"
    mark_coverage("reset")


# ─────────────────────────────────────────────────────────────
# T2: Line interrupt mode — IRQ0 fires INT pin, no APB
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_02_line_interrupt_mode(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=1)
    cocotb.start_soon(slave.start())

    await cpu_write(dut, ADDR_MICR, 0x00)
    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFE)
    await cpu_write(dut, ADDR_GCR, 0x01)

    await fire_irq_edge(dut, 0x01)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.INT.value) == 1, "INT should assert in line mode"
    assert slave.transaction_count() == 0, "no APB txn in line mode"
    assert int(dut.INT_VECT.value) == 0, "INT_VECT should be 0 for IRQ0"

    await cpu_ack(dut)
    await RisingEdge(dut.clk)
    assert int(dut.INT.value) == 0, "INT should clear after cpu_ack"

    slave.stop()
    mark_coverage("line_interrupt")


# ─────────────────────────────────────────────────────────────
# T3: Messaged mode — APB write fires instead of INT
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_03_messaged_interrupt_apb_fires(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=1)
    cocotb.start_soon(slave.start())

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFE)
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MADDR_LO, 0x80)
    await cpu_write(dut, ADDR_MADDR_HI, 0x10)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x01)
    await wait_for_txns(dut, slave, 1, timeout=40)

    assert int(dut.INT.value) == 0, "INT pin must stay 0 in messaged mode"
    assert slave.transaction_count() == 1, "expected exactly 1 APB txn"

    slave.stop()
    mark_coverage("messaged_apb")


# ─────────────────────────────────────────────────────────────
# T4: PWDATA equals ISR value
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_04_pwdata_equals_isr(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=1)
    cocotb.start_soon(slave.start())

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFB)   # unmask IRQ2
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MADDR_LO, 0x00)
    await cpu_write(dut, ADDR_MADDR_HI, 0x00)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x04)          # IRQ2
    await wait_for_txns(dut, slave, 1, timeout=40)

    isr_val = await cpu_read(dut, ADDR_ISR)
    txn = slave.last_transaction()
    assert txn is not None, "no APB txn recorded"
    assert txn["data"] == isr_val, f"PWDATA=0x{txn['data']:02X} != ISR=0x{isr_val:02X}"
    assert isr_val == 0x04, f"ISR expected 0x04 for IRQ2, got 0x{isr_val:02X}"

    slave.stop()
    mark_coverage("pwdata_equals_isr")


# ─────────────────────────────────────────────────────────────
# T5: PADDR matches MADDR registers
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_05_apb_target_address(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=1)
    cocotb.start_soon(slave.start())

    target_lo, target_hi = 0xBC, 0xDE
    expected_addr = (target_hi << 8) | target_lo

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFE)
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MADDR_LO, target_lo)
    await cpu_write(dut, ADDR_MADDR_HI, target_hi)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x01)
    await wait_for_txns(dut, slave, 1, timeout=40)

    txn = slave.last_transaction()
    assert txn is not None, "no APB txn recorded"
    assert txn["addr"] == expected_addr, \
        f"PADDR expected 0x{expected_addr:04X}, got 0x{txn['addr']:04X}"

    slave.stop()
    mark_coverage("paddr_config")


# ─────────────────────────────────────────────────────────────
# T6: PSLVERR sets sticky apb_err in MICR[1]
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_06_pslverr_sticky_error(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=1, inject_error=True)
    cocotb.start_soon(slave.start())

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFE)
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MADDR_LO, 0x00)
    await cpu_write(dut, ADDR_MADDR_HI, 0x00)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x01)
    await wait_apb_idle(dut, timeout=30)
    await RisingEdge(dut.clk)

    micr_val = await cpu_read(dut, ADDR_MICR)
    assert (micr_val >> 1) & 1, f"MICR[1] apb_err should be 1 after PSLVERR, MICR=0x{micr_val:02X}"

    slave.stop()
    mark_coverage("pslverr_sticky")


# ─────────────────────────────────────────────────────────────
# T7: apb_err W1C clear via MICR[1]
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_07_apb_err_w1c_clear(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=1, inject_error=True)
    cocotb.start_soon(slave.start())

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFE)
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x01)
    await wait_apb_idle(dut, timeout=30)
    await RisingEdge(dut.clk)

    micr_before = await cpu_read(dut, ADDR_MICR)
    assert (micr_before >> 1) & 1, f"apb_err not set before clear, MICR=0x{micr_before:02X}"

    await cpu_write(dut, ADDR_MICR, 0x02)   # W1C bit[1]
    await RisingEdge(dut.clk)

    micr_after = await cpu_read(dut, ADDR_MICR)
    assert not ((micr_after >> 1) & 1), f"apb_err should be 0 after W1C, MICR=0x{micr_after:02X}"

    slave.stop()
    mark_coverage("apb_err_w1c")


# ─────────────────────────────────────────────────────────────
# T8: apb_busy asserted during transaction (extra check, no coverage point)
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_08_apb_busy_signal(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=3)
    cocotb.start_soon(slave.start())

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFE)
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x01)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    busy_during = int(dut.apb_busy.value)
    await wait_apb_idle(dut, timeout=30)
    busy_after = int(dut.apb_busy.value)

    assert busy_during == 1, f"apb_busy should be 1 during txn, got {busy_during}"
    assert busy_after == 0, f"apb_busy should be 0 after txn, got {busy_after}"

    slave.stop()


# ─────────────────────────────────────────────────────────────
# T9: Software interrupt in messaged mode
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_09_sw_interrupt_messaged(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=1)
    cocotb.start_soon(slave.start())

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xF7)   # unmask IRQ3
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MADDR_LO, 0x40)
    await cpu_write(dut, ADDR_MADDR_HI, 0x00)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await cpu_write(dut, ADDR_SWIR, 0x08)  # SW inject IRQ3
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await cpu_write(dut, ADDR_SWIR, 0x00)

    await wait_for_txns(dut, slave, 1, timeout=40)
    txn = slave.last_transaction()
    assert txn is not None, "no APB txn for SW interrupt"
    assert txn["data"] == 0x08, f"expected PWDATA=0x08 for IRQ3, got 0x{txn['data']:02X}"

    slave.stop()
    mark_coverage("sw_interrupt")


# ─────────────────────────────────────────────────────────────
# T10: Mode switch line -> messaged (extra check, no coverage point)
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_10_mode_switch(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=1)
    cocotb.start_soon(slave.start())

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFE)
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MADDR_LO, 0x10)
    await cpu_write(dut, ADDR_MADDR_HI, 0x00)

    await cpu_write(dut, ADDR_MICR, 0x00)   # line mode
    await fire_irq_edge(dut, 0x01)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert int(dut.INT.value) == 1, "INT should be high in line mode"
    assert slave.transaction_count() == 0, "no APB txn in line mode"
    await cpu_ack(dut)
    await RisingEdge(dut.clk)

    await cpu_write(dut, ADDR_MICR, 0x01)   # messaged mode
    await fire_irq_edge(dut, 0x01)
    await wait_for_txns(dut, slave, 1, timeout=40)
    assert int(dut.INT.value) == 0, "INT should be 0 in messaged mode"
    assert slave.transaction_count() == 1, "expected 1 APB txn after switch"

    slave.stop()


# ─────────────────────────────────────────────────────────────
# T11: Pending interrupt during APB is retained and serviced after ACK
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_11_pending_irq_during_apb(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=3)
    cocotb.start_soon(slave.start())

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFC)   # unmask IRQ0 and IRQ1
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MADDR_LO, 0x00)
    await cpu_write(dut, ADDR_MADDR_HI, 0x20)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x01)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    # second IRQ arrives while the first APB txn is in flight
    await fire_irq_edge(dut, 0x02)

    await wait_for_txns(dut, slave, 1, timeout=60)
    assert slave.transaction_count() == 1, \
        f"expected 1 APB txn after first IRQ, got {slave.transaction_count()}"

    ipr_val = await cpu_read(dut, ADDR_IPR)
    assert ipr_val == 0x02, f"IRQ1 should remain pending in IPR, got 0x{ipr_val:02X}"

    # ACK the first interrupt so the controller services the pending IRQ1
    await cpu_ack(dut)
    await wait_for_txns(dut, slave, 2, timeout=80)
    assert slave.transaction_count() == 2, \
        f"expected 2nd APB txn after ACK, got {slave.transaction_count()}"

    second_txn = slave.transactions[1]
    assert second_txn["data"] == 0x02, \
        f"2nd APB payload should be 0x02 for IRQ1, got 0x{second_txn['data']:02X}"

    ipr_after = await cpu_read(dut, ADDR_IPR)
    assert ipr_after == 0x00, f"IPR should clear after IRQ1 issued, got 0x{ipr_after:02X}"

    slave.stop()
    mark_coverage("pending_irq_during_apb")


# ─────────────────────────────────────────────────────────────
# T12: Delayed APB response (>500 clk) asserts soft_reset
# NOTE: no APB slave is started, so PREADY stays low and the access
# phase stalls; soft_reset must assert at the delayed-response threshold.
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_12_apb_delayed_response_soft_reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)  # no slave coroutine -> PREADY never asserts

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFE)
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MADDR_LO, 0x00)
    await cpu_write(dut, ADDR_MADDR_HI, 0x00)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x01)

    saw_soft = False
    for _ in range(800):  # threshold is 500 clk; give margin, stay below the 2000 WDT
        await RisingEdge(dut.clk)
        if int(dut.soft_reset.value) == 1:
            saw_soft = True
            break
    assert saw_soft, "soft_reset should assert on a delayed APB response (>500 clk)"
    assert int(dut.hard_reset.value) == 0, "hard_reset must not fire before the no-response threshold"

    mark_coverage("apb_delayed_reset")


# ─────────────────────────────────────────────────────────────
# T13: No APB response (>2000 clk) asserts hard_reset (watchdog)
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_13_apb_no_response_hard_reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)  # no slave coroutine -> PREADY never asserts

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFE)
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MADDR_LO, 0x00)
    await cpu_write(dut, ADDR_MADDR_HI, 0x00)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x01)

    saw_hard = False
    for _ in range(2200):  # threshold is 2000 clk
        await RisingEdge(dut.clk)
        if int(dut.hard_reset.value) == 1:
            saw_hard = True
            break
    assert saw_hard, "hard_reset (watchdog) should assert on no APB response (>2000 clk)"

    # After the watchdog fires, the stuck interrupt is abandoned.
    isr_val = await cpu_read(dut, ADDR_ISR)
    assert isr_val == 0x00, f"ISR should be cleared by the watchdog, got 0x{isr_val:02X}"

    mark_coverage("apb_no_response_reset")


# ─────────────────────────────────────────────────────────────
# T14: Fixed-priority arbitration — IRQ0 wins over IRQ1 when both pending
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_14_irq_priority_order(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=1)
    cocotb.start_soon(slave.start())

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFC)   # unmask IRQ0 and IRQ1
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MADDR_LO, 0x00)
    await cpu_write(dut, ADDR_MADDR_HI, 0x00)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x03)          # IRQ0 and IRQ1 pending in the same cycle
    await wait_for_txns(dut, slave, 1, timeout=40)

    txn = slave.last_transaction()
    assert txn is not None, "no APB txn recorded"
    assert txn["data"] == 0x01, \
        f"IRQ0 (highest priority) should be serviced first, got PWDATA=0x{txn['data']:02X}"

    isr_val = await cpu_read(dut, ADDR_ISR)
    assert isr_val == 0x01, f"ISR expected 0x01 for IRQ0, got 0x{isr_val:02X}"

    ipr_val = await cpu_read(dut, ADDR_IPR)
    assert ipr_val == 0x02, f"IRQ1 should remain pending behind IRQ0, got IPR=0x{ipr_val:02X}"

    slave.stop()
    mark_coverage("irq_priority_order")


# ─────────────────────────────────────────────────────────────
# T15: A masked IRQ never becomes pending or fires
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_15_irq_masking(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    slave = APBSlaveModel(dut, ready_latency=1)
    cocotb.start_soon(slave.start())

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFF)   # everything masked
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x01)         # IRQ0, but masked
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    ipr_val = await cpu_read(dut, ADDR_IPR)
    assert ipr_val == 0x00, f"masked IRQ0 must never become pending, got IPR=0x{ipr_val:02X}"
    assert slave.transaction_count() == 0, "masked IRQ0 must not trigger an APB txn"
    assert int(dut.INT.value) == 0, "masked IRQ0 must not assert INT"

    slave.stop()
    mark_coverage("irq_masking")


# ─────────────────────────────────────────────────────────────
# T16: Level-triggered channel re-arms on its own; edge-triggered needs a fresh edge
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_16_edge_level_trigger(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)

    await cpu_write(dut, ADDR_TRIG, 0xEF)   # channel 4 = level, rest = edge
    await cpu_write(dut, ADDR_IMR, 0xEF)    # unmask channel 4 only
    await cpu_write(dut, ADDR_GCR, 0x01)    # GIE=1, line mode

    await RisingEdge(dut.clk)
    dut.irq.value = 0x10                   # drive IRQ4 high and HOLD - no further edge ever

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.INT.value) == 1:
            break
    assert int(dut.INT.value) == 1, "level-triggered IRQ4 should assert INT"
    assert int(dut.INT_VECT.value) == 4, f"expected vector 4, got {int(dut.INT_VECT.value)}"

    await cpu_ack(dut)

    # irq[4] is still held high with no new edge: a level-triggered source must re-arm on
    # its own once the mask/ISR allow it (this can happen as soon as the very next clock,
    # since ipr's bit4 has been continuously re-set by the held level the whole time). A
    # trig_mode implementation stuck at edge-only would never see INT again here.
    reasserted = False
    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.INT.value) == 1:
            reasserted = True
            break
    assert reasserted, "level-triggered IRQ4 held high should re-trigger without a new edge"

    dut.irq.value = 0
    await cpu_ack(dut)
    mark_coverage("edge_level_trigger")


# ─────────────────────────────────────────────────────────────
# T17: A new IRQ pending in the same cycle as a CPU IPR W1C write is not dropped
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_17_ipr_set_ack_race(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFC)   # unmask IRQ0 and IRQ1
    await cpu_write(dut, ADDR_GCR, 0x00)   # GIE=0: keep IPR from being drained into ISR/APB

    # Get IRQ0 pending first, so the CPU write below has something unrelated to W1C-clear.
    await fire_irq_edge(dut, 0x01)
    await RisingEdge(dut.clk)
    ipr_before = await cpu_read(dut, ADDR_IPR)
    assert ipr_before == 0x01, f"expected IRQ0 pending before the race, got 0x{ipr_before:02X}"

    # Drive IRQ1 high (fresh edge) in the exact same cycle the CPU issues a W1C write to IPR
    # that clears IRQ0's bit only - IRQ1's bit must still land in IPR despite the collision.
    await RisingEdge(dut.clk)
    dut.cpu_wr.value = 1
    dut.cpu_rd.value = 0
    dut.cpu_addr.value = ADDR_IPR
    dut.cpu_wdata.value = 0x01              # W1C clears IRQ0 only
    dut.irq.value = 0x02                    # IRQ1 rising edge lands on this same clock
    await RisingEdge(dut.clk)
    dut.cpu_wr.value = 0
    dut.cpu_wdata.value = 0
    dut.irq.value = 0

    ipr_after = await cpu_read(dut, ADDR_IPR)
    assert ipr_after == 0x02, \
        f"IRQ1 pending in the same cycle as the IPR W1C write must survive, got 0x{ipr_after:02X}"

    mark_coverage("ipr_set_ack_race")


# ─────────────────────────────────────────────────────────────
# T18: soft_reset asserts exactly one clock after apb_wait_cnt is observed at the documented
# threshold (apb_wait_cnt registers the pre-increment count that the comparator used, so the
# comparator's own "wait_cnt >= threshold" trip is only visible on the following sample -
# see apb_wait_cnt in rtl/interrupt_controller.sv). Not one clock later, not one earlier.
# ─────────────────────────────────────────────────────────────
@cocotb.test()
async def test_18_apb_threshold_boundary(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)  # no slave coroutine -> PREADY never asserts

    await cpu_write(dut, ADDR_TRIG, 0xFF)
    await cpu_write(dut, ADDR_IMR, 0xFE)
    await cpu_write(dut, ADDR_GCR, 0x01)
    await cpu_write(dut, ADDR_MADDR_LO, 0x00)
    await cpu_write(dut, ADDR_MADDR_HI, 0x00)
    await cpu_write(dut, ADDR_MICR, 0x01)

    await fire_irq_edge(dut, 0x01)

    threshold = 500
    boundary_seen = False
    prev_wait_cnt = None
    for _ in range(800):
        await RisingEdge(dut.clk)
        wait_cnt = int(dut.apb_wait_cnt.value)
        soft = int(dut.soft_reset.value)
        if prev_wait_cnt == threshold:
            assert soft == 1, (
                f"soft_reset must assert the clock after apb_wait_cnt is observed at "
                f"{threshold} (prev apb_wait_cnt={prev_wait_cnt}, now={wait_cnt}, soft_reset=0)"
            )
            boundary_seen = True
            break
        if prev_wait_cnt is not None and prev_wait_cnt < threshold:
            assert soft == 0, (
                f"soft_reset asserted early (prev apb_wait_cnt={prev_wait_cnt} < {threshold})"
            )
        prev_wait_cnt = wait_cnt
    assert boundary_seen, "apb_wait_cnt never reached the delayed-response threshold"

    mark_coverage("apb_threshold_boundary")
