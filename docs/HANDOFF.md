# HANDOFF: project state for Claude (read this first after a context reset)

Last updated: **2026-10-28**: all 3 layers done and working on hardware;
explainer page `docs/learn/media_visual.html` extended (ADPCM in depth,
video load timing, reference side panel). Context compacted right after
this at the user's request; they said they have "multiple things" - more
requests are coming, wait for them. Keep this file current whenever
something important changes. Durable facts also live in Claude's memory
(`...\.claude\projects\D--All-files-Me-university-digital-system-assignment\memory\`:
`digital-system-final-project.md`, `git-workflow.md`).

---

## 0. Where we are RIGHT NOW (start here)

### Latest (2026-10-28 evening): submission package in `submission/`
* User asked to plan + prepare every hand-in item (Thai with English terms;
  docs go into Google Docs, brochure into Canva). Rules re-read from the
  assignment PDF + the new announcement: proposal and brochure no longer
  pre-checked but still handed in (paper + file); everything due Fri 30 Oct
  16:00, queue sign-up closes 09:00, joint check may start 09:00 (5-minute
  rule); all items except the piece on ONE storage medium, folders per item
  2.1, 2.2, 2.3, 2.5.
* `submission/README.md` = the plan (checklist, timeline, USB folder layout,
  what to bring, cautions: Public video, YouTube copyright, friends' faces).
  `2.1_Proposal/proposal.md`, `2.3_Design_Document/design_document.md`
  (Top-Down: levels 0-3, every module, tests, problems), `2.5_Video/video_script.md`
  (shot list + timed Thai narration + credits + YouTube description),
  `demo_and_qa.md` (demo order + 21 likely questions with answers),
  `2.2_Brochure/brochure.html` (tri-fold: A4 landscape, outside P2|P6|P1 at
  97/100/100 mm, inside P3|P4|P5; Chrome --print-to-pdf to `Brochure_example.pdf`,
  PNGs `Brochure_outside/inside.png` rendered from that PDF with pypdfium2) and `brochure_text.md` (for Canva).
  `figures/figures.py` draws 13 Thai diagrams (SVG -> PNG via headless
  Chrome); `build_docs.py` converts the .md to .docx (python-docx, Sarabun).
  Placeholders `[...]` = names, student IDs, group name, video link/QR,
  real photos: the user fills them. Sarabun is not installed on this PC, so
  Word previews look off; Google Docs has the font.

### Latest (2026-10-28): media_visual.html round 2 (commit 2f82e9a)
* User asked (a) ADPCM in far more detail (what is a step, idx, why those
  numbers, /8 /4 /2, pred, code), (b) whether a 10 fps video loads on a
  varying frame, (c) the reference (code reader / names) usable beside the
  text, (d) compact prep. Done, all in the page:
  - ADPCM section rewritten ("ADPCM, slowly"): names table, 1 the idea,
    2 a ruler of 8 slots (interactive: idx + real-sample sliders; slot =
    bits 2..0 as quarter steps, + step/8 = middle of the slot; encoder's 3
    yes/no questions), table of the 8 codes, 3 why the step adapts (fast
    up +2/4/6/8, slow down -1), 4 the 89 IMA steps (geometric ~1.1x, chart
    with idx-1/+2/+4/+6/+8 marks), 5 a "microscope" (4 sounds, window of
    25 samples with reach bands +-1 7/8 step, zoomed ruler of the current
    sample, every encoder / decoder number, slider to change a sample),
    6 the old whole-sound widget + 3 hardware clocks.
  - Video timing (in "video + sound"): a 10 fps record = 0.1 s = 5.952
    screen frames (screen = 59.52 Hz, 840,000 clocks); loads come after 6
    frames, about 1 in 21 after 5, never 4 or 7; 15 fps: 4, sometimes 3.
    Picture leads its sound by 16-33 ms, a sawtooth, no drift. Widget
    simulates 30 s (284x6 + 16x5 for 10 fps).
  - Reference panel: "reference" button (fixed bottom right) / Esc; moves
    #refReader #refNames #refPatterns #refWords into <aside id=refPane>
    (tabs, widths S/M/L, remembered in localStorage), sticky right column
    >= 900 px, overlay drawer below. Every <code>name</code> in the text
    that GL knows gets a dotted underline: click = open it in the reader
    (window.REF.lookup / window.refPick). Glossary rows clickable. E_ and
    M_ states added to GL.
  - Fix after the user's screenshot (2000 px screen: big empty middle, side
    index gone): docked layout = [index (only >= 1400 px)] | text (980,
    centred) | draggable divider #refDiv | panel. Width presets fit (text
    keeps 980, panel gets the rest, >= 420) / half and half / wide; drag
    (pointer, arrow keys, double-click = fit) is remembered. Below 900 px
    the panel is a drawer with the divider on its left edge. Checked at
    2000, 1280 and 375 px.
  - Published again to the same private artifact (version 2).

### Before that (2026-10-25)
* The user read Part 8 and was lost ("how is it stored / flashed / retrieved,
  what is BRAM, frame buffer, sound ring, what do the states do, the short
  variable names..."). Answer: **`docs/learn/media_visual.html`** ("Tetris
  Duel Media Internals"), branch `media`: 18 sections from zero, in the
  order things happen (memory, block RAM + inference + tile shapes + banks,
  flash + erase rules, the real media file byte by byte, the Python steps,
  flash_media.bat / spiOverJtag, spi_flash clock by clock (a JS port of the
  VHDL), all 7 state machines with walks + code, frame buffer pixel path,
  one frame clock by clock (JS port of E_RH..E_SND + decoder + hold against
  the beam), sound ring, ADPCM, A/V sync + rec_pos-2 resume, media_ctrl game
  simulator, media_mix layers, VERIFY LFSR, a code reader where clicking a
  name shows its meaning and every write / read line, glossaries).
  Its embedded VHDL sources and real file numbers come from
  **`tools/update_media_visual.py`**: run it again after changing src/media
  or rebuilding a media file. Uses only made-up pictures (no media content):
  safe to publish. Also published as a private artifact (link in the chat).
* Found while doing it: adpcm_dec's STEPS table is a RAMB18 (read in the
  clocked process), so the game uses **20 of 20** BRAM halves, not 19;
  fixed in Part 9 (9.5, 9.6).

### Before that (2026-10-21 .. 24)
* Media in the game **works on hardware** (user: "everything seems to be
  correct") after the round in docs 9.13 (flash_media.bat fix, Foxy crop,
  Kaka panel pictures back, ROM cat removed).
* **Branches stay SEPARATE** (user's decision): `main` = versus, `chaos` =
  + chaos layer, `media` = + media. NO more merging chaos -> main. Each
  branch's root `README.md` was rewritten (same "three branches" table at
  the top, then that branch's own controls / rules / files / testbenches /
  docs / status) and its `docs/learn/README.md` fixed (private artifact link
  removed: GitHub readers can't open it; "download tetris_visual.html").
  Commits: main 546033f, chaos 64df0f1, media 01eab78. The generator for
  the 3 READMEs was a scratchpad script (gone after the session); if they
  need changing, edit each branch's README.md directly.
* The user pushes to GitHub themselves (`git push origin main chaos media`).
* Checked out: `media`, working tree clean.

### Status of the 4 layers
* Game = **"Tetris Duel, CHAOS edition"**, versus Tetris on two EDGE boards.
  1. **versus core**: `main` (tag `v1-versus` + later fixes). Played on two
     real boards with a friend on 2026-10-19: works.
  2. **chaos**: branch `chaos` (round 2 of feedback done, see docs Part 7 §7.8;
     still has the ROM OIIA cat - only `media` removed it).
  3. **media**: branch **`media`** (checked out) = chaos + test 06 + media
     plan tools. **Test 06 PASSED on hardware 2026-10-20** (ID 016017, media
     file found, VERIFY 0 bad in 83 ms, no sound underruns, A/V sync; tearing
     only at 3.125 MHz). Media plan approved (v3), **built into the game and
     working on the boards** (see "Media in the game" below).
  4. extra mini-games: probably no time.
* Fixes on ALL branches (made on `main`, merged main -> chaos -> media):
  1.5 s start cool-down after a game (tetris_core `cool`, output `can_start`),
  `src/common/switch_filter.vhd` (integrator debounce) + PULLDOWN on every
  slide switch, settings on the right. Slide switches left -> right on the
  board: SW22 SW21 SW19 SW17 SW15 SW13 SW12 SW11 | SW10 SW9 SW8 | SW7 SW6 SW5
  SW4 SW2. Game: 8 leftmost = task switches (task_sw bit7 = SW22 J1 ... bit0
  = SW11 L2), SW7 N10 = USB link, SW6 P12 = chaos on, SW5 sfx, SW4 music,
  SW2 pause. SW8-10 free.
* Builds: main 3,496 LUTs (44 %); chaos 6,200 LUTs (77.5 %), WNS +4.6 ns,
  0 BRAM; **media 6,797 LUTs (85 %), slices 98 %, BRAM 10/10, WNS +3.4 ns**
  (nearly full: new features need cuts first). Test 06: 1,749 LUTs, 6 BRAM. Builds now also write
  `build\utilization_by_block.txt` (per-block numbers are muddled by Vivado's
  flattening; tetris_core ~3,000 is the real big one).
* **Never push to GitHub.** Commit on the branch as you go.
* **Deadline Fri 30 Oct 2026 16:00**; stop building ~26-27 Oct (docs, video,
  brochure need ~3 days).

### The media plan (approved, v3)
Files: `tools/media_plan.py` (THE list, every item + settings),
`tools/media_lab.py` (FPGA-accurate renders + sizes -> `media/renders/`,
`python tools/media_lab.py [ids]`), `tools/media_page.py` (writes
`media/renders/plan.html`; local only, never publish: friends' photos and
other people's videos). `media/*` is git-ignored except `media/media.bin`
(test 06 demo). Sources: `media/music`, `media/effects`, `media/lose`,
`media/win` + friend pictures in `media/` (not used).

Approved set = 6.88 MB of 7.34 MB (94 %):
| item | how | notes |
|---|---|---|
| music_teto_sv (0-141.2 s) + music_original (83.6 s) | sound only, playlist, 2 s / 1.5 s fade | user OK'd; eurobeat + metal are in the plan unticked |
| atk_badapple 0-84 s | bg mode, 1 bpp, 10 fps, dim 1/2 | media attack |
| atk_oiia_psy 0-43.75 s | bg mode, 4 bpp, 10 fps, REAL video (no loop), fade 0.2 | ends on the fart tail; first drum at 43.90 s |
| atk_jevil | bg mode, jevil_background.mp4 loop (0-3.4 s), 2 bpp 10 fps; audio THE WORLD REVOLVING 20.2-60.5 s, fade 0.5 | + Jevil sprite |
| spr_jevil | 8 gif frames, 48x50, 4 bpp (7 colours, alpha), drawn 2x; new pose every 4th screen frame (15/s); floats on a Lissajous over the WHOLE screen: x = 320-w/2 + 230 sin(2pi t/6.1), y = 240-h/2 + 150 sin(2pi t/3.7 + 0.6) | user tuned 30 -> 8 -> 20 -> 16 -> 15 |
| spr_faces | the 4 webp faces in media/effects, 32x32, 8 bpp, shared palette, on the bouncers (picked at random) | bouncers become 32 px |
| lose: rickroll (all 34 s, full, 4 bpp 10 fps), foxy + puppet jump scares (over mode, green key + de-fringe, 8 bpp 15 fps; puppet = FNaF 2 video 1.0-2.0 s), loss0/1/2 images (full, 4 bpp) | random pick on lose | |
| win: yippee video (full, 8 bpp 10 fps), diabeetus / miku / teto (panel, 8 bpp) | random pick on win | |

Decided by the user: blocks stay SOLID in bg mode (hollow rejected); win/lose
mixed (full-screen ones + panel pictures); no other friend pictures.
**New rule: media-attack cool-down on the SENDER**: when I send a media attack
(Bad Apple / OIIA / Jevil) I count down its length + a gap (e.g. 10 s); until
then my chaos_task only sends normal attacks. Media attacks keep their full
length (40-84 s); their sound replaces the rival's music meanwhile.

### Formats decided in media_lab.py (the hardware must match)
* Sound: **4-bit IMA ADPCM at 16 kHz** (8 KB/s), standard step table (89) and
  index table, predictor/index start at 0 per item; decode -> 16-bit ->
  sigma-delta (wider than the current 8-bit bucket). `adpcm_roundtrip`.
* Pictures: 160x120, per-item palette (2^bpp x 12-bit), **delta + run-length**
  per frame (`rle_bytes`): byte `00nnnnnn` SKIP n+1 unchanged pixels,
  `01nnnnnn` FILL n+1 pixels with the next byte's colour, `1nnnnnnn` COPY n+1
  literal pixels packed bpp bits MSB first. First frame of an item / loop =
  no SKIPs (keyframe). Frame buffer keeps the previous frame, so SKIP is free.
  Records will need a length header (variable size). Encoder exists only as a
  size estimator -> must become a real encoder in make_media.py.
* Display modes: `bg` (video behind the game: screen background + empty field
  incl. grid show the video at `dim` 3/4 or 1/2; blocks/ghost/text solid),
  `full` (covers everything, result band y 192-240 on top), `over` (palette
  index 0 = see-through, drawn on top of the game), `panel` (96x88 picture at
  2x in the right panel, x 430.., y 286.., 4 px frame gold/red).
* Attack items = a long sound track + optional short video loop (two streams
  read in turns) - only Jevil uses the loop now; OIIA/Bad Apple are full A/V.

### Media in the game (branch `media`): built 2026-10-20, works on hardware
All 4 steps done in one go (music, win/lose, media attacks + sender cool-down,
Jevil + faces). Bad Apple changed by the user to 0-84.2 s, fade 0.4 s.
* `tools/make_game_media.py` -> `media/game_media.bin` (6.83 MB, git-ignored),
  format "TDM2" (byte list at the top of the script): header with groups
  (music/attack/lose/win first+count, sprite block address), 16-byte
  directory entries, records = 8-byte header (picture address+length, ADPCM
  pred+idx) + aud sound bytes; pictures stored once (delta+RLE, keyframe
  first; Jevil loop = records point at 34 deltas); sprite block = 256-colour
  palette (Jevil 1..15, faces 16..255) + Jevil 8 poses 48x50 4bpp + 4 faces
  32x32 8bpp. It decodes everything back to check. `--sim` -> sim/game_sim.hex.
  Flash it: `tools\flash_media.bat media\game_media.bin` (both boards).
* `src/media/`: `adpcm_dec` (IMA, 3 clocks), `media_engine` (replaces
  media_player in the game; RLE decoder with spi_flash `hold`; panel mode
  96x88 at 2x; sprite RAMs; 19 of 20 BRAM halves; `ram_style block`
  attributes are REQUIRED), `media_ctrl` (C_IDLE/C_MUSIC/C_ATTACK/C_END,
  music resume at rec_pos-2), `media_mix` (stage A/B after tetris_render:
  game 2 clocks + 1, media 3 clocks; Jevil Lissajous with quarter sine
  table + 1 DSP).
* Game changes: chaos_pkg N_ATTACKS 12 (A_APPLE 9, A_OIIA_V 10, A_JEVIL 11,
  MEDIA_COOL, banners 0..27), chaos_task `mcool` + `media_ok`, chaos_fx
  `media_hit/media_id`, chaos_render bouncers 32 px + face_en/face_addr +
  bouncers moved one per clock (`bk`), tetris_render `see_bg`/`keep` outputs,
  tetris_sound ROM music removed + 12-bit sigma-delta with pcm, top_tetris
  STARTUPE2 (generic USE_STARTUP, testbenches false: its sim model never
  stops) + flash pins in pins.xdc. SW4 = all media sound.
* LUTs: first full build did NOT place (7,566 = 95 %). Fixed by
  `text_multi.vhd` (all text lines of a renderer share ONE font ROM;
  replaces text_layer in the game; text_layer still used by tests) and
  the bouncer sequencer: final build 6,972 LUTs (87 %), slices 99.6 %, BRAM 10/10, WNS +3.7 ns.
* Tests: tb_media_engine PASS, tb_media_ctrl PASS, tb_chaos PASS,
  tb_flash_read PASS; frame testbenches compared pixel-exact with the
  pre-refactor screenshots. Synth-only per-block report: scratchpad tcl with
  `-flatten_hierarchy none` (the normal report lumps text logic into vga_sync).
* Docs: Part 9 `docs/learn/09_media_walkthrough.md` (written with
  {{file:text}} markers resolved by a scratchpad script; if any marker is
  left, resolve it), visual guide section 16 (ADPCM, RLE, Jevil path,
  pipeline table). Parts 5-8 line refs remapped; 6.5 notes the sound file
  changed (refs = chaos branch version).
* 2026-10-21 after the first board test (docs 9.13): flash_media.bat fixed
  (unescaped ')' in an if block made it quit silently); Foxy jump scare
  `crop=(160,0,960,720)` (4:3 screen inside the 16:9 video) so it fills the
  screen; Kaka scream / disappointed back as lose PANEL pictures (the user
  meant "keep everything shown, add nothing more"); ROM OIIA cat attack
  REMOVED (attacks renumbered: GARBAGE 4, CURSED 5, SPEED 6, LOCK 7,
  APPLE 8, OIIA 9, JEVIL 10; N_ATTACKS 11; banners 0..25), melody-only notes
  removed. Build now 6,797 LUTs (85 %), slices 98 %, WNS +3.4 ns; media file
  6.86 MB. User wants unused things removed generally.
* Hardware: done, works. Branches stay separate (no merge).

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
  (M13) rx (PULLUP), GND pin 2. Crossed plain wires, no resistors (user, 2026-10-29).
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
**Never pushed; never push** unless the user says so. (Old plan, now
CANCELLED by the user: merge `chaos` →
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
  (Parts 1–9 exist on `media`: VHDL basics, blocks, tests, Vivado, game,
  versus, chaos, flash (test 06), media in the game; 9.13 = round after the
  first board test)
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
  Now version 10, **16 sections**: 16 = media in the game (ADPCM stepper,
  RLE coder, Jevil Lissajous path, pipeline table); 13 (cat) has a
  "history: removed" note. Branches main/chaos have older copies (11/13).
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
* Resource watch (media): 85 % LUTs, 98 % slices, 100 % BRAM. Already done
  to make room: text_multi (one font ROM per renderer), bouncers moved one
  per clock, ROM cat removed. Next candidates: banner ROM, tetris_core.
  Per-block truth needs `synth_design -flatten_hierarchy none` (normal
  reports lump logic into vga_sync).
* Testbenches with top_tetris must set `USE_STARTUP => false` (STARTUPE2's
  sim model never stops, -runall would run forever).
* Batch files: never put ( ) in an echo inside an if ( ... ) block (escape
  as ^( ^)); it silently ends the block.
* Doc line refs for new docs: write {{file:text}} markers and resolve them
  with a small script at the end (did this for Part 9).
