# Mutant Catalog

This DV task grades a submitted cocotb testbench against a correct golden `interrupt_controller_apb`
DUT and a set of hidden mutant DUTs. A good testbench PASSES on the golden DUT and FAILS
(kills) each mutant. Every mutant is a single-line change to the golden RTL and compiles
cleanly, so a testbench that never exercises the relevant behavior will fail to catch it.

1. **`intc_line_int_dead.sv` — line INT never asserts**
   - `INT` is tied to 0, so line-mode interrupts are never signalled.
   - Caught by a line-mode test that fires an unmasked IRQ and checks `INT == 1`.

2. **`intc_msg_no_apb.sv` — messaged mode never triggers APB**
   - The APB trigger is forced low; no APB transaction is ever launched in messaged mode.
   - Caught by a messaged-mode test that expects one APB transaction after an interrupt.

3. **`intc_pwdata_wrong.sv` — wrong APB payload**
   - `PWDATA` is driven with a constant (`0xAA`) instead of the latched ISR value.
   - Caught by asserting `PWDATA == ISR` for a known interrupt (e.g. IRQ2 -> 0x04).

4. **`intc_paddr_byteswap.sv` — byte-swapped target address**
   - `PADDR` is `{MADDR_LO, MADDR_HI}` instead of `{MADDR_HI, MADDR_LO}`.
   - Caught by configuring MADDR with distinct high/low bytes and checking `PADDR`.

5. **`intc_pslverr_ignored.sv` — slave error dropped**
   - A `PSLVERR` response never latches the sticky `apb_err` bit.
   - Caught by injecting `PSLVERR` and checking `MICR[1]` is set (and clears via W1C).

6. **`intc_pending_dropped.sv` — pending interrupt lost during APB**
   - `ipr_clear` is asserted unconditionally, so an interrupt raised while another is being
     serviced over APB is cleared without ever being delivered.
   - Caught by raising a second IRQ during an in-flight APB transaction, then ACKing the
     first and expecting a second APB message for the pending interrupt.

7. **`intc_no_soft_reset.sv` — delayed-response detection broken**
   - `soft_reset` is never asserted, so a delayed APB response (access phase > 500 clocks)
     goes unsignalled.
   - Caught by stalling an APB write (no `PREADY`) and checking `soft_reset` asserts.

8. **`intc_no_wdt_hard_reset.sv` — watchdog / no-response reset broken**
   - `hard_reset` is never asserted, so a total APB no-response (access phase > 2000 clocks)
     never trips the watchdog output.
   - Caught by stalling an APB write indefinitely and checking `hard_reset` asserts.

9. **`intc_priority_swapped.sv` — fixed-priority arbitration order broken**
   - The priority encoder's IRQ0 and IRQ1 vector assignments are swapped, so when both are
     simultaneously pending, IRQ1 wins instead of IRQ0 (documented as highest priority).
   - Caught by raising IRQ0 and IRQ1 in the same cycle and checking the serviced
     interrupt (ISR / vector / PWDATA) corresponds to IRQ0, not IRQ1.

10. **`intc_mask_bypassed.sv` — IMR masking bypassed**
    - `irq_active` no longer ANDs with `~imr`, so a masked interrupt source still fires.
    - Caught by masking a channel via IMR, firing it, and checking it does NOT become
      pending/serviced.

11. **`intc_trig_mode_stuck.sv` — edge/level trigger mode configuration ignored**
    - Writes to `TRIG` are dropped, so `trig_mode` stays at its reset value (all-edge)
      regardless of configuration.
    - Caught by configuring a channel as level-triggered, holding its `irq` line high
      across an ACK, and checking it re-triggers on its own (level semantics) instead of
      requiring a fresh edge.

12. **`intc_ipr_new_irq_race.sv` — new IRQ dropped on a same-cycle CPU IPR write**
    - The CPU's W1C write to IPR (`ipr <= (ipr | ipr_set) & ~cpu_wdata`) drops the
      `| ipr_set` term, so a new interrupt becoming pending in the exact same cycle as an
      unrelated CPU write to IPR is silently lost instead of OR'd in.
    - Caught by asserting a new unmasked IRQ in the same clock cycle the CPU performs an
      IPR W1C write (clearing a different bit) and checking the new IRQ's pending bit
      survives.

13. **`intc_soft_reset_offbyone.sv` — delayed-response threshold off by one clock**
    - `apb_delayed` compares against `DELAYED_RESP_THRESHOLD + 1` instead of
      `DELAYED_RESP_THRESHOLD`, so `soft_reset` asserts one clock late.
    - Caught by a boundary-precise test that checks `soft_reset` asserts in the same cycle
      `apb_wait_cnt` first reaches the documented threshold (500), not one cycle later.
