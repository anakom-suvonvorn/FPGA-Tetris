# Part 2: The building blocks, line by line (`src/common/`)

These six files are the "parts library" every design uses. Open each file
next to this page. Line numbers (`L12`) refer to the file as it is now.
Skipped lines are comments or blank.

Order: [common_pkg](#21-common_pkgvhd) → [debounce](#22-debouncevhd) →
[seg7_scan](#23-seg7_scanvhd) → [vga_sync](#24-vga_syncvhd) →
[uart_tx](#25-uart_txvhd) → [uart_rx](#26-uart_rxvhd)

---

## 2.1 `common_pkg.vhd`

**What it is:** not hardware. A package of shared constants, a type and a
function. Every other file that says `use work.common_pkg.all;` can use them.

```vhdl
L10  library ieee;
L11  use ieee.std_logic_1164.all;
L12  use ieee.numeric_std.all;
```
Every file starts like this. `library ieee;` makes the IEEE standard library
available; the two `use` lines pull in `std_logic` / `std_logic_vector` and the
`unsigned` number type with its `+ - < >` and conversion functions.

```vhdl
L14  package common_pkg is
```
Start of the package **declaration** (the "table of contents").

```vhdl
L17  constant CLK_HZ : integer := 50_000_000;
```
The board's clock frequency as a named number. `constant name : type := value;`.
Used for "count to one second" (`CLK_HZ - 1`) and to compute the bit time.

```vhdl
L21  constant BAUD          : integer := 115_200;
L22  constant CLKS_PER_BIT  : integer := CLK_HZ / BAUD;   -- = 434
```
Serial speed. The division happens **when compiling** (both are constants),
so no divider hardware is built. Integer division drops the fraction:
50,000,000 / 115,200 = 434.03 → 434. The 0.007 % error is far below what
serial can tolerate (about 2 %).

```vhdl
L36  subtype glyph_t is std_logic_vector(6 downto 0);
```
A nickname: a "glyph" is a 7-bit bus, one bit per segment, bit 0 = a ...
bit 6 = g (the picture in L30–34 shows where a..g are). Using `glyph_t`
in port lists makes it clear what a signal means.

```vhdl
L38  constant SEG_BLANK : glyph_t := "0000000";
L39  constant SEG_DASH  : glyph_t := "1000000";   -- g only
L40  constant SEG_J     : glyph_t := "0011110";   -- b c d e
L41  constant SEG_P     : glyph_t := "1110011";   -- a b e f g
```
Fixed shapes. Read the string left to right as `g f e d c b a`.
`"1000000"`: only g (the middle bar) = a dash. `"0011110"`: e d c b = a "J".

```vhdl
L44  function hex7(n : std_logic_vector(3 downto 0)) return glyph_t;
L45  function hex7(n : integer) return glyph_t;
```
Promises that two functions called `hex7` exist (their code is in the body).
One takes 4 bits, the other an integer. The compiler picks by what you pass.

```vhdl
L47  end package common_pkg;
L50  package body common_pkg is
```
End of the declarations, start of the **body**, where function code lives.

```vhdl
L52  function hex7(n : std_logic_vector(3 downto 0)) return glyph_t is
L53  begin
L54    case n is
L55      when "0000" => return "0111111";  -- 0
...
L70      when others => return "1110001";  -- F
L71    end case;
L72  end function;
```
A 4-input, 7-output truth table: a hex-to-7-segment decoder, the same as the
`bcd_to_7_segment` block of your Lab 7 (which the Schematic Studio built from
separate `segment_a`, `segment_b`, ... gate networks). `case n is` checks
`n` against each `when`; `return` gives the output. `when others` covers
every value not listed. For 4 bits there's one left ("1111" = F), but VHDL
also requires `others` because a `std_logic` can be `'X'`, `'Z'`, etc.

Example: `"0111111"` = g off, f e d c b a on = the digit **0** (a ring
without the middle bar).

```vhdl
L74  function hex7(n : integer) return glyph_t is
L75  begin
L76    return hex7(std_logic_vector(to_unsigned(n mod 16, 4)));
L77  end function;
```
Convenience version: `hex7(5)` instead of `hex7("0101")`. It converts the
integer to 4 bits (`to_unsigned(value, bits)`), then to a plain bus
(`std_logic_vector(...)`), and calls the first version. `mod 16` keeps it
in 0..15.

```vhdl
L79  end package body common_pkg;
```

---

## 2.2 `debounce.vhd`

**What it is:** cleans one push button. Input: the raw pin. Outputs: a clean
level, and a one-clock pulse per press. Read the header comment L5–19: it
explains the three problems (asynchronous, bouncing, wanting one event).

As a schematic:

```
btn_in ─►[FF sync1]─►[FF sync2]─┬──────────────────────────► (compare)
                                │       ┌──────────────┐
                                └──────►│ = stable ?   │──► reset counter
                                        └──────────────┘
                         ┌─────────────────────────────┐
                         │ cnt (20-bit counter)        │──► reached 999,999?
                         └─────────────────────────────┘        │
                                                       load sync2 into [FF stable] ──► level
                                                       if it's a 0→1 change: [FF pulse] ──► pressed
```

```vhdl
L29 entity debounce is
L30   generic (
L31     STABLE_CYCLES : integer := 1_000_000      -- 20 ms at 50 MHz
L32   );
```
A parameter: how many clocks the input must stay unchanged. Default
1,000,000 clocks × 20 ns = 20 ms (button bounce lasts a few ms). A
testbench could set it to 10 to simulate faster.

```vhdl
L33   port (
L34     clk     : in  std_logic;
L35     btn_in  : in  std_logic;                   -- raw pin, '1' = pressed
L36     level   : out std_logic;
L37     pressed : out std_logic
L38   );
```
The block's 4 pins. Note: no `;` after the last one.

```vhdl
L42   signal sync1, sync2 : std_logic := '0';
L43   signal stable       : std_logic := '0';
L44   signal cnt          : integer range 0 to STABLE_CYCLES := 0;
L45   signal pulse        : std_logic := '0';
```
The internal wires, which all become flip-flops because they're assigned in
the clocked process. `:= '0'` is the power-up value. `cnt` has a range,
so the compiler makes it just wide enough (20 bits for 1,000,000).

```vhdl
L48   process(clk)
L49   begin
L50     if rising_edge(clk) then
```
Everything below happens at each rising clock edge → flip-flops.

```vhdl
L52       sync1 <= btn_in;
L53       sync2 <= sync1;
```
Two flip-flops in a chain: the **2-FF synchronizer**. Remember (Part 1,
1.8) both load at the same edge: `sync2` gets the *old* `sync1`. So `sync2`
is `btn_in` delayed by 2 clocks, and safe to use.

```vhdl
L56       pulse <= '0';
```
Default: no pulse. It gets overridden below on the one clock where a press is
accepted ("last assignment wins"), so `pressed` is high for exactly 1 clock.

```vhdl
L57       if sync2 = stable then
L58         cnt <= 0;                              -- no change, keep waiting
```
If the input agrees with what we already believe, there's nothing to do;
keep the counter at 0.

```vhdl
L59       elsif cnt = STABLE_CYCLES - 1 then
L60         stable <= sync2;                       -- held long enough: accept it
L61         cnt    <= 0;
L62         if sync2 = '1' then
L63           pulse <= '1';                        -- (3) 0 -> 1 means "pressed"
L64         end if;
```
The input has disagreed with `stable` for 1,000,000 clocks in a row: it's a
real change, not bounce. Accept it. If the new value is `'1'`, this was a
press → pulse.

```vhdl
L65       else
L66         cnt <= cnt + 1;
L67       end if;
```
Input disagrees, but not for long enough yet: count. If it bounces back, the
first branch resets `cnt` to 0, so a bounce restarts the wait.

```vhdl
L71   level   <= stable;
L72   pressed <= pulse;
```
Outside the process: plain wires from the internal registers to the out
ports. (We can't read `level`/`pressed` inside the block, VHDL-93 rule, which
is why they have internal twins `stable` and `pulse`.)

**Cost:** about 25 flip-flops and some LUTs per button. Test 02 uses three.

---

## 2.3 `seg7_scan.vhd`

**What it is:** the 4-digit display driver. Same circuit as the `display`
block of your Lab 7 (`D:\setup\lab7_handfixed_async.vhd`, line 1016),
rewritten:

| Lab 7 `display` | `seg7_scan` |
|---|---|
| two toggle FFs `n2_q`, `n18_q`, the second clocked by the first (ripple) | top 2 bits of an 18-bit counter, all on the one clock |
| switches digit every 2 clocks (25 MHz) | switches every 65,536 clocks (1.3 ms) |
| `mux_4_1_4b` picks the BCD digit, then `bcd_to_7_segment` | the caller passes ready-made glyphs (so it can show letters); a 7-bit 4-to-1 mux picks one |
| `n10_y0..y3`: 2-to-4 decoder, active-high | same decoder, active-high, plus a "blank" input |
| dp = `not n10_y2` (dot fixed on one digit) | each digit has its own dot input |
| outputs straight from gates | outputs from flip-flops |

**The bug this replaced:** the first version drove the digit enables
active-**low** (`'0'` = on). The board's enables are active-**high** (your
Lab 7 shows it). So 3 of the 4 digits were on at any moment, each showing the
glyph meant for another digit, which looks like "all segments lit".

```
                         ┌────────────────────────── cnt (18-bit counter) ─────────────────────┐
                         │ bits 17..16 = sel                 bits 15..12 = "0000"? → blank      │
                         └──────┬────────────────────────────────┬──────────────────────────────┘
d3 ─┤11                         │                                │
d2 ─┤10  4-to-1  glyph ──┐      │                                │
d1 ─┤01  mux ◄───────────┼── sel│                                ▼
d0 ─┤00                  │      └──► 2-to-4 decoder (enable = not blank) ──►[FF dig_r]──► dig(3..0)
                         └─► dot & glyph ──► NOT (8 inverters) ──►[FF seg_r]──► seg_n(7..0)
```

```vhdl
L39  entity seg7_scan is
L40    port (
L41      clk   : in  std_logic;
L42      d3    : in  std_logic_vector(6 downto 0);   -- leftmost digit glyph
...
L45      d0    : in  std_logic_vector(6 downto 0);   -- rightmost digit glyph
L46      dp    : in  std_logic_vector(3 downto 0);   -- decimal points, '1' = on
L47      seg_n : out std_logic_vector(7 downto 0);   -- '0' = segment lit
L48      dig   : out std_logic_vector(3 downto 0)    -- '1' = digit on
L49    );
```
Four 7-bit glyph inputs (use `hex7(...)` or `SEG_...` from the package),
four dot bits, 8 segment outputs, 4 digit-enable outputs. The `_n` suffix
is our habit for "active-low", so you can tell polarity from the name.

```vhdl
L56    signal cnt   : unsigned(17 downto 0) := (others => '0');
```
An 18-bit counter, `unsigned` so `+ 1` works. 2^18 = 262,144 clocks = 5.2 ms
for all 4 digits → each digit refreshes 190 times per second. No flicker.

```vhdl
L57    signal sel   : unsigned(1 downto 0);
L58    signal blank : std_logic;
L59    signal glyph : std_logic_vector(6 downto 0);
L60    signal dot   : std_logic;
```
Wires between the parts (combinational, not assigned in a clocked process →
no flip-flops). No initial value needed for those.

```vhdl
L64    signal seg_r : std_logic_vector(7 downto 0) := (others => '1');   -- all off
L65    signal dig_r : std_logic_vector(3 downto 0) := (others => '0');   -- all off
```
The output registers. Power-up values = everything off (segments high = off,
digits low = off).

```vhdl
L69    process(clk)
L70    begin
L71      if rising_edge(clk) then
L72        cnt <= cnt + 1;
L73      end if;
L74    end process;
```
The counter: adder + register. When it reaches all ones it wraps to 0 by
itself (an 18-bit adder simply overflows), so no "if cnt = max" is needed.

```vhdl
L76    sel   <= cnt(17 downto 16);
```
A bus tap: the top 2 wires of the counter. They change every 2^16 clocks,
going 00, 01, 10, 11, 00, ...: which digit's turn it is.

```vhdl
L77    blank <= '1' when cnt(15 downto 12) = "0000" else '0';
```
A 4-input NOR, written as a comparison. True for the first 4,096 of each
turn's 65,536 clocks (1/16). During that time all digits are off, so when
the segments switch to the next digit's glyph no digit shows the change
halfway (that would be "ghosting": a faint copy of one digit on its neighbour).

```vhdl
L80    with sel select glyph <=
L81      d3 when "11",
L82      d2 when "10",
L83      d1 when "01",
L84      d0 when others;
```
A 7-bit-wide 4-to-1 mux, `sel` as the select lines. `others` covers "00"
(and the non-0/1 values only a simulator knows about).

```vhdl
L86    with sel select dot <=
L87      dp(3) when "11",
...
```
Same mux, 1 bit wide, for the decimal point.

```vhdl
L93    process(clk)
L94    begin
L95      if rising_edge(clk) then
L97        if blank = '1' then
L98          dig_r <= "0000";
L99        else
L100         case sel is
L101           when "11"   => dig_r <= "1000";
L102           when "10"   => dig_r <= "0100";
L103           when "01"   => dig_r <= "0010";
L104           when others => dig_r <= "0001";
L105         end case;
L106       end if;
```
A 2-to-4 decoder with an enable (`not blank`), into a register. Exactly one
bit is `'1'` (one-hot), or none during blanking. `dig_r(3)` = leftmost digit
(pin H4), `dig_r(0)` = rightmost (H1).

```vhdl
L109       seg_r <= not (dot & glyph);
```
`dot & glyph` joins 1 + 7 bits into 8: bit 7 = dot, bits 6..0 = g..a.
`not` inverts all 8 (glyphs use '1' = on, the board wants '0' = on). Into the
register.

Note the timing: `sel` changes, and at that same clock edge both `dig_r` and
`seg_r` load values computed from the new `sel`, so digit and segments always
change together.

```vhdl
L113   seg_n <= seg_r;
L114   dig   <= dig_r;
```
Registers → output ports.

---

## 2.4 `vga_sync.vhd`

**What it is:** the VGA timing generator: two counters (x along the line,
y down the screen) and the sync pulses decoded from them. It's the heart of
test 01, which works perfectly on your monitor. Header L5–44 explains VGA; also
see `docs/concepts.md` §5.

```
     ┌─[FF half]◄─NOT─┐  (toggles: 1,0,1,0 → pix_en, a 25 MHz enable)
     └────────────────┘
                 ┌─────────────────────────────┐
  half ─(enable)►│ hc: 0..799 counter          │──► x ──► compare 656..751 ──► hsync
                 └──────────┬──────────────────┘
                            │ hc wraps (end of line) = enable for vc
                 ┌──────────▼──────────────────┐
                 │ vc: 0..524 counter          │──► y ──► compare 490..491 ──► vsync
                 └─────────────────────────────┘
       x < 640 and y < 480 ──► video_on
```

```vhdl
L50  entity vga_sync is
L51    port (
L52      clk        : in  std_logic;               -- 50 MHz
L53      pix_en     : out std_logic;
L54      x          : out unsigned(9 downto 0);
L55      y          : out unsigned(9 downto 0);
L56      video_on   : out std_logic;
L57      hsync      : out std_logic;
L58      vsync      : out std_logic;
L59      frame_tick : out std_logic
L60    );
```
x and y are `unsigned` ports (10 bits = 0..1023, enough for 799 and 524), so
the top can compare them with numbers directly.

```vhdl
L64    constant H_VISIBLE : integer := 640;
...
L71    constant V_TOTAL   : integer := 525;
```
The timing table from the header as named constants (back porches aren't
needed: they're whatever is left until the total).

```vhdl
L73    signal half : std_logic := '0';             -- toggles every clock
L74    signal hc   : unsigned(9 downto 0) := (others => '0');
L75    signal vc   : unsigned(9 downto 0) := (others => '0');
L76    signal tick : std_logic := '0';
```
Registers. `hc` = horizontal count, `vc` = vertical count.

```vhdl
L82        half <= not half;
```
A T flip-flop (D = not Q): 0,1,0,1,... It's `'1'` on every other clock,
the 25 MHz pixel **enable**. Not a clock! It's only used as a condition.

```vhdl
L83        tick <= '0';
```
Default for the one-clock pulse.

```vhdl
L85        if half = '1' then                      -- this is a pixel step
L86          if hc = H_TOTAL - 1 then
L87            hc <= (others => '0');
```
Only on pixel steps: if x is at the last position (799), go back to 0 (end of
line)...

```vhdl
L88            if vc = V_TOTAL - 1 then
L89              vc <= (others => '0');
L90            else
L91              vc <= vc + 1;
L92            end if;
```
...and move y one line down, wrapping 524 → 0 (end of frame). This is
two counters chained, the second enabled by the first's wrap, like cascading
two counter chips in a lab.

```vhdl
L93            if vc = V_VISIBLE - 1 then
L94              tick <= '1';                      -- last visible line just ended
L95            end if;
```
At the end of line 479 (the last visible one), pulse `tick`. The game updates
on this: the picture of the next frame isn't being drawn yet, so changing the
game state now can't tear the image.

```vhdl
L96          else
L97            hc <= hc + 1;
L98          end if;
```
Normal case: next pixel.

```vhdl
L103   pix_en     <= half;
L104   x          <= hc;
L105   y          <= vc;
L106   video_on   <= '1' when (hc < H_VISIBLE and vc < V_VISIBLE) else '0';
L107   hsync      <= '0' when (hc >= H_VISIBLE + H_FRONT and
L108                           hc <  H_VISIBLE + H_FRONT + H_SYNC) else '1';
L109   vsync      <= '0' when (vc >= V_VISIBLE + V_FRONT and
L110                           vc <  V_VISIBLE + V_FRONT + V_SYNC) else '1';
L111   frame_tick <= tick;
```
Combinational decoding of the counters (comparators + AND gates):

* `video_on`: inside the 640×480 area.
* `hsync` low for x = 656..751 (640+16 = 656, 656+96 = 752), active-low.
* `vsync` low for y = 490..491.

These come from gates, so the top registers them together with the colour
(see `outreg` in test 01) so they arrive at the pins on the same clock.

---

## 2.5 `uart_tx.vhd`

**What it is:** sends one byte as a serial frame: start bit `0`, 8 data bits
LSB first, stop bit `1`, each bit 434 clocks long. Header L5–22 has the
picture.

The trick: put all 10 bits in a shift register, output bit 0, and shift right
every 434 clocks.

```
data(7..0) ─┐
            ▼
 '1' & data & '0' ──load──►[ frame: 9 8 7 6 5 4 3 2 1 0 ]──► frame(0) ──┤1
                             shifts right, '1' enters at top               MUX ──► tx
                                                                    '1' ──┤0
                           baud_cnt 0..433 ─► at 433: shift, bit_idx+1      │
                           sending ─────────────────────────────────────────┘
```

```vhdl
L28 entity uart_tx is
L29   generic (
L30     CLKS_PER_BIT : integer := 434
L31   );
L32   port (
L33     clk   : in  std_logic;
L34     data  : in  std_logic_vector(7 downto 0);
L35     start : in  std_logic;
L36     tx    : out std_logic;
L37     busy  : out std_logic
L38   );
```
Give it a byte on `data`, pulse `start` for one clock, wait for `busy = '0'`.

```vhdl
L42   signal sending  : std_logic := '0';
L45   signal frame    : std_logic_vector(9 downto 0) := (others => '1');
L46   signal bit_idx  : integer range 0 to 9 := 0;
L47   signal baud_cnt : integer range 0 to CLKS_PER_BIT - 1 := 0;
```
`sending` = "a frame is going out". `frame` = the 10-bit shift register.
`bit_idx` = which of the 10 bits is on the wire. `baud_cnt` counts the
434 clocks of one bit. Note the range uses the generic: change the speed and
the counter width adapts.

```vhdl
L53       if sending = '0' then
L54         if start = '1' then
L55           frame    <= '1' & data & '0';       -- stop, data, start
L56           bit_idx  <= 0;
L57           baud_cnt <= 0;
L58           sending  <= '1';
L59         end if;
```
Idle and asked to send: load the shift register. `'1' & data & '0'` is
10 bits: bit 9 = stop (`'1'`), bits 8..1 = data, bit 0 = start (`'0'`). Since
we output bit 0 first, the order on the wire is start, data(0), data(1), ...,
data(7), stop: LSB first, as the standard says.

```vhdl
L60       else
L61         if baud_cnt = CLKS_PER_BIT - 1 then   -- current bit has lasted long enough
L62           baud_cnt <= 0;
L63           if bit_idx = 9 then
L64             sending <= '0';                   -- stop bit done
L65             frame   <= (others => '1');
L66           else
L67             bit_idx <= bit_idx + 1;
L68             frame   <= '1' & frame(9 downto 1);   -- next bit to position 0
L69           end if;
L70         else
L71           baud_cnt <= baud_cnt + 1;
L72         end if;
L73       end if;
```
While sending: count 434 clocks. At the end of each bit, either finish (after
bit 9, the stop bit), or shift right: `frame(9 downto 1)` is the top 9 bits,
with `'1'` added at the top: 10 bits again, everything moved one place
toward bit 0. A shift register is just wires going one place over into the
next flip-flop, no gates at all.

```vhdl
L77   tx   <= frame(0) when sending = '1' else '1';
L78   busy <= sending;
```
The wire: the current bit while sending, else idle high. `busy` is just
`sending`.

**Timing detail used by the tops:** `busy` rises one clock *after* `start`
(the register needs the clock edge). So the caller must not pulse `start`
again in the very next clock. Our tops check `tx_busy = '0' and tx_start = '0'`.

---

## 2.6 `uart_rx.vhd`

**What it is:** the opposite: watches the wire, finds the start bit, samples
the 8 data bits in the middle of each bit, checks the stop bit, outputs the
byte with a one-clock `valid` pulse. A **state machine** with 4 states.

```
            rx_s='0'               half bit, still '0'        8 bits sampled
  ┌────────┐ ───────► ┌─────────┐ ──────────────────► ┌────────┐ ─────────► ┌────────┐
  │ S_IDLE │          │ S_START │                     │ S_DATA │            │ S_STOP │
  └────────┘ ◄─────── └─────────┘                     └────────┘            └───┬────┘
      ▲      was '1' again: glitch                                              │
      └─────────────── after one bit time (valid pulse if the wire is '1') ─────┘
```

```vhdl
L23 entity uart_rx is
L24   generic (
L25     CLKS_PER_BIT : integer := 434
L26   );
L27   port (
L28     clk   : in  std_logic;
L29     rx    : in  std_logic;
L30     data  : out std_logic_vector(7 downto 0);
L31     valid : out std_logic                     -- one-clock pulse per good byte
L32   );
```

```vhdl
L36   type state_t is (S_IDLE, S_START, S_DATA, S_STOP);
L37   signal state    : state_t := S_IDLE;
```
An enumeration type with our 4 state names, and the state register. Vivado
chooses the encoding (it reports it in the log: often one-hot = 4 FFs).
This is the VHDL version of the state diagrams + state tables you did by
hand: you don't encode the states or derive next-state equations. You write
the transitions and the tool builds the logic.

```vhdl
L38   signal sync1    : std_logic := '1';
L39   signal rx_s     : std_logic := '1';
```
The 2-FF synchronizer for the incoming wire. Initial `'1'` = the idle level,
so no false start bit at power-up.

```vhdl
L40   signal cnt      : integer range 0 to CLKS_PER_BIT - 1 := 0;
L41   signal bit_idx  : integer range 0 to 7 := 0;
L42   signal shreg    : std_logic_vector(7 downto 0) := (others => '0');
L43   signal data_r   : std_logic_vector(7 downto 0) := (others => '0');
L44   signal valid_r  : std_logic := '0';
```
Bit-time counter, which data bit we're on, the shift register collecting
bits, and the output registers.

```vhdl
L50       sync1 <= rx;
L51       rx_s  <= sync1;
L52       valid_r <= '0';
```
Synchronizer, and the default for the one-clock pulse.

```vhdl
L54       case state is
L55         when S_IDLE =>
L56           cnt <= 0;
L57           if rx_s = '0' then
L58             state <= S_START;
L59           end if;
```
`case state is` = "depending on the current state". In IDLE: wait for the wire
to go low (the start bit's falling edge).

```vhdl
L61         when S_START =>
L62           if cnt = CLKS_PER_BIT / 2 - 1 then
L63             cnt <= 0;
L64             if rx_s = '0' then
L65               bit_idx <= 0;
L66               state   <= S_DATA;
L67             else
L68               state   <= S_IDLE;              -- just a glitch
L69             end if;
L70           else
L71             cnt <= cnt + 1;
L72           end if;
```
Wait half a bit (217 clocks) to reach the **middle** of the start bit. Still
low? It's a real start bit. Back to high? It was a spike; ignore it.

```vhdl
L74         when S_DATA =>
L75           if cnt = CLKS_PER_BIT - 1 then
L76             cnt   <= 0;
L77             shreg <= rx_s & shreg(7 downto 1);
L78             if bit_idx = 7 then
L79               state <= S_STOP;
L80             else
L81               bit_idx <= bit_idx + 1;
L82             end if;
L83           else
L84             cnt <= cnt + 1;
L85           end if;
```
From the middle of the start bit, every full bit time lands in the middle of
the next bit. Sample it: `rx_s & shreg(7 downto 1)` puts the new bit at the
**top** and moves the rest down. After 8 bits, the first bit (the LSB) has
moved all the way to bit 0, so the byte is in the right order. After bit 7, go
check the stop bit.

```vhdl
L87         when S_STOP =>
L88           if cnt = CLKS_PER_BIT - 1 then
L89             cnt <= 0;
L90             if rx_s = '1' then
L91               data_r  <= shreg;
L92               valid_r <= '1';
L93             end if;
L94             state <= S_IDLE;
L95           else
L96             cnt <= cnt + 1;
L97           end if;
L98       end case;
```
Middle of the stop bit: must be `'1'`. If so, publish the byte and pulse
`valid`. If not (wrong speed, noise), drop it silently. Either way, back to
IDLE.

```vhdl
L102   data  <= data_r;
L103   valid <= valid_r;
```

**Why test 03 could fail even though this block passes simulation:** the
simulation proves the *logic*. It can't prove that the FPGA pin we named is
the one the USB chip is really wired to. That's what test 05 checks on the
board.

Next: [Part 3: the test designs and testbenches](03_tests_walkthrough.md)
