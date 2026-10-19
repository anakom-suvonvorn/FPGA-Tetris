# Part 6: Versus mode, line by line (layer 1: the versus core)

Everything added to turn single-player Tetris into **Tetris Duel**: two
boards talking over a cable, garbage lines, win / lose, on-screen text, and
music + sound effects. Read Part 5 first. This part only explains what's
new or changed.

Line numbers (`L94`) refer to the files as they are now. The visual guide
(`tetris_visual.html`) has interactive diagrams for the link message,
garbage and sigma-delta sections.

Contents:
[6.0 What changed](#60-what-changed) ·
[6.1 versus_link](#61-versus_linkvhd-the-conversation) ·
[6.2 tetris_core changes](#62-tetris_corevhd-what-changed) ·
[6.3 text_pkg + text_layer](#63-text_pkgvhd--text_layervhd-writing-on-the-screen) ·
[6.4 tetris_render changes](#64-tetris_rendervhd-what-changed) ·
[6.5 tetris_sound](#65-tetris_soundvhd-music-and-effects) ·
[6.6 top_tetris](#66-top_tetrisvhd) ·
[6.7 tests](#67-testing-it) ·
[6.8 try it on the board](#68-try-it-on-the-board)

---

## 6.0 What changed

```
                                     J5 cable or USB (SW7) 
                                          ▲      │
                                    tx    │      ▼  rx
 buttons ─► tetris_input ─► tetris_core ◄──► versus_link        (NEW)
                               │   ▲            uart_tx / uart_rx (from test 03/04)
                               │   └── garbage in, opponent lost, start
                               ▼
              tetris_render (+9 × text_layer, NEW) ──► VGA
              tetris_sound (NEW) ──► audio jack, buzzer
```

| File | New / changed | What |
|---|---|---|
| `src/game/versus_link.vhd` | new | 1-byte messages to/from the other board |
| `src/game/text_pkg.vhd` | new | a 5×7 pixel font + string → character codes |
| `src/game/text_layer.vhd` | new | draws one line of text |
| `src/game/tetris_sound.vhd` | new | Tetris theme + sound effects → audio pin |
| `src/game/tetris_core.vhd` | changed | garbage in/out, 3 new states, win/lose/draw, start sync, stack height |
| `src/game/tetris_render.vhd` | changed | text, garbage meter, rival bar, result banner |
| `game/top_tetris.vhd` | changed | wires the new blocks, 3 more switches, link + audio pins |
| `sim/tb_versus.vhd` | new | two whole boards in one simulation |
| `tools/fake_opponent.py` | new | the PC plays the other board |

Cost: logic use went from 28 % to 44 % of the chip; timing still fine
(WNS +7.8 ns).

---

## 6.1 `versus_link.vhd`: the conversation

### The message (L5–22)

Every message is **one byte**: the top 3 bits say *what* it is, the bottom 5
bits carry a number.

```
  bit:   7   6   5   4   3   2   1   0
       [  type   ] [       value       ]

  type 000  HEARTBEAT  value = my stack height (0..20)
  type 001  GARBAGE    value = lines to add (1..31)
  type 010  LOST       I topped out
  type 011  START      start your round too
  type 100..111        free: the chaos attacks will use these
```

Example: "send 4 garbage lines" = type 001, value 00100 = `00100100` = 0x24.

Why one byte? It's the smallest thing `uart_tx` sends (one frame of 10
bits, 87 µs at 115200 baud), so every message arrives whole or not at all,
and there's no "which byte am I in" problem.

### Constants and signals (L63–86)

`T_HEARTBEAT` ... `T_START`: the 4 type codes. Then the transmitter and
receiver wires (`tx_data`, `tx_start`, ...), then three groups:

* **waiting to be sent:** `start_p`, `lost_p`, `hb_p` (one flag each) and
  `garb_p` (a *number*: garbage lines waiting, so several requests add up);
  `hb_cnt` counts frames between heartbeats.
* **receive side:** `silence` counts frames since the last byte; `g_*` are
  the one-clock output pulses; `opp_h` is the last height heard.

`msg(t, v)` (L90) builds a byte: `t & 5-bit v`.

### Placing the UART blocks (L96–102)

The exact `uart_tx` / `uart_rx` from tests 03 and 04, with the bit time as
a generic (the testbench makes it 8 clocks instead of 434 to run faster).

### Sending (L114–160)

Two halves, the same pattern as `top_uart_echo`:

1. **Remember** (L114–128): `send_start` / `send_lost` pulses set their
   flags. Every `HB_FRAMES` (6) frames, `hb_p` is set: 10 heartbeats per
   second.
2. **Send** (L130–160) when the transmitter is free, **in priority order**:
   START, LOST, GARBAGE, HEARTBEAT. An `if / elsif` chain *is* a priority
   encoder: the first true condition wins, so a heartbeat can never delay a
   LOST.

The garbage number uses a variable `gsum` because two things can change
it in the same clock: it's sent (→ 0) and new garbage arrives (+ n). Doing
both on a variable in order, then writing the signal once at the end, gets
both right. (The core uses the same trick for `pending`, 6.2.)

### Receiving (L161–185)

On each `rx_valid` pulse: reset `silence` to 0, then `case` on the top 3
bits: a heartbeat updates the rival height, the others become one-clock
pulses with the 5-bit value. Unknown types are ignored. That's why adding
chaos messages later won't break anything.

**link_ok** (L195) = `silence < TIMEOUT_FRAMES`. Since the other board sends
a heartbeat every 6 frames, silence for 30 frames (0.5 s) means the cable
is out or the other board is off. Then the core plays single player.

---

## 6.2 `tetris_core.vhd`: what changed

### New ports

| In | Out |
|---|---|
| `versus`: link_ok, a second board is there | `start_out`: I pressed start |
| `start_in`: the other board started | `lost_out`: I topped out |
| `garb_in` + `garb_in_n`: garbage arrived | `garb_out` + `garb_out_n`: send this garbage |
| `opp_lost`: the other board topped out | `height`, `pending`, `result` |

`result` (L182–186): 0 nothing, 1 WIN, 2 LOSE, 3 DRAW, 4 GAME OVER
(single player).

### Starting together (S_IDLE, L313)

Pressing start on either board sends START (`start_o` pulse → link →
cable). The other board's `start_in` makes it leave S_IDLE too. Both
boards start within ~0.1 ms of each other. A START that arrives while
already playing is ignored, because only S_IDLE looks at it.

**Cool-down.** Found playing on two boards: you press hard drop, and in that
same moment the rival tops out. Your board jumps to WIN and the hard drop
lands in S_IDLE, which starts the next round on both boards. So for 1.5 s
after a game ends, S_IDLE ignores the buttons (Part 5, S_IDLE). A START
message from the other board is still accepted: that board has the same
cool-down, so it can only send START once its 1.5 s are over too.
`tb_versus` checks both: a press 5 frames after the end does nothing, a
press after the cool-down starts both boards.

### `pending`: garbage waiting for me (L274–279, L743–747)

`pending_r` holds the number of garbage lines that arrived but haven't come
in yet (the red meter). Up to three things change it in one clock:
S_INIT (→ 0), S_ATTACK (cancel / take some out), and new garbage arriving.
So, like `gsum` above, the process copies it into variable `p` at the start
(L279), every part works on `p`, and the end of the process writes it back
once (L747), after adding newly arrived garbage (L743–746).

### S_ATTACK (L607): turning lines into garbage

Runs after S_SCORE, every time a piece locks.

```vhdl
case cleared is
  when 2 => atk := 1;   when 3 => atk := 2;   when 4 => atk := 4;
  when others => atk := 0;
end case;
```

Lines cleared → garbage to send (a single sends nothing, a Tetris sends
4). Then **cancelling**:

```vhdl
if atk >= p then  atk := atk - p;  p := 0;      -- my attack wipes out what waits for me
else              p := p - atk;    atk := 0;    -- my attack only reduces it
end if;
```

Example: 3 lines wait for me (p = 3) and I clear a Tetris (atk = 4) → 3 of
my 4 cancel them, 1 is sent. If I'd cleared 3 lines (atk = 2): p becomes 1,
nothing is sent. Defending first is the standard rule.

Then: anything left to send → `garb_out` pulse. And if I **cleared
nothing** while garbage waits, some of it comes in now → S_HOLE: at most
3, 4 or 5 lines per lock, picked at random from 2 LFSR bits (chaos round 2;
it was a fixed 8 before, which felt like too much on top of the chaos).

### S_HOLE (L641) and S_GARB (L650): garbage rising from the bottom

S_HOLE picks the hole column, a random 0..9 from the LFSR (4 bits, retry if
≥ 10, the same trick as S_PICK).

S_GARB adds one grey row per clock:

```vhdl
for r in 0 to ROWS - 2 loop
  occ_r(r) <= occ_r(r + 1);         -- every row takes the one below it
  col_r(r) <= col_r(r + 1);
end loop;
occ_r(ROWS - 1)       <= (others => '1');    -- new bottom row: all full...
occ_r(ROWS - 1)(hole) <= '0';                -- ...except the hole
col_r(ROWS - 1)       <= (others => '1');    -- colour 7 = grey
```

This is the opposite of S_CLEAR: the whole field moves **up** one row.
In hardware it's very cheap. Row r's flip-flops just load from row r + 1,
fixed wires with no muxes, all 20 rows in the same clock.

Before shifting it checks `occ_r(0) /= EMPTY_OCC`: if the top row has
anything, shifting would push it off the field, so **I lose**.

### Losing, winning, drawing

* **Lose** (no room to spawn, or garbage push-out): `over_r`, `playing_r = 0`,
  `lost_o` pulse (→ LOST message), `result_r` = LOSE (or GAME OVER if no
  link), `lose_age = 0`.
* **Win** (L726): when `opp_lost` arrives while I'm playing → `result_r = WIN`,
  stop, go to S_IDLE. This is written **after** the `case`, so it overrides
  whatever state the `case` chose in that clock ("last assignment wins").
  Receiving LOST means "you won", **at once**: the game stops in that clock,
  so I can't top out afterwards.
* **Draw** (very rare): both boards top out at practically the same moment,
  *before* either LOST message has arrived. Then:

  ```
  board A                                board B
  tops out → LOSE, sends LOST ──┐   ┌── tops out → LOSE, sends LOST
                                 ╳
  LOST arrives while A is  ◄────┘   └────► LOST arrives while B is
  already LOSE → DRAW                      already LOSE → DRAW
  ```

  Each board sees the other's LOST arrive *while it has already lost* and
  changes its own LOSE into DRAW. Both do it the same way, so both screens
  agree, and **no extra "we tied" message is needed**.

  In the normal case only one board tops out: its LOST makes the other one
  WIN and stop, so the winner never sends LOST, and the loser stays LOSE.

  `lose_age` (frames since I lost) must be below 6 (0.1 s) for a DRAW. A
  LOST message takes well under a millisecond to arrive, so a real "same
  moment" draw always fits. The limit is only a safety net: if the cable was
  out when I lost (my LOST went nowhere) and the other board keeps playing
  alone and loses much later, that late LOST must not turn my old LOSE into
  a DRAW.

### Stack height (L751–765)

A separate clocked process scans rows 19 → 0. Each non-empty row
overwrites `h`, so after the loop `h` = 20 − (highest non-empty row).
That's a *priority encoder* built from a loop. It feeds the heartbeat.

---

## 6.3 `text_pkg.vhd` + `text_layer.vhd`: writing on the screen

### The font (text_pkg L45–102)

Each character is a 5×7 picture written as text, the same idea as the
piece shapes (Part 5 §5.1):

```vhdl
10 => g(".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"),  -- A
```

`g()` joins the 7 rows and turns 'X' into '1': bit `5*r + c`. The table
`FONT` has 64 entries (6-bit codes). In hardware it's a ROM, 64 × 35 bits.

**Character codes** (L5–10): digits are 0..9 (so a BCD digit *is* its
character code, no conversion), letters 10..35, then a few symbols.
`to_codes("WIN!")` (L128) turns a whole string into codes, 6 bits each,
character 1 in the lowest bits. It only runs while compiling, for fixed
text.

### Drawing one line (text_layer)

Generics: `X0, Y0` (top-left), `LEN` (characters), `SHIFT` (size: each font
pixel is a 2^SHIFT square). Each character takes a 6 × 8 cell (5×7 + one
pixel gap).

For each screen pixel:

```vhdl
dx := (xi - X0) / S;      -- position in font pixels (S = 2^SHIFT: free shift)
dy := (yi - Y0) / S;
ci := dx / 6;             -- which character
cc := dx mod 6;           -- which column inside it (5 = the gap)
code := chars(6*ci + 5 downto 6*ci);   -- (done with a loop: synthesis-friendly)
pix  := glyph_of(code)(5 * dy + cc);
```

`/ 6` is not a power of 2, so this one *does* build a small divider. It's
small because `dx` is at most ~130. The output is registered, so it's ready
exactly when stage 2 of the renderer needs it (same timing as the `s1_*`
registers).

Size example: "WIN!" with SHIFT = 2: each font pixel = 4×4 screen pixels,
each character 24 × 32, 4 characters = 96 px wide.

---

## 6.4 `tetris_render.vhd`: what changed

New inputs: `lines_bcd`, `result`, `pending`, `opp_height`, `link_ok`.

**Nine text layers** (L144–161), each a separate copy of `text_layer`
placed at a fixed spot: NEXT, LEVEL, LINES, the line number, RIVAL, the link
status, PRESS START, the result word, GAME OVER. Fixed text comes from
constants (`TXT_NEXT`...), because VHDL-93 doesn't allow a function call in
a port map (our rule from Part 1). Changing text is chosen by signals:

* `num_chars` (L135): the 4 BCD digits, with "00" added to make 6-bit codes.
* `link_chars` (L137): " LINKED" or "NO LINK".
* `res_chars` (L138): "WIN!" / "LOSE" / "DRAW" chosen with `with result select`.

**Stage 1 additions:**
* garbage meter (L248): the 8 px column left of the field, filled
  if `y ≥ 400 − 16 × pending`, so it grows upwards, 16 px per waiting line;
* rival bar (L261): same idea with `opp_height`;
* dark bands (L274): rows behind the result text and PRESS START, so the
  text is readable over blocks.

**Stage 2 additions** (L330 on): inside the field, the banner is drawn
*last*, so it covers blocks. Result colours: gold WIN!, red LOSE / GAME
OVER, white DRAW. The field frame turns gold when you win. Outside the
field, new layers: the meter (red on dark red), the rival bar (grey, red
when it's ≥ 15 high, dark when no link), the link text (green / red), and
the labels.

---

## 6.5 `tetris_sound.vhd`: music and effects

### A note is a counter (L66–89, L268–291)

A square wave at frequency f flips every 25,000,000 / f clocks. A4 = 440 Hz
→ flip every 56,818 clocks. `half_period(n)` is that table for the 18 notes
we use. A tone generator is a counter that flips `m_sq` and restarts when it
reaches the half period:

```vhdl
elsif m_cnt >= half_period(mus_now) - 1 then
  m_cnt <= 0;
  m_sq  <= not m_sq;
```

Note 0 means silence: the counter and output stay at 0. Two generators: one
for music (`m_sq`), one for effects (`s_sq`).

### The melody (L101–120)

Two ROMs side by side: `MUS_NOTE` (which note) and `MUS_LEN` (how many
eighth notes), 40 steps = the 8-bar Tetris theme ("Korobeiniki"), bar by bar
in the comments. The player (L246–264), once per frame:

* when a note runs out: load the next one, length = eighths ×
  `eighth_frames(level)` (12 frames = 0.2 s at level 0, down to 6 at level
  6+: **the music speeds up with the level**);
* in the last frame of a note: silence (`mus_now <= 0`), so two equal notes
  in a row are heard as two.

It only runs while `playing = '1'` and restarts at every game.

### Effects (L122–166, L205–244)

Each effect is up to 4 (note, frames) steps in two 2-D arrays (`fx_t`, an
array indexed by two numbers). Events start them: a lock click, a rising
chirp for lines, a fanfare for a Tetris, a low thud when garbage arrives,
win / lose jingles, a start beep. Starts are detected as **edges**: the
process keeps last clock's `playing` and `result` (`playing_d`,
`result_d`). "Was 0, is now 1" = the game just started.

### Mixing to one pin: the bucket trick (sigma-delta) (L293–313)

The visual guide's section 11 shows all of this step by step, with a bucket
you can fill clock by clock. Here is the same in text.

**1. The problem.** An FPGA pin is a switch: 0 V or 3.3 V, nothing in
between. Connect one square wave to it and you hear one beep at full volume.
But we want **two sounds at once**, and the music **quieter** than the
effects. Both need voltages *between* 0 and 3.3 V, which a pin can't make.

**2. The trick.** Switch the pin on and off *very* fast: up to 50 million
times a second. A headphone's speaker (a little paper cone with a magnet) is
far too slow to follow that. It only follows the **average**. If the pin is
on 3 clocks out of every 16, the speaker behaves as if it got a steady
3/16 × 3.3 V ≈ 0.6 V. It's the same as dimming an LED by blinking it faster
than the eye can see.

**3. How loud should it be right now?** That's `loudness`, a number from 0
to 15 ("out of 16"). Each sound is a square wave, so at any instant it's
either up or down:

```vhdl
loudness := 0;
if m_sq = '1' and music_on = '1' then loudness := loudness + 3; end if;   -- music: quiet
if s_sq = '1' and sfx_on = '1'   then loudness := loudness + 7; end if;   -- effects: louder
```

| music square | effect square | loudness | the speaker feels |
|---|---|---|---|
| 0 | 0 | 0 | 0 V |
| 1 | 0 | 3 | 0.62 V |
| 0 | 1 | 7 | 1.44 V |
| 1 | 1 | 10 | 2.06 V |

As the two squares go up and down at their own speeds (440 Hz and, say,
1047 Hz), `loudness` jumps between these four values. The speaker then
draws the **sum of the two waves**: that's mixing. And the music adds only 3
while effects add 7: that's the volume difference.

**4. Turning `loudness` into on/off clocks: the bucket.** Imagine a bucket
that holds 16. Every clock, pour `loudness` into it. If it reaches 16 or
more, it **overflows**: the pin is ON for this clock, and 16 is poured away.
Otherwise the pin is OFF. With loudness 3:

```
clock:    1  2  3  4  5  6   7  8  9 10 11  12 13 14 15 16
bucket:   3  6  9 12 15  2   5  8 11 14  1   4  7 10 13  0
           (18→2)    (17→1)       (16→0)
pin:      0  0  0  0  0  1   0  0  0  0  1   0  0  0  0  1    → ON 3 times in 16
```

Over every 16 clocks the bucket overflows exactly `loudness` times, and the
ONs are spread out evenly, which makes the averaging easy.

**5. The bucket in VHDL** is one 5-bit register, `bucket`:

```vhdl
bucket <= ('0' & bucket(3 downto 0)) + to_unsigned(loudness, 5);
audio  <= bucket(4);
```

* `bucket(3 downto 0)`: what's in the bucket (0..15).
* `'0' &` it: drop the old bit 4. Dropping a bit worth 16 = **pouring 16 away**.
* `+ loudness`: pour in this clock's amount.
* bit 4 of the result is '1' exactly when the sum reached 16: **overflow =
  pin on**.

That's the whole mixer: one adder and five flip-flops, no DAC chip.

**The name:** Σ (sigma) means "sum", because the bucket keeps adding. Δ
(delta) means "difference", because each overflow takes 16 back out, so the
output keeps correcting itself and never drifts from the right average.
"Sigma-delta modulator" is the textbook name for exactly this bucket.

---

## 6.6 `top_tetris.vhd`

* **Generic `LINK_CLKS_PER_BIT`**: 434 normally (115200 baud).
* **The settings switches** go through `switch_filter` (L176–181): pause
  (SW2), music (SW4), sound effects (SW5), and SW7 = "use USB". All settings
  sit at the right end of the row of slide switches (SW7 was SW22 before the
  switch re-layout).
* **Link source** (L232): `rx_line <= usb_rx when usb_s = '1' else link_rx;`.
  A 2-to-1 mux picks which wire the link listens to. It *sends* on both
  wires always: the J5 pin and the USB line. Nobody listening is harmless.
* **Pull-ups** in `pins.xdc` on both receive pins: an unplugged J5 pin then
  reads '1' (= idle), not random noise that could look like messages.
* `u_link`, `u_sound` placed; core outputs go to the link and vice versa.
  `got_garb` also goes to the sound block (thud when garbage arrives).

---

## 6.7 Testing it

### `sim/tb_versus.vhd`: two boards in one simulation

Two `tetris_core` + two `versus_link`, wired exactly like the cable:

```vhdl
link_a_i : ... rx => line_ba, tx => line_ab ...
link_b_i : ... rx => line_ab, tx => line_ba ...
```

Faster settings so it simulates in seconds: frame tick every 400 clocks,
link at 8 clocks per bit (logic unchanged, only generics).

* The **robots** are now *procedures* (`play_piece`, `choose`, `press`) that
  take the board's signals as parameters, so the same code plays board A
  and board B. Robot B is "sloppy": one piece in four goes to a random
  column.
* `robot_a` waits until both links are up (heartbeats), then presses start
  **only on A**. `robot_b` waits until B is playing, which proves that START
  went over the link.
* The **referee** waits for a game end, then checks:
  one WIN + one LOSE (or DRAW + DRAW); garbage messages sent = received;
  if garbage was sent, a grey row really appeared.

**Story from writing it:** the first runs PASSED but reported "no garbage
was sent". Logging every clear showed the robots only ever cleared
**single** lines, which send nothing. The fix was in the robot: it now
prefers 2+ line clears. Then: "A cleared 2 → A sends 1 garbage → B received
1 → grey row → A WIN / B LOSE". **A passing test can still be testing the
wrong thing:** always check it exercised what you care about.

### `sim/tb_tetris_frame.vhd`: screenshots

The whole `top_tetris` with a pretend PC on the USB input (a `uart_tx` in
the testbench) sending heartbeats (rival height 9), then 3 garbage lines
(→ red meter), then LOST (→ WIN!). Two screenshots: `sim/out/frame.png`
and `frame2.png`.

### `tools/fake_opponent.py`

The same protocol in Python with pyserial: a thread sends a heartbeat
every 0.1 s, another prints what the board sends, and you type commands
(`s`, `g 3`, `l`, `h 12`, `a` for auto). See `game/README.md`.

---

## 6.8 Try it on the board

1. **One board + PC:** load `game`, SW7 up, run
   `python tools\fake_opponent.py COM3`. LINKED appears; try `g 3`, `h 15`,
   `l`, and clear 2 lines yourself.
2. **Two boards:** run test 04 first (cable check), then load `game` on both,
   SW7 down, wire J5 as in `game/README.md`, press SW18 on either board.
3. **Sound:** headphones / speakers in the audio jack, SW4 + SW5 up.

Next layer: **chaos**. The free message types 100..111 will carry attacks
(scramble controls, flip screen, the OIIA cat, ...) and the switch
mini-tasks will trigger them.
