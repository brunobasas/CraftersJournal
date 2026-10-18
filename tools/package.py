"""Genera el zip para CurseForge tal como lo haría BigWigsMods/packager.

  - Solo lo que se publica: fuera tools/, docs/, dist/, .github/, *.py, *.md y los
    archivos ocultos (.git, .pkgmeta...), igual que en .pkgmeta.
  - Los bloques --@debug@ ... --@end-debug@ quedan comentados (ES.DEV_BUILD = false:
    la versión de los jugadores, sin el modo desarrollo).
  - Dentro del zip, la carpeta CraftersJournal/ (lo que se copia a Interface\\AddOns).
  - La versión sale del .toc (## Version).

Uso: python tools/package.py          -> dist/CraftersJournal-<versión>.zip
Pasa las pruebas antes (python tools/build_data.py).
"""
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NAME = "CraftersJournal"
IGNORE_DIRS = {"tools", "docs", "dist", ".github", ".git", "__pycache__"}
IGNORE_EXT = {".py", ".md", ".pyc"}


def published(path):
    rel = path.relative_to(ROOT)
    if any(part in IGNORE_DIRS or part.startswith(".") for part in rel.parts):
        return False
    return path.suffix not in IGNORE_EXT


def strip_debug(text):
    """Comenta cada línea entre --@debug@ y --@end-debug@ (como el empaquetador)."""
    out, inside = [], False
    for line in text.split("\n"):
        if line.strip() == "--@debug@":
            inside = True
            out.append(line)
        elif line.strip() == "--@end-debug@":
            inside = False
            out.append(line)
        elif inside:
            out.append("--" + line if not line.startswith("--") else line)
        else:
            out.append(line)
    if inside:
        sys.exit("Bloque --@debug@ sin cerrar")
    return "\n".join(out)


def main():
    toc = (ROOT / f"{NAME}.toc").read_text(encoding="utf-8")
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    dest = ROOT / "dist" / f"{NAME}-{version}.zip"
    dest.parent.mkdir(exist_ok=True)
    files = sorted(p for p in ROOT.rglob("*") if p.is_file() and published(p))
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            arc = f"{NAME}/{p.relative_to(ROOT).as_posix()}"
            if p.suffix in (".lua", ".toc", ".xml"):
                z.writestr(arc, strip_debug(p.read_text(encoding="utf-8")).encode("utf-8"))
            else:
                z.write(p, arc)
    # Comprobación: en el zip, el modo desarrollo tiene que estar apagado
    with zipfile.ZipFile(dest) as z:
        core = z.read(f"{NAME}/Core.lua").decode("utf-8")
        if re.search(r"^ES\.DEV_BUILD = true", core, re.M):
            sys.exit("ERROR: el zip tiene el modo desarrollo activo")
        names = z.namelist()
    print(f"{dest} ({dest.stat().st_size // 1024} KB, {len(names)} archivos, versión {version}, modo desarrollo apagado)")


if __name__ == "__main__":
    main()
