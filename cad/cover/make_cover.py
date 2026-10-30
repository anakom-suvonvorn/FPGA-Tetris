"""
Cover plate for the EDGE Spartan-7 board, made for Tetris Duel (main and chaos).

A thin plate that sits on 4 legs over the board (one leg on each mounting
hole), its top 6 mm above the PCB. The 16 slide switches share one opening;
the push buttons get printed extenders held in by pockets under the plate.
It has windows for what the game uses (7-segment display, VGA, audio, J5
link header, USB, power, reset) and for the parts taller than the plate
(pin headers, jumpers, buzzer, temperature sensor). Everything else is
hidden. Labels are inlaid 0.6 mm into the top face, so they can be printed
in a second colour (or left as engraved grooves).

Positions come from a top-down photo of the board (ref/board_top.webp),
scaled to the measured board size, plus a few numbers measured on the real
board (holes, slide switch row, heights): see "MEASURED" below.

Run:   python make_cover.py
Out:   out/cover.3mf              plate + labels as one 2-part object (best for OrcaSlicer / Bambu Studio)
       out/cover_body.stl         the plate alone, upside down, ready to print
       out/cover_labels.stl       the label inlay alone (same position as the body)
       out/button_caps.stl        the 5 push-button extenders
       out/spacers_m3.stl         4 M3 spacers, 2 mm
       out/check_overlay.png      the plate drawn on the photo: windows must sit on their parts
       out/preview.png            3D view
       out/template_1to1.pdf      print on paper at 100 % and lay it on the board to check the fit
"""

import os

import numpy as np
from shapely import set_precision
from shapely.geometry import Polygon, Point, box, LineString
from shapely.ops import unary_union
from shapely.affinity import translate, rotate, scale as shp_scale
from matplotlib.textpath import TextPath
from matplotlib.font_manager import FontProperties
import manifold3d as mf
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
PHOTO = os.path.join(HERE, "ref", "board_top.webp")

# ---------------------------------------------------------------- MEASURED
BOARD_W, BOARD_H = 130.0, 100.0   # PCB size
BOTTOM_HOLE_SPACING = 120.0       # centre to centre, bottom mounting holes
TOP_HOLE_SPACING = 77.5           # centre to centre, top mounting holes
SW_ROW_LEN = 103.5                # the 16 slide switches, outer edge to outer edge
SW_FROM_LEFT_HOLE = 7.5           # bottom-left hole centre -> left edge of the leftmost switch
SW_FROM_RIGHT_HOLE = 9.0          # right edge of the rightmost switch -> bottom-right hole centre
SWITCH_FRAME_H = 6.0              # PCB -> top of a slide switch's metal frame (switches get one big opening)
SWITCH_KNOB_H = 12.0              # PCB -> top of its plastic knob
BUTTON_TOP = 4.5                  # PCB -> top of a push button
BUZZER_H = 10.0                   # USB-B 11, VGA 11.7: both are cut out at the edge

# ---------------------------------------------------------------- options
PLATE_TOP = 6.0                   # PCB -> top face of the plate
THICK = 1.6                       # plate thickness
PLATE_Z = PLATE_TOP - THICK       # PCB -> underside of the plate (= leg height): everything covered must be lower
CLR = 0.6                         # extra gap around every window
SW_W = 6.4                        # width of one slide switch body
SW_OPEN_W, SW_OPEN_H = 105.0, 17.0   # one opening for all 16 slide switches, from the bottom edge up
BUTTON_CAPS = True                # False: one open D-pad window instead
BUTTON_WINDOW = 10.0              # square per button when BUTTON_CAPS = False
# Button extenders: a knob through the plate and a wide base that sits in a
# pocket in the underside of the plate (so it can't fall out). The base has a
# shallow dimple that sits on the button's plunger.
CAP_HOLE, CAP_KNOB = 8.4, 8.2     # hole in the plate, knob diameter (0.1 mm gap all round)
# The buttons above / below the centre one are only 9.7 mm apart, so the base
# is a disc with two flats (top and bottom): wide sideways, narrow up / down.
CAP_BASE, CAP_BASE_FLAT = 11.0, 9.2   # base diameter, width across the flats
POCKET_CLR = 0.3                  # pocket = base + this all round
POCKET_H = 0.9                    # pocket depth into the underside (leaves 0.7 mm on top)
CAP_DIMPLE_D, CAP_DIMPLE_H = 3.6, 0.5   # dimple for the 3.4 mm plunger: base bottom = BUTTON_TOP - 0.5
CAP_STICK_OUT = 4.0               # knob top above the plate
LABEL_DEPTH = 0.6                 # inlay depth of the labels (3 layers at 0.2 mm)
FONT = FontProperties(family="DejaVu Sans", weight="bold")
LEG_OD, LEG_BORE = 6.0, 3.3       # legs: M3 clearance bore
SPACER_H, SPACER_N = 2.0, 4       # separate M3 spacers (same OD / bore as the legs)
CORNER_R = 2.5
MIN_WEB = 1.4                     # plastic strips thinner than this between windows are removed
OPEN_WIFI = False                 # True if the WiFi module turns out taller than PLATE_Z
OPEN_Y1 = False                   # True if the crystal Y1 (HC-49, ~3.5-4 mm) touches the plate

