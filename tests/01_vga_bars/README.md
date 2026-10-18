# Test 01: VGA picture

**Goal:** get a picture on a VGA monitor, and check the colours, the screen
edges, our Tetris cell maths and the 60 Hz frame tick.

**Files:** `top_vga_bars.vhd` (this test) + `src\common\vga_sync.vhd`
(timing) + `common_pkg.vhd`. Ready-built: `build\top_vga_bars.bit`.

## Steps

1. Connect a VGA monitor to the board's VGA port (P1) and turn it on.
   (HDMI-only monitor: you need an *active* VGA→HDMI converter; a plain
   cable won't work.)
2. Load the design: `tools\program.bat 01_vga_bars`, or with FPGA Builder:
   run `tools\load_into_builder.bat 01_vga_bars` → open Builder → Build → Program.
3. Use slide switches **SW2** and **SW4** (the two right-most) to change the
   picture:

| SW4 | SW2 | You should see |
|---|---|---|
| 0 | 0 | 8 vertical bars: white, yellow, cyan, green, magenta, red, blue, black |
| 0 | 1 | 4 bands (red, green, blue, grey), each getting brighter left→right in 16 steps |
| 1 | 0 | a 10×20 grid of coloured blocks with light/dark edges, in a grey frame, centred |
| 1 | 1 | an orange square bouncing around a dark blue screen |

In every picture there is a thin **white line around all four edges** of the
screen.

`..\..\sim\out\preview_all_patterns.png` shows exactly what to expect (made
by the simulator from this same VHDL).

## What each result tells you

* **No picture / "No signal" / "Out of range":** the monitor didn't lock on to
  the sync. Check the cable, try another monitor, make sure the board is
  programmed (DONE LED D1 lit). Our timing is checked in simulation, so a
  cable or monitor problem is most likely.
* **White edge line missing on one side:** the monitor is cropping or shifting
  the image. Press the monitor's "Auto adjust" button (common on VGA inputs).
* **Picture 2 ramps look "jumpy"** (brightness goes up and down instead of
  smoothly up): that colour's 4 pins are in the wrong order. Reverse the order of
  that colour's lines in `pins.xdc` (e.g. RED0↔RED3, RED1↔RED2) and rebuild.
* **A colour is missing entirely** (e.g. the white bar looks yellow = no blue):
  a pin assignment or a broken resistor; check `pins.xdc`.
* **Square doesn't move:** the frame tick isn't firing; shouldn't happen
  if the picture is stable.

## How the code works (short version, more in docs\concepts.md §5)

* `vga_sync` keeps two counters, x (0..799) and y (0..524), stepping at 25 MHz
  (every second 50 MHz clock, the `pix_en` pulse). From those it makes
  hsync, vsync and `video_on`, and a `frame_tick` pulse once per frame.
* The `pattern` process is pure combinational logic: "given x, y and the
  switches, what colour?" Bars are `if x < 80 ... elsif x < 160 ...`. Ramps use
  `x(8 downto 5)` as the brightness (changes every 32 pixels). The grid takes
  cell column = (x−240)/16 and row = (y−80)/16, colour from a palette, and
  makes the outer pixel of each cell lighter (top/left) or darker
  (bottom/right) for a 3D look.
* The `bounce` process moves the square 2 px per `frame_tick` and reverses at
  the edges.
* `outreg` registers colour + hsync + vsync on the same clock edge (so they
  stay aligned) and forces black outside the visible area.

## For the design document

Take photos of the monitor in all four modes. Picture 3 is the first look at
the Tetris display.
