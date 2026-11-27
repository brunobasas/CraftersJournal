"""Genera Data/Sources.lua para Crafter's Journal desde QuestieDB (Forever).

De dónde sale cada receta de pergamino (vendedores y misiones), quién vende los
materiales de vendedor y los libros de rango, y dónde está cada PNJ (vendedores,
quien da las misiones e instructores). Así el addon no necesita Questie para
"Conseguir receta" ni para marcar el camino.

QuestieDB guarda sus datos "baked" en su .toc (Base64 + CBOR; los IDs con zlib).
Uso:  python gen_sources.py
"""
import csv
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from questie import (ITEM, NPC, NPC_AUCTIONEER, NPC_INNKEEPER, QUEST, all_ids, at, field, ids,  # noqa: E402
                     load_store, row, seq, zone_tables)

HERE = Path(__file__).resolve().parent
ADDON = HERE.parent
# Datos de Forever que no van en el repositorio: su carpeta, junto al repositorio o en CJ_PRIVATE_DATA
PRIVATE = Path(os.environ.get("CJ_PRIVATE_DATA") or (ADDON.parent / "CraftersJournal-private"))
PROFS = ["Leatherworking", "Enchanting", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Cooking", "FirstAid"]
RANK_BOOKS = [16072, 16084]  # Expert Cookbook, Expert First Aid - Under Wraps

WORLD_DROP = 12  # más criaturas que esto: botín del mundo (solo se guarda cuántas)
ALLIANCE_RACES, HORDE_RACES = 77, 178
# Capitales por área: un PNJ amistoso con los dos bandos dentro de una solo atiende a ese bando
CAPITALS = {1519: "A", 1537: "A", 1657: "A", 1637: "H", 1497: "H", 1638: "H"}


def main():
    print("Leyendo QuestieDB ...", file=sys.stderr)
    load_store()
    zt = zone_tables()
    area, area_o = zt.get("areaIdToUiMapId", {}), zt.get("areaIdToUiMapIdOverride", {})
    parent, parent_o = zt.get("subZoneToParentZone", {}), zt.get("subZoneToParentZoneOverride", {})

    def ui_map(a):
        m = area_o.get(a) or area.get(a)
        if not m:
            p = parent_o.get(a) or parent.get(a)
            m = p and (area_o.get(p) or area.get(p))
        return m or None

    # Objetos: pergaminos de nuestras recetas, libros de rango y materiales de vendedor
    scrolls, vendor_items, trainers = set(), set(), set()
    for prof in PROFS:
        text = (ADDON / "Data" / f"{prof}.lua").read_text(encoding="utf-8")
        scrolls.update(int(x) for x in re.findall(r"scroll = (\d+)", text))
        vendor_items.update(int(x) for x in re.findall(r"ES\.Data\.VendorPrices\[(\d+)\]", text))
        tm = re.search(r"trainers = \{(.*)\},", text)
        if tm:
            trainers.update(int(a) for a, _ in re.findall(r"\{ (\d+), (\d+) \}", tm.group(1)))
        # Otros PNJ a los que hay que ir (extraNPCs en los datos de la profesión)
        em = re.search(r"extraNPCs = \{([^}]*)\}", text)
        if em:
            trainers.update(int(a) for a in re.findall(r"\d+", em.group(1)))

    def levels(npc_id):
        """(mínimo, máximo) de nivel de una criatura, o None"""
        r = row("Npc", npc_id)
        lo, hi = r and field("Npc", npc_id, NPC["minLevel"], r), r and field("Npc", npc_id, NPC["maxLevel"], r)
        return (int(lo), int(hi or lo)) if isinstance(lo, (int, float)) and lo > 0 else None

    # Nombres de objeto de Forever (para leer cuántos pide una misión en su texto)
    item_names = {}
    with open(HERE / "wago" / "ItemSparse_forever.csv", encoding="utf-8") as f:
        rd = csv.reader(f)
        next(rd)
        for r in rd:
            item_names[int(r[0])] = r[1]

    def item_objectives(q, qr):
        obj = field("Quest", q, QUEST["objectives"], qr) or {}
        item_obj = obj.get(3) if isinstance(obj, dict) else (obj[2] if len(obj) > 2 else None)
        return [o for o in (item_obj or []) if o]

    def objectives_text(q, qr):
        text = field("Quest", q, QUEST["objectivesText"], qr) or []
        text = " ".join(t.decode("utf-8", "replace") if isinstance(t, bytes) else str(t) for t in text)
        return " ".join(text.split())

    # Lo que pide entregar una misión: su texto de objetivos ("Bring 2 Turtle Scale
    # Helms...") si pide objetos, o None. Se enseña tal cual en el tooltip
    def quest_asks(q, qr):
        if not item_objectives(q, qr):
            return None
        return objectives_text(q, qr) or None

    # Los objetos que pide, con cuántos: [id, n, id, n...] (n = 0: no se sabe cuántos).
    # QuestieDB dice qué objetos pero no cuántos; la cantidad sale del texto ("Bring 2
    # Turtle Scale Helms ... and a Wildvine"). Con ellos la ruta le pone precio a la
    # receta de misión (Discord: las de Wild Leather salían gratis y la cadena de Wild
    # Leather Leggings pedía objetos por casi 20 de oro)
    NUM_WORDS = {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                 "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
                 "thirty": 30, "forty": 40, "fifty": 50}
    COUNT = r"\b(\d+|" + "|".join(NUM_WORDS) + r")\s+(?:(?:pieces?|vials?|helpings?|mugs?|bundles?|bags?)\s+of\s+)?"

    def name_pattern(name):
        """El nombre del objeto tal como puede salir en el texto: en plural ("Star Rubies",
        "Bolts of Runecloth": se pluraliza la palabra antes de "of") y con las palabras
        juntas o separadas ("Bronze Battleaxes" es el objeto Bronze Battle Axe)"""
        words = name.split()
        head = words.index("of") - 1 if "of" in words[1:] else len(words) - 1
        parts = []
        for i, w in enumerate(words):
            p = re.escape(w)
            if i == head:
                p = re.escape(w[:-1]) + r"(?:y|ies)" if w.endswith("y") else p + r"(?:e?s)?"
            parts.append(p)
        return r"\s*".join(parts) + r"\b"

    # Cuántos se piden cuando el texto no lo dice (o dice otra cosa). Sacado de Wowhead
    # Forever, la página de cada misión (comprobado 2026-11-26: las demás cantidades que
    # salen del texto coinciden con Wowhead)
    THORIUM_BAR = 12359
    QUEST_COUNTS = {
        484: {3397: 6},  # Young Crocolisk Skins: el texto dice 4, Forever pide 6
        7604: {17203: 1},  # A Binding Contract: con el contrato se entrega un Sulfuron Ingot
        # Imperial Plate (Derotain Mudsipper): no tienen texto de objetivos
        7653: {THORIUM_BAR: 20}, 7654: {THORIUM_BAR: 40}, 7655: {THORIUM_BAR: 20}, 7656: {THORIUM_BAR: 60},
        7657: {THORIUM_BAR: 50}, 7658: {THORIUM_BAR: 60}, 7659: {THORIUM_BAR: 20},
    }

    def quest_items(q, qr):
        objs = item_objectives(q, qr)
        if not objs:
            return None
        text = objectives_text(q, qr)
        out = []
        for o in objs:
            item_id = int(seq(o)[0]) if not isinstance(o, int) else o
            # (los objetos de misión no están en ItemSparse: el nombre de QuestieDB)
            ir = row("Item", item_id)
            name, n = item_names.get(item_id) or (ir and field("Item", item_id, ITEM["name"], ir)), 0
            pat = name and name_pattern(name)
            m = pat and re.search(COUNT + pat, text, re.I)
            if m:
                c = m.group(1).lower()
                n = int(c) if c.isdigit() else NUM_WORDS[c]
            elif pat and re.search(r"\b" + pat, text, re.I):
                n = 1  # nombrado sin cantidad ("Find Frost Oil", "some Soothing Spices"): uno
            n = QUEST_COUNTS.get(q, {}).get(item_id, n)
            out += [item_id, n]
        return out

    # Misiones que hay que hacer antes (toda la cadena, no solo la anterior)
    def quest_chain(q, seen=None):
        seen = set() if seen is None else seen
        qr = row("Quest", q)
        if not qr:
            return seen
        def flat(t):  # (a veces viene anidado: [[36]])
            if isinstance(t, int):
                return [t]
            return [x for v in (t if isinstance(t, list) else seq(t)) for x in flat(v)] if t else []
        pre = flat(field("Quest", q, QUEST["preQuestGroup"], qr)) + flat(field("Quest", q, QUEST["preQuestSingle"], qr))
        for p in pre:
            if p not in seen:
                seen.add(p)
                quest_chain(p, seen)
        return seen

    items, quests, npcs_needed = {}, {}, set(trainers)

    # Una misión que da un pergamino (reward) y, para ponerle precio, las de su cadena que
    # piden objetos (sin reward: no se va a quien las da, solo se miran sus objetos)
    def add_quest(q, reward):
        if q in quests:
            return
        qr = row("Quest", q)
        if not qr:
            return
        races = field("Quest", q, QUEST["requiredRaces"], qr) or 0
        a, h = (races & ALLIANCE_RACES) != 0, (races & HORDE_RACES) != 0
        starters = ids(at(field("Quest", q, QUEST["startedBy"], qr), 1))
        chain = sorted(quest_chain(q))
        quests[q] = (field("Quest", q, QUEST["name"], qr), "" if a == h else ("A" if a else "H"),
                     field("Quest", q, QUEST["requiredLevel"], qr) or 0, starters,
                     quest_asks(q, qr), len(chain), quest_items(q, qr), chain)
        if reward:
            npcs_needed.update(starters)
            for p in chain:
                pr = row("Quest", p)
                if pr and item_objectives(p, pr):
                    add_quest(p, False)
    drops = {}  # pergamino -> (criaturas o None si es del mundo, cuántas criaturas, cuántos objetos, niveles)
    droppers = set()  # criaturas de las que se guarda el nivel
    for item_id in sorted(scrolls | vendor_items | set(RANK_BOOKS)):
        r = row("Item", item_id)
        if not r:
            continue
        vendors = ids(field("Item", item_id, ITEM["vendors"], r))
        qs = ids(field("Item", item_id, ITEM["questRewards"], r)) if item_id not in vendor_items else []
        if item_id in scrolls:
            mobs = ids(field("Item", item_id, ITEM["npcDrops"], r))
            objs = ids(field("Item", item_id, ITEM["objectDrops"], r))
            if mobs or objs:
                listed = mobs if len(mobs) <= WORLD_DROP else None
                # Botín del mundo: de qué nivel a qué nivel son las criaturas que lo sueltan
                lv = [l for l in (levels(m) for m in mobs) if l] if not listed else []
                span = (min(l[0] for l in lv), max(l[1] for l in lv)) if lv else None
                drops[item_id] = (listed, len(mobs), len(objs), span)
                npcs_needed.update(listed or [])
                droppers.update(listed or [])
        if vendors or qs or item_id in drops:
            items[item_id] = (vendors, qs)
            npcs_needed.update(vendors)
        for q in qs:
            add_quest(q, True)

    # Vendedores de pergaminos de Forever (PRIVATE/forever_*.csv): se suman a los de
    # QuestieDB, solo los que tienen sitio en el mapa. Un pergamino que en Forever no vende
    # nadie (patrones de Spitfire, Ironvine...: no existen en Forever) se queda sin vendedor
    fv_npcs, fv_vendors, limited = {}, {}, set()
    if (PRIVATE / "forever_scroll_vendors.csv").exists():
        with open(PRIVATE / "forever_npcs.csv", encoding="utf-8") as f:
            for r in csv.DictReader(l for l in f if not l.startswith("#")):
                fv_npcs[int(r["npc"])] = (r["name"], int(r["map"]), float(r["x"]), float(r["y"]))
        with open(PRIVATE / "forever_scroll_vendors.csv", encoding="utf-8") as f:
            for r in csv.DictReader(l for l in f if not l.startswith("#")):
                if int(r["npc"]) in fv_npcs:
                    fv_vendors.setdefault(int(r["item"]), set()).add(int(r["npc"]))
                    # "Limited (N)": vende N y se repone con el tiempo ("Unlimited": siempre hay)
                    if r["stock"].strip().startswith("Limited"):
                        limited.add((int(r["item"]), int(r["npc"])))
        # Correcciones comprobadas en el juego.
        # Raptor Hide Harness / Raptor Hide Belt: los datos los tienen al revés.
        # En el juego Tunkk (Horda, Hammerfall) vende el Belt y Androd Fadran (Alianza,
        # Refuge Pointe) la Harness, como en el Classic original (dos jugadores de la
        # Horda, Discord y CurseForge, 2026-11)
        VENDOR_FIXES = {13287: {2816}, 13288: {2819}}
        for item_id, npcs in VENDOR_FIXES.items():
            if item_id in fv_vendors:
                was = fv_vendors[item_id]
                for old, new in zip(sorted(was), sorted(npcs)):
                    if (item_id, old) in limited:
                        limited.add((item_id, new))
                fv_vendors[item_id] = set(npcs)
        for item_id in scrolls:
            book = fv_vendors.get(item_id)
            vendors, qs = items.get(item_id, ([], []))
            if item_id in VENDOR_FIXES:
                vendors = sorted(VENDOR_FIXES[item_id]) # (QuestieDB también lo tiene al revés)
                npcs_needed.update(VENDOR_FIXES[item_id])
            elif book:
                vendors = sorted(set(vendors) | book)
                npcs_needed.update(book)
            elif vendors:
                vendors = []
            if vendors or qs or item_id in drops:
                items[item_id] = (vendors, qs)
            elif item_id in items:
                del items[item_id]
        # (y los instructores de Forever que QuestieDB no conoce: la ruta lleva a ellos, ver tr)
        with open(PRIVATE / "forever_trainers.csv", encoding="utf-8") as f:
            npcs_needed.update(int(r["npc"]) for r in csv.DictReader(l for l in f if not l.startswith("#"))
                               if int(r["npc"]) in fv_npcs)

    # Subastadores (para "poner en la AH" desde la vista Profit) y posaderos: hay
    # uno en cada pueblo y, como cualquier vendedor, compran lo que fabricas
    auctioneers, innkeepers = [], []
    for npc_id in all_ids("Npc"):
        r = row("Npc", npc_id)
        flags = r and field("Npc", npc_id, NPC["npcFlags"], r)
        if not isinstance(flags, int):
            continue
        name = field("Npc", npc_id, NPC["name"], r) or ""
        if flags & NPC_AUCTIONEER and name.startswith("Auctioneer"):  # no los intendentes con la marca puesta
            auctioneers.append(npc_id)
        elif flags & NPC_INNKEEPER:
            innkeepers.append(npc_id)
    sell_vendors = set(innkeepers)
    for item_id in vendor_items:  # quien vende hilo, sal... también compra
        if item_id in items:
            sell_vendors.update(items[item_id][0])
    npcs_needed.update(auctioneers)
    npcs_needed.update(sell_vendors)

    npcs = {}
    for npc_id in sorted(npcs_needed):
        r = row("Npc", npc_id)
        name = r and field("Npc", npc_id, NPC["name"], r)
        if not name:
            continue
        spawns = field("Npc", npc_id, NPC["spawns"], r) or {}
        home = field("Npc", npc_id, NPC["zoneID"], r)
        spawns = {int(k): seq(v) for k, v in (spawns.items() if isinstance(spawns, dict) else enumerate(seq(spawns), 1))}
        zone = home if home in spawns else (min(spawns) if spawns else None)
        spots = [(float(seq(p)[0]), float(seq(p)[1])) for p in spawns.get(zone, [])
                 if len(seq(p)) >= 2 and 0 <= float(seq(p)[0]) <= 100 and 0 <= float(seq(p)[1]) <= 100]
        side = {"A": "A", "H": "H", "AH": ""}.get(field("Npc", npc_id, NPC["friendlyToFaction"], r), "X")
        if side == "" and zone is not None:
            side = CAPITALS.get(zone) or CAPITALS.get(parent_o.get(zone) or parent.get(zone)) or ""
        entry = [name, side]
        if spots and zone is not None and ui_map(zone):
            cx, cy = sum(s[0] for s in spots) / len(spots), sum(s[1] for s in spots) / len(spots)
            x, y = min(spots, key=lambda s: (s[0] - cx) ** 2 + (s[1] - cy) ** 2)
            entry += [ui_map(zone), round(x / 100, 4), round(y / 100, 4)]
        elif zone is not None:
            entry += [0, 0, 0, zone]  # mazmorra: sin mapa, solo la zona (para el nombre)
        npcs[npc_id] = entry

    # PNJ nuevos de Forever que QuestieDB aún no ha situado (sin posición): la sacada
    # de guías y bases de datos, con su fuente, en tools/forever/npc_locations.csv
    fixed = 0
    with open(HERE / "forever" / "npc_locations.csv", encoding="utf-8") as f:
        for loc in csv.DictReader(f):
            npc_id = int(loc["npc"])
            if npc_id in npcs and len(npcs[npc_id]) <= 2:
                npcs[npc_id] = [npcs[npc_id][0], loc["side"], int(loc["map"]),
                                round(float(loc["x"]) / 100, 4), round(float(loc["y"]) / 100, 4)]
                fixed += 1
    # PNJ de Forever que QuestieDB no tiene o no sitúa: los de PRIVATE/forever_npcs.csv
    # (sin bando: los dos; esos datos no lo dicen)
    for npc_id in sorted(npcs_needed):
        if npc_id in fv_npcs and (npc_id not in npcs or len(npcs[npc_id]) <= 2):
            name, m, x, y = fv_npcs[npc_id]
            side = npcs[npc_id][1] if npc_id in npcs else ""
            npcs[npc_id] = [npcs[npc_id][0] if npc_id in npcs else name, side, m, round(x, 4), round(y, 4)]
            fixed += 1

    def lua_str(s):
        return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'

    def lua_ids(lst):
        return "{ " + ", ".join(map(str, lst)) + " }"

    out = [
        "-- Generado por tools/gen_sources.py desde QuestieDB (Forever). No editar a mano.",
        "local _, ES = ...",
        "ES.Data = ES.Data or {}",
        "",
        "-- [objeto] = { v = { vendedores }, q = { misiones que lo dan },",
        f"--   d = {{ criaturas que lo sueltan }} (hasta {WORLD_DROP}), w = nº de criaturas si es botín del mundo",
        "--   (wl = { nivel mínimo, máximo } de esas criaturas),",
        "--   o = nº de objetos (cofres...) que lo contienen,",
        "--   lim = true si todos sus vendedores tienen stock limitado (venden pocos y reponen con el tiempo) }",
        "-- (pergaminos de receta, libros de rango y materiales que se compran al vendedor)",
        "ES.Data.ItemSources = {",
    ]
    for item_id, (vendors, qs) in sorted(items.items()):
        parts = []
        if vendors:
            parts.append("v = " + lua_ids(vendors))
            # Todos sus vendedores tienen stock limitado: puede no haber (la ruta lo avisa)
            if all((item_id, v) in limited for v in vendors):
                parts.append("lim = true")
        if qs:
            parts.append("q = " + lua_ids(qs))
        if item_id in drops:
            listed, n_mobs, n_objs, span = drops[item_id]
            if listed:
                parts.append("d = " + lua_ids(listed))
            elif n_mobs:
                parts.append(f"w = {n_mobs}")
                if span:
                    parts.append("wl = { %d, %d }" % span)
            if n_objs:
                parts.append(f"o = {n_objs}")
        out.append(f"  [{item_id}] = {{ {', '.join(parts)} }},")
    out += ["}", "", "-- [misión] = { nombre, bando (\"A\", \"H\" o \"\" los dos), nivel mínimo, { quien la da },",
            "--   texto de lo que pide entregar (o nil), misiones antes en su cadena,",
            "--   { objeto, cuántos, ... } que pide (cuántos 0: no se sabe) o nil, { misiones de su cadena } o nil }",
            "-- (también las de la cadena que piden objetos, para ponerles precio)", "ES.Data.Quests = {"]
    for q, (name, side, level, starters, asks, n_chain, q_items, chain) in sorted(quests.items()):
        rest = ""
        if q_items or chain:
            rest = f", {lua_ids(q_items) if q_items else 'nil'}" + (f", {lua_ids(chain)}" if chain else "")
        out.append(f"  [{q}] = {{ {lua_str(name)}, \"{side}\", {level}, {lua_ids(starters)}, "
                   f"{lua_str(asks) if asks else 'nil'}, {n_chain}{rest} }},")
    out += ["}", "",
            "-- [PNJ] = { nombre, bando (\"A\", \"H\", \"\" los dos, \"X\" ninguno), mapa, x, y } (x, y de 0 a 1;",
            "-- en una mazmorra: mapa 0 y la zona como 6.º campo)", "ES.Data.NPCs = {"]
    for npc_id, e in sorted(npcs.items()):
        rest = "" if len(e) == 2 else ", " + ", ".join(str(v) for v in e[2:])
        out.append(f"  [{npc_id}] = {{ {lua_str(e[0])}, \"{e[1]}\"{rest} }},")
    out += ["}", "", "-- [criatura que suelta un pergamino] = { nivel mínimo, nivel máximo }", "ES.Data.NPCLevels = {"]
    for npc_id in sorted(droppers):
        lv = levels(npc_id)
        if lv and npc_id in npcs:
            out.append("  [%d] = { %d, %d }," % (npc_id, lv[0], lv[1]))
    out += ["}", "",
            "-- Subastadores, y PNJ que compran lo que fabricas (posaderos y vendedores de materiales):",
            "-- el clic de la vista Profit marca el más cercano",
            "ES.Data.Auctioneers = " + lua_ids(sorted(n for n in auctioneers if n in npcs)),
            "ES.Data.SellVendors = " + lua_ids(sorted(n for n in sell_vendors if n in npcs)), ""]
    dest = ADDON / "Data" / "Sources.lua"
    dest.write_text("\n".join(out), encoding="utf-8")
    print(f"{dest}: {len(items)} objetos con fuente, {len(quests)} misiones, {len(npcs)} PNJ "
          f"({sum(1 for e in npcs.values() if len(e) > 2)} con posición, {fixed} de npc_locations.csv), {len(auctioneers)} subastadores, "
          f"{len(sell_vendors)} que compran, {dest.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
