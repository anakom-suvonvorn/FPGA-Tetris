# Part 7: The CHAOS layer, line by line

Everything added on the `chaos` git branch: slide-switch **tasks**, **attacks**
sent to the rival over the link, **bonuses**, the visual effects (mirror,
flip, blind, bouncers, the OIIA cat), and their sounds. Read Parts 5 and 6
first; this part only explains what's new or changed.

Line numbers (`L114`) refer to the files as they are now. The visual guide
(`tetris_visual.html`) has interactive diagrams for this part in sections
12 and 13.

> **Round 2 (after the first test on the board):** the panel now only
> appears when a task starts; a new **HEX** task; a new **LOCK** attack;
> every length of time is a random range; random green-zone widths; 5–10
> bouncers; BLIND really hides the blocks; SINK works immediately; at most
> 3–5 garbage rows come in per lock. All of it is described below where it
> belongs; the [list of what changed and why](#78-round-2-what-changed-and-why)
> is at the end.

Contents:
[7.0 What it does](#70-what-it-does) ·
[7.1 chaos_pkg](#71-chaos_pkgvhd-the-numbers-texts-and-the-cat) ·
[7.2 chaos_task](#72-chaos_taskvhd-the-tasks) ·
[7.3 chaos_fx](#73-chaos_fxvhd-effects-on-my-board) ·
[7.4 chaos_render](#74-chaos_rendervhd-drawing-the-chaos) ·
[7.5 changes elsewhere](#75-changes-in-the-other-files) ·
[7.6 tests](#76-testing-it) ·
[7.7 try it](#77-try-it-on-the-board) ·
[7.8 round 2](#78-round-2-what-changed-and-why)

---

## 7.0 What it does

* **SW21** turns chaos on (on both boards, or it is one-sided). The right
  side of the screen then just says **CHAOS MODE ON**, nothing else: no
  countdown, so you never know when the next task comes.
* Every 10–17 s (random) a **task** pops up in a panel on the right, with a
  sound. The 7-segment display counts down the seconds left. You do the
  task with the **task switches SW6..SW13** while still playing Tetris with
  the buttons.
* Finish it in time and you get a reward: with a rival connected, 5 times in
  8 an **attack** on the rival, otherwise a **bonus** for yourself. With no
  rival it is always a bonus. Running out of time only shows TASK FAILED.
* A **banner** under the field says what happened: `INCOMING: MIRROR!`,
  `SENT: OIIA CAT!`, `BONUS: FREEZE TIME`, `TASK FAILED`.
* Every length of time is picked at random from a range each time, so no two
  are the same.

| Task | What you do | Time allowed |
|---|---|---|
| FLIP | flip the shown switch 10 times | 7–9 s |
| MATCH | copy a pattern of 8 lights onto SW13..SW6 | 10–13 s |
| BINARY | set a decimal number (1..255) in binary on SW13..SW6 | 13–17 s |
| HEX | set a 2-digit hex number (like `A4` = 1010 0100) on SW13..SW6 | 11–14 s |
| HANDS | don't touch any button for 3–5 s (shown on the panel; pieces keep falling!) | 9–12 s |
| HOLD | keep a bouncing bar in the green zone (40–60 px wide) for 3–4 s; the switch pushes it up | 13–16 s |
| TIMING | flip the switch while the moving marker (2–4 px per frame) is in the green zone (28–44 px, new place and width after each hit), 3 times in a row | 10–13 s |

| Attack (on the rival) | Effect | Lasts |
|---|---|---|
| MIRROR | left and right swapped | 8–12 s |
| FLIP | the field drawn upside down | 6–10 s |
| BLIND | locked blocks invisible (empty field + grid) | 5–8 s |
| BOUNCERS | 5–10 squares bouncing over the field | 8–12 s |
| OIIA | a spinning cat bouncing over the field, with its jingle | 6–10 s |
| GARBAGE | +3 garbage lines | at once |
| CURSED | the next piece becomes an S or a Z | at once |
| SPEED | pieces fall as if 6 levels higher | 8–12 s |
| LOCK | **all buttons locked** until the victim finishes a task. A task starts for them at once; if it fails, the next one starts at once too | until done |

| Bonus (for me) | Effect |
|---|---|
| FREEZE | no gravity for 3–5 s |
| SINK | right away: the 2 bottom rows disappear, waiting garbage is cancelled |
| I PIECE | the next piece becomes an I |

```
            my board                                       rival's board
 switches ─► chaos_task ──success──► attack? ─► versus_link ═══ATTACK n═══► versus_link
                │                       │                                    │ got_attack
                │                     bonus                                  ▼
                └─fail/sent──► chaos_fx (banner,                          chaos_fx ──► effects:
                               my bonuses)                                    │  mirror, lock → buttons
                                   │                                         │  lock → hurry → its chaos_task
                                   ▼                                         │  flip, blind → tetris_render
                            chaos_render (panel, banner)                     │  bouncers, cat → chaos_render
                                                                             │  speed, cursed, garbage → tetris_core
```

New files: `chaos_pkg.vhd`, `chaos_task.vhd`, `chaos_fx.vhd`,
`chaos_render.vhd` (all in `src/game/`), `sim/tb_chaos.vhd`,
`sim/tb_chaos_core.vhd`, `sim/tb_chaos_frame.vhd`. Changed: `tetris_core`,
`versus_link`, `tetris_render`, `tetris_sound`, `top_tetris`, `pins.xdc`,
`tools/fake_opponent.py`.

Cost: logic use went from 44 % (versus only) to 75 % of the chip
(66 % before round 2: the 10 bouncers and the random-range multiplications
cost about 760 LUTs); timing still fine (WNS +4.2 ns).

---

## 7.1 `chaos_pkg.vhd`: the numbers, texts and the cat

Like `tetris_pkg`: no hardware of its own, just shared names.

* **L48–70:** task, attack and bonus numbers as named constants
  (`T_FLIP` = 0 ... `T_HEX` = 6, `A_MIRROR` = 0 ... `A_LOCK` = 8,
  `B_FREEZE` = 0 ...). The rest of the code uses the names, so the numbers
  only live here. The attack number is also the value of the ATTACK message
  on the cable (5 bits, so up to 31 would fit).
* **L75, L143–146: `rand_range(lo, hi, r)`** turns a random byte `r`
  (0..255) into a number from `lo` to `hi`:

  ```vhdl
  return lo + (r * (hi - lo + 1)) / 256;
  ```

  `r / 256` is a fraction from 0 to almost 1; times the size of the range,
  plus the low end. Example: `rand_range(5, 10, 200)` = 5 + 200·6/256 =
  5 + 4 = 9. Dividing by 256 is free in hardware (drop 8 bits); the
  multiplication costs some LUTs.
* **L77–90: the ranges**, in frames (60 = 1 s), as pairs of constant arrays
  indexed by the number: `ATTACK_LO(A_FLIP)` = 360, `ATTACK_HI(A_FLIP)` = 600
  = 6..10 s. 0 means "instant". `TASK_LO/HI` = time allowed per task,
  `GAP_LO/HI` = 600..1020 = 10..17 s between tasks, `FREEZE_LO/HI` = 3..5 s.
* **L92–103, L117–154: banners.** A table of 22 fixed 20-character texts,
  numbered so the banner number says both *what* and *which*:
  0..8 = `INCOMING: <attack n>` (8 = `LOCKED! DO THE TASK`),
  9..17 = `SENT: <attack n − 9>`, 18..20 = `BONUS: ...`, 21 = `TASK FAILED`.
  The named starts `BAN_SENT` = 9, `BAN_BONUS` = 18, `BAN_FAIL` = 21 let
  chaos_fx pick a banner with simple arithmetic: `BAN_SENT + sent_id`.
* **L108–110, L157–198: the cat.** 16 × 16 pixels, drawn as text like the
  font: `.` see-through, `K` black, `G` grey, `W` white, `P` pink. `crow`
  turns one text row into 48 bits (3 bits per pixel), `cat_pixel(r, c)`
  reads one pixel back. In hardware: a 16 × 48-bit ROM.

---

## 7.2 `chaos_task.vhd`: the tasks

### Ports (L36–71)

In: clock, frame tick, `enable` (chaos on and a game running), `paused`,
`versus` (a rival is connected), `hurry` (I am under the LOCK attack),
`sw` = the 8 task switches (already synchronised in the top), `touch` (any
button action).
Out: everything the panel draws (`active`, `task`, `sel`, `target`, `count`,
`meter_pos`, `zone_lo/hi`, `progress`, `secs`, `hands_secs`) and one-clock
result pulses (`task_start`, `task_ok`, `task_fail`, `send_attack` +
`attack_id`, `bonus` + `bonus_id`).

Generics `FIRST_DELAY` and `FORCE_TASK` let a testbench make the first task
come quickly and always be the same one.

### Random lengths for HANDS and HOLD (L100–107)

How long you must keep your hands off (HANDS) or keep the bar green (HOLD)
is one of 4 values, picked by 2 random bits `g`: `HANDS_GOAL` =
180/240/240/300 frames (3, 4, 4, 5 s), `HOLD_GOAL` = 180..240 (3..4 s).
Next to each goal is a **scale** = 256 × 180 / goal, used by the progress bar
so it is full exactly when the goal is reached (see below). A table of 4
instead of `rand_range` because the scale would otherwise need a division.

### Two states: WAIT and RUN (L119–272)

The state is just one bit, `running`. `frames` counts down in both: in
WAIT the frames until the next task, in RUN the frames left for this task.
Each clock two random bytes are taken from the task's own LFSR: `rnd` (bits
7..0) and `rnd2` (bits 15..8).

**`enable = '0'`** (L138): no game or chaos off: drop any task and reset the
first wait. **Paused** (L142): nothing changes.

**WAIT** (L145–190): if `hurry` is on (LOCK attack, L146), the wait is cut
to 0 at once. Otherwise count down once per frame. At 0, pick a task:
`t := rnd mod 8` from the LFSR. If it is 7 (no such task) or the same as
last time, nothing happens and the next frame tries again (the same retry
trick as the 7-bag in S_PICK). Then set the task up:

* `frames`: the time allowed, `rand_range(TASK_LO(t), TASK_HI(t), rnd2)`
* `sel`: which of the 8 switches (random 0..7, shown as SW6..SW13)
* `target`: a random 8-bit pattern / number, guaranteed **not** equal to
  the switches right now (otherwise MATCH would be solved before you start)
* `step`: TIMING's marker speed, 2..4 px per frame
* `goal` / `pscale`: HANDS or HOLD goal and its progress scale
* the green zone: TIMING 28..44 px wide, HOLD 40..60 px, at a random place
  that still fits in the 192 px meter (`zlo` ≤ 191 − width)

**RUN** (L192–270): first

```vhdl
flipped := sw(sel_r) xor sw_d(sel_r);
```

`sw_d` is `sw` one clock ago, so the XOR is '1' exactly in the clock the
task switch changed: an **edge detector**, like the button press pulse.
Then one `case` per task:

* **FLIP** (L196): count edges; the 10th is a success.
* **MATCH / BINARY / HEX** (L201): success when `sw = target`. They are the
  same check: MATCH shows the target as lights, BINARY as a decimal number,
  HEX as two hex digits. You convert it in your head (173 = 1010 1101,
  `AD` = 1010 1101), or just watch the progress bar go up and down as you
  flip switches.
* **HANDS** (L203): `good` counts frames; any `touch` sets it back to 0;
  `goal` frames in a row is a success.
* **HOLD** (L210): a tiny physics simulation, once per frame. The switch
  on = the velocity goes up by 1, off = down by 1 (gravity), limited to ±4.
  The position moves by the velocity and stops at the ends. `good` counts
  frames spent inside the green zone (not necessarily in a row); `goal`
  frames = success.
* **TIMING** (L227): the marker sweeps `step` px per frame, bouncing at the
  ends. On a switch edge: inside the zone → hit (count + 1, and a new zone:
  new width **and** new place); outside → count back to 0. 3 hits in a row
  = success.

**Success** (L248): stop, schedule the next task (`rand_range(GAP_LO,
GAP_HI)` = 10..17 s), and choose the reward from LFSR bits:

```vhdl
if versus = '1' and to_integer(unsigned(lfsr(10 downto 8))) < 5 then   -- 5 out of 8
  atk_p  <= '1';  atk_id <= rand_range(0, N_ATTACKS - 1, rnd2);        -- attack 0..8
else
  bon_p  <= '1';  ... bonus 0..2
```

**Time out** (L261): `frames` reaches 0 → `task_fail` pulse, and a new
random wait.

### Progress bar (L274–292)

A combinational process turns each task's state into a 0..191 bar
(the panel is 192 px wide): FLIP `count × 19`, MATCH/BINARY/HEX `right
switches × 23` (`ones()` counts the 1s in `target xor sw` = the wrong
switches), TIMING `count × 63`. HANDS and HOLD use

```vhdl
q := (good * pscale) / 256;
```

With `pscale` = 256 × 180 / goal this is `good × 180 / goal`: 180 (full)
when `good` reaches the goal, whatever the goal was. Multiplying and then
dropping 8 bits replaces a real division, which would be expensive.

---

## 7.3 `chaos_fx.vhd`: effects on my board

**Timers** (L68–70): `t` is an array of 8 frame counters, one per timed
attack number, and `t_frz` for the FREEZE bonus. An effect is "on" while
its counter is above 0 (L151–158):

```vhdl
mirror <= '1' when t(A_MIRROR) > 0 else '0';
```

Once per frame every counter goes down by 1 (L93–100; a `for` loop = 8
copies of a down-counter). Getting the same attack again restarts it.

**LOCK** (L71, L102–109): not a timer but a flag, `lock_r`. While it is on,
the banner is kept at `LOCKED! DO THE TASK` (number 8) whenever no other
banner is showing, and the flag goes off with the next `task_ok`. The top
level uses `locked` to block the buttons and feeds it to chaos_task as
`hurry`.

**An attack arrives** (L111–127): `got_attack` + `got_id` from versus_link.
Banner `got_id` (INCOMING), then: GARBAGE and CURSED are one-clock pulses
to the core, LOCK sets `lock_r`; all others start their timer with a random
length, `rand_range(ATTACK_LO(id), ATTACK_HI(id), rnd)`. BOUNCE also picks
how many squares (5..10, `n_bounce`); OIIA pulses `oiia_evt` for the sound.

**My own results** (L129–146): `SENT` banner (`BAN_SENT + id`); a bonus
starts FREEZE's timer (3..5 s) or pulses `sink` / `next_i`; a failed task
shows `BAN_FAIL`.

**Banner** (L73–74, L166–167): a 150-frame (2.5 s) counter + the banner
number.

When chaos is off or no game runs (`enable = '0'`, L87), everything is
reset, including the lock.

---

## 7.4 `chaos_render.vhd`: drawing the chaos

An **overlay**: for every pixel it outputs `ov_on` (draw something here?)
and `ov_rgb` (which colour). `tetris_render` draws it on top of its own
picture as the very last step. Same timing as `text_layer`: all from (x, y),
registered once, ready for tetris_render's stage 2.

### Moving things (L123–153)

Once per frame: the 10 **bouncers** (L70–83: positions, per-square speeds
`SPX`/`SPY`, colours `BCOL`, direction bits) move and bounce off the field
edges, like the bouncing square of test 01 times ten. All 10 always move;
only the first `n_bounce` are drawn. The **cat** (L85–89) does the same,
and `spin` counts frames.

### Text (L155–203)

Two 16-character panel lines and the banner, three `text_layer`s. Each line
starts from a fixed template (`L1_TXT`, `L2_TXT`, one per task + one for
"no task") and `put_digit` writes numbers into it: the switch number
(`sel + 6` → "SW13"), the BINARY number (hundreds/tens/ones by dividing by
100 and 10), the HEX digits (L182: a hex digit 0..15 *is* its character
code, `0`..`9` then `A`..`F`, so no conversion at all), the HANDS seconds
(L186), the TIMING hit count. With no task (L162) line 1 is
`CHAOS MODE ON` and line 2 is empty.

### Geometry (L205–336)

* **The panel** (L224–281): with no task (L226) only the first text line's
  area is marked (no box, nothing else), so just the words show. During a
  task: a purple frame, **red while my buttons are LOCKED** (L235), and dark
  inside. Below the text: the MATCH target lamps; **8 switch pictures** (a
  slot with a knob at the top = on or bottom = off, SW13 on the left; the
  switch the task wants is shown in orange); the **meter** (dark, green
  zone, white marker) for HOLD / TIMING; the **progress bar**; the **time
  bar** (L272: 11 px per second, red in the last 3 seconds). The switch
  under a pixel is `7 − px / 24` (8 columns of 24 px).
* **Banner** (L283–296): a black band, text colour by banner number (red
  incoming / failed, gold sent, green bonus).
* **Bouncers** (L298–306): `if i < n_bounce and (inside square i)`, colour
  `BCOL(i)`.
* **The cat** (L308–331): 64 × 64 px = the 16 × 16 picture at 4× (`dy / 4`,
  `dx / 4`: free shifts). The **spin** is faked with 4 pictures, chosen by
  `spin(4 downto 3)` (each lasts 8 frames):

  | picture | how |
  |---|---|
  | 0 | normal, full width |
  | 1 | squeezed to half width: only the middle 32 px, `sx = (dx − 16) / 2` |
  | 2 | mirrored: `sx = 15 − dx / 4` |
  | 3 | mirrored and squeezed |

  Normal → thin → mirrored → thin → normal looks like a card turning around
  its vertical axis. Pixel value 0 is see-through: `ov_on` stays '0' there,
  so the field shows between the cat's ears.

### Output (L338–344)

The text pixels arrive at the same edge as the `r_*` registers, so they are
merged combinationally: text on top of the panel / band it belongs to
(`CHAOS MODE ON` in purple, task text white / light blue), otherwise the
registered geometry colour.

---

## 7.5 Changes in the other files

### `tetris_core.vhd`

* **New inputs** (L73–78): `fx_freeze`, `fx_speed` (levels while '1'),
  `fx_next_bad`, `fx_next_i`, `fx_sink` (pulses).
* **Gravity** in S_PLAY (L387–400): FREEZE skips it; SPEED compares with
  `gravity_frames(speed_level(level))`, `speed_level` (L231–234) = level +
  6, at most 15.
* **Next piece** (L685–698): after the `case`, CURSED sets `next_p` to S or Z
  (picked by one LFSR bit), I PIECE to I, and `next_sh` to match, so the
  preview updates at once.
* **SINK** (L699–702): adds 2 to `sink_left` and sets `p := 0` (waiting
  garbage cancelled). The rows go **at once**: S_PLAY checks `sink_left`
  first (L376) and jumps to **S_SINK** (L656–673), which is S_GARB
  backwards:

  ```vhdl
  for r in ROWS - 1 downto 1 loop
    occ_r(r) <= occ_r(r - 1);          -- every row takes the one ABOVE it
  end loop;
  occ_r(0) <= EMPTY_OCC;               -- empty row enters at the top
  ```

  The bottom row falls out of the field, one row per clock. The falling
  piece stays where it is on the screen. **S_SINK_CHK** (L675–682) then
  checks it still fits: normally yes, because the stack moved *away* from
  it. But if a block was hanging right above the piece (the piece had slid
  under an overhang), that block has now moved down into it; then the piece
  is lifted one row at a time until it fits. Then S_GHOST works out the new
  ghost and play goes on.
* **Garbage per lock** (L604–610): at most 3, 4 or 5 rows (random, from 2
  LFSR bits) come in after one lock; the rest stays in the red meter for the
  next locks.

### `versus_link.vhd`

Type 4 = **ATTACK** (L67), value = attack number. `send_attack` + `attack_id`
are remembered like the others (L117–120) and sent with priority START >
LOST > **ATTACK** > GARBAGE > HEARTBEAT (L141–144). Received ones become
`got_attack` + `got_attack_id` (L176–178).

### `tetris_render.vhd`

* **FLIP** (L184, L284): the row read from the field is `19 − row`, and the
  in-cell `py` is `15 − py` (`not y(3 downto 0)`), so even the bevel flips.
  The piece and ghost use the same row, so the whole field turns over.
* **BLIND** (L311): `elsif s1_occ_bit = '1' and fx_blind = '0'`: with BLIND
  on, a locked cell skips the "draw a block" branch completely and is drawn
  exactly like an empty cell (field background + grid lines), so there is
  nothing at all to see. The falling piece and its ghost stay visible.
* **Overlay** (L398–400): `if ov_on = '1' then c := ov_rgb;` as the last
  step before the output registers.

### `tetris_sound.vhd`

Six new effects (L130–136): task pops up (double blip), task done (rising),
task failed (low buzz), attack sent (falling "zap"), attack hit (alarm),
and the OIIA jingle (low, high, high, middle: "o-i-i-a"). Started by new
event inputs (L215–220).

### `top_tetris.vhd`

* SW21 = chaos on, SW6..SW13 = `task_sw` (bit 0 = SW6 ... bit 7 = SW13); all
  in the 13-bit synchronizer.
* **MIRROR** (L192–193): `c_left <= a_right when fx_mirror = '1' else a_left;`
  and the same the other way. The swap happens *before* the core, which never
  knows.
* **LOCK** (L195–199): every button action is ANDed with `not fx_locked`
  (`g_left <= c_left and not fx_locked;` ...), so while locked the core
  gets no actions at all. `touch` (L201) is taken *before* the lock, so the
  HANDS task still notices presses.
* **Garbage** (L204–205): from the rival's GARBAGE message *or* the GARBAGE
  attack (+3), merged into one input.
* `chaos_en <= chaos_s and playing` (L246) enables task and fx;
  `hurry => fx_locked` (L252) connects the lock to chaos_task.
* The 7-segment display (L311–325) shows `--ss` (seconds left) during a task.

### `tools/fake_opponent.py`

Command `x n`: send ATTACK n (0..8; `x 8` = LOCK). Attacks from the board are
printed by name.

---

## 7.6 Testing it

### `sim/tb_chaos.vhd`: tasks → attacks → effects

Board A's `chaos_task` and `chaos_fx`, two `versus_link`s wired together,
and board B's `chaos_fx` plus its own `chaos_task`. A **solver** process
plays every task on A the way a person would, by changing `sw`:

* FLIP: flip the wanted switch 10 times;
* MATCH / BINARY / HEX: set `sw <= target`;
* HANDS: do nothing;
* HOLD: switch on while the bar is below the middle of the zone, off above
  it (a simple controller);
* TIMING: flip once each time the marker passes through the zone.

The **referee** checks 30 tasks: none may fail; every attack must arrive at
B with the same number and turn on the matching effect (and the INCOMING
banner); every bonus must act on A; all 7 task types should come up.
For **LOCK** it also checks that B is locked, that B's `chaos_task` starts a
task at once (`hurry`), and that B is unlocked when B's little solver (B's
tasks are forced to MATCH) finishes it. Result: 30 tasks, 18 attacks
(including 2 LOCKs), 12 bonuses, **TEST PASSED**.

### `sim/tb_chaos_core.vhd`: the core's chaos inputs

Drops a few pieces, then: I PIECE → next is I; CURSED → next is S or Z;
FREEZE for 120 frames → the piece doesn't move; SPEED → it falls 3 rows in
48 frames (normally 1); SINK → 20 clocks later (no lock needed), exactly
the cells of the 2 bottom rows are gone. **TEST PASSED**.

### `sim/tb_chaos_frame.vhd`: screenshots

The whole design with chaos on, the first task forced to BINARY, and a
pretend PC sending ATTACK 4 (cat) and later ATTACK 1 + 3 (flip + bouncers).
Screenshots in `game/screenshot_chaos_task.png` and
`game/screenshot_chaos_flip.png` (from round 1: 4 bouncers, panel always
visible).

---

## 7.7 Try it on the board

1. Load `game`. Put **SW21 up** (chaos on): `CHAOS MODE ON` appears on the
   right. Start a game with SW18.
2. After 10–17 s a task appears on the right, and the 7-segment display
   counts down. Use **SW6..SW13** (SW13 is the leftmost, like on the panel).
3. With one board, the PC can attack you:
   `python tools\fake_opponent.py COM3` (SW22 up), then `x 4` (cat),
   `x 0` (mirror), `x 1` (flip), `x 8` (lock) ... Solved tasks send attacks
   to the PC, which prints them.
4. Two boards: both SW21 up, SW22 down, cable as before.

Next layer: **media** (videos and sound clips from the board's flash), see
[Part 8](08_flash_walkthrough.md) and test 06.

---

## 7.8 Round 2: what changed and why

From playing round 1 on the board:

| Feedback | Change | Where |
|---|---|---|
| The panel and the "next task in" timer spoil the surprise | panel only during a task, otherwise just `CHAOS MODE ON`; no countdown | chaos_render L162, L226 |
| BINARY is fine (watch the progress bar), but add a hex version | new task HEX: two hex digits | chaos_pkg, chaos_task L201, chaos_render L182 |
| Green zones always the same width | HOLD 40..60 px per task; TIMING 28..44 px, new width after each hit | chaos_task L182–188, L240 |
| Everything with a time should be a random range | tasks, gaps, attacks, freeze, HANDS / HOLD goals, TIMING speed | chaos_pkg L77–90, `rand_range` |
| You could ignore tasks and just play Tetris | new attack LOCK: buttons locked until you finish a task | chaos_fx, chaos_task `hurry`, top_tetris L195 |
| SINK only happened at the next lock | SINK right away, from S_PLAY | tetris_core L376, S_SINK_CHK |
| FREEZE too long (10 s) | 3..5 s | chaos_pkg FREEZE_LO/HI |
| Too few bouncers | 5..10 | chaos_fx, chaos_render |
| BLIND still showed grey blocks | locked blocks not drawn at all | tetris_render L311 |
| 8 garbage rows at once is too much | at most 3..5 per lock | tetris_core L604 |
| The OIIA cat isn't the real one | later, with the media layer (real picture + sound from flash) | |
