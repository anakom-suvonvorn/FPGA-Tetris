# Tetris Duel (CHAOS edition with media): FPGA project

Two-player versus Tetris on two **EDGE Spartan-7** boards (Xilinx XC7S15),
written in VHDL. Final project for Digital System Fundamentals (01076113),
CE KMITL, 2569. Everything runs inside the FPGA: game logic, VGA picture,
sound, and the link between the boards.

> **This is the `media` branch.** Everything on `chaos` **plus media from the board's SPI flash chip**: real music, three video attacks that play behind the rival's game (Bad Apple, OIIA OIIA, Jevil), a random clip or picture when you win or lose, Jevil floating over the screen and friends' faces on the bouncers.

## The three branches

The project grew in layers; each layer is a branch that builds on the one
before. All three are complete and work on their own: pick the one you want
with `git checkout <branch>`. Each has its own ready-built
`game/build/top_tetris.bit`.

| branch | what it is | built on | on real hardware | LUTs of 8,000 |
|---|---|---|---|---|
| `main` | Versus Tetris: two boards linked by 3 wires, garbage, rival bar, win / lose / draw; single player without a link | - | played on two boards | 3,496 (44 %) |
| `chaos` | + CHAOS layer: slide-switch tasks, attacks sent over the link, bonuses | `main` | played on two boards | 6,200 (78 %) |
| **`media`** (you are here) | + media from the SPI flash: music, video attacks, win / lose clips, sprites; + hardware test 06 | `chaos` | tested on the boards | 6,797 (85 %), all 10 block RAMs |

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

