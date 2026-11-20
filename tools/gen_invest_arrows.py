"""Genera los triángulos de la pestaña Inversiones (InvestUI.lua): verde hacia arriba
(el precio está por encima de tu media), rojo hacia abajo (por debajo) y sus versiones
en gris (precio viejo), planos y del color del % que acompañan.

Salen en Media/Invest/ como TGA de 32x32 (sin compresión, con alfa):
Up, Down, Up-Grey, Down-Grey, Dot (punto blanco redondo para la gráfica) y ViewGrid /
ViewList (los botones de vista de fichas o de lista, en blanco). Las monedas no: el
addon usa siempre las del juego (ES.Money). Sin dependencias: se dibuja a mano con
supermuestreo. Con --preview escribe además un PNG con los triángulos, ampliados.

    python tools/gen_invest_arrows.py [--preview carpeta]
"""
import struct
import sys
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Media" / "Invest"
SIZE = 32
SS = 4  # supermuestreo por lado

# Planos y macizos, del mismo color que el % que acompañan (los del texto del addon:
# |cff40ff40, |cffff4040, |cff9d9d9d), sin borde: "▲ +95%"
COLORS = {
    "green": (64, 255, 64),
    "red": (255, 64, 64),
    "grey": (157, 157, 157),
}


def inside(x, y, pts):
    (x1, y1), (x2, y2), (x3, y3) = pts

    def side(ax, ay, bx, by):
        return (x - bx) * (ay - by) - (ax - bx) * (y - by)

    d1, d2, d3 = side(x1, y1, x2, y2), side(x2, y2, x3, y3), side(x3, y3, x1, y1)
    return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def sample(x, y, up, color):
    """Color y alfa de un punto (x, y desde el centro; y hacia abajo)."""
    s = -1 if up else 1  # la punta: arriba (y negativa) o abajo
    core = [(0.0, s * 10.0), (-12.0, -s * 9.0), (12.0, -s * 9.0)]
    if inside(x, y, core):
        return COLORS[color], 1.0
    return (0, 0, 0), 0.0


def render(up, color):
    pixels = []
    for py in range(SIZE):
        for px in range(SIZE):
            r = g = b = a = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    x = px + (sx + 0.5) / SS - SIZE / 2
                    y = py + (sy + 0.5) / SS - SIZE / 2
                    (cr, cg, cb), ca = sample(x, y, up, color)
                    r, g, b, a = r + cr * ca, g + cg * ca, b + cb * ca, a + ca
            if a > 0:
                r, g, b = r / a, g / a, b / a
            a = a / (SS * SS)
            pixels.append((int(r + 0.5), int(g + 0.5), int(b + 0.5), int(a * 255 + 0.5)))
    return pixels


def write_tga(path, pixels, size=SIZE):
    # Sin compresión, 32 bits, origen arriba a la izquierda (descriptor 0x28)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    body = bytearray()
    for r, g, b, a in pixels:
        body += bytes((b, g, r, a))
    path.write_bytes(header + bytes(body))


def write_preview(path, images, scale=4, bg=(58, 45, 30), size=SIZE):
    """Los iconos en fila sobre el marrón de las fichas, ampliados (PNG sin dependencias)."""
    w, h = size * scale * len(images), size * scale
    rows = []
    for y in range(h):
        row = bytearray([0])
        for i, img in enumerate(images):
            for x in range(size * scale):
                r, g, b, a = img[(y // scale) * size + x // scale]
                k = a / 255
                row += bytes(int(bg[j] * (1 - k) + (r, g, b)[j] * k) for j in range(3))
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(kind, data):
        c = struct.pack(">I", len(data)) + kind + data
        return c + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def render_dot():
    """Punto redondo blanco con el borde suave (se tiñe en el juego: los puntos de la gráfica)."""
    pixels = []
    for py in range(SIZE):
        for px in range(SIZE):
            a = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    x = px + (sx + 0.5) / SS - SIZE / 2
                    y = py + (sy + 0.5) / SS - SIZE / 2
                    if x * x + y * y <= 13.5 * 13.5:
                        a += 1
            pixels.append((255, 255, 255, int(a / (SS * SS) * 255 + 0.5)))
    return pixels


def render_view(kind):
    """Iconos blancos de las vistas (se tiñen en el juego): 'grid' cuatro cuadrados,
    'list' tres líneas con su punto delante."""
    def shape(x, y):  # x, y en [0, 32)
        if kind == "grid":
            for ox in (5, 18):
                for oy in (5, 18):
                    if ox <= x < ox + 9 and oy <= y < oy + 9:
                        return True
            return False
        for oy in (6, 14, 22):
            if oy <= y < oy + 4 and (4 <= x < 8 or 11 <= x < 28):
                return True
        return False

    pixels = []
    for py in range(SIZE):
        for px in range(SIZE):
            a = 0
            for sy in range(SS):
                for sx in range(SS):
                    if shape(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS):
                        a += 1
            pixels.append((255, 255, 255, int(a / (SS * SS) * 255 + 0.5)))
    return pixels


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    write_tga(OUT / "Dot.tga", render_dot())
    write_tga(OUT / "ViewGrid.tga", render_view("grid"))
    write_tga(OUT / "ViewList.tga", render_view("list"))
    images = []
    for name, up, color in (("Up", True, "green"), ("Down", False, "red"),
                            ("Up-Grey", True, "grey"), ("Down-Grey", False, "grey")):
        img = render(up, color)
        write_tga(OUT / f"{name}.tga", img)
        images.append(img)
    print("escritas en", OUT)
    if "--preview" in sys.argv:
        folder = Path(sys.argv[sys.argv.index("--preview") + 1])
        write_preview(folder / "invest_arrows.png", images)
        print("vista previa en", folder / "invest_arrows.png")


if __name__ == "__main__":
    main()
