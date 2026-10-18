# Test 06: pictures, animation and sound from the SPI flash

**Why this test exists:** the FPGA has only 45 KB of memory inside (block
RAM). A video, a song or even a few pictures don't fit. The board has an 8 MB
**flash chip**: the one the FPGA loads its design from at power-up. About
7 MB of it is free. This test checks, on the real board, that our design can
read that chip fast enough and without errors, and shows what pictures,
animations and sound from it look and sound like. **The results decide what
media goes into the game** (see "Deciding" below).

Explained from zero in [docs/learn/08_flash_walkthrough.md](../../docs/learn/08_flash_walkthrough.md).

**Files:** `top_flash_read.vhd` + `src/media/spi_flash.vhd`,
`src/media/media_player.vhd`, and `vga_sync`, `debounce`, `seg7_scan`,
`text_layer`, `text_pkg`, `common_pkg`. Ready-built: `build\top_flash_read.bit`
(1,749 LUTs, 6 of 10 BRAM tiles, timing met by 6.9 ns).
Simulated with a pretend flash chip: `tools\sim.bat tb_flash_read` (PASS).
`screenshot_sim.png` is the colour test card as the simulation drew it.

## Steps

You need: the board on USB, a VGA monitor, and for the sound, headphones or
speakers in the audio jack. Close FPGA Builder first (it shares the cable).

1. **Make the media file** (once). In a terminal in the `assignment` folder:

   ```
   python tools\make_media.py media\media.bin --demo
   ```

   It prints a table of 5 demo items (~1.5 MB). `media\media.bin` is already
   in git, so you can skip this step unless you change something.

2. **Write it into the flash** (once; it stays there when the power is off):

   ```
   tools\flash_media.bat media\media.bin
   ```

   openFPGALoader first loads a helper design into the FPGA, then erases and
   writes the flash from 1 MB on. ~1.5 MB takes about half a minute.
   Optional: `tools\flash_media.bat check media\media.bin` reads the first
   64 KB back and should say `FLASH CONTENTS OK`.

3. **Load the test** (temporary, like every other test):

   ```
   tools\program.bat 06_flash_read
   ```

4. Look at the screen and the 7-segment display, then go through the
   checklist below.

## Controls

| | |
|---|---|
| SW14 left / SW20 right | previous / next item (starts playing it) |
| SW18 centre | play the item again / stop |
| SW16 top | **VERIFY**: read the 256 KB test block, count wrong bytes |
| SW23 bottom | hide / show the text |
| SW2, SW4 | SPI clock: both off = 25 MHz, SW2 = 12.5, SW4 = 6.25, both = 3.125 MHz |
| SW5 | sound on (audio jack) |

7-segment display: the chip's ID, `6017`. Right dot = media file found, the
dot next to it = an item is playing.

## Checklist (please tell Claude what you got)

| # | Check | Good result | If not |
|---|---|---|---|
| 1 | Line 1 / 7-segment | `ID 016017 S25FL064L 8 MB`, display `6017` | `FFFFFF` or `000000`: the chip doesn't answer. CCLK/STARTUPE2 or pin problem, tell Claude |
| 2 | Line 2 | `MEDIA FILE OK ITEMS 05` | `NO MEDIA HEAD FFFFFFFF`: step 2 didn't write (or wrote elsewhere). Any other HEAD value: tell Claude the 8 digits |
| 3 | Item 0 `COLOUR TEST` | 8 colour bars, a grey ramp, a rainbow, a checkerboard, sharp edges (like `screenshot_sim.png`) | stripes / noise / shifted columns = read errors: try a slower SPI clock (SW2) |
| 4 | Line 4, `LOAD` | about `006.1 MS` at 25 MHz for item 0 | much longer = something's slow |
| 5 | Top button (VERIFY), at 25 MHz | `VERIFY 0000 BAD`, time about `0084 MS` | any BAD > 0: try SW2 (12.5 MHz) and SW4 (6.25), note which speed gives 0 |
| 6 | Item 1 `BALL 16 COLOURS` | smooth bouncing ball, 20 frames a second | flicker or tearing (a horizontal cut through the ball) |
| 7 | Item 2 `1 BIT 30 FPS` | black and white shape moving smoothly (Bad Apple style) | |
| 8 | Item 3 `FLASH + BEEP` (sound on) | the screen flashes white **at the same moment** as each beep; line 5 stays `0000` | beep before/after the flash, or the count goes up |
| 9 | Item 4 `TUNE 8 KHZ` | a short tune plays (dark blue screen: sound only) | silence / noise / crackles |
| 10 | Try items 1 and 3 at 3.125 MHz (both switches) | probably tearing on item 1 and the sound running dry on item 3 | that's the expected limit, not a bug |

## Deciding what media the game gets

Speed is not the problem: at 25 MHz the flash gives 3.1 MB a second, and even
a full-colour frame loads in 6 ms (a screen frame lasts 16.7 ms). **Space
is:** 7 MB in total. Every picture is 160 x 120 (shown 4x bigger). Costs:

| what | bytes | 7 MB lasts |
|---|---|---|
| sound, 8,000 samples/s | 8 KB per second | 15 minutes |
| picture, 1 bit (2 colours) | 2.4 KB per frame | at 15 fps: 3.4 minutes |
| picture, 2 bits (4 colours) | 4.8 KB per frame | at 15 fps: 1.7 minutes |
| picture, 4 bits (16 colours) | 9.6 KB per frame | at 15 fps: 51 s, at 10 fps: 76 s |
| picture, 8 bits (256 colours) | 19.2 KB per frame | at 15 fps: 25 s; a still image is 19 KB |

Examples: full Bad Apple (3 min 39 s) at 1 bit + sound only fits at 10 fps
and then nothing else fits. A 20 s rickroll at 4 bits, 10 fps + sound is
2.1 MB. A 6 s jump scare at 8 bits, 10 fps + sound is 1.2 MB. Still pictures
and sound effects are cheap. Pick lengths, colours and frame rates with this
table; `make_media.py` prints the real sizes for your files.

## Your own files

```
python tools\make_media.py media\mine.bin --item "av:rick.mp4,bpp=4,fps=10,seconds=20,name=RICK" --item "image:cat.png" --item "sound:oiia.mp3,seconds=3"
tools\flash_media.bat media\mine.bin
```

Kinds: `image`, `video` (no sound), `av` (picture + sound), `sound`. Options:
`bpp` (1/2/4/8), `fps` (at most 30 with sound), `rate` (sound samples a
second, default 8000), `start` and `seconds` (which part of the file; 0 = all),
`loop=1`, `name` (16 characters). Videos and sounds need ffmpeg (installed).
