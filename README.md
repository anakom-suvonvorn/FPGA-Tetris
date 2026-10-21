# Tetris Duel (versus core): FPGA project

Two-player versus Tetris on two **EDGE Spartan-7** boards (Xilinx XC7S15),
written in VHDL. Final project for Digital System Fundamentals (01076113),
CE KMITL, 2569. Everything runs inside the FPGA: game logic, VGA picture,
sound, and the link between the boards.

> **This is the `main` branch.** **Versus Tetris** for two boards: garbage lines, a rival bar, win / lose / draw. With no second board it plays single player.

## The three branches

The project grew in layers; each layer is a branch that builds on the one
before. All three are complete and work on their own: pick the one you want
with `git checkout <branch>`. Each has its own ready-built
`game/build/top_tetris.bit`.

| branch | what it is | built on | on real hardware | LUTs of 8,000 |
|---|---|---|---|---|
| **`main`** (you are here) | Versus Tetris: two boards linked by 3 wires, garbage, rival bar, win / lose / draw; single player without a link | - | played on two boards | 3,496 (44 %) |
| `chaos` | + CHAOS layer: slide-switch tasks, attacks sent over the link, bonuses | `main` | played on two boards | 6,200 (78 %) |
| `media` | + media from the SPI flash: music, video attacks, win / lose clips, sprites; + hardware test 06 | `chaos` | tested on the boards | 6,797 (85 %), all 10 block RAMs |

* **`main`** is the plain game: the smallest design, the easiest to read.
* **`chaos`** adds the slide-switch tasks and attacks. It needs nothing extra.
* **`media`** adds pictures and sound from the flash chip. It needs the media
  file written into each board's flash once (see below); without it, it plays
  like `chaos` with no music.

## What you need

* 2 EDGE Spartan-7 boards (1 is enough for single player), each with a VGA
  monitor
* 3 jumper wires + two 330 Ω resistors to link the boards (header J5)
* headphones or powered speakers on the audio jack (optional; the buzzer
  needs jumper J6)
