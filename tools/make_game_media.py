"""
make_game_media.py - build the GAME's media file (format 2, "TDM2") from the
approved plan in tools/media_plan.py, for src/media/media_engine.vhd.

    python tools/make_game_media.py                 -> media/game_media.bin  (~7 MB)
    python tools/make_game_media.py --sim           -> sim/game_sim.hex + sim/game_sim_expect.txt
                                                        (tiny file for sim/tb_media_engine.vhd)
Then write it into the flash (1 MB in, after the FPGA's own bitstream):

    tools\\flash_media.bat media\\game_media.bin

Everything is encoded exactly the way tools/media_lab.py rendered it (same
cuts, fades, palettes, green key), so the board shows what the renders showed.

THE FILE (all numbers little-endian), at flash address BASE = 0x100000
  header, 16 bytes
     0..3  "TDM2"            4  version (2)        5  number of items
     6     first music item  7  number of music items (played in turn)
     8     first attack item (3 items: Bad Apple, OIIA, Jevil - chaos_pkg order)
     9     first lose item   10 number of lose items (one picked at random)
     11    first win item    12 number of win items  (one picked at random)
     13..15 address of the sprite block (0 = none)
  directory at BASE + 16, 16 bytes per item
     0     bpp: bits per pixel 1/2/4/8 (0 = sound only)
     1     frame_ticks: 60ths of a second per record (items without sound)
     2     mode: bits 1..0 = 0 bg (behind the game), 1 full, 2 over (index 0
           see-through), 3 panel (96 x 88 picture in the right panel);
           bit 2 = dim the background video to 1/2 (else 3/4)
     3     0
     4..5  number of records
     6..7  sound bytes per record ("aud"; 0 = no sound)
     8..10 address of the palette (2^bpp colours x 2 bytes, 12-bit 0x0RGB)
     11    0
     12..14 address of record 0 (record r is at + r * (8 + aud))
     15    low water / 8: load the next record when fewer sound bytes than
           this wait in the FPGA's ring
  record, 8 + aud bytes
     0..2  address of this record's picture     3..4 its length (0 = no new picture)
     5..6  ADPCM predictor before this record's first sample (signed)
     7     ADPCM step index before it
     8..   aud bytes of sound: 4-bit IMA ADPCM, 16,000 samples a second,
           2 samples per byte, LOW nibble first
  picture = "delta + run length" (only what changed since the last picture):
     00nnnnnn          SKIP n+1 pixels (they stay as they are)
     01nnnnnn c        FILL n+1 pixels with colour c
     1nnnnnnn p p ..   COPY n+1 pixels given next, bpp bits each, MSB first
                       (the last byte may be half used)
     160 x 120 pixels row by row (96 x 88 in panel mode). The first picture
     of an item has no SKIPs, so it does not matter what was there before.
  sprite block: 256 colours x 2 bytes (Jevil uses 1..15, 0 = see-through;
     the faces use 16..255), then Jevil's 8 poses of 48 x 50 pixels, 4 bits
     each (2 per byte, LEFT pixel in the high nibble), then 4 faces of
     32 x 32 pixels, 1 byte each.
"""
import argparse
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageSequence

sys.path.insert(0, os.path.dirname(__file__))
import make_media as mm          # noqa: E402
import media_lab as lab          # noqa: E402
from media_plan import PLAN      # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = 0x100000
FREE = 0x800000 - BASE
RATE = 16000                     # every sound in the game file
RING = 2048                      # the FPGA's sound ring, bytes
W, H = 160, 120
PW, PH = 96, 88                  # panel picture
MODES = {'bg': 0, 'full': 1, 'over': 2, 'panel': 3}
N_POSES, JW, JH = 8, 48, 50      # Jevil
FS = 32                          # face size

# ============================================================== ADPCM
STEPS, IDX = lab.STEPS, lab.IDX


