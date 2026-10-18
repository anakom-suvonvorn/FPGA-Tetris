# Test 05: USB serial probe (which pin is which?)

**Why this test exists:** in test 03 the PC got no reply at all. Two possible
reasons: the data never reaches the FPGA, or the FPGA answers on the wrong pin
(the manual's TX/RX labels could be swapped). This design finds out by itself
and tells you on the 7-segment display.

**Files:** `top_uart_probe.vhd` + `uart_rx.vhd`, `uart_tx.vhd`, `debounce.vhd`,
`seg7_scan.vhd`, `common_pkg.vhd`. Ready-built: `build\top_uart_probe.bit`.
Simulated with `tools\sim.bat tb_uart_probe 0` and `... 1` (both PASS).

## Steps

1. Load the design (`tools\load_into_builder.bat` → `05_uart_probe` → Build →
   Program, or `tools\program.bat 05_uart_probe`).
2. The display shows **`00.00`**:
   left two digits = bytes received on pin **F2**, right two = on pin **G1**.
   At this point the FPGA drives neither pin; it only listens.
3. Open PuTTY on COM3, 115200, Flow control **None**. Click into the black
   window and type a few letters.
4. Read the display:

| Display | Meaning | What happens next |
|---|---|---|
| left number goes up, **dot on the far left** | PC talks on F2, the manual is right | the FPGA now answers on G1 |
| right number goes up, **dot on the far right** | PC talks on G1, the manual has TX/RX **swapped** | the FPGA now answers on F2 |
| stays `00.00` | nothing reaches the FPGA | see "Still nothing" below |

5. PuTTY should now show your letters in CAPITALS, and every 3 seconds the
   line `FPGA here: TX on .., RX on ..`. PB3 (middle button) prints it at once.

**Please tell Claude which row of the table you got.** Then we fix
`pins.xdc` of tests 03 and the game for real.

## Still nothing?

* In PuTTY: Connection → Serial → **Flow control: None** (the default
  XON/XOFF is fine too, but RTS/CTS or DSR/DTR would block).
* Close the VS Code serial monitor before opening PuTTY: only one program
  can open COM3 at a time.
* Unplug and replug the USB cable, then load the design again (loading
  happens over channel A; COM3 is channel B of the same chip).

## Why it's safe to try both pins

The USB chip has one output pin (its TXD) and one input pin (its RXD). If the
FPGA drove the pin that is the chip's *output*, two outputs would fight each
other. So the FPGA starts with both pins as inputs (`'Z'` in VHDL = "don't
drive"). Only after it has *heard* the PC on one pin does it start driving the
other one, which must then be the chip's input. A weak pull-up (`PULLUP` in
`pins.xdc`) keeps an undriven pin at '1' so noise can't fake a byte.
