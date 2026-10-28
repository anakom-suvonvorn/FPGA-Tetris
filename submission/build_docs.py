# build_docs.py: turns the submission's Markdown files into Word files that
# import cleanly into Google Docs (headings, tables, pictures, Thai font).
#   python submission\build_docs.py
# Writes 2.1_Proposal\Proposal.docx and 2.3_Design_Document\Design_Document.docx.
# Only the Markdown this folder uses is understood: # headings, paragraphs,
# * / - / 1. lists, | tables |, ![caption](picture), > quotes, ``` code,
# **bold**, *italic*, `code`.
import os, re, sys
from docx import Document
from docx.enum.section import WD_ORIENT
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

HERE = os.path.dirname(os.path.abspath(__file__))
FONT, MONO = 'Sarabun', 'Consolas'
ACCENT = RGBColor(0x4C, 0x1D, 0x95)

DOCS = [
    ('2.1_Proposal/proposal.md', '2.1_Proposal/Proposal.docx', False),
    ('2.3_Design_Document/design_document.md', '2.3_Design_Document/Design_Document.docx', True),
]


def set_font(run_or_style, name, size=None, bold=None, color=None):
    f = run_or_style.font
    f.name = name
    if size:
        f.size = Pt(size)
    if bold is not None:
        f.bold = bold
    if color is not None:
        f.color.rgb = color
    el = run_or_style.element if hasattr(run_or_style, 'element') else run_or_style._element
    rpr = el.get_or_add_rPr()
    fonts = rpr.find(qn('w:rFonts'))
    if fonts is None:
        fonts = OxmlElement('w:rFonts')
        rpr.insert(0, fonts)
    for k in ('w:ascii', 'w:hAnsi', 'w:cs', 'w:eastAsia'):
        fonts.set(qn(k), name)
    if size:
        szcs = rpr.find(qn('w:szCs'))
        if szcs is None:
            szcs = OxmlElement('w:szCs')
            rpr.append(szcs)
        szcs.set(qn('w:val'), str(int(size * 2)))
    if bold:
        if rpr.find(qn('w:bCs')) is None:
            rpr.append(OxmlElement('w:bCs'))


def setup(doc):
    sec = doc.sections[0]
    sec.page_width, sec.page_height = Cm(21), Cm(29.7)
    sec.orientation = WD_ORIENT.PORTRAIT
    for side in ('left_margin', 'right_margin'):
        setattr(sec, side, Cm(2.2))
    sec.top_margin, sec.bottom_margin = Cm(2.0), Cm(2.0)
    st = doc.styles
    set_font(st['Normal'], FONT, 11)
    st['Normal'].paragraph_format.space_after = Pt(4)
    st['Normal'].paragraph_format.line_spacing = 1.15
    sizes = {1: 22, 2: 17, 3: 14, 4: 12}
    for lv, sz in sizes.items():
        s = st[f'Heading {lv}']
        set_font(s, FONT, sz, True, ACCENT if lv <= 2 else RGBColor(0x1D, 0x24, 0x33))
        s.paragraph_format.space_before = Pt(14 if lv <= 2 else 10)
        s.paragraph_format.space_after = Pt(6)
        s.paragraph_format.keep_with_next = True
    for name in ('List Bullet', 'List Number'):
        set_font(st[name], FONT, 11)


INLINE = re.compile(r'(\*\*[^*]+\*\*|`[^`]+`|\*[^*\s][^*]*\*)')


def add_inline(p, text, size=None, bold=False):
    for part in INLINE.split(text):
        if not part:
            continue
        if part.startswith('**') and part.endswith('**'):
            r = p.add_run(part[2:-2]); set_font(r, FONT, size, True)
        elif part.startswith('`') and part.endswith('`'):
            r = p.add_run(part[1:-1]); set_font(r, MONO, (size or 11) - 1, bold or None, RGBColor(0x9D, 0x17, 0x4D))
        elif part.startswith('*') and part.endswith('*') and len(part) > 2:
            r = p.add_run(part[1:-1]); set_font(r, FONT, size, bold or None); r.italic = True
        else:
            r = p.add_run(part); set_font(r, FONT, size, bold or None)


def shade(cell, hexcol):
    tcpr = cell._element.get_or_add_tcPr()
    sh = OxmlElement('w:shd')
    sh.set(qn('w:val'), 'clear'); sh.set(qn('w:color'), 'auto'); sh.set(qn('w:fill'), hexcol)
    tcpr.append(sh)


