"""
remap_doc_lines.py - keep the "L123" line references in docs/learn/*.md correct
after a source file changed.

It compares the old version of a file (from git) with the current one, line
by line (difflib), and moves every reference in one section of a doc to the
line's new number. A reference to a line that was deleted is reported, so it
can be fixed by hand.

    python tools/remap_doc_lines.py <doc.md> "<section start>" "<section end>" <git rev> <source file>

Example (after changing tetris_core.vhd on the chaos branch):
    python tools/remap_doc_lines.py docs/learn/05_game_walkthrough.md "## 5.3 " "## 5.4 " main src/game/tetris_core.vhd

"<section end>" may be "" for "until the end of the doc".
Run it from the project folder.
"""
import difflib
import re
import subprocess
import sys


def line_map(old_lines, new_lines):
    """old line number (1-based) -> new line number, for lines that still exist"""
    m = {}
    sm = difflib.SequenceMatcher(a=old_lines, b=new_lines, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                m[i1 + k + 1] = j1 + k + 1
        elif tag == "replace" and (i2 - i1) == (j2 - j1):
            for k in range(i2 - i1):          # same number of lines, edited in place
                m[i1 + k + 1] = j1 + k + 1
    return m


def nearest(m, n, direction):
    """for a deleted line: the closest surviving line before/after it"""
    k = n
    while 0 < k < 100000:
        if k in m:
            return m[k]
        k += direction
    return None


def main():
    doc, start, end, rev, src = sys.argv[1:6]
    old = subprocess.run(["git", "show", f"{rev}:{src}"], capture_output=True, text=True,
                         encoding="utf-8", check=True).stdout.splitlines()
    new = open(src, encoding="utf-8").read().splitlines()
    m = line_map(old, new)

    text = open(doc, encoding="utf-8").read()
    a = text.index(start)
    b = text.index(end, a + len(start)) if end else len(text)
    part = text[a:b]
    problems = []

    def fix(mo):
        n1 = int(mo.group(1))
        n2 = int(mo.group(3)) if mo.group(3) else None
        r1 = m.get(n1) or nearest(m, n1, +1)
        if n1 not in m:
            problems.append(f"L{n1} was deleted or changed; now pointing at L{r1}")
        if n2 is None:
            return f"L{r1}"
        r2 = m.get(n2) or nearest(m, n2, -1)
        if n2 not in m:
            problems.append(f"L..{n2} was deleted or changed; now pointing at L{r2}")
        return f"L{r1}–{r2}"

    part = re.sub(r"L(\d+)(–(\d+))?", fix, part)
    open(doc, "w", encoding="utf-8").write(text[:a] + part + text[b:])
    print(f"{doc} [{start.strip()}]: remapped against {src}")
    for p in problems:
        print("   check:", p)


if __name__ == "__main__":
    main()
