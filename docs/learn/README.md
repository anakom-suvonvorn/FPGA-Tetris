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
7. [Visual guide](tetris_visual.html) (open in a browser, or
   https://claude.ai/artifact/28Mdg6vDhCJzwXsmgR6Cdb): interactive diagrams
   for Parts 5 and 6.

Quick start for Vivado:

```bat
cd /d D:\setup\assignment
tools\vivado_gui.bat 05_uart_probe tb_uart_probe
```

Then: Flow Navigator → SIMULATION → Run Behavioral Simulation.

See also `docs\concepts.md` for how VGA, serial, J5, clocks and timing work in
general.
