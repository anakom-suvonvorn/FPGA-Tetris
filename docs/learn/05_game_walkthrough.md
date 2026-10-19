# Part 5: The game, line by line (`src/game/` + `game/`)

This part explains the Tetris game: what each file does, how they talk to
each other, and why it's designed this way. Read Parts 1–3 first; this part
uses the same ideas (clocked processes, one-clock pulses, enables, state
machines, port maps) on a bigger design.

Line numbers (`L205`) refer to the files as they are now.

**Visual version:** `docs/learn/tetris_visual.html` (also published at
https://claude.ai/artifact/28Mdg6vDhCJzwXsmgR6Cdb). It has interactive
diagrams for the coordinates, the collision check, the state machine,
S_LOCK / placed_row, S_CLEAR, bcd_inc, the randomiser and the renderer.
Keep it open next to this text.

Contents:
[5.0 The big picture](#50-the-big-picture) ·
[5.1 tetris_pkg](#51-tetris_pkgvhd-shared-types-shapes-colours) ·
[5.2 tetris_input](#52-tetris_inputvhd-buttons--actions) ·
[5.3 tetris_core](#53-tetris_corevhd-the-rules) ·
[5.4 tetris_render](#54-tetris_rendervhd-drawing) ·
[5.5 top_tetris](#55-top_tetrisvhd-wiring-it-together) ·
[5.6 the testbenches](#56-the-testbenches) ·
[5.7 changing things](#57-changing-things-exercises)

---

## 5.0 The big picture

### A game without a program

In software, a game is a loop: read input, update, draw, repeat. On the FPGA
there's no CPU running a loop. Instead there are **separate circuits running
at the same time**, each doing one job all the time:

```
             ┌──────────────┐  action pulses     ┌──────────────┐  field, piece,   ┌───────────────┐
 5 buttons ─►│ tetris_input │──────────────────► │ tetris_core  │────────────────► │ tetris_render │──► VGA pins
             └──────────────┘ act_left, act_rot… │  (the rules) │ ghost, next…     └───────▲───────┘
                     ▲                           └──────▲───────┘                         │ x, y, sync
                     │ frame_tick (60 Hz)               │ frame_tick                      │
                     └──────────────────────┬───────────┴─────────────────────────────────┘
                                      ┌─────┴─────┐
                                      │ vga_sync  │   (from Part 2, unchanged)
                                      └───────────┘
```

* **vga_sync** counts pixels. Once per frame (60 times a second) it gives a
  one-clock `frame_tick` pulse. That pulse is the game's heartbeat.
* **tetris_input** turns the buttons into one-clock "do this" pulses.
* **tetris_core** holds the whole game state in flip-flops: the field, the
  falling piece, the next piece, lines, level. Once per frame it applies the
  rules.
* **tetris_render** doesn't change anything. It *looks* at the core's state
  and, for whichever pixel the monitor is drawing right now, outputs that
  pixel's colour. It never stores a picture: the picture is computed fresh,
  pixel by pixel, 60 times a second.

That last point is important. We have no frame buffer (640×480×12 bits =
3.7 Mbit, ten times the chip's block RAM). It works because the field is
small (200 cells) and every pixel's colour can be computed from the cell it
falls in.

### How much time does the core have?

One frame is 1/60 s = **833,333 clocks**. The core's whole per-frame sequence
(rotate, move, fall, find ghost, lock check) takes **about 10 to 40 clocks**.
Even locking a piece and clearing 4 lines takes under 50 more. So the core is
idle 99.99 % of the time, and that's fine: being idle costs nothing. It lets
us do things **one step per clock** with simple, small hardware instead of
doing everything at once with huge hardware (see 5.3, "Why one collision
checker").

### The files

| File | What it is | Hardware? |
|---|---|---|
| `src/game/tetris_pkg.vhd` | types, the piece shapes, colours, speed table | no (shared definitions) |
| `src/game/tetris_input.vhd` | 5 debouncers + auto-repeat | yes, ~150 FFs |
| `src/game/tetris_core.vhd` | the game rules and state | yes, the biggest part |
| `src/game/tetris_render.vhd` | pixel colours | yes |
| `game/top_tetris.vhd` | places and wires everything | wiring only |
| `game/project.txt`, `game/pins.xdc` | file list, pins | (Part 3 §3.0) |

---

## 5.1 `tetris_pkg.vhd`: shared types, shapes, colours

### How the playfield is stored (L35–41)

```vhdl
L35  constant ROWS : integer := 20;
L36  constant COLS : integer := 10;
L38  subtype occ_row_t   is std_logic_vector(COLS - 1 downto 0);
L39  type    occ_field_t is array (0 to ROWS - 1) of occ_row_t;
L40  subtype col_row_t   is std_logic_vector(3 * COLS - 1 downto 0);
L41  type    col_field_t is array (0 to ROWS - 1) of col_row_t;
```

The field is stored **twice, in two different ways**:

* `occ_field_t` ("occupied"): 20 rows, each a 10-bit vector. Bit `c` of row
  `r` is `'1'` if that cell has a block. **200 flip-flops.**
* `col_field_t` ("colour"): 20 rows, each 30 bits = 3 bits per cell saying
  *which* colour (0..7). **600 flip-flops.**

Why separate? The rules (collision, full-row check) only care *whether* a cell
is full, never *which colour*. Keeping that as a plain bit vector makes those
checks tiny: "is row 7 full?" is just `occ(7) = "1111111111"` (a 10-input AND
gate). Colour is only needed by the renderer.

```
          column:  0 1 2 3 4 5 6 7 8 9
 row 0  (top)      . . . . . . . . . .      occ(0)  = "0000000000"
 ...
 row 18            . . . T . . . . . .      occ(18) = "0000001000"   (bit 3 set)
 row 19 (bottom)   . . T T T . . . . I      occ(19) = "1000011100"   (bits 2,3,4,9)
                                                       ↑ bit 9       ↑ bit 0
```

(Remember: in `"1000011100"` the **leftmost** character is bit 9, because the
vector is declared `9 downto 0`. So column 0 is the **rightmost** character.
Only humans get confused by this; the hardware doesn't care.)

`colf(r)(3*c + 2 downto 3*c)` is the colour of cell (r, c). Column 0 =
bits 2..0, column 1 = bits 5..3, and so on.

**Row 0 is the top.** Pieces fall to bigger row numbers. Same direction as
the VGA `y`, which makes drawing easy.

### Shapes and colours (L43–45)

```vhdl
L43  subtype shape_t  is std_logic_vector(15 downto 0);
L44  subtype color_t  is std_logic_vector(2 downto 0);
L45  subtype rgb_t    is std_logic_vector(11 downto 0);    -- RRRR GGGG BBBB
```

A **shape** is a 4×4 picture of one piece in one rotation, 16 bits:
bit `(4*r + c)` = row r, column c of the box.

```
 T, rotation 0:          bit numbers in the box:
   . X . .                  0  1  2  3
   X X X .                  4  5  6  7
   . . . .                  8  9 10 11
   . . . .                 12 13 14 15
 → bits 1, 4, 5, 6 are '1'
```

A **colour number** (3 bits) is 0..6 for the pieces I O T S Z J L and 7 for
grey (garbage, for versus mode later). The piece number *is* its colour
number, so we never need a separate table.

### Positions (L48–52): "wide" columns

```vhdl
L48  subtype xpos_t is integer range -2 to 14;
L49  subtype ypos_t is integer range -2 to 21;
L51  constant SPAWN_X : integer := 6;
L52  constant SPAWN_Y : integer := 0;
```

The piece's position is where the **top-left corner of its 4×4 box** is.
`y` is simply the board row of the box's top row. `x` uses a trick:

```
 wide column:  0  1  2 | 3  4  5  6  7  8  9 10 11 12 | 13 14 15
               wall    |  board columns 0 .. 9          |  wall
```

There are 3 imaginary wall columns on each side, so `x` (wide) = board
column + 3. Why? Look at the vertical I piece: its blocks are in box column
2. To put it against the left wall (board column 0) the box must start at
board column −2: wide x = 1. With wide columns, every legal position has
x ≥ 0, and the walls can simply be treated as `'1'` cells (5.3, `collides`).

`SPAWN_X = 6` puts the box over board columns 3..6, so 3-wide pieces appear
centred (columns 3–5), like official Tetris.

**About the ranges −2..14 and −2..21:** these are the ranges of the
*integer types*, which only decide how many bits the register gets (5 bits).
They are not the play area. Where pieces really go is about x = 1..11. But the
core also *tests* positions that may be illegal: moving tries x ± 1, a wall
kick tries up to x ± 2. So a tested position can be about −1..13, and the
type range covers that with a little spare. It's the same for y.

**Why not just use board columns (box from −2 to 8)?** You could. Then the
collision check would need separate "is this left of the wall / right of the
wall" logic, and couldn't index a bit vector with a negative number. Shifting
everything by 3 turns the walls into ordinary `'1'` bits of a 16-bit row
(`"111" & occ(row) & "111"`), so the same check handles walls, floor and
blocks.

### Timing constants (L55–56)

`LOCK_FRAMES = 30`: a piece resting on something locks after 30 frames
(0.5 s). `LOCK_RESETS = 15`: moving/turning it restarts that wait, at most 15
times per piece (otherwise you could spin forever).

### `pic`: drawing shapes as text (L77–86)

```vhdl
L77  function pic(s : string) return shape_t is
L78    variable r : shape_t := (others => '0');
L79  begin
L80    for i in 0 to 15 loop
L81      if s(s'low + i) = 'X' then
L82        r(i) := '1';
```

Takes 16 characters and makes a 16-bit shape: character i → bit i. `s'low`
is the index of the string's first character (strings start at 1; `'low`
saves us from remembering that).

This function only runs **while compiling**: it's used to build the
constant table below, so the result is just fixed bits. No hardware is made
from it. That lets us write the shapes as readable pictures.

### The shape table (L88–129)

```vhdl
L88  type shape_table_t is array (0 to 31) of shape_t;
L90  constant SHAPES : shape_table_t := (
       -- 2: T
       pic(".X.." & "XXX." & "...." & "...."),     -- rotation 0
       pic(".X.." & ".XX." & ".X.." & "...."),     -- rotation 1 (turned right)
       pic("...." & "XXX." & ".X.." & "...."),     -- rotation 2
       pic(".X.." & "XX.." & ".X.." & "...."),     -- rotation 3
```

`&` joins the 4 rows into one 16-character string. 8 groups (7 pieces + an
empty one so the table is 32 = 2⁵ entries) × 4 rotations.

The rotations follow **SRS** (Super Rotation System), the official
rotation rules: each piece turns around a fixed centre inside its box. That's
why the T's rotation 2 is in rows 1–2, not 0–1: it turns in place instead of
jumping up. Players expect exactly this behaviour, so it's worth copying.

In hardware `SHAPES` is a **ROM**: 32 entries × 16 bits, made of LUTs.

```vhdl
L131 function shape_of(p : integer range 0 to 7; rot : integer range 0 to 3) return shape_t is
L133   return SHAPES(p * 4 + rot);
```

The ROM address = piece × 4 + rotation. Multiplying by 4 is free (it's just
putting `p` in address bits 4..2 and `rot` in bits 1..0).

### Speed table (L136–156)

`gravity_frames(level)` = how many frames the piece waits before falling
one row: 48 frames (0.8 s) at level 0 down to 2 frames (30 rows/s) at level
15. A `case` on a 4-bit input = a small ROM. The numbers are similar to
the NES version of Tetris.

### Colours (L158–193)

`piece_rgb` maps the 3-bit colour number to a 12-bit RGB colour (a ROM
again). `lighten` and `darken` are the same as in test 01 (Part 3 §3.1):
for each of R, G, B, `lighten` moves the 4-bit value halfway to 15
(e.g. 8 → 8 + (15−8)/2 = 11) and `darken` halves it (8 → 4). Used for the
3D bevel on every block.

---

## 5.2 `tetris_input.vhd`: buttons → actions

**Job:** five buttons in, five one-clock "action" pulses out. Moving
sideways and soft drop **repeat** while held, like holding a key on a
keyboard.

```vhdl
L22  entity tetris_input is
       generic (DEBOUNCE_CYCLES : integer := 250_000);   -- 5 ms
       port (clk, frame_tick, btn(4 downto 0),
             act_left, act_right, act_rot, act_soft, act_hard);
```

`btn` order: 0 left, 1 right, 2 rotate, 3 soft drop, 4 hard drop. The
generic lets a testbench use a much shorter debounce (Part 1 §1.11).
5 ms is shorter than the 20 ms used in the tests. Games need fast reactions,
and these buttons bounce for well under 5 ms.

### Five debouncers with `generate` (L52–56)

```vhdl
L52  g_db : for i in 0 to 4 generate
L53    u_db : entity work.debounce
L54      generic map (STABLE_CYCLES => DEBOUNCE_CYCLES)
L55      port map (clk => clk, btn_in => btn(i), level => lvl(i), pressed => prs(i));
L56  end generate;
```

A `for ... generate` **copies hardware** N times (here 5 debouncers), with
`i` being 0, 1, 2, 3, 4 in the copies. It's like placing 5 copies of a
symbol on a schematic and wiring copy *i* to bus bit *i*. `btn(i)` is a
plain wire of the bus, so it's allowed in a port map.

Outputs: `lvl(i)` = clean "is it held", `prs(i)` = one-clock pulse on press.

### The repeat tables (L43–48)

```vhdl
L44  constant REPEATS : std_logic_vector(4 downto 0) := "01011";   -- soft, right, left
L45  constant DAS     : int5_t := (10, 10, 1, 2, 1);
L46  constant ARR     : int5_t := ( 3,  3, 1, 2, 1);
L48  signal held : cnt5_t := (others => 0);        -- frames since pressed
```

* `REPEATS(i) = '1'`: button i repeats (bits 0, 1, 3 → left, right, soft).
* **DAS** ("delayed auto shift"): frames to hold before repeating starts.
* **ARR** ("auto repeat rate"): frames between repeats.
* `held(i)`: a small counter per button.

These names are the ones Tetris players use, which makes them easy to look
up and tune.

### The process (L58–76)

```vhdl
for i in 0 to 4 loop
  act(i) <= '0';                                -- default: no action
  if prs(i) = '1' then                          -- just pressed
    act(i)  <= '1';
    held(i) <= 0;
  elsif lvl(i) = '1' and REPEATS(i) = '1' and frame_tick = '1' then
    if held(i) = DAS(i) - 1 then                -- held long enough
      act(i)  <= '1';
      held(i) <= DAS(i) - ARR(i);
    else
      held(i) <= held(i) + 1;
    end if;
  end if;
end loop;
```

The `for` loop is **copied 5 times** in hardware (Part 1 §1.9). Per button:

* On the press pulse: act at once, reset the counter.
* While held, once per frame: count up. When the count reaches `DAS − 1`,
  act, and **set the counter back to `DAS − ARR`**, so it reaches `DAS − 1`
  again after ARR more frames.

Timeline for "left", DAS = 10, ARR = 3:

```
frame:   0    1  2  ...  9   10   11  12  13   14  15  16 ...
held:    0    1  2  ...  9 → 7     8   9 → 7    8   9 → 7
act:     ▲ (press)          ▲              ▲              ▲
         moves at 0, 10, 13, 16, 19 ...  (1 cell, wait 1/6 s, then 20 cells/s)
```

Soft drop (DAS = 2, ARR = 2): acts on the press, then every 2 frames.

---

## 5.3 `tetris_core.vhd`: the rules

The biggest file. Read its header (L1–42) first, then this section.

### The ports (L48–103)

**In:** clock, frame tick, pause, and the five action pulses.
**Out:** everything the renderer needs (field, piece shape/colour/position,
ghost row, next piece, playing/game-over flags), plus lines (BCD), level,
and `clear_evt` / `clear_n` (a pulse after each lock telling how many lines
it cleared). Versus mode will use that pulse to send garbage to the opponent.

`occ` and `colf` are ports of the **array types from the package**, i.e.
800 wires. Allowed because both sides `use work.tetris_pkg.all` and so
agree on the type.

### The registers (L107–190)

```vhdl
L107  type state_t is (S_IDLE, S_INIT, S_PICK, ..., S_GARB);   -- 21 states (3 of them for versus, Part 6)
L115  signal occ_r : occ_field_t := (others => (others => '0'));
L116  signal col_r : col_field_t := (others => (others => '0'));
```

`(others => (others => '0'))`: a nested aggregate: "every row = (every bit
= '0')". An empty field at power-up.

The rest, grouped:

| Group | Signals | Meaning |
|---|---|---|
| falling piece | `cur_p` (0..6), `cur_rot` (0..3), `cur_sh`, `cur_xr`, `cur_yr` | which piece, rotation, its shape (kept in a register so nobody needs the ROM again), position |
| ghost | `ghost_r` | the lowest row the piece could fall to |
| **candidate** | `cand_rot`, `cand_sh`, `cand_x`, `cand_y`, `collide` | a position being *tested* (see below) |
| kicks | `KICKS`, `kick` | sideways offsets to try when a rotation doesn't fit |
| next piece | `next_p`, `next_sh`, `have_next`, `bag`, `lfsr` | randomiser |
| buttons | `req_*` (remembered), `w_*` (this frame) | see below |
| timers | `grav_cnt`, `lock_cnt`, `resets`, `lock_r` | gravity, lock delay |
| line clear | `rd`, `wr`, `cleared`, `score_left` | see S_CLEAR |
| score | `lines_r` (BCD), `level_r`, `lvl_cnt`, `evt_r`, `evt_n` | |
| flags | `playing_r`, `over_r` | |

### Idea 1: "try" with one collision checker (L195–220, L266)

Almost every rule is "**would the piece fit there?**": moving, rotating,
falling, spawning, finding the ghost. The core has exactly **one** circuit
that answers it:

```vhdl
L266  collide <= collides(occ_r, cand_sh, cand_x, cand_y);
```

It always looks at the **candidate** registers. To test a position, a state
writes it into `cand_*`; on the next clock, `collide` shows the answer and
the next state uses it:

```
 clock k   : S_MOVE      cand_x <= cur_x - 1          (write the question)
 clock k+1 : S_MOVE_CHK  if collide = '0' then         (read the answer)
                            cur_x <= cand_x            (accept the move)
```

**Why one collision checker?** The checker is combinational logic of
roughly a hundred LUTs (4 row-muxes over 20 rows, wall logic, 16 AND
checks). Checking rotation, left, right, down and the ghost all at once
would need five or more copies, plus the ghost would need up to 20 copies
(one per row). Since we have 833,333 clocks per frame, it's far cheaper to
build one checker and ask it questions one after another.

### The `collides` function, step by step (L195–220)

```vhdl
L200  for r in 0 to 3 loop                 -- each row of the 4x4 box
L201    ry := y + r;                       -- which board row that is
L202    if ry > ROWS - 1 then
L203      wide := (others => '1');         -- below the floor: solid
L204    elsif ry < 0 then
L205      wide := "1110000000000111";      -- above the top: only walls
L206    else
L207      wide := "111" & o(ry) & "111";   -- walls + the real field row
L208    end if;
L209    for c in 0 to 3 loop               -- each column of the box
L210      if sh(4*r + c) = '1' then        -- the piece has a block here
L211        if x + c < 0 or x + c > 15 then
L212          hit := '1';                  -- outside even the walls
L213        elsif wide(x + c) = '1' then
L214          hit := '1';                  -- block meets wall/floor/cell
```

For each of the 4 box rows, build a 16-bit "wide row": 3 wall bits, the 10
field bits, 3 wall bits (wide column w = board column w − 3, as in 5.1).
Below the floor every bit is `'1'`; above the top only walls (pieces may
stick out of the top while rotating). Then for each of the box's 4 columns:
if the piece has a block there and the wide row has a `'1'` there → hit.

**Worked example:** T, rotation 0 (bits 1, 4, 5, 6), at x = 6, y = 18:

* r = 0 → board row 18. Block at c = 1 → wide column 7 = board column 4.
  Hit if `occ(18)(4) = '1'`.
* r = 1 → row 19. Blocks at c = 0, 1, 2 → board columns 3, 4, 5.
* r = 2 → row 20 = below the floor, all `'1'`. But the T has no blocks in
  box row 2, so no hit.
* r = 3 → same, nothing.

So the T fits at the bottom if those 4 cells are empty. One row lower
(y = 19), its row-1 blocks would be at row 20 = floor → collide. That's how
"landing" is found.

In hardware the two loops are unrolled (copied 4×4 times). `o(ry)` with a
variable `ry` is a 20-to-1 mux of 10-bit rows; `wide(x + c)` is a 16-to-1
mux of single bits.

### Idea 2: requests vs. this frame's work (L146–149, L304–308, L397–426)

Button pulses can arrive at **any clock**, but the rules run once per frame.
So each action has two flags:

```vhdl
L304  if act_left = '1' then req_left <= '1'; end if;     -- (and the other 4)
```

At the very top of the clocked process, outside the `case`: any action
pulse sets its `req_` flag ("requested"), whatever state we're in. It stays
`'1'` until used.

```vhdl
L397  when S_PLAY =>
        if frame_tick = '1' and pause = '0' then
          w_left  <= req_left  or act_left;     -- take this frame's actions...
          ...
          req_left <= '0'; ...                   -- ...and forget them
```

At the frame tick, copy every `req_` into its `w_` ("work") flag and clear
the `req_`. The steps of this frame use `w_`. The `or act_left` catches a
pulse arriving in exactly this clock. Without it, that press would be lost:
the `req_left <= '0'` below would override the `req_left <= '1'` above
("last assignment wins", Part 1 §1.8).

Gravity is also decided here:

```vhdl
if grav_cnt >= gravity_frames(level_r) - 1 then
  grav_cnt <= 0;   w_grav <= '1';               -- time to fall one row
else
  grav_cnt <= grav_cnt + 1;   w_grav <= '0';
end if;
state <= S_ROT;
```

### The state machine

```
                    ┌──────────────────────── once per frame ────────────────────────┐
                    ▼                                                                │
 S_IDLE ─start─► S_INIT ─► S_PICK ─► S_SPAWN ─► S_SPAWN_CHK ─(fits)─► S_GHOST ─► … ─►│
   ▲                          ▲                     │ (no room)                      │
   └──────── game over ───────┼─────────────────────┘                                │
                              │                                                       │
 S_PLAY ─tick─► S_ROT ─► S_ROT_CHK ─► S_MOVE ─► S_MOVE_CHK ─► S_DOWN ─► S_DOWN_CHK ─┐ │
   ▲                  (kicks loop)                                                   │ │
   │                                                                                 ▼ ▼
   │                                                          S_GHOST ─► S_GHOST_CHK (loop)
   │                                                                          │
   │                    not landed / still waiting                           ▼
   └──────────────────────────────────────────────────────────────────── S_LOCKCHK
                              │                                               │ lock!
                              └── S_SCORE ◄── S_CLEAR (loop) ◄── S_LOCK ◄─────┘
                                  (then S_ATTACK, S_PICK: next piece)
```

Each `when` below is one box. Every "skip" path (button not pressed) just
moves to the next box, so a quiet frame takes only a handful of clocks.

#### S_IDLE (L313): title / game over

Waits for a hard-drop (or rotate) request, then S_INIT. At power-up the field
is empty and the frame is green. After a game over the field keeps its
blocks (shown grey). In versus it also leaves when the other board's START
message arrives, and pressing start sends START (Part 6 §6.2).

**Cool-down** (L286–295, L314–319): when a game ends, presses are ignored
for 1.5 s (`COOLDOWN_FRAMES` = 90 frames), so a hard drop that was on its way
when the game ended doesn't start the next one. `cool` is loaded when
`playing_r` goes from 1 to 0 (`playing_d` is `playing_r` one clock ago: the
same edge-detector trick as the buttons), wherever in the state machine the
game ended. While `cool > 0`, S_IDLE throws the requests away (otherwise the
press would be remembered and start the game the moment the cool-down
ends). `can_start` (L785) tells the renderer when to show PRESS START.

#### S_INIT (L327): new game

Clears both field arrays in **one clock** (`occ_r <= (others => EMPTY_OCC)`
loads 0 into all 800 flip-flops at once), resets lines, level, bag and all
requests, sets `playing_r`.

#### S_PICK (L349): the 7-bag randomiser

```vhdl
rnd := to_integer(unsigned(lfsr(2 downto 0)));       -- random 0..7
if rnd < 7 then
  if bag(rnd) = '0' then                             -- not dealt in this bag yet
    newbag := bag;  newbag(rnd) := '1';
    if newbag = "1111111" then newbag := (others => '0'); end if;
    bag    <= newbag;
    cur_p  <= next_p;                                -- waiting piece comes in
    next_p <= rnd;                                   -- new one waits
```

**The random source:** `lfsr` (L299) is a 16-bit *linear feedback shift
register*: each clock it shifts left and the new bit 0 is the XOR of bits
15, 13, 12, 10. With these "taps" it goes through all 65,535 non-zero values
before repeating. Not truly random, but it changes every 20 ns, and **when**
we sample it depends on when the player pressed buttons (to the
nanosecond). So in practice every game is different.

**The 7-bag rule** (as in modern Tetris): `bag` has one bit per piece type.
A random number is accepted only if it's 0..6 and that piece hasn't been
dealt from the current bag. When all 7 bits are set, the bag empties. So
every group of 7 pieces contains each piece exactly once: no long droughts
without an I piece.

If the random number is rejected (it's 7, or already dealt), nothing happens
and the state stays S_PICK. Next clock the LFSR has moved on, so it tries a
new number. That's a loop that takes a few clocks on average, at worst a few
dozen. Nobody notices.

`have_next`: at the start of a game there's no "next" piece yet, so the
first pick only fills `next_p` (`have_next <= '1'`, stay in S_PICK), the
second pick moves it to `cur_p` and goes on.

#### S_SPAWN / S_SPAWN_CHK (L369, L382)

Put the piece at rotation 0, position (6, 0), load `cur_sh` from the ROM,
**and the same values into the candidate**, then reset the lock timers.
Also update `next_sh` for the preview.

S_SPAWN_CHK reads `collide`: if the new piece overlaps the stack, there's no
room: **game over** (`over_r`, back to S_IDLE; in versus it also sends LOST
to the other board, Part 6). Otherwise go and compute the ghost.

#### S_PLAY (L397): wait for the frame tick

Explained above (Idea 2). While `pause = '1'` the tick is ignored, so the
game freezes. Requests still pile up, which is harmless.

#### S_ROT / S_ROT_CHK (L427, L440): rotate with wall kicks

```vhdl
when S_ROT =>
  if w_rot = '1' then
    if cur_rot = 3 then nrot := 0; else nrot := cur_rot + 1; end if;
    cand_rot <= nrot;
    cand_sh  <= shape_of(cur_p, nrot);
    cand_x   <= cur_xr;   cand_y <= cur_yr;   kick <= 0;
    state    <= S_ROT_CHK;
```

Candidate = the turned shape, same place.

```vhdl
when S_ROT_CHK =>
  if collide = '0' then                       -- fits: accept it
    cur_rot <= cand_rot;  cur_sh <= cand_sh;  cur_xr <= cand_x;
    (restart lock timer, if resets left)
    state <= S_MOVE;
  elsif kick < 4 then                         -- doesn't fit: try a shifted spot
    kick   <= kick + 1;
    cand_x <= cur_xr + KICKS(kick + 1);       -- stay in this state
  else
    state <= S_MOVE;                          -- no luck, don't turn
```

A **wall kick**: if the turned piece hits something, try it 1 right, 1 left,
2 right, 2 left (`KICKS = (0, 1, -1, 2, -2)`). Without kicks you couldn't turn
a piece that's against a wall. Each try costs one clock; the state loops on
itself with a new `cand_x`. (Official SRS has bigger per-piece kick tables
including upward kicks; ours is a simpler version that covers the common
cases.)

#### S_MOVE / S_MOVE_CHK (L458, L472): left / right

```vhdl
if (w_left xor w_right) = '1' then
```

Only if exactly one of them is pressed (both = cancel out). Candidate =
1 column over; accept if no collision. Restarts the lock timer (with the
15-reset limit).

#### S_DOWN / S_DOWN_CHK (L483, L493): fall one row

If gravity says so (`w_grav`) or soft drop is pressed, and it's **not** a
hard drop: candidate = one row lower. If it fits, accept, and reset the
lock timer (the piece is in the air again). Soft drop also restarts the
gravity counter, so the piece doesn't fall twice in a row.

If it doesn't fit, nothing happens: the piece is resting on something, and
S_LOCKCHK decides when it locks.

#### S_GHOST / S_GHOST_CHK (L504, L510): how far could it fall?

```vhdl
when S_GHOST =>
  cand_sh <= cur_sh;  cand_x <= cur_xr;  cand_y <= cur_yr + 1;
when S_GHOST_CHK =>
  if collide = '0' then
    cand_y <= cand_y + 1;              -- still free: look one row lower
  else
    ghost_r <= cand_y - 1;             -- the last free row
    state   <= S_LOCKCHK;
```

A loop: keep moving the candidate down one row per clock until it collides.
The row above that is the **ghost** position, where the piece would land.
It's used twice: the renderer draws the outline there, and a hard drop
simply jumps there. At most ~20 clocks.

If `ghost_r = cur_yr`, the piece can't fall at all: it's **landed**.

#### S_LOCKCHK (L519): lock now?

```vhdl
if w_hard = '1' then                  -- hard drop: jump to the ghost, lock
  w_hard <= '0';  cur_yr <= ghost_r;  lock_r <= 0;  state <= S_LOCK;
elsif ghost_r = cur_yr then           -- landed
  if lock_cnt = LOCK_FRAMES then      -- ...for 30 frames already
    lock_r <= 0;  state <= S_LOCK;
  else
    lock_cnt <= lock_cnt + 1;  state <= S_PLAY;
  end if;
else                                  -- in the air
  lock_cnt <= 0;  state <= S_PLAY;
end if;
```

The **lock delay** gives the player half a second to slide a landed piece
before it sticks: that's what makes fast levels playable. Since this state
runs once per frame, `lock_cnt` counts frames.

#### S_LOCK (L539): write the piece into the field (4 clocks)

```vhdl
row  := cur_yr + lock_r;                         -- board row of box row lock_r
prow := placed_row(cur_sh, lock_r, cur_xr);      -- that box row as 10 field bits
if row >= 0 and row <= ROWS - 1 then
  occ_r(row) <= occ_r(row) or prow;              -- add the blocks
  for c in 0 to COLS - 1 loop
    if prow(c) = '1' then
      col_r(row)(3*c + 2 downto 3*c) <= std_logic_vector(to_unsigned(cur_p, 3));
```

One box row per clock, `lock_r` = 0, 1, 2, 3. `placed_row` (L223) shifts the
4 bits of box row `r` to their board columns: for each board column c, the
box column above it is `j = c + 3 − x`; if j is 0..3, copy that shape bit.
OR-ing it into the row adds the blocks without touching the others. The
colour bits of those cells get the piece number.

**Why 4 clocks and not 1?** Writing all 16 box cells at once means every one
of the 800 field flip-flops needs logic checking "is any of the 16 cells
me?". One row at a time, each field row only needs "is this row
`cur_y + lock_r`?" (a 20-way decoder) and an OR. Far smaller, and 3 extra
clocks cost nothing.

After the 4th row: set up the line clear (`rd = wr = 19`) → S_CLEAR.

#### S_CLEAR (L563): remove full rows (one row per clock)

```vhdl
if rd >= 0 then
  if occ_r(rd) = FULL_ROW then
    cleared <= cleared + 1;                      -- skip it (don't copy)
  else
    if wr /= rd then
      occ_r(wr) <= occ_r(rd);  col_r(wr) <= col_r(rd);   -- copy row down
    end if;
    wr <= wr - 1;
  end if;
  rd <= rd - 1;
elsif wr >= 0 then
  occ_r(wr) <= EMPTY_OCC;  col_r(wr) <= EMPTY_COL;  -- fill the top with empty rows
  wr <= wr - 1;
else
  (done: report cleared lines, go to S_SCORE)
```

Two pointers walk up from the bottom: `rd` (read) visits every row; `wr`
(write) is where the next *kept* row goes. A full row is simply not copied,
so `wr` falls behind `rd` and everything above slides down. When `rd` has
passed the top, the rows from `wr` up to 0 are emptied.

Worked example, rows 17 and 19 full:

```
 start                 rd=19 full: skip    rd=18: copy→19     rd=17 full: skip
 16 [A]                16 [A]              16 [A]             16 [A]
 17 [#########]        17 [#########]      17 [#########]     17 [#########]
 18 [B]                18 [B]              18 [B]             18 [B]
 19 [#########]        19 [#########]      19 [B]  ← wr was 19 19 [B]
 rd=19 wr=19           rd=18 wr=19 clr=1   rd=17 wr=18        rd=16 wr=18 clr=2

 rd=16: copy→18        rd=-1 … wr: empty rows 17, 16, ... 0
 18 [A]                result: 19 [B], 18 [A], everything above shifted by 2
 rd=15 wr=17
```

20 clocks for the reads + up to 20 for the empty rows. Every clock it reads
one row (`occ_r(rd)`: a 20-to-1 mux) and writes one row (decoder on `wr`):
small hardware.

At the end: `evt_r <= '1'` with `evt_n = cleared` → the `clear_evt` /
`clear_n` outputs (for versus mode: "I cleared 2 lines").

#### S_SCORE (L587): count lines, level up

Adds the cleared lines **one per clock** (`score_left` counts down):
`lines_r <= bcd_inc(lines_r)` and every 10th line `level_r + 1` (max 15).

`bcd_inc` (L243) adds 1 to a 4-digit **BCD** number (each 4 bits = one
decimal digit 0..9; you did BCD in the labs): from the lowest digit up, a 9
becomes 0 and carries, anything else gets +1 and stops. We keep the lines
in BCD so the 7-segment display can show them directly, with no binary-to-
decimal converter (the "double dabble" from your lab).

Then → S_ATTACK (turns cleared lines into garbage for the other board, Part 6 §6.2), and from there S_PICK for the next piece.

### Outputs (L767–790)

Each internal register is copied to its out port (Part 1 rule: never read an
out port, so the core keeps internal `_r` copies). `cur_color` is the piece
number as 3 bits (piece number = colour number).

---

## 5.4 `tetris_render.vhd`: drawing

**Job:** for the pixel (x, y) that vga_sync is at right now, output its
colour. Same idea as test 01's `pattern` process (Part 3 §3.1), but split
into **two pipeline stages** because there's more to compute.

This section explains the playfield, next box and level squares. Versus
added text, the garbage meter, the rival bar and the result banner to the
same two stages: see Part 6 §6.4.

### Layout constants (L79–90)

```vhdl
L79  constant FX0 : integer := 240;  constant FY0 : integer := 80;    -- field
L81  constant NX0 : integer := 432;  constant NY0 : integer := 80;    -- next piece
L82  constant LX0 : integer := 432;  constant LY0 : integer := 176;   -- level squares
```

All are **multiples of 16** on purpose: then "pixel position inside its cell"
is just the low 4 bits of x and y (`x(3 downto 0)`), and the cell number is
just the upper bits, with no subtraction needed for the in-cell position.
(The first version had the level squares at y = 168, not a multiple of 16,
and each square was cut in two. The simulated screenshot showed it, and
moving to 176 fixed it.)

### Why a pipeline?

Within one clock (20 ns) the logic between two flip-flops must settle.
"Pixel → cell → read that row of the field → look up the colour → bevel →
compare with piece and ghost" in one go would be a long chain. Splitting it
in two halves with registers in between gives each half a full clock.

```
  x, y ──► [ stage 1 logic ] ──► s1_* registers ──► [ stage 2 logic ] ──► vga_r/g/b registers
  hsync ─────────────────────► s1_hs ──────────────────────────────────► vga_hs
```

The colour comes out 2 clocks after its (x, y). The sync signals go through
the same 2 registers (`s1_hs` → `vga_hs`), so everything is delayed equally
and the picture lines up perfectly. (The monitor can't tell: the whole image
is just 2 clocks = 1 pixel "later", and the sync with it.)

### Stage 1 (L164–294): what's under this pixel?

```vhdl
in_f := xi >= FX0 and xi < FX0 + FW and yi >= FY0 and yi < FY0 + FH;
if in_f then
  col := (xi - FX0) / 16;            -- 0..9
  row := (yi - FY0) / 16;            -- 0..19
```

Which cell (dividing by 16 = dropping 4 bits). Outside the field, use 0 so
the reads below stay in range (their results are ignored there).

```vhdl
occ_row := occ(row);
col_row := colf(row);
s1_occ_bit  <= occ_row(col);
s1_cell_col <= col_row(3*col + 2 downto 3*col);
```

Read that cell from the field: a 20-to-1 mux (row) then a 10-to-1 mux
(column). **This is how 200 cells get drawn without a frame buffer.**

```vhdl
rr := row - cur_y;                   -- which box row of the piece is here?
cc := col + 3 - cur_x;               -- which box column? (+3: wide → board)
if in_f and playing = '1' and rr >= 0 and rr <= 3 and cc >= 0 and cc <= 3 then
  s1_piece <= cur_shape(4*rr + cc);
```

Is the falling piece covering this cell? Turn the cell position into a
position inside the piece's 4×4 box; if it's inside the box, the shape bit
says yes or no. The **ghost** is the same check with `ghost_y` instead of
`cur_y` (same shape, same column, lower row).

The **next-piece box** (64×64 px at (432, 80)) does the same with
`next_shape`, with the box always at its own corner. The **level squares**:
16 px grid, the square is the first 12×12 px of each grid cell, lit if its
index (`lj * 8 + li`) ≤ level.

`s1_field_frame` / `s1_next_frame`: inside a rectangle 4 px bigger than the
field / box. Stage 2 only uses it when the pixel isn't inside, so the result
is a 4 px border.

Everything else (`s1_px`, `s1_py`, video_on, sync) is just copied into
stage-1 registers.

### Stage 2 (L297–415): choose the colour

A priority list. The first match wins, like layers in a drawing program:

```
 inside the field?
   background:  black, with grid lines (x"111") on the first pixel row/column of each cell
   piece?       → its colour with bevel
   else block?  → its stored colour with bevel  (all grey x"555" after game over)
   else ghost?  → only the cell's 1 px outline, in the darkened piece colour
   paused?      → everything ÷ 4 (darken twice)
 on the field frame?  → green (press start) / grey (playing) / red (game over)
 inside the next box? → next piece with bevel, or black
 on the next frame?   → grey
 a level square?      → yellow
 otherwise            → background x"113" (dark blue)
```

`bevel(c, px, py)` (L120): top/left pixel of a cell → `lighten(c)`,
bottom/right → `darken(c)`, else `c`. That 1-pixel light/dark edge makes
flat squares look like raised blocks.

Then exactly as in test 01: black outside the visible area, colour + syncs
into the output registers.

---

## 5.5 `top_tetris.vhd`: wiring it together

The top is only wiring, plus `switch_filter` for the slide switches.
(Versus added the link, sound and three switches, Part 6 §6.6; chaos added more
switches and its three blocks, Part 7.)

* **L54–89, ports:** clock, the 5 buttons, the slide switches, the link and USB
  serial pins, audio, VGA, 7-segment. The generics `DEBOUNCE_CYCLES` and
  `LINK_CLKS_PER_BIT` let testbenches use smaller numbers.
* **L93–166:** one signal per wire between the blocks. The array-type
  signals (`occ`, `colf`) carry 800 bits from core to renderer.
* **L169:** `vga_sync`. `pix_en => open`: the renderer doesn't need it
  (the 2-clock pixel just gets computed twice).
* **L174:**
  ```vhdl
  btns <= btn_hard & btn_soft & btn_rot & btn_right & btn_left;
  ```
  Builds the 5-bit bus in the order tetris_input expects (bit 0 = left ...
  bit 4 = hard drop; `&` puts the leftmost item at the top bit). This is the
  one line to change if you want different buttons for different actions
  (or change the pins in `pins.xdc`).
* **L176–187:** the slide switches (5 settings + 8 task switches) go through
  `switch_filter` (Part 2, §2.7: synchroniser + bounce filter) as a 13-bit
  bus, then get names (`pause_s`, `music_s`, ..., `task_sw`).
* **L189–230:** `tetris_input` and `tetris_core`. Notice how every output of
  the core goes on with the same name: `cur_x => cur_x`. Left of `=>` is the
  block's port, right is the top's signal. Same name on both sides keeps it
  readable.
* **L232–314:** the link (Part 6), the chaos blocks (Part 7), `tetris_render` (L290) and the sound.
* **L315–333:** the 7-segment display: lines, or the countdown of a chaos task (Part 7). Each BCD digit (4 bits) goes
  through `hex7` (Part 2 §2.1), and since a BCD digit is only ever 0..9, the
  hex decoder shows normal decimal digits.

---

## 5.6 The testbenches

### `sim/tb_tetris_core.vhd`: a robot plays

Places only `tetris_core` (no video, no buttons) and makes `frame_tick` very
fast: every 200 clocks instead of 833,333, so a whole game simulates in
seconds.

**The robot** (process `robot`), for every new piece:

1. Reads `cur_color` (= which piece) and the field `occ` from the core's
   outputs.
2. For all 4 rotations × 13 positions: if the piece fits at the top, slides
   it down (with its own copy of the collision rule) to where it would land,
   and counts how many rows that would complete.
3. Picks the best: most lines, then lowest landing spot, then fewest moves.
4. "Presses buttons" by pulsing `a_rot`, `a_left`, `a_right`, `a_hard`
   exactly like tetris_input would, then waits for the lock.

**The checks** after every piece. These are the important part; the robot
is only there to generate lots of realistic games:

* **Cells = 4 × pieces − 10 × lines.** Every piece adds 4 blocks, every
  cleared line removes 10. If locking or clearing ever loses or duplicates a
  block, this fails immediately and prints the field.
* **No full row may remain** after the clear.

It also prints the field as text every 20 pieces, using the piece letters:

```
|.SS.TOOJJJ|
|SSJTTT.ZZ.|
```

Result: 57 pieces, 8 lines, game over detected, **TEST PASSED**.

**A lesson from writing it:** its first run reported "8 cells after 1
piece". The *core* was fine. The *robot* waited for the lock pulse with
`wait until clear_evt = '1'`, but the pulse had already happened while it
was inside `press()`, so it waited for the next one. Meanwhile gravity
dropped a second piece. Fixed by counting lock pulses in a separate process
(`n_locks`) that never misses one. **Testbenches have bugs too.** When a test
fails, check both sides.

### `sim/tb_tetris_frame.vhd`: screenshots

Places the **whole** `top_tetris` (with `DEBOUNCE_CYCLES => 20`), presses the
buttons through the real button inputs (start, then 11 pieces with some
rotations and moves), leaves the 12th piece falling, and records VGA frames
exactly like `tb_vga_frame` (Part 3 §3.6). Since versus, a pretend PC also
sends link messages, so it takes two screenshots: a game in progress and the
WIN! screen (Part 6 §6.7). Results: `sim/out/frame.png`, `frame2.png`
(copies in `game/screenshot_versus.png`, `game/screenshot_win.png`). It
simulates about 1.5 s of real time = 75 million clocks, so it takes several
minutes.

---

## 5.7 Changing things (exercises)

Each of these is a small, safe change. Build with `tools\build.bat game`, or
check the core first with `tools\sim.bat tb_tetris_core`.

1. **Faster sideways repeat:** in `tetris_input.vhd` L45–46 change DAS for
   left/right from 10 to 8 and ARR from 3 to 2.
2. **Longer lock delay:** `LOCK_FRAMES` in `tetris_pkg.vhd` L55 (30 = 0.5 s).
3. **Colours:** `piece_rgb` in `tetris_pkg.vhd`. Each colour is `x"RGB"`,
   one hex digit (0..F) per channel.
4. **Start at a higher level:** in S_INIT, `level_r <= 0` → e.g. 5.
5. **Swap controls:** change the order in the `btns <= ...` line of
   `top_tetris.vhd` (L162), e.g. swap `btn_soft` and `btn_hard`.
6. **Harder:** add a "hold" piece (a register like `next_p` and a button
   that swaps `cur_p` with it, then goes to S_SPAWN). Use the
   first 4 states of a new piece as a guide.
7. **Look inside in Vivado:** `tools\vivado_gui.bat game tb_tetris_core`,
   run the simulation, add `dut/state`, `dut/cur_yr`, `dut/cand_y`,
   `dut/collide` to the waveform and watch one frame's sequence
   S_PLAY → S_ROT → ... → S_LOCKCHK, and the S_GHOST_CHK loop counting
   `cand_y` down to the landing row.

---

## What came next

Versus mode is built: two boards, garbage, win / lose, text and sound.
Everything it added or changed is explained in
[Part 6: versus mode, line by line](06_versus_walkthrough.md).
