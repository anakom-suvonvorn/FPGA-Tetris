# HANDOFF: project state for Claude (read this first after a context reset)

Last updated: **2026-10-19** (two-board fixes on all branches; test 06 waiting). Keep this
file current whenever something important changes. Durable facts also live in
Claude's memory (`...\.claude\projects\D--All-files-Me-university-digital-system-assignment\memory\`:
`digital-system-final-project.md`, `git-workflow.md`).

---

## 0. Where we are RIGHT NOW (start here)

* Game = **"Tetris Duel, CHAOS edition"**, versus Tetris on two EDGE
  Spartan-7 boards. Agreed 4-layer plan:
  1. **versus core**: DONE (tag `v1-versus` on `main`).
  2. **chaos**: DONE on branch **`chaos`**. Round 1 was played on hardware
     by the user (single board); their feedback became **round 2**
     (commit 9faa68f + docs): panel hidden except during a task ("CHAOS MODE
     ON" text only), new task HEX (7 tasks), new attack LOCK (id 8: buttons
     locked until the victim finishes a task, chaos_task `hurry`), every time
     a random range (`rand_range` in chaos_pkg), random zone widths, 5–10
     bouncers, BLIND draws locked cells as empty, SINK immediate (S_SINK from
     S_PLAY + S_SINK_CHK), garbage 3–5 rows per lock. All sims PASS. Build
     6022 LUTs (75 %), WNS +4.2 ns. Round 2 not yet tried on hardware.
     Still to do later: the real OIIA cat (picture + sound from flash) - the
     user said "we'll come back to this later".
  3. **media**: branch **`media`** (checked out; = chaos + test 06). **Test 06
     (`tests\06_flash_read`) is built + simulated, waiting for the user's
     hardware run.** It reads the S25FL064L via STARTUPE2 (CCLK) at
     25/12.5/6.25/3.125 MHz, shows ID, the media file (`TDMF`) from flash
     address 0x100000, plays items (pictures 160x120 with palette 1/2/4/8
     bpp, animations, picture+sound, sound), VERIFY of a 256 KB LFSR block,
     load time, underruns. Files: `src\media\spi_flash.vhd`,
     `src\media\media_player.vhd` (6 BRAM tiles, ~700 LUTs), `tools\make_media.py`
     (Pillow + ffmpeg; `--demo`, `--item kind:path,...`, `--sim`),
     `tools\flash_media.bat` (openFPGALoader `-f -B spiOverJtag -o 0x100000`,
     plus `check`), `sim\tb_flash_read` + `flash_model` (PASS).
     `media\media.bin` = demo set (5 items, 1.5 MB). Docs: Part 8 +
     visual guide sections 14–15 (published).
     **The user decides what media to make from the test results.** Space is
     the limit (7 MB), not speed.
  4. extra mini-games if time is left.
* **Two-board session (2026-10-19, user + friend, real J5 cable):** versus
  works well. Fixes made on `main` and merged into `chaos` and `media`:
  1.5 s **start cool-down** after a game (tetris_core `cool`, `can_start`
  output; PRESS START only shows after it), **switch_filter** (integrator
  debounce, 1 ms samples, LIMIT 10) + PULLDOWN on all slide switches,
  **settings moved to the right**. Physical order of the 16 slide switches,
  left → right (confirmed by the user): SW22 SW21 SW19 SW17 SW15 SW13 SW12
  SW11 | SW10 SW9 SW8 | SW7 SW6 SW5 SW4 SW2. Now: task switches = the 8
  leftmost (task_sw bit 7 = SW22 J1 ... bit 0 = SW11 L2), SW8–10 free,
  SW7 N10 = USB link, SW6 P12 = chaos on, SW5 sfx, SW4 music, SW2 pause.
  Panel labels via `SW_NUM` table in chaos_render. Build: main 3496 LUTs
  (44 %), chaos 6200 LUTs (77.5 %), WNS +4.6 ns.
