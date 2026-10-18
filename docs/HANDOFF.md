# HANDOFF: project state for Claude (read this first after a context reset)

Last updated: 2026-10-16 (seg7 fixed, J5 + UART pins verified, test 03 rebuilt with G1=rx F2=tx). Keep this file current whenever something important
changes. Durable facts also live in Claude's memory file
`C:\Users\Asus 444\.claude\projects\D--All-files-Me-university-digital-system-assignment\memory\digital-system-final-project.md`.

---

## 1. The assignment (short)

* Course 01076113 Digital System Fundamentals, CE KMITL, year 2569.
  Assignment PDF: `D:\All files\Me\university\digital system\assignment\20260629_Assignment2569.pdf`.
* **Deadline moved:** everything due **Fri 30 Oct 2026, 16:00**. Queue to book
  the check closes 30 Oct 09:00; a joint check may start 09:00 that day (if
  no group is ready within 5 min it ends). Proposal + brochure are no longer
  reviewed in advance but are still handed in (paper + file) with: the piece,
  design document (must use Top-Down Design for the FPGA part, with a short
  link to the video), public video 1–5 min named `CE_KMITL_Digital_2569_xxxx`
  with all names + student IDs, and one storage medium with everything.
* Rules: ≥ 2 FPGA boards, ≥ 1 new board; main logic must be in the FPGA;
  harder than the labs; graded relative to other groups.
* Group chose (probably) **versus Tetris on two EDGE Spartan-7 boards**
  ("Tetris Duel"); fallback Snake/Tron; stretch Bad Apple, music, keyboard.
* Shared ideas page for teammates (Thai default, EN toggle):
  https://claude.ai/artifact/CSSutE2ycH2T7azPArQmME
  (to edit: Artifact read it, strip the outer skeleton = line 1 and the
  injected mermaid runtime after the page's own `</script>`, patch, publish
  with `url`). Teammates read Thai more easily than English.

## 2. Hardware + toolchain facts

* Board: EDGE Spartan-7, XC7S15-FTGB196-1, 50 MHz clock on H11.
  Manual: `D:\All files\Me\university\digital system\assignment\EDGE Spartan 7 FPGA Development board User Manual.pdf`.
