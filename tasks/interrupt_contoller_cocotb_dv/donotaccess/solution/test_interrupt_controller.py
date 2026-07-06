
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
