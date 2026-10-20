"""
media_lab.py - try out the media plan (tools/media_plan.py) before building it.

For every item it does exactly what the board will do, so the renders show
the REAL quality:
  * pictures: 160 x 120, quantised to the item's palette (1/2/4/8 bits per
    pixel, 12-bit colours), drawn 4x bigger (or 2x in the side panel)
  * sound: resampled to the item's rate, then 4-bit IMA ADPCM encoded AND
    decoded again (that's what the FPGA will play)
  * size: pictures go through the planned "delta + run length" compression
    (only the pixels that changed since the last frame are stored, in runs),
    sound is rate / 2 bytes a second
and then composites it into a real screenshot of the game (game/*.png) the
way the hardware would draw it (hollow blocks over a background video,
jump scare on top, picture in the panel, Jevil floating, faces on the
bouncers).

    python tools/media_lab.py              all items  (a few minutes)
    python tools/media_lab.py atk_jevil    just these ids

Writes media/renders/<id>.mp4 / .wav / .png and media/renders/budget.json.
Needs Pillow, numpy and ffmpeg.
"""
import json
import math
import os
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageSequence

sys.path.insert(0, os.path.dirname(__file__))
import make_media as mm          # noqa: E402  (fit, to12, make_palette, frame_indices, pack, ffmpeg)
from media_plan import PLAN      # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'media', 'renders')
W, H = 160, 120
FREE = 7_340_032
OUT_FPS = 30                      # render frame rate (the board draws 60; 30 looks the same in a video)
DIM = 0.75                        # background video brightness behind the game (3/4: cheap in hardware)
RING = 3                          # hollow block: pixels of the block that stay
HOLLOW = False                    # blocks stay solid (hollow looked weird on the real renders)

# ============================================================== ADPCM (IMA, 4 bits)
STEPS = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73,
         80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494,
         544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499,
         2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487,
         12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
IDX = [-1, -1, -1, -1, 2, 4, 6, 8]


def adpcm_roundtrip(x):
    """int16 samples -> (decoded int16 samples, number of bytes stored)"""
    pred, idx = 0, 0
    out = np.empty(len(x), dtype=np.int16)
    for i, s in enumerate(x.tolist()):
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
        # decode exactly like the hardware will
        dq = step >> 3
        if code & 4: dq += step
        if code & 2: dq += step >> 1
        if code & 1: dq += step >> 2
        pred = pred - dq if code & 8 else pred + dq
        pred = -32768 if pred < -32768 else (32767 if pred > 32767 else pred)
        idx += IDX[code & 7]
        idx = 0 if idx < 0 else (88 if idx > 88 else idx)
        out[i] = pred
    return out, (len(x) + 1) // 2


def read_pcm16(path, rate, start, dur):
    cmd = [mm.ffmpeg(), '-v', 'error'] + mm.cut_args(start, dur) + ['-i', path, '-vn', '-ac', '1',
                                                                     '-ar', str(rate), '-f', 's16le', '-']
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).copy()


def fade_out(x, rate, sec):
    n = min(len(x), int(rate * (sec or 0)))
    if n > 0:
        x = x.astype(np.float64)
        x[-n:] *= np.linspace(1, 0, n)
        x = x.astype(np.int16)
    return x


def write_wav(path, x, rate):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(x.astype('<i2').tobytes())


