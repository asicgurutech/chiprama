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
