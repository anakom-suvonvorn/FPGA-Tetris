# Part 1: VHDL from zero (for someone who already draws schematics)

You already know how to design hardware: you draw gates, flip-flops, muxes and
blocks, connect them with wires and buses, and put sub-schematics inside
bigger ones. **VHDL is just a text way of drawing the same schematic.** The
TA's Schematic Studio proves it: every schematic you drew was turned into a
`.vhd` file before Vivado ever saw it. Vivado never sees pictures, only VHDL.

So the goal of this part is to give you a dictionary: "this thing I draw" =
"this thing I write". Part 2 and Part 3 then go through every file of our
project line by line using that dictionary.

---

## 1.0 The single most important idea

A C/Python program is a list of instructions that run **one after another**.
VHDL is **not** that. A VHDL file describes a circuit, and every part of the
circuit exists and works **at the same time**, all the time, just like every
gate in your schematic is powered and working at the same time.

```vhdl
y <= a and b;
z <= c or d;
```

These two lines are two gates sitting side by side on the board. Swapping the
two lines changes nothing. There is no "first line runs, then the second".

The one place where order matters is inside a `process`, and even there it
describes hardware, not steps in time (section 1.8).

---

## 1.1 The dictionary: schematic ↔ VHDL

| In your schematic | In VHDL | Example |
|---|---|---|
| A block symbol (its outline + pins) | `entity` | `entity debounce is port (...); end entity;` |
| What's drawn *inside* the block | `architecture` | `architecture rtl of debounce is ... begin ... end architecture;` |
| An input pin / output pin of the block | `port` with `in` / `out` | `clk : in std_logic;` |
| A pin that is sometimes input, sometimes output | `inout` port | `pin_f2 : inout std_logic;` |
| A wire (net) inside the sheet | `signal` | `signal pulse : std_logic;` |
| A bus `d[7:0]` | `std_logic_vector(7 downto 0)` | `signal data : std_logic_vector(7 downto 0);` |
| Taking one wire out of a bus | index | `data(3)` |
| Taking a few wires out of a bus (bus tap) | slice | `data(7 downto 4)` |
| Joining wires into a bus | `&` (concatenation) | `'1' & data & '0'` (10 bits) |
| VCC / GND | `'1'` / `'0'` | `tx <= '1';` |
| A gate | logic operator | `y <= (a and b) or not c;` |
| A 2-to-1 mux | `when ... else` | `y <= a when s = '1' else b;` |
| A 4-to-1 mux, a decoder, a truth table | `with ... select` or `case` | see 1.7 |
| A D flip-flop | assignment inside `if rising_edge(clk)` | see 1.8 |
| A register (8 D flip-flops) | the same, on an 8-bit signal | `q <= d;` with `q, d : std_logic_vector(7 downto 0)` |
| A counter (adder + register) | `cnt <= cnt + 1;` in a clocked process | see 1.8 |
| Placing a block from the library | component instantiation | `u_btn : entity work.debounce port map (...);` |
| Wiring the block's pins | `port map` | `port map (clk => clk, btn_in => b, pressed => p)` |
| A pin left unconnected | `open` | `level => open` |
| A block with a setting you change per copy (e.g. counter width) | `generic` | `generic map (STABLE_CYCLES => 1_000_000)` |
| The pin-assignment table in FPGA Builder | the `.xdc` file | `set_property PACKAGE_PIN H11 ...` |

Keep this table open while reading the code. Almost every line of our
project is one row of it.

---

## 1.2 Anatomy of a VHDL file

Every design file has the same three parts. Here is a complete, tiny one: a
2-input AND gate plus a flip-flop on its output.

```vhdl
-- (1) LIBRARIES: which "parts bins" this file uses
library ieee;
use ieee.std_logic_1164.all;     -- the std_logic type ('0','1','Z',...)
use ieee.numeric_std.all;        -- unsigned/signed numbers and + - < >

-- (2) ENTITY: the outside of the block (the symbol)
entity and_ff is
  port (
    clk : in  std_logic;
    a   : in  std_logic;
    b   : in  std_logic;
    q   : out std_logic
  );
end entity;

-- (3) ARCHITECTURE: the inside of the block (the drawing)
architecture rtl of and_ff is
  signal y : std_logic;           -- an internal wire
begin
  y <= a and b;                   -- the AND gate

  process(clk)                    -- the flip-flop
  begin
    if rising_edge(clk) then
      q <= y;
    end if;
  end process;
end architecture;
```

