# Tetris Duel: FPGA project (Digital System Fundamentals 2569)

Two-player versus Tetris on two EDGE Spartan-7 boards. This folder holds all
of our VHDL, the hardware test designs, simulation testbenches and helper
scripts.

Deadline: **Fri 30 Oct 2026**. Be ready from 09:00; everything is due by 16:00.

---

## Folder layout

```
assignment\
  README.md               <- this file
  docs\
    concepts.md           <- how everything works (VGA, serial, J5, clocks...)
    learn\                <- VHDL + Vivado course: line-by-line walkthrough of our code
    HANDOFF.md            <- project status notes (for Claude after a context reset)
  src\
    common\               <- reusable building blocks, shared by every design
      common_pkg.vhd      <-   constants (50 MHz, 115200 baud) + 7-seg glyphs
      debounce.vhd        <-   clean push button: sync + debounce + 1 pulse/press
      seg7_scan.vhd       <-   4-digit 7-segment display driver
      vga_sync.vhd        <-   640x480 @ 60 Hz VGA timing
      uart_tx.vhd         <-   serial transmitter (send one byte)
      uart_rx.vhd         <-   serial receiver (receive one byte)
  tests\                  <- small designs that each test ONE piece of hardware
    01_vga_bars\          <-   picture on a VGA monitor
    02_j5_pin_finder\     <-   confirm which FPGA pin is on which J5 header pin
    03_uart_echo\         <-   talk to the PC over the USB serial port
    04_board_link\        <-   two boards talking over jumper wires
    05_uart_probe\        <-   finds which USB-serial pin is TX and which is RX
       (each has: top_*.vhd, project.txt, pins.xdc, README.md, build\*.bit)
  sim\                    <- testbenches (run on the PC, no board needed)
    tb_uart_loop.vhd      <-   checks uart_tx -> uart_rx
    tb_vga_frame.vhd      <-   checks VGA timing + saves one frame as a PNG
    tb_uart_probe.vhd     <-   checks test 05 with both possible wirings
    out\                  <-   simulator output (frame.png etc.)
  tools\                  <- scripts
    build.bat             <-   build one design to .bit (+ timing report)
    build_all.bat         <-   build every test
    program.bat           <-   load a .bit into the board (or into flash)
    sim.bat               <-   run a testbench
    load_into_builder.bat <-   fill the TA's FPGA Builder with one of our designs
    vivado_gui.bat        <-   open a design (+ testbench) in the Vivado GUI
```

Every design is described by two small text files:

* `project.txt`: the top entity name and the list of VHDL files, in compile
  order (the package `common_pkg.vhd` first).
* `pins.xdc`: which FPGA pin each port of the top entity connects to.

Both the scripts and `load_into_builder` read these, so there is one place to
change things.

---

## Quick start: test the hardware today

The `.bit` files are already built in each `tests\*\build\` folder, so you can
go straight to loading them. Do the tests in order; each one says what you
should see in its own README.

| # | Test | You need | Pass when |
|---|------|----------|-----------|
| 01 | `01_vga_bars` | 1 board + VGA monitor | colour bars, ramps, grid and bouncing square all look right |
| 02 | `02_j5_pin_finder` | 1 board + multimeter or LED+330 Ω | the pin shown on the display is the one at 3.3 V, for all 16 |
| 03 | `03_uart_echo` | 1 board + PuTTY | what you type comes back in CAPITALS; PB3 prints a message |
| 05 | `05_uart_probe` | 1 board + PuTTY | display shows which pin the PC talks on, then it echoes like 03 |
| 04 | `04_board_link` | 2 boards + 3 jumper wires + 2×330 Ω | each board shows the other board's switches |

### Option A: use the TA's FPGA Builder (what you already know)

1. **Close FPGA Builder** if it is open.
2. Double-click `tools\load_into_builder.bat`, type e.g. `01_vga_bars`.
   This fills the Builder with our VHDL files and every pin (your old Builder
   settings are saved as `fpga_builder.backup.json` next to the exe).
3. Open `D:\setup\FPGA_Builder_Package_V9\FPGA_Builder.exe`.
   Tabs 1 and 2 are already filled in. Don't press "ดึงขาจาก VHDL", it would
   only re-read the same ports.
4. Press **Build .bit**, then **Program** → Normal Rom.
   (Or skip the build: Program can load our ready-made `tests\01_vga_bars\build\top_vga_bars.bit`.)

### Option B: use our scripts (also gives a timing report)

Open a Command Prompt in `D:\setup\assignment` and run:

```
tools\build.bat 01_vga_bars       (about 1-2 minutes)
tools\program.bat 01_vga_bars     (loads it into the board)
```

`tools\program.bat 01_vga_bars flash` writes it permanently into the board's
flash instead (use only for the final version, flash wears out).

The build prints `WNS : x.xxx ns`. That number must be **0 or more**. It means
the design is fast enough for the 50 MHz clock. The TA Builder never shows
this, which is why these scripts exist. Detailed reports land in
`tests\<name>\build\timing.txt` and `utilization.txt`.

### Simulation (no board needed)

```
tools\sim.bat tb_uart_loop        -> prints TEST PASSED
tools\sim.bat tb_vga_frame 2      -> prints TIMING PASSED, writes sim\out\frame.png
```

`sim\out\preview_all_patterns.png` shows what test 01 should look like on the
monitor, generated from the simulation.

---

## Rules we follow in all VHDL

1. **One clock.** Everything runs on the 50 MHz clock (`clk`, pin H11).
   Slower things use one-clock "enable pulses" (`pix_en`, `frame_tick`,
   1-second counters), never a divided clock signal. See `docs\concepts.md`.
2. **Synchronise every input** that comes from outside (buttons, switches,
   the rx wire) through two flip-flops before using it.
3. **VHDL-93 only** (the TA Builder reads files as VHDL-93):
   * no `process(all)`, list the signals instead;
   * don't read an `out` port inside its own entity, use an internal signal;
   * only plain signals or constants in a port map, never `a and b` or
     `func(sig)`: put it in a signal first.
4. **Every file starts with a comment block** saying what it does and how.
   The design document will reuse this text.
5. Folder paths must have **no spaces and no Thai** (Vivado fails otherwise).

---

## Verified so far (15 Oct 2026, on the PC)

| Check | Result |
|---|---|
| `tb_uart_loop` (6 bytes through tx → rx) | PASSED |
| `tb_vga_frame`, all 4 pictures | TIMING PASSED, images correct, edge pixels exactly at 0 and 639 / 0 and 479 |
| Build of all 4 tests (Vivado 2025.2, XC7S15) | all OK, WNS +14.3 to +15.5 ns, under 3% of LUTs used |
| On the real board (16 Oct) | 01 VGA works perfectly. 02/03/04: 7-seg was unreadable (digit enables are active-HIGH, fixed in `seg7_scan`, rebuilt). 03: no reply from the board → test 05 added |
| `tb_uart_probe` (16 Oct) | PASSED for both wirings |

The builds of tests 03 and 04 print one harmless warning:
`[Synth 8-13157] FSM with state register 'state_reg' is not having reset`.
It refers to the receiver's state machine in `uart_rx.vhd`. It has no reset
button, but its starting value (`S_IDLE`) is loaded when the FPGA is
configured, and any glitch on the wire just returns it to `S_IDLE`.
