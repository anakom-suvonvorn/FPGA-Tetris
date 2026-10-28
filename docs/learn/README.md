# Learn VHDL + Vivado (for this project)

Written for someone who already designs with schematics (Labs 1–10) but has
never written VHDL by hand or opened the Vivado GUI. Read in order:

1. [VHDL from zero](01_vhdl_basics.md): the language, translated from
   schematic thinking (entity = symbol, signal = wire, process(clk) =
   flip-flops, ...), plus our house rules and common errors.
2. [The building blocks, line by line](02_blocks_walkthrough.md):
   `common_pkg`, `debounce`, `seg7_scan`, `vga_sync`, `uart_tx`, `uart_rx`,
   `switch_filter`.
3. [The tests and testbenches, line by line](03_tests_walkthrough.md):
   the 5 hardware tests, `project.txt`, `pins.xdc`, and the 3 testbenches.
4. [Vivado](04_vivado.md): opening our designs in the GUI, schematic view,
   simulation waveforms, synthesis, timing (WNS), programming.
5. [The game, line by line](05_game_walkthrough.md): how the Tetris
   design works: field storage, the "try with one collision checker" idea,
   every state of the game state machine, the 2-stage renderer, and the
   robot testbench.
6. [Versus mode, line by line](06_versus_walkthrough.md): the board-to-board
   link and its 1-byte messages, garbage (cancel, send, rise), win / lose /
   draw, the on-screen font and text, music + sound effects (sigma-delta),
   the two-board testbench and the PC fake opponent.
7. [The CHAOS layer, line by line](07_chaos_walkthrough.md): slide-switch
   tasks (incl. HEX), attacks over the link (incl. LOCK), bonuses, random time
   ranges, mirror / flip / blind / bouncers /
   the spinning OIIA cat (removed again in Part 9), and how they are tested.
8. [Pictures and sound from the flash chip](08_flash_walkthrough.md): what
   the SPI flash is, talking SPI, the STARTUPE2 clock trick, how pictures
   (palette, bits per pixel) and sound (8-bit samples) are stored, the
   media player (frame buffer, sound ring, pacing, tearing), test 06 and the
   pretend-flash testbench, and what fits in 7 MB.
9. [The media in the game, line by line](09_media_walkthrough.md): ADPCM
   sound in 4 bits, "delta + run length" pictures, the flash file
   (`make_game_media.py`), the media engine, what plays when, the last
   stage of the picture (Jevil's path), making it fit in the chip, and what
   changed after the first test on the board.
10. [Visual guide](tetris_visual.html) (download and open in a browser):
   interactive diagrams for Parts 5 to 9.
11. [Media from zero](media_visual.html) (download and open in a browser):
   Parts 8 and 9 explained from scratch, step by step: what memory and block
   RAM are, the media file byte by byte (real numbers from the file), how it
   gets into the flash, SPI clock by clock, all seven state machines, the frame
   buffer, the sound ring, ADPCM, timing against the screen beam, what plays
   when, and a code reader where clicking any short name tells you what it
   means and every line that uses it. The "reference" button puts the code
   reader, the names and the words in a panel beside the text.

Quick start for Vivado:

```bat
cd /d D:\setup\assignment
tools\vivado_gui.bat 05_uart_probe tb_uart_probe
```

Then: Flow Navigator → SIMULATION → Run Behavioral Simulation.

See also `docs\concepts.md` for how VGA, serial, J5, clocks and timing work in
general.
