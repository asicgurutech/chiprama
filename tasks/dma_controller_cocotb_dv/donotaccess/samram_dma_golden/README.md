# SAMRAM DMA Golden RTL

Prepared by: SAMRAM LLC for Chiparama LLC  
Project: Chiparama HUD Benchmark Task  
Confidentiality: Proprietary and confidential. Use only as authorized under the applicable project agreement.

## Purpose

This repository contains a golden RTL implementation and validation environment for a CSR-controlled DMA benchmark task. The design provides eight logical DMA channels sharing one AXI read/write master datapath, an APB software-programming interface, descriptor SRAM/ring support, per-channel completion interrupts, and fatal/error interrupt handling.

## Development Notice

Created independently by SAMRAM LLC. No third-party confidential or proprietary information, materials, tools, systems, documents, code, specifications, or resources were used.

## Deliverable Contents

```text
rtl/golden/samram_dma/          Golden RTL source files
rtl/golden/samram_dma/include/  Shared RTL include files
tb/golden/                      Verilog regression testbench and tests
tb/cocotb/                      cocotb AXI VIP smoke and randomized tests
sim/golden/                     Simulation Makefile and cocotb requirements
docs/golden/                    Golden RTL status and design notes
```

Build outputs, simulator logs, virtual environments, waveform files, backup archives, and intentionally buggy RTL variants are not part of the golden RTL deliverable.

## RTL Module Structure

```text
samram_dma_top.v             Top-level integration and public module interface
samram_dma_apb_decode.v      APB address/aperture decode
samram_dma_apb_resp_mux.v    APB read-data/ready/error response mux
samram_dma_csr_write_ctrl.v  CSR write command/control decode
samram_dma_csr_read_mux.v    CSR readback mux
samram_dma_desc_sram.v       Descriptor SRAM storage and APB descriptor access
samram_dma_desc_ring.v       Descriptor ring head/tail/count tracking
samram_dma_irq_ctrl.v        DONE/ERROR interrupt status, enables, and claim logic
samram_dma_scheduler.v       Channel scheduling and service-start helper logic
samram_dma_rr_arbiter.v      Round-robin channel selector
samram_dma_xfer_engine.v     DMA transfer engine, channel state, and AXI response handling
samram_dma_axi_master_out.v  AXI master output decode from transfer state
samram_dma_align.v           Source/destination alignment, WSTRB, and WDATA helper logic
include/samram_dma_defs.vh   Shared constants and field definitions
include/samram_dma_funcs.vh  Shared pure helper functions
```

## Top-Level Interfaces

The public RTL entry point is:

```text
module samram_dma_top
```

The top-level module exposes:

```text
Clock/reset: pclk, preset_n
APB slave:   CSR, descriptor, and interrupt register access
AXI master:  shared read/write DMA datapath
Interrupts:  per-channel done interrupt vector and fatal/error interrupt
```

## Channel Register Map

Each channel uses a `0x20` byte CSR stride:

```text
Channel N base = N * 0x20

Offset  Register
0x00    SRC_ADDR
0x04    DST_ADDR
0x08    LEN_BYTES
0x0c    CTRL
0x10    STATUS
0x14    DESC_HEAD
0x18    DESC_TAIL
0x1c    DESC_RING_STATUS
```

Important software-visible bits:

```text
CTRL[0]    START, write pulse, reads back as 0
CTRL[1]    CLEAR_DONE
CTRL[2]    CLEAR_ERROR
CTRL[3]    DESC_DOORBELL

STATUS[0]  BUSY
STATUS[1]  DONE
STATUS[2]  ERROR
```

## Descriptor SRAM Map

Descriptor SRAM is mapped at `0x1000` through `0x11ff`.

```text
8 channels
4 descriptor slots per channel
4 words per descriptor

Descriptor address = 0x1000 + channel*0x40 + slot*0x10 + word*0x4

word0  SRC_ADDR
word1  DST_ADDR
word2  LEN_BYTES
word3  CTRL_STATUS
```

## Interrupt Register Map

Interrupt CSRs are mapped at `0x0200` through `0x02ff`.

```text
0x0200  INT_DONE_STATUS
0x0204  INT_ERROR_STATUS
0x0208  INT_IRQ_ENABLE
0x020c  INT_FIQ_ENABLE
0x0210  INT_CLAIM
0x0214  INT_CLEAR
```

`INT_CLAIM` encoding:

```text
[31]   valid
[16]   class: 1 = ERROR/FIQ, 0 = DONE/IRQ
[2:0]  channel
```

Priority rule:

```text
ERROR/FIQ claims have priority over DONE/IRQ claims.
Lower-numbered channel has priority within the same class.
```

## Verification

The golden validation environment includes:

```text
Verilog regression testbench with directed CSR, descriptor, interrupt, alignment, error, and scheduling tests
cocotb AXI VIP smoke tests
cocotb AXI VIP randomized unaligned transfer tests
Verilator lint target through the simulation Makefile
```

Run from the golden simulation directory:

```bash
cd sim/golden

make clean
make regression
make cocotb_axi_vip_smoke
make cocotb_axi_vip_random
```

Expected result:

```text
SAMRAM DMA consolidated regression PASSED
cocotb smoke:  TESTS=2 PASS=2 FAIL=0
cocotb random: TESTS=2 PASS=2 FAIL=0
```

## Python Requirements for cocotb

Install cocotb dependencies from:

```bash
cd sim/golden
python -m pip install -r requirements-cocotb.txt
```

## Notes

This golden RTL is intended for benchmark/evaluation validation. It is not presented as production silicon signoff collateral.