* a Windows PC with Vivado 2025.2 (the scripts look in
  `D:\AMDDesignTools\2025.2`, then in the TA's FPGA Builder package), or
  just the TA's FPGA Builder to load the ready-built `.bit` files.
  Keep the project in a folder path **without spaces or Thai letters**.

## Quick start

1. **Load the game into both boards** (the same `.bit` on both):
   `tools\program.bat game`, or with the TA's FPGA Builder:
   `tools\load_into_builder.bat` -> type `game` -> open the Builder -> Program.
   The ready-built bitstream is `game\build\top_tetris.bit`.
2. **Connect the boards** with 3 jumper wires on header J5 (two 330 Ω
   resistors in the signal wires):
   ```
   Board A  J5 pin 5 (TX) ---[330 Ω]---> J5 pin 6 (RX)  Board B
   Board A  J5 pin 6 (RX) <---[330 Ω]--- J5 pin 5 (TX)  Board B
   Board A  J5 pin 2 (GND) ------------- J5 pin 2 (GND) Board B
   ```
   Within half a second both screens say **LINKED**. Without a second
   board: play alone, or let the PC play the rival (SW7 up, then
   `python tools\fake_opponent.py COM3`).
3. A VGA monitor on each board, headphones or speakers on the audio jack.
   Press **SW18** to start.

Full rules, screen layout and the PC test opponent: [`game/README.md`](game/README.md).

## Controls

The 5 push buttons form a cross:

```
              SW16 rotate
   SW14 left  SW18 hard drop   SW20 right      (hold left / right to keep moving)
              SW23 soft drop (hold)
```

SW18 (centre) also **starts a round**, on both boards at once in versus
(from 1.5 s after the last round ended; PRESS START shows when).

| slide switch (up = on) | does |
|---|---|
| SW2 (rightmost) | pause |
| SW4 | music (the Tetris theme, beeps) |
| SW5 | sound effects |
| SW7 | link to the PC over USB instead of the J5 cable (for `tools\fake_opponent.py`) |

The 7-segment display shows your cleared lines.

## What happens in the game

**Versus.** Clearing 2 / 3 / 4 lines at once sends 1 / 2 / 4 garbage lines
to the rival. They wait in a red meter next to the field; lines you clear
first cancel them, otherwise they rise from the bottom as grey rows with one
hole. The RIVAL bar on the left shows how high the other stack is. Last one
standing wins. Up to 8 waiting garbage lines come in at once.

## Build, load, simulate

From a Command Prompt in the project folder:

```
tools\build.bat game          build game\build\top_tetris.bit (a few minutes)
tools\program.bat game        load it into the board (temporary, until power-off)
tools\sim.bat tb_versus       run a testbench (no board needed)
```

`build.bat` prints **WNS** (worst negative slack): it must be 0 or more, which
means the design is fast enough for the 50 MHz clock. Reports land in
`game\build\timing.txt` and `utilization.txt`. The same commands work for
the tests: `tools\build.bat 01_vga_bars`, `tools\program.bat 01_vga_bars`.

Testbenches (`tools\sim.bat <name>`, look for TEST PASSED):

| testbench | checks |
|---|---|
| `tb_uart_loop` | uart_tx -> uart_rx |
| `tb_vga_frame` | VGA timing; saves a frame as a PNG |
| `tb_uart_probe` | test 05 with both wirings |
| `tb_switch_filter` | the slide switch debouncer |
| `tb_tetris_core` | a robot plays a whole game; no cells lost |
| `tb_versus` | two boards (core + link each) played by two robots |
| `tb_tetris_frame` | the whole design; screenshots of a game and of WIN! |

## Hardware tests

Small designs in `tests\` that each check one piece of the board. Each has a
README saying what you should see.

| test | checks |
|---|---|
| 01_vga_bars | VGA picture: colour bars, ramps, grid, a bouncing square |
| 02_j5_pin_finder | which FPGA pin is on which J5 header pin |
| 03_uart_echo | talking to the PC over the USB serial port |
| 04_board_link | two boards talking over jumper wires |
| 05_uart_probe | which USB-serial pin is TX and which is RX |

## Folder layout

```
  game\                top_tetris.vhd (the top level), pins.xdc, project.txt,
                        README.md, build\top_tetris.bit
  src\
    common\             reusable blocks: vga_sync, uart_tx / uart_rx, debounce,
                        switch_filter, seg7_scan, common_pkg
    game\               the game: tetris_core (rules), tetris_render (picture),
                        tetris_input, versus_link, tetris_sound, text_pkg, text_layer
  tests\               small designs that each test ONE piece of the hardware
    01_vga_bars  02_j5_pin_finder  03_uart_echo  04_board_link  05_uart_probe
                        (each: top_*.vhd, project.txt, pins.xdc, README.md, build\*.bit)
  sim\                 testbenches (+ a .prj file list each); sim\out = their output
  tools\               build.bat, program.bat, sim.bat, build_all.bat, vivado_gui.bat,
                        load_into_builder.bat (fills the TA's FPGA Builder), fake_opponent.py
  docs\
    learn\             the course: VHDL from zero, then every file line by line
    concepts.md         how VGA, serial, J5, clocks and timing work
    HANDOFF.md          project status notes
```

Every design (the game and each test) is described by two text files:
`project.txt` (the top entity + the VHDL files in compile order) and
`pins.xdc` (which FPGA pin each port uses). The scripts and the Builder
loader read these.

## Documentation

`docs/learn/` explains the whole design from zero, every file line by line:

1. [Part 1](docs/learn/01_vhdl_basics.md): VHDL from zero (for someone who knows schematics)
2. [Part 2](docs/learn/02_blocks_walkthrough.md): the building blocks in `src/common`, line by line
3. [Part 3](docs/learn/03_tests_walkthrough.md): the hardware tests and testbenches
4. [Part 4](docs/learn/04_vivado.md): using Vivado: GUI, simulation, timing
5. [Part 5](docs/learn/05_game_walkthrough.md): the Tetris game, line by line
6. [Part 6](docs/learn/06_versus_walkthrough.md): versus mode: the link, garbage, text, sound

Plus [`tetris_visual.html`](docs/learn/tetris_visual.html), an interactive
visual guide (11 sections; GitHub only shows its source, so download it and
open it in a browser).

## Rules we follow in all VHDL

1. **One clock.** Everything runs on the 50 MHz clock (pin H11). Slower
   things use one-clock enable pulses (`frame_tick`, ...), never a divided
   clock.
2. **Synchronise every outside input** (buttons, switches, the link wire)
   through two flip-flops before using it.
3. **VHDL-93 only** (the TA's Builder reads files as VHDL-93): no
   `process(all)`; don't read an `out` port inside its entity; only signals
   or constants in a port map.
4. **Every file starts with a comment block** saying what it does and how.

## Status

* Hardware tests 01, 02, 03 and 05 work on the real board (test 05 found
  that the USB-serial TX / RX pins are swapped compared with the manual:
  G1 = from the PC, F2 = to the PC). The two-board link of test 04 is what
  the game uses, and it works.
* The versus game was played on two real boards (19 Oct 2026).
* Every testbench above passes.