* **Test 06 PASSED on hardware (2026-10-20):** ID, media file, all items,
  VERIFY 0 bad (83 ms / 256 KB), no underruns, A/V in sync; only tearing at
  3.125 MHz (expected). The user collected media in `media\` (git-ignored:
  music/, effects/, lose/, win/, friends' pictures). **Media plan v1**:
  `tools\media_plan.py` (the list) → `python tools\media_lab.py [ids]`
  (FPGA-accurate renders + sizes into mediaenders\, git-ignored) →
  `python tools\media_page.py` → open `mediaenders\plan.html` (local only:
  friends' photos + others' videos; don't publish). Proposed: 16 kHz 4-bit IMA
  ADPCM sound, delta+RLE picture codec (SKIP/FILL/COPY ops, see media_lab
  rle_bytes), modes bg (hollow blocks over dimmed video) / full / over
  (green key) / panel (2x picture in the right panel), audio track + short
  video loop for attacks, Jevil + face sprites. Proposed set 6.76 MB (97 %).
  LUT risk: ~+1,500 on 6,200. Waiting for the user's decisions (list on
  the page). `utilization_by_block.txt` now written by every build.
* **Next action:** wait for the user's test 06 results (checklist in
  `tests\06_flash_read\README.md`) and their media choices; then build the
  player into the game (loss video, win picture, Tetoris song, OIIA cat
  picture + sound, SFX). LUT budget is tight: game 75 % + player ~9 %;
  candidates to save LUTs: text layers, bouncers (10 compare blocks),
  rand_range multipliers. Untested risk: openFPGALoader writing a raw .bin at
  an offset (the `check` mode tells).
* User answers 2026-10-19: switch order SW13 left .. SW6 right (as drawn).
  **Never push to GitHub** unless the user explicitly says so.
* Second board "sometime this week" (then test 04 + real two-board versus).
* **Deadline: Fri 30 Oct 2026, 16:00** (queue closes 09:00). Docs, video and
  brochure need ~3 days, so building should stop around 26–27 Oct.

## 1. The assignment (short)

* Course 01076113 Digital System Fundamentals, CE KMITL, year 2569.
  Assignment PDF: `D:\All files\Me\university\digital system\assignment\20260629_Assignment2569.pdf`.
* Hand in on the day: the piece, proposal + brochure (paper + file, no prior
  review), design document (Top-Down Design for the FPGA part, short link to
  the video), public video 1–5 min named `CE_KMITL_Digital_2569_xxxx` with all
  names + student IDs, one storage medium with everything.
* Rules: ≥ 2 FPGA boards, ≥ 1 new board; main logic in the FPGA; harder than
  the labs; graded relative to other groups.
* Shared ideas page for teammates (Thai default, EN toggle):
  https://claude.ai/artifact/CSSutE2ycH2T7azPArQmME. Teammates read Thai more
  easily than English.

## 2. Hardware + toolchain facts (all hardware-verified unless noted)

* Board: EDGE Spartan-7, XC7S15-FTGB196-1 (8,000 LUTs, 16,000 FFs, 10 BRAM
  tiles), 50 MHz clock on H11. Manual: `D:\All files\Me\university\digital system\assignment\EDGE Spartan 7 FPGA Development board User Manual.pdf`.
* VGA R0..3 B6 D3 C3 A4, G0..3 A3 B3 A2 B5, B0..3 A5 B2 B1 C5, HS C4, VS E4.
* Push buttons (pressed = '1') form a CROSS: SW14 J14 left, SW16 J13 top,
  SW18 J12 centre, SW20 J11 right, SW23 L13 bottom.
* Slide switches (16): SW2 K11, SW4 M11, SW5 N14, SW6 P12, SW7 N10, SW8 P10,
  SW9 M10, SW10 N4, SW11 L2, SW12 P3, SW13 N1, SW15 M2, SW17 L1, SW19 J3,
  SW21 K3, SW22 J1. On the board left → right: SW22 SW21 SW19 SW17 SW15 SW13
  SW12 SW11 SW10 SW9 SW8 SW7 SW6 SW5 SW4 SW2. Game uses: the 8 leftmost =
  task switches, SW7 USB link, SW6 chaos, SW5 sfx, SW4 music, SW2 pause.
  Free: SW8, SW9, SW10. They bounce badly and float when held halfway:
  always switch_filter + PULLDOWN.
* 7-seg segments a..g,dp = L3 P4 P2 M3 M1 J4 K4 J2 (active-low); digit
  enables H4 (left) H3 H2 H1 (right), **ACTIVE-HIGH** (from the user's Lab 7).
* USB serial (FT2232 ch. B, COM3 on the user's PC): **G1 = from PC (FPGA rx),
  F2 = to PC (FPGA tx)** - the manual and the TA Builder labels are swapped.
* J5 header: pins 1..4 = 5V GND 3V3 GND; pins 5..20 = L14 M13 H14 H13 F11 G11
  C14 D14 E13 F13 F14 G14 D13 D12 E12 F12. Link uses pin 5 (L14) tx, pin 6
  (M13) rx (PULLUP), GND pin 2. Crossed wires + 330 Ω.
* Buzzer B14 (jumper J6), audio jack L/R A13/B13 (driven directly by pins;
  sigma-delta - not yet heard on hardware), PS/2 C12/E11. **Flash** (from
  Vivado `get_package_pins`, not yet hardware-verified): FCS_B C11, D00/MOSI
  B11, D01/MISO B12, D02 D10, D03 C10 (drive both high), CCLK A8 = only via
  STARTUPE2.USRCCLKO. Chip S25FL064L (ID 01 60 17), 8 MB; bitstream ~0.54 MB.
* Toolchain: the user's labs use the TA's Schematic Studio + **FPGA Builder**
  (`D:\setup\FPGA_Builder_Package_V9`, bundled Vivado 2025.2 batch, read_vhdl
  = VHDL-93, programs with openFPGALoader `-c ft2232 -m` / flash `-f -B
  spiOverJtag_xc7s15ftgb196.bit`; its setup put WinUSB on the JTAG channel, so
  Vivado Hardware Manager can't program - don't change drivers).
  Full Vivado: `D:\AMDDesignTools\2025.2\Vivado\bin`. Paths: no spaces / Thai.
* Hardware tests passed (2026-10-16): 01 VGA, 02 J5 pins, 03 UART echo, 05
  UART probe. 04 board link: needs the second board. Single-player game was
  tested and "feels fine"; versus and chaos not yet on hardware.

## 3. Project: `D:\setup\assignment` (git repo)

```
README.md, docs\concepts.md, docs\HANDOFF.md (this)
docs\learn\         the course for the user (see §5)
src\common\         common_pkg, debounce, seg7_scan (active-high digits),
                    vga_sync, uart_tx, uart_rx
