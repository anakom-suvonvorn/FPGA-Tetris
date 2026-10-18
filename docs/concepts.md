# How it all works

This explains every idea used in the test designs, from the ground up. Read
it once now; come back to the relevant section when something on the board
doesn't behave.

Contents:

1. From VHDL to a running board
2. One clock, many "enable pulses"
3. Outside signals: synchronising and debouncing
4. The 7-segment display
5. VGA: how a picture gets onto a monitor
6. Serial (UART): sending bytes over one wire
7. "Serial echo to the PC": what test 03 actually does
8. Connectors, and what "J5" means
9. Connecting two boards
10. Simulation and testbenches
11. Timing: what WNS means
12. VHDL-93 rules for the TA's Builder

---

## 1. From VHDL to a running board

```
 your .vhd files + pins.xdc
          |
          v
   [ synthesis ]        Vivado turns VHDL into a netlist: LUTs (tiny truth
          |             tables) and flip-flops, like gates in Logisim
          v
   [ place & route ]    picks real locations on the chip for each LUT/FF and
          |             wires them together; pins.xdc fixes which ports go
          v             to which package pins (H11, B6, ...)
   [ bitstream ]        the .bit file: the chip's whole configuration
          |
          v
   [ program ]          openFPGALoader sends it down the USB cable (JTAG)
                        * "Normal Rom" / program.bat: into the FPGA itself,
                          lost when power is removed or SW1 pressed
                        * "PROM Rom" / program.bat ... flash: into the 8 MB
                          flash chip; the FPGA reloads it at every power-on
```

The TA's FPGA Builder does exactly these steps with a hidden copy of Vivado.
`tools\build.bat` does the same with the full Vivado and also writes the
timing and size reports.

## 2. One clock, many "enable pulses"

The board has one 50 MHz oscillator (pin H11). Everything we build is
clocked by it: every flip-flop in every file says `if rising_edge(clk)`.

Many things need to happen *slower*: VGA pixels at 25 MHz, the game 60 times
a second, the pin finder once a second. In the labs we made slow clocks with
counters (dividers) and fed those into flip-flop clock inputs. In a design
this size that causes trouble: each divided clock is a separate clock
domain, Vivado can't check timing between them, and signals crossing from
one to another can be caught mid-change. (The TA's Builder even switches off
the check that would normally warn about it.)

So instead we keep *one* clock and make **enable pulses**: a signal that is
`'1'` for exactly one 50 MHz cycle, every N cycles:

```
clk        _-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
pix_en     _--__--__--__--__--__--__--__-   '1' every 2nd cycle  (25 MHz rate)
frame_tick ____________--________________   '1' once per frame   (60 Hz rate)
```

and the slow logic only acts when the pulse is high:

```vhdl
if rising_edge(clk) then
  if frame_tick = '1' then      -- happens 60 times a second
    sq_x <= sq_x + 2;
  end if;
end if;
```

Same result as a slow clock, but everything stays in one clock domain, and
Vivado's timing check covers the whole design.

## 3. Outside signals: synchronising and debouncing

Buttons, switches and the serial rx wire change whenever *they* want, not in
step with our clock. If a flip-flop samples a signal at the exact moment it
changes, the flip-flop can hang half-way between 0 and 1 for a moment
("metastability") and different parts of the circuit can see different
values. The standard fix is a **2-flip-flop synchroniser**:

```
button --> [FF] --> [FF] --> safe to use
   (sync1)  (sync2)
```

The first FF may wobble, but it has a whole clock cycle to settle before the
second one copies it. Every outside input in our designs goes through this
(`debounce.vhd`, `uart_rx.vhd`, and the switch registers in the tests).

Buttons also **bounce**: for a few milliseconds the contacts make and break
many times. `debounce.vhd` only believes a new button level after it has held
steady for 20 ms (1,000,000 clocks), and then outputs a single one-clock
`pressed` pulse. That is why one press always moves the pin finder exactly one
step.

## 4. The 7-segment display

Four digits, but only 8 shared segment wires (a–g + dot) and 4 digit-enable
wires. `seg7_scan.vhd` lights one digit at a time, cycling through all four
about 190 times a second; persistence of vision makes it look steady.

Polarity on this board (checked against our working Lab 7):

* segment wires a–g, dp: **active-low** (`'0'` lights the segment; the display
  is common anode);
* digit enables H1–H4: **active-high** (`'1'` switches the digit on).

The first version of `seg7_scan` had the digit enables active-low too, so
three digits were on at once, each showing a mix of the others' glyphs:
almost every segment looked lit. Glyphs are stored active-high (`'1'` =
segment on) in `common_pkg.vhd`, which is easier to read; the module inverts
them at the very end.

Jumper **J9** connects LEDs D10–D17 to the same wires as the segments. Remove
it, or those LEDs flicker along with the display.

