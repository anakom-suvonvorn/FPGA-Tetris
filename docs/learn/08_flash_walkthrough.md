# Part 8: Pictures and sound from the flash chip (test 06), line by line

This part explains the first piece of the **media layer**: reading the
board's SPI flash chip from our own logic, and showing pictures, animations
and sound stored there. It starts from zero (what is a flash chip? why
can't we just put a video into the FPGA?) and then goes through every file
of test 06.

Files: `src/media/spi_flash.vhd`, `src/media/media_player.vhd`,
`tests/06_flash_read/top_flash_read.vhd`, `tools/make_media.py`,
`tools/flash_media.bat`, `sim/flash_model.vhd`, `sim/tb_flash_read.vhd`.
Line numbers (`L114`) refer to the files as they are now (git branch
`media`). The visual guide (`tetris_visual.html`) has interactive diagrams
for this part in sections 14 and 15.

Contents:
[8.0 Why a flash chip?](#80-why-a-flash-chip) ·
[8.1 Talking SPI](#81-talking-spi) ·
[8.2 The clock pin problem: STARTUPE2](#82-the-clock-pin-problem-startupe2) ·
[8.3 How pictures and sound are stored](#83-how-pictures-and-sound-are-stored) ·
[8.4 spi_flash.vhd](#84-spi_flashvhd-line-by-line) ·
[8.5 media_player.vhd](#85-media_playervhd-line-by-line) ·
[8.6 top_flash_read.vhd](#86-top_flash_readvhd) ·
[8.7 make_media.py and flash_media.bat](#87-make_mediapy-and-flash_mediabat) ·
[8.8 Testing without the board](#88-testing-without-the-board) ·
[8.9 What the results mean](#89-what-the-results-mean)

---

## 8.0 Why a flash chip?

### The FPGA forgets everything

Everything inside the FPGA (which LUT does what, how they are wired, the
contents of the block RAM) is kept in tiny memory cells of the **SRAM**
kind: fast, but they lose their contents when the power goes off. That is
why loading a design with `program.bat` is "temporary": unplug the board and
the design is gone.

So how does a finished product (or the TA's demo design) start by itself?
Next to the FPGA sits a second chip: an **SPI flash** (on our board a
Spansion/Infineon **S25FL064L**, 64 Mbit = **8 MB**). Flash keeps its
contents without power, like a USB stick (it *is* the same technology). At
power-up the FPGA reads its bitstream (our design, ~0.5 MB) out of the
flash by itself. That is what the Builder's "PROM" / `program.bat ... flash`
does: it writes the bitstream into the flash at address 0.

```
   power on ──► FPGA: "I'm empty"  ──reads address 0..0.5 MB──►  flash chip (8 MB)
                                                                ┌──────────────────┐
                                                        0 MB    │ bitstream        │ (only if you used "PROM")
                                                      0.5 MB    │ (empty)          │
                                                        1 MB    │ OUR MEDIA FILE   │ ← tools\flash_media.bat
                                                                │  pictures, sound │
                                                        8 MB    └──────────────────┘
```

### The rest of the flash is ours

The bitstream uses about half a megabyte. The other ~7.5 MB are free, and
after configuration the flash chip is just a chip on four wires that our
own logic may talk to. We put our media at **1 MB** (address `0x100000`),
safely after any bitstream, leaving **7 MB** (7,340,032 bytes).

### Why not inside the FPGA?

The XC7S15 has 10 block RAM tiles of 36 Kbit = **45 KB** in total. One
picture of 160 × 120 pixels with 256 colours is 19 KB; a second of sound at
8,000 samples per second is 8 KB. A video or a song is millions of bytes.
So the plan is: keep everything in the flash, and bring in only what is
needed **right now**: one picture (the one on the screen) and a fraction of
a second of sound. That is exactly what `media_player` does.

---

## 8.1 Talking SPI

**SPI** (Serial Peripheral Interface) is the simplest chip-to-chip
"language". Four wires:

| wire | on our board | meaning |
|---|---|---|
| **CS_N** (chip select, active low) | pin C11 (FCS_B) | low = "chip, I'm talking to you" |
| **SCLK** (serial clock) | pin A8 (CCLK) | made by us (the master); one bit moves per period |
| **MOSI** (master out, slave in) | pin B11 (D00) | bits from us to the chip |
| **MISO** (master in, slave out) | pin B12 (D01) | bits from the chip to us |

We use **mode 0**: SCLK rests low. The chip **reads MOSI on the rising
edge** of SCLK and **changes MISO just after the falling edge**. Bits travel
most significant first.

Every conversation ("transaction") has the same shape: pull CS_N low, send
a **command byte**, maybe an address, then keep clocking and the chip
answers. Pull CS_N high to end it. We need only two commands:

```
READ ID (9F):   CS_N ‾‾\________________________________________/‾‾
                MOSI      1 0 0 1 1 1 1 1 | x x x ...
                MISO      - - - - - - - - | 0000 0001  0110 0000  0001 0111
                                             01 = maker Spansion, 60 17 = 64 Mbit chip

READ (03):      MOSI      0 0 0 0 0 0 1 1 | A23 ... A0 (24 bits)   | x x x ...
                MISO      - - - - - - - - | - - - - - - - - - - -  | byte[A] byte[A+1] byte[A+2] ...
```

The nice thing about READ: after the address, the chip keeps sending the
next byte for as long as we keep clocking. One READ can bring in a whole
picture (19,200 bytes) without sending another address.

**Speed.** Each bit takes one SCLK period. Our clock is 50 MHz, so the
fastest SCLK we can make with registers is 25 MHz (low for one clock, high
for one clock): 25 Mbit/s = **3.1 MB per second**. The READ command allows up
to 50 MHz on this chip, so 25 MHz is well within its limits. The test lets
you slow down to 12.5, 6.25 or 3.125 MHz with switches, to see whether
errors appear or disappear.

There is a faster "Quad SPI" (4 data wires: D00..D03), but 3.1 MB/s is
already about 10× more than we need (see 8.9), so we keep it simple and
hold D02 (WP#) and D03 (HOLD#) high: if HOLD# floated low the chip would
pause and ignore us.

---

## 8.2 The clock pin problem: STARTUPE2

MOSI, MISO and CS_N are normal I/O pins after configuration; we just put
them in `pins.xdc`. **SCLK is not.** It is the FPGA's own configuration
clock pin **CCLK** (A8), a *dedicated* pin: the FPGA drove it itself while
loading the bitstream from the flash, and it is not connected to the normal
I/O fabric. You can't write `PACKAGE_PIN A8` for it.

Xilinx gives one door to it: the **STARTUPE2 primitive**, a small block
built into the chip (it also handles the end of configuration). It has an
input called **USRCCLKO** ("user CCLK out"): whatever signal we connect
there comes out on the CCLK pin. So `spi_flash` makes an `sclk` signal, and
the top level hands it to STARTUPE2 (top_flash_read L201–215):

```vhdl
u_startup : STARTUPE2
  port map (..., USRCCLKO  => sclk,     -- our SPI clock -> CCLK pin
                 USRCCLKTS => '0',      -- '0' = drive the pin
                 USRDONEO  => '1', ...);
```

A *primitive* is a piece of the chip used directly by name instead of
described in VHDL; `library unisim; use unisim.vcomponents.all;` makes the
names known.

**One quirk:** the Xilinx documentation says the first 3 clock edges on
USRCCLKO after configuration are swallowed while CCLK switches over from
the configuration logic to us. So `spi_flash` starts with 8 dummy SCLK
periods while CS_N is high (the chip ignores clocks while it isn't
selected): state S_WAKE.

**Timing.** Our SCLK register → STARTUPE2 → CCLK pin → board wire → flash →
MISO → board wire → FPGA pin → our register takes several nanoseconds each
way, and at 25 MHz a whole SCLK period is only 40 ns. So `spi_flash` reads
the MISO bit as late as possible: at the **end of the high half**, at the
same clock edge that drives SCLK low again. The chip only changes MISO a few
ns *after* it sees that falling edge, and our edge reaches it late anyway,
so the old bit is still there. In the picture (one bit at 25 MHz):

```
 50 MHz clock   _|‾|_|‾|_|‾|_|‾|_
 sclk (ours)    ___|‾‾‾|___|‾‾‾|__
 MISO (chip)    ==X=======X=======    changes ~10-15 ns after each falling edge
                          ^ we take the bit here (end of the high half):
                            it has been stable for ~25 ns
```

If the speed was too much for the board, VERIFY would count bad bytes at
25 MHz and none at 12.5 MHz. That is exactly what test 06 checks.

---

## 8.3 How pictures and sound are stored

### Pictures: 160 × 120, with a palette

The screen is 640 × 480. A full-size picture would be 307,200 pixels; at
12 bits each that is 450 KB, ten times the whole block RAM. So pictures are
**160 × 120** and each pixel is drawn as a 4 × 4 block (the screen pixel at
(x, y) shows picture pixel (x / 4, y / 4); dividing by 4 = dropping 2 bits,
free). It looks chunky, like an old game, which suits us.

Each pixel stores not a colour but a **number into a palette** (a colour
table), exactly like a GIF file:

```
 frame buffer (BRAM, 19,200 bytes)        palette (BRAM, 256 entries x 12 bits)
 pixel (x/4, y/4) = 37  ─────────────────► entry 37 = 0xF80 (orange) ──► VGA R G B
```

With 8 bits per pixel (bpp) there are 256 colours to choose from, picked by
`make_media.py` for each item (it looks at the picture(s) and chooses the
256 most useful colours: "quantizing"). Fewer bits per pixel = fewer
colours but smaller files:

| bpp | colours | bytes per picture | pixels per byte |
|---|---|---|---|
| 8 | 256 | 19,200 | 1 |
| 4 | 16 | 9,600 | 2 |
| 2 | 4 | 4,800 | 4 |
| 1 | 2 (Bad Apple!) | 2,400 | 8 |

In the flash, pixels are **packed** (bpp 1: 8 pixels in one byte, the
leftmost pixel in the highest bit). The player unpacks them into the
frame buffer, which always has one byte per pixel.

### Sound: numbers, many times a second

Sound is air pressure going up and down. A microphone turns it into a
voltage; measuring that voltage 8,000 times a second (the **sample rate**)
and storing each measurement as one byte (0..255, 128 = silence) gives
**8-bit PCM** sound, like a `.wav` file. To play it back we output those
numbers at the same rate, through the same sigma-delta "bucket" as the game
music (Part 6, section 6.5): the audio pin's average follows the sample.
8,000 samples/s keeps sounds up to 4 kHz: telephone quality, fine for memes.

### Animations and videos: records

An animation is a list of pictures. A video with sound is pictures + sound.
Every frame is one **record** in the flash:

```
 record = [ sound bytes for this frame ][ packed picture ]
            e.g. 533 bytes (8 kHz / 15 fps)   9,600 bytes (4 bpp)
```

The player loads one record, then the next, ... Sound first, so it gets
into the sound buffer as soon as possible.

### The file layout

`make_media.py` writes one file, copied to flash address 1 MB:

```
 1 MB + 0        header, 16 bytes: "TDMF", version, number of items,
                 address + length of the VERIFY block
 1 MB + 16       directory: 32 bytes per item (up to 16 items):
                 bpp, frame time, loop flag, number of records, sound
                 bytes per record, address of the data, sample rate,
                 "low water" (see 8.5), name (16 characters)
 1 MB + 4 KB     VERIFY block: 256 KB of a known pseudo-random sequence
 ...             item 0: palette (2^bpp x 2 bytes), then its records
 ...             item 1: ...
```

Multi-byte numbers are little-endian (lowest byte first). Every part starts
at a multiple of 4 KB (the flash erases in 4 KB sectors). `TDMF` = "Tetris
Duel Media File": if the first 4 bytes say that, the file is there.

### The VERIFY block: how do we know every byte is right?

256 KB made by a 16-bit **LFSR** (the same kind of random generator as the
game's piece picker: shift left, the new bit is an XOR of 4 bits), starting
from `ACE1`, 8 steps per byte. The FPGA runs the very same LFSR while it
reads the block and compares every byte: any difference is a read error. No
need to store the right answers anywhere.

---

## 8.4 `spi_flash.vhd`, line by line

The SPI master. It knows nothing about pictures: give it a command, an
address and a length, and it delivers the bytes one by one.

### Ports (L46–68)

| port | meaning |
|---|---|
| `half_period` | SCLK speed: clocks per half period (1 = 25 MHz, 2 = 12.5, 4 = 6.25, 8 = 3.125) |
| `start` + `cmd`, `use_addr`, `addr`, `len` | a request: command byte, with or without a 24-bit address, read `len` bytes |
| `busy` | '1' from `start` until done |
| `dout` + `dout_valid` | each byte, for one clock |
| `done` | one-clock pulse at the end |
| `sclk`, `cs_n`, `mosi`, `miso` | the 4 wires (`sclk` goes to STARTUPE2 in the top) |

There is no way for the user to say "wait": bytes come at most once every
16 clocks and must be taken when `dout_valid` is '1'.

### Registers (L71–84)

`state` (5 states), `sclk_r` and `cs_r` (the pins), `hp` (the speed, frozen
for the whole transaction), `ph` (clocks spent in the current SCLK half),
`sh_out` (32-bit shift register: command + address), `n_out` (bits left to
send), `sh_in` (8-bit shift register for incoming bits), `n_in` (bits of
this byte received), `left` (bytes left), `wake` (counter), `dv`/`dn`
(the output pulses).

### The half-period timer (L94–95)

```vhdl
half_done := (ph = hp - 1);
if half_done then ph <= 0; else ph <= ph + 1; end if;
```

`ph` counts 0, 1, ..., hp−1, 0, ... and `half_done` is true in the last
clock of each half. With hp = 1 it is true every clock: SCLK toggles every
clock = 25 MHz.

### S_WAKE (L100–105)

16 half periods (8 SCLK periods) with CS_N high, slowly (hp = 4), to get
STARTUPE2's clock path going (8.2). Then S_IDLE.

### S_IDLE (L107–120)

Wait for `start`. Then: CS_N low (the chip listens from now), load
`sh_out` with the command in the top 8 bits and the address below it,
`n_out` = 32 bits (or 8 for a command without address), `left` = `len`.

### S_SEND (L122–135)

Each half period: if SCLK is low, raise it (the chip reads MOSI now); if
high, lower it and shift `sh_out` left so the next bit appears on
`mosi <= sh_out(31)`. After the last bit: S_READ (or S_END if `len` = 0).

### S_READ (L137–157)

The same toggling. At the end of each high half (just before SCLK falls,
8.2):

```vhdl
sh_in <= sh_in(6 downto 0) & miso;   -- the new bit enters on the right
```

After 8 bits, `dv <= '1'` and `left` goes down by 1. Note the timing: `dv`
and the 8th bit are written at the same clock edge, so in the next clock
`dout_valid` is '1' and `dout` (= `sh_in`) holds the whole byte (L173–176).
When `left` reaches 0: S_END.

(The first lines of S_READ, L138–139, were added for the game's media
engine: while the input `hold` is '1', the next byte doesn't start. Test 06
leaves `hold` at its default '0'. Part 9, section 9.6, explains why.)

### S_END (L158–162)

CS_N high, wait 3 clocks (the chip wants CS_N high for a moment between
commands), pulse `done`, back to S_IDLE. `wake` is reused as the counter;
L166–168 loads it with 3 when a transaction starts.

---

## 8.5 `media_player.vhd`, line by line

The player: reads the directory, loads palettes and records, keeps the
picture in a frame buffer and the sound in a ring buffer, and decides
**when** to load the next record. One state machine, plus 3 memories.

### Ports (L53–91)

Commands: `play` (+ `item`), `stop`, `verify`, one-clock pulses. The 4
flash wires. Picture: `x, y` in, `rgb` out **3 clocks later**. Sound:
`sample` (8 bits, 128 = silence). Status for the screen: `flash_id`,
`head` (the first 4 bytes), `found`, `n_items`, the item `name`,
`is_playing`, `has_video`, and four BCD counters (`frame_bcd` records
loaded, `load_bcd` time to load the last record in 0.1 ms, `under_bcd` times
the sound ran dry, `ver_err_bcd` / `ver_ms_bcd` the verify result). BCD
counters are counted with the same `bcd_inc` as the game's line counter
(L179–198), so the screen can show them without converting.

### The memories (L98–119, L484–540)

Three block RAMs, each written by the state machine and read every clock:

* **frame buffer**, 160 × 120 bytes, built as **5 banks of 4,096 bytes**
  (`g_fb`, L487–499). Why banks? A BRAM tile holds 4,096 × 9 bits. Left to
  itself, Vivado built the 19,200 × 8 memory from 8 tiles that are each
  32,768 × 1 bit (8 bits wide = 8 tiles, mostly empty). Splitting it by
  hand, bank = address / 4,096 and place = address mod 4,096, uses 5 tiles.
  Each bank reads the same place; `rbank` (L501–507) remembers which bank's
  output to use.
* **palette**, 256 × 12 bits (L509–515), read with the frame buffer's
  output as the address.
* **sound ring**, 2,048 bytes (L517–523), read at `rd_ptr`.

The picture path (L527–540 and 509–515): 3 registers in a row, so the
colour for (x, y) is ready 3 clocks after (x, y):

```
 clock 1: ra    <= (y/4) * 160 + x/4      address; 160 = 128 + 32: two shifts + add
 clock 2: fq(k) <= bank k (ra mod 4096)   the pixel's palette number
 clock 3: pal_q <= palette(fb_q)          its colour  →  rgb
```

The top level delays HSYNC / VSYNC / "visible" by 3 clocks to match (8.6).

### Power-up: ID and header (L267–298)

**M_ID** asks for command 9F (no address, 3 bytes) and **M_ID_W** shifts
the 3 bytes into `id_r`: `01 60 17`. **M_HDR** reads 16 bytes at `BASE`;
**M_HDR_W** sorts them by byte number `k` (L284–298): bytes 0..3 → `head`,
5 → number of items, 8..10 → verify address, 12..14 → verify length.
`bi` counts bytes of the current read (L262).

### Waiting for a command (L301–309)

`req_play`, `req_stop`, `req_ver` remember a command (L257–260) until the
flash reader is free. M_IDLE starts `play` only if the header said `TDMF`
and the item number exists.

### Loading an item (L312–372)

* **M_ENT / M_ENT_W**: read the item's 32-byte directory entry at
  `BASE + 16 + 32 × item` and sort the bytes into `e_bpp`, `e_ft`,
  `e_loop`, `e_nrec`, `e_aud`, `e_addr`, `e_rate`, `e_low`, and 16 name
  characters (shifted into `name_r`).
* **M_PAL / M_PAL_W**: read `2^bpp × 2` bytes: each colour as low byte
  (G, B) then high byte (R). The second byte writes `pal(bi / 2)`.
* **M_PLAY0**: reset everything for playing: record 0, its address, the
  counters, and an **empty** sound ring.

### When to load the next record? (M_WAIT, L375–392)

This is the heart of the player. Three cases:

```vhdl
if e_aud = 0 then          -- picture only:  every frame_ticks frames, at a frame_tick
elsif e_bpp = 0 then       -- sound only:    whenever the ring has room for one more record
else                       -- picture+sound: when the ring is running low (< low water),
                           --                at the next frame_tick
```

* **Picture only** (an animation): `ticks` counts screen frames since the
  last record. `frame_ticks` = 3 means a new picture every 3 frames = 20 fps.
* **Sound only**: keep the ring as full as possible.
* **Picture + sound**: the **sound sets the pace**. Sound must play at
  exactly 8,000 samples a second or it sounds wrong; pictures can wait a
  few ms. So the next record is loaded when the sound left in the ring falls
  below the "low water" mark (`e_low`, ~25 ms of sound, computed by
  make_media.py). That record's picture is shown at once, and its sound
  starts playing within those ~25 ms: picture and sound can't drift apart,
  however long the video is.

Why wait for `frame_tick`? It comes at the end of the visible picture
(vga_sync, line 480). If we start writing the frame buffer there, the
loader (19,200 bytes in 6 ms at 25 MHz) runs ahead of the screen beam
(which takes 15 ms to draw 480 lines), so every frame shows either all-old
or all-new pixels, never a mix. A mix is called **tearing**: a horizontal
cut through moving things. At 3.125 MHz loading takes 50 ms, the beam
overtakes the loader, and you *will* see tearing: that's in the checklist.

A command (`stop`, `play`, `verify`) while waiting goes back to M_IDLE.

### Loading a record (M_REC, M_REC_W, L394–441)

M_REC starts one READ of `sound bytes + picture bytes` at the record's
address and resets `wa` (the frame buffer write position). M_REC_W then
handles each byte:

* **byte number < sound bytes** (L405): into the ring at `wr_ptr`,
  `wr_ptr` + 1, and `dfill := 1` (one more byte waiting, see below).
* **8 bpp**: straight into the frame buffer at `wa`.
* **fewer bpp** (L412–418): keep the byte in `un_sh` and set `un_n` = pixels
  in it (8, 4 or 2). Then, in the clocks *between* bytes (L419–426), one
  pixel per clock: the top `bpp` bits of `un_sh` go into the frame buffer,
  `un_sh` shifts left by `bpp`. There are at least 16 clocks between bytes
  and at most 8 pixels per byte, so it always finishes in time.

`load_cnt` counts the loading time in 0.1 ms steps (5,000 clocks). When the
read is done (L428–441): remember the time, count the frame, and go to the
next record, or back to the first (loop), or stop.

### Sound out (L461–481)

A sample is due every 50,000,000 / rate clocks. Instead of dividing, a
**phase accumulator**: add `rate` every clock; whenever the sum passes 50
million, a sample is due and 50 million is taken off:

```vhdl
if acc + e_rate >= CLK_HZ then
  acc <= acc + e_rate - CLK_HZ;      -- a sample is due
  ...  smp <= ring_q; rd_ptr + 1; dfill := dfill - 1;
else
  acc <= acc + e_rate;
end if;
```

On average this is exactly `rate` samples per second, for any rate, even
7,995 (the clocks between samples alternate between 6,253 and 6,254).

If the ring is empty when a sample is due, the last sample is kept (no
click) and `under_bcd` counts it, but only after the first record has
arrived (`started`), so the start of an item doesn't count.

**`fill`** = bytes waiting in the ring. In one clock a byte can come in
(loader) *and* go out (sound) at the same time, so both parts only set a
variable `dfill` (+1, −1, or both = 0) and `fill <= fill + dfill` is
written once at the end (L478–480), the same trick as `p` for the garbage
in tetris_core.

### Verify (M_VER, M_VER_W, L444–459)

Read the whole verify block; for every byte compare with `v_lfsr(7 downto
0)` and step the LFSR 8 times (`lfsr8`, L201–208: a `for` loop of 8 steps,
which becomes 8 layers of XOR gates, all in one clock). Count wrong bytes
and milliseconds (50,000 clocks).

---

## 8.6 `top_flash_read.vhd`

Wiring + controls + text, for the test only.

* **L121–149: inputs.** vga_sync, 5 debounced buttons (`pressed` pulses),
  3 synchronised switches. SW2 / SW4 select `half` (L145–149).
* **L151–180: buttons.** Left/right change `item` (wrapping around) and
  start it, centre plays or stops, top starts VERIFY, bottom hides the text.
  When the header is first found (`found` rises), item 0 starts by itself.
* **L183–215: the player, the pins and STARTUPE2** (8.2). WP# and HOLD#
  are tied high (L195–196).
* **L216–278: text.** 10 lines of 27 characters, built from fixed templates
  (`to_codes`) with numbers written in by `put`, `put_hex` (2 hex digits)
  and `put_bcd` (4 BCD digits). Hex digits need no conversion: character
  codes 0..15 *are* `0`..`9`, `A`..`F`. 10 `text_layer`s (a `generate`
  loop) draw them.
* **L280–316: the picture.** The player's `rgb` is 3 clocks behind `x, y`;
  `text_layer`'s pixel is 1 clock behind. So HSYNC, VSYNC, "visible" and
  the "behind the text" area are delayed by 3 clocks (shift registers
  `hs_d`, `vs_d`, `von_d`, `bnd_d`) and the text pixels by 2 more (`td`).
  Then: the picture; dark blue for sound-only items; behind the text the
  picture at half brightness (each colour shifted right by 1 bit) with
  yellow letters.
* **L317–327: sound.** First-order sigma-delta: an 8-bit bucket plus the
  sample every clock, the carry is the audio pin (Part 6, 6.5).
* **L329–336: 7-segment.** The last 2 ID bytes (`6017`), dots for "found"
  and "playing".

`pins.xdc`: the flash pins C11, B11, B12, D10, C10 (bank 14, the
configuration bank). We found them by asking Vivado for the pins of the
XC7S15-FTGB196 whose function names contain `FCS_B`, `D00`, `D01`, ...
(`get_package_pins -filter {PIN_FUNC =~ *FCS*}`).

---

## 8.7 `make_media.py` and `flash_media.bat`

### make_media.py (Python, runs on the PC)

* **L54–64 `lfsr_bytes`**: the verify block, the same LFSR as `lfsr8`.
* **L67–79 `fit`, `to12`**: scale a picture to fit 160 × 120 with black
  bars; round 8-bit colours to the 4 bits per colour the VGA output has.
* **L82–105 `make_palette`**: one palette for all frames of an item, like a
  GIF's colour table. For many frames it makes a "contact sheet" of up to 64
  frames side by side and asks Pillow to choose the best `2^bpp` colours
  (median cut). For 1 bpp it just uses black and white.
* **L108–128 `frame_indices`, `pack`**: each pixel → nearest palette entry
  (with dithering: mixing two colours in a pattern to fake a third), then
  packed MSB first.
* **L141–170 ffmpeg**: videos, GIFs and sounds are decoded by **ffmpeg**:
  `-vf fps=..,scale=..,pad=..` gives raw 160 × 120 RGB frames,
  `-ac 1 -ar 8000 -f u8` gives raw 8-bit mono sound.
* **L173–215 `Item`**: one directory entry; `build()` makes its palette and
  records (sound + picture per record), `entry()` its 32 bytes.
* **L217–226 `av_params`**: sound bytes per record = rate / fps, rounded,
  and the rate adjusted so it is exact (8,000 Hz at 15 fps → 533 bytes →
  7,995 Hz). Low water = 25 ms of sound + 64. At most 30 fps (the screen
  has 60 frame ticks a second; the pacing needs at least 2 per record).
* **L262–343 `demo_items`**: the 5 demo items, drawn with Pillow: the colour
  card, the ball (16 colours, 20 fps), the 1-bit animation (30 fps), the
  FLASH + BEEP sync test (a beep exactly on the frames that flash white),
  and an 8 kHz tune.
* **L365–391 `build`**: lays out header, directory, verify block and items
  (each at a 4 KB boundary), and prints the size table.

### flash_media.bat

```
openFPGALoader -c ft2232 -f -B spiOverJtag_xc7s15ftgb196.bit -o 0x100000 media\media.bin
```

How can the PC write the flash at all? The USB cable talks **JTAG** to the
FPGA, not SPI to the flash. So openFPGALoader first loads a tiny helper
design (`spiOverJtag`, `-B`) into the FPGA that passes JTAG data on to the
flash's SPI pins (through STARTUPE2, like ours). Then it erases the 4 KB
sectors it needs and writes our file, starting at `-o 0x100000` (1 MB), so
a bitstream at address 0 is untouched. `check` mode reads 64 KB back
(`--dump-flash`) and compares, to tell "writing went wrong" apart from
"our reading goes wrong".

---

## 8.8 Testing without the board

### `sim/flash_model.vhd`: a pretend flash chip

Behaves like the S25FL064L for 9F and 03: reads MOSI on rising SCLK edges,
puts MISO bits out after falling edges, **15 ns late** (the real chip:
at most 8 ns), so the simulation checks that our "sample late" idea copes
with delay. Its contents come from `sim/media_sim.hex` (one hex byte per
line), written by `python tools/make_media.py sim/media_sim.bin --sim`.

### `sim/tb_flash_read.vhd`

`media_player` + `vga_sync` + the model. Checks: (1) the ID is 01 60 17;
(2) `TDMF` and 3 items; (3) item 0 loads (6.1 ms at 25 MHz), one VGA frame
is captured to `frame.png` and 15 pixels are compared with the colours
`make_media.py` wrote to `media_sim_expect.txt`; (4) VERIFY of 4 KB: 0
errors; (5) a 1-bit picture + sound item: all 4 records, all 256 sound
samples in the right order, no underruns. The fake `frame_tick` comes every
30,000 clocks instead of 833,333 so it runs in minutes. **TEST PASSED.**
The captured frame is `tests/06_flash_read/screenshot_sim.png`.

Two things the simulation found before the board did:

* At first the testbench's frame tick came exactly once per record, so the
  ring could never fill up and the sound ran dry every frame. Real videos
  have ≤ 30 fps on a 60 Hz screen, so make_media.py now refuses more.
* Underruns were counted at the very start, before the first record had
  arrived. Now only after `started`.

---

## 8.9 What the results mean

**Speed is not the limit.** At 25 MHz the flash gives 3.1 MB/s. A 256-colour
frame takes 6 ms to load, a 16-colour frame 3 ms, and a video at 15 fps
with sound needs ~0.15 MB/s: 5 % of what the flash can do.

**Space is.** 7 MB in total:

| what | bytes | 7 MB lasts |
|---|---|---|
| sound, 8,000 samples/s | 8 KB per second | 15 minutes |
| picture, 1 bit (2 colours) | 2.4 KB per frame | at 15 fps: 3.4 minutes |
| picture, 2 bits (4 colours) | 4.8 KB per frame | at 15 fps: 1.7 minutes |
| picture, 4 bits (16 colours) | 9.6 KB per frame | at 15 fps: 51 s, at 10 fps: 76 s |
| picture, 8 bits (256 colours) | 19.2 KB per frame | at 15 fps: 25 s; a still picture is 19 KB |

So: still pictures and sound clips are cheap, short videos are fine, and a
long video (full Bad Apple = 3 min 39 s) needs 1 bit, a low frame rate, or
**compression** (Bad Apple is mostly big black and white areas: storing
"80 white, then 12 black, ..." instead of every pixel would make it ~10×
smaller; the player would need a small decoder, which is possible later if
we want it).

**BRAM.** The player uses 6 of the 10 tiles (frame buffer 5, palette and
sound ring half a tile each). The game uses none, so the player fits next to
the game. LUTs: the game is at 75 %, the player needs ~700 more (test 06's
1,749 includes 10 text lines), which is tight but should fit.

Next steps, once the test passes: pick the media (which clips, how long,
how many colours), then build the player into the game: a loss video
replacing the board when you lose, a win picture, the Tetoris song from
flash instead of the Korobeiniki ROM, real OIIA cat sound + picture.