def add_table(doc, rows):
    cells = [[c.strip() for c in r.strip().strip('|').split('|')] for r in rows]
    cells = [r for r in cells if not all(re.fullmatch(r':?-{2,}:?', c) or c == '' for c in r)] if len(cells) > 1 else cells
    hdr, body = cells[0], cells[1:]
    empty_hdr = all(c == '' for c in hdr)
    data = body if empty_hdr else [hdr] + body
    ncol = max(len(r) for r in data)
    t = doc.add_table(rows=len(data), cols=ncol)
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, r in enumerate(data):
        for j in range(ncol):
            c = t.cell(i, j)
            c.paragraphs[0].paragraph_format.space_after = Pt(0)
            add_inline(c.paragraphs[0], r[j] if j < len(r) else '', size=10, bold=(i == 0 and not empty_hdr))
            if i == 0 and not empty_hdr:
                shade(c, 'EDE9FE')
    # column widths in proportion to the longest text in each column
    weight = [min(max(len(r[j]) if j < len(r) else 0 for r in data), 45) + 6 for j in range(ncol)]
    t.autofit = False
    for j in range(ncol):
        wcm = Cm(16.6 * weight[j] / sum(weight))
        for i in range(len(data)):
            t.cell(i, j).width = wcm
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def add_picture(doc, md_dir, cap, path):
    full = os.path.normpath(os.path.join(md_dir, path))
    if not os.path.exists(full):
        p = doc.add_paragraph(); add_inline(p, f'[รูป: {cap}]'); return
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.keep_with_next = True
    from PIL import Image
    w, h = Image.open(full).size
    width = 16.5 if w / h > 1.1 else 11.0
    p.add_run().add_picture(full, width=Cm(width))
    c = doc.add_paragraph(); c.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = c.add_run(cap); set_font(r, FONT, 10, None, RGBColor(0x5B, 0x64, 0x75)); r.italic = True


def convert(md_path, out_path, chapter_breaks):
    md_dir = os.path.dirname(md_path)
    lines = open(md_path, encoding='utf-8').read().split('\n')
    if lines and lines[0].strip() == '---':
        end = lines.index('---', 1)
        lines = lines[end + 1:]
    doc = Document()
    setup(doc)
    i, para, first_h2 = 0, [], True

    def flush():
        nonlocal para
        if para:
            p = doc.add_paragraph()
            add_inline(p, ' '.join(s.strip() for s in para))
            para = []

    while i < len(lines):
        ln = lines[i]
        s = ln.strip()
        if s.startswith('```'):
            flush(); i += 1
            while i < len(lines) and not lines[i].strip().startswith('```'):
                p = doc.add_paragraph(); p.paragraph_format.space_after = Pt(0)
                p.paragraph_format.left_indent = Cm(0.6)
                r = p.add_run(lines[i]); set_font(r, MONO, 9.5)
                i += 1
            i += 1; continue
        m = re.match(r'^(#{1,4})\s+(.*)$', s)
        if m:
            flush()
            lv = len(m.group(1))
            if lv == 2 and chapter_breaks:
                if not first_h2:
                    doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
                elif first_h2:
                    doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
                first_h2 = False
            h = doc.add_heading('', level=lv)
            add_inline(h, m.group(2))
            if lv == 1:
                h.alignment = WD_ALIGN_PARAGRAPH.CENTER
            i += 1; continue
        if s.startswith('|'):
            flush(); rows = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                rows.append(lines[i]); i += 1
            add_table(doc, rows); continue
        m = re.match(r'^!\[(.*?)\]\((.*?)\)$', s)
        if m:
            flush(); add_picture(doc, md_dir, m.group(1), m.group(2)); i += 1; continue
        m = re.match(r'^(\s*)([*-]|\d+\.)\s+(\[[ x]\]\s+)?(.*)$', ln)
        if m and s:
            flush()
            item = m.group(4)
            # continuation lines (indented, not a new item)
            while i + 1 < len(lines) and lines[i + 1].startswith('  ') and lines[i + 1].strip() and not re.match(r'^\s*([*-]|\d+\.)\s', lines[i + 1]):
                i += 1; item += ' ' + lines[i].strip()
            style = 'List Number' if m.group(2)[0].isdigit() else 'List Bullet'
            p = doc.add_paragraph(style=style)
            if m.group(1):
                p.paragraph_format.left_indent = Cm(1.6)
            box = '☐ ' if m.group(3) else ''
            add_inline(p, box + item)
            p.paragraph_format.space_after = Pt(2)
            i += 1; continue
        if s.startswith('>'):
            flush()
            p = doc.add_paragraph(); p.paragraph_format.left_indent = Cm(0.8)
            add_inline(p, s.lstrip('> ').strip()); i += 1; continue
        if s == '' or s == '---':
            flush(); i += 1; continue
        para.append(s); i += 1
    flush()
    doc.save(out_path)
    print('wrote', out_path)


if __name__ == '__main__':
    for md, out, br in DOCS:
        convert(os.path.join(HERE, md), os.path.join(HERE, out), br)