Drawn as a schematic it is exactly:

```
 a ──┐
     AND── y ──[D  Q]── q
 b ──┘          [>   ]
 clk ───────────[    ]
```

Notes on syntax:

* `--` starts a comment (until the end of the line).
* VHDL **does not care about upper/lower case**: `SIGNAL`, `signal`, `Signal`
  are the same, and so are `Clk` and `clk`. We write keywords in lowercase and
  constants in UPPERCASE as a habit.
* Every statement ends with `;`. Port lists separate items with `;`, but the
  **last port has no `;`** before the `)`. Port maps separate with `,`. (These
  two are the most common syntax errors; the compiler tells you the line.)
* `rtl` is just a name for the architecture (it means "register transfer
  level"). Any name works; we always use `rtl`.
* `end entity;` / `end architecture;` can also be written `end and_ff;` /
  `end rtl;`. Same meaning.

---

## 1.3 Types: what can travel on a wire

VHDL is strict about types: you can't connect an `integer` to a
`std_logic_vector` without converting, just like you couldn't plug a 4-bit
bus into a 1-bit pin. The types we use:

### `std_logic`: one wire

Values you'll meet:

| Value | Meaning |
|---|---|
| `'0'`, `'1'` | low, high (what real hardware has) |
| `'Z'` | high impedance: "I'm not driving this wire" (tri-state, used on `inout` pins) |
| `'U'` | uninitialised: only in simulation, a flip-flop that never got a value |
| `'X'` | conflict: two drivers fighting, or unknown. Seeing it in simulation = bug |
| `'H'`, `'L'` | weak 1 / weak 0 (a pull-up / pull-down resistor), only in testbenches |

Single characters use **single quotes**: `'1'`.

### `std_logic_vector(N downto 0)`: a bus

`std_logic_vector(7 downto 0)` is an 8-wire bus, bit 7 on the left (MSB),
bit 0 on the right (LSB). Values use **double quotes**: `"10100011"`, or hex:
`x"A3"` (each hex digit = 4 bits, so `x"A3"` is 8 bits and `x"F80"` is 12).

A `std_logic_vector` is **just wires**. It is not a number. You can't do
`+ 1` on it. For that you need:

### `unsigned` / `signed`: a bus that is also a number

From `ieee.numeric_std`. Same wires, but VHDL now knows to treat them as a
binary number, so `+`, `-`, `<`, `>=` work. `unsigned(9 downto 0)` holds
0..1023. We use `unsigned` for counters and the VGA x/y.

### `integer range A to B`: a number, the compiler picks the bits

`signal idx : integer range 0 to 15;` becomes a 4-bit register in hardware.
`integer range 0 to 49_999_999` becomes 26 bits. Always give a range,
otherwise the compiler makes it 32 bits. Underscores in numbers are allowed
for readability (`50_000_000`).

### `boolean`: true / false

What comparisons produce: `a = '1'` is a boolean. `if` needs a boolean.
You can't put a boolean on a wire directly, which is why you write
`y <= '1' when cnt = 5 else '0';`.

### Your own types

* **Enumeration** (a list of names), used for state machines:
  `type state_t is (S_IDLE, S_START, S_DATA, S_STOP);`
  The compiler picks the binary codes for you.
* **Array** (a list of same-type things), used for look-up tables (ROMs):
  `type palette_t is array (0 to 7) of std_logic_vector(11 downto 0);`
* **Subtype** (a nickname with limits):
  `subtype glyph_t is std_logic_vector(6 downto 0);`

### `character` / `string`

Text, for messages sent over the serial port: `"Hello"` is a string,
`'H'` is a character. `character'pos('A')` gives its ASCII code 65.
Careful: strings are numbered **from 1**, so `MSG(1)` is the first letter.

### Converting between types (the "adapter cables")

```
                    unsigned(v)                   to_integer(u)
 std_logic_vector  ─────────────►  unsigned  ─────────────────►  integer
                   ◄─────────────            ◄─────────────────
               std_logic_vector(u)            to_unsigned(i, N)
```

Examples from our code:

```vhdl
level := std_logic_vector(x(8 downto 5));        -- unsigned slice -> plain bits
sel   := to_integer(cnt(17 downto 16));           -- unsigned -> integer
tx_data <= std_logic_vector(to_unsigned(65, 8));  -- integer 65 -> "01000001"
```

None of these create any gates: they only change how the compiler *looks* at
the same wires. `to_unsigned(i, N)` needs `N` = how many bits.

---

## 1.4 Literals and aggregates (writing values)

```vhdl
'1'                    -- one bit
"0101"                 -- 4 bits
x"F80"                 -- 12 bits in hex
16#61#                 -- the INTEGER 97 written in hex (not a bus)
50_000_000             -- integer with separators
(others => '0')        -- "all bits zero", whatever the width
(others => '1')        -- all ones
```

`(others => '0')` is extremely common: it fills a bus of any width, so you
don't have to count bits. It's an *aggregate*. You can also mix:
`(0 => '1', others => '0')` = only bit 0 high.

---

## 1.5 Signals, constants, variables

```vhdl
architecture rtl of x is
  constant SIZE : integer := 32;                         -- fixed number, no hardware
  signal   cnt  : unsigned(7 downto 0) := (others => '0'); -- a wire or a register
begin
```

* **constant**: a name for a fixed value. No hardware: the compiler just
  pastes the value in. Use it so magic numbers have names (`CLKS_PER_BIT`
  instead of `434`).
* **signal**: a wire. If it is assigned inside a clocked process, it becomes
  the *output of a flip-flop* (a register). Declared between `architecture`
  and `begin`. The `:= value` at the end is the **power-up value**: on an
  FPGA, every flip-flop really is loaded with it when the `.bit` file is
  loaded. That's why our designs don't need a reset button.
* **variable**: only exists inside a process (or function). A scratch value
  used to break a long calculation into steps. Explained in 1.8.

Assignment symbols:

* `<=` assigns a **signal** ("connect / schedule").
* `:=` assigns a **variable**, and also gives initial values in declarations.

---

## 1.6 Concurrent statements (the "drawn on the sheet" part)

Everything between the architecture's `begin` and `end` is a list of
**concurrent statements**. Each one is a piece of hardware. Order doesn't
matter. There are only five kinds:

1. **Simple assignment**: a gate or a plain wire.
   `busy <= sending;` (just a wire) / `y <= a xor b;` (a gate)
2. **Conditional assignment** `when ... else`: a priority mux.
   ```vhdl
   tx <= frame(0) when sending = '1' else '1';
   ```
   ```
   frame(0) ──┤1
              MUX├── tx
   '1'     ───┤0
               │
   sending ────┘ (select)
   ```
3. **Selected assignment** `with ... select`: a normal N-to-1 mux / truth table.
   ```vhdl
   with sel select glyph <=
     d3 when "11",
     d2 when "10",
     d1 when "01",
     d0 when others;    -- 'others' = every remaining case (required)
   ```
4. **Process**: a block of logic described step-by-step (1.8).
5. **Instantiation**: placing another block (1.10).

(There's also `generate`, which copies hardware N times or includes it only
if a condition holds. We use it once, in a testbench.)

---

## 1.7 Combinational logic in a process

Sometimes a truth table or a big mux is easier to write as `if`/`case` than as
one long `when/else`. Then you use a process with **every input in its
sensitivity list**:

```vhdl
process(idx)                     -- "re-evaluate whenever idx changes"
begin
  if idx >= 15 then
    tens_g <= hex7(2);
  elsif idx >= 5 then
    tens_g <= hex7(1);
  else
    tens_g <= hex7(0);
  end if;
end process;
```

This makes *gates only*, no flip-flops. Two rules:

1. **Every signal read inside must be in the list** `process(a, b, c)`.
   (Synthesis ignores the list, but the simulator uses it; a missing one makes
   simulation disagree with the real board. VHDL-2008 allows `process(all)`,
   but the TA Builder uses VHDL-93, so we write the list out.)
2. **Every output must get a value in every path** through the `if`/`case`.
   If some path doesn't assign `tens_g`, the hardware must "remember" the old
   value: the compiler builds a **latch**, which is almost always a bug.
   Easy fix: give everything a default value at the top of the process, then
   override it below (our `pattern` process starts with `c := x"000";`).

---

## 1.8 Clocked processes = flip-flops (the most important section)

```vhdl
process(clk)
begin
  if rising_edge(clk) then
    q <= d;
  end if;
end process;
```

Read it as: "**at every rising edge of clk, q takes the value of d**". That is
the definition of a D flip-flop, so that's what the compiler builds. Every
signal assigned inside `if rising_edge(clk)` becomes a register. Only `clk` is
in the sensitivity list.

### A counter

```vhdl
process(clk)
begin
  if rising_edge(clk) then
    cnt <= cnt + 1;
  end if;
end process;
```

```
       ┌──────┐     ┌──────────┐
  ┌───►│ +1   ├────►│D   cnt  Q├──┬──► cnt
  │    └──────┘     │>         │  │
  │          clk ──►│          │  │
  │                 └──────────┘  │
  └───────────────────────────────┘
```

`cnt + 1` is an adder (combinational), `cnt <=` inside the clock edge is
the register. In Lab 6/7 you drew exactly this with T flip-flops or an
adder; here it's one line.

### `if` inside a clocked process = a mux in front of the D input

```vhdl
if rising_edge(clk) then
  if frame_tick = '1' then
    sq_x <= sq_x + 2;
  end if;
end if;
```

means: D input = `sq_x + 2` when `frame_tick = '1'`, otherwise D = `sq_x`
(keep the old value). In a clocked process, "not assigned in this path" means
**"keep the old value"**, which a flip-flop does naturally. (That's why
latches are only a problem in *combinational* processes.)

`frame_tick` here is an **enable**. That's how we make slow things (60 times a
second) without making a slow clock: the flip-flop still sees the 50 MHz
clock, it just only *changes* when the enable is `'1'`.

