"""
fake_opponent.py - the PC pretends to be the second board (versus mode test)

Set slide switch SW22 ON on the board (link over USB instead of the J5 cable),
close PuTTY / the VS Code serial monitor, then run:

    python tools\\fake_opponent.py COM3

It sends a heartbeat 10 times a second (so the board shows LINKED), prints
every message the board sends, and lets you type commands:

    s        send START   (the board starts a round)
    g 3      send 3 garbage lines
    l        send LOST    (the board wins)
    h 12     pretend my stack is 12 rows high (the RIVAL bar)
    a        auto mode on/off: stack grows, random garbage every few seconds
    q        quit

Message format (same as src/game/versus_link.vhd): one byte,
bits 7..5 = type, bits 4..0 = value.
    type 0 HEARTBEAT (value = stack height)   type 1 GARBAGE (value = lines)
    type 2 LOST                               type 3 START
"""
import random
import sys
import threading
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial is missing:  python -m pip install pyserial")

T_HEARTBEAT, T_GARBAGE, T_LOST, T_START = 0, 1, 2, 3
NAMES = {0: "HEARTBEAT", 1: "GARBAGE", 2: "LOST", 3: "START"}


def msg(t, v=0):
    return bytes([(t << 5) | (v & 0x1F)])


class Opponent:
    def __init__(self, port):
        self.ser = serial.Serial(port, 115200, timeout=0.05)
        self.height = 0
        self.auto = False
        self.running = True
        self.playing = False
        self.lock = threading.Lock()
        self.last_hb_height = None

    def send(self, t, v=0):
        with self.lock:
            self.ser.write(msg(t, v))

    def heartbeat_loop(self):
        next_garbage = time.time() + 6
        while self.running:
            self.send(T_HEARTBEAT, self.height)
            if self.auto and self.playing:
                if random.random() < 0.05 and self.height < 20:
                    self.height += 1                        # my stack slowly grows
                if time.time() > next_garbage:
                    n = random.choice([1, 1, 2, 4])
                    self.send(T_GARBAGE, n)
                    print(f"\n  -> sent {n} garbage (auto)")
                    next_garbage = time.time() + random.uniform(4, 9)
                if self.height >= 20:
                    self.send(T_LOST)
                    print("\n  -> my stack reached the top: sent LOST (the board should show WIN!)")
                    self.playing = False
            time.sleep(0.1)

    def receive_loop(self):
        while self.running:
            data = self.ser.read(16)
            for b in data:
                t, v = b >> 5, b & 0x1F
                if t == T_HEARTBEAT:
                    if v != self.last_hb_height:              # only print changes
                        print(f"  <- board stack height {v}")
                        self.last_hb_height = v
                elif t == T_GARBAGE:
                    print(f"  <- board sends {v} garbage at me")
                    if self.auto:
                        self.height = min(20, self.height + v)
                elif t == T_LOST:
                    print("  <- board says LOST (it topped out: I win)")
                    self.playing = False
                elif t == T_START:
                    print("  <- board says START (new round)")
                    self.playing = True
                    self.height = 0
                else:
                    print(f"  <- unknown message type {t} value {v}")

    def run(self):
        threading.Thread(target=self.heartbeat_loop, daemon=True).start()
        threading.Thread(target=self.receive_loop, daemon=True).start()
        print(__doc__.split("Message format")[0].split("lets you type commands:")[1])
        while True:
            try:
                line = input("> ").strip().lower().split()
            except (EOFError, KeyboardInterrupt):
                break
            if not line:
                continue
            cmd, arg = line[0], (int(line[1]) if len(line) > 1 and line[1].isdigit() else None)
            if cmd == "q":
                break
            elif cmd == "s":
                self.send(T_START)
                self.playing = True
                self.height = 0
                print("  -> START")
            elif cmd == "g":
                n = max(1, min(31, arg or 1))
                self.send(T_GARBAGE, n)
                print(f"  -> {n} garbage")
            elif cmd == "l":
                self.send(T_LOST)
                self.playing = False
                print("  -> LOST")
            elif cmd == "h":
                self.height = max(0, min(20, arg or 0))
                print(f"  my height is now {self.height}")
            elif cmd == "a":
                self.auto = not self.auto
                print(f"  auto mode {'ON' if self.auto else 'OFF'}")
            else:
                print("  commands: s, g <n>, l, h <n>, a, q")
        self.running = False
        time.sleep(0.2)
        self.ser.close()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: python tools\\fake_opponent.py COM3")
    Opponent(sys.argv[1]).run()
