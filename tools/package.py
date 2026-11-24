"""Genera el zip para CurseForge tal como lo haría BigWigsMods/packager.

  - Solo lo que se publica: fuera tools/, docs/, dist/, .github/, *.py, *.md y los
    archivos ocultos (.git, .pkgmeta...), igual que en .pkgmeta.
  - Dentro del zip, la carpeta CraftersJournal/ (lo que se copia a Interface\\AddOns).
  - La versión: en el .toc del repositorio va @project-version@ (el empaquetador de
    CurseForge pone la de la etiqueta). Aquí se pone la del argumento o, sin él, la de
    la última etiqueta v* de git (sin la v). Sin versión, no se empaqueta.
  - Las herramientas del desarrollador (DevTools.lua) no van: ni el archivo ni su
    línea del .toc (#@do-not-package@).

Uso: python tools/package.py [versión]   -> dist/CraftersJournal-<versión>.zip
     (por ejemplo python tools/package.py 0.64.0; sin versión hace falta git en el PATH)
Pasa las pruebas antes (python tools/build_data.py).
"""
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NAME = "CraftersJournal"
IGNORE_DIRS = {"tools", "docs", "dist", ".github", ".git", "__pycache__", "openspec"}
IGNORE_EXT = {".py", ".md", ".pyc"}
# Herramientas del desarrollador, los bancos del asistente (apagados) y BulkMoney, que
# aún no se publican (como en .pkgmeta). El asistente de ruta sí (beta)
BULK_FILES = {"BulkMoneyUI.lua", "BulkPostUI.lua"}
IGNORE_FILES = {"DevTools.lua", "Data/Bankers.lua"} | BULK_FILES
IGNORE_PREFIXES = ()
# Como BigWigsMods/packager: en el .toc se quita lo que va entre estas dos líneas
DO_NOT_PACKAGE = re.compile(r"^#@do-not-package@\s*$.*?^#@end-do-not-package@\s*$\n?", re.M | re.S)


def published(path):
    rel = path.relative_to(ROOT)
    if any(part in IGNORE_DIRS or part.startswith(".") for part in rel.parts):
        return False
    if rel.as_posix() in IGNORE_FILES or rel.as_posix().startswith(IGNORE_PREFIXES):
        return False
    return path.suffix not in IGNORE_EXT


VERSION_RE = re.compile(r"^\d+(\.\d+)+$")
VERSION_LINE = re.compile(r"^## Version:.*$", re.M)


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)


def version_from_git():
    """La última etiqueta v* (sin la v), o None si no hay git o etiquetas."""
    try:
        last = git("describe", "--tags", "--abbrev=0", "--match", "v*")
    except OSError:
        return None
    if last.returncode != 0:
        return None
    tag = last.stdout.strip()
    if git("describe", "--tags", "--exact-match", "--match", "v*").returncode != 0:
        print(f"Aviso: HEAD no está en una etiqueta; se usa la última, {tag}")
    return tag[1:]


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else version_from_git()
    if version and version.startswith("v"):
        version = version[1:]
    if not version or not VERSION_RE.match(version):
        sys.exit(f"Sin versión válida ({version!r}): pásala, por ejemplo python tools/package.py 0.64.0")
    toc = (ROOT / f"{NAME}.toc").read_text(encoding="utf-8")
    assert VERSION_LINE.search(toc), "el .toc no tiene línea ## Version"
    dest = ROOT / "dist" / f"{NAME}-{version}.zip"
    dest.parent.mkdir(exist_ok=True)
    files = sorted(p for p in ROOT.rglob("*") if p.is_file() and published(p))
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            arc = f"{NAME}/{p.relative_to(ROOT).as_posix()}"
            if p.suffix == ".toc":
                text = DO_NOT_PACKAGE.sub("", p.read_text(encoding="utf-8"))
                z.writestr(arc, VERSION_LINE.sub(f"## Version: {version}", text, count=1))
            else:
                z.write(p, arc)
        names = z.namelist()
    # Nada del desarrollador en lo que se publica
    with zipfile.ZipFile(dest) as z:
        toc_out = z.read(f"{NAME}/{NAME}.toc").decode("utf-8")
        assert "@project-" not in toc_out and re.search(rf"^## Version: {re.escape(version)}\s*$", toc_out, re.M), \
            "la versión del .toc del zip no se ha sustituido"
        assert "DevTools" not in toc_out and f"{NAME}/DevTools.lua" not in z.namelist(), \
            "DevTools.lua se ha colado en el zip"
        assert "Bankers" not in toc_out and not any("Bankers" in n for n in z.namelist()), \
            "los bancos del asistente (aún sin publicar) se han colado en el zip"
        for bulk in BULK_FILES:
            assert bulk not in toc_out and f"{NAME}/{bulk}" not in z.namelist(), \
                f"{bulk} (BulkMoney, aún sin publicar) se ha colado en el zip"
        # El asistente sí va: su archivo, su línea del .toc, los buzones y sus iconos
        for need in ("Assistant.lua", "Data/Mailboxes.lua", "Media/Assistant/HelpBig.tga"):
            assert f"{NAME}/{need}" in z.namelist(), f"falta {need} en el zip"
        assert "Assistant.lua" in toc_out and "Mailboxes.lua" in toc_out, "falta el asistente en el .toc del zip"
    print(f"{dest} ({dest.stat().st_size // 1024} KB, {len(names)} archivos, versión {version})")


if __name__ == "__main__":
    main()