# ---------------------------------------------------------------- photo -> mm
# In the photo the PCB spans x 58..1120 px, y 218..1036 px (= 130 x 100 mm).
PX0, PY0 = 58.0, 1036.0           # PCB bottom-left corner in the photo
KX, KY = (1120 - 58) / BOARD_W, (1036 - 218) / BOARD_H   # px per mm


def pt(px, py):
    """Photo pixel -> board mm (origin bottom-left of the PCB, y up)."""
    return ((px - PX0) / KX, (PY0 - py) / KY)


def rect_px(x0, y0, x1, y1, clr=CLR):
    """Window from a pixel box (top-left, bottom-right) plus clearance."""
    (ax, ay), (bx, by) = pt(x0, y1), pt(x1, y0)
    return box(ax - clr, ay - clr, bx + clr, by + clr)


def square_at(px, py, size, r=1.0):
    x, y = pt(px, py)
    s = size / 2 - r
    return box(x - s, y - s, x + s, y + s).buffer(r, quad_segs=8)


def circle_at(px, py, d):
    x, y = pt(px, py)
    return Point(x, y).buffer(d / 2, quad_segs=24)


def spaced(p0, p1, spacing):
    """Two photo points moved apart/together to a measured spacing (same midpoint)."""
    (x0, y0), (x1, y1) = pt(*p0), pt(*p1)
    mx, my, half = (x0 + x1) / 2, (y0 + y1) / 2, spacing / 2
    return [(mx - half, y0), (mx + half, y1)]


# ---------------------------------------------------------------- board parts
HOLES = spaced((317, 430), (950, 425), TOP_HOLE_SPACING) + spaced((96, 995), (1082, 995), BOTTOM_HOLE_SPACING)

# Push buttons (centre of each, px)
BUTTONS = {
    "rotate": (899, 646),   # SW16 top
    "left":   (800, 725),   # SW14
    "drop":   (899, 725),   # SW18 centre: hard drop / start
    "right":  (996, 725),   # SW20
    "soft":   (899, 805),   # SW23 bottom
}

# The 16 slide switches: index 0 = leftmost (SW22) ... 15 = rightmost (SW2).
SW_LEFT = HOLES[2][0] + SW_FROM_LEFT_HOLE
SW_RIGHT = HOLES[3][0] - SW_FROM_RIGHT_HOLE
SW_PITCH = (SW_RIGHT - SW_LEFT - SW_W) / 15
SW_Y = pt(0, 955)[1]                       # centre of the switch bodies (photo)
SETTINGS = {          # index: icon above the slot (main + chaos)
    15: "pause",      # SW2
    14: "music",      # SW4
    13: "sfx",        # SW5: speaker
    12: "chaos",      # SW6: CHAOS on (chaos branch)
    11: "pc",         # SW7: link over USB
}
TASKS = range(0, 8)   # SW22 .. SW11: the chaos task switches; 8..10 are free
ICON = 3.6            # icon size (mm)

