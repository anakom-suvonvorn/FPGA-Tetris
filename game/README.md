# The game: Tetris Duel, CHAOS edition

Versus Tetris on two EDGE boards linked by a cable. With no second board it
plays single player.

**Files:** `top_tetris.vhd` (this folder) + `src\game\` (`tetris_pkg`,
`text_pkg`, `tetris_input`, `tetris_core`, `versus_link`, `text_layer`,
`tetris_render`, `tetris_sound`) + `src\common\` (`vga_sync`, `debounce`,
`seg7_scan`, `uart_tx`, `uart_rx`, `common_pkg`). Ready-built:
`build\top_tetris.bit`.

Load it like the tests: `tools\load_into_builder.bat` → type `game`, or
`tools\program.bat game`. Build: `tools\build.bat game`.
**Both boards get the same .bit file.**

## Controls

The 5 push buttons form a cross:

```
              SW16
              rotate
   SW14       SW18          SW20
   left       hard drop     right
              (start)
              SW23
              soft drop
```

| Button | Action |
|---|---|
| SW14 (left) | move left (hold = keeps moving) |
| SW16 (top) | rotate clockwise |
| SW18 (centre) | hard drop; **also starts a round (on both boards in versus)** |
| SW20 (right) | move right (hold = keeps moving) |
| SW23 (bottom) | soft drop (hold) |

| Slide switch | Up (on) means |
|---|---|
| SW2 | pause |
| SW4 | music (Tetris theme) |
| SW5 | sound effects |
| SW22 | link to the PC over USB instead of the J5 cable |
| SW21 | **CHAOS** on (tasks + attacks) |
| SW6..SW13 | the task switches (SW13 = left in the panel picture) |

## The screen

```
   RIVAL            ┌──────────┐      NEXT
   ┌──┐           ▌ │          │      ┌────┐
   │  │  garbage  ▌ │  your    │      └────┘
   │▓▓│  meter →  ▌ │  field   │      LEVEL ■■■
   │▓▓│           ▌ │          │      LINES
   └──┘             └──────────┘      0012
  LINKED
```

* **RIVAL** bar = how high the other player's stack is (turns red near the top).
* **LINKED** (green) / **NO LINK** (red): is the other board talking to us?
* **Red meter** left of the field = garbage lines waiting to come in.
* Field frame: green = press SW18 to start, grey = playing, gold = you won,
  red = you lost. The result (**WIN!**, **LOSE**, **DRAW**, or **GAME OVER**
  in single player) appears over the field.

## Versus rules

* Clearing **2 / 3 / 4** lines at once sends **1 / 2 / 4** garbage lines.
* Garbage first waits in your red meter. If your next piece clears lines,
  they **cancel** waiting garbage first. If it clears nothing, up to 8
  waiting lines rise from the bottom as grey rows with one hole.
* Garbage pushing your blocks out of the top, or no room for a new piece:
  you lose, the other board wins (it stops at once). Both topping out at
  practically the same instant, before either LOST message arrives: DRAW.
* SW18 after a round starts the next one on both boards.

## CHAOS (SW21 up)

The right side only says **CHAOS MODE ON**. At a random moment (every
10–17 s) a task pops up in a purple panel there, with a sound; the
7-segment display counts down its seconds. Do it with **SW6..SW13** (SW13 =
leftmost) while you keep playing. Every time is random within a range.

| Task | Do this |
|---|---|
| FLIP | flip the shown switch 10 times |
| MATCH | copy the 8 lights onto the switches |
| BINARY | set the number in binary (SW13 = 128 ... SW6 = 1) |
| HEX | set the 2 hex digits in binary (`A4` = 1010 0100) |
| HANDS | don't touch any button for 3–5 s (the panel says how long) |
| HOLD | keep the bar in the green for 3–4 s: the switch pushes it up, it falls by itself |
| TIMING | flip the switch while the marker is in the green, 3 times in a row |

Done in time → with a rival connected, usually an **attack** on the rival:
MIRROR (left/right swapped), FLIP (field upside down), BLIND (locked blocks
invisible), 5–10 BOUNCERS, the spinning **OIIA cat**, +3 GARBAGE, CURSED
next piece (S or Z), SPEED, or **LOCK** (all the rival's buttons locked until
they finish a task, which starts for them at once; the panel frame turns
red). Otherwise a **bonus**: FREEZE gravity (3–5 s), SINK 2 rows right away
(+ cancel waiting garbage), or an I PIECE next. The banner under the field
says what happened. At most 3–5 garbage rows come in per piece.

## Wiring two boards

Same as test 04 (test that first):

```
   Board A                                    Board B
   J5 pin 5  (TX) ---[330 Ω]--------------->  J5 pin 6  (RX)
   J5 pin 6  (RX) <---------------[330 Ω]---  J5 pin 5  (TX)
   J5 pin 2  (GND) -------------------------  J5 pin 2  (GND)
