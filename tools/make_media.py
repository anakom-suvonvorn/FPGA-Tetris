"""
make_media.py - turn pictures / GIFs / videos / sounds into ONE file for the
board's SPI flash, in the format media_player.vhd reads (see its header).

    python tools/make_media.py media/media.bin --demo
    python tools/make_media.py media/media.bin --item "av:badapple.mp4,bpp=1,fps=15,seconds=30"
    python tools/make_media.py media/media.bin --demo --item "image:cat.png" --item "sound:oiia.mp3"

Then write it into the flash (1 MB in, after the FPGA's own bitstream):

    tools\\flash_media.bat media\\media.bin

ITEM = "kind:path[,key=value...]", kinds:
    image   a picture (png/jpg/...)              keys: bpp (default 8), name
    video   moving picture, no sound (gif/mp4)   keys: bpp (4), fps (15), seconds (10), start, loop, name
    av      moving picture + its sound           keys: bpp (4), fps (15), rate (8000), seconds (10), start, loop, name
    sound   sound only (mp3/wav/...)             keys: rate (8000), seconds (10), start, loop, name
  bpp = bits per pixel: 1 (2 colours), 2 (4), 4 (16) or 8 (256 colours).
  seconds=0 means "all of it". name = up to 16 characters (A-Z 0-9 space - ! : . ?).
Videos and sounds need ffmpeg (installed: C:\\ProgramData\\chocolatey\\bin\\ffmpeg).

Every picture is 160 x 120 (shown 4x bigger), squeezed to fit with black bars.
The program prints how big everything is: the flash has 7 MB free for media.
"""
import argparse
import colorsys
import math
import os
import shutil
import struct
import subprocess
import sys

from PIL import Image, ImageDraw

W, H = 160, 120
BASE = 0x100000                      # flash address of the file (1 MB)
FLASH_END = 0x800000                 # 8 MB chip
RING = 2048                          # sound ring in the FPGA (bytes)
CLK_HZ = 50_000_000

# text_pkg character codes: 0-9, A-Z, then ' ' '-' '!' ':' '.' '?'
CODES = {**{str(i): i for i in range(10)},
         **{chr(65 + i): 10 + i for i in range(26)},
         ' ': 36, '-': 37, '!': 38, ':': 39, '.': 40, '?': 41}


def name_codes(name):
    name = name.upper()[:16].ljust(16)
    return bytes(CODES.get(c, 36) for c in name)


# ----------------------------------------------------------------- verify block
def lfsr_bytes(n, seed=0xACE1):
    """Same as lfsr8 in media_player.vhd: byte = low 8 bits, then 8 steps."""
    out = bytearray(n)
    s = seed
    for i in range(n):
        out[i] = s & 0xFF
        for _ in range(8):
            bit = ((s >> 15) ^ (s >> 13) ^ (s >> 12) ^ (s >> 10)) & 1
            s = ((s << 1) | bit) & 0xFFFF
    return bytes(out)


