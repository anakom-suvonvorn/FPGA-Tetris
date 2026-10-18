# Part 4: Using Vivado (the GUI), from zero

You've been using Vivado all along: the TA's FPGA Builder runs a hidden copy
of it in "batch mode" (no window) and only shows you "done" or "error". The
full Vivado at `D:\AMDDesignTools\2025.2\Vivado` does the same work, but
lets you **see** every step:

* your VHDL drawn back as a **schematic** (great for checking your code
  means what you think);
* **simulation waveforms**, a logic analyser for your design before it
  touches the board;
* **reports**: how much of the chip you use and whether you're fast enough;
* the chip itself after place & route.

---

## 4.0 The flow (what happens to your VHDL)

```
 your .vhd files + pins.xdc
        │
        ▼  ELABORATION    parse the VHDL, connect the hierarchy
   RTL schematic          (generic boxes: registers, adders, muxes)
        │
        ▼  SYNTHESIS      turn it into the FPGA's real parts:
   netlist                LUTs (6-input look-up tables = any logic),
        │                 FDRE (flip-flops), CARRY4 (fast adders), IOBs (pins)
        ▼  IMPLEMENTATION
   placed & routed        choose WHERE each LUT/FF goes on the chip (place)
        │                 and which wires connect them (route); check timing
        ▼  GENERATE BITSTREAM
   .bit file              the configuration that sets every switch in the chip
        │
        ▼  PROGRAM        send .bit over USB (FPGA Builder / tools\program.bat)
   board
```

The FPGA Builder runs exactly these steps. `tools\build.bat` too, plus it
prints the timing result (WNS). The GUI is the same engine with windows.

Simulation is a separate side branch: it runs your VHDL on the PC, with a
testbench pretending to be the outside world. No board, no synthesis needed.

---

## 4.1 Open one of our designs (the easy way)

We have a script that makes a Vivado project for any test and opens it. In a
Command Prompt (or VS Code terminal) in `D:\setup\assignment`:

```bat
tools\vivado_gui.bat 05_uart_probe tb_uart_probe
```