```

SW22 down (off) on both boards. Within half a second both show **LINKED**.

## Testing versus with ONE board (the PC plays the other board)

1. Load the game, put **SW22 up** (link over USB).
2. Close PuTTY and the VS Code serial monitor (only one program can use COM3).
3. Run: `python tools\fake_opponent.py COM3`. The board shows **LINKED**,
   and the RIVAL bar follows the PC's height.
4. Type commands in the terminal:
   * `s` start a round, or press SW18 on the board (the PC prints START);
   * `g 3` send 3 garbage lines (watch the red meter, then grey rows);
   * `h 15` set the PC's stack height (RIVAL bar turns red);
   * `l` the PC loses → the board shows **WIN!**;
   * `a` auto mode: the PC's stack grows and it sends random garbage;
   * `x 4` attack the board with the OIIA cat (`x 0`..`x 8`: all 9 attacks,
     `x 8` = LOCK; needs SW21 up on the board);
   * clear 2+ lines on the board → the PC prints "board sends n garbage".

## Sound

Audio jack (headphones or powered speakers): music + effects, mixed. The
buzzer (jumper J6 on Enable) plays effects only. SW4 / SW5 switch them.

## Checked in simulation

* `tools\sim.bat tb_tetris_core`: single player, a robot plays a full game;
  checks no cells are lost or duplicated. PASSED.
* `tools\sim.bat tb_versus`: **two boards** (core + link each, cross-wired)
  played by two robots; checks START sync, garbage sent = received, grey
  rows appear, one WIN + one LOSE. PASSED.
* `tools\sim.bat tb_tetris_frame`: the whole design with a pretend PC;
  saves screenshots `sim\out\frame.png` (game) and `frame2.png` (WIN!).
* `tools\sim.bat tb_chaos`: a robot solves the tasks; attacks go over the link
  and switch on the effects of the other board. PASSED.
* `tools\sim.bat tb_chaos_core`: freeze, speed, cursed / I next, sink. PASSED.
* `tools\sim.bat tb_chaos_frame`: screenshots with a task panel, the cat,
  flip + bouncers (`screenshot_chaos_task.png`, `screenshot_chaos_flip.png`).

## How it's built (top-down)

```
top_tetris
 ├─ vga_sync        640x480 timing + frame_tick (60/s)          src\common
 ├─ tetris_input    5 buttons → action pulses                    src\game
 ├─ tetris_core     rules + state, garbage, win/lose             src\game
 ├─ versus_link     1-byte messages over uart_tx / uart_rx       src\game
 ├─ chaos_task      slide-switch tasks                           src\game
 ├─ chaos_fx        attacks / bonuses on me, banner              src\game
 ├─ chaos_render    task panel, banner, bouncers, cat (overlay)  src\game
 ├─ tetris_render   (x, y) + state → colour, 9 x text_layer      src\game
 ├─ tetris_sound    music + effects → audio jack / buzzer        src\game
 └─ seg7_scan       lines on the 7-segment display               src\common
```

Explained line by line in `docs\learn\05_game_walkthrough.md` (single
player), `docs\learn\06_versus_walkthrough.md` (versus) and
`docs\learn\07_chaos_walkthrough.md` (chaos).