# ----------------------------------------------------------------- pictures
def fit(img):
    """Scale to fit 160x120, keep the shape, black bars around."""
    img = img.convert('RGB')
    k = min(W / img.width, H / img.height)
    img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    out = Image.new('RGB', (W, H))
    out.paste(img, ((W - img.width) // 2, (H - img.height) // 2))
    return out


def to12(rgb):
    """8-bit colour -> nearest 4-bit-per-channel colour (the VGA DAC has 4 bits)."""
    return tuple(min(15, (c + 8) // 17) for c in rgb)


def make_palette(frames, bpp):
    """One palette for all frames (like a GIF's global colour table)."""
    n = 1 << bpp
    if len(frames) == 1:
        sheet = frames[0]
    else:                                     # a contact sheet of up to 64 frames
        step = max(1, len(frames) // 64)
        pick = frames[::step][:64]
        sheet = Image.new('RGB', (W * 8, H * ((len(pick) + 7) // 8)))
        for i, f in enumerate(pick):
            sheet.paste(f, ((i % 8) * W, (i // 8) * H))
    if bpp == 1:
        # two colours: black and white looks best (Bad Apple style)
        pal = [(0, 0, 0), (255, 255, 255)]
    else:
        q = sheet.quantize(colors=n, method=Image.Quantize.MEDIANCUT)
        p = q.getpalette()[:3 * n]
        p += [0] * (3 * n - len(p))
        pal = [tuple(p[3 * i:3 * i + 3]) for i in range(n)]
    pal = [tuple(c * 17 for c in to12(rgb)) for rgb in pal]   # what the screen really shows
    pimg = Image.new('P', (1, 1))
    flat = [c for rgb in pal for c in rgb]
    pimg.putpalette(flat + [0] * (768 - len(flat)))
    return pal, pimg


def frame_indices(frame, pimg, bpp, dither):
    if bpp == 1:
        g = frame.convert('L')
        idx = g.point(lambda v: 1 if v >= 128 else 0)
        return list(idx.getdata())
    q = frame.quantize(palette=pimg, dither=Image.Dither.FLOYDSTEINBERG if dither else Image.Dither.NONE)
    return list(q.getdata())


def pack(indices, bpp):
    """Pixels -> bytes, MSB first (bpp 1: 8 pixels per byte)."""
    if bpp == 8:
        return bytes(indices)
    per = 8 // bpp
    out = bytearray()
    for i in range(0, len(indices), per):
        v = 0
        for j in range(per):
            v = (v << bpp) | (indices[i + j] & ((1 << bpp) - 1))
        out.append(v)
    return bytes(out)


def palette_bytes(pal):
    out = bytearray()
    for rgb in pal:
        r, g, b = to12(rgb)
        v = (r << 8) | (g << 4) | b
        out += struct.pack('<H', v)
    return bytes(out)


# ----------------------------------------------------------------- ffmpeg
def ffmpeg():
    exe = shutil.which('ffmpeg') or r'C:\ProgramData\chocolatey\bin\ffmpeg.exe'
    if not os.path.exists(exe) and not shutil.which('ffmpeg'):
        sys.exit('ffmpeg not found - needed for videos and sounds')
    return exe


def cut_args(start, seconds):
    a = []
    if start:
        a += ['-ss', str(start)]
    if seconds:
        a += ['-t', str(seconds)]
    return a


def read_video(path, fps, start, seconds):
    vf = f'fps={fps},scale={W}:{H}:force_original_aspect_ratio=decrease,pad={W}:{H}:(ow-iw)/2:(oh-ih)/2'
    cmd = [ffmpeg(), '-v', 'error'] + cut_args(start, seconds) + ['-i', path, '-vf', vf,
                                                                   '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-']
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    n = len(raw) // (W * H * 3)
    return [Image.frombytes('RGB', (W, H), raw[i * W * H * 3:(i + 1) * W * H * 3]) for i in range(n)]


def read_sound(path, rate, start, seconds):
    cmd = [ffmpeg(), '-v', 'error'] + cut_args(start, seconds) + ['-i', path, '-vn', '-ac', '1',
                                                                   '-ar', str(rate), '-f', 'u8', '-']
    return subprocess.run(cmd, capture_output=True, check=True).stdout


# ----------------------------------------------------------------- items
class Item:
    """One directory entry + its data."""

    def __init__(self, name, bpp=0, frames=None, sound=b'', rate=8000, fps=15,
                 frame_ticks=4, loop=False, aud=0, low=0, dither=True, records=None):
        self.name, self.bpp, self.loop = name, bpp, loop
        self.rate, self.fps, self.frame_ticks = rate, fps, frame_ticks
        self.frames = frames or []
        self.sound = sound
        self.aud, self.low, self.dither = aud, low, dither
        self.records = records            # prebuilt (for sound-only)

    def build(self):
        """-> (palette bytes, list of record bytes)"""
        pal_b, recs = b'', []
        idx_frames = []
        if self.bpp:
            pal, pimg = make_palette(self.frames, self.bpp)
            pal_b = palette_bytes(pal)
            self.palette = pal
            for f in self.frames:
                idx = frame_indices(f, pimg, self.bpp, self.dither)
                idx_frames.append(idx)
            self.indices = idx_frames
        if self.bpp and self.aud:                       # picture + sound
            n = len(idx_frames)
            snd = self.sound.ljust(n * self.aud, b'\x80')
            for i in range(n):
                recs.append(snd[i * self.aud:(i + 1) * self.aud] + pack(idx_frames[i], self.bpp))
        elif self.bpp:                                  # picture only
            recs = [pack(idx, self.bpp) for idx in idx_frames]
        else:                                           # sound only
            s = self.sound
            pad = (-len(s)) % self.aud
            s = s + b'\x80' * pad
            recs = [s[i:i + self.aud] for i in range(0, len(s), self.aud)]
        return pal_b, recs

    def entry(self, addr, nrec):
        e = struct.pack('<BBBBHHIHH', self.bpp, self.frame_ticks if not self.aud else 0,
                        1 if self.loop else 0, 0, nrec, self.aud, addr, self.rate, self.low)
        return e + name_codes(self.name)


def av_params(rate, fps):
    """Sound bytes per record, and the exact rate that makes it a whole number."""
    if fps > 30:
        sys.exit('fps can be at most 30 with sound (the screen does 60 frames a second)')
    aud = max(1, round(rate / fps))
    rate = aud * fps
    low = int(rate * 0.025) + 64                        # 25 ms + a bit (a frame is 16.7 ms)
    if aud + low > RING:
        sys.exit(f'rate/fps too high: {aud} sound bytes per frame + {low} > {RING}')
    return aud, rate, low


def parse_item(spec):
    kind, _, rest = spec.partition(':')
    parts = rest.split(',')
    path, opts = parts[0], {}
    for p in parts[1:]:
        k, _, v = p.partition('=')
        opts[k.strip()] = v.strip()
    name = opts.get('name', os.path.splitext(os.path.basename(path))[0])
    loop = opts.get('loop', '0') in ('1', 'yes', 'true')
    start = float(opts.get('start', 0))
    seconds = float(opts.get('seconds', 10))
    if kind == 'image':
        bpp = int(opts.get('bpp', 8))
        return Item(name, bpp=bpp, frames=[fit(Image.open(path))], frame_ticks=60)
    if kind == 'video':
        bpp, fps = int(opts.get('bpp', 4)), float(opts.get('fps', 15))
        ft = max(1, round(60 / fps))
        frames = read_video(path, 60 / ft, start, seconds)
        return Item(name, bpp=bpp, frames=frames, frame_ticks=ft, loop=loop)
    if kind == 'av':
        bpp, fps, rate = int(opts.get('bpp', 4)), float(opts.get('fps', 15)), int(opts.get('rate', 8000))
        aud, rate, low = av_params(rate, fps)
        frames = read_video(path, fps, start, seconds)
        snd = read_sound(path, rate, start, seconds)
        return Item(name, bpp=bpp, frames=frames, sound=snd, rate=rate, fps=fps, aud=aud, low=low, loop=loop)
    if kind == 'sound':
        rate = int(opts.get('rate', 8000))
        snd = read_sound(path, rate, start, seconds)
        return Item(name, sound=snd, rate=rate, aud=1024, loop=loop)
    sys.exit(f'unknown item kind "{kind}" (image / video / av / sound)')


# ----------------------------------------------------------------- the demo set
def demo_items():
    items = []
    # 1. colour test card, 256 colours
    img = Image.new('RGB', (W, H))
    d = ImageDraw.Draw(img)
    bars = [(255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
            (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0)]
    for i, c in enumerate(bars):
        d.rectangle([i * 20, 0, i * 20 + 19, 59], fill=c)
    for x in range(W):                               # grey ramp
        v = x * 255 // (W - 1)
        d.line([x, 60, x, 79], fill=(v, v, v))
    for x in range(W):                               # rainbow
        r, g, b = colorsys.hsv_to_rgb(x / W, 1, 1)
        d.line([x, 80, x, 99], fill=(int(r * 255), int(g * 255), int(b * 255)))
    for yy in range(100, 120, 4):                    # checker
        for xx in range(0, W, 4):
            if ((xx + yy) // 4) % 2:
                d.rectangle([xx, yy, xx + 3, yy + 3], fill=(255, 255, 255))
    items.append(Item('COLOUR TEST', bpp=8, frames=[img], frame_ticks=60, dither=False))

    # 2. a ball bouncing over a gradient, 16 colours, 20 fps, loops
    frames = []
    for t in range(40):
        f = Image.new('RGB', (W, H))
        d = ImageDraw.Draw(f)
        for yy in range(H):
            d.line([0, yy, W, yy], fill=(0, yy, 120 - yy // 2))
        bx = 20 + int(120 * abs(((t / 40.0) * 2) % 2 - 1))
        by = 90 - int(70 * abs((t % 20) / 10.0 - 1) ** 0.5)
        d.ellipse([bx - 12, by - 12, bx + 12, by + 12], fill=(255, 80, 40), outline=(255, 255, 0))
        frames.append(f)
    items.append(Item('BALL 16 COLOURS', bpp=4, frames=frames, frame_ticks=3, loop=True, dither=False))

    # 3. Bad-Apple-style black & white, 1 bit, 30 fps, loops
    frames = []
    for t in range(60):
        f = Image.new('RGB', (W, H), (255, 255, 255))
        d = ImageDraw.Draw(f)
        a = t / 60.0 * 2 * math.pi
        cx, cy = 80 + int(50 * math.cos(a)), 60 + int(30 * math.sin(2 * a))
        d.ellipse([cx - 20, cy - 20, cx + 20, cy + 20], fill=(0, 0, 0))
        d.rectangle([0, 100, W, H], fill=(0, 0, 0))
        d.polygon([(cx, cy + 20), (cx - 15, 100), (cx + 15, 100)], fill=(0, 0, 0))
        frames.append(f)
    items.append(Item('1 BIT 30 FPS', bpp=1, frames=frames, frame_ticks=2, loop=True))

    # 4. A/V sync test: a white flash and a beep at the same moment, every second
    fps = 15
    aud, rate, low = av_params(8000, fps)
    frames, snd = [], bytearray()
    for t in range(fps * 4):
        flash = (t % fps) < 2
        f = Image.new('RGB', (W, H), (255, 255, 255) if flash else (20, 20, 60))
        d = ImageDraw.Draw(f)
        x = int((t % fps) * W / fps)
        d.rectangle([x, 50, x + 8, 70], fill=(255, 200, 0))
        frames.append(f)
        for i in range(aud):
            if flash:
                v = 128 + int(100 * math.sin(2 * math.pi * 880 * i / rate))
            else:
                v = 128
            snd.append(v)
    items.append(Item('FLASH + BEEP', bpp=4, frames=frames, sound=bytes(snd), rate=rate, fps=fps,
                      aud=aud, low=low, loop=True, dither=False))

    # 5. sound only: a little tune (square-ish waves), 8 kHz
    rate = 8000
    notes = [(659, 2), (494, 1), (523, 1), (587, 2), (523, 1), (494, 1), (440, 2), (440, 1),
             (523, 1), (659, 2), (587, 1), (523, 1), (494, 3), (523, 1), (587, 2), (659, 2),
             (523, 2), (440, 2), (440, 4)]
    snd = bytearray()
    for f, beats in notes:
        n = int(rate * 0.18 * beats)
        for i in range(n):
            env = min(1.0, (n - i) / 400.0)
            v = 128 + int(60 * env * (1 if math.sin(2 * math.pi * f * i / rate) > 0 else -1))
            snd.append(v)
        snd += b'\x80' * int(rate * 0.02)
    items.append(Item('TUNE 8 KHZ', sound=bytes(snd), rate=rate, aud=1024))
    return items


def sim_items():
    """Tiny items for the testbench (sim/tb_flash_read.vhd)."""
    items = demo_items()[:1]                             # the colour test card
    frames = []
    for t in range(3):
        f = Image.new('RGB', (W, H), (0, 0, 0))
        ImageDraw.Draw(f).rectangle([t * 40, 20, t * 40 + 39, 99], fill=(255, 255, 255))
        frames.append(f)
    items.append(Item('SIM 1 BIT', bpp=1, frames=frames, frame_ticks=1))
    # picture + sound with sim numbers: frame_tick every 30,000 clocks in the
    # testbench (2 ticks per record, like 30 fps on a 60 Hz screen),
    # 64 sound bytes per record of 60,000 clocks -> rate = 64 * 50e6 / 60e3
    snd = bytes((i * 7) & 0xFF for i in range(64 * 4))
    items.append(Item('SIM AV', bpp=1, frames=frames + frames[:1], sound=snd,
                      rate=53333, aud=64, low=128))
    return items


# ----------------------------------------------------------------- the file
def build(items, verify_len):
    if len(items) > 16:
        sys.exit('at most 16 items')
    head_len = 16 + 32 * 16
    align = lambda n: (n + 4095) & ~4095
    off = align(head_len)
    verify_off = off
    blob = {}
    off = align(off + verify_len)
    entries, summary = [], []
    for it in items:
        pal_b, recs = it.build()
        data = pal_b + b''.join(recs)
        entries.append(it.entry(BASE + off, len(recs)))
        blob[off] = data
        kind = ('picture+sound' if it.bpp and it.aud else 'picture' if it.bpp else 'sound')
        secs = (len(recs) * it.aud / it.rate) if it.aud else (len(recs) * it.frame_ticks / 60.0)
        summary.append((it.name, kind, it.bpp, len(recs), len(data), secs))
        off = align(off + len(data))
    out = bytearray(off)
    out[0:16] = b'TDMF' + bytes([1, len(items), 0, 0]) + struct.pack('<II', BASE + verify_off, verify_len)
    for i, e in enumerate(entries):
        out[16 + 32 * i:16 + 32 * (i + 1)] = e
    out[verify_off:verify_off + verify_len] = lfsr_bytes(verify_len)
    for o, data in blob.items():
        out[o:o + len(data)] = data
    return bytes(out), summary


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('out', help='output file, e.g. media/media.bin')
    ap.add_argument('--demo', action='store_true', help='add the built-in demo items')
    ap.add_argument('--item', action='append', default=[], help='kind:path[,key=value...]')
    ap.add_argument('--verify-kb', type=int, default=256, help='size of the verify block (KB)')
    ap.add_argument('--sim', action='store_true', help='tiny file + .hex/.txt for the testbench')
    a = ap.parse_args()

    if a.sim:
        items = sim_items()
        a.verify_kb = 4
    else:
        items = (demo_items() if a.demo else []) + [parse_item(s) for s in a.item]
    if not items:
        sys.exit('nothing to do: use --demo and/or --item')
    data, summary = build(items, a.verify_kb * 1024)

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, 'wb') as f:
        f.write(data)
    print(f'{"#":>2}  {"name":16}  {"kind":13} {"bpp":>3} {"frames":>6} {"bytes":>9} {"seconds":>7}')
    for i, (n, k, bpp, recs, size, secs) in enumerate(summary):
        print(f'{i:>2}  {n:16}  {k:13} {bpp:>3} {recs:>6} {size:>9,} {secs:>7.1f}')
    free = FLASH_END - BASE
    print(f'total {len(data):,} bytes = {100.0 * len(data) / free:.1f} % of the {free:,} bytes free in flash')
    if len(data) > free:
        sys.exit('TOO BIG for the flash')
    print(f'wrote {a.out}   (flash address 0x{BASE:06X} .. 0x{BASE + len(data) - 1:06X})')

    if a.sim:
        # the testbench reads the flash contents as hex text, and checks
        # some pixels / sound bytes against these expected values
        base = os.path.splitext(a.out)[0]
        with open(base + '.hex', 'w') as f:
            for b in data:
                f.write(f'{b:02X}\n')
        with open(base + '_expect.txt', 'w') as f:
            it0 = items[0]
            for (x, y) in [(10, 10), (30, 30), (50, 50), (70, 20), (90, 40), (110, 10), (130, 50),
                           (150, 30), (0, 70), (80, 70), (159, 70), (40, 90), (120, 90), (2, 102), (6, 102)]:
                p = it0.palette[it0.indices[0][y * W + x]]
                r, g, b = to12(p)
                f.write(f'{x * 4 + 1} {y * 4 + 1} {r} {g} {b}\n')
        print(f'wrote {base}.hex and {base}_expect.txt')


if __name__ == '__main__':
    main()