# Windows that are always cut: what the game uses + parts taller than the plate (px boxes)
WINDOWS = [
    rect_px(40, 190, 272, 310),      # DC jack J1 + USB-B (programming / PC link), open to the top edge
    rect_px(40, 300, 170, 405),      # power switch SW3
    rect_px(482, 190, 752, 355),     # VGA, open to the top edge
    rect_px(972, 190, 1140, 338),    # USB-A (PS2) socket, ~7 mm tall, open to the top edge
    rect_px(1012, 385, 1140, 500),   # audio jack, open to the right edge
    circle_at(1074, 565, 6.5),       # reset button
    rect_px(1050, 625, 1140, 855),   # J5 header (board link), open to the right edge
    rect_px(140, 690, 397, 807, 0.2),  # 7-segment display (tight on the left: a 1.7 mm strip to the ADC header)
    rect_px(200, 580, 247, 645),     # temperature sensor (TO-92 stands up); the LDR is covered
    # pin headers and jumpers (8.5 mm)
    rect_px(40, 400, 100, 560),      # J3 JTAG, open to the left edge
    rect_px(40, 630, 124, 748, 0.1),   # ADC channel header, open to the left edge
    rect_px(278, 218, 320, 390),     # J15 BLE header + PWR jumper
    rect_px(362, 460, 392, 532),     # J16 USB UART header
    rect_px(755, 218, 790, 378),     # J10 / J11
    rect_px(830, 520, 910, 548),     # J6 buzzer jumper
    rect_px(40, 840, 125, 925),      # J9 LED 9-16 jumper, open to the left edge
    rect_px(1050, 852, 1088, 930),   # J4 LED 1-8 jumper
    rect_px(295, 995, 665, 1060),    # LCD header (bottom edge)
    rect_px(825, 995, 1015, 1060),   # TFT header (bottom edge)
]
if OPEN_WIFI:
    WINDOWS.append(rect_px(800, 150, 950, 352))
if OPEN_Y1:
    WINDOWS.append(rect_px(260, 455, 300, 550))

BUZZER, BUZZER_D = (864, 437), 12.4

# Labels: (text, centre px, size mm). Size = font size; capitals are ~0.73 of it.
LABELS = [
    ("ROTATE", (899, 590), 3.0),
    ("LEFT", (800, 668), 3.0),
    ("RIGHT", (997, 668), 2.8),
    ("HARD", (811, 796), 2.6),     # centre button: HARD DROP (+ arrow)
    ("DROP", (811, 822), 2.6),
    ("SOFT", (985, 796), 2.6),     # bottom button: SOFT DROP
    ("DROP", (985, 822), 2.6),
    ("LINES", (268, 668), 3.0),
    ("VGA", (617, 392), 3.0),
    ("AUDIO", (1000, 520), 2.6),
    ("RST", (1018, 565), 2.4),
    ("LINK", (1082, 606), 2.4),
    ("USB", (211, 342), 3.0),
    ("TETRIS DUEL", (590, 500), 6.0),
]
ARROWS = [   # small arrows from a label to its button: (from px, to px)
    ((850, 785), (868, 762)),   # HARD DROP -> centre button
]


# ---------------------------------------------------------------- 2D helpers
def text_shape(s, size, cx, cy, angle=0.0):
    """Text as a shapely shape centred on (cx, cy) mm."""
    tp = TextPath((0, 0), s, size=size, prop=FONT)
    g = Polygon()
    for ring in tp.to_polygons(closed_only=True):
        if len(ring) >= 3:
            g = g.symmetric_difference(Polygon(ring).buffer(0))
    x0, y0, x1, y1 = g.bounds
    g = translate(g, -(x0 + x1) / 2, -(y0 + y1) / 2)
    g = rotate(g, angle, origin=(0, 0))
    return translate(g, cx, cy)


def arrow(p0, p1, w=0.5, head=1.4):
    a, b = np.array(pt(*p0)), np.array(pt(*p1))
    d = b - a
    L = np.linalg.norm(d)
    u, n = d / L, np.array([-d[1], d[0]]) / L
    tip = b
    base = b - u * head
    shaft = Polygon([a + n * w / 2, base + n * w / 2, base - n * w / 2, a - n * w / 2])
    hd = Polygon([tip, base + n * head * 0.6, base - n * head * 0.6])
    return shaft.union(hd)