### The rule that confuses everyone: signals update at the END

Inside a process, `<=` on a signal does **not** change it immediately. All
signal assignments in the process are collected, and they all happen together
at the clock edge, when the process finishes. So:

```vhdl
if rising_edge(clk) then
  a <= b;
  b <= a;
end if;
```

**swaps** `a` and `b` every clock: both flip-flops load at the same moment,
each from the other's *old* value. In schematic terms it's obvious: two flip-
flops, each D wired to the other's Q. In software terms it looks wrong, which
is why the schematic view is the right way to think.

Same thing with `sync1 <= rx; rx_s <= sync1;`: that's two flip-flops in a
chain (a 2-stage synchronizer), **not** "rx_s gets rx".

### "Last assignment wins"

If the same signal is assigned twice in one pass, the later one counts:

```vhdl
tx_start <= '0';                 -- default: no pulse
...
if tx_busy = '0' and echo_pending = '1' then
  tx_start <= '1';               -- overrides the default on this clock only
end if;
```

This gives a **one-clock pulse**: `tx_start` is `'1'` only on the cycle
where the condition held, and back to `'0'` on the next. We use this pattern
everywhere for "do it once" signals (`pressed`, `valid`, `tick`, `start`).

### Variables (`:=`) inside a process

A variable changes **immediately**, like in software. It's a named piece of
the combinational logic, a way to write a long formula in several lines:

