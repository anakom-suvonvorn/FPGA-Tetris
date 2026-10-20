# Part 9: The media in the game, line by line

Part 8 (test 06) showed that the FPGA can read pictures and sound out of the
flash chip. This part builds the **approved media plan** into the game:
real music instead of the beeping Korobeiniki, three **media attacks**
(Bad Apple, OIIA, Jevil) that play behind the rival's game, a random clip or
picture when you win or lose, and two kinds of **sprites** (Jevil floating
over the screen, friends' faces on the bouncers).

It starts with the two tricks that make 7 minutes of video and sound fit
into 7 MB (**ADPCM** sound and **delta + run-length** pictures), then goes
through every new file and every change.

Files: `tools/make_game_media.py`, `src/media/adpcm_dec.vhd`,
`src/media/media_engine.vhd`, `src/media/media_ctrl.vhd`,
`src/media/media_mix.vhd`, `sim/tb_media_engine.vhd`,
`sim/tb_media_ctrl.vhd`, and changes in `spi_flash.vhd`, `chaos_pkg.vhd`,
`chaos_task.vhd`, `chaos_fx.vhd`, `chaos_render.vhd`, `tetris_render.vhd`,
`tetris_sound.vhd`, `top_tetris.vhd`, `game/pins.xdc`. Line numbers (`L114`)
refer to the files as they are now (git branch `media`). The visual guide
(`tetris_visual.html`) has interactive diagrams for this part in section 16.

Contents:
[9.0 What you get](#90-what-you-get) ·
[9.1 The plan and the budget](#91-the-plan-and-the-budget) ·
[9.2 ADPCM: sound in 4 bits](#92-adpcm-sound-in-4-bits) ·
[9.3 Delta + run length: pictures that only store changes](#93-delta--run-length-pictures-that-only-store-changes) ·
[9.4 The file (make_game_media.py)](#94-the-file-make_game_mediapy) ·
[9.5 adpcm_dec.vhd](#95-adpcm_decvhd-line-by-line) ·
[9.6 media_engine.vhd](#96-media_enginevhd-line-by-line) ·
[9.7 media_ctrl.vhd](#97-media_ctrlvhd-what-plays-when) ·
[9.8 media_mix.vhd](#98-media_mixvhd-the-last-stage-of-the-picture) ·
[9.9 Changes in the game files](#99-changes-in-the-game-files) ·
[9.10 Testing it](#910-testing-it) ·
[9.11 Try it on the board](#911-try-it-on-the-board) ·
[9.12 How big is it?](#912-how-big-is-it)

---

## 9.0 What you get

| when | what you see | what you hear |
|---|---|---|
| a game runs | the game, as before | **music**: Tetris (Teto SV), then Tetris (original), then again... |
| the rival hits you with a **media attack** | its video **behind** your game: in the background and the empty cells of your field, dimmed so the blocks stay readable | the video's sound, instead of your music |
| ... **Bad Apple!!** (84 s) | black and white shadow video, at half brightness | Bad Apple |
| ... **OIIA OIIA** (44 s) | the spinning cat video (psytrance remix) | its sound, ending on the fart |
| ... **JEVIL** (40 s) | a short looping background + **Jevil himself floating over the whole screen** | THE WORLD REVOLVING |
| the attack is over | the game | the music carries on **where it was** |
| the **BOUNCERS** attack (chaos) | the bouncing squares wear your friends' **faces** (32 × 32) | |
| you **win** | one of: the yippee cat video (whole screen), or a picture in the right panel (Diabeetus, Miku, Teto) | its sound |
| you **lose** | one of: 10 rickrolls (whole screen), a Foxy or Puppet **jump scare** over your game, or one of 3 "loss" pictures | its sound (or the scream) |

The result text (WIN! / LOSE) and PRESS START stay on top of the
full-screen clips. Videos disappear when they end; still pictures stay until
the next game starts. **SW4** switches all of the media sound on/off (it
used to be "music on"), SW5 the sound effects as before. Without the media
file in the flash, the game is the old one minus the music (and the
bouncers are coloured squares, now 32 px instead of 20).

A media attack is a normal chaos attack (a task you finished sends it), but
they are long, so the **sender** has to wait: after sending one, it can't
send another media attack until that one is over + 10 s.

---

## 9.1 The plan and the budget

What goes in, and how each piece is stored, is one Python list:
`tools/media_plan.py` (`PLAN`). You tuned it with the renders of
`tools/media_lab.py` (they show and play exactly what the board will), and
`tools/make_game_media.py` now turns the same list into the flash file. So
the board shows what the renders showed: same cuts, fades, colours, green
screen key, frame rates.

The flash has **7 MB** free after the FPGA's own bitstream. The plan uses
6.83 MB of it:

| item | seconds | pictures | sound | total |
|---|---|---|---|---|
| music: Teto SV + original | 225 | – | 1.80 MB | 1.80 MB |
| Bad Apple (1 bit, 10 fps) | 84 | 0.67 MB | 0.67 MB | 1.35 MB |
| OIIA (16 colours, 10 fps) | 44 | 1.24 MB | 0.35 MB | 1.59 MB |
| Jevil (4 colours, 3.4 s loop) | 40 | 0.02 MB | 0.32 MB | 0.35 MB |
| rickroll (16 colours, 10 fps) | 34 | 0.67 MB | 0.27 MB | 0.95 MB |
| yippee (256 colours, 10 fps) | 6 | 0.59 MB | 0.05 MB | 0.64 MB |
| jump scares, pictures, sprites | | | | 0.14 MB |

Stored plainly (every pixel of every frame, 16-bit sound) the same plan
would need about **27 MB**: 13.9 MB of sound and 13.2 MB of pictures. The
two tricks below bring that down to 3.5 MB of sound (4× smaller) and
3.3 MB of pictures (4× smaller overall; from 3× for Bad Apple up to 75×
for the Jevil loop).

---

## 9.2 ADPCM: sound in 4 bits

**Plain sound (PCM)** is a list of numbers: how far the speaker is pushed,
measured 16,000 times a second ("16 kHz", enough for everything up to
8 kHz: much better than test 06's 8 kHz). With 16 bits per number that's
32 KB a second; 7 MB would last less than 4 minutes, and we have 7+ minutes
of sound.

**The idea of ADPCM** ("adaptive differential PCM"): sound changes smoothly,
so each sample is close to the one before. Instead of the sample, store
**how much it changed**, and only roughly, in 4 bits:

```
  code (4 bits):  bit 3 = up or down, bits 2..0 = how far, in units of 'step'
  move = step/8 + (bit2 ? step) + (bit1 ? step/2) + (bit0 ? step/4)
         -> anything from step/8 to 15/8 step
```

**The adaptive part:** the step size isn't fixed. A table of 89 sizes goes
from 7 to 32,767, each about 10 % bigger than the one before. After every
sample the decoder moves through the table: a big move (bits 2..0 = 4..7)
means the sound is changing fast, so the next step is bigger (2, 4, 6 or 8
places up); a small move (0..3) means it's quiet, so the step shrinks (1
place down). So loud, fast music gets big steps, a quiet fade gets tiny
precise ones.

**Both sides do the same arithmetic.** The encoder (Python) doesn't just
pick the closest code, it then decodes it itself, exactly like the FPGA
will, and continues from *that* result. So encoder and decoder always agree
on the current guess ('pred') and step ('idx'), and the errors don't add
up. This is the standard "IMA ADPCM" (the same as in `.wav` files from old
games); `media_lab.py` made all the `.wav` renders with this very
arithmetic, so what you heard there is what the board plays.

**4 bits per sample = 8 KB per second** at 16 kHz. Two samples per byte;
the low 4 bits are played first.

**One more thing for "carry on where it was":** the music is cut into
records of 1,024 bytes (2,048 samples, 0.128 s). Every record stores the
decoder's state (pred, idx) at its start (3 bytes). To continue the music
from record 300 after an attack, the decoder loads record 300's state and
goes on as if it had played everything before.

---

## 9.3 Delta + run length: pictures that only store changes

A 160 × 120 picture at 4 bits per pixel is 9,600 bytes. Two observations
make most frames much smaller:

1. **Most of a frame is the same as the frame before** (a video at 10
   frames a second barely moves between two frames). The frame buffer still
   holds the previous frame, so those pixels just don't need to be written:
   **SKIP**.
2. **Pictures have big areas of one colour** (Bad Apple: all black or all
   white). "80 white pixels" is 2 bytes instead of 10: **FILL**.

Everything else is stored as it is: **COPY**. One byte says which, and how
many pixels:

```
  00nnnnnn            SKIP n+1 pixels (they stay as they are)     1 byte for up to 64 pixels
  01nnnnnn  c         FILL n+1 pixels with colour c                2 bytes for up to 64 pixels
  1nnnnnnn  p p p ..  COPY n+1 pixels, given next, bpp bits each   1 byte + the pixels, up to 128
```

The pixels go row by row (like reading), so a run can go on into the next
row. Example, one 160-pixel row of a 1-bit (Bad Apple) frame, where a
black shape 50 pixels wide moved 20 pixels to the right:

```
 before:  60 white            | 50 black                    | 50 white
 after:   80 white                      | 50 black                    | 30 white
          └ 60 the same ┘└20 now white┘└─ 30 the same ─┘└20 now black┘└ 30 the same ┘
 stored:  SKIP 60 | FILL 20 white | SKIP 30 | FILL 20 black | SKIP 30
          1 byte    2 bytes         1 byte    2 bytes         1 byte     = 7 bytes
```

Raw, that row is 20 bytes (160 pixels, 8 per byte).

(The encoder decides with fixed rules: an unchanged run is only worth a
SKIP if it is at least a few pixels long, a colour run only worth a FILL if
it is longer than the COPY bytes it saves; see `rle_encode` in
`make_game_media.py`.) The first picture of every item has **no SKIPs**: it
can't rely on what an earlier item left in the frame buffer.

How much it saves depends on the video: Bad Apple's 842 frames are 2.0 MB
raw and 0.67 MB stored (3×); the Jevil background loop (34 frames) is
0.16 MB raw and **25 KB** stored; still pictures with big flat areas shrink
2–5×.

**Loops for free:** a record doesn't hold its picture, it holds the picture's
**address** in the flash. The Jevil attack has 403 records (40.3 s of
sound) but only 35 pictures: the first frame whole, and the 34 "changes to
frame k" deltas. Record r points at delta (r mod 34), so the background
loops while the sound plays on, and the loop costs 25 KB instead of 300 KB.

---

## 9.4 The file (`make_game_media.py`)

```
python tools/make_game_media.py          -> media/game_media.bin  (6.8 MB, takes a few minutes)
tools\flash_media.bat media\game_media.bin
```

It reads `PLAN` (items with `keep=True`), puts them in groups (music,
attacks, lose, win), encodes everything, **checks** it (it decodes every
picture back and compares, and checks the ADPCM state stored in the
records), and writes one file. The layout ("TDM2", format 2; the full byte
list is at the top of the script):

```
 BASE (1 MB)    header, 16 bytes   "TDM2", version, number of items,
                                   first item + count of each group, sprite block address
 BASE + 16      directory          16 bytes per item: bpp, frame time, mode (bg / full /
                                   over / panel, dim), number of records, sound bytes per
                                   record, palette address, record address, low water
 ...            per item:          palette | records | pictures
 ...            sprite block       sprite palette | Jevil's 8 poses | 4 faces

 record r (at record address + r * (8 + aud)):
   [ picture address (3) | picture length (2) | ADPCM pred (2) | ADPCM idx (1) ][ aud bytes of sound ]
```

Pictures are stored once each and records point at them. A record with
picture length 0 keeps the picture (music items have no pictures at all).

**Groups instead of fixed numbers.** The header says "the music is items
0–1, the lose items are 5–10, ...". So the plan can gain or lose a song or
a picture without changing the hardware; only the 3 attacks are fixed
(Bad Apple, OIIA, Jevil, the order of `A_APPLE`, `A_OIIA_V`, `A_JEVIL` in
`chaos_pkg`); the script stops with an error if the plan doesn't have them
in that order.

**Sound** is cut with ffmpeg (start, length, fade-out from the plan),
resampled to 16 kHz, encoded (`adpcm_encode`, L83). For a
video at f frames a second a record holds 8000 / f bytes of sound (10 fps:
800 bytes = 0.1 s), so one record = one picture.

**Pictures** go through `media_lab.quantise` (the same palette and green
key as the renders) and `rle_encode` (L139). A
second function, `rle_decode`, does what the FPGA does; `check_item`
(L439) uses it to prove every picture comes back exactly.

**Sprites** (`sprite_block`, L335): Jevil's gif has 8 poses and 7
colours; they get palette entries 1..15 (0 = see-through). The 4 faces
share 240 colours at entries 16..255. Jevil is packed 2 pixels per byte,
the faces 1 byte per pixel: 512 + 9,600 + 4,096 = 14,208 bytes.

`--sim` writes a tiny file with 4 test items and sprites (`sim/game_sim.hex`)
plus the answers the testbench must find (`sim/game_sim_expect.txt`).

---

## 9.5 `adpcm_dec.vhd`, line by line

The decoder from 9.2, in hardware. One code in, the new sample out 3 clocks
later. We have 3,125 clocks per sample (50 MHz / 16 kHz), so there's no
hurry: the work is spread over 3 clocks to keep each clock's logic short.

**Ports** (L31–41): `go` + `code` = decode one code;
`load` + `load_pred` + `load_idx` = jump to a known state (start of an item,
or record r's state when continuing the music). `pcm` = the current sample,
signed 16 bits.

**The step table** (L44–50): the 89 standard sizes. A
constant array becomes a small ROM made of LUTs.

**Clock 0** (L66): on `go`, keep the code and look up the step
for the current `idx`.

**Clock 1** (L72): start the move: step/8, plus step if bit 2 is
set. (`step(14 downto 3)` = step shifted right by 3 = step / 8, free:
it's just wires.)

**Clock 2** (L77–101): add step/2 if bit 1, step/4 if bit 0
(`step(14 downto 1) and (13 downto 0 => c(1))` = "step/2, or 0 if bit 1
is 0": AND-ing every bit with c(1)). Then pred ± move, in 18 bits so it
can't overflow, and **clamp** it back into −32,768..32,767 (a very loud
moment could overshoot; the encoder clamps the same way). Then adapt `idx`
(L92): +2/+4/+6/+8 or −1, clamped to 0..88.

**load** (L104) comes last in the process, so it wins over
everything else in that clock.

---

## 9.6 `media_engine.vhd`, line by line

The engine replaces test 06's `media_player` in the game. Same idea
(header, directory, records, frame buffer, palette, sound ring), but with
format 2, the two decoders, the panel mode and the sprites. It is the
biggest new block, so it is split up here by job.

### Ports (L57–102)

* commands: `play` with `item` and `from_rec` (start record), `stop`.
* `ready` (the file is there), `spr_ok` (sprites loaded), and the group
  numbers from the header (`mus_first`, `mus_n`, ...).
* about the item playing: `busy`, `has_snd`, `pic_ok` (its first picture is
  complete: media_mix waits for this, so you never see half a picture or an
  old picture in new colours), `mode`, `dim_half`, `rec_pos` (the next
  record, saved by media_ctrl to continue the music later).
* the flash pins, as in test 06.
* picture: `x`, `y` in; 3 clocks later `rgb`, `see` (palette index 0) and
  `zone` (where on the picture: 3 = on it; in panel mode 1 = the frame, 2 =
  the dark gap).
* sprites: `j_en`/`j_addr` (a Jevil pixel) and `f_en`/`f_addr` (a face
  pixel) in, `spr_on`/`spr_rgb` out 2 clocks later.
* `pcm`: the sound, 16 bits.

### The memories and the BRAM budget (L570–631)

| memory | size | BRAM (18 Kbit halves) |
|---|---|---|
| frame buffer, 5 banks × 4,096 bytes (L572) | 19,200 pixels × 8 bits | 10 |
| Jevil, 5 banks × 4,096 × 4 bits (L588) | 19,200 pixels × 4 bits | 5 |
| faces (L607) | 4,096 × 8 bits | 2 |
| sound ring | 2,048 × 8 bits | 1 |
| palettes: 0..255 the item, 256..511 the sprites | 512 × 12 bits | 1 |
| **total** | | **19 of 20** |

The chip has 10 BRAM tiles of 36 Kbit, each usable as two 18 Kbit halves.
The game itself uses none. Why banks: a memory of 19,200 bytes would make
Vivado use 8 whole tiles (it rounds up to powers of 2); 5 banks of 4,096
fit 5 tiles exactly (Part 8 explains the trick). Jevil's 8 poses of
48 × 50 = 19,200 pixels too: the same numbers as the frame buffer, by
luck.

**One palette memory, two readers.** A block RAM has two ports. Port A
(L616–621) either writes (while a palette is being loaded) or
reads the picture's colour; port B (L631) reads the sprite colour
from the upper half. While a palette loads, the picture is off the screen
anyway (pic_ok is '0').

### Power-up (E_HDR, E_SPR; L282–330)

Read the 16 header bytes; if they start with "TDM2", read the sprite block
(14,208 bytes, ~5 ms) and send each byte where it belongs by its number
`bi`: bytes 0..511 = sprite palette (2 bytes a colour, into entries
256..511), the next 9,600 = Jevil (2 pixels each: the high nibble is written
when the byte arrives, the low one in the next clock, L311),
the last 4,096 = faces.

### Playing an item (E_IDLE … E_START; L333–406)

`play` and `stop` pulses are remembered (`req_play`, `req_stop`,
L275) and done when the engine is free. Play: read the
16-byte directory entry, then the palette (2^bpp colours), then **E_START**
(L398): the first record's address is

```
  record address + from_rec × (8 + aud)
```

A 16 × 16 bit multiplication: Vivado puts it into one of the chip's 20 DSP
blocks (hardware multipliers, unused until now), so it costs no LUTs. The
ring is emptied and the ADPCM decoder set to 0.

### When to load the next record (E_WAIT, L409)

As in test 06, with one rule for both kinds of sound items:

* **sound** (+ maybe a picture): when fewer than `low water` bytes wait in
  the ring, and (for items with pictures) at the start of a frame. Music
  has low water = 2,048 − 1,024: "load when a whole record fits". Videos
  have 264 bytes (33 ms of sound): the next record comes just before the
  ring runs dry, and its picture appears at a frame start, in step with
  the sound.
* **picture only** (the still pictures): at the next frame start.

A new `play` or `stop` interrupts the waiting.

### Loading one record (E_RH … E_NEXT, L426–484)

Three flash reads in a row, all started right at the frame start:

1. **E_RH**: the 8-byte header: picture address and length, ADPCM state.
   For the first record after E_START (`started = '0'`) the state goes into
   the decoder (L441).
2. **E_PIC**: the picture (if its length isn't 0) into the run-length
   decoder, then wait until it has written its last run (E_PIC_END) and set
   `pic_ok`.
3. **E_SND**: the sound bytes into the ring.

Picture before sound this time: the picture must be written before the
screen's beam gets there (the "beam race" from Part 8), sound has 33 ms to
spare. **E_NEXT** moves to the next record, or ends (`loading` = '0'; the
ring then plays out, and `busy` falls when it's empty).

### The run-length decoder (L495–543)

A second little state machine that runs next to the main one. Flash bytes
arrive in `pb` ("pending byte", `pb_v` = there is one). States:

```
 D_OP    take a byte: SKIP -> wa += n+1 (stay)   FILL -> D_COL   COPY -> D_LIT
 D_COL   take the colour byte                                    -> D_FILL
 D_FILL  write the colour at wa, wa+1, ... (one pixel a clock)   -> D_OP when done
 D_LIT   take a byte of packed pixels                            -> D_UNP
 D_UNP   write its pixels, MSB first, one a clock                -> D_LIT for the next byte,
                                                                    D_OP when the run is done
```

**The speed problem.** A byte arrives every 16 clocks (25 MHz SPI), but a
FILL can be 64 pixels and a COPY 128: 64–128 clocks of writing. Without
care, the next bytes would arrive while the decoder is busy and get lost.
The fix is a new input of `spi_flash`: **`hold`**. While it is '1', the
flash reader doesn't start the next byte; it simply leaves the SPI clock
low (L138 in spi_flash: flash chips don't mind a paused
clock). The engine holds while a byte is waiting in `pb` or arriving right
now (L246). So:

```
 byte k arrives -> pb -> decoder takes it at once (pb empty again)
                         ... and works 64 clocks on a FILL
 byte k+1 arrives (16 clocks later) -> pb, decoder still busy -> hold
 the flash reader waits with SCLK low ... decoder takes byte k+1 -> continue
```

At most one byte is ever waiting, none gets lost, and the decoder works at
full speed: one pixel per clock for FILL and packed COPY bytes. The worst
case is COPY at 256 colours, one byte (17 clocks) per pixel; the beam uses
a frame-buffer pixel every 40 clocks (a row of 160 is shown on 4 screen lines
of 1,600 clocks each), so even then the loader stays well ahead.

### Sound out (L546–565)

Every 3,125 clocks (`SAMPLE_CLKS`, a generic so the testbench can use 100)
one 4-bit code goes into `adpcm_dec`: first the low nibble of the byte at
`rd_ptr`, next time the high nibble, then `rd_ptr` moves on. `fill` counts
the bytes in the ring; `rst` is set in the clocks where the ring is
emptied, so nothing else changes it in that clock. (Test 06's phase
accumulator for any sample rate is gone: everything is 16 kHz now, so a
plain counter does it, with fewer LUTs.)

### The screen (L635–674)

Clock 1: work out the frame buffer address `ra`, and the zone:

* normal (bg / full / over): `ra = (y/4) × 160 + x/4`, as in test 06.
* **panel**: the picture is 96 × 88, drawn 2× at x 430..621, y 286..461:
  `ra = ((y−286)/2) × 96 + (x−430)/2`. 96 = 64 + 32, so "× 96" is two
  shifts and an add, no multiplier. Around it: 2 px dark gap (zone 2) and a
  2 px frame (zone 1), in the colour media_mix chooses.

Clock 2: the frame buffer banks are read. Clock 3: the palette, and `see`
= "this pixel's index is 0" (the jump scares' green screen became index 0).
The sprite reads run alongside: Jevil's nibble and the face byte in clock 2,
then "Jevil if he has a colour here, else the face" picks the sprite palette
entry (L627).

---

## 9.7 `media_ctrl.vhd`: what plays when

A small state machine (L54) with four states:

```
                    game starts                   media attack
   C_IDLE ──────────────────────► C_MUSIC ─────────────────────► C_ATTACK
     ▲                              │  ▲     attack over: music     │
     │                              │  └──── from mus_save ─────────┘
     │ draw                         │ track over: next track (playlist)
     │                              ▼
     └──────────────────────────  C_END  ◄──── game over (from C_MUSIC or C_ATTACK):
                                              a random win / lose item
```

* **A new game** (L91): play music item `mus_first + mus_k`
  from record 0, hide the picture.
* **Game over** (L105): result 1 → a win item, 2 or 4 → a
  lose item, picked at random: `pick` (L68) turns a random byte
  r (0..255) into 0..n−1 by `r × n / 256` (the same trick as
  `rand_range` in chaos_pkg). A draw: silence.
* **Attacked** (L122): from C_MUSIC, first remember where the
  music is: `rec_pos − 2`, because up to 2 records (0.25 s) are still
  waiting in the ring unheard; better to hear a quarter second twice than
  to skip it. Then play `atk_first + media_id`; Jevil (id 2) also sets
  `jevil`.
* **The item has finished** (`busy` = '0', L136): music →
  the next music item (back to the first after the last); attack → the
  music from `mus_save`; end → a video with sound disappears, a still
  picture stays.

`gap` (L86) waits 7 clocks after every command, because the
engine's `busy` only rises a clock after `play`: without it, the very
next clock would see "not busy" and think the new item had already ended.

---

## 9.8 `media_mix.vhd`: the last stage of the picture

### Lining up the pipelines

Every block that draws works on a pixel some clocks after vga_sync announced
its x, y:

```
 clock      0        1                 2                       3                    4
 vga_sync   x, y
 render              stage 1           colour, see_bg, keep
 engine              address, zone     BRAM read               colour, see, zone
 media_mix                                                     A: game colour waits  B: choose -> VGA pins
                                                                  one clock
```

tetris_render's colour is ready after 2 clocks, the engine's after 3. So
media_mix delays the game by one clock (stage A, L188), and in
stage B both are there for the same pixel. hsync and vsync go through the
same registers, so the picture stays where it should; the whole screen is
just 4 pixel clocks "later", which nobody can see.

### Choosing (stage B, L195–221)

| mode | the media pixel is used where | |
|---|---|---|
| 0 bg | `see_bg` (background or empty field cell) and on the picture | dimmed: 3/4 = c/2 + c/4, or 1/2 = c/2 (L113): shifts only |
| 1 full | on the picture and not `keep` (the result / PRESS START bands) | |
| 2 over | on the picture and not `see` (index 0 = the green screen) | |
| 3 panel | the picture; the gap dark grey; the frame gold (won) or red | |
| sprites | wherever `s_on`, on top of everything | |

### Jevil's path (L130–158)

```
  x = 272 + 230 sin(2π t / 6.1 s)        y = 190 + 150 sin(2π t / 3.7 s + 0.6)
```

Two sine waves with different periods: together they draw a "Lissajous"
figure that never quite repeats the same way, so he seems to drift around
the whole screen. In hardware:

* **phase**: a 16-bit number per wave, 65,536 = one full turn. Every frame
  `ph_x` grows by 179 (65,536 / 179 = 366 frames = 6.1 s) and `ph_y` by 295
  (3.7 s). It overflows back to 0 by itself: exactly what a turn does.
* **sine**: `sine()` (L84) uses a table of a quarter wave,
  128 values 0..255 (`QUARTER`, made by `make_quarter` with `ieee.math_real`
  while Vivado builds the design, so the numbers aren't typed in by hand).
  The other three quarters are mirror images: the top 2 bits of the phase
  say which quarter, the next 7 where in it.
* **scaling**: `230 × sine / 256` (−229..229). The multiply only happens
  once per frame, in a little 3-step sequence (`step`), using one DSP block.
* **poses**: every 4th frame `pbase` moves on by 2,400 (one pose = 48 × 50
  pixels): 15 poses a second, as you chose.

**Which pixel of Jevil?** (L163) For a screen pixel inside his
96 × 100 box: `pbase + (dy/2) × 48 + dx/2` (48 = 32 + 16: shifts again),
sent to the engine with `j_en`. He's drawn 2× like everything else.

---

## 9.9 Changes in the game files

### `chaos_pkg.vhd`

* `N_ATTACKS` 9 → 12: `A_APPLE` 9, `A_OIIA_V` 10, `A_JEVIL` 11
  (L73); `A_MEDIA` = 9 = "ids from here on are media
  attacks".
* `MEDIA_COOL` (L95): the sender's wait per media attack, in
  frames: its length from the plan + 600 (10 s). If you change a length in
  the plan, change it here too.
* 6 new banners (INCOMING / SENT for each), so `BAN_SENT` 12, `BAN_BONUS`
  24, `BAN_FAIL` 27 (L113).

### `chaos_task.vhd`: the sender's cool-down

`mcool` (L104) counts down once per frame. When a task
succeeds and the attack is picked (L267): if it's a media attack
but `mcool` isn't 0 yet, or this board has no media file (`media_ok`), a
normal attack is picked instead. Sending a media attack sets `mcool` to its
`MEDIA_COOL`. It's reset when the game ends.

### `chaos_fx.vhd`

An incoming media attack (L126) gives the INCOMING banner and the alarm
sound like every attack, and a pulse `media_hit` with `media_id` = 0..2
for media_ctrl. No timer: the video decides how long.

### `chaos_render.vhd`: bouncers with faces

The bouncers are 32 × 32 now (`BQ`, L73). The loop that finds
the bouncer under (x, y) also remembers **which** one (`hb`), and then
(L349):

```
  face_addr = face × 1024 + (y − by) × 32 + (x − bx)      face = (hb + foff) mod 4
```

Everything is a power of 2, so the address is just the bits side by side
(L352): 2 bits face, 5 bits row, 5 bits column. `foff` is
shuffled at the start of every BOUNCE attack, so the faces move around. The
coloured squares are still drawn in the overlay underneath (that's what
you see without the media file); media_mix puts the face over them. Where
the OIIA cat is, `face_en` is cleared, so the cat stays on top.

### `tetris_render.vhd`

Two new outputs (L420): `see_bg` = this pixel is the screen
background, or an empty field cell (not a block, not the ghost's outline,
not a text band, not the chaos overlay): the bg video may show here.
`keep` = the result / PRESS START bands. The colour logic itself didn't
change, so the blocks stay solid over the video, as you decided after the
renders.

### `tetris_sound.vhd`: real music

The Korobeiniki ROM and its note player are gone. The mixer
(L239) now has 4,096 levels instead of 16:

```
  loudness = 1536 + pcm / 32  (+ 1024 while the effect's square wave is high)
             ^ middle  ^ −1024..+1023
```

and the sigma-delta bucket is 12 bits instead of 4 (same idea as Part 6,
just finer). `pcm / 32` = drop the 5 lowest bits (`pcm(15 downto 5)`).

### `spi_flash.vhd`

Only the `hold` input (L56), with a default of '0', so test 06
still builds unchanged.

### Making room: `text_multi.vhd` and the bouncers

The first build with everything in it **didn't fit**: 7,566 LUTs of
8,000 (95 %), and Vivado's placer gave up ("the unplaced instances require
1,557 slices", 1,505 were free). A synthesis run that keeps every block
separate (`-flatten_hierarchy none`) showed where the space went, and two
blocks had a lot of copies of the same thing:

**12 text layers, 12 fonts.** Every `text_layer` had its own copy of the
font ROM (64 characters × 35 bits, ~45 LUTs plus bit picking). But a pixel
can only be on one line of text at a time. `text_multi` (new file) draws N
lines with ONE font: first find which line (x, y) is on and which character
of it (L80), then look up just that one character
(L99). The line positions come in as generic *lists*
(`int_list`, a new type in `text_pkg`):

```vhdl
u_text : entity work.text_multi
  generic map (N => 9,
               X0S    => (NX0, LX0, LX0, LX0, 90, 78,  254, 272, 266),
               Y0S    => (52,  156, 224, 244, 52, 412, 264, 202, 210), ...
```

The WIN!/LOSE word and GAME OVER overlap on the screen, so there's an
enable per line (`t_en`, L160 of tetris_render): only one of those two
is ever switched on. tetris_render went from 1,172 to 895 LUTs.

**10 bouncers, 10 sets of adders.** Every frame all 10 bouncers moved in
the same clock: 10 × (x ± speed, compare with the walls, y the same). Now
a counter `bk` (L90 of chaos_render) moves one bouncer per clock in
the 10 clocks after `frame_tick` (the screen is blank then), with one
shared set. Same positions, same pictures; ~130 LUTs less.

Together: −440 LUTs, and the frame testbenches' screenshots are **pixel
for pixel the same** as before (compared automatically, see 9.10).

Two smaller things in the same spirit: the sine table in media_mix is
looked up once and shared by x and y (`ph_s`), and the media memories are
marked `ram_style = "block"` (L122 of media_engine). Without
that, Vivado first counted the banner ROM as a block RAM candidate, thought
the block RAM had run out, and moved one Jevil bank into LUTs (+512 LUTs!).

### `top_tetris.vhd` and `pins.xdc`

The flash pins (as test 06: C11, B11, B12, and D10, C10 held high) and
STARTUPE2 for the clock (L366), the four new blocks, and:

* `f_en = face_en and m_spr` (L358): faces only once they're loaded.
* `show = c_show and m_picok`, `jev = c_jev and m_picok and m_spr`: nothing
  appears before its first picture is complete.
* tetris_render's pins now go to media_mix, which drives the real pins.
* `flash_miso` has a default of '1', so the old frame testbenches (no flash
  in them) still work: they read FF..., no "TDM2", no media.
* a generic `USE_STARTUP` (L72): the testbenches set it to false. The
  simulation model of STARTUPE2 has its own little clock inside that never
  stops, so with it the simulator would never finish ("-runall" runs until
  nothing happens any more).

---

## 9.10 Testing it

```
python tools\make_game_media.py --sim
tools\sim.bat tb_media_engine
tools\sim.bat tb_media_ctrl
```

### `sim/tb_media_engine.vhd`

The engine against the pretend flash (`flash_model`, Part 8) holding the
tiny file. Sound samples are compared with what the Python decoder made of
the same bytes. Because the testbench can only see `pcm` *change*, both
lists are compared with repeated values left out. It checks:

1. header + groups + sprites loaded;
2. a sound-only item: all 384 samples;
3. the same item from record 2 (the "continue the music" case): the
   decoder starts from the state in record 2's header, samples 256..383;
4. a picture + sound item: its samples, and 22 pixels after 3 delta
   pictures (so SKIP / FILL / COPY all worked on top of each other);
5. a panel picture: 20 pixels + the frame and gap zones;
6. a 1-bit picture: `see` exactly where the index is 0;
7. 20 Jevil pixels (see-through = off) and 20 face pixels.

```
1. TDM2 header found, groups right, sprites loaded
   item 0: samples 0..383 all right
   item 0 rec 2: samples 256..383 all right
   item 1: samples 0..383 all right
   22 of 22 pixels right after 3 delta pictures
5. panel: 20 of 20 pixels right, frame + gap in place
6. 1-bit over picture: see-through right at 22 of 22 spots
7. sprites: 40 of 40 pixels right
TEST PASSED
```

### `sim/tb_media_ctrl.vhd`

media_ctrl + the engine + the pretend flash, going through a whole game:
music starts, the playlist repeats it, an attack interrupts it, the music
continues from the remembered record, Jevil, a win (the panel picture stays
on screen), a new game, a loss. Every `play` command (item, record) is
written down and compared.

The older testbenches still pass with the new files: `tb_chaos` (the
attacks over the link), `tb_flash_read` (test 06, with the new `hold`
input of spi_flash left at '0'). `tb_tetris_frame` and `tb_chaos_frame`
take their screenshots through the whole new picture path (tetris_render
→ media_mix, with no media file). They look exactly like the game always
did (nothing shifted by the 2 extra clocks), and after the text / bouncer
change (9.9) they were compared with the screenshots from just before it:
**identical, pixel for pixel**.

---

## 9.11 Try it on the board

1. Build the file and write it into the flash (close FPGA Builder first):
   ```
   python tools\make_game_media.py
   tools\flash_media.bat media\game_media.bin
   ```
   Writing 6.8 MB takes a few minutes. Do this on **both** boards.
2. Load the game: `tools\program.bat game` (both boards).
3. Checklist:
   * [ ] start a game: the Teto SV music plays (SW4 on); SW4 off = silent
   * [ ] effects (SW5) still beep over the music
   * [ ] let it run 2:21: the original Tetris theme follows
   * [ ] chaos on both (SW6), versus: finish tasks until a media attack
         comes (banner "SENT: BAD APPLE!" etc.); the rival sees the video
         behind their game, hears its sound, their music stops
   * [ ] after the attack the rival's music continues where it was
   * [ ] you can't send a second media attack until the first is over + 10 s
   * [ ] Jevil floats over the whole screen during his attack
   * [ ] BOUNCERS show the 4 faces
   * [ ] win: yippee video or a picture in the right panel (gold frame)
   * [ ] lose: rickrolls, a jump scare, or a loss picture; WIN!/LOSE and
         PRESS START stay readable
   * [ ] a new game stops whatever was playing
   * [ ] no tearing in the videos, no clicks / gaps in the music

If nothing at all happens (no music): the file isn't in the flash or SW4
is off. `tools\flash_media.bat check media\game_media.bin` compares the
first 64 KB.

---

## 9.12 How big is it?

The game with the media layer, built with `tools\build.bat game`
(`game\build\utilization.txt`, `timing.txt`):

| | before the media (chaos) | now | of the chip |
|---|---|---|---|
| LUTs | 6,200 (77.5 %) | **6,972 (87 %)** | 8,000 |
| flip-flops | 2,064 | 3,079 (19 %) | 16,000 |
| slices (groups of 4 LUTs + 8 flip-flops) | | 1,992 (99.6 %) | 2,000 |
| block RAM tiles | 0 | **10 (100 %)** | 10 |
| DSP blocks | 2 | 3 | 20 |
| timing (WNS, must be ≥ 0) | +4.6 ns | **+3.7 ns** | |

The new blocks, from a synthesis run that keeps every block separate
(the normal report mixes some of them into `vga_sync`):

| block | LUTs | flip-flops |
|---|---|---|
| media_engine (with spi_flash 92, adpcm_dec 121) | 780 | 813 |
| media_mix | 335 | 121 |
| media_ctrl | 170 | 70 |
| text_multi (saved) | −440 | |

What this means:

* **It fits, but the chip is full.** Nearly every slice has something in
  it (99.6 %), and all 10 block RAM tiles are used. A new feature now needs
  something else to get smaller first. Candidates if it ever comes to that:
  the old 64 × 64 ROM cat (the OIIA video does the same job now), the
  banner texts (28 × 20 characters of ROM), or `tetris_core` (2,900 LUTs,
  the biggest block by far).
* **Timing is comfortable:** the slowest path still has 3.7 ns to spare out
  of 20 ns. The extra pipeline stage in media_mix helps here: the media
  colour choice gets a whole clock to itself.
* **Flash:** the media file is 6.83 MB of the 7 MB free (93 %).