def icon(kind, cx, cy, s=ICON):
    """Small symbols for the slide switches, s mm square, centred on (cx, cy)."""
    u = s / 10.0
    if kind == "pause":
        g = box(-3.5, -4, -1, 4).union(box(1, -4, 3.5, 4))
    elif kind == "music":   # quaver: head, stem, flag
        g = unary_union([Point(-1.6, -3.0).buffer(2.0, quad_segs=12), box(-0.1, -3.0, 1.5, 4.8),
                         Polygon([(1.5, 4.8), (4.6, 2.0), (4.6, 0.6), (1.5, 2.8)])])
    elif kind == "sfx":     # speaker with one sound wave
        body = Polygon([(-5, -1.6), (-2.8, -1.6), (0.6, -4.4), (0.6, 4.4), (-2.8, 1.6), (-5, 1.6)])
        ring = Point(0.6, 0).buffer(4.6, quad_segs=16).difference(Point(0.6, 0).buffer(3.2, quad_segs=16))
        g = body.union(ring.intersection(box(2.2, -5, 6, 5)))
    elif kind == "chaos":   # lightning bolt
        g = Polygon([(1.8, 5), (-3.2, -0.6), (-0.2, -0.6), (-1.8, -5), (3.2, 0.9), (0.2, 0.9)])
    else:
        return text_shape("PC", s * 0.85, cx, cy)
    g = shp_scale(g, u, u, origin=(0, 0))
    return translate(g, cx, cy)


def switch_x(i):
    """Centre of slide switch i (mm)."""
    return SW_LEFT + SW_W / 2 + SW_PITCH * i


def build_2d():
    outline = box(CORNER_R, CORNER_R, BOARD_W - CORNER_R, BOARD_H - CORNER_R).buffer(CORNER_R, quad_segs=12)

    cuts = list(WINDOWS)
    if not BUTTON_CAPS:   # the windows overlap (buttons are 9.7 mm apart), so cut them as one D-pad shaped cross
        cuts.append(unary_union([square_at(px, py, BUTTON_WINDOW, 0.1) for px, py in BUTTONS.values()])
                    .buffer(1.0, quad_segs=8).buffer(-1.0, quad_segs=8))
    # one opening for all 16 slide switches, open to the bottom edge, centred on the row
    mid = (SW_LEFT + SW_RIGHT) / 2
    open_top = SW_OPEN_H
    cuts.append(box(mid - SW_OPEN_W / 2, -1, mid + SW_OPEN_W / 2, open_top))
    if BUZZER_H >= PLATE_Z:
        cuts.append(circle_at(*BUZZER, BUZZER_D + 1.0))
    cuts = unary_union(cuts)
    plate = outline.difference(cuts)
    # drop strips too thin to print between windows
    plate = plate.buffer(-MIN_WEB / 2, quad_segs=8).buffer(MIN_WEB / 2, quad_segs=8).intersection(outline)
    assert plate.geom_type == "Polygon", "windows cut the plate into pieces: move or shrink one"

    small = []   # extender holes, buzzer grille (if it fits under) and leg bores: cut after the thin-strip clean-up
    if BUTTON_CAPS:   # (the strip between the holes above / below the centre one is only 1.3 mm)
        small += [circle_at(px, py, CAP_HOLE) for px, py in BUTTONS.values()]
    if BUZZER_H < PLATE_Z:
        bx, by = pt(*BUZZER)
        for gx in np.arange(-4.2, 4.3, 2.8):
            for gy in np.arange(-4.2, 4.3, 2.8):
                if gx * gx + gy * gy <= 4.8 ** 2:
                    small.append(Point(bx + gx, by + gy).buffer(0.8, quad_segs=8))
    for x, y in HOLES:
        small.append(Point(x, y).buffer(LEG_BORE / 2, quad_segs=24))
    plate = plate.difference(unary_union(small))
    cuts = outline.difference(plate)

    labels = []
    for s, (px, py), size in LABELS:
        labels.append(text_shape(s, size, *pt(px, py)))
    for p0, p1 in ARROWS:
        labels.append(arrow(p0, p1))
    # settings switches: a small "on" triangle above each one, then an icon
    for i, kind in SETTINGS.items():
        x = switch_x(i)
        labels.append(Polygon([(x, open_top + 1.9), (x - 1.0, open_top + 0.7), (x + 1.0, open_top + 0.7)]))
        labels.append(icon(kind, x, open_top + 2.3 + ICON / 2))
    # chaos task switches: a bracket over the 8 and a name
    x0, x1 = switch_x(TASKS[0]) - SW_W / 2 + 0.6, switch_x(TASKS[-1]) + SW_W / 2 - 0.6
    yb = open_top + 1.3
    labels.append(LineString([(x0, yb - 0.9), (x0, yb), (x1, yb), (x1, yb - 0.9)]).buffer(0.3, cap_style=2, join_style=2))
    labels.append(text_shape("TASK SWITCHES", 2.8, (x0 + x1) / 2, yb + 2.2))

    labels = unary_union(labels).intersection(outline.buffer(-1.0)).difference(cuts.buffer(0.6))
    if BUTTON_CAPS:   # the plastic over the extender pockets is too thin for an inlay
        labels = labels.difference(pockets().buffer(0.6))
    # snap to a 1 um grid: no near-duplicate points, so the meshes stay watertight in STL
    plate, labels = set_precision(plate, 1e-3), set_precision(labels, 1e-3)
    return outline, plate, labels, cuts


