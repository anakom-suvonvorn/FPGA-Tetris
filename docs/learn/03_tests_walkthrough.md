# Part 3: The test designs and testbenches, line by line

Each test is a **top**: the entity whose ports are real FPGA pins. Tops
mostly *place and wire* the blocks from Part 2, plus a little logic of their
own. Read Part 2 first.

Contents: [project.txt and pins.xdc](#30-the-two-text-files-every-design-has) ·
[01 VGA](#31-test-01-top_vga_barsvhd) · [02 J5 finder](#32-test-02-top_j5_findervhd) ·
[03 UART echo](#33-test-03-top_uart_echovhd) · [04 board link](#34-test-04-top_board_linkvhd) ·
[05 UART probe](#35-test-05-top_uart_probevhd) · [testbenches](#36-testbenches)

---

## 3.0 The two text files every design has

### `project.txt`

```
top=top_uart_echo
src/common/common_pkg.vhd
src/common/uart_rx.vhd
...
tests/03_uart_echo/top_uart_echo.vhd
```

Our own format (not a Vivado thing): which entity is the top, then the files
in compile order. `tools\build.bat`, `tools\vivado_gui.bat` and
`tools\load_into_builder.bat` all read it, so it's the one place to add a
file to a design.

### `pins.xdc`

XDC = Xilinx Design Constraints. Tcl commands that Vivado runs after reading
the VHDL:

```tcl
set_property -dict { PACKAGE_PIN H11  IOSTANDARD LVCMOS33 } [get_ports {clk}]
```

* `get_ports {clk}`: find the top-level port named `clk`.
* `PACKAGE_PIN H11`: connect it to ball H11 of the chip (the 50 MHz oscillator).
* `IOSTANDARD LVCMOS33`: 3.3 V logic levels (everything on this board).
* Bus ports use one line per bit: `{seg_n[0]}`, `{seg_n[1]}`, ... (square
  brackets in XDC, round in VHDL).
* Extra properties go in the same `{ }`: `PULLUP true` adds a weak pull-up
  resistor inside the FPGA.

```tcl
create_clock -name sys_clk -period 20.000 [get_ports {clk}]
```

Tells Vivado: this port is a clock with a 20 ns period (50 MHz). Without it
Vivado doesn't know how fast the flip-flops must work and can't check timing
(no meaningful WNS).

```tcl
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
```

Tells Vivado how the board powers the configuration pins. Without these two
lines it prints a warning on every build. Same in every design.

---

## 3.1 Test 01: `top_vga_bars.vhd`

**Works on your monitor.** Structure (L17–22): `vga_sync` + a picture
generator + a bouncing-square mover + an output register.

```
             ┌──────────┐ x, y, video_on, hs, vs
  clk ──────►│ vga_sync │──────────────┬────────────────────────────┐
             └──────────┘ frame_tick   │                            │
                               │       ▼                            ▼
  sw ─►[2FF]─► sw_s ───────────┼──► pattern (combinational) ─rgb─► outreg (FFs) ─► vga_r/g/b, hs, vs
                               ▼       ▲
                        bounce (FFs) ─ sq_x, sq_y
```

**Ports (L28–38):** `sw(1 downto 0)` from two slide switches; 4 bits each of
red, green, blue (the board turns 4 bits into a voltage with resistors, so
16 levels per colour, 4,096 colours); the two sync wires.

**L42–46:** wires coming out of `vga_sync`.

**L49** `rgb`: the colour of the current pixel as one 12-bit bus `RRRRGGGGBBBB`,
so one hex digit per colour: `x"F80"` = red 15, green 8, blue 0 = orange.

**L52** `sw_s1, sw_s`: the 2-FF synchronizer for the switches.

**L55–59:** the square: size constant, position registers starting at
(100, 60), and two direction bits.

**L62–65:** where the Tetris field sits on screen: x 240..399 (10 cells ×
16 px), y 80..399 (20 cells × 16 px). Centred: (640 − 160) / 2 = 240.

**L68–78:** `PALETTE`, a ROM: an array type of 8 entries × 12 bits, and a
constant of that type. Indexing it with a signal (`PALETTE(i)`) builds an
8-to-1 mux. The game will use the same table for piece colours.

**L82–101:** two functions on colours. `lighten` moves each 4-bit colour
halfway to 15: `v + (15 − v)/2`. `darken` halves it: `shift_right(v, 1)`.
The `for i in 0 to 2 loop` doesn't loop in time: the compiler **copies the
body 3 times** (red, green, blue), with `4*i+3 downto 4*i` picking bits
11..8, 7..4, 3..0.

**L108–118:** placing `vga_sync`. Every port wired to a local signal of the
same meaning.

**L123–144, process `bounce`** (clocked):

* L126–127: synchronizer.
* L129: everything else only happens on `frame_tick`, 60 times per second.
* L131–135: if moving right (`sq_dx_neg = '0'`) and about to hit the right
  edge (`640 − 32 − 2`), flip direction; else move 2 px. Mirror for moving
  left. L137–141: same for y. Each `if` here builds a comparator and a mux in
  front of the register's D input.

**L149–229, process `pattern`** (combinational, lists everything it reads:
`x, y, sw_s, sq_x, sq_y`):

* L150–155: variables: intermediate results of the formula, not registers.
* L157–159: integers of x and y for easy comparisons; default colour black
  (avoids latches, Part 1 §1.7).
* L161: `case sw_s is`: choose the picture by the switches. Each `when`
  branch computes `c`.
* L163–172: colour bars: compare x with 80, 160, ... (8 bars of 80 px).
* L178–188: ramps: `x(8 downto 5)` is "x divided by 32" for free (just the
  wires for bits 8..5), giving 16 steps over 512 px. `level & "0000" & "0000"`
  puts it in the red position.
* L191–213: Tetris grid. Inside the field: `col = (x − 240) / 16`. Dividing by
  16 is free (drop 4 bits); `px = x(3 downto 0)` is the position inside the
  cell. Colour from the palette, lightened on the top/left edge, darkened on
  the bottom/right: the 3D bevel. Around the field, a 4 px grey frame.
* L216–220: square: is (x, y) inside the 32×32 box at (sq_x, sq_y)?
  Four comparators and an AND.
* L224–226: white border, checked last so it wins.
* L228: drive the signal `rgb` from the variable.

**L235–250, process `outreg`** (clocked): copies colour and both syncs into
flip-flops on the same edge, so they reach the pins together. Outside the
visible area the colour is forced to black: monitors use the black level
during blanking to calibrate.

**Why the whole design works without a 25 MHz clock:** `x`, `y` only change
every other clock (pix_en), so `outreg` simply outputs the same pixel twice.

---

## 3.2 Test 02: `top_j5_finder.vhd`

Drives one J5 header pin high at a time and shows its number. The header
comment (L1–36) explains how to measure.

**L43–53, ports:** three buttons, the 16 header pins as a bus (`j5(0)` = pin
5 ... `j5(15)` = pin 20), and the display.

**L56–63:**
* `prev_p, pause_p, next_p`: one-clock press pulses from the debouncers.
* `idx`: which of the 16 lines is high (0..15 → 4-bit register).
* `running`: auto-advance on/off. Starts `'1'`.
* `sec_cnt`: counts to 49,999,999 (1 second), 26 bits.
* `j5_r`: register for the 16 outputs.
* `tens_g, ones_g`: the two number glyphs; `FIVE_G`: the constant glyph "5"
  (a constant because port maps can't contain function calls in VHDL-93).
* `dots`: the 4 decimal points.

**L67–69:** three copies of `debounce` (three separate pieces of hardware),
`level` unused (`open`).

**L71–97, the clocked process:**
* L75–79: free-running 1-second counter.
* L81–83: each press of PAUSE flips `running` (a T flip-flop with an enable).
* L85–91: NEXT, or one second passing while running: `idx + 1`, wrapping
  15 → 0; PREV: `idx − 1`, wrapping 0 → 15. Pressing a button also restarts
  the 1-second count (L87, L90), so the display doesn't jump right after a
  press. Note the `elsif`: NEXT wins if both happen in the same clock.
* L94–95: `j5_r <= (others => '0'); j5_r(idx) <= '1';`: all zero, then one
  bit set (last assignment wins). Hardware: a 4-to-16 decoder into 16 FFs.

**L99:** register → port.

**L102–113, combinational process:** pin number = `idx + 5`, split into tens
and ones (05..20) with comparisons instead of a divider.

**L118:** `"010" & (not running)` = dot on digit 2 (after the "5": `J5.07`)
and on digit 0 while paused.

**L120–130:** the display, showing `J`, `5`, tens, ones.

---

## 3.3 Test 03: `top_uart_echo.vhd`

Talks to PuTTY: echoes typed characters in capitals, PB3 sends a message, the
display shows the byte count and the last byte. Didn't answer on your PC; test
05 finds out why.

**L33–42, ports:** `uart_rx` (F2, from the PC), `uart_tx` (G1, to the PC), a
button, the display.

**L45** `constant MSG : string := "Hello from the FPGA!";`: a string constant.
The synthesizer turns it into a small ROM.

**L47–58:** wires to/from the receiver and transmitter, the button pulse,
counters and glyphs.

**L61–67:** a tiny "to do" list for the transmitter: `echo_pending` (an echo
waits), `lf_pending` (a line feed waits), `msg_active` + `msg_pos` (sending
the message, which character next).

**L69–72, function `to_byte`:** character → 8 bits (`character'pos` = ASCII
code).

**L75–82, function `upper`:** if the byte is between `0x61` ('a') and
`0x7A` ('z'), subtract 32 (lowercase and uppercase ASCII differ by exactly
32). `16#61#` is the integer 0x61.

**L86–95:** receiver, transmitter, debouncer placed. Note the generic map
passes `CLKS_PER_BIT` from the package.

**L97–148, the clocked process:** three independent jobs in one process:

1. **L103–111, a byte arrived** (`rx_valid` pulse): count it, remember it,
   queue its uppercase echo. If it's Enter (CR, `0x0D`), also queue a line
   feed so the cursor goes to a new line.
2. **L114–117, button:** start the message, unless already sending it.
3. **L122–146, feed the transmitter** when it's free. Priority order: echo,
   then LF, then the next message character. `MSG(msg_pos + 1)` because VHDL
   strings start at index 1. After the last character, CR then LF, then
   `msg_active <= '0'`.

   The check `tx_start = '0'` (L122) matters: `tx_busy` only goes high one
   clock *after* `start`, so without it we'd fire a second start straight
   away and lose a byte.

**L151–154:** glyphs: count in hex on the left, last byte on the right.
**L156–166:** display.

---

## 3.4 Test 04: `top_board_link.vhd`

Both boards run this. Each sends its 8 switches every 50 ms on J5 pin 5 and
shows what it receives on J5 pin 6.

**L46–47:** periods as constants computed from `CLK_HZ` (50 ms = 2,500,000
clocks, 250 ms = 12,500,000).

**L49–60:** synchronizer for the switches, send timer, receiver outputs, last
value received, `silence` counter (how long since the last byte), `link_ok`.

**L63–69:** transmitter sends `sw_s` (the switch value) directly; receiver.

**L71–96, clocked process:**
* L79–86: every 50 ms, pulse `tx_start` if the transmitter is free.
* L89–94: on each received byte, store it and reset `silence`; otherwise
  count up to `TIMEOUT` and stop there (it saturates, never wraps).

**L98:** `link_ok` = a byte came within the last 250 ms.

**L100–103:** left = own switches; right = received value, or `--`
(`SEG_DASH`) when the link is down. `when ... else` = a 2-to-1 mux on 7 bits.

This "heartbeat + timeout" idea will tell the game that the other player's
cable fell out.

---

## 3.5 Test 05: `top_uart_probe.vhd`

New, to debug test 03. Read its header (L1–30) and its README.

**New VHDL idea: `inout` ports and `'Z'`.**

```vhdl
pin_f2 : inout std_logic;
...
pin_g1 <= tx_line when tx_on_g1 = '1' else 'Z';
pin_f2 <= tx_line when tx_on_f2 = '1' else 'Z';
```

As a schematic, each pin has a **tri-state buffer**: when enabled it drives
`tx_line`, when disabled (`'Z'`) it lets go of the wire, and the pin is a
plain input. Both receivers always listen (`rx => pin_f2`: reading an inout
port is allowed).

```
                       tx_on_g1
                          │
 tx_line ─────────────────▷──────┬───── pin G1 ───── USB chip
                                 └──► uart_rx (u_rx_g1) ─► rxg_valid

 tx_line ─────────────────▷──────┬───── pin F2 ───── USB chip
                          │      └──► uart_rx (u_rx_f2) ─► rxf_valid
                       tx_on_f2
```

**L49–51:** two messages of equal length, one per wiring possibility.

**L56–57:** `tx_on_g1`, `tx_on_f2`: both `'0'` at power-up, so both pins are
inputs. Only one ever becomes `'1'`.

**Clocked process, step 1 (L128–146):** a byte on F2 (and we don't transmit
on F2) → count it; if no direction was chosen yet, choose "transmit on G1".
Mirror for G1. So the first key you type decides the direction, and the FPGA
never drives the pin the PC drives.

**Steps 2–4 (L148–203):** the same echo / message logic as test 03, plus a 3-second
timer that requests the status line, and the transmitter only runs once a
direction is known.

**Display:** left = bytes on F2, right = bytes on G1; leftmost dot = TX on
G1, rightmost dot = TX on F2.

**`PULLUP true`** in `pins.xdc`: without it, a pin nobody drives floats and
noise could look like a byte, picking the wrong direction.

---

## 3.6 Testbenches

A testbench is an entity with **no ports**. Inside, it places the design
(the "DUT", device under test), makes a clock, drives inputs and checks
outputs. It uses simulation-only VHDL (`wait`, `after`, `report`).

### `sim/tb_uart_loop.vhd`

* `clk <= not clk after 10 ns when not done else clk;`: an inverter feeding
  itself with a 10 ns delay = a 50 MHz square wave. When `done` is true the
  clock stops and the simulator ends (no more events).
* Places `uart_tx` and `uart_rx` with the tx output wired straight to the rx
  input.
* `stim` process: for each test byte: wait for a clock edge, put the byte on
  `tx_data`, pulse `tx_start`, wait for `tx_busy = '0'`. In a testbench,
  `wait until` really waits in simulated time.
* `check` process: waits for each `rx_valid`, compares, `report`s. Prints
  `TEST PASSED` if every byte matched.

### `sim/tb_vga_frame.vhd`

* Places the whole `top_vga_bars`; `PATTERN` generic sets the switches.
* `timing` process measures with `now` (current simulated time): hsync low =
  192 clocks, line = 1600, vsync low = 3200, frame = 840,000.
* `capture` process behaves like a monitor: counts hsync pulses after vsync
  to find line 0, waits 288 clocks to the first visible pixel, samples R,G,B
  640 times (every 2 clocks), and writes a `.ppm` text image with
  `std.textio` (file writing works only in simulation).

### `sim/tb_uart_probe.vhd`

* Generic `PATTERN`: 0 = the PC's chip wired as in the manual, 1 = swapped.
* `if PATTERN = 0 generate ... end generate;`: wires the pretend PC to F2 or
  G1 depending on the generic (`generate` = include this hardware only if...).
* The undriven pin gets `'H'` (a weak 1, like a pull-up); `to_x01()` turns
  `'H'` into `'1'` for the receiver.
* Sends `'a'`, expects `'A'` (echo) then `'F'` (start of the status line).
* `guard` process: if a pin ever resolves to `'X'`, both sides are driving it,
  which is the conflict the design must avoid.

Next: [Part 4: Vivado](04_vivado.md)