* Pins we use (also in each `tests\*\pins.xdc`):
  * VGA R0..3 B6 D3 C3 A4, G0..3 A3 B3 A2 B5, B0..3 A5 B2 B1 C5, HS C4, VS E4
    (**confirmed working on hardware 2026-10-16**)
  * Push buttons (pressed = '1'), a CROSS: SW14 J14 left, SW16 J13 top, SW18 J12 centre, SW20 J11 right, SW23 L13 bottom (user-confirmed 2026-10-16)
  * Slide switches SW2 K11, SW4 M11, SW5 N14, SW6 P12, SW7 N10, SW8 P10, SW9 M10, SW10 N4
  * 7-seg segments a..g,dp = L3 P4 P2 M3 M1 J4 K4 J2 (active-low),
    digit enables DIGIT4..DIGIT1 = H1 H2 H3 H4 (**ACTIVE-HIGH**, see §4);
    seg7_scan port `dig(3)`=H4 leftmost ... `dig(0)`=H1 rightmost (if the
    user reports digits mirrored, swap the H1..H4 order in the xdc files)
  * USB serial (FT2232 channel B), **HARDWARE-VERIFIED 2026-10-16 with test 05:
    G1 = data FROM the PC into the FPGA (uart_rx), F2 = FPGA TO the PC (uart_tx).**
    The manual diagram (and the Builder's labels) have them swapped.
  * Buzzer B14 (jumper J6), audio L/R A13/B13, PS/2 data C12 clock E11
  * J5 header pins 5..20 = L14 M13 H14 H13 F11 G11 C14 D14 E13 F13 F14 G14 D13
    D12 E12 F12 (from the official XDC inside the TA builder source; order
    derived from the manual's camera table; **HARDWARE-VERIFIED 2026-10-16 with test 02**).
    J5 pins 1..4 = 5V, GND, 3V3, GND.
* The user's normal workflow (all labs in `D:\setup`): draw schematics in the
  TA's "Schematic Studio" (`D:\setup\schematic&bus2vhdl.html`) which exports
  VHDL, then the TA's **FPGA Builder** (`D:\setup\FPGA_Builder_Package_V9\FPGA_Builder.exe`,
  Python source in `source\fpga_builder.py`) builds and programs. Builder
  facts: takes a list of .vhd files + a pin table, stores ONE config in
  `FPGA_Builder_Package_V9\fpga_builder.json`, runs a bundled Vivado 2025.2
  batch (read_vhdl = VHDL-93, no timing report, demotes
  CLOCK_DEDICATED_ROUTE on all BUFGs), programs with openFPGALoader
  (`-c ft2232 -m` SRAM, `-f -B spiOverJtag_xc7s15ftgb196.bit` flash).
  Its setup put WinUSB on FT2232 interface 0 (JTAG).
* Full Vivado is installed at `D:\AMDDesignTools\2025.2\Vivado\bin`
  (vivado.bat, xvhdl/xelab/xsim). The user has NEVER used the Vivado GUI or
  written VHDL by hand (only drawn schematics, which they're good at).
* Paths used by Vivado must have no spaces / Thai.

## 3. Project folder: `D:\setup\assignment`

```
README.md            quick start + rules
docs\concepts.md     long explanations (VGA, UART, J5, clocks, WNS, VHDL-93 rules)
docs\HANDOFF.md      this file
src\common\          common_pkg (CLK_HZ, CLKS_PER_BIT=434, hex7 glyphs gfedcba
                     active-high, SEG_J/P/DASH), debounce (2FF sync + 20 ms +
                     press pulse), seg7_scan (4-digit scan, 18-bit counter,
                     blank gap), vga_sync (640x480@60, pix_en, frame_tick),
                     uart_tx, uart_rx (8N1, 115200)
tests\01_vga_bars    4 pictures by SW4/SW2: bars, ramps, Tetris grid, square
tests\02_j5_pin_finder  one-hot on J5 pins, display "J5.nn", PB1/PB3/PB5
tests\03_uart_echo   echo uppercase to PuTTY, PB3 sends a message, 7-seg count|byte
tests\05_uart_probe  debug for 03: listens on F2+G1, transmits on the other pin
tests\04_board_link  sends 8 switches every 50 ms on J5 pin5 (L14), receives on
                     pin6 (M13), shows own|other or "--" after 250 ms
   each: top_*.vhd, project.txt (top= + file list in compile order),
         pins.xdc, README.md, build\*.bit
sim\                 tb_uart_loop (PASSES), tb_vga_frame (timing PASS + writes
                     frame.png; generic PATTERN 0..3), *.prj (paths relative
                     to sim\, library work)
tools\               build.bat <test> (full Vivado, runs in build dir, prints
                     WNS, timing.txt/utilization.txt), build_all.bat,
                     program.bat <test> [flash], sim.bat <tb> [pattern],
                     load_into_builder.bat/.py (writes Builder json, backs up
                     old as fpga_builder.backup.json), ppm2png.py
```

All four tests built OK on 2026-10-15 (WNS +14..+15.5 ns, <3% LUTs).
Harmless warning in 03/04: uart_rx FSM has no reset.

## 4. Hardware test results (reported by the user 2026-10-16)

| Test | Result | Diagnosis / next action |
|---|---|---|
| 01 VGA | **Works perfectly** | nothing |
| 02 J5 finder | **PASS after fix (2026-10-16): display readable, all 16 J5 pins match the table** | Was: 7-seg unreadable. **FIXED 2026-10-16:** seg7_scan rewritten, port `dig_n` renamed `dig`, active-high, 02/03/04/05 rebuilt. Original diagnosis: the **digit-enable polarity**. The user's proven Lab 7 (`D:\setup\lab7_handfixed_async.vhd`, entity `display`, ~line 1016) drives `digit`/`common` **one-hot ACTIVE-HIGH** (`y0 <= '1' when sel=00`), mapped common(0)=H1 ... common(3)=H4. Our `seg7_scan.vhd` drives dig_n active-LOW, so 3 digits are on at once showing each other's glyphs = everything lit. **Fix:** make digit enables active-high in seg7_scan (rename dig_n -> dig, '1' = on, blank gap = "0000"), rebuild 02/03/04. Lab 7 segments are active-low (dp = not y2), consistent with ours. User asked to base the display on their proven lab design (clean, hand-written, same logic). |
| 03 UART echo | **Root cause found 2026-10-16: TX/RX swapped vs manual (test 05: PC talks on G1). pins.xdc fixed (uart_rx=G1, uart_tx=F2), rebuilt; awaiting user retest.** Original symptom: PuTTY "can't even start typing", VS Code serial monitor: no response after sending, PB3 message: nothing in either | **2026-10-16 update:** user confirmed COM3 = "USB Serial Port" (FTDI channel B fine; channel A shows as "Digilent USB Device" = WinUSB from the Builder setup, so Vivado Hardware Manager likely can't program). PuTTY blank window is normal (no local echo). Manual diagram (page 6) says F2 <- USB TXD, G1 -> USB RXD (= our mapping). Built **test 05_uart_probe**: both pins inout, listen-only until a byte arrives on one, then transmits on the other; display = bytes on F2 . bytes on G1, left dot = TX on G1, right dot = TX on F2; status line every 3 s; PULLUP on both pins. Sim passes both wirings. **Waiting for the user's result** (which counter rises). If neither: PC side/driver/baud. Earlier notes: | To ask/check: (a) does Device Manager show "USB Serial Port (COMx)" under Ports, and is that the port used? (the Builder's Zadig/WinUSB step may have taken the whole FT2232 or interface 1); (b) exact PuTTY behaviour/error; (c) once the 7-seg is fixed, does the byte counter count when typing (tells PC->FPGA vs FPGA->PC); (d) possibly F2/G1 swapped: try swapping uart_rx/uart_tx pins as an experiment; (e) build a minimal test that just transmits 'U' repeatedly + blinks LED on any rx edge. |
| 04 board link | Not tried (second board not available yet; blocked by 7-seg) | after 02/03 fixes |

## 5. What the user asked for next (in order)

**GIT (from 2026-10-18):** repo D:\setupssignment, remote origin =
github.com/anakom-suvonvorn/FPGA-Tetris. Branch `main` = stable (tag
`v1-versus` = versus core). Branch `chaos` = layer 2 (commits 4122307,
304be72; not pushed - ask the user before pushing). Merge chaos -> main after
the user tests it on hardware. Commit as you go on a feature branch.
tools/remap_doc_lines.py <doc> "<sec start>" "<sec end>" <git rev> <src> fixes
L-number references in docs/learn after code changes (run it for every
changed file / doc section before committing).

**CHAOS LAYER DONE 2026-10-18 (layer 2, branch `chaos`)** in code + sim, NOT
yet on hardware. SW21 (K3) chaos on; task switches SW6..SW13 = sw_task(0..7)
(P12 N10 P10 M10 N4 L2 P3 N1; panel shows SW13 left - physical order not yet
confirmed by the user). New: chaos_pkg (ids, durations, 20 banners, 16x16
cat ROM), chaos_task (WAIT/RUN, 6 tasks FLIP MATCH BINARY HANDS HOLD TIMING,
success -> attack 5/8 if versus else bonus), chaos_fx (8 attack timers,
freeze, banner 150 frames), chaos_render (overlay: panel x428..627 y284..467,
banner y444..467, 4 bouncers, 64px cat with 4-phase fake spin). Link type 4
ATTACK. Core: fx_freeze/fx_speed/fx_next_bad/fx_next_i/fx_sink, S_SINK.
Render: flip, blind, overlay last. Sound: 6 chaos SFX. 7-seg = task
countdown. Build 66% LUTs, WNS +5.8. Sims PASS: tb_chaos, tb_chaos_core,
tb_tetris_core, tb_versus; screenshots game/screenshot_chaos_*.png.
Docs: docs/learn/07_chaos_walkthrough.md, visual guide sections 12-13 + S_SINK.
Next: layer 3 media (flash read test first), layer 4 mini-games.

**VERSUS CORE DONE 2026-10-17 (layer 1 of 4)** - in code + sim, NOT yet on
hardware. Agreed plan with the user ("Tetris CHAOS edition"): layer 1 versus
core (done), layer 2 chaos (attack/reward system, slide-switch mini-tasks,
effects: scramble controls, flip screen, cover-ups/OIIA cat, re-roll next),
layer 3 media from SPI flash (test 06 flash read via STARTUPE2 first; python
converter; loss videos e.g. Bad Apple/rickroll, Tetoris audio, custom SFX),
layer 4 extra mini-games. Win rule: last one standing (+ DRAW within 1 s).
New files: src/game/versus_link.vhd (1-byte msgs: type(7..5) 0 HEARTBEAT
value=height, 1 GARBAGE n, 2 LOST, 3 START, 4-7 free for chaos; heartbeat
every 6 frames, link_ok timeout 30 frames), text_pkg.vhd (5x7 font,
font_glyph_t, codes 0-9 digits, 10-35 A-Z, 36 space), text_layer.vhd
(generics X0,Y0,LEN,SHIFT; 1-clk latency), tetris_sound.vhd (Korobeiniki
40-step ROM, 7 SFX, sigma-delta mix music 3 + sfx 7 of 16). Core: new ports
versus/start_in/garb_in(_n)/opp_lost -> start_out/lost_out/garb_out(_n)/
height/pending/result(0 none 1 WIN 2 LOSE 3 DRAW 4 GAME OVER); states
S_ATTACK (2/3/4 lines -> 1/2/4, cancels pending first), S_HOLE, S_GARB
(shift up, grey row, max 8 per lock). Render: 9 text layers, garbage meter
x226, rival bar x104, result banner. Top: SW4 music, SW5 sfx, SW22 J1 =
link over USB (PC); link_tx L14/link_rx M13 (PULLUP), usb F2/G1 (PULLUP),
audio A13/B13, buzzer B14. Build: 44% LUTs, WNS +7.8. Sims PASS:
tb_tetris_core, tb_versus (two cores+links, robots, referee). Tool:
tools/fake_opponent.py COM3 (pyserial). Docs: docs/learn/06_versus_walkthrough.md
+ visual page sections 9-11. 2026-10-18: DRAW window cut to lose_age < 6
(each board turns its own LOSE into DRAW when the rival's LOST arrives
while already lost; no extra message); mixer renamed level4->loudness,
acc->bucket; visual page: FSM has S_ATTACK/S_HOLE/S_GARB + new scenarios,
section 11 rebuilt (bucket explainer); docs 05/06 line numbers refreshed.
7-seg kept (tiny) - plan: use it for chaos mini-task countdown. Second board arrives "sometime this week";
speakers TBD.

**GAME STARTED 2026-10-16** (all hardware tests 01-03 + 05 pass; 04 still
needs the second board). Single-player Tetris written: `game\` (top_tetris,
project.txt, pins.xdc, README) + `src\game\` (tetris_pkg: types, SRS shapes
via pic("...") table, colours, gravity table; tetris_input: 5 debouncers +
DAS 10/ARR 3 frames; tetris_core: one FSM per frame S_PLAY→ROT→MOVE→DOWN→
GHOST→LOCKCHK, LOCK (4 clk), CLEAR (rd/wr compaction), SCORE, PICK (7-bag
from LFSR), SPAWN; single collision checker on cand_* regs; occ (20x10) +
colf (20x30) fields; tetris_render: 2-stage pipeline). Buttons PB1 left,
SW16(top) rotate, SW18(centre) hard drop/start, SW23(bottom, L13) soft drop, SW20(right, J11) right; SW2 pause. User tested on hardware 2026-10-16: works and feels fine.
Build: 28% LUTs, WNS +8.8 ns. Sims: tb_tetris_core (robot, checks cell
count invariant) PASSED; tb_tetris_frame (screenshot). Waiting for the
user's hardware test. Next: versus over J5 (core already outputs
clear_evt/clear_n for garbage; garbage colour 7 exists), sound, on-screen
score/text, title screen.

**Status 2026-10-16:** item 1 DONE: `docs\learn\` (README + 01_vhdl_basics,
02_blocks_walkthrough, 03_tests_walkthrough, 04_vivado). New tool
`tools\vivado_gui.bat <design> [tb]` (makes `vivado\<design>\*.xpr` via
`tools\make_vivado_project.tcl`, linked sources, sim runtime -all; verified the
project sim passes). `program.bat` now also accepts a .bit path.
`load_into_builder.py` now passes extra XDC properties (e.g. PULLUP) to the
Builder's "extra" column. Item 2 fixed in code, awaiting the user's retest.
Item 3: test 05 built, awaiting the user's result.
NOTE for Claude: in this harness `NoDefaultCurrentDirectoryInExePath=1` is set,
which breaks Vivado `launch_simulation` (compile.bat not found); remove it in
the shell first when testing. Not an issue on the user's own desktop.

1. **Teach VHDL and Vivado from zero**, in depth: the user knows digital logic
   and schematics well but has never read VHDL or used Vivado. Wants a
   line-by-line walkthrough of every file I wrote (common_pkg, debounce,
   seg7_scan, vga_sync, uart_tx, uart_rx, the 4 tops, testbenches), how
   multiple files reference each other (package/use, entity work.x
   instantiation, port maps, generics), how to design in VHDL, and how to use
   the Vivado GUI (project, add sources, elaborated schematic, simulation
   waveforms, synthesis/implementation, timing report, hardware manager).
   Probably best as a document (e.g. `docs\learn_vhdl.md` + `docs\learn_vivado.md`)
   plus chat summary; relate VHDL to schematic thinking (signals = wires,
   process(clk) = flip-flops, combinational = gates/mux).
2. Fix the 7-seg (see §4), rebuild, have the user retest 02.
3. Debug the UART (see §4).
4. Test 04 when the second board is available.
5. Then start the game: playfield registers + renderer (test 01 grid picture
   is the start), piece ROM, game FSM, input with auto-repeat, link protocol,
   sound, 7-seg score. Plan details were given in chat on 2026-10-15
   (single 50 MHz clock + enables, playfield 20x10x3 bits in flip-flops,
   16 px cells at field x 240..399 y 80..399, UART 115200 one-byte messages
   3-bit type + 5-bit payload, garbage 0/1/2/4 for 1/2/3/4 lines, Korobeiniki
   music). Timeline: 15–17 Oct hello-hardware, 18–22 single-player, 23–25
   versus, 26–28 polish/docs/video, 29 buffer, 30 demo.

## 6. Working notes for Claude

* Verify VHDL with `tools\sim.bat` and `tools\build.bat` (cmd: `cmd //c "tools\\build.bat 02_j5_pin_finder"` from Git Bash in `D:\setup\assignment`). Never program the board yourself.
* Keep VHDL-93 compatible: no process(all), no expressions in port maps,
  don't read out ports.
* Don't overwrite the Builder's fpga_builder.json yourself; the user runs
  load_into_builder.
* When writing paths in Python heredocs from bash, beware backslash escapes
  (`\a`, `\b`, `\f` got mangled before); use raw strings or the Write tool.
