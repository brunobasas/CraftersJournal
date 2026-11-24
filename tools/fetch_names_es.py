"""Nombres de recetas y objetos en otros idiomas (cliente de WoW Forever).

Descarga SpellName e ItemSparse de wago.tools en cada idioma y los recorta a las
recetas y objetos que usa el addon -> tools/wago/SpellName_forever_<idioma>.csv e
ItemSparse_forever_<idioma>.csv (ID, nombre). Luego gen_names.py genera
Data/Names_<idioma>.lua.
Uso: python fetch_names_es.py [esES deDE frFR ruRU]   (por defecto, todos; solo hace
falta al cambiar de versión del cliente o al añadir un idioma)
"""
import csv
import io
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
WAGO = HERE / "wago"
BUILD = "1.60.1.70862"


LOCALES = ["esES", "deDE", "frFR", "ruRU"]


def download(table, locale):
    url = f"https://wago.tools/db2/{table}/csv?build={BUILD}&locale={locale}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    return urllib.request.urlopen(req, timeout=120).read().decode("utf-8")


def ids(name, col):
    with open(WAGO / name, encoding="utf-8") as f:
        return {r[col] for r in csv.DictReader(f)}


def main():
    spells = ids("SpellName_forever.csv", "ID")
    items = ids("ItemSparse_forever.csv", "ID")
    for locale in sys.argv[1:] or LOCALES:
        for table, keep, name_col, out in (("SpellName", spells, "Name_lang", f"SpellName_forever_{locale}.csv"),
                                           ("ItemSparse", items, "Display_lang", f"ItemSparse_forever_{locale}.csv")):
            rows = [r for r in csv.DictReader(io.StringIO(download(table, locale))) if r["ID"] in keep]
            with open(WAGO / out, "w", encoding="utf-8", newline="") as f:
                w = csv.writer(f)
                w.writerow(["ID", "Name"])
                for r in rows:
                    w.writerow([r["ID"], r[name_col]])
            print(out, len(rows), "filas")


if __name__ == "__main__":
    sys.exit(main())
