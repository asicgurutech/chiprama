Interrupt Controller 
====================

Features :
1.	8 External Interrupts, input to the design 
2.	3-bit interrupt vector as Line interrupt output
3.	Fixed Priority Encoder is present to prioritize between interrupts. IRQ0 has highest priority 
4.	Interrupt Mask Register to mask any h/w interrupts to be masked
5.	Interrupt Status Register to capture available interrupts 
6.	Interrupt Pending Register to check which interrupts are yet to be serviced
7.	Option for S/W injectable interrupts 
8.	Handles both Edge/Level Triggered interrupts 
9.	Handles both Line interrupt and Message Interrupt
10.	MICR register to decide between Line or Message interrupt 
11.	APB interface for sending message interrupt 
12.	ISR data to be fed as message interrupt write data
13.	All registers are 8bit wide 
14.	Error handling for APB response 
15.	One-bit Global Interrupt Enable


Possible DV Bugs: 
Complex: 
(1) Race Conditions between APB data and interrupt source data:
         Scoreboard not taking care of case where APB write transaction and interrupt source update, both are happening concurrently.
(2) Incorrect ISR due to bug in Scoreboard’s Priority Encoder modelling:
         The priority encoder model in scoreboard might not correctly determine the highest priority interrupt, especially in the presence of simultaneous interrupts. This could lead to incorrect ISR vector being loaded.
(3) Faulty handling of delayed APB response or No Response 
       Scoreboard needs to account for the cases where APB response is delayed. If RTL has a response timeout but similar mechanism is missing in scoreboard, that would result into mismatch between RTL & Scoreboard. If the APB Access phase is extended beyond 500 Clocks, it will be called as Delayed Response and if more than 2000 Clock, it will called No Response. In delayed Response, Soft Reset should assert and in Delayed Response, Hard Reset (e.g. Watchdog Timeout) should assert.
(4) Software Interrupt Race with Hardware Interrupts: 
     Test should set software interrupt (SWIR) while a hardware interrupt is being processed, and scoreboard to check if it may lead to conflicts in status registers and cause erroneous behavior or missed interrupts. 