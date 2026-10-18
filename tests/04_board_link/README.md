# Test 04: Board-to-board link

**Goal:** two boards exchange bytes over jumper wires on J5. This is the
exact link the versus game will use.

Do test 02 first: it confirms that J5 pin 5 is L14 and pin 6 is M13.

**Files:** `top_board_link.vhd` + `uart_rx.vhd`, `uart_tx.vhd`, `seg7_scan.vhd`,
`common_pkg.vhd`. Ready-built: `build\top_board_link.bit`.

## You need

* 2 boards, both loaded with this same design;
* 3 female-to-female jumper wires;
* 2 resistors, about 330 Ω (220 Ω–1 kΩ is fine).

## Step 1: one board, loopback

1. Load the design into one board: `tools\program.bat 04_board_link`.
2. The display shows `xx.--`: left = this board's switches (SW10…SW2,
   in hex), right = `--` because nothing is being received.
3. Connect **J5 pin 5 to J5 pin 6** on the same board (through a resistor).
4. The right two digits now show the same value as the left. Flip some of the
   8 right-hand switches: both halves change together.

That proves the transmitter and receiver both work through the J5 pins.

## Step 2: two boards

Wire them like this (see `docs\concepts.md` §9 for why):

```
   Board A                                    Board B
   J5 pin 5  (TX) ---[330 Ω]--------------->  J5 pin 6  (RX)
   J5 pin 6  (RX) <---------------[330 Ω]---  J5 pin 5  (TX)
   J5 pin 2  (GND) -------------------------  J5 pin 2  (GND)
```

* Board A's display, right half = Board B's switches, and vice versa.
* Pull any wire: the right half of the affected board shows `--` within a
  quarter of a second, and comes back when you reconnect it.

## Troubleshooting

* `--` with the loopback wire: wrong header pin (re-check with test 02), or
  the wire is on pins 5/6 of the wrong row.
* Works in loopback but not between boards: TX and RX not crossed, or the
  ground wire is missing.
* Right half shows a value, but the wrong one: usually a missing ground wire
  (the signal is "floating").

## How the code works

* Every 50 ms (a counter of 2,500,000 clocks) the board sends its 8-switch
  value through `uart_tx` on `link_tx` (J5 pin 5).
* `uart_rx` on `link_rx` (J5 pin 6) stores each received byte. A `silence`
  counter is reset on every byte; if it reaches 0.25 s, `link_ok` goes low
  and the display shows `--`. The game will use the same idea to detect a
  disconnected cable.
* Both boards run the identical design, which is also how the game will work:
  one design, loaded into both boards.

## What changes in the game

Instead of the switch value, the game will send short messages ("I cleared 2
lines", "I lost", "ready", ...), with a simple check so a glitch can't be
misread. The wires, `uart_tx` and `uart_rx` stay exactly as tested here.
