"""Lanza todas las pruebas de Crafter's Journal y dice sí o no.

    python tools/run_tests.py                    todas (las categorías y tools/test_ui.py)
    python tools/run_tests.py --only route earn  solo esas categorías
    python tools/run_tests.py --update-snapshots acepta las instantáneas que han cambiado
    python tools/run_tests.py -v                 con los detalles de cada prueba
    python tools/run_tests.py --list             las categorías y sus pruebas

Termina con 0 si todo pasa y con 1 si falla algo. Cada categoría es un archivo de
tools/tests/categories/ y cada prueba corre con el addon recién cargado (un Lua nuevo
por prueba). Ver docs/TESTS.md.
"""
import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ADDON = TOOLS.parent
TESTS = TOOLS / "tests"
CATEGORIES = TESTS / "categories"
SNAPSHOTS = TESTS / "snapshots"

# Categorías obligatorias (test-coverage: cada una tiene al menos una prueba)
REQUIRED = {
    "boot": "Arranque y eventos",
    "data": "Datos generados",
    "locales": "Idiomas",
    "route": "Subir profesiones (ruta)",
    "shopping": "Lista de compra",
    "earn": "Ganar dinero",
    "calculator": "Calculadora",
    "inventory": "Inventario",
    "favor": "Merchant's Favor",
    "collection": "Colección de recetas",
    "invest": "Inversiones",
    "assistant": "Asistente",
    "auction": "Casa de Subastas",
    "vendors": "Vendedores e instructores",
    "options": "Opciones",
    "whatsnew": "Novedades",
}
TEST_UI = "test_ui"
MARK = "@@CJ "

# Globales que el addon escribe a propósito
ALLOWED_GLOBALS = [
    "CraftersJournalDB", "SLASH_CRAFTERSJOURNAL1", "SLASH_CRAFTERSJOURNAL2", "SLASH_CRAFTERSJOURNAL3",
    "CraftersJournal_OnAddonCompartmentClick", "CraftersJournal", "CraftersJournalMainFrame",
    "CraftersJournalAHButton", "CraftersJournalMinimapButton", "CraftersJournalRowMarkButton",
    "LibStub",  # (global a propósito: así comparten librerías los addons)
]


def utf8_stdout():
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass


# --------------------------------------------------------------------------
# Trabajador: una categoría, un Lua nuevo por prueba
# --------------------------------------------------------------------------

def toc_files():
    toc = (ADDON / "CraftersJournal.toc").read_text(encoding="utf-8")
    return [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]


def read(path):
    return Path(path).read_text(encoding="utf-8-sig")  # (sin la marca BOM: Lua no la entiende)


class Runtime:
    """El addon cargado en un Lua 5.1 nuevo, con la simulación, el marco y una categoría."""

    def __init__(self, category_src, category_name):
        _eslua = os.environ.get("ESLUA")
        if _eslua and os.path.isdir(_eslua):
            sys.path.insert(0, _eslua)
        from lupa import lua51
        self.lua = lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        run = lua.eval("function(src, name) return assert(loadstring(src, name))() end")
        run(read(TESTS / "wow.lua"), "=tests/wow.lua")
        # Globales escritas desde los archivos del addon (las pruebas no cuentan: su
        # nombre de trozo empieza por "=")
        lua.globals().ALLOWED_LIST = lua.table_from(ALLOWED_GLOBALS)
        run(r"""
LEAKS = {}
local ALLOWED = {}
for _, k in ipairs(ALLOWED_LIST) do ALLOWED[k] = true end
setmetatable(_G, { __newindex = function(t, k, v)
  local info = debug.getinfo(2, "S")
  -- (como test_ui.py: los archivos del addon; las librerías de Libs\ llevan "-" y "."
  -- en el nombre y escriben sus globales a propósito)
  if info and info.source:match("^@[%w\\/]+%.lua$") and not ALLOWED[k] then
    LEAKS[#LEAKS + 1] = info.source:sub(2) .. ": " .. tostring(k)
  end
  rawset(t, k, v)
end })
""", "=tests/leaks")
        ES = lua.eval("{}")
        loader = lua.eval("function(src, name, ES) assert(loadstring(src, '@' .. name))('CraftersJournal', ES) end")
        for f in toc_files():
            loader(read(ADDON / f.replace("\\", "/")), f, ES)
        lua.globals().ES = ES
        # (para las pruebas que leen los archivos del addon: textos sin traducir...)
        lua.globals().ADDON_DIR = str(ADDON)
        lua.globals().TOC_FILES = lua.table_from(toc_files())
        run(read(TESTS / "framework.lua"), "=tests/framework.lua")
        run(read(TESTS / "fixtures.lua"), "=tests/fixtures.lua")
        run(category_src, "=tests/categories/" + category_name + ".lua")
        lua.execute(RUN_ONE)

    def count(self):
        return int(self.lua.eval("#TESTS"))

    def names(self):
        t = self.lua.eval("TESTS")
        return [t[i].name for i in range(1, self.count() + 1)]

    def run(self, i):
        return to_py(self.lua.eval("RunOne")(i))


