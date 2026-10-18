# Test 02: J5 pin finder

**Goal:** confirm which FPGA pin is wired to each pin of the J5 expansion
header, before we use J5 for the cable between the two boards.
(What J5 is: `docs\concepts.md` §8.)

**Files:** `top_j5_finder.vhd` + `debounce.vhd`, `seg7_scan.vhd`,
`common_pkg.vhd`. Ready-built: `build\top_j5_finder.bit`.

## You need

* the board, with **nothing plugged into J5**;
* a multimeter (DC volts), **or** an LED with a 330 Ω resistor and two
  jumper wires;
* jumper J9 removed (otherwise LEDs D10–D17 flicker with the display; harmless).

## Steps

1. Find pin 1 of J5 on the board (marked with a triangle, "1" or a square
   pad). Odd pins (1, 3, 5 … 19) are one row, even pins (2, 4 … 20) the
   other.
2. Load the design: `tools\program.bat 02_j5_pin_finder` (or via the Builder).
3. The display shows **`J5.05`**, then `J5.06`, `J5.07` … `J5.20` and back to
   `J5.05`, one step per second. The number is the J5 header pin that should
   be at 3.3 V right now; all other J5 pins are at 0 V.
4. Press **PB3** (SW18, middle button) to pause (the right-most dot lights).
   Use **PB1** (SW14) / **PB5** (SW23) to step back / forward.
5. For each number 05 … 20, check that pin:
   * **Multimeter:** black probe on J5 pin 2 or 4 (GND), red probe on the pin
     → about **3.3 V** on the pin shown, about **0 V** on its neighbours.
   * **LED:** LED + 330 Ω in series from the pin to GND (J5 pin 2/4). The LED's
     long leg goes toward the pin. It lights only on the pin shown.
6. Fill in the table below.

| Display | Expected FPGA pin | Header pin that was actually high |
|---|---|---|
| 05 | L14 | |
| 06 | M13 | |
| 07 | H14 | |
| 08 | H13 | |
| 09 | F11 | |
| 10 | G11 | |
| 11 | C14 | |
| 12 | D14 | |
| 13 | E13 | |
| 14 | F13 | |
| 15 | F14 | |
| 16 | G14 | |
| 17 | D13 | |
| 18 | D12 | |
| 19 | E12 | |
| 20 | F12 | |

**All match →** J5 is confirmed; test 04 can use pins 5 and 6 as they are.
**Some differ →** tell me the table and I'll fix the pin lists.

## Safety

* Never touch the probe/LED between pin 1 (5 V) or pin 3 (3.3 V) and a signal
  pin.
* Always use the resistor with an LED; without it the LED and the FPGA pin can
  be damaged.

## How the code works

* `idx` (0..15) says which line is high; `j5_r(idx) <= '1'` with all others
  `'0'` ("one-hot"). `j5(0)` is constrained to header pin 5 (L14) … `j5(15)` to
  pin 20 (F12) in `pins.xdc`.
* A counter of 50,000,000 clocks = 1 second advances `idx` while running.
* The three buttons go through `debounce`, so each press is exactly one step.
* The display shows `J`, `5`, then (idx + 5) as two decimal digits, with the
  dot after the 5.