## 5. VGA: how a picture gets onto a monitor

The monitor draws the picture like reading a book: one horizontal line left
to right, then the next line, top to bottom, 60 times per second. We don't send
it pixel addresses. We just put the colour of the *current* pixel on the
R, G, B wires at the right moment and send two timing pulses:

* **HSYNC**: "line finished, go back to the left" (once per line)
* **VSYNC**: "frame finished, go back to the top" (once per frame)

640×480 at 60 Hz uses a 25 MHz pixel rate, and each line and frame includes
invisible time (porches and sync), left over from CRT tubes:

```
             one line = 800 pixel times
 |<----------- 640 visible ----------->|16|<-96->|48|
 |  colour data                         |FP| sync |BP|
 hsync ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|______|‾‾‾

             one frame = 525 lines
 480 visible lines, 10 front porch, 2 sync, 33 back porch
```

`vga_sync.vhd` is two counters: `x` counts 0..799 (one step per pixel), `y`
counts 0..524 (one step per line). Everything else is comparisons:

* `video_on = (x < 640) and (y < 480)`
* `hsync = '0'` while `656 <= x < 752`
* `vsync = '0'` while `490 <= y < 492`

The top level decides the colour for (x, y) with plain combinational logic
(`if x < 80 then white ...`) and registers colour + hsync + vsync together on
the same clock edge so they stay lined up. Outside the visible area the colour
**must** be black, or many monitors refuse to sync.

The board's VGA connector has a 4-bit resistor ladder per colour (12 bits,
4,096 colours): `RED0..RED3` on pins B6 D3 C3 A4, etc. Picture 1 of test 01
(the brightness ramps) checks the bit order: each ramp should get smoothly
brighter in 16 steps.

**Why Tetris fits:** we never store the picture. Picture 2 of test 01 draws
the 10×20 field purely from (x, y): with 16-pixel cells, the cell column is
just `(x - 240) / 16`, which is "drop the lowest 4 bits", and the position
inside the cell is `x(3 downto 0)`. The game will only store the 10×20 grid of
cell colours (600 bits) and the renderer looks up the colour of whatever cell
(x, y) is in.

## 6. Serial (UART): sending bytes over one wire

A UART sends bytes one bit at a time on a single wire, with no clock wire.
Both ends agree on the speed in advance: **115,200 bits per second**, so one
bit lasts 50,000,000 / 115,200 ≈ **434 clock cycles**.

```
wire idle = 1
  ‾‾‾‾‾‾‾|___|b0 |b1 |b2 |b3 |b4 |b5 |b6 |b7 |‾‾‾|‾‾‾‾‾ idle
         start  data bits, lowest first      stop
          (0)                                (1)
```

* **uart_tx.vhd** loads `stop & data & start` into a 10-bit shift register
  and puts bit 0 on the wire, shifting every 434 clocks.
* **uart_rx.vhd** waits for the wire to fall (start bit), waits half a bit to
  reach the *middle* of the start bit, then samples every 434 clocks, landing
  in the middle of each data bit, where the signal is cleanest. If the stop bit
  isn't a 1, the byte is thrown away.

One byte takes 10 bits = 87 µs. Tetris messages are a byte or two, so the link
is effectively instant.

## 7. "Serial echo to the PC": what test 03 actually does

The USB cable you already plug in carries **two** separate things, because
the board's USB chip (FTDI FT2232) has two channels:

* **Channel A (JTAG):** used by FPGA Builder / openFPGALoader to load `.bit`
  files. The Builder's setup switched this channel to the WinUSB driver.
* **Channel B (UART):** a plain serial port. Windows shows it as
  **"USB Serial Port (COMx)"** in Device Manager → Ports (COM & LPT). Its two
  data lines are wired to FPGA pins **G1** (data *from* the PC) and **F2**
  (data *to* the PC). The board manual draws these the other way round; it's
  wrong. Test 05 (`05_uart_probe`) proved the real wiring on 16 Oct 2026.

A **terminal program** (PuTTY, already installed on your laptop) opens that
COM port: every key you press is sent as one byte to the FPGA, and every byte
the FPGA sends back is printed on screen. **Echo** means the FPGA sends every
byte straight back, so you see what you typed. Ours sends it back in capital
letters, which proves the character really went through the FPGA (PuTTY by
itself shows nothing when you type).

Why this matters for the project:

* it proves `uart_tx` and `uart_rx` work on real hardware before we trust them
  for the board-to-board cable;
* later, **the PC can play the "other board"**: type the bytes the other
  player would send (garbage, "I lost") into PuTTY and watch the game react,
  so most of the versus logic can be tested with one board;
* it's a debug window: the game can print what it's doing.

If no COM port appears, the FTDI "VCP" driver for channel B is missing; see
the troubleshooting in `tests\03_uart_echo\README.md`.