# Ejecuta la prueba i y devuelve lo que pasó (en Lua: los errores con su traza)
RUN_ONE = r"""
local function Trim(tb)
  local keep = {}
  for line in tostring(tb):gmatch("[^\n]+") do
    -- solo las líneas del addon y de las pruebas (sin la maquinaria de xpcall)
    if (line:find("%.lua:%d+") or line:find("tests/")) and not line:find("tests/framework.lua") then
      keep[#keep + 1] = line:gsub("^%s+", "")
      if #keep >= 6 then break end
    end
  end
  return table.concat(keep, "\n    ")
end

function RunOne(i)
  local t = TESTS[i]
  local res = { name = t.name, known = t.opts.known }
  local trace
  local ok, err = xpcall(function()
    if t.opts.boot ~= false then Boot(t.opts.state or "scan") end
    t.fn()
    RunTimers()
  end, function(e) trace = Trim(debug.traceback("", 2)) return e end)
  local problems = {}
  if not ok then problems[#problems + 1] = tostring(err) .. (trace ~= "" and ("\n    " .. trace) or "") end
  if #RECORDED_ERRORS > 0 then
    problems[#problems + 1] = "el addon apuntó errores (ES:RecordError): " .. table.concat(RECORDED_ERRORS, " | ")
  end
  if #LEAKS > 0 then
    problems[#problems + 1] = "variables globales escritas sin querer: " .. table.concat(LEAKS, ", ")
  end
  local unknown = {}
  for k in pairs(MOCK_METHODS) do if not WIDGET_API[k] then unknown[#unknown + 1] = k end end
  table.sort(unknown)
  if #unknown > 0 then
    problems[#problems + 1] = "métodos de marco que no están en la API del juego (tests/wow.lua, WIDGET_API): " .. table.concat(unknown, ", ")
  end
  res.ok = #problems == 0
  res.error = table.concat(problems, "\n  ")
  res.notes = NOTES
  res.snapshots = SNAPSHOTS
  return res
end
"""


def to_py(v):
    """Tabla de Lua -> dict/list de Python (las listas 1..n, como listas)."""
    from lupa import lua51
    if lua51.lua_type(v) == "table":
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [to_py(v[k]) for k in range(1, len(keys) + 1)]
        if not keys:
            return {}
        return {str(k): to_py(v[k]) for k in keys}
    if isinstance(v, float) and v.is_integer():
        return int(v)
    return v