0. **Media, once per board.** The game's media file is built from source
   videos, music and pictures listed in `tools\media_plan.py`. Those source
   files are **not in this repository** (other people's videos and music,
   and personal photos): put them in `media\` first. Then (close FPGA
   Builder; writing takes a few minutes):
   ```
   python tools\make_game_media.py
   tools\flash_media.bat media\game_media.bin
   ```
   It goes 1 MB into the flash, after the FPGA's own start-up area, and
   stays there until overwritten.
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
| SW4 | music and all media sound |
| SW5 | sound effects |
| SW6 | CHAOS on (tasks + attacks; switch it on on both boards) |
| SW7 | link to the PC over USB instead of the J5 cable (for `tools\fake_opponent.py`) |
| SW22 SW21 SW19 SW17 SW15 SW13 SW12 SW11 (the 8 leftmost) | the task switches |

The 7-segment display shows your cleared lines, or the seconds left while a task runs.

## What happens in the game

**Versus.** Clearing 2 / 3 / 4 lines at once sends 1 / 2 / 4 garbage lines
to the rival. They wait in a red meter next to the field; lines you clear
first cancel them, otherwise they rise from the bottom as grey rows with one
hole. The RIVAL bar on the left shows how high the other stack is. Last one
standing wins. At most 3-5 waiting garbage lines come in per piece.

**CHAOS.** Every 10-17 s (random) a task appears in the right panel: flip a
switch 10 times, copy a light pattern, set a number in binary or in hex,
don't touch any button, keep a bar in a green zone, flip a switch at the
right moment. Do it with the task switches before the time runs out (while
still playing Tetris). Success: with a rival connected, usually an
**attack** on them: MIRROR (left / right swapped), FLIP (field upside down),
BLIND (your blocks invisible), BOUNCERS (5-10 squares bouncing over the
field), +3 GARBAGE, CURSED next piece, SPEED, or LOCK (all buttons locked
until they finish a task). On this branch also the **media attacks**: Bad
Apple!!, OIIA OIIA or JEVIL play behind the rival's game, with their sound
instead of the rival's music (40-84 s; the sender can't send another one
until it is over + 10 s). Otherwise a **bonus** for you: FREEZE gravity, SINK 2 rows, or an I piece next.

**Media.** The music plays during a game (TETORIS by Hiiragi Magnetite,
Kasane Teto SV version, then the original Tetris theme, in turn). After a media attack your music continues
where it was. When you **win**: the yippee cat video, or a picture in the
right panel. When you **lose**: 10 rickrolls, a FNaF 2 jump scare (Foxy or
the Puppet) over your game, a loss picture, or a reaction picture in the
panel. During the Jevil attack Jevil floats over the whole screen; the
BOUNCERS show friends' faces. All of it comes from the board's 8 MB SPI flash
chip (6.9 MB used), as 16 kHz ADPCM sound and run-length coded 160 x 120
pictures. Without the media file in the flash the game still works, just
without these.

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
| `tb_chaos` | tasks solved -> attacks over the link -> effects on the other board, LOCK |
| `tb_chaos_core` | freeze, speed, cursed / I piece, sink |
| `tb_chaos_frame` | screenshots with a task panel and attacks |
| `tb_flash_read` | test 06 against a pretend flash chip |
| `tb_media_engine` | the game's media player: sound, delta pictures, panel, sprites |
| `tb_media_ctrl` | what plays when: music, attacks, win / lose |

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
| 06_flash_read | pictures, animation and sound from the SPI flash (first `tools\flash_media.bat media\media.bin`; note it shares the flash area with the game's media file) |

## Folder layout

```
  game\                top_tetris.vhd (the top level), pins.xdc, project.txt,
                        README.md, build\top_tetris.bit
  src\
    common\             reusable blocks: vga_sync, uart_tx / uart_rx, debounce,
                        switch_filter, seg7_scan, common_pkg
    game\               the game: tetris_core (rules), tetris_render (picture),
                        tetris_input, versus_link, tetris_sound, text_pkg, text_layer, text_multi,
                        chaos_pkg / chaos_task / chaos_fx / chaos_render (the CHAOS layer)
    media\              spi_flash, media_engine, adpcm_dec, media_ctrl, media_mix
                        (media_player: test 06's simpler player)
  tests\               small designs that each test ONE piece of the hardware
    01_vga_bars  02_j5_pin_finder  03_uart_echo  04_board_link  05_uart_probe
    06_flash_read       pictures, animation and sound from the SPI flash
                        (each: top_*.vhd, project.txt, pins.xdc, README.md, build\*.bit)
  sim\                 testbenches (+ a .prj file list each); sim\out = their output
  tools\               build.bat, program.bat, sim.bat, build_all.bat, vivado_gui.bat,
                        load_into_builder.bat (fills the TA's FPGA Builder), fake_opponent.py, remap_doc_lines.py
                        media: media_plan.py (the list), media_lab.py (renders),
                        make_game_media.py (the game's flash file), flash_media.bat,
                        make_media.py (test 06's file)
  media\               source media (not in git) + media.bin (test 06's demo file)
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
7. [Part 7](docs/learn/07_chaos_walkthrough.md): the CHAOS layer
8. [Part 8](docs/learn/08_flash_walkthrough.md): reading the SPI flash (test 06)
9. [Part 9](docs/learn/09_media_walkthrough.md): the media in the game: ADPCM sound, run-length pictures, the media engine

Plus [`tetris_visual.html`](docs/learn/tetris_visual.html), an interactive
visual guide (16 sections; GitHub only shows its source, so download it and
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
* CHAOS was played on two boards and changed twice after feedback; the
  changes are listed in `docs/learn/07_chaos_walkthrough.md`, section 7.8.
* Test 06 passed on the board (20 Oct 2026): flash ID, media file, 0 read
  errors, sound in sync with the pictures.
* The media in the game works on the boards (21 Oct 2026); fixes after the
  first try are listed in `docs/learn/09_media_walkthrough.md`, section 9.13.
* The chip is nearly full: 6,797 of 8,000 LUTs, 98 % of the slices, all 10
  block RAMs. Timing met with 3.4 ns to spare.
* Every testbench above passes.
