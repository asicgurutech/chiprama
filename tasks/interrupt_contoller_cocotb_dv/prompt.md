Build a cocotb verification environment for the `interrupt_controller_apb` module — an
8-source interrupt controller with a fixed-priority encoder, maskable/pending/service
registers (IMR/IPR/ISR), software-injectable interrupts, a global interrupt enable, and an
APB master that delivers *messaged* interrupts when `MICR[0]` is set (otherwise the legacy
`INT` line is driven).

Edit `dv/cocotb/test_interrupt_controller.py` so it implements meaningful drivers, an APB
slave model, and self-checking assertions covering:

- **reset** — registers come out of reset in their documented state, APB idle, `INT` low.
- **line_interrupt** — in line mode (`MICR[0]=0`) an unmasked IRQ asserts `INT`/`INT_VECT`
  and fires no APB transaction; `cpu_ack` clears it.
- **messaged_apb** — in messaged mode (`MICR[0]=1`) an interrupt drives an APB write instead
  of `INT`.
- **pwdata_equals_isr** — the APB `PWDATA` payload equals the `ISR` value.
- **paddr_config** — `PADDR` equals `{MADDR_HI, MADDR_LO}`.
- **pslverr_sticky** — a slave `PSLVERR` sets the sticky `apb_err` bit (`MICR[1]`).
- **apb_err_w1c** — writing 1 to `MICR[1]` clears the sticky error.
- **sw_interrupt** — a software-injected interrupt (`SWIR`) delivers over APB in messaged mode.
- **pending_irq_during_apb** — an interrupt raised while an APB transaction is in flight stays
  pending and is serviced (a second APB message) after the first is acknowledged.
- **apb_delayed_reset** — when an APB access phase stays unanswered beyond the delayed-response
  threshold (500 clocks), the `soft_reset` output asserts (and the error is recorded).
- **apb_no_response_reset** — when an APB access phase stays unanswered beyond the no-response
  threshold (2000 clocks), the `hard_reset` watchdog output asserts and the stuck interrupt is
  abandoned.

Mark each verified scenario by calling `mark_coverage("<point>")` with the exact names above.
The register map, APB FSM behavior, and signal names are described in `README.md` and the RTL
header comment in `rtl/interrupt_controller.sv`.

Run your testbench with `make test` (or `python3 scripts/run_cocotb.py ...`). Do **not** edit
the RTL, the Makefile, `filelist.f`, or the helper scripts — only the testbench.