```vhdl
variable col : integer range 0 to 63;
...
col  := (xi - FIELD_X0) / 16;     -- intermediate result
base := PALETTE((col + row) mod 8);
```

Rule of thumb for us: use **variables only for intermediate calculations**
inside a process, and **signals for everything that's a real register or
connects to something else**.

---

## 1.9 Operators you'll see

| Operator | Works on | Meaning |
|---|---|---|
| `and or nand nor xor xnor not` | std_logic, vectors (bit by bit) | gates |
| `&` | bits, vectors | join into a wider bus |
| `= /=` | anything | equal / not equal (`/=` is "≠") |
| `< <= > >=` | unsigned, signed, integer | compare (`<=` here is "less or equal", context tells it apart from assignment) |
| `+ -` | unsigned, signed, integer | adder / subtractor |
| `* / mod` | integer, unsigned | multiply / divide / remainder. Only use `/` and `mod` by powers of 2 (free: just drops bits) or on constants. A real divider is huge and slow. |
| `shift_right(u, n)` / `shift_left` | unsigned | shift by n bits (free: just rewiring) |

---

## 1.10 Using one block inside another (hierarchy)

This is exactly what you do when you place a sub-schematic symbol.

```vhdl
u_btn : entity work.debounce
  generic map (STABLE_CYCLES => 1_000_000)
  port map (
    clk     => clk,         -- block's pin  =>  our wire
    btn_in  => btn_send,
    level   => open,        -- not used
    pressed => send_p
  );
```

