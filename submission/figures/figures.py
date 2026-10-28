# figures.py: draws every figure of the submission documents as SVG, then
# renders each one to PNG with headless Chrome (2x, for sharp printing).
#   python submission\figures\figures.py            all figures
#   python submission\figures\figures.py fsm link   only these
# Output: submission\figures\fig_<name>.png (+ the .html it was rendered from
# in figures\_html, git-ignored).
import os, sys, subprocess, html, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_HTML = os.path.join(HERE, '_html')
CHROME = [r'C:\Program Files\Google\Chrome\Application\chrome.exe',
          r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe']

INK, MUTED, LINE, BG = '#1d2433', '#5b6475', '#9aa5b8', '#ffffff'
C = {  # group colours: (stroke, fill)
    'in':    ('#2563eb', '#e8f0fe'),
    'core':  ('#7c3aed', '#f1eafe'),
    'link':  ('#059669', '#e3f6ef'),
    'chaos': ('#dc2626', '#fdeaea'),
    'video': ('#d97706', '#fdf3e2'),
    'media': ('#db2777', '#fce9f2'),
    'sound': ('#0d9488', '#e2f5f3'),
    'pin':   ('#475569', '#eef1f5'),
    'pc':    ('#334155', '#f6f7f9'),
}
FONT = "'IBM Plex Sans Thai','Leelawadee UI','Tahoma',sans-serif"
MONO = "'IBM Plex Mono','Consolas',monospace"


def esc(s):
    return html.escape(str(s), quote=True)


class Fig:
    def __init__(self, w, h):
        self.w, self.h, self.parts = w, h, []

    def add(self, s):
        self.parts.append(s)

    def text(self, x, y, s, size=16, weight=400, anchor='start', color=INK, mono=False, italic=False):
        fam = MONO if mono else FONT
        st = ' font-style="italic"' if italic else ''
        self.add(f'<text x="{x}" y="{y}" font-family="{fam}" font-size="{size}" font-weight="{weight}" '
                 f'text-anchor="{anchor}" fill="{color}"{st}>{esc(s)}</text>')

    def lines(self, x, y, rows, size=14, gap=None, **kw):
        gap = gap or size * 1.35
        for i, r in enumerate(rows):
            self.text(x, y + i * gap, r, size=size, **kw)

    def rect(self, x, y, w, h, stroke=LINE, fill='none', r=10, sw=2, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ''
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')

    def box(self, x, y, w, h, title, sub=(), g='pin', mono=True, tsize=17, ssize=13, center=True, r=10):
        st, fi = C[g]
        self.rect(x, y, w, h, st, fi, r=r)
        n = len(sub)
        total = tsize + (n * ssize * 1.35)
        ty = y + h / 2 - total / 2 + tsize * 0.85
        cx = x + w / 2 if center else x + 12
        anc = 'middle' if center else 'start'
        self.text(cx, ty, title, size=tsize, weight=700, anchor=anc, color=st, mono=mono)
        for i, s in enumerate(sub):
            self.text(cx, ty + tsize * 0.45 + (i + 1) * ssize * 1.35 - 2, s, size=ssize, anchor=anc, color=INK)

    def arrow(self, pts, label=None, color=MUTED, dash=None, both=False, lpos=0.5, ldx=0, ldy=-6,
              lsize=12.5, lanchor='middle', sw=2):
        d = 'M' + ' L'.join(f'{x},{y}' for x, y in pts)
        mid = color.replace('#', '')
        da = f' stroke-dasharray="{dash}"' if dash else ''
        ms = f' marker-start="url(#s{mid})"' if both else ''
        self.add(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{sw}"{da} marker-end="url(#a{mid})"{ms}/>')
        self.markers.add(color)
        if label:
            # label on the longest segment
            best, bi = -1, 0
            for i in range(len(pts) - 1):
                l = abs(pts[i + 1][0] - pts[i][0]) + abs(pts[i + 1][1] - pts[i][1])
                if l > best:
                    best, bi = l, i
            (x1, y1), (x2, y2) = pts[bi], pts[bi + 1]
            lx, ly = x1 + (x2 - x1) * lpos + ldx, y1 + (y2 - y1) * lpos + ldy
            rows = label if isinstance(label, (list, tuple)) else [label]
            for i, r in enumerate(rows):
                self.add(f'<text x="{lx}" y="{ly + i * lsize * 1.3}" font-family="{FONT}" font-size="{lsize}" '
                         f'text-anchor="{lanchor}" fill="{color}" paint-order="stroke" stroke="#fff" '
                         f'stroke-width="5" stroke-linejoin="round">{esc(r)}</text>')

    markers = set()

    def svg(self):
        defs = []
        for col in sorted(self.markers):
            m = col.replace('#', '')
            defs.append(f'<marker id="a{m}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{col}"/></marker>')
            defs.append(f'<marker id="s{m}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{col}"/></marker>')
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}">'
                f'<defs>{"".join(defs)}</defs><rect width="100%" height="100%" fill="{BG}"/>' + ''.join(self.parts) + '</svg>')


def new(w, h):
    f = Fig(w, h)
    f.markers = set()
    return f


# ---------------------------------------------------------------- figures
def fig_system():
    f = new(1400, 660)
    for side, bx, mir in (('A', 50, False), ('B', 920, True)):
        mx = bx + 75
        f.rect(mx, 20, 280, 140, '#334155', '#1e293b', r=12, sw=3)
        f.rect(mx + 14, 32, 252, 104, '#475569', '#0f172a', r=4, sw=1)
        f.text(mx + 140, 80, f'จอ VGA ผู้เล่น {side}', 18, 700, 'middle', '#e2e8f0')
        f.text(mx + 140, 106, '640 × 480, สี 12 บิต', 14, 400, 'middle', '#94a3b8')
        f.rect(mx + 120, 160, 40, 16, '#334155', '#334155', r=2)
        f.rect(bx, 200, 430, 300, '#166534', '#ecfdf3', r=14, sw=3)
        f.text(bx + (414 if mir else 16), 226, f'บอร์ด {side}: EDGE Spartan-7', 16, 700, 'end' if mir else 'start', '#166534')
        f.box(bx + 120, 248, 190, 110, 'XC7S15 FPGA', ['วงจร top_tetris', '50 MHz, 8,000 LUT', 'block RAM 45 KB'], 'core', tsize=16)
        f.box(bx + 120, 380, 190, 100, 'SPI Flash 8 MB', ['เพลง วิดีโอ รูป', '6.9 MB'], 'media', tsize=16)
        io_x, out_x = (bx + 324, bx + 14) if mir else (bx + 14, bx + 324)
        f.box(io_x, 248, 92, 70, 'ปุ่ม 5', ['บังคับบล็อก'], 'in', mono=False, tsize=15, ssize=12)
        f.box(io_x, 330, 92, 70, 'สวิตช์ 16', ['ภารกิจ/ตั้งค่า'], 'in', mono=False, tsize=15, ssize=12)
        f.box(io_x, 412, 92, 70, '7-seg', ['แถวที่ล้าง'], 'sound', mono=False, tsize=15, ssize=12)
        f.box(out_x, 412, 92, 70, 'ช่องหูฟัง', ['เสียง'], 'sound', mono=False, tsize=15, ssize=12)
        f.box(out_x, 248, 92, 70, 'J5', ['TX RX GND'], 'link', mono=False, tsize=15, ssize=12)
        f.arrow([(bx + 215, 248), (bx + 215, 180)], 'VGA', '#334155', ldx=24, ldy=-14)
        f.arrow([(bx + 215, 358), (bx + 215, 380)], None, C['media'][0], both=True)
        fl, fr = bx + 120, bx + 310
        ii, oo = (fr, fl) if mir else (fl, fr)
        e_io = io_x if mir else io_x + 92
        e_out = out_x + 92 if mir else out_x
        f.arrow([(e_io, 283), (ii, 283)], None, C['in'][0])
        f.arrow([(e_io, 365), (ii, 340)], None, C['in'][0])
        f.arrow([(ii, 350), (e_io, 440)], None, C['sound'][0])
        f.arrow([(oo, 350), (e_out, 440)], None, C['sound'][0])
        f.arrow([(oo, 283), (e_out, 283)], None, C['link'][0], both=True)
        hx = out_x + 46
        f.add(f'<path d="M{hx - 28},{570} a28,28 0 0 1 56,0" fill="none" stroke="#0d9488" stroke-width="5"/>')
        f.rect(hx - 36, 566, 16, 30, '#0d9488', '#0d9488', r=5)
        f.rect(hx + 20, 566, 16, 30, '#0d9488', '#0d9488', r=5)
        f.text(hx, 625, 'หูฟัง / ลำโพง', 14, 600, 'middle', '#0d9488')
        f.arrow([(hx, 482), (hx, 538)], None, '#0d9488')
    ax, bxx = 50 + 416, 920 + 14
    labels = ['ขา 5 TX  →  330 Ω  →  ขา 6 RX', 'ขา 6 RX  ←  330 Ω  ←  ขา 5 TX', 'ขา 2 GND  ———  ขา 2 GND']
    for y, col in zip([262, 284, 306], ['#059669', '#0891b2', '#334155']):
        f.add(f'<path d="M{ax},{y} C{ax + 140},{y + 90} {bxx - 140},{y + 90} {bxx},{y}" fill="none" stroke="{col}" stroke-width="4"/>')
    f.rect(560, 120, 290, 106, '#059669', '#ffffff', r=10)
    f.text(705, 146, 'สายเชื่อม 3 เส้น (J5)', 16, 700, 'middle', '#059669')
    f.lines(705, 170, ['UART 115,200 bps', 'ข้อความ 1 ไบต์: garbage, ความสูง,', 'แพ้, เริ่มเกม, การโจมตี'], 13, anchor='middle')
    f.lines(705, 410, labels, 13, gap=20, anchor='middle', color='#334155', mono=True)
    f.rect(520, 520, 370, 120, '#334155', '#f6f7f9', r=12, dash='6 5')
    f.text(705, 548, 'คอมพิวเตอร์ (ใช้ครั้งเดียวก่อนเล่น)', 15, 700, 'middle', '#334155')
    f.lines(705, 574, ['Vivado: สร้างไฟล์ .bit → โหลดลง FPGA', 'Python: แปลงวิดีโอ/เพลง/รูป → game_media.bin', '→ เขียนลง SPI Flash ของทั้งสองบอร์ด'], 13, anchor='middle')
    f.arrow([(520, 560), (290, 482)], None, '#334155', dash='6 5')
    f.arrow([(890, 560), (1110, 482)], None, '#334155', dash='6 5')
    return f


def fig_hierarchy():
    f = new(1720, 820)
    lv = [(40, 'ระดับ 0'), (160, 'ระดับ 1'), (300, 'ระดับ 2'), (450, 'ระดับ 3')]
    for y, s in lv:
        f.text(16, y + 32, s, 15, 700, 'start', MUTED)
    f.box(660, 30, 420, 64, 'Tetris Duel: CHAOS Edition', ['ระบบทั้งหมด: 2 บอร์ด + สายเชื่อม'], 'pc', mono=False, tsize=18)
    l1 = [(170, 'บอร์ด A: top_tetris', ['วงจรของผู้เล่นหนึ่งคน'], 'core'),
          (720, 'สายเชื่อม J5', ['UART 115,200 bps, 3 เส้น'], 'link'),
          (1270, 'บอร์ด B: top_tetris', ['วงจรเดียวกันทุกบิต'], 'core')]
    for x, t, s, g in l1:
        f.box(x, 150, 300, 64, t, s, g, mono=False, tsize=17)
        f.arrow([(870, 94), (870, 120), (x + 150, 120), (x + 150, 150)], None, LINE)
    groups = [
        ('in', 'อินพุต', [('switch_filter', 'กรองสวิตช์เด้ง'), ('tetris_input', 'ปุ่ม: กดครั้งเดียว/ค้าง'), ('  └ debounce', 'กรองปุ่มเด้ง')]),
        ('core', 'กติกาเกม', [('tetris_core', 'FSM 23 สถานะ'), ('', 'กระดาน 10×20, ตรวจชน'), ('', '7-bag, ล้างแถว, garbage')]),
        ('link', 'การสื่อสาร', [('versus_link', 'โปรโตคอล 1 ไบต์'), ('  └ uart_tx', 'ส่งทีละบิต'), ('  └ uart_rx', 'รับทีละบิต')]),
        ('chaos', 'CHAOS', [('chaos_task', 'สุ่ม/ตรวจภารกิจ'), ('chaos_fx', 'ผลการโจมตี/โบนัส'), ('chaos_render', 'แผงภารกิจ, ลูกบอล'), ('  └ text_multi', 'ข้อความ')]),
        ('video', 'ภาพ', [('vga_sync', 'x, y, sync 59.5 Hz'), ('tetris_render', 'วาดเกม'), ('  └ text_multi', 'ข้อความ (ROM ฟอนต์)'), ('media_mix', 'ซ้อนวิดีโอ + sprite')]),
        ('media', 'สื่อจากแฟลช', [('media_ctrl', 'เลือกว่าเล่นอะไร'), ('media_engine', 'เครื่องเล่นสื่อ'), ('  └ spi_flash', 'อ่านแฟลช 25 MHz'), ('  └ adpcm_dec', 'ถอดรหัสเสียง')]),
        ('sound', 'เสียง + ตัวเลข', [('tetris_sound', 'ผสมเสียง, sigma-delta'), ('seg7_scan', 'สแกน 7-segment')]),
    ]
    gw, gx0 = 226, 100
    for i, (g, name, mods) in enumerate(groups):
        x = gx0 + i * (gw + 6)
        f.box(x, 300, gw, 56, name, [], g, mono=False, tsize=18)
        f.arrow([(320, 214), (320, 260), (x + gw / 2, 260), (x + gw / 2, 300)], None, LINE)
        y = 400
        for nm, ds in mods:
            st, fi = C[g]
            if nm == '':
                f.text(x + 12, y + 8, ds, 13, 400, 'start', INK)
                y += 24
                continue
            ind = 20 if nm.startswith('  ') else 0
            f.rect(x + ind, y, gw - ind, 58, st, fi, r=8, sw=1.6)
            f.text(x + ind + 10, y + 24, nm.strip().replace('└ ', ''), 15, 700, 'start', st, mono=True)
            f.text(x + ind + 10, y + 45, ds, 13, 400, 'start', INK)
            y += 68
    f.rect(100, 750, 1610, 50, LINE, '#f6f7f9', r=8, sw=1)
    f.text(120, 781, 'แพ็กเกจที่ทุกโมดูลใช้ร่วมกัน: common_pkg (ค่าคงที่ของบอร์ด) · tetris_pkg (รูปบล็อก, สี) · text_pkg (ฟอนต์ 5×7) · chaos_pkg (ภารกิจ, การโจมตี, ระยะเวลา)', 14, 400, 'start', INK)
    return f


def fig_blocks():
    f = new(1580, 960)
    B = {}

    def b(k, x, y, w, h, t, s, g, mono=True):
        B[k] = (x, y, w, h)
        f.box(x, y, w, h, t, s, g, mono=mono, tsize=16, ssize=12.5)

    b('btn', 20, 85, 140, 60, 'ปุ่มกด 5', [], 'pin', False)
    b('sw', 20, 260, 140, 60, 'สวิตช์ 16', [], 'pin', False)
    b('j5', 20, 410, 140, 80, 'J5', ['TX / RX'], 'pin', False)
    b('fl', 20, 600, 140, 80, 'SPI Flash', ['8 MB'], 'pin', False)
    b('vga', 1420, 85, 140, 60, 'จอ VGA', [], 'pin', False)
    b('aud', 1420, 715, 140, 80, 'หูฟัง', ['+ บัซเซอร์'], 'pin', False)
    b('segp', 1420, 850, 140, 80, '7-segment', [], 'pin', False)
    b('inp', 210, 75, 220, 80, 'tetris_input', ['debounce + กดค้าง'], 'in')
    b('swf', 210, 250, 220, 80, 'switch_filter', ['กรองสวิตช์เด้ง', '+ ตั้งค่า SW2-SW7'], 'in')
    b('link', 210, 400, 220, 100, 'versus_link', ['UART 115,200 bps', 'ข้อความ 1 ไบต์'], 'link')
    b('eng', 210, 560, 220, 160, 'media_engine', ['spi_flash · adpcm_dec', 'frame buffer 160×120', 'sound ring 2 KB'], 'media')
    b('ctrl', 210, 800, 220, 110, 'media_ctrl', ['เลือกว่าจะเล่นอะไร', 'ฟังเหตุการณ์จาก', 'tetris_core / chaos_fx'], 'media')
    b('core', 490, 40, 240, 150, 'tetris_core', ['state machine 23 สถานะ', 'กระดาน 10 × 20', 'ตรวจชน · 7-bag · garbage'], 'core')
    b('task', 490, 250, 240, 80, 'chaos_task', ['สุ่มภารกิจ · ตรวจผล'], 'chaos')
    b('fx', 490, 410, 240, 80, 'chaos_fx', ['ผลการโจมตี / โบนัส'], 'chaos')
    b('sync', 490, 800, 240, 110, 'vga_sync', ['x, y, frame_tick (59.5 Hz)', 'ส่งให้ทุกโมดูล', '(ไม่ได้วาดเส้น)'], 'video')
    b('rend', 800, 40, 240, 150, 'tetris_render', ['กระดาน บล็อก ghost', 'ข้อความ แถบ RIVAL', '(+ text_multi)'], 'video')
    b('cren', 800, 250, 240, 80, 'chaos_render', ['แผงภารกิจ · ลูกบอล'], 'chaos')
    b('mix', 1110, 40, 240, 150, 'media_mix', ['ชั้นวิดีโอ / sprite', 'ซ้อนกับภาพเกม'], 'video')
    b('snd', 1110, 700, 240, 110, 'tetris_sound', ['ผสมเพลง + เอฟเฟกต์', 'sigma-delta 12 บิต'], 'sound')
    b('seg', 1110, 850, 240, 80, 'seg7_scan', ['lines จาก tetris_core'], 'sound')
    A = f.arrow
    A([(160, 115), (210, 115)])
    A([(430, 115), (490, 115)], 'ปุ่ม', C['in'][0])
    A([(730, 115), (800, 115)], 'กระดาน', C['core'][0])
    A([(1040, 115), (1110, 115)], 'สีเกม', C['video'][0])
    A([(1350, 115), (1420, 115)], 'RGB', C['video'][0])
    A([(160, 290), (210, 290)])
    A([(430, 290), (490, 290)], 'สวิตช์ 8', C['in'][0])
    A([(730, 290), (800, 290)], None, C['chaos'][0])
    A([(920, 250), (920, 190)], 'overlay', C['chaos'][0], ldx=34, ldy=4)
    A([(160, 450), (210, 450)], None, C['link'][0], both=True)
    A([(430, 450), (490, 450)], 'ได้รับ', C['chaos'][0])
    A([(430, 420), (460, 420), (460, 165), (490, 165)], None, C['link'][0], both=True)
    f.lines(320, 190, ['garbage, ความสูง,', 'LOST, START'], 12.5, anchor='middle', color=C['link'][0])
    A([(520, 330), (520, 375), (400, 375), (400, 400)], 'ATTACK id', C['chaos'][0], ldy=-7)
    A([(730, 430), (755, 430), (755, 172), (730, 172)], None, C['chaos'][0])
    A([(730, 455), (775, 455), (775, 172), (800, 172)], None, C['chaos'][0])
    A([(730, 478), (790, 478), (790, 312), (800, 312)], None, C['chaos'][0])
    f.text(748, 222, 'ผลต่อเกม', 12, 600, 'end', C['chaos'][0])
    f.text(782, 222, 'ผลต่อภาพ', 12, 600, 'start', C['chaos'][0])
    f.text(800, 372, 'BOUNCERS', 12, 600, 'start', C['chaos'][0])
    f.lines(800, 400, ['เกม: FREEZE SPEED SINK CURSED LOCK +3', 'ภาพ: MIRROR FLIP BLIND'], 12, gap=18, color=C['chaos'][0])
    A([(160, 640), (210, 640)], 'SPI', C['media'][0], both=True, ldy=-8)
    A([(430, 600), (1230, 600), (1230, 190)], 'สีวิดีโอ + sprite', C['media'][0], ldy=-8)
    A([(430, 660), (1080, 660), (1080, 740), (1110, 740)], 'เสียง PCM 16 บิต', C['media'][0], ldy=-8)
    A([(320, 800), (320, 720)], 'play(item)', C['media'][0], ldx=40, ldy=4)
    A([(1350, 755), (1420, 755)], None, C['sound'][0])
    A([(1350, 890), (1420, 890)], None, C['sound'][0])
    return f


def fig_fsm():
    f = new(1560, 760)
    W, H = 128, 48
    P = {}

    def node(k, x, y, g='core'):
        P[k] = (x, y)
        st, fi = C[g]
        f.rect(x, y, W, H, st, fi, r=22, sw=2)
        f.text(x + W / 2, y + 30, k, 14, 700, 'middle', st, mono=True)

    def band(y, h, label, g):
        st, fi = C[g]
        f.rect(8, y, 1544, h, st, '#ffffff', r=14, sw=1.2, dash='5 4')
        f.text(20, y + 20, label, 13, 700, 'start', st)

    band(30, 120, 'เริ่มเกม / บล็อกใหม่', 'link')
    band(190, 215, 'ทุกเฟรม (frame_tick 60 ครั้งต่อวินาที): ลองหมุน → ลองเลื่อน → ลองตก → หาเงา → ล็อกหรือยัง', 'core')
    band(430, 150, 'เมื่อบล็อกล็อก', 'video')
    band(600, 140, 'โบนัส CHAOS', 'chaos')
    for i, k in enumerate(['S_IDLE', 'S_INIT', 'S_PICK', 'S_SPAWN', 'S_SPAWN_CHK']):
        node(k, 60 + i * 190, 70, 'link')
    row2 = ['S_PLAY', 'S_ROT', 'S_ROT_CHK', 'S_MOVE', 'S_MOVE_CHK', 'S_DOWN', 'S_DOWN_CHK', 'S_GHOST', 'S_GHOST_CHK', 'S_LOCKCHK']
    for i, k in enumerate(row2):
        node(k, 24 + i * 152, 262)
    for i, k in enumerate(['S_LOCK', 'S_CLEAR', 'S_SCORE', 'S_ATTACK', 'S_HOLE', 'S_GARB']):
        node(k, 24 + 9 * 152 - i * 200, 476, 'video')
    node('S_SINK', 24, 660, 'chaos')
    node('S_SINK_CHK', 230, 660, 'chaos')

    def r(k): return (P[k][0] + W, P[k][1] + H / 2)
    def l(k): return (P[k][0], P[k][1] + H / 2)
    def t(k, dx=0): return (P[k][0] + W / 2 + dx, P[k][1])
    def bo(k, dx=0): return (P[k][0] + W / 2 + dx, P[k][1] + H)

    A = f.arrow
    A([r('S_IDLE'), l('S_INIT')], 'START', '#059669', ldy=-8)
    A([r('S_INIT'), l('S_PICK')], None, '#059669')
    A([r('S_PICK'), l('S_SPAWN')], '7-bag', '#059669', ldy=-8)
    A([r('S_SPAWN'), l('S_SPAWN_CHK')], None, '#059669')
    A([bo('S_SPAWN_CHK'), (P['S_SPAWN_CHK'][0] + W / 2, 170), (P['S_GHOST'][0] + W / 2, 170), t('S_GHOST')], 'วางได้', '#059669', lpos=0.5)
    # connector pills
    def pill(x, y, s, col):
        f.rect(x, y, len(s) * 7.6 + 22, 26, col, '#ffffff', r=13, sw=1.5)
        f.text(x + 11, y + 18, s, 12.5, 600, 'start', col)

    A([r('S_SPAWN_CHK'), (1010, 94)], None, '#dc2626')
    pill(1012, 81, '→ S_IDLE: ไม่มีที่วาง = แพ้, ส่ง LOST', '#dc2626')
    for a, b2 in zip(row2, row2[1:]):
        A([r(a), l(b2)], None, C['core'][0])
    # skip arcs below the row
    for a, b2, lab in (('S_ROT', 'S_MOVE', 'ไม่ได้กดหมุน'), ('S_MOVE', 'S_MOVE_CHK', None), ('S_MOVE', 'S_DOWN', 'ไม่ได้กดเลื่อน'), ('S_DOWN', 'S_GHOST', 'ยังไม่ถึงเวลาตก')):
        if b2 == 'S_MOVE_CHK':
            continue
        x1, x2 = P[a][0] + W / 2, P[b2][0] + W / 2
        A([(x1, 310), (x1, 345), (x2, 345), (x2, 310)], lab, MUTED, ldy=16)
    # loop back
    x1, x2 = P['S_LOCKCHK'][0] + W / 2, P['S_PLAY'][0] + W / 2
    A([(x1 + 20, 310), (x1 + 20, 378), (x2, 378), (x2, 310)], 'ยังไม่ล็อก: รอ frame_tick ถัดไป', C['core'][0], lpos=0.5, ldy=18)
    A([bo('S_LOCKCHK', -20), (P['S_LOCKCHK'][0] + W / 2 - 20, 476)], ['พื้นใต้บล็อก 0.5 วิ', 'หรือ hard drop'], C['video'][0], ldx=-80, ldy=-2)
    row3 = ['S_LOCK', 'S_CLEAR', 'S_SCORE', 'S_ATTACK', 'S_HOLE', 'S_GARB']
    labs = [None, None, None, 'มีขยะรอ', None]
    f.text(P['S_LOCK'][0] + W / 2, 544, 'ใช้ 4 clock', 12.5, 400, 'middle', C['video'][0])
    f.text(P['S_CLEAR'][0] + W / 2, 544, '1 แถวต่อ clock', 12.5, 400, 'middle', C['video'][0])
    for (a, b2), lab in zip(zip(row3, row3[1:]), labs):
        A([l(a), r(b2)], lab, C['video'][0], ldy=-8)
    A([bo('S_ATTACK'), (P['S_ATTACK'][0] + W / 2, 541)], None, C['video'][0])
    pill(P['S_ATTACK'][0] - 10, 542, '→ S_PICK (ไม่มีขยะรอ)', C['video'][0])
    A([bo('S_GARB'), (P['S_GARB'][0] + W / 2, 541)], None, C['video'][0])
    pill(P['S_GARB'][0] - 70, 542, '→ S_PICK  หรือ  → S_IDLE (ล้นจอ = แพ้)', C['video'][0])
    # sink
    A([bo('S_PLAY'), (P['S_PLAY'][0] + W / 2, 660)], 'โบนัส SINK', C['chaos'][0], ldx=46, lpos=0.72)
    A([r('S_SINK'), l('S_SINK_CHK')], None, C['chaos'][0])
    A([r('S_SINK_CHK'), (420, 684)], None, C['chaos'][0])
    pill(422, 671, '→ S_GHOST (ยังวางได้)  หรือ  → S_IDLE (แพ้)', C['chaos'][0])
    f.lines(840, 668, ['แต่ละสถานะใช้ 1-2 clock: ทั้งรอบใช้ไม่กี่ร้อย clock', 'จาก 840,000 clock ต่อเฟรม (16.8 ms)',
                       '"_CHK" = ดูผลจากตัวตรวจชนตัวเดียวที่ใช้ร่วมกัน'], 13.5, color=MUTED)
    return f


def fig_link():
    f = new(1400, 600)
    f.text(30, 40, 'ข้อความ 1 ไบต์ (8 บิต)', 19, 700)
    x0 = 30
    for i in range(8):
        bit = 7 - i
        g = 'link' if bit >= 5 else 'core'
        st, fi = C[g]
        f.rect(x0 + i * 66, 60, 62, 56, st, fi, r=6)
        f.text(x0 + i * 66 + 31, 95, f'b{bit}', 16, 700, 'middle', st, mono=True)
    f.text(x0 + 99, 140, 'ชนิด (3 บิต)', 15, 700, 'middle', C['link'][0])
    f.text(x0 + 3 * 66 + 163, 140, 'ค่า (5 บิต: 0-31)', 15, 700, 'middle', C['core'][0])
    rows = [('0', 'HEARTBEAT', 'ความสูงกองบล็อกของฉัน', 'ทุก 6 เฟรม (10 ครั้ง/วิ)'),
            ('1', 'GARBAGE', 'จำนวนแถวขยะที่ส่ง', 'เมื่อล้าง 2-4 แถว'),
            ('2', 'LOST', '-', 'เมื่อแพ้'),
            ('3', 'START', '-', 'เมื่อกดเริ่มเกม'),
            ('4', 'ATTACK', 'หมายเลขการโจมตี 0-10', 'เมื่อทำภารกิจสำเร็จ'),
            ('5-7', '(ว่าง)', '', '')]
    y = 170
    hdr = ['ชนิด', 'ชื่อ', 'ค่า 5 บิต', 'ส่งเมื่อ']
    xs = [30, 100, 250, 470]
    for xx, h in zip(xs, hdr):
        f.text(xx, y, h, 14, 700, 'start', MUTED)
    for i, rw in enumerate(rows):
        yy = y + 30 + i * 30
        f.add(f'<line x1="30" x2="680" y1="{yy - 20}" y2="{yy - 20}" stroke="#e5e7eb"/>')
        for xx, v, m in zip(xs, rw, (True, True, False, False)):
            f.text(xx, yy, v, 14, 600 if m else 400, 'start', INK, mono=m)
    # UART frame
    f.text(740, 40, 'บนสาย: 1 ไบต์ = 10 บิต (UART 8N1)', 19, 700)
    bits = ['idle', 'start', 'b0', 'b1', 'b2', 'b3', 'b4', 'b5', 'b6', 'b7', 'stop', 'idle']
    lv = [1, 0, 1, 0, 0, 1, 1, 0, 0, 0, 1, 1]  # 0x19 = GARBAGE? b7..0=00011001 -> LSB first 1,0,0,1,1,0,0,0
    lv = [1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1]  # 0x22 sent LSB first
    bw = 52
    pts = []
    for i, v in enumerate(lv):
        yv = 80 if v else 130
        pts += [(740 + i * bw, yv), (740 + (i + 1) * bw, yv)]
    f.add('<path d="M' + ' L'.join(f'{x},{y}' for x, y in pts) + '" fill="none" stroke="#059669" stroke-width="3"/>')
    for i, bt in enumerate(bits):
        f.text(740 + i * bw + bw / 2, 160, bt, 12.5, 600, 'middle', MUTED, mono=True)
        f.add(f'<line x1="{740 + i * bw}" x2="{740 + i * bw}" y1="70" y2="140" stroke="#e5e7eb"/>')
    f.lines(740, 200, ['ตัวอย่าง: 0x22 = 001 00010 = GARBAGE 2 แถว (ส่งบิตต่ำ b0 ก่อน)',
                       'หนึ่งบิตยาว 434 clock ของ 50 MHz = 8.68 µs → 115,200 บิตต่อวินาที',
                       'หนึ่งไบต์ใช้เวลา 87 µs (เฟรมภาพหนึ่งเฟรม = 16,800 µs)',
                       'ฝั่งรับสุ่มอ่านกลางบิต และผ่าน flip-flop 2 ตัวก่อนใช้ (กัน metastability)'], 14, gap=24)
    # rules
    f.rect(30, 400, 1340, 180, '#059669', '#f3fbf8', r=12, sw=1.5)
    f.text(50, 432, 'กติกาที่ทำให้สองบอร์ดตัดสินตรงกันโดยไม่ต้องมีบอร์ดหลัก', 17, 700, 'start', '#059669')
    f.lines(50, 462, [
        'LINKED: ได้รับไบต์ใดๆ ภายใน 30 เฟรม (0.5 วินาที) ล่าสุด  (HEARTBEAT ทำให้มีไบต์มาเสมอ)',
        'เริ่มเกม: กด SW18 ที่บอร์ดไหนก็ได้ → ส่ง START → ทั้งสองบอร์ดเริ่มรอบใหม่พร้อมกัน',
        'ชนะ: ได้รับ LOST จากอีกบอร์ดขณะที่ฉันยังเล่นอยู่      เสมอ: ได้รับ LOST ภายใน 6 เฟรมหลังจากที่ฉันเพิ่งแพ้',
        'Garbage: ล้าง 2 / 3 / 4 แถว → ส่ง 1 / 2 / 4 แถว, หักกับขยะที่รอเข้ามาก่อน, รับเข้ามาได้ครั้งละ 3-5 แถวต่อบล็อก',
    ], 14.5, gap=27)
    return f


def fig_media_path():
    f = new(1640, 640)
    f.rect(10, 10, 560, 620, C['pc'][0], '#fafbfc', r=14, sw=1.5, dash='6 5')
    f.text(30, 40, 'บนคอมพิวเตอร์ (ทำครั้งเดียว)', 17, 700, 'start', C['pc'][0])
    f.rect(590, 10, 1040, 620, C['core'][0], '#fcfbff', r=14, sw=1.5, dash='6 5')
    f.text(610, 40, 'ในบอร์ด (ทุกเฟรมขณะเล่น)', 17, 700, 'start', C['core'][0])
    f.box(40, 70, 240, 90, 'ไฟล์ต้นฉบับ', ['วิดีโอ .mp4  เพลง .mp3', 'รูป .png .gif .webp'], 'pc', mono=False)
    f.box(310, 70, 240, 90, 'media_plan.py', ['รายการสื่อ + ค่าที่เลือก', '(ช่วงเวลา, fps, สี)'], 'pc')
    f.box(40, 210, 510, 150, 'make_game_media.py', ['ภาพ: ย่อเป็น 160×120 → palette 2-256 สี', '→ เก็บเฉพาะส่วนที่เปลี่ยน (delta) + run-length',
                                                  'เสียง: 16 kHz → IMA ADPCM 4 บิต (8 KB/วินาที)', 'ตรวจโดยถอดรหัสกลับทุกไฟล์'], 'pc')
    f.box(40, 410, 240, 80, 'game_media.bin', ['6.86 MB, รูปแบบ "TDM2"'], 'pc')
    f.box(310, 410, 240, 80, 'flash_media.bat', ['openFPGALoader', '(ผ่าน JTAG)'], 'pc')
    f.box(170, 530, 380, 80, 'SPI Flash ในบอร์ด', ['เริ่มที่ 1 MB, เก็บถาวรแม้ปิดไฟ'], 'media', mono=False)
    A = f.arrow
    A([(280, 115), (310, 115)])
    A([(430, 160), (430, 210)])
    A([(160, 360), (160, 410)])
    A([(280, 450), (310, 450)])
    A([(430, 490), (430, 530)])
    # board side
    f.box(620, 520, 230, 90, 'spi_flash', ['25 MHz, 3.1 MB/วินาที', 'ส่งทีละไบต์ + hold'], 'media')
    A([(550, 570), (620, 570)], 'SPI', C['media'][0])
    f.box(620, 70, 230, 150, 'media_ctrl', ['เพลงตอนเล่น', 'วิดีโอเมื่อโดนโจมตี', 'คลิปแพ้/ชนะ', 'เล่นเพลงต่อจุดเดิม'], 'media')
    f.box(890, 70, 300, 190, 'media_engine', ['อ่าน header + directory', 'อ่านทีละ record:', 'header 8 ไบต์ → ภาพ → เสียง', 'จังหวะ: โหลดเมื่อเสียงใน ring', 'ใกล้หมด (ภาพตามเสียงเสมอ)'], 'media')
    A([(850, 110), (890, 110)], 'play', C['media'][0], ldy=-8)
    A([(850, 565), (870, 565), (870, 220), (890, 220)], 'ไบต์', C['media'][0], lpos=0.5, ldx=-22)
    f.box(890, 310, 300, 100, 'ตัวถอด run-length', ['SKIP / FILL / COPY', '1 พิกเซลต่อ clock'], 'media')
    A([(1040, 260), (1040, 310)], 'ภาพ', C['media'][0], ldx=24, ldy=4)
    f.box(890, 460, 300, 110, 'frame buffer', ['160 × 120 × 8 บิต = 19,200 ไบต์', 'block RAM 5 ก้อน', '(ภาพก่อนหน้ายังอยู่)'], 'video')
    A([(1040, 410), (1040, 460)], None, C['video'][0])
    f.box(1240, 70, 360, 90, 'sound ring', ['block RAM 2,048 ไบต์', 'เขียนเป็นช่วง อ่านสม่ำเสมอ'], 'media')
    A([(1190, 115), (1240, 115)], 'เสียง', C['media'][0], ldy=-8)
    f.box(1240, 200, 360, 90, 'adpcm_dec', ['16,000 ตัวอย่าง/วินาที (ทุก 3,125 clock)', '4 บิต → 16 บิต'], 'sound')
    A([(1420, 160), (1420, 200)], None, C['sound'][0])
    f.box(1240, 330, 360, 70, 'tetris_sound → หูฟัง', ['sigma-delta 12 บิต'], 'sound')
    A([(1420, 290), (1420, 330)], None, C['sound'][0])
    f.box(1240, 440, 360, 170, 'media_mix → จอ VGA', ['palette → สี 12 บิต', 'ขยาย 4 เท่า (160×120 → 640×480)', 'โหมด: bg (หลังเกม), full (เต็มจอ),', 'over (ทับเกม), panel (กรอบขวา)', '+ sprite Jevil และหน้าเพื่อน'], 'video')
    A([(1190, 515), (1240, 515)], None, C['video'][0])
    return f


def fig_flash():
    f = new(1500, 560)
    x0, x1 = 40, 1460
    sc = (x1 - x0) / 8.0
    f.text(40, 36, 'แผนที่หน่วยความจำแฟลช 8 MB (S25FL064L)', 19, 700)
    segs = [(0, 0.54, 'ไฟล์ .bit', 'core'), (0.54, 1.0, 'ว่าง', 'pin'), (1.0, 7.86, 'game_media.bin (6.86 MB)', 'media'), (7.86, 8.0, '', 'pin')]
    for a, b2, t, g in segs:
        st, fi = C[g]
        f.rect(x0 + a * sc, 60, (b2 - a) * sc, 70, st, fi, r=4, sw=1.5)
        if t:
            f.text(x0 + (a + b2) / 2 * sc, 101, t, 14, 700, 'middle', st)
    for mb in range(9):
        f.text(x0 + mb * sc, 152, f'{mb} MB', 12.5, 400, 'middle', MUTED, mono=True)
    # zoom
    zx = x0 + 1.0 * sc
    f.add(f'<path d="M{zx},130 L{x0},200 M{x0 + 7.86 * sc},130 L{x1},200" stroke="{LINE}" stroke-dasharray="4 4"/>')
    parts = [('header', 24, '"TDM2" + กลุ่มรายการ'), ('directory', 24, '16 ไบต์ต่อรายการ'), ('sprite block', 34, 'Jevil 8 ท่า, หน้า 4 รูป'),
             ('records ของแต่ละรายการ', 50, 'header 8 ไบต์ + เสียง'), ('ภาพ delta + RLE', 70, 'เก็บครั้งเดียว ใช้ซ้ำได้')]
    tot = sum(p[1] for p in parts)
    xx = x0
    for nm, wv, ds in parts:
        w = (x1 - x0) * wv / tot
        f.rect(xx, 200, w, 80, C['media'][0], C['media'][1], r=4, sw=1.5)
        f.text(xx + w / 2, 233, nm, 14, 700, 'middle', C['media'][0])
        f.text(xx + w / 2, 257, ds, 12, 400, 'middle', INK)
        xx += w
    # one record
    f.text(40, 330, 'หนึ่ง record (เช่น วิดีโอ 10 fps = 0.1 วินาที)', 17, 700)
    rx = 40
    rec = [('ที่อยู่ภาพ', 140), ('ความยาวภาพ', 140), ('ADPCM pred', 120), ('idx', 60), ('เสียง 800 ไบต์ (1,600 ตัวอย่าง × 4 บิต)', 560)]
    for nm, w in rec:
        g = 'media' if 'เสียง' not in nm else 'sound'
        f.rect(rx, 345, w, 54, C[g][0], C[g][1], r=4, sw=1.5)
        f.text(rx + w / 2, 378, nm, 13.5, 600, 'middle', C[g][0])
        rx += w
    f.text(40, 422, '└──── header 8 ไบต์ ────┘', 13, 400, 'start', MUTED, mono=True)
    # rle codes
    f.text(40, 470, 'รหัส run-length ของภาพ (1 ไบต์ควบคุม)', 17, 700)
    codes = [('00nnnnnn', 'SKIP', 'ข้าม n+1 พิกเซลที่ไม่เปลี่ยน'), ('01nnnnnn', 'FILL', 'เติม n+1 พิกเซลด้วยสีในไบต์ถัดไป'), ('1nnnnnnn', 'COPY', 'n+1 พิกเซลตามมาแบบเรียงบิต')]
    for i, (b2, nm, ds) in enumerate(codes):
        x = 40 + i * 475
        f.rect(x, 488, 455, 56, C['video'][0], C['video'][1], r=6, sw=1.5)
        f.text(x + 14, 522, b2, 15, 700, 'start', C['video'][0], mono=True)
        f.text(x + 120, 522, f'{nm}: {ds}', 14, 400, 'start', INK)
    return f


def fig_layers():
    f = new(1200, 560)
    layers = [('7', 'วิดีโอเต็มจอ / jump scare (full, over)', 'media_mix', 'media'),
              ('6', 'Jevil ลอยทั้งจอ (sprite)', 'media_mix', 'media'),
              ('5', 'แผงภารกิจ, ลูกบอลเด้ง, แบนเนอร์ (CHAOS overlay)', 'chaos_render', 'chaos'),
              ('4', 'ข้อความ: NEXT, LINES, LINKED, WIN!', 'text_multi', 'video'),
              ('3', 'บล็อก, เงา (ghost), แถบ RIVAL, มิเตอร์ขยะ', 'tetris_render', 'core'),
              ('2', 'กรอบกระดานและตาราง', 'tetris_render', 'core'),
              ('1', 'พื้นหลัง หรือวิดีโอพื้นหลัง (bg, หรี่แสง)', 'media_mix', 'media')]
    f.text(40, 40, 'ทุกพิกเซล (640 × 480, 25 ล้านพิกเซลต่อวินาที): ชั้นบนที่ "มีของ" ชนะ', 18, 700)
    for i, (n, t, m, g) in enumerate(layers):
        y = 70 + i * 66
        st, fi = C[g]
        f.add(f'<path d="M{150 + i * 0},{y} l40,0 l0,0" />')
        f.rect(80, y, 760, 54, st, fi, r=8, sw=1.6)
        f.text(110, y + 34, n, 20, 700, 'middle', st, mono=True)
        f.text(140, y + 34, t, 15.5, 600, 'start', INK)
        f.text(820, y + 34, m, 14, 700, 'end', st, mono=True)
    f.arrow([(40, 520), (40, 80)], None, MUTED)
    f.text(40, 538, 'ล่าง', 13, 700, 'middle', MUTED)
    f.text(40, 66, 'บน', 13, 700, 'middle', MUTED)
    f.lines(880, 110, ['ภาพทั้งจอไม่ได้เก็บไว้ที่ไหนเลย:', 'คำนวณสีใหม่ทุกพิกเซล ทุกเฟรม', 'ตามตำแหน่ง (x, y) ที่ vga_sync บอก', '',
                       'ใช้ pipeline: เกม 3 clock,', 'สื่อ 3 clock → ทุกชั้นมาพร้อมกัน', '',
                       'เก็บไว้จริงเฉพาะ:', '• กระดาน 10×20 (flip-flop)', '• frame buffer วิดีโอ 160×120', '  (block RAM)'], 15, gap=26)
    return f


def fig_resources():
    f = new(1460, 560)
    f.text(30, 40, 'ทรัพยากรที่ใช้ในชิป XC7S15 (branch media, เวอร์ชันสุดท้าย)', 19, 700)
    rows = [('LUT (วงจรตรรกะ)', 6797, 8000), ('Slice', 1962, 2000), ('Flip-flop', 3045, 16000), ('Block RAM (36 Kb)', 10, 10), ('DSP', 3, 20), ('ขา I/O', 57, 100)]
    for i, (n, u, tot) in enumerate(rows):
        y = 70 + i * 52
        p = u / tot
        col = '#dc2626' if p >= 0.95 else ('#d97706' if p >= 0.8 else '#2563eb')
        f.text(30, y + 26, n, 15, 600)
        f.rect(250, y + 8, 620, 28, '#e5e7eb', '#f1f5f9', r=6, sw=1)
        f.rect(250, y + 8, max(6, 620 * p), 28, col, col, r=6, sw=1)
        f.text(885, y + 28, f'{u:,} / {tot:,}  ({p * 100:.0f} %)', 15, 700, 'start', col, mono=True)
    f.text(30, 410, 'LUT ที่ใช้ เมื่อเพิ่มทีละชั้น', 17, 700)
    br = [('main: เกม + versus', 3496), ('chaos: + ภารกิจ/การโจมตี', 6200), ('media: + สื่อจากแฟลช', 6797)]
    for i, (n, u) in enumerate(br):
        y = 430 + i * 40
        f.text(30, y + 22, n, 14.5, 400)
        f.rect(290, y + 6, 580 * u / 8000, 24, C['core'][0], C['core'][1], r=5, sw=1.5)
        f.text(300 + 580 * u / 8000, y + 24, f'{u:,} ({u / 80:.0f} %)', 14, 700, 'start', C['core'][0], mono=True)
    f.lines(1150, 90, ['Timing: WNS = +3.44 ns', '(ทุกเส้นทางเร็วพอสำหรับ 50 MHz', ' เหลือเวลาอีก 3.4 ns จาก 20 ns)', '',
                       'Slice 98 %, Block RAM 100 %:', 'เต็มชิปจริง ต้องลดวงจร', 'หลายรอบให้ใส่ได้'], 14.5, gap=24)
    return f


def fig_timeline():
    f = new(1400, 470)
    d0, d1 = 1, 31
    x0, x1 = 300, 1370
    sc = (x1 - x0) / (d1 - d0)
    f.text(20, 34, 'ไทม์ไลน์การทำงาน (ตุลาคม 2569)', 19, 700)
    for d in range(1, 31, 1):
        x = x0 + (d - d0) * sc
        if (d % 2 == 1 and d != 29) or d == 30:
            f.text(x + sc / 2, 66, str(d), 12, 400, 'middle', MUTED, mono=True)
        f.add(f'<line x1="{x}" x2="{x}" y1="74" y2="440" stroke="#f0f2f5"/>')
    tasks = [('เลือกหัวข้อ, ศึกษาบอร์ด/เครื่องมือ', 1, 15, 'pc'),
             ('ทดสอบฮาร์ดแวร์ 01-05', 15, 17, 'in'),
             ('ชั้น 1: เกม + versus', 17, 20, 'core'),
             ('ชั้น 2: CHAOS (+ปรับ 2 รอบ)', 19, 20, 'chaos'),
             ('ชั้น 3: ทดสอบ 06 อ่านแฟลช', 19, 21, 'media'),
             ('ชั้น 3: สื่อในเกม', 20, 22, 'media'),
             ('ทดสอบบนบอร์ดจริง + แก้', 19, 25, 'link'),
             ('เอกสารอธิบายโค้ด', 15, 29, 'video'),
             ('Proposal, Brochure, Design Doc, วิดีโอ', 25, 30, 'sound')]
    for i, (n, a, b2, g) in enumerate(tasks):
        y = 84 + i * 38
        st, fi = C[g]
        f.text(20, y + 21, n, 14.5, 500)
        f.rect(x0 + (a - d0) * sc, y + 4, (b2 - a + 1) * sc - 4, 24, st, fi, r=6, sw=1.6)
    for d, lab, anc in ((19, 'เล่น 2 บอร์ดจริงครั้งแรก', 'end'), (21, 'สื่อทำงานบนบอร์ด', 'start'), (30, 'ส่งงาน', 'end')):
        x = x0 + (d - d0) * sc + sc / 2
        f.add(f'<line x1="{x}" x2="{x}" y1="74" y2="440" stroke="#dc2626" stroke-dasharray="4 3"/>')
        f.text(x + (4 if anc == 'start' else -4), 458, lab, 12.5, 700, anc, '#dc2626')
    return f


def fig_flow():
    f = new(1500, 520)
    A = f.arrow
    f.box(20, 40, 230, 120, 'ไฟล์ VHDL', ['25 ไฟล์ ~5,700 บรรทัด', 'project.txt (ลำดับ)', 'pins.xdc (ขา)'], 'pc', mono=False)
    f.box(320, 40, 300, 120, 'build.bat → Vivado 2025.2', ['synthesis → place → route', 'รายงาน timing (WNS ≥ 0)', 'รายงานการใช้ทรัพยากร'], 'core', mono=False)
    f.box(690, 40, 200, 120, 'top_tetris.bit', ['~0.5 MB'], 'core')
    f.box(960, 40, 250, 120, 'program.bat', ['หรือ FPGA Builder', 'openFPGALoader (JTAG)'], 'core', mono=False)
    f.box(1270, 40, 210, 120, 'บอร์ด 2 บอร์ด', ['เล่นทดสอบจริง'], 'link', mono=False)
    A([(250, 100), (320, 100)])
    A([(620, 100), (690, 100)])
    A([(890, 100), (960, 100)])
    A([(1210, 100), (1270, 100)])
    f.box(320, 230, 300, 120, 'sim.bat → xsim', ['testbench 13 ชุด', 'ผล: TEST PASSED', 'หรือภาพหน้าจอ .png'], 'video', mono=False)
    A([(135, 160), (135, 290), (320, 290)], 'จำลองก่อนเสมอ', C['video'][0], lpos=0.7)
    A([(470, 230), (470, 160)], 'ผ่านแล้วจึง build', C['video'][0], ldx=70, ldy=4)
    f.box(20, 400, 230, 100, 'วิดีโอ เพลง รูป', ['(ไม่อยู่ใน git)'], 'pc', mono=False)
    f.box(320, 400, 300, 100, 'make_game_media.py', ['→ game_media.bin'], 'media')
    f.box(690, 400, 200, 100, 'flash_media.bat', ['เขียนลงแฟลช'], 'media')
    A([(250, 450), (320, 450)])
    A([(620, 450), (690, 450)])
    A([(890, 450), (1375, 450), (1375, 160)], 'ครั้งเดียวต่อบอร์ด', C['media'][0], lpos=0.5)
    f.lines(960, 260, ['ทุกอย่างสั่งได้จาก Command Prompt', 'ไม่ต้องเปิดหน้าต่าง Vivado:', 'build ซ้ำได้เหมือนเดิมทุกครั้ง', 'และใช้กับ FPGA Builder ของ TA ได้'], 14.5, gap=24, color=MUTED)
    return f


def fig_vmodel():
    f = new(1400, 560)
    L = [('ความต้องการ: เกมดวล 2 บอร์ด สนุก มีภาพและเสียง', 'pc'), ('ระบบ: 2 บอร์ด + โปรโตคอลสายเชื่อม', 'link'), ('top_tetris: แบ่งเป็นกลุ่มหน้าที่', 'core'), ('โมดูล VHDL แต่ละตัว', 'video')]
    R = [('เล่นจริงกับเพื่อน 2 บอร์ด + ปรับตามความเห็น', 'pc'), ('ทดสอบ 04 เชื่อมบอร์ด, tb_versus, tb_chaos', 'link'), ('ทดสอบ 01-06 บนบอร์ด, tb_*_frame (ภาพทั้งจอ)', 'core'), ('testbench ของแต่ละโมดูล (tb_tetris_core ฯลฯ)', 'video')]
    f.text(250, 36, 'ออกแบบจากบนลงล่าง (Top-Down)', 18, 700, 'middle', C['core'][0])
    f.text(1150, 36, 'ทดสอบจากล่างขึ้นบน', 18, 700, 'middle', C['link'][0])
    for i, ((lt, g1), (rt, g2)) in enumerate(zip(L, R)):
        y = 60 + i * 110
        f.box(30 + i * 60, y, 430, 70, lt, [], g1, mono=False, tsize=15)
        f.box(940 - i * 60, y, 430, 70, rt, [], g2, mono=False, tsize=15)
        f.arrow([(460 + i * 60, y + 35), (940 - i * 60, y + 35)], 'ตรวจด้วย', LINE, dash='5 4', both=True)
        if i < 3:
            f.arrow([(245 + i * 60, y + 70), (245 + (i + 1) * 60, y + 110)], None, C['core'][0])
            f.arrow([(1155 - (i + 1) * 60, y + 110), (1155 - i * 60, y + 70)], None, C['link'][0])
    f.box(470, 480, 460, 60, 'เขียน VHDL (ทีละโมดูล, ทีละชั้น: main → chaos → media)', [], 'sound', mono=False, tsize=15)
    f.arrow([(425, 440), (520, 480)], None, C['core'][0])
    f.arrow([(880, 480), (975, 440)], None, C['link'][0])
    return f


def fig_chaos():
    f = new(1400, 420)
    A = f.arrow
    f.box(20, 60, 230, 110, 'ภารกิจปรากฏ', ['ทุก 10-17 วินาที (สุ่ม)', '7 แบบ, เวลาจำกัด'], 'chaos', mono=False)
    f.box(310, 60, 250, 110, 'ผู้เล่นทำด้วยสวิตช์', ['8 ตัวซ้าย', 'ไปพร้อมกับเล่นเตตริส'], 'in', mono=False)
    f.box(620, 20, 230, 80, 'สำเร็จ', [], 'link', mono=False)
    f.box(620, 130, 230, 80, 'หมดเวลา', ['ไม่มีอะไรเกิดขึ้น'], 'pin', mono=False)
    f.box(920, 20, 230, 80, 'โจมตี (5/8)', ['ถ้าเชื่อมบอร์ดอยู่'], 'chaos', mono=False)
    f.box(920, 130, 230, 80, 'โบนัส (3/8)', ['FREEZE SINK I-PIECE'], 'link', mono=False)
    f.box(1200, 20, 180, 80, 'จอคู่แข่ง', ['ผ่าน ATTACK id'], 'core', mono=False)
    A([(250, 115), (310, 115)])
    A([(560, 100), (620, 60)])
    A([(560, 130), (620, 170)])
    A([(850, 60), (920, 60)])
    A([(850, 60), (885, 60), (885, 170), (920, 170)])
    A([(1150, 60), (1200, 60)])
    tasks = ['FLIP: โยกสวิตช์ 10 ครั้ง', 'MATCH: ทำตามรูปแบบไฟ', 'BINARY: ตั้งเลขฐานสอง', 'HEX: ตั้งเลขฐานสิบหก', 'HANDS: ห้ามแตะปุ่ม', 'HOLD: คุมแถบในโซนเขียว', 'TIMING: โยกให้ตรงจังหวะ']
    atk = ['MIRROR: ซ้าย-ขวาสลับ', 'FLIP: กระดานกลับหัว', 'BLIND: บล็อกล่องหน', 'BOUNCERS: ลูกบอลเด้งบังจอ', '+3 GARBAGE', 'CURSED: บล็อก S/Z', 'SPEED: ตกเร็วขึ้น', 'LOCK: ล็อกปุ่มจนทำภารกิจ', 'Bad Apple!! (วิดีโอ)', 'OIIA OIIA (วิดีโอ)', 'JEVIL (วิดีโอ + sprite)']
    f.text(20, 260, 'ภารกิจ 7 แบบ', 16, 700, 'start', C['chaos'][0])
    f.lines(20, 288, tasks[:4], 13.5, gap=22)
    f.lines(250, 288, tasks[4:], 13.5, gap=22)
    f.text(560, 260, 'การโจมตี 11 แบบ', 16, 700, 'start', C['chaos'][0])
    f.lines(560, 288, atk[:6], 13.5, gap=22)
    f.lines(820, 288, atk[6:], 13.5, gap=22)
    f.lines(1100, 260, ['การโจมตีวิดีโอ: ผู้ส่งต้องรอ', 'ความยาวคลิป + 10 วินาที', 'ก่อนส่งวิดีโอได้อีก'], 13.5, gap=22, color=MUTED)
    return f


FIGS = {
    'system': fig_system, 'hierarchy': fig_hierarchy, 'blocks': fig_blocks, 'fsm': fig_fsm,
    'link': fig_link, 'media_path': fig_media_path, 'flash': fig_flash, 'layers': fig_layers,
    'resources': fig_resources, 'timeline': fig_timeline, 'flow': fig_flow, 'vmodel': fig_vmodel,
    'chaos': fig_chaos,
}


def render(name, fig):
    os.makedirs(OUT_HTML, exist_ok=True)
    page = ('<!doctype html><html><head><meta charset="utf-8">'
            '<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Thai:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;600;700&display=block" rel="stylesheet">'
            f'<style>html,body{{margin:0;padding:0;background:#fff;width:{fig.w}px;height:{fig.h}px;overflow:hidden}}</style></head><body>'
            + fig.svg() + '</body></html>')
    hp = os.path.join(OUT_HTML, f'fig_{name}.html')
    with open(hp, 'w', encoding='utf-8') as fh:
        fh.write(page)
    out = os.path.join(HERE, f'fig_{name}.png')
    chrome = next(c for c in CHROME if os.path.exists(c))
    subprocess.run([chrome, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=2',
                    f'--window-size={fig.w},{fig.h}', '--virtual-time-budget=4000', f'--screenshot={out}',
                    'file:///' + hp.replace('\\', '/')], check=True, capture_output=True)
    print('wrote', out)


if __name__ == '__main__':
    names = sys.argv[1:] or list(FIGS)
    for n in names:
        render(n, FIGS[n]())
