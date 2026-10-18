# Test 03: Serial echo with the PC

**Goal:** prove the serial transmitter/receiver work on real hardware, using
the USB serial port that's already in the board's USB cable. (What "serial
echo" means: `docs\concepts.md` §6–7.)

**Files:** `top_uart_echo.vhd` + `uart_rx.vhd`, `uart_tx.vhd`, `debounce.vhd`,
`seg7_scan.vhd`, `common_pkg.vhd`. Ready-built: `build\top_uart_echo.bit`.

## Steps

1. Load the design: `tools\program.bat 03_uart_echo` (or via the Builder).
2. Find the board's COM port: **Device Manager → Ports (COM & LPT) →
   "USB Serial Port (COMx)"**. Note the number (e.g. COM5).
3. Open **PuTTY**:
   * Connection type: **Serial**
   * Serial line: **COM5** (yours)
   * Speed: **115200**
   * (Category → Connection → Serial: 8 data bits, 1 stop bit, parity None,
     flow control **None**)
   * Click **Open**: a black window appears.
4. Type `hello`. You should see **`HELLO`** appear (capitals = the FPGA
   processed it).
5. Press **Enter**: the cursor moves to a new line.
6. Press **PB3** (SW18, middle button): `Hello from the FPGA!` appears.
7. Watch the 7-segment display while typing:
   * left 2 digits = how many bytes the FPGA has received (hex);
   * right 2 digits = the last byte, as a hex ASCII code
     (`a` = 61, `A` = 41, `1` = 31, Enter = 0d).

## Troubleshooting

* **Nothing appears when typing:** (this happened on 16 Oct) load
  **test 05 (`05_uart_probe`)**: it works out by itself whether the PC talks
  on F2 or G1 and shows it on the display. Other causes:
  * wrong COM port or speed in PuTTY;
  * flow control not set to None;
  * the display's counter tells you which half is broken: if it **counts up**,
    the PC→FPGA direction works and the problem is FPGA→PC (pin F2); if it
    **doesn't count**, the PC→FPGA direction (pin G1) or PuTTY is the problem.
* **Garbage characters:** speed is not 115200.
* **No "USB Serial Port" in Device Manager:** the serial half of the board's
  USB chip has no driver. Install the **FTDI VCP driver** (ftdichip.com →
  Drivers → VCP). Only update the device that is *not* the one the Builder
  uses for programming. If programming from the Builder stops working
  afterwards, run the Builder's "ตั้งไดรเวอร์ USB" button again.
* **PuTTY says it can't open the port:** another program has it open; close
  other terminals or Arduino IDE.
* You can leave PuTTY open while reprogramming; the two channels are separate.

## How the code works

* `uart_rx` turns the serial wire into bytes; each good byte gives a
  one-clock `valid` pulse. On that pulse we:
  count it, store it for the display, and queue it to be sent back
  (`echo_pending`) after converting a–z to A–Z. If it was Enter (0x0D), a line
  feed (0x0A) is queued too.
* The send logic runs every clock: when `uart_tx` is free (`busy = '0'`), it
  sends the next waiting byte. Priority: echo, then line feed, then the next
  character of the button message. The extra check `tx_start = '0'` is there
  because `busy` only rises one clock *after* `start`, so we must not start
  twice in a row.
* The message `"Hello from the FPGA!"` is a VHDL `string` constant. Each
  character is converted to its ASCII code with `character'pos(c)`, and Vivado
  builds a small ROM from it.

## Later: the PC as the other player

Once the game is running, it can use this same serial port. Typing a byte in
PuTTY (or sending it with a small Python script) will look to the game exactly
like a message from the other board, so we can test garbage rows and win/lose
with one board.