First argument = design folder, second (optional) = testbench from `sim\`.
Others you can use:

```bat
tools\vivado_gui.bat 01_vga_bars tb_vga_frame
tools\vivado_gui.bat 03_uart_echo tb_uart_loop
tools\vivado_gui.bat 02_j5_pin_finder
```

It creates `vivado\<design>\<design>.xpr` (a throw-away folder, ignored by
git) and opens it. The VHDL files are **linked, not copied**: if you edit
`src\common\seg7_scan.vhd` in VS Code, Vivado uses the edited file. Running
the script again re-creates the project from scratch; your code is safe.

Vivado takes 20–40 s to open. Ignore the long list of "Board part ... not
available" warnings at the start, they're about boards we don't have.

## 4.2 Making a project by hand (so you know what the script does)

1. Start Vivado (Start menu → Vivado 2025.2). **Create Project** → Next.
2. Name `my_test`, location e.g. `D:\setup\assignment\vivado`. **No spaces
   and no Thai in the path.** Tick "Create project subdirectory".
3. **RTL Project**. Leave "Do not specify sources at this time" unticked.
4. **Add Sources** → Add Files → pick the `.vhd` files (e.g. everything listed
   in a `project.txt`). **Untick "Copy sources into project"** (otherwise
   Vivado edits a private copy and your VS Code edits are ignored). Target
   language VHDL.
5. **Add Constraints** → Add Files → the test's `pins.xdc`. Again don't copy.
6. **Default Part** → search `xc7s15ftgb196` → choose
   **xc7s15ftgb196-1**. (This is our chip: Spartan-7, 15k cells, FTGB196
   package, speed grade -1.)
7. Finish.

In the Sources window, right-click the top file → **Set as Top** if it isn't
bold already. To add a testbench: Sources → **+** → "Add or create simulation
sources" → pick the `sim\tb_*.vhd` file → Finish. Right-click it under
"Simulation Sources" → Set as Top.

---

## 4.3 Tour of the window

```
┌───────────────┬──────────────────────────────┬──────────────────────┐
│ FLOW          │ SOURCES                      │                      │
│ NAVIGATOR     │  Design Sources              │  (main area:         │
│               │   └ top_uart_probe (bold=top)│   code editor,       │
│ PROJECT MGR   │      ├ u_rx_f2 : uart_rx     │   schematic,         │
│ IP INTEGRATOR │      ├ u_tx : uart_tx        │   waveform,          │
│ SIMULATION    │      ...                     │   reports)           │
│ RTL ANALYSIS  │  Constraints  └ pins.xdc     │                      │
│ SYNTHESIS     │  Simulation Sources          │                      │
│ IMPLEMENTATION│   └ tb_uart_probe            │                      │
│ PROGRAM&DEBUG ├──────────────────────────────┤                      │
│               │ PROPERTIES (of what you      │                      │
│               │ clicked)                     │                      │
├───────────────┴──────────────────────────────┴──────────────────────┤
│ Tcl Console │ Messages │ Log │ Reports │ Design Runs                 │
└─────────────────────────────────────────────────────────────────────┘
```

* **Flow Navigator** (left): the buttons for each step, top to bottom in
  flow order.
* **Sources → Hierarchy**: the instance tree, exactly the "which block is
  inside which" structure from Part 1 §1.13. Double-click to open the file.
  A **?** icon = a file is missing / an entity isn't found.
* **Sources → Compile Order**: the order Vivado will compile in (it works it
  out itself).
* **Messages**: errors (red), critical warnings (orange), warnings. Click a
  message to jump to the line.
* **Tcl Console**: every button press is really a Tcl command, printed here.
  You can type commands too.

---

## 4.4 RTL Analysis: see your VHDL as a schematic

**Flow Navigator → RTL ANALYSIS → Open Elaborated Design** (or "Schematic"
under it). After a few seconds a schematic opens.

* Boxes with names like `u_seg`, `u_rx_f2` are your instances. **Double-click
  one** (or click the + in its corner) to look inside.
* Inside you'll see generic parts: `RTL_REG` (flip-flops/registers),
  `RTL_ADD` (adders), `RTL_MUX`, `RTL_EQ` (comparators), `RTL_AND`, `RTL_INV`,
  `RTL_ROM`.
* Click a wire to highlight it everywhere; Ctrl+click to select several.
* Toolbar: **Zoom Fit** (F) and the back/forward arrows.

**Try it:** open `u_seg` (seg7_scan). You should find: an 18-bit `RTL_REG`
(`cnt`) with an `RTL_ADD` feeding it back (the counter), two `RTL_MUX`es on
`sel` (glyph and dot), the decoder logic into the 4-bit `dig_r` register, and
8 inverters into `seg_r`. Compare it with the ASCII drawing in Part 2 §2.3 and
with your Lab 7 `display` schematic. This is the fastest way to check "did I
describe the circuit I meant?".

If elaboration fails, the Messages tab shows the VHDL error with file + line
(Part 1 §1.16 explains the common ones).

---

## 4.5 Simulation: a logic analyser on the PC

**Flow Navigator → SIMULATION → Run Simulation → Run Behavioral Simulation.**

Vivado compiles the testbench + design and runs it. Our testbenches stop by
themselves (the project is set to "run all"), so it runs to the end and you'll
see the `report` lines in the **Tcl Console**:

```
Note: reply byte 0 ok: 65
Note: reply byte 1 ok: 70
Note: TEST PASSED (PATTERN 0): the board answered on the right pin
```

Then the **waveform window** shows the testbench's signals.

### Reading the waveform

* Left column: signal names; right: their value over time. A single wire is
  a line (high/low); a bus is a band with the value written in it.
* **Zoom Fit** (the magnifier with the square, or Ctrl+0) shows the whole
  run. Scroll wheel + Ctrl = zoom; click to place the yellow cursor and read
  values at that moment in the Name/Value columns.
* Bus format: right-click a bus → **Radix** → Hexadecimal / Unsigned
  Decimal / ASCII (handy for UART bytes).
* Normal values are drawn in green. **Red** = `'X'` (two drivers fighting, or
  unknown) or `'U'` (never assigned, e.g. a register with no initial value):
  almost always a bug. A line in the **middle** of the row = `'Z'` (nobody
  driving: expected on our `inout` pins while they're listening).

### Looking inside the design

At first only the testbench's own signals are shown. To see the inside:

1. In the **Scope** panel (left), expand `tb_uart_probe` → `dut` → e.g.
   `u_rx_f2`.
2. The **Objects** panel now lists that block's signals (`state`, `cnt`,
   `shreg`, ...). Drag them into the waveform.
3. They show no history yet (they weren't recorded). Press **Restart**
   (the |◀ button), then **Run All** (▶ with no number) to run again.
   Tip: type `log_wave -r /` in the Tcl Console before running to record
   every signal in the design; then anything you drag in later already has
   its history.

Good things to look at:

* `tb_uart_probe`: `pin_f2` (the 'a' arriving: start bit, bits 1,0,0,0,0,1,1,0
  LSB first, stop bit), then inside `dut`: `tx_on_g1` going high, `pin_g1`
  changing from `Z` to the reply.
* `u_rx_f2/state` stepping S_IDLE → S_START → S_DATA → S_STOP; `shreg`
  filling up bit by bit.

### Running for a set time

The toolbar box next to "Run for" lets you enter e.g. `100 us` and run just
that much more. Useful for a testbench that never ends by itself.

### After editing VHDL

Click **Relaunch Simulation** (circular arrow in the simulation toolbar). It
recompiles and runs again with the same waveform setup. To keep your chosen
signals for next time: **File → Simulation Waveform → Save Configuration As**
(`.wcfg`) and say Yes to adding it to the project.

### Generics (e.g. which VGA picture)

`tb_vga_frame` has a generic `PATTERN` (0..3). To change it: Flow Navigator →
**Settings** → Simulation → **Elaboration** tab → *More Options*:
`-generic_top "PATTERN=0"`. The picture it captures is written to
`vivado\01_vga_bars\01_vga_bars.sim\sim_1\behav\xsim\frame.ppm` (open it
with `python tools\ppm2png.py <that file> out.png`). This testbench simulates
a whole 1/60 s frame, so it takes a minute or two; don't record all signals
(`log_wave -r /`) for it, the file would be huge.

(The command-line way, `tools\sim.bat tb_vga_frame 0`, does the same and
converts the picture automatically.)

---

## 4.6 Synthesis

**Flow Navigator → SYNTHESIS → Run Synthesis** (OK on the dialog). It runs in
the background; the top-right corner shows progress. When it finishes, pick
**Open Synthesized Design**.

* **Schematic** now shows the *real* FPGA parts: `LUT1`..`LUT6`, `FDRE`
  (flip-flop with enable), `CARRY4` (the fast-carry chain used by counters),
  `IBUF`/`OBUF`/`IOBUF` (pins; `IOBUF` = our tri-state `inout` pins),
  `BUFG` (the global clock buffer).
* **Report Utilization** (under Open Synthesized Design): how many LUTs/FFs
  you use out of 8,000 / 16,000. Our tests use under 3%. The full game should
  stay well under 50%.
* Messages worth reading after synthesis:
  * `inferring latch for variable/signal ...`: a combinational process misses
    an assignment (Part 1 §1.7). Fix it.
  * `multi-driven net`: the same signal assigned in two places. Fix it.
  * `... is unconnected` / `... has no load, removed`: something you wrote
    isn't used, so it was optimised away. Fine if expected, a hint if not.
  * `FSM with state register ... is not having reset`: harmless for us
    (initial values are loaded at configuration).

---

## 4.7 Implementation and timing

**Run Implementation**, then **Open Implemented Design**.

* The **Device** view shows the chip: the highlighted cells are your design.
  Not needed for anything, but it makes the "place" step visible.
* **Report Timing Summary** (under Open Implemented Design). The numbers:

| Name | Meaning | Must be |
|---|---|---|
| **WNS** (Worst Negative Slack) | for the slowest path between two flip-flops: how much time is *left over* in the 20 ns clock period | **≥ 0**. Ours: about +14.6 ns, so the slowest path needs ~5.4 ns of the 20 |
| TNS | sum of all negative slacks | 0 |
| **WHS** (Worst Hold Slack) | data must not arrive *too early* either | ≥ 0 |
| Failing endpoints | how many paths fail | 0 |

If WNS goes negative (it can, once the game has big combinational logic,
e.g. a long chain of comparisons in the drawing process), click the failing
path: Vivado shows which flip-flop to which, through which logic. The fix is
usually to put a register in the middle (pipelining) or simplify the logic.

The TA Builder never shows this. A design with negative WNS may *mostly*
work and fail randomly, which is the worst kind of bug in a demo. So check
it before the final build (`tools\build.bat` prints it too).

---

## 4.8 Bitstream and programming the board

**Generate Bitstream** → the file lands in
`vivado\<design>\<design>.runs\impl_1\<top>.bit`.

**Programming:** Vivado's **Hardware Manager** (Open Target → Auto Connect)
will most likely **not** find the board on your PC. The FPGA Builder's setup
replaced the driver of the USB chip's JTAG half with WinUSB (that's the
"Digilent USB Device" in Device Manager), which openFPGALoader needs but
Vivado's hardware server can't use. **Don't change the driver**, or the
Builder stops working. Program with what already works:

* FPGA Builder → Program → choose the `.bit` file, or
* `tools\program.bat 05_uart_probe` (loads `tests\05_uart_probe\build\*.bit`,
  which `tools\build.bat` makes), or
* `tools\program.bat path\to\file.bit` for any `.bit` file, e.g. one from
  the Vivado GUI.

---

## 4.9 The workflow we recommend

| Step | Tool |
|---|---|
| Write / edit VHDL | VS Code (with a VHDL extension for colours) |
| Check it compiles, look at the schematic | Vivado GUI: Open Elaborated Design |
| Check it works | testbench + Vivado simulation (or `tools\sim.bat`) |
| Build `.bit` + timing | `tools\build.bat <design>` (or Vivado: Generate Bitstream) |
| Load into the board | FPGA Builder Program, or `tools\program.bat <design>` |

Simulation first, board second: a bug is 10× easier to find in a waveform
than on the board, where you can't see inside.

---

## 4.10 Exercises

1. `tools\vivado_gui.bat 03_uart_echo tb_uart_loop`. Run the simulation, find
   `line` (the wire between tx and rx) in the waveform, zoom on the first
   byte (0x55 = `01010101`, a perfect square wave on the wire after the start
   bit). Set the cursor at the start and the end of one bit: is it 8.68 µs
   (= 1/115,200)?
2. Open the Elaborated Design of `02_j5_pin_finder` and find the three
   `debounce` instances and the 4-to-16 decoder feeding `j5_r`.
3. Run synthesis on `01_vga_bars` and open Report Utilization. How many LUTs,
   how many FFs? Which instance uses the most? (Tip: the report has a
   "hierarchical" option: `report_utilization -hierarchical` in the Tcl
   Console.)
4. In `seg7_scan.vhd`, change the counter to 16 bits (and `sel` to bits
   15..14, the blank check to 13..10). Simulate or build: the display now
   scans 4× faster. (Then change it back.)

Next: [Part 5: the game, line by line](05_game_walkthrough.md) · [index](README.md)
