"""Genera las imágenes de Novedades (WhatsNew.lua: el campo `image` de una novedad).

Lee los PNG originales de tools/whatsnew/ (una imagen por novedad, la página entera),
los reduce por media de área para que quepan en un lienzo de 2048x1024 sin deformarse,
los pone arriba a la izquierda del lienzo (el resto, negro) y escribe TGA de 24 bits
sin compresión en Media/WhatsNew/, con el mismo nombre. El juego pinta solo la parte
útil con SetTexCoord(0, w/2048, 0, h/1024): imprime `w` y `h` de cada una para copiarlos a
ES.WHATS_NEW. Sin dependencias (PNG de 8 bits por canal, RGB o RGBA, sin entrelazar).
Con --preview escribe además un PNG de cada TGA, para mirarlo.

    python tools/gen_whatsnew_images.py [--preview carpeta]
"""
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "whatsnew"
OUT = ROOT / "Media" / "WhatsNew"
# (en la ventana se ven a ~860x580 unidades: en 1080p, unos 1200x810 px reales; con
# 1024x512 se estiraban y se veían borrosas)
CANVAS_W, CANVAS_H = 2048, 1024


def read_png(path):
    """(ancho, alto, filas de (r, g, b)) de un PNG de 8 bits RGB o RGBA."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} no es un PNG")
    pos, idat = 8, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or ctype not in (2, 6) or interlace:
                raise ValueError(f"{path}: solo PNG de 8 bits RGB/RGBA sin entrelazar")
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    bpp = 3 if ctype == 2 else 4
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        ftype, line = raw[i], bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if ftype == 1:
                line[x] = (line[x] + a) & 255
            elif ftype == 2:
                line[x] = (line[x] + b) & 255
            elif ftype == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append([(line[x], line[x + 1], line[x + 2]) for x in range(0, stride, bpp)])
        prev = line
    return w, h, rows


def weights(src, dst):
    """Por cada píxel de destino, [(píxel de origen, peso)]: media de área."""
    k = src / dst
    out = []
    for d in range(dst):
        a, b = d * k, (d + 1) * k
        ws, s = [], int(a)
        while s < b and s < src:
            cover = min(b, s + 1) - max(a, s)
            if cover > 0:
                ws.append((s, cover / k))
            s += 1
        out.append(ws)
    return out


def resize(w, h, rows, nw, nh):
    wx, wy = weights(w, nw), weights(h, nh)
    horiz = []
    for row in rows:
        line = []
        for ws in wx:
            r = g = b = 0.0
            for s, f in ws:
                pr, pg, pb = row[s]
                r, g, b = r + pr * f, g + pg * f, b + pb * f
            line.append((r, g, b))
        horiz.append(line)
    out = []
    for ws in wy:
        line = []
        for x in range(nw):
            r = g = b = 0.0
            for s, f in ws:
                pr, pg, pb = horiz[s][x]
                r, g, b = r + pr * f, g + pg * f, b + pb * f
            line.append((min(255, int(r + 0.5)), min(255, int(g + 0.5)), min(255, int(b + 0.5))))
        out.append(line)
    return out


def fit(w, h):
    """Tamaño útil dentro del lienzo, con la proporción del original."""
    k = min(CANVAS_W / w, CANVAS_H / h, 1.0)
    return max(1, round(w * k)), max(1, round(h * k))


def canvas(rows, nw, nh):
    black = (0, 0, 0)
    return [(rows[y] + [black] * (CANVAS_W - nw)) if y < nh else [black] * CANVAS_W
            for y in range(CANVAS_H)]


def write_tga(path, pix):
    # Sin compresión, 24 bits, origen arriba a la izquierda (descriptor 0x20)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, CANVAS_W, CANVAS_H, 24, 0x20)
    body = bytearray()
    for row in pix:
        for r, g, b in row:
            body += bytes((b, g, r))
    path.write_bytes(header + bytes(body))


def read_tga(path):
    """Las filas (r, g, b) de un TGA escrito por write_tga (para la vista previa)."""
    data = path.read_bytes()
    w, h = struct.unpack("<HH", data[12:16])
    body = data[18:]
    return w, h, [[(body[(y * w + x) * 3 + 2], body[(y * w + x) * 3 + 1], body[(y * w + x) * 3])
                   for x in range(w)] for y in range(h)]


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)

    def chunk(kind, data):
        c = struct.pack(">I", len(data)) + kind + data
        return c + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    preview = None
    if "--preview" in sys.argv:
        preview = Path(sys.argv[sys.argv.index("--preview") + 1])
        preview.mkdir(parents=True, exist_ok=True)
    for src in sorted(SRC.glob("*.png")):
        w, h, rows = read_png(src)
        nw, nh = fit(w, h)
        out = OUT / (src.stem + ".tga")
        write_tga(out, canvas(resize(w, h, rows, nw, nh), nw, nh))
        print(f"{out.relative_to(ROOT)}: {w}x{h} -> w = {nw}, h = {nh}")
        if preview:
            write_png(preview / (src.stem + ".png"), *read_tga(out))
            print("  vista previa en", preview / (src.stem + ".png"))


if __name__ == "__main__":
    main()
