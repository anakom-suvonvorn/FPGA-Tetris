# Part 7: The CHAOS layer, line by line

Everything added on the `chaos` git branch: slide-switch **tasks**, **attacks**
sent to the rival over the link, **bonuses**, the visual effects (mirror,
flip, blind, bouncers, the OIIA cat), and their sounds. Read Parts 5 and 6
first; this part only explains what's new or changed.

Line numbers (`L114`) refer to the files as they are now. The visual guide
(`tetris_visual.html`) has interactive diagrams for this part in sections
12 and 13.

Contents:
[7.0 What it does](#70-what-it-does) ·
[7.1 chaos_pkg](#71-chaos_pkgvhd-the-numbers-texts-and-the-cat) ·
[7.2 chaos_task](#72-chaos_taskvhd-the-tasks) ·
[7.3 chaos_fx](#73-chaos_fxvhd-effects-on-my-board) ·
[7.4 chaos_render](#74-chaos_rendervhd-drawing-the-chaos) ·
[7.5 changes elsewhere](#75-changes-in-the-other-files) ·
[7.6 tests](#76-testing-it) ·
[7.7 try it](#77-try-it-on-the-board)

---

## 7.0 What it does

* **SW21** turns chaos on (on both boards, or it is one-sided).
* Every 10–20 s a **task** pops up in the panel on the right. The 7-segment
  display counts down the seconds left. You do the task with the **task
  switches SW6..SW13** while still playing Tetris with the buttons.
* Finish it in time and you get a reward: with a rival connected, 5 times in
  8 an **attack** on the rival, otherwise a **bonus** for yourself. With no
  rival it is always a bonus. Running out of time only shows TASK FAILED.
* A **banner** under the field says what happened: `INCOMING: MIRROR!`,
  `SENT: OIIA CAT!`, `BONUS: FREEZE TIME`, `TASK FAILED`.

| Task | What you do | Time |
|---|---|---|
| FLIP | flip the shown switch 10 times | 8 s |
| MATCH | copy a pattern of 8 lights onto SW13..SW6 | 12 s |
| BINARY | set a decimal number (1..255) in binary on SW13..SW6 | 15 s |
| HANDS | don't touch any button for 4 s (pieces keep falling!) | 10 s |
| HOLD | keep a bouncing bar in the green zone for 3 s; the switch pushes it up | 15 s |
| TIMING | flip the switch while the moving marker is in green, 3 times in a row | 12 s |

| Attack (on the rival) | Effect | Lasts |
|---|---|---|
| MIRROR | left and right swapped | 10 s |
| FLIP | the field drawn upside down | 8 s |
| BLIND | locked blocks invisible | 6 s |
| BOUNCERS | 4 squares bouncing over the field | 10 s |
| OIIA | a spinning cat bouncing over the field, with its jingle | 8 s |
| GARBAGE | +3 garbage lines | at once |
| CURSED | the next piece becomes an S or a Z | at once |
| SPEED | pieces fall as if 6 levels higher | 10 s |

| Bonus (for me) | Effect |
|---|---|
| FREEZE | no gravity for 10 s |
| SINK | the 2 bottom rows disappear, waiting garbage is cancelled |
| I PIECE | the next piece becomes an I |

```
            my board                                       rival's board
 switches ─► chaos_task ──success──► attack? ─► versus_link ═══ATTACK n═══► versus_link
                │                       │                                    │ got_attack
                │                     bonus                                  ▼
                └─fail/sent──► chaos_fx (banner,                          chaos_fx ──► effects:
                               my bonuses)                                    │  mirror → buttons
                                   │                                         │  flip, blind → tetris_render
                                   ▼                                         │  bouncers, cat → chaos_render
                            chaos_render (panel, banner)                     │  speed, cursed, garbage → tetris_core
```

New files: `chaos_pkg.vhd`, `chaos_task.vhd`, `chaos_fx.vhd`,
`chaos_render.vhd` (all in `src/game/`), `sim/tb_chaos.vhd`,
`sim/tb_chaos_core.vhd`, `sim/tb_chaos_frame.vhd`. Changed: `tetris_core`,
`versus_link`, `tetris_render`, `tetris_sound`, `top_tetris`, `pins.xdc`,
`tools/fake_opponent.py`.

Cost: logic use went from 44 % to 66 % of the chip; timing still fine (WNS
+5.8 ns).

---

## 7.1 `chaos_pkg.vhd`: the numbers, texts and the cat

Like `tetris_pkg`: no hardware of its own, just shared names.

* **L39–58:** task, attack and bonus numbers as named constants
  (`T_FLIP` = 0 ... `A_MIRROR` = 0 ... `B_FREEZE` = 0). The rest of the code
  uses the names, so the numbers only live here. The attack number is also
  the value of the ATTACK message on the cable.
* **L61–67:** how long things last, in frames, as constant arrays indexed by
  the number: `ATTACK_FRAMES(A_FLIP)` = 480 = 8 s. 0 means "instant".
* **L75–77, L91–121: banners.** A table of 20 fixed 20-character texts,
  numbered so the banner number says both *what* and *which*:
  0..7 = `INCOMING: <attack n>`, 8..15 = `SENT: <attack n−8>`,
  16..18 = `BONUS: ...`, 19 = `TASK FAILED`. So chaos_fx can pick a banner
  with simple arithmetic: `8 + sent_id`.
* **L82–84, L124–165: the cat.** 16 × 16 pixels, drawn as text like the
  font: `.` see-through, `K` black, `G` grey, `W` white, `P` pink. `crow`
  turns one text row into 48 bits (3 bits per pixel), `cat_pixel(r, c)`
  reads one pixel back. In hardware: a 16 × 48-bit ROM.

---

## 7.2 `chaos_task.vhd`: the tasks

### Ports (L29–62)

In: clock, frame tick, `enable` (chaos on and a game running), `paused`,
`versus` (a rival is connected), `sw` = the 8 task switches (already
synchronised in the top), `touch` (any button action).
Out: everything the panel draws (`active`, `task`, `sel`, `target`, `count`,
`meter_pos`, `zone_lo/hi`, `progress`, `secs`) and one-clock result pulses
(`task_start`, `task_ok`, `task_fail`, `send_attack` + `attack_id`,
`bonus` + `bonus_id`).

Generics `FIRST_DELAY` and `FORCE_TASK` let a testbench make the first task
come quickly and always be the same one.

### Two states: WAIT and RUN (L99–231)

The state is just one bit, `running`. `frames` counts down in both: in
WAIT the frames until the next task, in RUN the frames left for this task.

**`enable = '0'`** (L114): no game or chaos off: drop any task and reset the
first wait. **Paused** (L118): nothing changes.

**WAIT** (L120–152): count down once per frame. At 0, pick a task:
`t := rnd mod 8` from the task's own LFSR. If it is 6 or 7 (no such task) or
the same as last time, nothing happens and the next frame tries again (the
same retry trick as the 7-bag in S_PICK). Then set the task up:

* `sel`: which of the 8 switches (random 0..7, shown as SW6..SW13)
* `target`: a random 8-bit pattern / number, guaranteed **not** equal to
  the switches right now (otherwise MATCH would be solved before you start)
* the HOLD / TIMING values: marker in the middle, a random green zone

**RUN** (L154–231): first

```vhdl
flipped := sw(sel_r) xor sw_d(sel_r);
```

`sw_d` is `sw` one clock ago, so the XOR is '1' exactly in the clock the
task switch changed: an **edge detector**, like the button press pulse.
Then one `case` per task:

* **FLIP** (L158): count edges; the 10th is a success.
* **MATCH / BINARY** (L163): success when `sw = target`. They are the same
  check: MATCH shows the target as lights, BINARY as a decimal number. You
  convert it in your head (173 = 1010 1101).
* **HANDS** (L165): `good` counts frames; any `touch` sets it back to 0;
  240 frames (4 s) in a row is a success.
* **HOLD** (L172): a tiny physics simulation, once per frame. The switch
  on = the velocity goes up by 1, off = down by 1 (gravity), limited to ±4.
  The position moves by the velocity and stops at the ends. `good` counts
  frames spent inside the green zone (not necessarily in a row); 180 = success.
* **TIMING** (L189): the marker sweeps 3 px per frame, bouncing at the
  ends. On a switch edge: inside the zone → hit (count + 1, new zone);
  outside → count back to 0. 3 hits in a row = success.

**Success** (L208): stop, schedule the next task (10..14 s), and choose the
reward from LFSR bits:

```vhdl
if versus = '1' and to_integer(unsigned(lfsr(10 downto 8))) < 5 then   -- 5 out of 8
  atk_p  <= '1';  atk_id <= to_integer(unsigned(lfsr(13 downto 11)));  -- attack 0..7
else
  bon_p  <= '1';  ... bonus 0..2
```

**Time out**: `frames` reaches 0 → `task_fail` pulse.

### Progress bar (L235–252)

A combinational process turns each task's state into a 0..191 bar
(the panel is 192 px wide): FLIP `count × 19`, MATCH/BINARY `right
switches × 23` (`ones()` counts the 1s in `target xor sw` = the wrong
switches), HANDS `good × 3/4`, HOLD `good`, TIMING `count × 63`.

---

## 7.3 `chaos_fx.vhd`: effects on my board

**Timers** (L61–63): `t` is an array of 8 frame counters, one per attack
number, and `t_frz` for the FREEZE bonus. An effect is "on" while its
counter is above 0 (L123–129):

```vhdl
mirror <= '1' when t(A_MIRROR) > 0 else '0';
```

Once per frame every counter goes down by 1 (a `for` loop = 8 copies of a
down-counter). Getting the same attack again restarts it.

**An attack arrives** (L87–99): `got_attack` + `got_id` from versus_link.
Banner `got_id` (INCOMING), then: GARBAGE and CURSED are one-clock pulses
to the core; all others start their timer. OIIA also pulses `oiia_evt` for
the sound.

**My own results** (L101–117): `SENT` banner (8 + id); a bonus starts
FREEZE's timer or pulses `sink` / `next_i`; a failed task shows banner 19.

**Banner** (L64–65, L136): a 150-frame (2.5 s) counter + the banner number.

When chaos is off or no game runs (`enable = '0'`), everything is reset.

---

## 7.4 `chaos_render.vhd`: drawing the chaos

An **overlay**: for every pixel it outputs `ov_on` (draw something here?)
and `ov_rgb` (which colour). `tetris_render` draws it on top of its own
picture as the very last step. Same timing as `text_layer`: all from (x, y),
registered once, ready for tetris_render's stage 2.

### Moving things (L111–140)

Once per frame: the 4 **bouncers** (L66–72: positions, per-square speeds
`SPX`/`SPY`, direction bits) move and bounce off the field edges, like the
bouncing square of test 01 times four. The **cat** (L75–78) does the same,
and `spin` counts frames.

### Text (L143–186)

Two 16-character panel lines and the banner, three `text_layer`s. Each line
starts from a fixed template (`L1_TXT`, `L2_TXT`, one per task + one for
"waiting") and `put_digit` writes numbers into it: the switch number
(`sel + 6` → "SW13"), the BINARY number (hundreds/tens/ones by dividing by
100 and 10), the TIMING hit count, the seconds until the next task.

### Geometry (L189–316)

* **The panel** (L207–255): a purple frame and dark inside. Below the text:
  the MATCH target lamps; **8 switch pictures** (a slot with a knob at the
  top = on or bottom = off, SW13 on the left; the switch the task wants is
  shown in orange); the **meter** (dark, green zone, white marker) for HOLD /
  TIMING; the **progress bar**; the **time bar** (12 px per second, red in
  the last 3 seconds). The switch under a pixel is `7 − px / 24` (8 columns
  of 24 px).
* **Banner** (L257–270): a black band, text colour by banner number (red
  incoming / failed, gold sent, green bonus).
* **Bouncers** (L272–285): 4 coloured squares.
* **The cat** (L287–314): 64 × 64 px = the 16 × 16 picture at 4× (`dy / 4`,
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

### Output (L318–322)

The text pixels arrive at the same edge as the `r_*` registers, so they are
merged combinationally: text on top of the panel / band it belongs to,
otherwise the registered geometry colour.

---

## 7.5 Changes in the other files

### `tetris_core.vhd`

* **New inputs** (L71–75): `fx_freeze`, `fx_speed` (levels while '1'),
  `fx_next_bad`, `fx_next_i`, `fx_sink` (pulses).
* **Gravity** in S_PLAY (L381–397): FREEZE skips it; SPEED compares with
  `gravity_frames(speed_level(level))`, `speed_level` (L227–231) = level +
  6, at most 15.
* **Next piece** (L660–673): after the `case`, CURSED sets `next_p` to S or Z
  (picked by one LFSR bit), I PIECE to I, and `next_sh` to match, so the
  preview updates at once.
* **SINK** (L674–677): adds 2 to `sink_left` and sets `p := 0` (waiting
  garbage cancelled). The rows are removed after the next lock: S_ATTACK
  (L598) goes to the new **S_SINK** (L645–657), which is S_GARB backwards:

  ```vhdl
  for r in ROWS - 1 downto 1 loop
    occ_r(r) <= occ_r(r - 1);          -- every row takes the one ABOVE it
  end loop;
  occ_r(0) <= EMPTY_OCC;               -- empty row enters at the top
  ```

  The bottom row falls out of the field, one row per clock.

### `versus_link.vhd`

Type 4 = **ATTACK** (L67), value = attack number. `send_attack` + `attack_id`
are remembered like the others (L117–120) and sent with priority START >
LOST > **ATTACK** > GARBAGE > HEARTBEAT (L141–144). Received ones become
`got_attack` + `got_attack_id` (L176–178).

### `tetris_render.vhd`

* **FLIP** (L185, L285): the row read from the field is `19 − row`, and the
  in-cell `py` is `15 − py` (`not y(3 downto 0)`), so even the bevel flips.
  The piece and ghost use the same row, so the whole field turns over.
* **BLIND** (L313, L320–322): locked cells drawn as almost-black, without the
  bevel (the bevel edges would give the blocks away). The falling piece and
  ghost stay visible.
* **Overlay** (L400–403): `if ov_on = '1' then c := ov_rgb;` as the last
  step before the output registers.

### `tetris_sound.vhd`

Six new effects (L130–136): task pops up (double blip), task done (rising),
task failed (low buzz), attack sent (falling "zap"), attack hit (alarm),
and the OIIA jingle (low, high, high, middle: "o-i-i-a"). Started by new
event inputs (L215–220).

### `top_tetris.vhd`

* SW21 = chaos on, SW6..SW13 = `task_sw` (bit 0 = SW6 ... bit 7 = SW13); all
  in the 13-bit synchronizer.
* **MIRROR** (L187–188): `c_left <= a_right when fx_mirror = '1' else a_left;`
  and the same the other way. The swap happens *before* the core, which never
  knows.
* **Garbage** (L192–193): from the rival's GARBAGE message *or* the GARBAGE
  attack (+3), merged into one input.
* `chaos_en <= chaos_s and playing` (L234) enables task and fx.
* The 7-segment display (L298–312) shows `--ss` (seconds left) during a task.

### `tools/fake_opponent.py`

New command `x n`: send ATTACK n. Attacks from the board are printed by name.

---

## 7.6 Testing it

### `sim/tb_chaos.vhd`: tasks → attacks → effects

Board A's `chaos_task` and `chaos_fx`, two `versus_link`s wired together,
and board B's `chaos_fx`. A **solver** process plays every task the way a
person would, by changing `sw`:

* FLIP: flip the wanted switch 10 times;
* MATCH / BINARY: set `sw <= target`;
* HANDS: do nothing;
* HOLD: switch on while the bar is below the middle of the zone, off above
  it (a simple controller);
* TIMING: flip once each time the marker passes through the zone.

The **referee** checks 30 tasks: none may fail; every attack must arrive at
B with the same number and turn on the matching effect (and the INCOMING
banner); every bonus must act on A; all 6 task types must come up.
Result: 30 tasks, 14 attacks, 16 bonuses, **TEST PASSED**.

### `sim/tb_chaos_core.vhd`: the core's chaos inputs

Drops a few pieces, then: I PIECE → next is I; CURSED → next is S or Z;
FREEZE for 120 frames → the piece doesn't move; SPEED → it falls 3 rows in
48 frames (normally 1); SINK → after the next lock, exactly the cells of the
2 bottom rows are gone. **TEST PASSED**.

### `sim/tb_chaos_frame.vhd`: screenshots

The whole design with chaos on, the first task forced to BINARY, and a
pretend PC sending ATTACK 4 (cat) and later ATTACK 1 + 3 (flip + bouncers).
Screenshots in `game/screenshot_chaos_task.png` and
`game/screenshot_chaos_flip.png`.

---

## 7.7 Try it on the board

1. Load `game`. Put **SW21 up** (chaos on). Start a game with SW18.
2. After ~10 s a task appears on the right, and the 7-segment display counts
   down. Use **SW6..SW13**.
3. With one board, the PC can attack you:
   `python tools\fake_opponent.py COM3` (SW22 up), then `x 4` (cat),
   `x 0` (mirror), `x 1` (flip) ... Solved tasks send attacks to the PC,
   which prints them.
4. Two boards: both SW21 up, SW22 down, cable as before.

**Tell Claude:** which physical order the switches SW6..SW13 are in on the
board, so the panel picture (SW13 on the left) can match it.

Next layer: **media** (videos and sound clips from the board's flash).
