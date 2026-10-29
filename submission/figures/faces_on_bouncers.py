# faces_on_bouncers.py: the screenshots for the documents.
#   python submission\figures\faces_on_bouncers.py
# sim\tb_chaos_frame.vhd simulates the whole game without a flash chip, so
# its BOUNCERS are plain coloured squares. On the board media_engine draws a
# friend's face on each one. This script does the same thing to the
# simulated picture, with the hardware's rule (chaos_render.vhd):
#   bouncer i (colour BCOL(i)) wears face (i mod 4 + foff) mod 4,
#   face pixel = faces[face][row * 32 + column], colour = sprite palette,
# reading the faces and the palette from media\game_media.bin (the sprite
# block at the address in the file header).
# Writes figures\screenshot_chaos_on.png (frame0), screenshot_chaos_task.png
# (frame) and screenshot_chaos_flip.png (frame2, with the faces).
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, 'sim', 'out')
BASE = 0x100000
BCOL = [0xF2F, 0x2FF, 0xFF2, 0xFFF, 0xF80, 0x8F2, 0xF44, 0x48F, 0xFAF, 0x0F8]   # chaos_render.vhd
FX0, FY0, FW, FH, BQ = 240, 80, 160, 320, 32
FOFF = 0


def sprite_faces():
    d = open(os.path.join(ROOT, 'media', 'game_media.bin'), 'rb').read()
    spr = int.from_bytes(d[13:16], 'little') - BASE
    pal = []
    for i in range(256):
        v = int.from_bytes(d[spr + 2 * i:spr + 2 * i + 2], 'little')
        pal.append(((v >> 8) & 15, (v >> 4) & 15, v & 15))
    faces = d[spr + 512 + 9600:spr + 512 + 9600 + 4096]
    return pal, faces


def put_faces(img):
    a = np.array(img.convert('RGB')).astype(int)
    pal, faces = sprite_faces()
    field = a[FY0:FY0 + FH, FX0:FX0 + FW]
    for i, c in enumerate(BCOL):
        rgb = np.array([(c >> 8) * 17, ((c >> 4) & 15) * 17, (c & 15) * 17])
        ys, xs = np.where((field == rgb).all(2))
        if len(xs) < 64:
            continue                                   # this bouncer is not on screen
        # its top-left corner: the box is 32 x 32; a later bouncer may hide part of it
        x0 = xs.min() if xs.max() - xs.min() >= BQ - 1 else max(xs.max() - BQ + 1, 0)
        y0 = ys.min() if ys.max() - ys.min() >= BQ - 1 else max(ys.max() - BQ + 1, 0)
        f = (i % 4 + FOFF) % 4
        for r in range(BQ):
            for k in range(BQ):
                if (field[y0 + r, x0 + k] == rgb).all():  # only where this bouncer shows
                    pr, pg, pb = pal[faces[f * 1024 + r * 32 + k]]
                    a[FY0 + y0 + r, FX0 + x0 + k] = (pr * 17, pg * 17, pb * 17)
        print(f'bouncer {i}: corner ({FX0 + x0}, {FY0 + y0}), face {f}')
    return Image.fromarray(a.astype('uint8'))


if __name__ == '__main__':
    Image.open(os.path.join(OUT, 'frame0.png')).save(os.path.join(HERE, 'screenshot_chaos_on.png'))
    Image.open(os.path.join(OUT, 'frame.png')).save(os.path.join(HERE, 'screenshot_chaos_task.png'))
    put_faces(Image.open(os.path.join(OUT, 'frame2.png'))).save(os.path.join(HERE, 'screenshot_chaos_flip.png'))
    print('wrote screenshot_chaos_on / _task / _flip')