* `u_btn` is the **instance name** (like `U1`, `U2` on a schematic). Each copy
  needs its own name: test 02 places three debouncers `u_prev`, `u_pause`,
  `u_next`, which is three separate copies of the hardware.
* `entity work.debounce` means "the entity called `debounce` from the
  library `work`". `work` is simply "all the files compiled into this project".
* `generic map` sets the block's parameters for this copy. If you leave it
  out, the defaults from the entity are used.
* `port map (pin => wire, ...)`: left side is the block's port name, right side
  is the signal in *this* architecture. `=>` reads "connects to".
* Every `in` port must be connected (or have a default). `out` ports you don't
  need can be `open`.

**VHDL-93 rule:** on the right side of `=>` only put a signal, a port or a
constant, **not a calculation** like `a and b` or `hex7(cnt)`. Make a signal
for it first:

```vhdl
signal g3 : glyph_t;
...
g3 <= hex7(std_logic_vector(rx_count(7 downto 4)));
u_seg : entity work.seg7_scan port map (..., d3 => g3, ...);
```

You will see this pattern in all our tops.

The older style you might see in Lab files is `component` declarations: the
Schematic Studio writes `component mux_4_1_4b ... end component;` and then
`u_0 : mux_4_1_4b port map (...)`. It means the same thing, just with more
typing. `entity work.x` (direct instantiation) needs no component declaration.

---

## 1.11 Generics: parameters for a block

```vhdl
entity uart_rx is
  generic (
    CLKS_PER_BIT : integer := 434       -- default value
  );
  port ( ... );
end entity;
```

Inside the architecture, `CLKS_PER_BIT` is a constant. Each instance can give
its own value. Generics are fixed when the design is built, so they cost no
hardware; they change *what* hardware gets built (e.g. how many bits a counter
needs). The testbench `tb_vga_frame` uses a generic `PATTERN` to choose which
picture to simulate.

---

## 1.12 Packages: shared constants and functions

A **package** is a file of shared things: constants, types, functions. It's
not hardware by itself. Our `common_pkg.vhd` holds the clock frequency, the
baud rate, the 7-segment glyph type and the `hex7` function.

Any file uses it with:

```vhdl
use work.common_pkg.all;     -- "make everything in common_pkg visible here"
```

A package has two halves:

* `package common_pkg is ... end package;`: the **declarations** (what exists,
  like a table of contents).
* `package body common_pkg is ... end package body;`: the **bodies** of the
  functions (how they work).

### Functions

```vhdl
function hex7(n : std_logic_vector(3 downto 0)) return glyph_t is
begin
  case n is
    when "0000" => return "0111111";
    ...
  end case;
end function;
```

A function is a reusable piece of **combinational logic**. Calling `hex7(x)`
in two places builds two copies of the decoder. Functions can't contain
flip-flops or remember anything. Two functions may share a name if their
inputs have different types (`hex7(vector)` and `hex7(integer)`); the
compiler picks by the argument (this is called *overloading*).

### Compile order

The compiler reads files one at a time. A file can only use things that were
compiled **before** it. So the package comes first, then the small blocks,
then the top that uses them. That's why `project.txt` lists
`common_pkg.vhd` first and the `top_*.vhd` last. (Vivado's GUI works the
order out by itself; `read_vhdl` in batch mode mostly does too, but keeping
the list in order avoids surprises.)

---

## 1.13 How the files of our project fit together

```
project.txt (03_uart_echo)            pins.xdc
  top=top_uart_echo                     clk     -> H11
  common_pkg.vhd   ─┐                   uart_rx -> G1
  uart_rx.vhd       │                   ...
  uart_tx.vhd       │ compiled
  debounce.vhd      │ in this order
  seg7_scan.vhd     │ into library
  top_uart_echo.vhd ┘ "work"

top_uart_echo   (the top: its ports are the FPGA pins, named in pins.xdc)
 ├── uses work.common_pkg  (CLKS_PER_BIT, hex7, glyph_t)
 ├── u_rx  : entity work.uart_rx    (generic CLKS_PER_BIT)
 ├── u_tx  : entity work.uart_tx
 ├── u_btn : entity work.debounce
 ├── u_seg : entity work.seg7_scan
 └── its own process: echo + message logic
```

* The **top** entity is the one whose ports are real pins. You tell the tools
  which one it is (`top=` in project.txt, or "Set as Top" in Vivado). All
  other entities are only used if the top (or something inside it) places
  them.
