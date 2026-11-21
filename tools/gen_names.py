"""Genera Data/Names_<idioma>.lua (esES, deDE, frFR): nombres de las recetas y objetos
del addon en cada idioma.

Lee tools/wago/SpellName_forever_<idioma>.csv e ItemSparse_forever_<idioma>.csv (ver
fetch_names_es.py) y guarda solo los que cambian respecto al inglés. El addon los
usa cuando su idioma es ese y el cliente está en otro (y en inglés usa los de
ES.Data.ItemNames y el nombre de cada receta).
Cada idioma se guarda como una sola cadena (ver lua_names), no como tabla.
Uso: python gen_names.py
     python gen_names.py --selftest   (comprueba que rechaza nombres que romperían la cadena)
"""
import csv
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ADDON = HERE.parent
WAGO = HERE / "wago"
PROFS = ["Leatherworking", "Enchanting", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Cooking", "FirstAid",
         "Mining"]  # (de Minería, solo la fundición)


def read(name):
    path = WAGO / name
    if not path.exists():
        return {}
    with open(path, encoding="utf-8") as f:
        return {int(r["ID"]): r["Name"] for r in csv.DictReader(f)}


# Los nombres van en una cadena larga de Lua ([==[ ... ]==]), una línea por nombre: un
# idioma sin usar ocupa ~0,2 MB en vez de ~0,6 MB como tabla. ES.NamesFor (Core.lua)
# la convierte en tabla solo al pedir ese idioma. Dentro no se escapa nada (comillas y
# barras van tal cual), así que un nombre no puede tener saltos de línea ni el cierre
CLOSE = "]==]"


class BadName(ValueError):
    pass


def check_name(kind, ident, name):
    """Falla si `name` rompería la cadena: salto de línea o el cierre ]==]"""
    for bad, what in (("\n", "un salto de línea"), ("\r", "un retorno de carro"), (CLOSE, "el cierre " + CLOSE)):
        if bad in name:
            raise BadName(f"{'receta' if kind == 'S' else 'objeto'} {ident}: el nombre tiene {what}: {name!r}")


def lua_names(lang, spells, items):
    """La asignación de Lua con los nombres de un idioma en una cadena larga"""
    lines = []
    for kind, names in (("S", spells), ("I", items)):
        for ident, name in sorted(names.items()):
            check_name(kind, ident, name)
            lines.append(f"{kind}{ident}={name}")
    # (Lua se salta el salto de línea justo después de [==[)
    return [f"ES.Data.Names.{lang} = [==[", *lines, CLOSE]


# Idioma del cliente -> clave del addon (ES.LANGS en Locale.lua) y nombre para el comentario
LOCALES = {"esES": ("es", "español"), "deDE": ("de", "alemán"), "frFR": ("fr", "francés")}


def generate(locale, lang, label):
    """Devuelve (destino, texto, resumen) sin escribir nada, o None si faltan los datos"""
    spells_loc = read(f"SpellName_forever_{locale}.csv")
    items_loc = read(f"ItemSparse_forever_{locale}.csv")
    if not spells_loc and not items_loc:
        print(f"{locale}: sin datos (python fetch_names_es.py {locale})")
        return None
    spells, items = {}, {}
    for prof in PROFS:
        text = (ADDON / "Data" / f"{prof}.lua").read_text(encoding="utf-8")
        for sid, name in re.findall(r'^\s*\[(\d+)\] = \{ name = "((?:[^"\\]|\\.)*)"', text, re.M):
            loc = spells_loc.get(int(sid))
            if loc and loc != name:
                spells[int(sid)] = loc
        used = {int(x) for x in re.findall(r"\{ (\d+), [\d.]+ \}", text)}  # materiales y lo fabricado
        used |= {int(x) for x in re.findall(r"scroll = (\d+)", text)}
        used |= {int(x) for x in re.findall(r"ES\.Data\.ItemNames\[(\d+)\]", text)}
        en = dict((int(i), n) for i, n in re.findall(r'ES\.Data\.ItemNames\[(\d+)\] = "((?:[^"\\]|\\.)*)"', text))
        for iid in used:
            loc = items_loc.get(iid)
            if loc and loc != en.get(iid):
                items[iid] = loc
    out = [f"-- Generado por tools/gen_names.py (cliente de Forever en {locale}, wago.tools). No editar a mano.",
           "local _, ES = ...", "ES.Data = ES.Data or {}", "ES.Data.Names = ES.Data.Names or {}", "",
           f"-- Nombres en {label} (solo los que cambian respecto al inglés), una línea por nombre:",
           "-- S<receta>=nombre o I<objeto>=nombre. Es una cadena y no una tabla para que ocupe",
           f"-- poco mientras no se usa: ES.NamesFor(\"{lang}\") la convierte en tabla al pedirla",
           *lua_names(lang, spells, items), ""]
    dest = ADDON / "Data" / f"Names_{locale}.lua"
    return dest, "\n".join(out), f"{len(spells)} recetas y {len(items)} objetos en {label}"


def selftest():
    """Comprueba que un nombre que rompería la cadena hace fallar al generador"""
    for bad in ("Dos\nlíneas", "Con\rretorno", "Cierra ]==] aquí"):
        try:
            lua_names("xx", {123: bad}, {})
        except BadName as e:
            print("bien, rechazado:", e)
        else:
            raise SystemExit(f"no rechazó {bad!r}")
    lines = lua_names("xx", {1: 'Caja "Bum" = 2\\3'}, {})
    assert lines[1] == 'S1=Caja "Bum" = 2\\3', lines
    print("selftest: bien")


def main():
    # Todos en memoria primero: si un nombre no vale, no se escribe ninguno
    results = []
    for locale, (lang, label) in LOCALES.items():
        try:
            r = generate(locale, lang, label)
        except BadName as e:
            raise SystemExit(f"{locale}: {e}. No se ha escrito ningún archivo.")
        if r:
            results.append(r)
    for dest, text, summary in results:
        dest.write_text(text, encoding="utf-8")
        print(f"{dest}: {summary}, {dest.stat().st_size // 1024} KB")


if __name__ == "__main__":
    import sys
    selftest() if "--selftest" in sys.argv else main()
