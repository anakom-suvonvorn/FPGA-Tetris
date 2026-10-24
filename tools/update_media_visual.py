"""
update_media_visual.py - refresh the data inside docs/learn/media_visual.html

    python tools/update_media_visual.py

The page has two blocks of data written into it:
  SRC   the VHDL files of the media layer, so its code reader ("Read the code with help")
        shows the code exactly as it is now, with the right line numbers
  REAL  numbers read out of media/game_media.bin and media/media.bin (header,
        directory, record headers, sizes), for the file explorer ("What is in the flash")
Run this again after changing a VHDL file or rebuilding a media file. If a
media file is missing (it is not in git), its old numbers are kept.
"""
import json
import os
import re
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = os.path.join(ROOT, 'docs', 'learn', 'media_visual.html')
FILES = ['src/media/spi_flash.vhd', 'src/media/media_player.vhd', 'src/media/media_engine.vhd',
         'src/media/media_ctrl.vhd', 'src/media/media_mix.vhd', 'src/media/adpcm_dec.vhd',
         'game/top_tetris.vhd', 'tests/06_flash_read/top_flash_read.vhd']
BASE = 0x100000

# the items of the game file, in the order make_game_media.py writes them
ITEMS = [('music_teto_sv', 'Tetris (Teto SV)', 'music'), ('music_original', 'Tetris (original)', 'music'),
         ('atk_badapple', 'Bad Apple!!', 'attack'), ('atk_oiia_psy', 'OIIA OIIA (psytrance)', 'attack'),
         ('atk_jevil', 'JEVIL: THE WORLD REVOLVING', 'attack'), ('lose_rickroll', '10 rickrolls', 'lose'),
         ('lose_foxy', 'Foxy jump scare', 'lose'), ('lose_puppet', 'Puppet jump scare', 'lose'),
         ('lose_loss0', 'Loss (1)', 'lose'), ('lose_loss1', 'Loss (2)', 'lose'), ('lose_loss2', 'Loss (3)', 'lose'),
         ('lose_kakascream', 'Kaka scream', 'lose'), ('lose_kakadisappointed', 'Kaka disappointed', 'lose'),
         ('win_yippee', 'Yippee cat', 'win'), ('win_diabeetus', 'Diabeetus', 'win'),
         ('win_miku', 'Miku approves', 'win'), ('win_teto', 'Teto approves', 'win')]
CODES = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ -!:.?'


def u24(b):
    return struct.unpack('<I', bytes(b) + b'\0')[0]


def game_file(path):
    d = open(path, 'rb').read()
    items = []
    for i in range(d[5]):
        e = d[16 + 16 * i:32 + 16 * i]
        bpp, ft, mode, _, nrec, aud = struct.unpack('<BBBBHH', e[:8])
        pal, rec = u24(e[8:11]), u24(e[12:15])
        recs, pics = [], {}
        for r in range(nrec):
            o = rec - BASE + r * (8 + aud)
            x = d[o:o + 8]
            pa = u24(x[:3])
            pl, pred, idx = struct.unpack('<HhB', x[3:8])
            if r < 12:
                recs.append([pa, pl, pred, idx])
            if pl:
                pics[pa] = pl
        sizes = list(pics.values())
        end = max(a + l for a, l in pics.items()) if pics else rec + nrec * (8 + aud)
        iid, title, group = ITEMS[i] if i < len(ITEMS) else ('item%d' % i, 'item %d' % i, '?')
        items.append(dict(id=iid, title=title, group=group, bpp=bpp, ft=ft, mode=mode, nrec=nrec, aud=aud,
                          pal=pal, rec=rec, low8=e[15], npics=len(pics), picbytes=sum(sizes),
                          picmin=min(sizes) if sizes else 0, picmax=max(sizes) if sizes else 0,
                          recbytes=nrec * (8 + aud), palbytes=rec - pal, end=end, recs=recs, entry=list(e),
                          rec1=list(d[rec - BASE + (8 + aud):rec - BASE + (8 + aud) + 24]) if nrec > 1 else []))
    return dict(size=len(d), header=list(d[:16]), items=items, spr=u24(d[13:16]), sprlen=512 + 9600 + 4096)


def test06_file(path):
    m = open(path, 'rb').read()
    items = []
    for i in range(m[5]):
        e = m[16 + 32 * i:48 + 32 * i]
        bpp, ft, fl, _, nrec, aud, addr, rate, low = struct.unpack('<BBBBHHIHH', e[:16])
        items.append(dict(name=''.join(CODES[c] if c < len(CODES) else '?' for c in e[16:32]).rstrip(),
                          bpp=bpp, ft=ft, loop=fl & 1, nrec=nrec, aud=aud, addr=addr, rate=rate, low=low, entry=list(e)))
    return dict(size=len(m), header=list(m[:16]), items=items)


def main():
    page = open(PAGE, encoding='utf-8').read()
    old = re.search(r'/\*REAL-BEGIN\*/(.*?)/\*REAL-END\*/', page, re.S).group(1)
    real = json.loads(old) if old.strip() not in ('', 'null') else {}
    g = os.path.join(ROOT, 'media', 'game_media.bin')
    t = os.path.join(ROOT, 'media', 'media.bin')
    if os.path.exists(g):
        real['game'] = game_file(g)
    if os.path.exists(t):
        real['t6'] = test06_file(t)
    src = {}
    for f in FILES:
        src[os.path.basename(f)] = open(os.path.join(ROOT, f), encoding='utf-8').read().rstrip('\n').split('\n')
    s_real = json.dumps(real, separators=(',', ':'))
    s_src = json.dumps(src, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
    page = re.sub(r'/\*REAL-BEGIN\*/.*?/\*REAL-END\*/', lambda m: '/*REAL-BEGIN*/' + s_real + '/*REAL-END*/', page, flags=re.S)
    page = re.sub(r'/\*SRC-BEGIN\*/.*?/\*SRC-END\*/', lambda m: '/*SRC-BEGIN*/' + s_src + '/*SRC-END*/', page, flags=re.S)
    open(PAGE, 'w', encoding='utf-8', newline='\n').write(page)
    print(f'updated {PAGE}: {len(src)} source files, media data: {", ".join(sorted(real)) or "none"}')


if __name__ == '__main__':
    main()