* The **xdc file** maps each top-level port to a package pin and a voltage.
  A port with no pin = build error; a pin line for a port that doesn't exist
  = a warning, ignored.
* The same `uart_rx.vhd` file is used by tests 03, 04, 05 and later the game.
  Fix a bug in it once, and every design that uses it gets the fix on the
  next build. This is the big advantage over copying schematics around.

---

## 1.14 Synthesizable vs. simulation-only

Some VHDL can't become hardware. It's only for testbenches (files that
pretend to be the outside world in the simulator):

| Simulation only | Why it can't be hardware |
|---|---|
| `wait for 10 ns;` / `after 10 ns` | an FPGA has no "wait 10 ns" gate; time comes from counting clocks |
| `wait until ...` in a process | same |
| `report "..."` / `assert` | prints text in the simulator |
| file reading/writing | the FPGA has no files |
| `'H'`, `'L'` | weak drivers, modelled in the testbench only |

A design for the board (synthesizable) uses: signals, ports, `<=`, `when`,
`with select`, `process(clk)` with `rising_edge`, combinational processes,
`if`, `case`, `for` loops with fixed bounds (copied N times, not looped in
time), functions, generics, instantiation.

---

## 1.15 Our house rules (and why)

1. **One clock (50 MHz) for everything.** Slow events (pixel steps, 1 second,
   60 frames per second) are one-clock **enable pulses**, not divided clocks.
   Your Lab 7 used a flip-flop output as the clock for the next flip-flop
   (ripple counter). That works in small labs but it's what forced the "hand
   edits" with BUFG in `lab7_handfixed_async.vhd`: Vivado can't time signals
   between clock domains it didn't expect. With one clock, Vivado checks every
   path and tells us (WNS) if anything is too slow.
2. **Every outside input goes through 2 flip-flops** (synchronizer) before
   use. A button or the serial wire can change at any instant; a flip-flop
   that samples right at that instant can go "half-way" (metastable) for a
   moment. The second flip-flop gives it a full clock to settle.
3. **VHDL-93 only**, because that's what the TA Builder compiles:
   * no `process(all)`: list the signals;
   * don't read an `out` port inside its own entity: use an internal signal
     and copy it to the port (`seg_n <= seg_r;`);
   * no calculations in a port map: make a signal.
4. **Outputs to pins come from flip-flops** where possible (`seg_r`, `dig_r`,
   the VGA `outreg`), so they switch cleanly once per clock.
5. **Every file starts with a comment block** explaining what it does. It's
   also the text for the design document.

---

## 1.16 Reading errors

The compiler stops at the first problem and gives file + line:

```
ERROR: [Synth 8-1031] dig_n is not declared [D:/setup/assignment/tests/02_j5_pin_finder/top_j5_finder.vhd:128]
```

Common ones:

| Message contains | Usually means |
|---|---|
| `is not declared` | typo, or the signal/port was renamed, or a missing `use work.common_pkg.all` |
| `near "end" ; expecting ...` / `syntax error` | a missing `;` on the line before, or an extra `;` after the last port |
| `type of ... is incompatible` / `can't determine type` | e.g. `unsigned` assigned to `std_logic_vector`: needs a conversion (1.3) |
| `has multiple drivers` | the same signal is assigned in two processes (two outputs shorted together!). Assign each signal in only one place |
| `formal port ... has no actual` | an `in` port in a port map was left unconnected |
| `cannot read from 'out' object` | VHDL-93 rule 3b above |
| `inferring latch` (warning) | a combinational process doesn't assign something in every path (1.7) |

---

## 1.17 Practise (do these with Part 4, Vivado)

1. In `top_j5_finder.vhd`, change the 1-second step to half a second. (Hint:
   the counter limit `CLK_HZ - 1` appears three times; put `CLK_HZ / 2` in a constant and use it everywhere.)
2. In `top_uart_echo.vhd`, change `upper()` so that it echoes lowercase
   instead.
3. Write a new tiny entity `blink` with `clk` in and `led` out that toggles
   `led` twice per second, using a counter and an internal signal (you can't
   read `led` itself, rule 3b). Simulate it in Vivado with a 3-line testbench
   (Part 4 shows how).

Next: [Part 2: the building blocks, line by line](02_blocks_walkthrough.md)
