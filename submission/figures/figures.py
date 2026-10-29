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
              lsize=12.5, lanchor='middle', sw=2, lat=None):
        d = 'M' + ' L'.join(f'{x},{y}' for x, y in pts)
        mid = color.replace('#', '')
        da = f' stroke-dasharray="{dash}"' if dash else ''
        ms = f' marker-start="url(#s{mid})"' if both else ''
        # white halo underneath: where two lines cross, the top one stays readable
        self.add(f'<path d="{d}" fill="none" stroke="#fff" stroke-width="{sw + 5}" stroke-linejoin="round"/>')
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
            if lat:
                lx, ly = lat
            rows = label if isinstance(label, (list, tuple)) else [label]
            for i, r in enumerate(rows):
                self.labels.append(f'<text x="{lx}" y="{ly + i * lsize * 1.3}" font-family="{FONT}" font-size="{lsize}" '
                         f'text-anchor="{lanchor}" fill="{color}" paint-order="stroke" stroke="#fff" '
                         f'stroke-width="5" stroke-linejoin="round">{esc(r)}</text>')

    markers = set()
    labels = []

    def svg(self):
        defs = []
        for col in sorted(self.markers):
            m = col.replace('#', '')
            defs.append(f'<marker id="a{m}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{col}"/></marker>')
            defs.append(f'<marker id="s{m}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{col}"/></marker>')
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}">'
                f'<defs>{"".join(defs)}</defs><rect width="100%" height="100%" fill="{BG}"/>' + ''.join(self.parts) + ''.join(self.labels) + '</svg>')