# ---------------------------------------------------------------- 3D helpers
def to_cs(geom):
    contours = []
    for p in getattr(geom, "geoms", [geom]):
        if p.is_empty or p.geom_type != "Polygon":
            continue
        contours.append(np.array(p.exterior.coords[:-1]))
        for r in p.interiors:
            contours.append(np.array(r.coords[:-1]))
    return mf.CrossSection(contours, mf.FillRule.EvenOdd)


def extrude(geom, z0, h):
    return mf.Manifold.extrude(to_cs(geom), h).translate((0, 0, z0))


def to_trimesh(m):
    mesh = m.to_mesh()
    return trimesh.Trimesh(vertices=np.asarray(mesh.vert_properties)[:, :3], faces=np.asarray(mesh.tri_verts), process=False)


def base_shape(grow=0.0):
    """Outline of an extender base around (0, 0): a disc with flats top and bottom."""
    w = CAP_BASE / 2 + grow
    return Point(0, 0).buffer(w, quad_segs=24).intersection(box(-w, -CAP_BASE_FLAT / 2 - grow, w, CAP_BASE_FLAT / 2 + grow))


def pockets():
    """The extender pockets in the underside of the plate."""
    return unary_union([translate(base_shape(POCKET_CLR), *pt(px, py)) for px, py in BUTTONS.values()])


def build_3d(plate, labels):
    z_top = PLATE_Z + THICK
    body = extrude(plate, PLATE_Z, THICK)
    for x, y in HOLES:
        leg = Point(x, y).buffer(LEG_OD / 2, quad_segs=24).difference(Point(x, y).buffer(LEG_BORE / 2, quad_segs=24))
        body = body + extrude(leg, 0, PLATE_Z + 0.01)
    if BUTTON_CAPS:
        body = body - extrude(pockets(), PLATE_Z - 0.01, POCKET_H + 0.01)
    label_solid = extrude(labels, z_top - LABEL_DEPTH, LABEL_DEPTH)
    body = body - extrude(labels, z_top - LABEL_DEPTH, LABEL_DEPTH + 0.01)
    return body, label_solid


CAP_Z = BUTTON_TOP - CAP_DIMPLE_H          # bottom of an extender, sitting on its button


def cap():
    """One button extender, from its bottom (z = 0): a base with a dimple for the
    plunger, sitting in the pocket under the plate, and a knob through the plate."""
    base_top = PLATE_Z + POCKET_H - 0.3 - CAP_Z    # 0.3 mm play under the pocket ceiling
    knob_top = PLATE_TOP + CAP_STICK_OUT - CAP_Z
    base = extrude(base_shape(), 0, base_top)
    knob = mf.Manifold.cylinder(knob_top - base_top, CAP_KNOB / 2, circular_segments=64).translate((0, 0, base_top))
    dimple = mf.Manifold.cylinder(CAP_DIMPLE_H, CAP_DIMPLE_D / 2, circular_segments=48).translate((0, 0, -0.01))
    return base + knob - dimple


def build_spacers():
    """M3 spacers in a row (washer-like rings, same size as the legs)."""
    ring = Point(0, 0).buffer(LEG_OD / 2, quad_segs=24).difference(Point(0, 0).buffer(LEG_BORE / 2, quad_segs=24))
    rings = unary_union([translate(ring, k * (LEG_OD + 3), 0) for k in range(SPACER_N)])
    return extrude(rings, 0, SPACER_H)


def build_caps():
    """The 5 extenders in a row, base down: prints without supports."""
    caps = mf.Manifold()
    for k in range(5):
        caps = caps + cap().translate((k * (CAP_BASE + 3), 0, 0))
    return caps


# ---------------------------------------------------------------- outputs
def flip_for_print(t):
    """Top face down on the bed: smooth top, labels in the first layers, legs point up."""
    t = t.copy()
    t.apply_transform(trimesh.transformations.rotation_matrix(np.pi, [0, 1, 0]))
    t.apply_translation([BOARD_W, 0, PLATE_Z + THICK])
    return t