## 8. Connectors, and what "J5" means

On a circuit board every part gets a printed label called a **reference
designator**: a letter for the kind of part plus a number. **J** means a
connector (jack/header), **SW** a switch, **D** a diode/LED, **U** a chip.
On our board:

| Label | What it is |
|---|---|
| J1 | DC power jack |
| J2 | the 16-pin socket the LCD plugs into |
| J4, J9 | 3-pin jumpers that enable LED groups D2–D9 and D10–D17 |
| **J5** | **20-pin expansion header: 16 free FPGA pins + power** |
| J6, J11, J13 | jumpers: buzzer, WiFi and Bluetooth power |
| J7 | header with the ADC inputs and DAC output |
| J10, J15 | test headers for the WiFi and Bluetooth modules |
| J14 | socket for the small TFT screen |

**J5** is two rows of 10 metal pins. Pin 1 is normally marked on the board
(a small triangle, a "1", or a square pad). The numbering zig-zags between
the two rows:

```
   row A:  1   3   5   7   9  11  13  15  17  19
   row B:  2   4   6   8  10  12  14  16  18  20

   1 = 5 V    3 = 3.3 V     (power OUT of the board: never connect these
   2 = GND    4 = GND        to a signal pin!)
   5 .. 20 = FPGA pins L14 M13 H14 H13 F11 G11 C14 D14
                       E13 F13 F14 G14 D13 D12 E12 F12
```

The manual's own J5 table uses the old Spartan-6 board's pin names, which
don't exist on our chip. The names above come from the official pin file
inside the TA's FPGA Builder. Their order along the header is our best
reading of the manual's camera diagram, and **test 02 checks it**. Because J5 pins
connect straight to the FPGA with nothing else on them, they're the right place
for the cable between the two boards.

## 9. Connecting two boards

```
   Board A                                    Board B
   J5 pin 5  (L14, TX) ---[330 Ω]------------> J5 pin 6  (M13, RX)
   J5 pin 6  (M13, RX) <------------[330 Ω]--- J5 pin 5  (L14, TX)
   J5 pin 2  (GND)     ----------------------- J5 pin 2  (GND)
```

* **Crossed over:** what one board *transmits* is what the other *receives*.
* **Ground wire:** a voltage only means something relative to ground. The
  boards are powered separately, so without this wire the receiver can't
  tell 0 from 1.
* **330 Ω resistors:** if a pin assignment is wrong and two outputs end up
  fighting each other, the resistor limits the current to ~10 mA so nothing
  gets damaged. Normal signals pass through unaffected at this speed.

## 10. Simulation and testbenches

A **testbench** is a VHDL file that only runs in the simulator (Vivado's
`xsim`). It contains no ports. It instantiates our design, generates the clock,
drives the inputs and checks the outputs, printing PASS or FAIL. It's much
faster than rebuilding for the board each time, and you can see every
internal signal.

* `sim\tb_uart_loop.vhd` connects `uart_tx` straight into `uart_rx` and checks
  that 6 bytes come out unchanged.
* `sim\tb_vga_frame.vhd` runs test 01 for about three frames, measures the
  hsync/vsync timing, and records one frame of the R/G/B outputs into
  `sim\out\frame.png`: it "sees" the screen the way a monitor would, using
  only the output wires. This is how we know the picture is right before ever
  plugging in a monitor.

Run them with `tools\sim.bat <testbench>`. To view waveforms instead, open the
full Vivado → File → Project → New → add the files → Run Simulation.

## 11. Timing: what WNS means

A signal needs time to travel from one flip-flop through the logic to the
next one. At 50 MHz it has 20 ns. After routing, Vivado measures the slowest
path. **WNS (Worst Negative Slack)** = 20 ns minus that slowest path:

* WNS ≥ 0: every path makes it in time. Good.
* WNS < 0: some path is too slow; the board may behave randomly.
  Fix by simplifying that logic or adding a register stage.

Our tests have WNS around +14 to +15 ns: lots of margin. The full game will
have more logic (the renderer especially), so check `build.bat`'s WNS line
after every big change.

## 12. VHDL-93 rules for the TA's Builder

The Builder compiles with Vivado's default VHDL-93 mode. These VHDL-2008
conveniences cause errors there:

| Don't (2008 only) | Do instead |
|---|---|
| `process(all)` | list every signal the process reads: `process(x, y, sw_s)` |
| reading an `out` port inside the entity | drive an internal signal, read that, and assign the port from it |
| `port map (a => not b)` or `(a => func(sig))` | `sig2 <= not b;` then `port map (a => sig2)` |
| `when ... else` inside a process | `if ... then ... else ... end if;` inside processes |

Our own build script uses the same default, so if `tools\build.bat` passes,
the Builder will too.