def new(w, h):
    f = Fig(w, h)
    f.markers = set()
    f.labels = []
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
    labels = ['ขา 5 TX  ————→  ขา 6 RX', 'ขา 6 RX  ←————  ขา 5 TX', 'ขา 2 GND  ———  ขา 2 GND']
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
    # every module of top_tetris, and every module-to-module connection
    # (from the port maps in game/top_tetris.vhd), one line per pair of modules
    f = new(2050, 1080)
    B = {}
    AX, BX, CX, DX, EX, QX = 200, 520, 910, 1280, 1640, 1920

    def b(k, x, y, w, h, t, s, g, mono=True, tsize=16):
        B[k] = (x, y, w, h)
        f.box(x, y, w, h, t, s, g, mono=mono, tsize=tsize, ssize=12.5)

    def L(k, y): return (B[k][0], y)
    def R(k, y): return (B[k][0] + B[k][2], y)
    def T(k, x): return (x, B[k][1])
    def D(k, x): return (x, B[k][1] + B[k][3])

    # pins (left: in, right: out)
    b('btn', 20, 60, 120, 80, 'ปุ่มกด 5', ['SW14..SW23'], 'pin', False, 15)
    b('sw', 20, 320, 120, 80, 'สวิตช์เลื่อน', ['13 ตัวที่ใช้'], 'pin', False, 15)
    b('j5', 20, 525, 120, 110, 'J5 / USB', ['TX, RX', '(SW7 เลือก)'], 'pin', False, 15)
    b('vga', QX, 70, 110, 80, 'จอ VGA', ['R G B hs vs'], 'pin', False, 15)
    b('aud', QX, 520, 110, 80, 'หูฟัง', ['+ บัซเซอร์'], 'pin', False, 15)
    b('flash', QX, 825, 110, 90, 'SPI Flash', ['8 MB'], 'pin', False, 15)
    b('segp', QX, 955, 110, 80, '7-segment', ['4 หลัก'], 'pin', False, 15)
    # modules
    b('inp', AX, 50, 210, 100, 'tetris_input', ['debounce 5 ms × 5', 'กดค้าง: DAS 10 เฟรม'], 'in')
    b('swf', AX, 300, 210, 120, 'switch_filter', ['กรองสวิตช์เด้ง', 'SW2 พัก · SW4 เพลง', 'SW5 เอฟเฟกต์ · SW6 CHAOS'], 'in')
    b('link', AX, 520, 210, 150, 'versus_link', ['uart_tx + uart_rx', '115,200 bps', 'HEARTBEAT ทุก 6 เฟรม', 'LINKED: ไบต์ใน 30 เฟรม'], 'link')
    b('sync', AX, 900, 300, 120, 'vga_sync', ['x, y, video_on, hs, vs', 'frame_tick (59.5 ครั้ง/วินาที)', '→ ทุกโมดูล (ไม่วาดเส้น)'], 'video')
    b('gate', BX, 55, 210, 90, 'ตัวกรองปุ่ม', ['(เขียนใน top_tetris)', 'MIRROR สลับซ้าย-ขวา', 'LOCK ปิดทุกปุ่ม'], 'in', False, 15)
    b('task', BX, 300, 210, 140, 'chaos_task', ['สุ่มภารกิจทุก 10-17 วิ', 'ตรวจสวิตช์ทุกเฟรม', 'สำเร็จ → สุ่ม: โจมตี', '62.5 % / โบนัส 37.5 %'], 'chaos')
    b('core', CX, 30, 240, 170, 'tetris_core', ['FSM 23 สถานะ', 'กระดาน 10 × 20', 'ตรวจชน · 7-bag', 'ล้างแถว · garbage'], 'core')
    b('fx', CX, 300, 240, 140, 'chaos_fx', ['ผลของการโจมตี/โบนัส', 'นับเวลาแต่ละผล', 'แบนเนอร์ INCOMING'], 'chaos')
    b('mctrl', CX, 760, 240, 130, 'media_ctrl', ['เลือกว่าเล่นอะไร:', 'เพลง · วิดีโอโจมตี', 'ชนะ / แพ้'], 'media')
    b('rend', DX, 30, 240, 170, 'tetris_render', ['วาดกระดาน บล็อก เงา', 'ข้อความ (text_multi)', 'แถบ RIVAL, มิเตอร์ขยะ', 'pipeline 3 clock'], 'video')
    b('cren', DX, 300, 240, 140, 'chaos_render', ['แผงภารกิจ (text_multi)', 'ลูกบอลเด้ง 5-10 ลูก', 'แบนเนอร์'], 'chaos')
    b('eng', DX, 740, 240, 170, 'media_engine', ['spi_flash · adpcm_dec', 'frame buffer 160 × 120', 'sound ring 2 KB', 'sprite Jevil + หน้า'], 'media')
    b('mix', EX, 30, 200, 170, 'media_mix', ['ซ้อนภาพเกม', 'กับวิดีโอ + sprite', 'ตามโหมด bg / full', '/ over / panel'], 'video')
    b('snd', EX, 500, 200, 130, 'tetris_sound', ['ผสมเสียงสื่อ', '+ เสียงเอฟเฟกต์', 'sigma-delta 12 บิต'], 'sound')
    b('seg', EX, 935, 200, 120, 'seg7_scan', ['แสดง: แถวที่ล้าง', 'หรือวินาทีภารกิจ', '(เลือกใน top_tetris)'], 'sound')

    A = f.arrow
    ci, cc, cl, cx, cv, cm, cs = (C[k][0] for k in ('in', 'core', 'link', 'chaos', 'video', 'media', 'sound'))
    # input row
    A([R('btn', 100), L('inp', 100)], None, ci)
    A([R('inp', 100), L('gate', 100)], 'ปุ่ม 5 ตัว', ci, ldy=-8)
    A([R('gate', 100), L('core', 100)], 'คำสั่งที่ผ่านแล้ว', ci, ldy=-8)
    A([R('core', 70), L('rend', 70)], 'กระดาน, บล็อก, เงา, NEXT', cc, ldy=-8, lsize=12)
    A([R('core', 150), L('rend', 150)], ['playing, lines,', 'level, result, ขยะรอ'], cc, ldy=-22, lsize=12)
    A([R('rend', 110), L('mix', 110)], ['สีเกม', '+ hs, vs'], cv, ldy=-24)
    A([R('mix', 110), L('vga', 110)], 'RGB', cv, ldy=-8)
    # switches + chaos row
    A([R('sw', 360), L('swf', 360)], None, ci)
    A([R('swf', 345), L('task', 345)], ['สวิตช์ภารกิจ 8', 'CHAOS (SW6)'], ci, ldy=-22, lsize=12)
    A([R('task', 345), L('fx', 345)], ['สำเร็จ/ล้มเหลว', 'โจมตีที่ส่ง, โบนัส'], cx, lat=(832, 323), lsize=12)
    A([R('fx', 345), L('cren', 345)], ['BOUNCERS, LOCK', 'แบนเนอร์'], cx, lat=(1215, 323), lsize=12)
    A([T('cren', DX + 180), D('rend', DX + 180)], ['overlay', '(ov_on, ov_rgb)'], cx, lat=(DX + 236, 240), lsize=12)
    A([T('fx', CX + 120), D('core', CX + 120)], ['FREEZE SPEED SINK', 'CURSED I-PIECE +3'], cx, lat=(CX + 196, 236), lsize=12)
    A([T('fx', CX + 210), (CX + 210, 280), (DX + 40, 280), D('rend', DX + 40)], 'FLIP, BLIND', cx, lat=(DX - 20, 274), lsize=12)
    A([T('fx', CX + 30), (CX + 30, 270), (625, 270), D('gate', 625)], 'MIRROR, LOCK', cx, lat=(760, 264), lsize=12)
    A([D('task', 700), (700, 480), (DX + 40, 480), D('cren', DX + 40)], 'ข้อมูลแผงภารกิจ (ข้อความ, มิเตอร์, เวลา)', cx, lat=(1000, 474), lsize=12)
    # link
    A([R('j5', 580), L('link', 580)], None, cl, both=True)
    A([R('link', 545), (750, 545), (750, 175), L('core', 175)], ['ไป-กลับ: START, LOST, GARBAGE,', 'ความสูงกอง, LINKED'], cl, both=True, lat=(580, 562), lsize=12)
    A([D('task', 560), (560, 500), (380, 500), T('link', 380)], 'ส่ง ATTACK', cx, lat=(470, 494), lsize=12)
    A([R('link', 620), (CX + 80, 620), D('fx', CX + 80)], 'ATTACK ที่ได้รับ', cl, lat=(700, 614), lsize=12)
    A([R('link', 655), (1250, 655), (1250, 185), L('rend', 185)], 'ความสูงคู่แข่ง (แถบ RIVAL), LINKED', cl, lat=(900, 649), lsize=12)
    # media
    A([D('fx', CX + 160), T('mctrl', CX + 160)], ['การโจมตี', 'วิดีโอ'], cx, lat=(CX + 205, 705), lsize=12)
    A([R('core', 190), (1190, 190), (1190, 780), R('mctrl', 780)], ['playing,', 'result'], cc, lat=(1220, 560), lsize=12)
    A([R('mctrl', 840), L('eng', 840)], ['play, item →', '← ready, rec_pos'], cm, both=True, ldy=-22, lsize=12)
    A([D('mctrl', CX + 120), (CX + 120, 960), (EX - 35, 960), (EX - 35, 190), L('mix', 190)], 'show, jevil, won', cm, lat=(1300, 954), lsize=12)
    A([D('cren', DX + 80), T('eng', DX + 80)], ['ตำแหน่งพิกเซล', 'หน้าเพื่อน'], cx, lat=(DX + 82, 590), lanchor='end', lsize=12)
    A([R('eng', 760), (EX - 60, 760), (EX - 60, 165), L('mix', 165)], ['ภาพวิดีโอ, sprite', '↔ ตำแหน่ง Jevil'], cm, both=True, lat=(DX + 236, 700), lanchor='end', lsize=12)
    A([R('eng', 800), (EX - 80, 800), (EX - 80, 590), L('snd', 590)], 'pcm', cm, lat=(EX - 18, 582), lsize=12)
    A([R('eng', 870), L('flash', 870)], 'SPI 25 MHz (นาฬิกาผ่าน STARTUPE2)', cm, both=True, lat=(1750, 862), lsize=12)
    A([R('snd', 560), L('aud', 560)], None, cs)
    A([R('seg', 995), L('segp', 995)], None, cs)
    f.lines(EX + 10, 662, ['tetris_sound ยังรับ: ล้างแถว/ขยะ/ชนะแพ้', 'จาก core, ภารกิจจาก chaos_task,', 'โดนโจมตีจาก chaos_fx, SW4/SW5'], 12, gap=17, color=MUTED)
    f.lines(560, 1000, ['เส้นที่ไม่ได้วาด (ดูตารางการต่อสายในบทที่ 3):', '• x, y, frame_tick จาก vga_sync → เกือบทุกโมดูล',
                        '• pause (SW2) → tetris_core, chaos_task, chaos_fx, tetris_render', '• lines (core) / วินาทีภารกิจ (task) → seg7_scan'], 12.5, gap=19, color=MUTED)
    return f