def adpcm_encode(x, states_at):
    """int16 samples -> (bytes, {sample number: (pred, idx) before it})"""
    pred, idx = 0, 0
    codes = bytearray(len(x))
    states = {}
    want = set(states_at)
    for i, s in enumerate(x.tolist()):
        if i in want:
            states[i] = (pred, idx)
        step = STEPS[idx]
        diff = s - pred
        code = 0
        if diff < 0:
            code = 8
            diff = -diff
        t = step
        if diff >= t: code |= 4; diff -= t
        t >>= 1
        if diff >= t: code |= 2; diff -= t
        t >>= 1
        if diff >= t: code |= 1
        dq = step >> 3
        if code & 4: dq += step
        if code & 2: dq += step >> 1
        if code & 1: dq += step >> 2
        pred = pred - dq if code & 8 else pred + dq
        pred = -32768 if pred < -32768 else (32767 if pred > 32767 else pred)
        idx += IDX[code & 7]
        idx = 0 if idx < 0 else (88 if idx > 88 else idx)
        codes[i] = code
    if len(x) % 2:
        codes.append(0)
    out = bytes((codes[i] & 15) | ((codes[i + 1] & 15) << 4) for i in range(0, len(codes), 2))
    return out, states


def adpcm_decode(data, pred, idx, n):
    """what the FPGA plays: n samples from data (low nibble first)"""
    out = []
    for i in range(n):
        b = data[i // 2]
        code = (b >> 4) if i % 2 else (b & 15)
        step = STEPS[idx]
        dq = step >> 3
        if code & 4: dq += step
        if code & 2: dq += step >> 1
        if code & 1: dq += step >> 2
        pred = pred - dq if code & 8 else pred + dq
        pred = -32768 if pred < -32768 else (32767 if pred > 32767 else pred)
        idx += IDX[code & 7]
        idx = 0 if idx < 0 else (88 if idx > 88 else idx)
        out.append(pred)
    return out, pred, idx


# ============================================================== pictures
def rle_encode(cur, prev, bpp):
    """one picture -> bytes (see the header). cur/prev: arrays of palette indices."""
    n = len(cur)
    skip_min = max(2, 8 // bpp + 1)
    fill_min = 16 // bpp + 1
    same = (cur == prev) if prev is not None else np.zeros(n, dtype=bool)
    out = bytearray()
    lit = []                                  # pending literal pixels

    def flush():
        while lit:
            k = min(len(lit), 128)
            chunk, lit[:] = lit[:k], lit[k:]
            out.append(0x80 | (k - 1))
            acc, nb = 0, 0
            for p in chunk:
                acc = (acc << bpp) | int(p)
                nb += bpp
                if nb == 8:
                    out.append(acc)
                    acc, nb = 0, 0
            if nb:
                out.append((acc << (8 - nb)) & 0xFF)

    def changed(a, b):
        seg = cur[a:b]
        e = np.flatnonzero(np.diff(seg)) + 1
        for s, t in zip(np.concatenate(([0], e)).tolist(), np.concatenate((e, [len(seg)])).tolist()):
            L = t - s
            if L >= fill_min:
                flush()
                c = int(seg[s])
                while L > 0:
                    k = min(L, 64)
                    out.extend((0x40 | (k - 1), c))
                    L -= k
            else:
                lit.extend(seg[s:t].tolist())

    edges = np.flatnonzero(np.diff(same.astype(np.int8))) + 1
    starts = np.concatenate(([0], edges)).tolist()
    ends = np.concatenate((edges, [n])).tolist()
    ops_end = len(starts)
    # trailing unchanged pixels need no SKIP at all: the picture just ends
    if same[starts[-1]] and prev is not None:
        ops_end -= 1
    for a, b in zip(starts[:ops_end], ends[:ops_end]):
        L = b - a
        if same[a] and L >= skip_min:
            flush()
            while L > 0:
                k = min(L, 64)
                out.append(k - 1)
                L -= k
        else:
            changed(a, b)
    flush()
    return bytes(out)


def rle_decode(data, fb, bpp):
    """what the FPGA does with a picture (for checking)"""
    i, wa, n = 0, 0, len(fb)
    while i < len(data):
        op = data[i]; i += 1
        if op & 0x80:
            k = (op & 0x7F) + 1
            per = 8 // bpp
            for j in range(k):
                b = data[i + j // per]
                sh = 8 - bpp * (j % per + 1)
                if wa < n:
                    fb[wa] = (b >> sh) & ((1 << bpp) - 1)
                wa += 1
            i += (k * bpp + 7) // 8
        elif op & 0x40:
            k = (op & 0x3F) + 1
            c = data[i]; i += 1
            for _ in range(k):
                if wa < n:
                    fb[wa] = c
                wa += 1
        else:
            wa += (op & 0x3F) + 1


def pal_bytes(pal, bpp):
    pal = list(pal)[:1 << bpp]
    pal += [(0, 0, 0)] * ((1 << bpp) - len(pal))
    return mm.palette_bytes(pal)


# ============================================================== items
class GItem:
    def __init__(self, pid, bpp=0, mode=0, dim_half=False, aud=0, frame_ticks=60):
        self.id, self.bpp, self.mode, self.dim_half = pid, bpp, mode, dim_half
        self.aud, self.frame_ticks = aud, frame_ticks
        self.palette = b''
        self.pics = []             # picture byte strings, stored once each
        self.rec_pic = []          # per record: index into pics, or None
        self.sound = b''           # aud bytes per record, all records
        self.states = []           # per record (pred, idx)
        self.seconds = 0.0

    @property
    def nrec(self):
        return len(self.rec_pic)

    @property
    def low(self):
        if self.aud == 0:
            return 0
        if self.bpp == 0:
            return RING - self.aud            # sound only: load when it fits
        return RATE // 2 * 25 // 1000 + 64    # 25 ms + a bit (a frame is 16.7 ms)


def sound_records(it, pcm, nrec):
    """pcm -> it.sound (nrec records of aud bytes) + the ADPCM state per record"""
    spr = 2 * it.aud                          # samples per record
    x = np.zeros(nrec * spr, dtype=np.int16)
    x[:min(len(pcm), len(x))] = pcm[:len(x)]
    data, st = adpcm_encode(x, [r * spr for r in range(nrec)])
    it.sound = data
    it.states = [st[r * spr] for r in range(nrec)]
    it.seconds = nrec * spr / RATE


def frames_pics(it, idx_frames, loop_from=None):
    """pictures for a list of index frames; with loop_from = number of records,
    the frames repeat (Jevil): record 0 = whole first frame, then deltas that
    go round and round (frame 0 is stored again as a delta from the last one)."""
    if loop_from is None:
        prev = None
        for a in idx_frames:
            it.pics.append(rle_encode(a, prev, it.bpp))
            it.rec_pic.append(len(it.pics) - 1)
            prev = a
        return
    L = len(idx_frames)
    it.pics.append(rle_encode(idx_frames[0], None, it.bpp))          # pics[0]: key frame 0
    for k in range(L):                                               # pics[1 + k]: delta to frame k
        it.pics.append(rle_encode(idx_frames[k], idx_frames[k - 1], it.bpp))
    for r in range(loop_from):
        it.rec_pic.append(0 if r == 0 else 1 + (r % L))


def build_item(p):
    kind = p['kind']
    mode = MODES.get(p.get('mode', 'bg'), 0)
    if kind == 'sound':
        it = GItem(p['id'], aud=1024)
        pcm = lab.read_pcm16(p['src'], RATE, p.get('start', 0), p.get('dur'))
        pcm = lab.fade_out(pcm, RATE, p.get('fade', 0))
        nrec = -(-len(pcm) // (2 * it.aud))
        it.rec_pic = [None] * nrec
        sound_records(it, pcm, nrec)
        return it

    if kind == 'image':
        size = (PW, PH) if p['mode'] == 'panel' else (W, H)
        img = lab.load_image(p['src'], size)
        pal, idx = lab.quantise([img], p['bpp'], dither=True)
        it = GItem(p['id'], bpp=p['bpp'], mode=mode, frame_ticks=60)
        it.palette = pal_bytes(pal, p['bpp'])
        it.pics = [rle_encode(idx[0], None, p['bpp'])]
        it.rec_pic = [0]
        it.states = [(0, 0)]
        return it

    # av: picture + sound
    fps, bpp = p['fps'], p['bpp']
    it = GItem(p['id'], bpp=bpp, mode=mode, dim_half=(p.get('dim', 0.75) <= 0.5),
               aud=round(RATE / 2 / fps))
    pcm = lab.read_pcm16(p.get('audio', p['src']), RATE, p.get('start', 0), p.get('dur'))
    pcm = lab.fade_out(pcm, RATE, p.get('fade', 0))
    pad = '0x00FF00' if p.get('key') else 'black'
    if p.get('loop'):
        ls, ld = p['loop']
        frames = lab.read_video(p['src'], fps, ls, ld, pad)
    else:
        frames = lab.read_video(p['src'], fps, p.get('start', 0), p.get('dur'), pad)
    pal, idx = lab.quantise(frames, bpp, key=p.get('key'))
    it.palette = pal_bytes(pal, bpp)
    if p.get('loop'):
        nrec = -(-len(pcm) // (2 * it.aud))
        frames_pics(it, idx, loop_from=nrec)
    else:
        frames_pics(it, idx)
        nrec = len(idx)
    sound_records(it, pcm, nrec)
    it._check = (idx, p.get('loop') is not None)
    return it


# ============================================================== sprites
def sprite_block():
    pj = next(p for p in PLAN if p['id'] == 'spr_jevil')
    pf = next(p for p in PLAN if p['id'] == 'spr_faces')
    # Jevil: the gif's poses at 48 x 50, colours rounded to 12 bits, alpha -> index 0
    im = Image.open(pj['src'])
    poses = [np.array(f.convert('RGBA').resize((JW, JH), Image.NEAREST)) for f in ImageSequence.Iterator(im)]
    if len(poses) != N_POSES:
        sys.exit(f'Jevil has {len(poses)} poses, the hardware expects {N_POSES}')
    cols = {}
    jidx = []
    for a in poses:
        rgb = np.minimum(15, (a[..., :3].astype(np.int32) + 8) // 17)
        ix = np.zeros((JH, JW), dtype=np.int32)
        for yy in range(JH):
            for xx in range(JW):
                if a[yy, xx, 3] > 127:
                    c = tuple(rgb[yy, xx])
                    if c not in cols:
                        cols[c] = len(cols) + 1
                    ix[yy, xx] = cols[c]
        jidx.append(ix.reshape(-1))
    if len(cols) > 15:
        sys.exit(f'Jevil has {len(cols)} colours, at most 15 fit')
    pal = [(0, 0, 0)] * 256
    for c, i in cols.items():
        pal[i] = tuple(v * 17 for v in c)
    # faces: 240 colours shared by all 4, at palette 16..255
    faces = [lab.load_image(f, (FS, FS)) for f in pf['src']]
    sheet = Image.new('RGB', (FS * len(faces), FS))
    for i, f in enumerate(faces):
        sheet.paste(f, (i * FS, 0))
    q = sheet.quantize(colors=240, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    qp = q.getpalette()[:240 * 3]
    for i in range(240):
        r, g, b = mm.to12(tuple(qp[3 * i:3 * i + 3]))
        pal[16 + i] = (r * 17, g * 17, b * 17)
    qa = np.array(q, dtype=np.int32) + 16
    fidx = [qa[:, i * FS:(i + 1) * FS].reshape(-1) for i in range(len(faces))]
    while len(fidx) < 4:
        fidx.append(fidx[0])
    out = bytearray(mm.palette_bytes(pal))
    for ix in jidx:
        for i in range(0, len(ix), 2):
            out.append((int(ix[i]) << 4) | int(ix[i + 1]))
    for ix in fidx[:4]:
        out += bytes(int(v) for v in ix)
    return bytes(out), pal, jidx, fidx


# ============================================================== the file
def layout(items, groups, spr):
    """-> file bytes. items in order; groups = dict of (first, count)."""
    align = lambda n: (n + 255) & ~255
    off = align(16 + 16 * len(items))
    chunks = []
    entries = []
    for it in items:
        pal_off = off
        off += len(it.palette)
        rec_off = off
        rsize = 8 + it.aud
        off += rsize * it.nrec
        pic_off = []
        for pc in it.pics:
            pic_off.append(off)
            off += len(pc)
        recs = bytearray()
        for r in range(it.nrec):
            k = it.rec_pic[r]
            pa, pl = (BASE + pic_off[k], len(it.pics[k])) if k is not None else (0, 0)
            if pl > 0xFFFF:
                sys.exit(f'{it.id}: picture too long ({pl} bytes)')
            pred, idx = it.states[r] if it.states else (0, 0)
            recs += struct.pack('<I', pa)[:3] + struct.pack('<HhB', pl, pred, idx)
            recs += it.sound[r * it.aud:(r + 1) * it.aud]
        chunks.append((pal_off, it.palette))
        chunks.append((rec_off, bytes(recs)))
        for o, pc in zip(pic_off, it.pics):
            chunks.append((o, pc))
        mode = it.mode | (4 if it.dim_half else 0)
        entries.append(struct.pack('<BBBBHH', it.bpp, it.frame_ticks, mode, 0, it.nrec, it.aud)
                       + struct.pack('<I', BASE + pal_off)[:3] + b'\0'
                       + struct.pack('<I', BASE + rec_off)[:3] + bytes([it.low // 8]))
        off = align(off)
    spr_off = 0
    if spr:
        spr_off = off
        chunks.append((off, spr))
        off = align(off + len(spr))
    head = b'TDM2' + bytes([2, len(items),
                            groups['music'][0], groups['music'][1],
                            groups['attack'][0],
                            groups['lose'][0], groups['lose'][1],
                            groups['win'][0], groups['win'][1]])
    head += struct.pack('<I', BASE + spr_off if spr else 0)[:3]
    out = bytearray(off)
    out[0:16] = head
    for i, e in enumerate(entries):
        out[16 + 16 * i:32 + 16 * i] = e
    for o, d in chunks:
        out[o:o + len(d)] = d
    return bytes(out)


def check_item(it):
    """decode the item like the FPGA would and compare with the encoder's input"""
    if it.bpp and hasattr(it, '_check'):
        idx, loops = it._check
        fb = [0] * len(idx[0])
        for r in range(min(it.nrec, 3 * len(idx) if loops else it.nrec)):
            rle_decode(it.pics[it.rec_pic[r]], fb, it.bpp)
            want = idx[r % len(idx)] if loops else idx[r]
            if not np.array_equal(np.array(fb), want):
                sys.exit(f'{it.id}: picture {r} does not decode back')
    if it.aud:
        spr = 2 * it.aud
        for r in (0, it.nrec // 2, it.nrec - 1):
            pred, sidx = it.states[r]
            _, p2, i2 = adpcm_decode(it.sound[r * it.aud:(r + 1) * it.aud], pred, sidx, spr)
            if r + 1 < it.nrec and (p2, i2) != it.states[r + 1]:
                sys.exit(f'{it.id}: ADPCM state of record {r + 1} is wrong')


def game_items():
    keep = [p for p in PLAN if p.get('keep', True) and p['kind'] != 'sprite']
    order = {'music': [], 'attack': [], 'lose': [], 'win': []}
    for p in keep:
        order[p['group']].append(p)
    atk_ids = [p['id'] for p in order['attack']]
    if atk_ids != ['atk_badapple', 'atk_oiia_psy', 'atk_jevil']:
        sys.exit(f'the hardware expects 3 attacks in the order Bad Apple, OIIA, Jevil, not {atk_ids}')
    items, groups = [], {}
    for g in ('music', 'attack', 'lose', 'win'):
        groups[g] = (len(items), len(order[g]))
        for p in order[g]:
            print(f'  {len(items):2}  {p["id"]}', flush=True)
            items.append(build_item(p))
    if groups['lose'][1] > 8 or groups['win'][1] > 8 or groups['music'][1] > 8:
        sys.exit('at most 8 items per group')
    return items, groups


# ============================================================== the simulation file
def sim_file(out_base):
    """tiny items for sim/tb_media_engine.vhd + the numbers it must see"""
    rng = np.random.default_rng(5)
    items = []
    # 0: sound only, 3 records of 64 bytes (a short beep)
    t = np.arange(3 * 128)
    pcm = (8000 * np.sin(2 * np.pi * t / 23)).astype(np.int16)
    s = GItem('snd', aud=64)
    s.rec_pic = [None] * 3
    sound_records(s, pcm, 3)
    items.append(s)
    # 1: picture + sound, 4 bpp, 3 records, frames that change a little
    av = GItem('av', bpp=4, mode=0, aud=64)
    fr = []
    a = rng.integers(0, 16, W * H)
    a[:4000] = 3
    for k in range(3):
        b = a.copy()
        b[5000 + 300 * k:5300 + 300 * k] = 9
        b[100 * k:100 * k + 7] = rng.integers(0, 16, 7)
        fr.append(b)
    av.palette = pal_bytes([(17 * i, 255 - 17 * i, (34 * i) % 256) for i in range(16)], 4)
    frames_pics(av, fr)
    sound_records(av, (4000 * np.sin(2 * np.pi * np.arange(3 * 128) / 11)).astype(np.int16), 3)
    items.append(av)
    # 2: panel picture, 8 bpp
    pn = GItem('panel', bpp=8, mode=3)
    pa = rng.integers(0, 256, PW * PH)
    pa[2000:2600] = 77
    pn.palette = pal_bytes([((i * 7) % 256, (i * 13) % 256, (i * 29) % 256) for i in range(256)], 8)
    pn.pics = [rle_encode(pa, None, 8)]
    pn.rec_pic = [0]
    pn.states = [(0, 0)]
    items.append(pn)
    # 3: 1 bpp over-mode picture
    ov = GItem('one', bpp=1, mode=2)
    oa = (rng.random(W * H) > 0.7).astype(np.int32)
    oa[8000:9000] = 0
    ov.palette = pal_bytes([(0, 0, 0), (255, 255, 255)], 1)
    ov.pics = [rle_encode(oa, None, 1)]
    ov.rec_pic = [0]
    ov.states = [(0, 0)]
    items.append(ov)
    groups = {'music': (0, 1), 'attack': (1, 3), 'lose': (3, 1), 'win': (2, 1)}
    # a small sprite block: palette + Jevil poses + faces
    spal = [((i * 5) % 256, (i * 11) % 256, (i * 3) % 256) for i in range(256)]
    jv = [rng.integers(0, 16, JW * JH) for _ in range(N_POSES)]
    fc = [rng.integers(16, 256, FS * FS) for _ in range(4)]
    spr = bytearray(mm.palette_bytes(spal))
    for ix in jv:
        for i in range(0, len(ix), 2):
            spr.append((int(ix[i]) << 4) | int(ix[i + 1]))
    for ix in fc:
        spr += bytes(int(v) for v in ix)
    data = layout(items, groups, bytes(spr))
    with open(out_base + '.hex', 'w') as f:
        for b in data:
            f.write(f'{b:02X}\n')
    # expected: decoded samples of item 0 and item 1, pixels of every picture item
    to12 = lambda rgb: '%d %d %d' % mm.to12(rgb)
    with open(out_base + '_expect.txt', 'w') as f:
        for it in items[:2]:
            smp, _, _ = adpcm_decode(it.sound, 0, 0, 2 * len(it.sound))
            f.write(f'{len(smp)} ' + ' '.join(str(v) for v in smp) + '\n')
        # av after its last record, at 20 spots
        fb = [0] * (W * H)
        for r in range(av.nrec):
            rle_decode(av.pics[av.rec_pic[r]], fb, 4)
        pal = [(17 * i, 255 - 17 * i, (34 * i) % 256) for i in range(16)]
        spots = [(int(v) % W, int(v) // W % H) for v in rng.integers(0, W * H, 20)] + [(10, 41), (90, 43)]
        f.write(' '.join(f'{x} {y} {to12(pal[fb[y * W + x]])}' for x, y in spots) + '\n')
        # panel picture
        fb = [0] * (PW * PH)
        rle_decode(pn.pics[0], fb, 8)
        ppal = [((i * 7) % 256, (i * 13) % 256, (i * 29) % 256) for i in range(256)]
        spots = [(int(v) % PW, int(v) // PW % PH) for v in rng.integers(0, PW * PH, 20)]
        f.write(' '.join(f'{x} {y} {to12(ppal[fb[y * PW + x]])}' for x, y in spots) + '\n')
        # 1 bpp: index (0 = see-through) at 20 spots
        fb = [0] * (W * H)
        rle_decode(ov.pics[0], fb, 1)
        spots = [(int(v) % W, int(v) // W % H) for v in rng.integers(0, W * H, 20)] + [(0, 50), (159, 56)]
        f.write(' '.join(f'{x} {y} {fb[y * W + x]}' for x, y in spots) + '\n')
        # sprites: Jevil pose p pixel (x, y) -> index; face k pixel -> colour
        spots = [(int(rng.integers(0, 8)), int(rng.integers(0, JW)), int(rng.integers(0, JH))) for _ in range(20)]
        f.write(' '.join(f'{p} {x} {y} {jv[p][y * JW + x]} {to12(spal[jv[p][y * JW + x]])}' for p, x, y in spots) + '\n')
        spots = [(int(rng.integers(0, 4)), int(rng.integers(0, FS)), int(rng.integers(0, FS))) for _ in range(20)]
        f.write(' '.join(f'{k} {x} {y} {to12(spal[fc[k][y * FS + x]])}' for k, x, y in spots) + '\n')
    print(f'wrote {out_base}.hex ({len(data)} bytes) and {out_base}_expect.txt')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default=os.path.join(ROOT, 'media', 'game_media.bin'))
    ap.add_argument('--sim', action='store_true', help='tiny file for the testbench instead')
    a = ap.parse_args()
    os.chdir(ROOT)
    if a.sim:
        sim_file(os.path.join(ROOT, 'sim', 'game_sim'))
        return
    print('items:')
    items, groups = game_items()
    for it in items:
        check_item(it)
    spr, *_ = sprite_block()
    data = layout(items, groups, spr)
    with open(a.out, 'wb') as f:
        f.write(data)
    print(f'\n{"#":>2}  {"id":16} {"bpp":>3} {"mode":>4} {"recs":>5} {"aud":>5} {"pictures":>9} {"sound":>9} {"secs":>6}')
    for i, it in enumerate(items):
        print(f'{i:>2}  {it.id:16} {it.bpp:>3} {it.mode:>4} {it.nrec:>5} {it.aud:>5} '
              f'{sum(map(len, it.pics)):>9,} {len(it.sound):>9,} {it.seconds:>6.1f}')
    print(f'    sprites {len(spr):,} bytes')
    print(f'total {len(data):,} bytes = {100.0 * len(data) / FREE:.1f} % of the {FREE:,} bytes free in flash')
    if len(data) > FREE:
        sys.exit('TOO BIG for the flash')
    print(f'wrote {a.out}   (flash 0x{BASE:06X} .. 0x{BASE + len(data) - 1:06X})')


if __name__ == '__main__':
    main()