# ============================================================== picture compression (size estimate)
def rle_bytes(cur, prev, bpp):
    """Bytes for one frame in the planned delta + run-length format:
         00nnnnnn  SKIP n+1 pixels (unchanged since the last frame)
         01nnnnnn  FILL n+1 pixels with the colour in the next byte
         1nnnnnnn  COPY n+1 pixels that follow, packed bpp bits each
    """
    n = len(cur)
    skip_min = max(2, 8 // bpp + 1)          # shorter unchanged runs are cheaper as literals
    fill_min = 16 // bpp + 1                 # shorter colour runs are cheaper as literals
    same = (cur == prev) if prev is not None else np.zeros(n, dtype=bool)
    edges = np.flatnonzero(np.diff(same.astype(np.int8))) + 1
    starts = np.concatenate(([0], edges))
    ends = np.concatenate((edges, [n]))
    total = 0
    lit = 0                                  # pending literal pixels

    def flush():
        nonlocal lit, total
        while lit > 0:
            k = min(lit, 128)
            total += 1 + (k * bpp + 7) // 8
            lit -= k

    def changed(a, b):
        nonlocal lit, total
        seg = cur[a:b]
        e = np.flatnonzero(np.diff(seg)) + 1
        rs = np.concatenate(([0], e))
        re_ = np.concatenate((e, [len(seg)]))
        for L in (re_ - rs).tolist():
            if L >= fill_min:
                flush()
                total += 2 * ((L + 63) // 64)
            else:
                lit += L

    for a, b in zip(starts.tolist(), ends.tolist()):
        L = b - a
        if same[a] and L >= skip_min:
            flush()
            total += (L + 63) // 64
        else:
            changed(a, b)
    flush()
    return total


# ============================================================== pictures
def read_video(path, fps, start, seconds, pad='black', crop=None):
    """like make_media.read_video, with a choice of colour for the bars around,
    and an optional crop = (x, y, w, h) of the source first (the part that matters)"""
    pre = f'crop={crop[2]}:{crop[3]}:{crop[0]}:{crop[1]},' if crop else ''
    vf = (f'{pre}fps={fps},scale={W}:{H}:force_original_aspect_ratio=decrease,'
          f'pad={W}:{H}:(ow-iw)/2:(oh-ih)/2:color={pad}')
    cmd = [mm.ffmpeg(), '-v', 'error'] + mm.cut_args(start, seconds) + ['-i', path, '-vf', vf,
                                                                     '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-']
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    n = len(raw) // (W * H * 3)
    return [Image.frombytes('RGB', (W, H), raw[i * W * H * 3:(i + 1) * W * H * 3]) for i in range(n)]


def green_mask(rgb):
    a = rgb.astype(np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return (g > 80) & (g - np.maximum(r, b) > 40)


def quantise(frames, bpp, key=None, dither=False):
    """PIL RGB frames -> (palette as list of (r,g,b) screen colours, list of index arrays).
    With key: index 0 = see-through (green pixels), the others from the rest."""
    if key:
        masks, clean = [], []
        for f in frames:
            a = np.array(f)
            m = green_mask(a)
            # the fringe: pixels next to the green screen that are still greenish
            near = m.copy()
            near[1:, :] |= m[:-1, :]; near[:-1, :] |= m[1:, :]
            near[:, 1:] |= m[:, :-1]; near[:, :-1] |= m[:, 1:]
            ai = a.astype(np.int16)
            mx = np.maximum(ai[..., 0], ai[..., 2])
            m |= near & (ai[..., 1] > mx + 10)
            # "despill": no pixel left may be greener than its red or blue
            a[..., 1] = np.minimum(ai[..., 1], mx).astype(np.uint8)
            a[m] = 0
            masks.append(m)
            clean.append(Image.fromarray(a))
        pal, pimg = mm.make_palette(clean, bpp) if bpp > 1 else ([(0, 0, 0), (255, 255, 255)], None)
        n = 1 << bpp
        pal = [(0, 0, 0)] + pal[:n - 1]
        flat = [c for rgb in pal[1:] for c in rgb]
        pimg = Image.new('P', (1, 1))
        pimg.putpalette(flat + [0] * (768 - len(flat)))
        idx = []
        for f, m in zip(clean, masks):
            q = np.array(f.quantize(palette=pimg, dither=Image.Dither.NONE)).astype(np.int32) + 1
            q[m] = 0
            idx.append(q.reshape(-1))
        return pal, idx
    pal, pimg = mm.make_palette(frames, bpp)
    idx = [np.array(mm.frame_indices(f, pimg, bpp, dither), dtype=np.int32) for f in frames]
    return pal, idx


def to_rgb(pal, idx, w=W, h=H):
    p = np.array(pal, dtype=np.uint8)
    return p[idx].reshape(h, w, 3)


def up(img, k):
    return img.repeat(k, axis=0).repeat(k, axis=1)


def load_image(path, size=(W, H)):
    im = Image.open(path)
    im = im.convert('RGBA')
    bg = Image.new('RGBA', im.size, (0, 0, 0, 255))
    bg.alpha_composite(im)
    im = bg.convert('RGB')
    k = min(size[0] / im.width, size[1] / im.height)
    im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    out = Image.new('RGB', size)
    out.paste(im, ((size[0] - im.width) // 2, (size[1] - im.height) // 2))
    return out


# ============================================================== the game screen
FX0, FY0, CELL = 240, 80, 16
FONT = {}


def load_font():
    import re
    src = open(os.path.join(ROOT, 'src', 'game', 'text_pkg.vhd'), encoding='utf-8').read()
    for m in re.finditer(r'(\d+) => g\(((?:"[.X]{5}",?\s*){7})\)', src):
        rows = re.findall(r'"([.X]{5})"', m.group(2))
        FONT[int(m.group(1))] = rows


def char_code(ch):
    if ch.isdigit():
        return int(ch)
    if ch.isalpha():
        return ord(ch.upper()) - 55
    return {' ': 36, '-': 37, '!': 38, ':': 39, '.': 40, '?': 41}.get(ch, 36)


def draw_text(img, x0, y0, text, colour, scale=2):
    for i, ch in enumerate(text):
        g = FONT.get(char_code(ch))
        if not g:
            continue
        for r, row in enumerate(g):
            for c, v in enumerate(row):
                if v == 'X':
                    x = x0 + (i * 6 + c) * scale
                    y = y0 + r * scale
                    img[y:y + scale, x:x + scale] = colour


def screens():
    """the base screens: playing, win, lose (made from the win screenshot)"""
    play = np.array(Image.open(os.path.join(ROOT, 'game', 'screenshot_versus.png')).convert('RGB'))
    win = np.array(Image.open(os.path.join(ROOT, 'game', 'screenshot_win.png')).convert('RGB'))
    lose = win.copy()
    gold = np.array([0xFF, 0xDD, 0x33])
    # frame and text gold -> red, blocks -> grey (what tetris_render does when I lost)
    fr = (np.abs(lose.astype(int) - gold).sum(axis=2) < 60)
    lose[fr] = (0xFF, 0x44, 0x44)
    lose[192:240, FX0:FX0 + 160] = (0x11, 0x11, 0x11)
    draw_text(lose, FX0 + 32, 200, 'LOSE', (0xFF, 0x44, 0x44), scale=4)
    for r in range(20):
        for c in range(10):
            y, x = FY0 + r * CELL, FX0 + c * CELL
            if 192 <= y < 288:
                continue
            cell = lose[y:y + CELL, x:x + CELL]
            centre = cell[8, 8].astype(int)
            if centre.max() > 0x40:
                g = cell.astype(int).mean(axis=2, keepdims=True)
                cell[:] = (g * 0.6).astype(np.uint8)
    return play, win, lose


def see_through(base):
    """mask of the pixels where a background video shows through:
    the screen background, the empty field (incl. grid lines), and the
    middle of every block (blocks are drawn hollow, RING px thick)"""
    bgc = base[5, 5]
    m = np.all(base == bgc, axis=2)
    for r in range(20):
        for c in range(10):
            y, x = FY0 + r * CELL, FX0 + c * CELL
            cell = base[y:y + CELL, x:x + CELL]
            centre = cell[8, 8].astype(int)
            if centre.max() < 0x40:                    # empty cell: all of it, except a ghost outline
                m[y:y + CELL, x:x + CELL] = cell.astype(int).max(axis=2) <= 0x60
            elif HOLLOW:                               # a block: hollow (tried, looked odd)
                m[y + RING:y + CELL - RING, x + RING:x + CELL - RING] = True
    # text bands over the field (WIN!/LOSE, PRESS START) stay solid
    return m


def compose_bg(base, mask, frame640, dim=DIM):
    out = base.copy()
    v = (frame640.astype(np.float32) * dim).astype(np.uint8)
    out[mask] = v[mask]
    return out


def compose_over(base, frame640, keymask640):
    out = base.copy()
    out[~keymask640] = frame640[~keymask640]
    return out


def compose_full(base, frame640):
    out = frame640.copy()
    out[192:240, FX0:FX0 + 160] = base[192:240, FX0:FX0 + 160]   # result text stays on top
    return out


def compose_panel(base, pic, frame_col):
    """picture (96 x 88 at 2x = 192 x 176) in the right panel"""
    out = base.copy()
    x0, y0 = 430, 286
    out[y0 - 4:y0 + 180, x0 - 4:x0 + 196] = frame_col
    out[y0 - 2:y0 + 178, x0 - 2:x0 + 194] = (0x10, 0x10, 0x10)
    p = up(pic, 2)
    out[y0:y0 + p.shape[0], x0:x0 + p.shape[1]] = p
    return out


# ============================================================== output
def write_mp4(path, frames, fps, wav=None):
    """frames: iterable of 640x480 RGB uint8 arrays"""
    cmd = [mm.ffmpeg(), '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '640x480',
           '-r', str(fps), '-i', '-']
    if wav:
        cmd += ['-i', wav]
    cmd += ['-c:v', 'libx264', '-crf', '20', '-preset', 'veryfast', '-pix_fmt', 'yuv420p']
    if wav:
        cmd += ['-c:a', 'aac', '-b:a', '128k', '-shortest']
    cmd += [path]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for f in frames:
        p.stdin.write(np.ascontiguousarray(f, dtype=np.uint8).tobytes())
    p.stdin.close()
    p.wait()


def duration(path):
    r = subprocess.run([mm.ffmpeg().replace('ffmpeg', 'ffprobe'), '-v', 'error', '-show_entries',
                        'format=duration', '-of', 'csv=p=0', path], capture_output=True, text=True)
    return float(r.stdout.strip())


# ============================================================== one item
def do_sound(it, info):
    rate = it.get('rate', 16000)
    x = read_pcm16(it.get('audio', it['src']), rate, it.get('start', 0), it.get('dur'))
    x = fade_out(x, rate, it.get('fade', 0))
    y, nbytes = adpcm_roundtrip(x)
    wav = os.path.join(OUT, it['id'] + '.wav')
    write_wav(wav, y, rate)
    info.update(sound_bytes=nbytes, seconds=round(len(x) / rate, 1), rate=rate)
    return wav, len(x) / rate


def do_item(it, bases):
    play, win, lose = bases
    info = dict(id=it['id'], group=it['group'], title=it['title'], kind=it['kind'],
                mode=it.get('mode', ''), keep=it.get('keep', True), bpp=it.get('bpp', 0),
                fps=it.get('fps', 0), files=[])
    kind = it['kind']
    if kind == 'sound':
        wav, secs = do_sound(it, info)
        info['files'].append(os.path.basename(wav))
        # the 8 kHz 8-bit sound of test 06, for comparison (first 30 s)
        if it['id'] == 'music_teto_sv':
            for rate, tag in [(8000, '8k_8bit'), (11025, '11k_adpcm'), (22050, '22k_adpcm')]:
                x = read_pcm16(it['src'], rate, 0, 30)
                if tag == '8k_8bit':
                    y = ((x.astype(np.int32) >> 8) << 8).astype(np.int16)      # keep 8 bits
                else:
                    y, _ = adpcm_roundtrip(x)
                fn = f"{it['id']}_{tag}.wav"
                write_wav(os.path.join(OUT, fn), y, rate)
                info['files'].append(fn)
        info['bytes'] = info['sound_bytes']
        return info

    if kind == 'image':
        size = (96, 88) if it['mode'] == 'panel' else (W, H)
        img = load_image(it['src'], size)
        pal, idx = quantise([img], it['bpp'], dither=True)
        pic = to_rgb(pal, idx[0], *size)
        base = lose if it['group'] == 'lose' else win
        if it['mode'] == 'panel':
            col = (0xFF, 0x44, 0x44) if it['group'] == 'lose' else (0xFF, 0xDD, 0x33)
            scr = compose_panel(base, pic, col)
        else:
            scr = compose_full(base, up(pic, 4))
        fn = it['id'] + '.png'
        Image.fromarray(scr).save(os.path.join(OUT, fn))
        info['files'].append(fn)
        info['bytes'] = 2 * (1 << it['bpp']) + size[0] * size[1] * it['bpp'] // 8
        return info

    if kind == 'sprite':
        return do_sprite(it, info, play)

    # ---------------------------------------------------------- av
    fps, bpp = it['fps'], it['bpp']
    wav, secs = do_sound(it, info)
    src = it['src']
    pad = '0x00FF00' if it.get('key') else 'black'
    if it.get('loop'):
        ls, ld = it['loop']
        frames = read_video(src, fps, ls, ld, pad, it.get('crop'))
    else:
        frames = read_video(src, fps, it.get('start', 0), it.get('dur'), pad, it.get('crop'))
    pal, idx = quantise(frames, bpp, key=it.get('key'))
    # size: first frame whole, then only changes
    vbytes, prev = 0, None
    for k, a in enumerate(idx):
        vbytes += rle_bytes(a, prev, bpp)
        prev = a
    raw = len(idx) * W * H * bpp // 8
    info.update(frames=len(idx), video_bytes=vbytes, video_raw=raw,
                bytes=vbytes + info['sound_bytes'] + 2 * (1 << bpp))
    # render: clip alone, and in the game
    rgb = [up(to_rgb(pal, a), 4) for a in idx]
    keym = [up((a == 0).reshape(H, W), 4) for a in idx] if it.get('key') else None
    nout = int(secs * OUT_FPS)

    def pick(t):
        k = int(t * fps)
        return k % len(rgb) if it.get('loop') else min(k, len(rgb) - 1)

    fn = it['id'] + '_clip.mp4'
    write_mp4(os.path.join(OUT, fn), (rgb[pick(i / OUT_FPS)] for i in range(nout)), OUT_FPS, wav)
    info['files'].append(fn)

    mode = it['mode']
    if mode == 'bg':
        mask = see_through(play)
        jev = jevil_frames() if it['id'] == 'atk_jevil' else None

        def scene(i):
            t = i / OUT_FPS
            s = compose_bg(play, mask, rgb[pick(t)], it.get('dim', DIM))
            if jev:
                draw_jevil(s, jev, t)
            return s
        gen = (scene(i) for i in range(nout))
    elif mode == 'over':
        gen = (compose_over(play, rgb[pick(i / OUT_FPS)], keym[pick(i / OUT_FPS)]) for i in range(nout))
    else:
        base = lose if it['group'] == 'lose' else win
        gen = (compose_full(base, rgb[pick(i / OUT_FPS)]) for i in range(nout))
    fn = it['id'] + '_scene.mp4'
    write_mp4(os.path.join(OUT, fn), gen, OUT_FPS, wav)
    info['files'].append(fn)
    # a still for the page
    k = len(rgb) // 3
    still = {'bg': compose_bg(play, see_through(play), rgb[k], it.get('dim', DIM)) if mode == 'bg' else None,
             'over': compose_over(play, rgb[k], keym[k]) if keym else None,
             'full': compose_full(lose if it['group'] == 'lose' else win, rgb[k])}.get(mode)
    if mode == 'bg' and it['id'] == 'atk_jevil':
        draw_jevil(still, jevil_frames(), 1.3)
    if still is not None:
        Image.fromarray(still).save(os.path.join(OUT, it['id'] + '.png'))
        info['files'].append(it['id'] + '.png')
    return info


# ============================================================== sprites
_JEV = None


def jevil_frames():
    """Jevil gif -> 48 x 50, 4 bits (index 0 = see-through), drawn 2x"""
    global _JEV
    if _JEV:
        return _JEV
    it = next(p for p in PLAN if p['id'] == 'spr_jevil')
    w, h = it['size']
    im = Image.open(it['src'])
    frames = []
    for f in ImageSequence.Iterator(im):
        f = f.convert('RGBA').resize((w, h), Image.NEAREST)
        frames.append(np.array(f))
    # palette: the gif has 7 colours; keep them exactly (12-bit rounded)
    out = []
    for a in frames:
        rgb = a[..., :3].astype(np.int32)
        rgb = (np.minimum(15, (rgb + 8) // 17) * 17).astype(np.uint8)
        alpha = a[..., 3] > 127
        out.append((up(rgb, it['scale']), up(alpha, it['scale'])))
    _JEV = out
    return out


def draw_jevil(img, frames, t):
    """floats around the whole screen on a figure-of-eight; a new pose 15 times a second
    (every 4th screen frame)"""
    rgb, alpha = frames[int(t * 15) % len(frames)]
    h, w = alpha.shape
    x = int(320 - w / 2 + 230 * math.sin(2 * math.pi * t / 6.1))
    y = int(240 - h / 2 + 150 * math.sin(2 * math.pi * t / 3.7 + 0.6))
    x = max(0, min(640 - w, x))
    y = max(0, min(480 - h, y))
    reg = img[y:y + h, x:x + w]
    reg[alpha] = rgb[alpha]


def do_sprite(it, info, play):
    if it['id'] == 'spr_jevil':
        fr = jevil_frames()
        w, h = it['size']
        info['bytes'] = len(fr) * w * h * it['bpp'] // 8 + 32
        info['frames'] = len(fr)
        # Jevil floating over a plain game for 8 s
        gen = []
        for i in range(8 * OUT_FPS):
            s = play.copy()
            draw_jevil(s, fr, i / OUT_FPS)
            gen.append(s)
        fn = it['id'] + '_scene.mp4'
        write_mp4(os.path.join(OUT, fn), gen, OUT_FPS)
        info['files'].append(fn)
        return info
    # faces on the bouncers: 32 x 32, one 256-colour palette for all faces
    sz = it['size'][0]
    faces = [load_image(p, (sz, sz)) for p in it['src']]
    pal, idx = quantise(faces, 8, dither=True)
    tex = [to_rgb(pal, a, sz, sz) for a in idx]
    info['bytes'] = len(tex) * sz * sz + 512
    info['frames'] = len(tex)
    # chaos_render's bouncer speeds and start positions, field x 240..399, y 80..399
    SPX = (3, 2, 4, 3, 5, 2, 4, 1, 3, 5)
    SPY = (2, 3, 3, 4, 2, 5, 1, 4, 5, 3)
    bx = [250, 300, 330, 350, 260, 350, 280, 310, 360, 245]
    by = [100, 200, 300, 150, 360, 90, 240, 130, 330, 200]
    dx = [1, -1, 1, -1, -1, 1, 1, -1, 1, -1]
    dy = [-1, 1, 1, -1, 1, -1, -1, 1, 1, -1]
    nb = 8
    gen = []
    for i in range(10 * 60):                       # 10 s at the board's 60 frames a second
        for k in range(nb):
            bx[k] += dx[k] * SPX[k]
            by[k] += dy[k] * SPY[k]
            if bx[k] <= FX0 or bx[k] >= FX0 + 160 - sz: dx[k] = -dx[k]
            if by[k] <= FY0 or by[k] >= FY0 + 320 - sz: dy[k] = -dy[k]
            bx[k] = max(FX0, min(FX0 + 160 - sz, bx[k]))
            by[k] = max(FY0, min(FY0 + 320 - sz, by[k]))
        if i % 2:
            continue
        s = play.copy()
        for k in range(nb):
            s[by[k]:by[k] + sz, bx[k]:bx[k] + sz] = tex[k % len(tex)]
        gen.append(s)
    fn = it['id'] + '_scene.mp4'
    write_mp4(os.path.join(OUT, fn), gen, OUT_FPS)
    Image.fromarray(gen[40]).save(os.path.join(OUT, it['id'] + '.png'))
    info['files'] += [fn, it['id'] + '.png']
    return info


# ============================================================== main
def main():
    os.makedirs(OUT, exist_ok=True)
    os.chdir(ROOT)
    load_font()
    bases = screens()
    want = sys.argv[1:]
    bj = os.path.join(OUT, 'budget.json')
    old = {d['id']: d for d in json.load(open(bj, encoding='utf-8'))} if os.path.exists(bj) else {}
    for it in PLAN:
        if want and it['id'] not in want:
            continue
        print('...', it['id'], flush=True)
        old[it['id']] = do_item(it, bases)
    res = [old[p['id']] for p in PLAN if p['id'] in old]
    json.dump(res, open(bj, 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    total = 0
    print(f"\n{'id':22} {'keep':4} {'bytes':>10}  detail")
    for d in res:
        if d['keep']:
            total += d['bytes']
        det = ''
        if 'video_bytes' in d:
            det = f"video {d['video_bytes']:,} (raw {d['video_raw']:,}, {d['frames']} frames)"
        if 'sound_bytes' in d:
            det += f"  sound {d['sound_bytes']:,} ({d['seconds']} s)"
        print(f"{d['id']:22} {'yes' if d['keep'] else 'no':4} {d['bytes']:>10,}  {det}")
    print(f"\nproposed set: {total:,} bytes = {100 * total / FREE:.0f} % of {FREE:,}")


if __name__ == '__main__':
    main()