def snapshot_diff(old, new, path=""):
    """Las diferencias entre dos instantáneas, legibles (como mucho 8)."""
    out = []
    if isinstance(old, dict) and isinstance(new, dict):
        for k in sorted(set(old) | set(new)):
            if k not in old:
                out.append(f"{path}{k}: nuevo = {json.dumps(new[k], ensure_ascii=False)[:120]}")
            elif k not in new:
                out.append(f"{path}{k}: ya no está (era {json.dumps(old[k], ensure_ascii=False)[:120]})")
            else:
                out += snapshot_diff(old[k], new[k], f"{path}{k}.")
    elif isinstance(old, list) and isinstance(new, list):
        if len(old) != len(new):
            out.append(f"{path[:-1] or 'valor'}: {len(old)} elementos antes, {len(new)} ahora")
        for i, (a, b) in enumerate(zip(old, new)):
            if a != b:
                out += snapshot_diff(a, b, f"{path}{i + 1}.")
                break  # (el primero distinto basta: los siguientes suelen moverse con él)
    elif old != new:
        out.append(f"{path[:-1] or 'valor'}: antes {json.dumps(old, ensure_ascii=False)}, ahora {json.dumps(new, ensure_ascii=False)}")
    return out[:8]


def list_category(category):
    """Los nombres de las pruebas de una categoría, o el error que impide cargarla."""
    src_path = CATEGORIES / f"{category}.lua"
    if not src_path.exists():
        return None, f"falta el archivo {src_path.relative_to(ADDON)}"
    try:
        names = Runtime(read(src_path), category).names()
    except Exception as e:  # el addon o la categoría no cargan
        return None, "no carga el addon o la categoría: " + str(e)
    if not names:
        return None, "la categoría no tiene ninguna prueba"
    return names, None


def run_one(category, i, name):
    """Una prueba, en un Lua nuevo (se ejecuta en un proceso del grupo)."""
    utf8_stdout()
    t0 = time.perf_counter()
    try:
        res = Runtime(read(CATEGORIES / f"{category}.lua"), category).run(i)
    except Exception as e:
        res = {"name": name, "ok": False, "error": str(e)}
    res["secs"] = round(time.perf_counter() - t0, 2)
    return res


