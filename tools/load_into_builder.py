"""
load_into_builder.py  -  fill the TA's FPGA Builder with one of our designs.

FPGA Builder remembers only ONE project, in
    D:\\setup\\FPGA_Builder_Package_V9\\fpga_builder.json
(it writes that file when you close it and reads it when you open it).
This script writes that file for you from a design's project.txt and pins.xdc,
so you don't have to add the VHDL files and pick every pin by hand.

Usage (FPGA Builder must be CLOSED, or it will overwrite this on exit):
    python tools\\load_into_builder.py 01_vga_bars
or double-click tools\\load_into_builder.bat and type the name.

The previous fpga_builder.json is kept as fpga_builder.backup.json.
"""
import json
import os
import re
import shutil
import sys

BUILDER_DIR = r"D:\setup\FPGA_Builder_Package_V9"
CONFIG = os.path.join(BUILDER_DIR, "fpga_builder.json")
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def find_design(name):
    for cand in (os.path.join(ROOT, "tests", name), os.path.join(ROOT, name), name):
        if os.path.isfile(os.path.join(cand, "project.txt")):
            return os.path.abspath(cand)
    sys.exit(f"Cannot find project.txt for '{name}'")


def read_project(d):
    top, files = None, []
    with open(os.path.join(d, "project.txt"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("top="):
                top = line[4:].strip()
            else:
                files.append(os.path.join(ROOT, line).replace("\\", "/"))
    return top, files


def read_pins(d):
    """[[port, 'PIN  (comment)', 'LVCMOS33', 'extra'], ...] from pins.xdc"""
    rows = []
    pat = re.compile(r"PACKAGE_PIN\s+(\w+)\s+IOSTANDARD\s+(\w+)([^}]*)\}.*?get_ports\s*\{([^}]+)\}\]\s*(?:;#\s*(.*))?")
    with open(os.path.join(d, "pins.xdc"), encoding="utf-8") as f:
        for line in f:
            m = pat.search(line)
            if m:
                pin, io, extra = m.group(1), m.group(2), m.group(3).strip()   # extra: e.g. "PULLUP true"
                port, note = m.group(4).strip(), (m.group(5) or "").strip()
                rows.append([port, f"{pin}  ({note})" if note else pin, io, extra])
    return rows


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    d = find_design(sys.argv[1])
    top, files = read_project(d)
    pins = read_pins(d)

    old = {}
    if os.path.exists(CONFIG):
        shutil.copyfile(CONFIG, os.path.join(BUILDER_DIR, "fpga_builder.backup.json"))
        with open(CONFIG, encoding="utf-8") as f:
            old = json.load(f)

    cfg = {
        "board": "edge",
        "ise": old.get("ise", ""),
        "vivado": old.get("vivado", ""),
        "ofl": old.get("ofl", ""),
        "cable": "ft2232",
        "vhdl": files,
        "part": "xc7s15",
        "speed": "-1",
        "pkg": "ftgb196",
        "top": top,
        "period": "20",
        "clk": "clk",
        "pins": pins,
    }
    with open(CONFIG, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    print(f"FPGA Builder is now set up for '{top}':")
    print(f"  {len(files)} VHDL files, {len(pins)} pins")
    print("Open FPGA_Builder.exe and press Build .bit")


if __name__ == "__main__":
    main()
