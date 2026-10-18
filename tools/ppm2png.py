"""
ppm2png.py - convert the frame.ppm written by tb_vga_frame into a normal PNG
             (Windows can't open .ppm files). No extra Python packages needed.

Usage:  python tools\\ppm2png.py sim\\out\\frame.ppm sim\\out\\frame.png
"""
import struct
import sys
import zlib


def read_ppm(path):
    with open(path, encoding="ascii") as f:
        tokens = f.read().split()
    assert tokens[0] == "P3", "not a P3 ppm file"
    w, h, maxval = int(tokens[1]), int(tokens[2]), int(tokens[3])
    vals = [int(t) for t in tokens[4:4 + w * h * 3]]
    scale = 255 / maxval
    return w, h, bytes(int(v * scale + 0.5) for v in vals)


def write_png(path, w, h, rgb):
    raw = b"".join(b"\x00" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "frame.ppm"
    dst = sys.argv[2] if len(sys.argv) > 2 else src.rsplit(".", 1)[0] + ".png"
    w, h, rgb = read_ppm(src)
    write_png(dst, w, h, rgb)
    print(f"wrote {dst} ({w}x{h})")