def apply_snapshots(category, results, update):
    """Compara (o con update, guarda) las instantáneas que dieron las pruebas."""
    snap_file = SNAPSHOTS / f"{category}.json"
    stored = json.loads(read(snap_file)) if snap_file.exists() else {}
    changed = False
    for res in results:
        if not res.get("error"):
            res["error"] = ""
        for snap in res.pop("snapshots", None) or []:
            key, value = snap["key"], snap.get("value")
            if snap.get("kind") == "budget":
                base = stored.get(key)
                if update:
                    if base != value:
                        stored[key], changed = value, True
                    continue
                if not isinstance(base, (int, float)):
                    res["ok"] = False
                    res["error"] = (res["error"] + "\n  " if res["error"] else "") + \
                        f"presupuesto nuevo «{key}»: guarda la referencia con --update-snapshots"
                    continue
                tol, slack = snap.get("tolerance", 0.2), snap.get("slack", 0)
                limit = base * (1 + tol) + slack
                pct = (value / base - 1) * 100 if base else 0
                res.setdefault("notes", [])
                if isinstance(res["notes"], dict):
                    res["notes"] = list(res["notes"].values())
                if value > limit:
                    res["ok"] = False
                    res["error"] = (res["error"] + "\n  " if res["error"] else "") + \
                        f"«{key}» se pasa del presupuesto: {value:.4g} (referencia {base:.4g}, límite {limit:.4g}, {pct:+.0f}%)" + \
                        f"\n    (si es a propósito: python tools/run_tests.py --only {category} --update-snapshots)"
                else:
                    res["notes"].append(f"{key}: {value:.4g} (referencia {base:.4g}, {pct:+.0f}%)")
                continue
            if update:
                if stored.get(key) != value:
                    stored[key], changed = value, True
            elif key not in stored:
                res["ok"] = False
                res["error"] = (res["error"] + "\n  " if res["error"] else "") + f"instantánea nueva «{key}»: acéptala con --update-snapshots"
            elif stored[key] != value:
                res["ok"] = False
                res["error"] = (res["error"] + "\n  " if res["error"] else "") + f"la instantánea «{key}» ha cambiado:\n    " + \
                    "\n    ".join(snapshot_diff(stored[key], value)) + \
                    f"\n    (si el cambio es a propósito: python tools/run_tests.py --only {category} --update-snapshots)"
    if update and changed:
        SNAPSHOTS.mkdir(parents=True, exist_ok=True)
        snap_file.write_text(json.dumps(stored, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        results.append({"name": "(instantáneas)", "ok": True, "info": True,
                        "notes": [f"guardadas en {snap_file.relative_to(ADDON)}"]})


# --------------------------------------------------------------------------
# Lanzador
# --------------------------------------------------------------------------

def env_utf8():
    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    return env


def run_test_ui():
    t0 = time.perf_counter()
    p = subprocess.run([sys.executable, str(TOOLS / "test_ui.py")], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env=env_utf8(), cwd=ADDON)
    results = []
    last_fail = None
    for line in p.stdout.splitlines():
        if line.startswith("OK   "):
            results.append({"name": line[5:].strip(), "ok": True})
            last_fail = None
        elif line.startswith("FAIL "):
            name, _, err = line[5:].partition(": ")
            last_fail = {"name": name.strip().rstrip(":"), "ok": False, "error": err}
            results.append(last_fail)
        elif last_fail is not None and line.startswith("  "):
            # (el detalle de un FAIL en las líneas siguientes, sangradas)
            last_fail["error"] = (last_fail["error"] + "\n  " if last_fail["error"] else "") + line.strip()
        else:
            last_fail = None
    if p.returncode != 0 and not any(not r["ok"] for r in results):
        results.append({"name": "(test_ui.py)", "ok": False,
                        "error": f"terminó con código {p.returncode}\n  " + "\n  ".join(p.stderr.strip().splitlines()[-8:])})
    if not results:
        results.append({"name": "(test_ui.py)", "ok": False, "error": "no dio ningún resultado"})
    return TEST_UI, results, time.perf_counter() - t0


def main():
    utf8_stdout()
    ap = argparse.ArgumentParser(description="Pruebas de Crafter's Journal")
    ap.add_argument("--only", nargs="+", metavar="CATEGORÍA", help="solo estas categorías (test_ui incluida)")
    ap.add_argument("--update-snapshots", action="store_true", help="acepta las instantáneas que han cambiado")
    ap.add_argument("-v", "--verbose", action="store_true", help="detalles de cada prueba")
    ap.add_argument("--list", action="store_true", help="lista las categorías y sus pruebas")
    ap.add_argument("-j", "--jobs", type=int, default=max(2, (os.cpu_count() or 2) - 2), help="pruebas a la vez")
    args = ap.parse_args()

    found = sorted(p.stem for p in CATEGORIES.glob("*.lua")) if CATEGORIES.exists() else []
    all_cats = list(REQUIRED) + [c for c in found if c not in REQUIRED]
    cats = all_cats + [TEST_UI]
    if args.only:
        unknown = [c for c in args.only if c not in cats]
        if unknown:
            print("Categorías que no existen: " + ", ".join(unknown) + "\nHay: " + ", ".join(cats))
            return 2
        cats = [c for c in cats if c in args.only]

    if args.list:
        for c in cats:
            if c == TEST_UI:
                print(f"{c}: tools/test_ui.py (sus pasos)")
                continue
            path = CATEGORIES / f"{c}.lua"
            try:
                names = Runtime(read(path), c).names() if path.exists() else ["(falta el archivo)"]
            except Exception as e:
                names = [f"(no carga: {e})"]
            print(f"{c} — {REQUIRED.get(c, '')}")
            for n in names:
                print(f"    {n}")
        return 0

    t0 = time.perf_counter()
    done = {}
    lua_cats = [c for c in cats if c != TEST_UI]
    # test_ui.py en su propio proceso (en un hilo, a la vez que el resto); las pruebas de
    # las categorías, cada una por separado, repartidas entre procesos
    with ThreadPoolExecutor(max_workers=1) as side, ProcessPoolExecutor(max_workers=args.jobs) as pool:
        ui_future = side.submit(run_test_ui) if TEST_UI in cats else None
        listed = {c: pool.submit(list_category, c) for c in lua_cats}
        tasks = {}
        for c in lua_cats:
            names, err = listed[c].result()
            if err:
                done[c] = ([{"name": "(categoría)", "ok": False, "error": err}], 0.0)
                continue
            tasks[c] = [pool.submit(run_one, c, i, n) for i, n in enumerate(names, 1)]
        for c, futures in tasks.items():
            results = []
            for f, name in zip(futures, listed[c].result()[0]):
                try:
                    results.append(f.result())
                except Exception as e:  # el proceso se cayó
                    results.append({"name": name, "ok": False, "error": f"el proceso de la prueba se cayó: {e}"})
            apply_snapshots(c, results, args.update_snapshots)
            done[c] = (results, sum(r.get("secs", 0) for r in results))
        if ui_future:
            c, results, secs = ui_future.result()
            done[c] = (results, secs)

    totals = {"ok": 0, "fail": 0, "known": 0, "fixed": 0}
    failures, knowns, fixed = [], [], []
    rows = []
    for c in cats:
        results, secs = done[c]
        n = {"ok": 0, "fail": 0, "known": 0, "fixed": 0}
        print(f"\n== {c}" + (f" · {REQUIRED[c]}" if c in REQUIRED else "") + f" ({secs:.1f} s)")
        for r in results:
            if r.get("info"):
                for note in r.get("notes") or []:
                    print(f"   · {note}")
                continue
            known = r.get("known")
            if r["ok"] and known:
                n["fixed"] += 1
                fixed.append((c, r))
                tag = "YA PASA"
            elif r["ok"]:
                n["ok"] += 1
                tag = "OK"
            elif known:
                n["known"] += 1
                knowns.append((c, r))
                tag = "CONOCIDO"
            else:
                n["fail"] += 1
                failures.append((c, r))
                tag = "FAIL"
            if tag != "OK" or args.verbose:
                print(f"   {tag:8} {r['name']}" + (f"  ({r['secs']} s)" if args.verbose and 'secs' in r else ""))
                if tag == "FAIL" or (tag == "CONOCIDO" and args.verbose):
                    print("     " + (r.get("error") or "").replace("\n", "\n     "))
                if tag in ("CONOCIDO", "YA PASA"):
                    print(f"     motivo: {known}")
                if args.verbose or tag == "FAIL":
                    for note in r.get("notes") or []:
                        print(f"     · {note}")
        if not args.verbose:
            print(f"   {n['ok']} OK" + (f", {n['fail']} FAIL" if n['fail'] else "") +
                  (f", {n['known']} conocidos" if n['known'] else "") + (f", {n['fixed']} ya pasan" if n['fixed'] else ""))
        for k in totals:
            totals[k] += n[k]
        rows.append((c, n))

    secs = time.perf_counter() - t0
    print("\n" + "=" * 70)
    print("RESUMEN")
    for c, n in rows:
        print(f"  {c:12} {n['ok']:4} OK  {n['fail']:3} FAIL  {n['known']:3} conocidos")
    if knowns:
        print("\nFallos conocidos (no hacen fallar):")
        for c, r in knowns:
            print(f"  {c}: {r['name']} — {r['known']}")
    if fixed:
        print("\nMarcados como fallo conocido que YA PASAN (quita la marca «known»):")
        for c, r in fixed:
            print(f"  {c}: {r['name']}")
    if failures:
        print("\nFALLAN:")
        for c, r in failures:
            print(f"  {c}: {r['name']}")
    verdict = "TODO EN VERDE" if not failures else f"{totals['fail']} PRUEBAS FALLAN"
    print(f"\n{verdict}: {totals['ok']} OK, {totals['fail']} FAIL, {totals['known']} conocidos · {secs:.0f} s")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