def fig_fsm():
    # same layout as the state machine in docs/learn/tetris_visual.html:
    # a centre spine (new piece -> ghost -> lock check), the once-a-frame loop
    # round the left, lock/clear/score up the right, garbage top right and the
    # chaos SINK bonus far right. Every arrow is one 'state <= ...' in tetris_core.
    S = 1.32
    f = new(int(1180 * S), int(660 * S) + 26)
    W, H = 124 * S, 40 * S
    N = {
        'S_IDLE': (100, 60), 'S_INIT': (260, 60), 'S_PICK': (420, 60), 'S_SPAWN': (580, 60),
        'S_SPAWN_CHK': (580, 155), 'S_GHOST': (580, 250), 'S_GHOST_CHK': (580, 345), 'S_LOCKCHK': (580, 440),
        'S_PLAY': (580, 540), 'S_ROT': (420, 540), 'S_ROT_CHK': (260, 540), 'S_MOVE': (100, 540),
        'S_MOVE_CHK': (100, 440), 'S_DOWN': (100, 345), 'S_DOWN_CHK': (100, 250),
        'S_LOCK': (760, 440), 'S_CLEAR': (760, 345), 'S_SCORE': (760, 250),
        'S_ATTACK': (760, 155), 'S_HOLE': (940, 155), 'S_GARB': (940, 60),
        'S_SINK': (1080, 440), 'S_SINK_CHK': (1080, 345)}
    G = {'S_IDLE': 'link', 'S_INIT': 'link', 'S_PICK': 'link', 'S_SPAWN': 'link', 'S_SPAWN_CHK': 'link',
         'S_LOCK': 'video', 'S_CLEAR': 'video', 'S_SCORE': 'video', 'S_ATTACK': 'video',
         'S_HOLE': 'video', 'S_GARB': 'video', 'S_SINK': 'chaos', 'S_SINK_CHK': 'chaos'}
    P = lambda x, y: (x * S, y * S + 34)
    def T(n): return P(N[n][0], N[n][1] - 20)
    def Bo(n): return P(N[n][0], N[n][1] + 20)
    def Lf(n): return P(N[n][0] - 62, N[n][1])
    def R(n): return P(N[n][0] + 62, N[n][1])
    A = f.arrow
    cg, cc, cv, cx = C['link'][0], C['core'][0], C['video'][0], C['chaos'][0]

    def E(pts, lab=None, col=cc, at=None, dash=None, anchor='middle'):
        pts = [p if isinstance(p[0], float) else P(*p) for p in pts]
        A(pts, lab, col, dash=dash, lat=P(*at) if at else None, lanchor=anchor, lsize=13)

    # new game / new piece
    E([R('S_IDLE'), Lf('S_INIT')], 'เริ่ม', cg, at=(180, 50))
    E([R('S_INIT'), Lf('S_PICK')], None, cg)
    E([R('S_PICK'), Lf('S_SPAWN')], 'ได้บล็อก', cg, at=(500, 50))
    E([Bo('S_SPAWN'), T('S_SPAWN_CHK')], None, cg)
    E([Bo('S_SPAWN_CHK'), T('S_GHOST')], 'วางได้', cg, at=(612, 207))
    E([Lf('S_SPAWN_CHK'), (130, 155), (130, 80)], 'ไม่มีที่วาง: แพ้', '#dc2626', at=(330, 147))
    # spine
    E([Bo('S_GHOST'), T('S_GHOST_CHK')], None)
    E([Bo('S_GHOST_CHK'), T('S_LOCKCHK')], 'ชนแล้ว', at=(614, 397))
    E([Bo('S_LOCKCHK'), T('S_PLAY')], 'ยังไม่ล็อก', at=(624, 494))
    E([R('S_LOCKCHK'), Lf('S_LOCK')], 'ล็อก', cv, at=(670, 432))
    # frame loop (left)
    E([Lf('S_PLAY'), R('S_ROT')], 'frame_tick', at=(500, 512))
    E([Lf('S_ROT'), R('S_ROT_CHK')], 'กดหมุน', at=(345, 512))
    E([Lf('S_ROT_CHK'), R('S_MOVE')], 'หมุนได้ / ลองครบ 5 ที่', at=(170, 512))
    E([T('S_MOVE'), Bo('S_MOVE_CHK')], 'กดซ้าย/ขวา', at=(108, 496), anchor='start')
    E([T('S_MOVE_CHK'), Bo('S_DOWN')], None)
    E([T('S_DOWN'), Bo('S_DOWN_CHK')], 'ถึงเวลาตก / กดตกช้า', at=(108, 302), anchor='start')
    E([R('S_DOWN_CHK'), Lf('S_GHOST')], None)
    E([Bo('S_ROT'), (420, 600), (100, 600), Bo('S_MOVE')], 'ไม่ได้กดหมุน', MUTED, at=(260, 618), dash='6 4')
    E([Lf('S_MOVE'), (22, 540), (22, 345), Lf('S_DOWN')], 'ไม่ได้กดเลื่อน', MUTED, at=(28, 396), dash='6 4', anchor='start')
    E([R('S_DOWN'), (470, 345), (470, 262), (518, 262)], 'ไม่ต้องตก', MUTED, at=(300, 337), dash='6 4')
    # lock, clear, score (right)
    E([T('S_LOCK'), Bo('S_CLEAR')], 'เขียนครบ 4 แถว', cv, at=(770, 397), anchor='start')
    E([T('S_CLEAR'), Bo('S_SCORE')], 'ลบแถวเต็มเสร็จ', cv, at=(770, 318), anchor='start')
    E([T('S_SCORE'), Bo('S_ATTACK')], 'นับแถวเสร็จ', cv, at=(770, 207), anchor='start')
    E([T('S_ATTACK'), (760, 18), (420, 18), T('S_PICK')], 'บล็อกถัดไป', cv, at=(560, 12))
    E([R('S_ATTACK'), Lf('S_HOLE')], 'มีขยะรอ', cv, at=(850, 147))
    E([T('S_HOLE'), Bo('S_GARB')], 'สุ่มช่องว่างได้', cv, at=(950, 112), anchor='start')
    E([(900, 40), (900, 31), (445, 31), (445, 40)], None, cv)
    f.text(*P(800, 27), 'ดันครบ', 13, 400, 'middle', cv)
    E([(980, 40), (980, 2), (100, 2), T('S_IDLE')], 'ดันจนล้นจอ: แพ้', '#dc2626', at=(1060, 8))
    # chaos SINK (far right)
    E([Bo('S_PLAY'), (580, 588), (1080, 588), Bo('S_SINK')], 'sink_left > 0 (เพิ่งได้โบนัส SINK)', cx, at=(830, 604))
    E([T('S_SINK'), Bo('S_SINK_CHK')], 'เลื่อนครบ', cx, at=(1088, 397), anchor='start')
    E([T('S_SINK_CHK'), (1080, 292), (670, 292), (670, 250), R('S_GHOST')], 'บล็อกยังวางได้', cx, at=(900, 286))
    # self loops: state stays for several clocks
    loops = {'S_IDLE': ('b', 'รอเริ่ม'), 'S_PICK': ('b', 'สุ่มใหม่'), 'S_PLAY': ('r', 'รอ frame_tick'),
             'S_ROT_CHK': ('t', 'ลอง kick ถัดไป'), 'S_GHOST_CHK': ('l', 'ลงอีก 1 แถว'), 'S_LOCK': ('r', 'แถวถัดไป'),
             'S_CLEAR': ('r', '1 แถว/clock'), 'S_SCORE': ('r', '1 แถว/clock'), 'S_HOLE': ('r', 'สุ่มใหม่'),
             'S_GARB': ('r', '1 แถว/clock'), 'S_SINK': ('l', '1 แถว/clock'), 'S_SINK_CHK': ('l', 'ยกบล็อก 1 แถว')}
    for n, (side, lab) in loops.items():
        cx0, cy0 = P(*N[n])
        col = C[G.get(n, 'core')][0]
        if side == 'r':
            x0 = cx0 + W / 2
            d = f'M{x0},{cy0 - 10} C{x0 + 40},{cy0 - 28} {x0 + 40},{cy0 + 28} {x0 + 2},{cy0 + 10}'
            tx, ty, an = x0 + 36, cy0 + 5, 'start'
        elif side == 'l':
            x0 = cx0 - W / 2
            d = f'M{x0},{cy0 - 10} C{x0 - 40},{cy0 - 28} {x0 - 40},{cy0 + 28} {x0 - 2},{cy0 + 10}'
            tx, ty, an = x0 - 36, cy0 + 30, 'end'
        elif side == 't':
            y0 = cy0 - H / 2
            d = f'M{cx0 - 18},{y0} C{cx0 - 30},{y0 - 40} {cx0 + 30},{y0 - 40} {cx0 + 18},{y0 - 2}'
            tx, ty, an = cx0 - 34, y0 - 30, 'end'
        else:
            y0 = cy0 + H / 2
            d = f'M{cx0 - 18},{y0} C{cx0 - 30},{y0 + 40} {cx0 + 30},{y0 + 40} {cx0 + 18},{y0 + 2}'
            tx, ty, an = cx0 + 32, y0 + 30, 'start'
        mid = col.replace('#', '')
        f.markers.add(col)
        f.add(f'<path d="{d}" fill="none" stroke="{col}" stroke-width="1.8" marker-end="url(#a{mid})"/>')
        f.labels.append(f'<text x="{tx}" y="{ty}" font-family="{FONT}" font-size="12" text-anchor="{an}" fill="{col}" '
                        f'paint-order="stroke" stroke="#fff" stroke-width="5" stroke-linejoin="round">{esc(lab)}</text>')
    for n, (x, y) in N.items():
        g = G.get(n, 'core')
        st, fi = C[g]
        px, py = P(x, y)
        f.rect(px - W / 2, py - H / 2, W, H, st, fi, r=10, sw=2)
        f.text(px, py + 6, n, 15, 700, 'middle', st, mono=True)
    # captions
    f.text(*P(250, 390), 'ทุกเฟรม (60 ครั้ง/วินาที):', 14, 700, 'start', cc)
    f.lines(*P(250, 410), ['ลองหมุน → ลองเลื่อน → ลองตก', '→ หาเงา → ล็อกหรือยัง', 'แต่ละขั้น 1 clock (20 ns)'], 13, color=MUTED)
    f.text(*P(180, 118), 'คู่แข่งแพ้ (ได้ LOST) ในสถานะใดก็ได้ → S_IDLE = ชนะ', 13, 700, 'start', '#dc2626')
    f.text(*P(1080, 500), 'โบนัส SINK', 14, 700, 'middle', cx)
    f.text(*P(940, 230), 'ขยะจากคู่แข่ง', 14, 700, 'middle', cv)
    f.text(*P(830, 520), 'ล็อก → ล้างแถว → นับ', 14, 700, 'middle', cv)
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
    # addresses read from media/game_media.bin (header + directory), see
    # tools/make_game_media.py layout(): items in order, sprite block LAST
    f = new(1500, 900)
    x0, x1 = 40, 1460
    MB = 1 << 20
    sc = (x1 - x0) / (8 * MB)
    f.text(40, 34, 'ชิปแฟลช 8 MB (S25FL064L): ที่อยู่ 0x000000 - 0x7FFFFF', 19, 700)
    top = [(0, 0x83956, 'ไฟล์ .bit', 'core'), (0x83956, 0x100000, 'ว่าง', 'pin'),
           (0x100000, 0x78BA00, 'game_media.bin  6,863,360 ไบต์ (0x100000 - 0x78B9FF)', 'media'), (0x78BA00, 0x800000, 'ว่าง', 'pin')]
    for a, b2, t, g in top:
        st, fi = C[g]
        f.rect(x0 + a * sc, 50, (b2 - a) * sc, 60, st, fi, r=3, sw=1.5)
        f.text(x0 + (a + b2) / 2 * sc, 86, t, 13.5 if g != 'pin' else 12, 700, 'middle', st)
    for adr in (0, 0x100000, 0x200000, 0x300000, 0x400000, 0x500000, 0x600000, 0x700000, 0x800000):
        f.text(x0 + adr * sc, 128, f'0x{adr:06X}', 11.5, 400, 'middle', MUTED, mono=True)
    f.text(x0 + 0x40000 * sc, 146, '(~527 KB ถ้าเขียน .bit ลงแฟลช)', 11.5, 400, 'middle', MUTED)
    # the file, item by item, in the order it is stored
    items = [(0x100000, 0x100200, 'header + directory', 'pc'),
             (0x100200, 0x216500, 'เพลง 1', 'sound'), (0x216500, 0x2BB200, 'เพลง 2', 'sound'),
             (0x2BB200, 0x405600, 'Bad Apple!!', 'chaos'), (0x405600, 0x589900, 'OIIA OIIA', 'chaos'),
             (0x589900, 0x5DF300, 'Jevil', 'chaos'),
             (0x5DF300, 0x6C6900, 'แพ้: rickroll', 'link'), (0x6C6900, 0x6E6C00, 'แพ้: อื่นๆ 7', 'link'),
             (0x6E6C00, 0x783600, 'ชนะ: yippee', 'core'), (0x783600, 0x788200, 'ชนะ 3', 'core'),
             (0x788200, 0x78BA00, 'sprite', 'media')]
    y = 200
    f.add(f'<path d="M{x0 + 0x100000 * sc},110 L{x0},{y} M{x0 + 0x78BA00 * sc},110 L{x1},{y}" stroke="{LINE}" stroke-dasharray="4 4" fill="none"/>')
    s2 = (x1 - x0) / (0x78BA00 - 0x100000)
    for a, b2, t, g in items:
        st, fi = C[g]
        xa, xb = x0 + (a - 0x100000) * s2, x0 + (b2 - 0x100000) * s2
        f.rect(xa, y, max(3, xb - xa), 64, st, fi, r=2, sw=1.4)
        if xb - xa > 70:
            f.text((xa + xb) / 2, y + 30, t, 13, 700, 'middle', st)
            f.text((xa + xb) / 2, y + 50, f'0x{a:06X}', 11, 400, 'middle', INK, mono=True)
    f.text(x0, y - 10, 'ข้างใน game_media.bin เรียงตามที่เก็บจริง (ตัวเลข = ที่อยู่เริ่มของแต่ละส่วนในแฟลช)', 15, 700)
    # callouts for the two tiny parts at the very start and the very end
    f.arrow([(x0 + 2, y + 64), (x0 + 2, y + 96), (x0 + 30, y + 96)], None, C['pc'][0])
    f.lines(x0 + 36, y + 101, ['header 16 ไบต์ @ 0x100000 ("TDM2", กลุ่มรายการ, ที่อยู่ sprite = 0x788200)',
                               'directory 17 × 16 ไบต์ @ 0x100010 (ที่อยู่ palette / record ของแต่ละรายการ)'], 13, gap=19)
    f.arrow([(x1 - 2, y + 64), (x1 - 2, y + 96), (x1 - 30, y + 96)], None, C['media'][0])
    f.lines(x1 - 36, y + 101, ['sprite block อยู่ท้ายสุด @ 0x788200 - 0x78B97F', 'โหลดครั้งเดียวตอนเปิดเครื่อง (ดูด้านล่าง)'], 13, gap=19, anchor='end')
    f.text(x0, y + 160, 'แต่ละรายการ = palette → records → ภาพ (แต่ละรายการเริ่มที่ที่อยู่หาร 256 ลงตัว)', 13.5, 400, 'start', MUTED)
    # sprite block zoom
    y2 = 410
    f.text(40, y2 - 12, 'sprite block (14,208 ไบต์) ซูม', 15, 700)
    parts = [(0x788200, 512, 'palette 256 สี × 2 ไบต์', 'สี 1-15 = Jevil, 16-255 = หน้า'),
             (0x788400, 9600, 'Jevil 8 ท่า × 48 × 50 พิกเซล', '4 บิตต่อพิกเซล (2 พิกเซลต่อไบต์)'),
             (0x78A980, 4096, 'หน้าเพื่อน 4 รูป × 32 × 32', '1 ไบต์ต่อพิกเซล')]
    xx = x0
    widths = [260, 760, 400]
    for (a, n, t, d), w in zip(parts, widths):
        f.rect(xx, y2, w, 74, C['media'][0], C['media'][1], r=4, sw=1.5)
        f.text(xx + w / 2, y2 + 26, t, 13.5, 700, 'middle', C['media'][0])
        f.text(xx + w / 2, y2 + 46, d, 12, 400, 'middle', INK)
        f.text(xx + w / 2, y2 + 65, f'0x{a:06X}  ({n:,} ไบต์)', 11.5, 400, 'middle', MUTED, mono=True)
        xx += w
    # one record
    y3 = 560
    f.text(40, y3, 'หนึ่ง record ของรายการที่มีเสียง (เช่น วิดีโอ 10 fps = 0.1 วินาที)', 15, 700)
    rx = 40
    rec = [('ที่อยู่ภาพ 3 ไบต์', 170), ('ความยาวภาพ 2', 150), ('ADPCM pred 2', 140), ('idx 1', 70), ('เสียง 800 ไบต์ = 1,600 ตัวอย่าง × 4 บิต', 560)]
    for nm, w in rec:
        g = 'media' if 'เสียง' not in nm else 'sound'
        f.rect(rx, y3 + 14, w, 52, C[g][0], C[g][1], r=4, sw=1.5)
        f.text(rx + w / 2, y3 + 46, nm, 13, 600, 'middle', C[g][0])
        rx += w
    hx1 = 40 + sum(w for nm, w in rec[:4])  # header = first 4 fields (3+2+2+1 bytes)
    by = y3 + 76
    f.add(f'<path d="M42 {by - 6} V{by} H{hx1 - 2} V{by - 6}" fill="none" stroke="{MUTED}" stroke-width="1.5"/>')
    f.text((40 + hx1) / 2, by + 18, 'header 8 ไบต์', 13, 600, 'middle', MUTED)
    f.text(1140, y3 + 46, 'record r อยู่ที่ record0 + r × (8 + aud)', 13, 400, 'start', MUTED)
    # rle codes
    y4 = 700
    f.text(40, y4, 'รหัสของภาพแบบ delta + run-length (1 ไบต์ควบคุม)', 15, 700)
    codes = [('00nnnnnn', 'SKIP', 'ข้าม n+1 พิกเซล (เหมือนภาพก่อน)'), ('01nnnnnn c', 'FILL', 'เติม n+1 พิกเซลด้วยสี c'), ('1nnnnnnn …', 'COPY', 'n+1 พิกเซลตามมา บิตเรียงกัน')]
    for i, (b2, nm, ds) in enumerate(codes):
        x = 40 + i * 475
        f.rect(x, y4 + 16, 455, 56, C['video'][0], C['video'][1], r=6, sw=1.5)
        f.text(x + 14, y4 + 50, b2, 14, 700, 'start', C['video'][0], mono=True)
        f.text(x + 132, y4 + 50, f'{nm}: {ds}', 13.5, 400, 'start', INK)
    f.text(40, y4 + 110, 'ภาพ 160 × 120 พิกเซล เรียงทีละแถว (โหมด panel 96 × 88) · ภาพแรกของรายการไม่มี SKIP · ทุกค่าเก็บแบบ little-endian', 13, 400, 'start', MUTED)
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
    f.box(920, 20, 230, 80, 'โอกาส 62.5 %: โจมตี', ['(5 ใน 8, ต้องเชื่อมบอร์ด)'], 'chaos', mono=False)
    f.box(920, 130, 230, 80, 'โอกาส 37.5 %: โบนัส', ['FREEZE / SINK / I-PIECE'], 'link', mono=False)
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