def save_3mf(path, parts):
    """3MF with one object made of several parts (slicers keep them aligned)."""
    import zipfile
    objs, comps = [], []
    for i, (name, t) in enumerate(parts, start=1):
        v = "".join(f'<vertex x="{a:.4f}" y="{b:.4f}" z="{c:.4f}"/>' for a, b, c in t.vertices)
        f = "".join(f'<triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in t.faces)
        objs.append(f'<object id="{i}" name="{name}" type="model"><mesh><vertices>{v}</vertices>'
                    f'<triangles>{f}</triangles></mesh></object>')
        comps.append(f'<component objectid="{i}"/>')
    top = len(parts) + 1
    model = ('<?xml version="1.0" encoding="UTF-8"?>'
             '<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">'
             f'<resources>{"".join(objs)}<object id="{top}" name="edge_cover" type="model">'
             f'<components>{"".join(comps)}</components></object></resources>'
             f'<build><item objectid="{top}"/></build></model>')
    types = ('<?xml version="1.0" encoding="UTF-8"?>'
             '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
             '<Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/></Types>')
    rels = ('<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Target="/3D/3dmodel.model" Id="rel0" '
            'Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", types)
        z.writestr("_rels/.rels", rels)
        z.writestr("3D/3dmodel.model", model)


def save_overlay(outline, plate, labels, cuts):
    from PIL import Image, ImageDraw
    if not os.path.exists(PHOTO):
        print("no photo, skipping overlay")
        return
    im = Image.open(PHOTO).convert("RGBA")
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def px(xy):
        x, y = xy
        return (x * KX + PX0, PY0 - y * KY)

    def draw(geom, fill, outline_col):
        for p in getattr(geom, "geoms", [geom]):
            if p.is_empty or p.geom_type != "Polygon":
                continue
            d.polygon([px(c) for c in p.exterior.coords], fill=fill, outline=outline_col)
            for r in p.interiors:
                d.polygon([px(c) for c in r.coords], fill=(0, 0, 0, 0), outline=outline_col)

    draw(plate, (30, 90, 200, 120), (20, 60, 200, 255))
    draw(labels, (255, 230, 0, 255), None)
    for x, y in HOLES:
        hx, hy = px((x, y))
        d.ellipse([hx - LEG_OD / 2 * KX, hy - LEG_OD / 2 * KY,
                   hx + LEG_OD / 2 * KX, hy + LEG_OD / 2 * KY], outline=(255, 0, 0, 255), width=3)
    for i in range(16):   # measured switch positions, to compare with the photo
        cx, cy = px((switch_x(i), SW_Y))
        d.line([(cx, cy - 60), (cx, cy + 60)], fill=(255, 0, 255, 255), width=1)
    Image.alpha_composite(im, layer).convert("RGB").save(os.path.join(OUT, "check_overlay.png"))


def save_template(outline, plate, labels):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import PathPatch
    from matplotlib.path import Path
    margin = 10
    w, h = BOARD_W + 2 * margin, BOARD_H + 2 * margin
    fig = plt.figure(figsize=(w / 25.4, h / 25.4))
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(-margin, BOARD_W + margin)
    ax.set_ylim(-margin, BOARD_H + margin)
    ax.set_aspect("equal")
    ax.axis("off")

    def patch(geom, **kw):
        for p in getattr(geom, "geoms", [geom]):
            if p.is_empty or p.geom_type != "Polygon":
                continue
            verts, codes = [], []
            for ring in [p.exterior, *p.interiors]:
                c = list(ring.coords)
                verts += c
                codes += [Path.MOVETO] + [Path.LINETO] * (len(c) - 2) + [Path.CLOSEPOLY]
            ax.add_patch(PathPatch(Path(verts, codes), **kw))

    patch(plate, facecolor="#dddddd", edgecolor="black", lw=0.4)
    patch(labels, facecolor="black", edgecolor="none")
    for x, y in HOLES:
        ax.add_patch(plt.Circle((x, y), LEG_OD / 2, fill=False, lw=0.4, color="red"))
    ax.plot([0, 50], [-margin / 2, -margin / 2], color="black", lw=0.8)
    ax.text(25, -margin / 2 + 1, "this line must measure 50 mm", ha="center", fontsize=6)
    fig.savefig(os.path.join(OUT, "template_1to1.pdf"))
    plt.close(fig)


def render(meshes, elev=50, azim=-60, size=1400):
    """Tiny z-buffer renderer (orthographic): list of (trimesh, rgb) -> image array."""
    a, e = np.radians(azim), np.radians(elev)
    rz = np.array([[np.cos(a), -np.sin(a), 0], [np.sin(a), np.cos(a), 0], [0, 0, 1]])
    rx = np.array([[1, 0, 0], [0, np.sin(e), np.cos(e)], [0, -np.cos(e), np.sin(e)]])
    R = rx @ rz.T
    light = R @ (np.array([-0.4, -0.6, 1.0]) / np.linalg.norm([-0.4, -0.6, 1.0]))
    allv = np.vstack([m.vertices @ R.T for m, _ in meshes])
    lo, hi = allv[:, :2].min(0), allv[:, :2].max(0)
    k = (size - 40) / (hi - lo).max()
    w, h = [int(v) + 40 for v in (hi - lo) * k]
    img = np.full((h, w, 3), 245.0)
    zb = np.full((h, w), -np.inf)
    for m, rgb in meshes:
        v = m.vertices @ R.T
        n = m.face_normals @ R.T
        p = np.column_stack([(v[:, 0] - lo[0]) * k + 20, h - ((v[:, 1] - lo[1]) * k + 20), v[:, 2]])
        shade = 0.35 + 0.65 * np.abs(n @ light)
        for f, s in zip(m.faces, shade):
            t = p[f]
            x0, y0 = np.floor(t[:, :2].min(0)).astype(int)
            x1, y1 = np.ceil(t[:, :2].max(0)).astype(int)
            x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, w - 1), min(y1, h - 1)
            if x1 < x0 or y1 < y0:
                continue
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            (ax_, ay), (bx, by), (cx, cy) = t[:, :2]
            den = (by - cy) * (ax_ - cx) + (cx - bx) * (ay - cy)
            if abs(den) < 1e-9:
                continue
            l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
            l2 = ((cy - ay) * (xs - cx) + (ax_ - cx) * (ys - cy)) / den
            l3 = 1 - l1 - l2
            inside = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
            z = l1 * t[0, 2] + l2 * t[1, 2] + l3 * t[2, 2]
            sub = zb[y0:y1 + 1, x0:x1 + 1]
            upd = inside & (z > sub)
            sub[upd] = z[upd]
            img[y0:y1 + 1, x0:x1 + 1][upd] = np.array(rgb) * s
    return img.astype(np.uint8)


def save_preview(body_t, label_t):
    from PIL import Image
    use = [(body_t, (70, 110, 210)), (label_t, (255, 215, 40))]
    if BUTTON_CAPS:   # caps sitting on the buttons
        caps = mf.Manifold()
        for px_, py_ in BUTTONS.values():
            caps = caps + cap().translate((*pt(px_, py_), CAP_Z))
        use.append((to_trimesh(caps), (235, 235, 235)))
    top = render(use, elev=55, azim=-15)
    under = render(use, elev=-35, azim=-15, size=900)
    Image.fromarray(top).save(os.path.join(OUT, "preview.png"))
    Image.fromarray(under).save(os.path.join(OUT, "preview_under.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    outline, plate, labels, cuts = build_2d()
    body, label_solid = build_3d(plate, labels)
    body_t, label_t = to_trimesh(body), to_trimesh(label_solid)

    save_overlay(outline, plate, labels, cuts)
    save_template(outline, plate, labels)
    save_preview(body_t, label_t)

    pb, pl = flip_for_print(body_t), flip_for_print(label_t)
    pb.export(os.path.join(OUT, "cover_body.stl"))
    pl.export(os.path.join(OUT, "cover_labels.stl"))
    save_3mf(os.path.join(OUT, "cover.3mf"), [("cover_body", pb), ("cover_labels", pl)])
    to_trimesh(build_caps()).export(os.path.join(OUT, "button_caps.stl"))
    to_trimesh(build_spacers()).export(os.path.join(OUT, "spacers_m3.stl"))

    print(f"board {BOARD_W:.1f} x {BOARD_H:.1f} mm, plate {PLATE_Z} mm up, {THICK} mm thick")
    print(f"body watertight={body_t.is_watertight} volume={body_t.volume / 1000:.1f} cm3, labels {label_t.volume / 1000:.2f} cm3")


if __name__ == "__main__":
    main()