src\game\           tetris_pkg, text_pkg (5x7 font), chaos_pkg,
                    tetris_input, tetris_core, versus_link, chaos_task,
                    chaos_fx, text_layer, chaos_render, tetris_render,
                    tetris_sound
game\               top_tetris.vhd, project.txt, pins.xdc, README.md,
                    build\top_tetris.bit, screenshot_*.png
tests\01..06\       hardware tests (top, project.txt, pins.xdc, README, .bit)
src\media\          spi_flash, media_player (layer 3)
media\              media.bin (make_media.py --demo output)
sim\                testbenches + .prj (paths relative to sim\)
tools\              build.bat, build_all.bat, program.bat, sim.bat,
                    vivado_gui.bat (+ make_vivado_project.tcl),
                    load_into_builder.bat/.py, ppm2png.py,
                    fake_opponent.py (PC plays the rival; pyserial),
                    remap_doc_lines.py (fix docs L-numbers after code edits),
                    make_media.py, flash_media.bat (media into flash)
vivado\             throw-away GUI projects (git-ignored)
```

**Git** (remote origin = github.com/anakom-suvonvorn/FPGA-Tetris):
`main` = stable, tag `v1-versus`. Branch `chaos` = chaos layer (round 2
included). Branch `media` (current) = chaos + test 06 + Part 8 docs.
**Never pushed; never push** unless the user says so. Plan: merge `chaos` →
`main` after the user's hardware test. Each branch has its own built
`game\build\top_tetris.bit`.

### Design summary (details in docs\learn 05/06/07)

* One 50 MHz clock, enables (frame_tick 60 Hz from vga_sync). VHDL-93.
* tetris_core: one FSM; per frame S_PLAY→ROT(+kicks)→MOVE→DOWN→GHOST→LOCKCHK;
  LOCK (4 clk) → CLEAR (rd/wr) → SCORE → ATTACK → (HOLE → GARB | SINK) → PICK
  (7-bag LFSR) → SPAWN. One collision checker on cand_* regs. Field = occ
  20x10 + colf 20x30 in FFs. Wide x coordinates (board col + 3), SPAWN (6,0).
* versus_link: 1-byte msgs type(7..5)+value(4..0): 0 HEARTBEAT(height, every
  6 frames), 1 GARBAGE n, 2 LOST, 3 START, 4 ATTACK id, 5..7 free. link_ok =
  byte within 30 frames. Garbage 2/3/4 lines → 1/2/4, cancels pending first,
  3–5 rows per lock (random). Win = rival's LOST while playing; DRAW = rival's LOST
  while I lost < 6 frames ago (both boards decide the same way, no extra msg).
* Chaos: task every 10–17 s (random; first after 10 s); 7 tasks (FLIP MATCH
  BINARY HANDS HOLD TIMING HEX); success → attack (5/8, only if link_ok) or
  bonus. Attacks 0 MIRROR 1 FLIP 2 BLIND 3 BOUNCE 4 OIIA 5 GARBAGE(+3)
  6 CURSED(S/Z) 7 SPEED 8 LOCK; bonuses 0 FREEZE 1 SINK(2 rows, now,
  cancel pending) 2 I-PIECE. All durations random ranges (chaos_pkg). chaos_render = overlay (ov_on/ov_rgb) drawn last
  in tetris_render stage 2; 1-clock latency like text_layer.
* Sound: tetris_sound, Korobeiniki ROM + 13 SFX, mix music 3 + sfx 7 →
  'loudness' 0..15 → 'bucket' sigma-delta → audio pins; buzzer = sfx only.
* Builds (tools\build.bat game): chaos round 2 = 6022 LUTs (75 %), 0 BRAM,
  WNS +4.2 ns. Test 06: 1749 LUTs, 6 BRAM tiles, WNS +6.9 ns.
* Sims (all PASS on `chaos`): tb_tetris_core (robot, cell invariant),
  tb_versus (two cores + links), tb_chaos (task solver → attacks over link →
  effects), tb_chaos_core (freeze/speed/next/sink), screenshots:
  tb_tetris_frame (versus + WIN) and tb_chaos_frame (task + cat, flip +
  bouncers) - those take ~10 min, run them in the background.

## 4. Things the user wants from me (standing requests)

* **Docs for every layer**: `docs\learn\NN_*.md` line-by-line walkthrough
  (Parts 1–7 exist: VHDL basics, blocks, tests, Vivado, game, versus, chaos)
  **plus** interactive sections in the visual guide. The user strongly
  prefers real visuals over ASCII art, and step-by-step explanations from
  zero (they were confused by "wide columns" and "sigma-delta" until
  rewritten). Keep line numbers correct: after code edits run
  `python tools/remap_doc_lines.py <doc> "<sec start>" "<sec end>" <git rev> <src>`
  for each doc section that cites a changed file, then spot-check.
* **Visual guide** = `docs\learn\tetris_visual.html`, published artifact
  https://claude.ai/artifact/28Mdg6vDhCJzwXsmgR6Cdb (republish with the
  Artifact tool using the same file path; no `url` needed from this session,
  from a new session pass `url`). 13 sections: 1 coords, 2 collides, 3 state
  machine (all states incl. ATTACK/HOLE/GARB/SINK, step-through scenarios,
  every transition a drawn arrow - the user insisted), 4 S_LOCK, 5 S_CLEAR,
  6 bcd_inc, 7 LFSR/bag, 8 renderer, 9 link message, 10 garbage, 11 audio
  mixer (bucket), 12 playable chaos task panel, 13 cat spin. Edit via Python
  patch scripts written to the scratchpad (inline heredocs with long JS broke
  bash once), then `node --check` the extracted script, then publish.
  Sections 14 SPI (bit stepper) and 15 media (beam race / tearing, sound
  ring pacing, 7 MB planner) added 2026-10-19 (version 7). Local preview:
  launch.json "docs" in the session folder serves docs/learn on :8765.
* Use git as described in §3; never push.
* Explain decisions plainly; the user catches logic gaps (e.g. the DRAW
  question) - answer honestly, fix wording/code.

## 5. Working notes for Claude

* Build: from Git Bash in `D:\setup\assignment`: `cmd //c "tools\\build.bat game"`
  (prints `WNS :`), sims: `cmd //c "tools\\sim.bat tb_chaos"`. Never program
  the board yourself.
* VHDL-93: no process(all), no function calls/expressions in port maps (use
  constants/signals), don't read out ports. Reserved words bit me: `label`,
  `on` (also avoid `in`, `out`, `range`, ...). VHDL is case-insensitive:
  `MUS_NOTE` and `mus_note` clash.
* Python from bash heredocs: backslashes in Windows paths get mangled
  (`\a` → BEL, `\f`); prefer the Write tool or byte-level replace to fix.
* This harness sets `NoDefaultCurrentDirectoryInExePath=1`, which breaks
  Vivado `launch_simulation` (compile.bat not found); remove it in the
  PowerShell session when testing Vivado GUI projects. Not an issue for the
  user.
* Don't overwrite the Builder's fpga_builder.json; the user runs
  `tools\load_into_builder.bat game`.
* VHDL is case-insensitive: this bit me twice more (port `t_hands` vs
  constant `T_HANDS`, constant `RING` vs signal `ring`). Big BRAMs: Vivado
  maps a 19,200 x 8 array to 8 tiles; split into 4K-deep banks by hand (5).
* Resource watch: 75 % LUTs. Text layers (12 instances) are a likely place
  to save LUTs if media needs room.
