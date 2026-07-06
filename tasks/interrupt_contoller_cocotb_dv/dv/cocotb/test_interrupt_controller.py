
# =============================================================
# Starter cocotb testbench for interrupt_controller_apb.
#
# This skeleton compiles and passes a single reset check. YOUR JOB is to flesh it out into a
# real verification environment: drive the CPU register interface and IRQ lines, model the
# APB slave, and check line-mode INT, messaged-mode APB writes (PWDATA==ISR, PADDR==MADDR),
# PSLVERR sticky error + W1C clear, software interrupts, and pending-interrupt handling.
#
# Record each verified scenario with the mark_coverage helper (see COVERAGE_POINTS below and
# the list in prompt.md). See prompt.md for the full rubric.
# =============================================================

import json
import logging
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# Register address map (matches the RTL).
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

# Coverage points the grader looks for (write them via the helper below).
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
    """Record a covered scenario. The grader passes INTC_COVERAGE_FILE in the environment."""
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


@cocotb.test()
async def test_reset_state(dut):
    """Minimal starting point: verify the controller comes out of reset in a known state."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)

    assert (await cpu_read(dut, ADDR_IMR)) == 0xFF, "IMR should reset to 0xFF"
    assert (await cpu_read(dut, ADDR_GCR)) == 0x00, "GCR should reset to 0x00"
    assert int(dut.PSEL.value) == 0, "PSEL should be 0 at reset"
    assert int(dut.INT.value) == 0, "INT should be 0 at reset"

    # TODO: add tests for line-mode INT, messaged-mode APB, PWDATA/PADDR, PSLVERR sticky +
    # W1C, software interrupts, and pending-interrupt handling — and record each with the
    # coverage helper.
