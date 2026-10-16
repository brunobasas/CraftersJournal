"""Analiza QuestieDB (Forever) fuera del juego: de dónde sale cada receta de
pergamino de nuestras profesiones (vendedores, misiones, drops) y de qué bando.

Lee los datos "baked" del .toc de QuestieDB (Base64 + CBOR, IDs con zlib).
Uso: python questie_recipes.py [salida.json]
"""
import base64
import json
import re
import struct
import sys
import zlib
from pathlib import Path

ADDONS = Path(r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns")
TOC = ADDONS / "QuestieDB" / "QuestieDB_Forever.toc"
DATA = ADDONS / "CraftersJournal" / "Data"
PROFS = ["Leatherworking", "Enchanting", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Cooking", "FirstAid"]

ITEM = {"name": 1, "npcDrops": 2, "questRewards": 6, "vendors": 14, "teachesSpell": 16}
NPC = {"name": 1, "spawns": 7, "zoneID": 9, "friendlyToFaction": 13}
QUEST = {"name": 1, "startedBy": 2, "requiredLevel": 4, "requiredRaces": 6}
ALLIANCE_RACES, HORDE_RACES = 77, 178


# --- CBOR mínimo -----------------------------------------------------------
def cbor(data):
    def item(i):
        ib = data[i]
        major, info = ib >> 5, ib & 31
        i += 1

        def arg(i):
            if info < 24:
                return info, i
            n = {24: 1, 25: 2, 26: 4, 27: 8}[info]
            return int.from_bytes(data[i:i + n], "big"), i + n

        if major == 7:
            if info == 20: return False, i
            if info == 21: return True, i
            if info in (22, 23): return None, i
            if info == 25: return struct.unpack(">e", data[i:i + 2])[0], i + 2
            if info == 26: return struct.unpack(">f", data[i:i + 4])[0], i + 4
            if info == 27: return struct.unpack(">d", data[i:i + 8])[0], i + 8
            return None, i
        v, i = arg(i)
        if major == 0: return v, i
        if major == 1: return -1 - v, i
        if major == 2: return data[i:i + v], i + v
        if major == 3: return data[i:i + v].decode("utf-8", "replace"), i + v
        if major == 4:
            out = []
            for _ in range(v):
                x, i = item(i)
                out.append(x)
            return out, i
        if major == 5:
            out = {}
            for _ in range(v):
                k, i = item(i)
                x, i = item(i)
                out[k] = x
            return out, i
        if major == 6:
            return item(i)
        raise ValueError(major)
    return item(0)[0]


# --- Almacén de metadatos del .toc -----------------------------------------
print("Leyendo", TOC.name, "...", file=sys.stderr)
store = {}
with open(TOC, encoding="utf-8") as f:
    for line in f:
        if line.startswith("## X-"):
            key, _, value = line[3:].partition(": ")
            store[key] = value.rstrip("\n")


def stored(key):
    v = store.get(key)
    if v is None:
        return None
    m = re.fullmatch(r"~(\d+)~", v)
    if m:
        return "".join(store[f"{key}-{i}"] for i in range(1, int(m.group(1)) + 1))
    return v


def decode(v):
    return cbor(base64.b64decode(v))


def row(prefix, eid):
    s = stored(f"X-{prefix}-{eid}-S")
    return decode(s) if s else None


def field(prefix, eid, idx, r):
    """Valor de un campo: escalar en la fila, tabla en su propia clave."""
    if r is None:
        return None
    key = idx if idx in r else str(idx)
    if key in r:
        v = r[key]
    else:
        s = stored(f"X-{prefix}-{eid}-{idx}")
        v = decode(s) if s else None
    return v.decode("utf-8", "replace") if isinstance(v, bytes) else v


def at(t, i):
    """Elemento i (1-based, como en Lua) de una lista o de un mapa con huecos."""
    if isinstance(t, list):
        return t[i - 1] if 0 < i <= len(t) else None
    if isinstance(t, dict):
        return t.get(i, t.get(str(i)))
    return None


def ids_list(lst):
    if isinstance(lst, dict):
        lst = [lst[k] for k in sorted(lst, key=lambda k: int(k))]
    return [x for x in (lst or []) if isinstance(x, int)]


def side_of_npc(npc_id):
    r = row("Npc", npc_id)
    if not r:
        return None, None
    name = field("Npc", npc_id, NPC["name"], r)
    f = field("Npc", npc_id, NPC["friendlyToFaction"], r)
    return name, {"A": "A", "H": "H", "AH": "AH"}.get(f, "-")


def quest_info(qid):
    r = row("Quest", qid)
    if not r:
        return None
    races = field("Quest", qid, QUEST["requiredRaces"], r) or 0
    a, h = (races & ALLIANCE_RACES) != 0, (races & HORDE_RACES) != 0
    started = field("Quest", qid, QUEST["startedBy"], r)
    starters = ids_list(at(started, 1))
    return {
        "id": qid, "name": field("Quest", qid, QUEST["name"], r),
        "level": field("Quest", qid, QUEST["requiredLevel"], r) or 0,
        "side": "AH" if a == h else ("A" if a else "H"), "starters": starters,
    }


# --- Recetas de pergamino de nuestros datos --------------------------------
recipes = {}
for prof in PROFS:
    for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]*)",[^\n]*?scroll = (\d+)[^\n]*', (DATA / f"{prof}.lua").read_text(encoding="utf-8")):
        line = m.group(0)
        if "fee = " in line:
            continue
        price = re.search(r"scrollPrice = (\d+)", line)
        recipes[(prof, int(m.group(1)))] = {"name": m.group(2), "scroll": int(m.group(3)),
                                            "train": int(re.search(r"train = (\d+)", line).group(1)) if "train = " in line else None,
                                            "price": int(price.group(1)) if price else None}

result = {}
summary = {}
for (prof, sid), r in sorted(recipes.items()):
    it = row("Item", r["scroll"])
    vendors, quests, drops = [], [], []
    if it:
        for v in ids_list(field("Item", r["scroll"], ITEM["vendors"], it)):
            name, side = side_of_npc(v)
            if name:
                vendors.append({"id": v, "name": name, "side": side})
        for q in ids_list(field("Item", r["scroll"], ITEM["questRewards"], it)):
            qi = quest_info(q)
            if qi:
                quests.append(qi)
        drops = ids_list(field("Item", r["scroll"], ITEM["npcDrops"], it))
    sides = lambda lst: "".join(sorted({c for x in lst for c in x["side"] if c in "AH"}))
    kind = ("vendor" if vendors else "quest" if quests else "drop" if drops else "none")
    entry = dict(r, spell=sid, profession=prof, vendors=vendors, quests=quests, drops=len(drops),
                 kind=kind, vendorSides=sides(vendors), questSides=sides(quests), inQuestie=it is not None)
    result[f"{prof}:{sid}"] = entry
    s = summary.setdefault(prof, {"total": 0, "vendor": 0, "quest": 0, "drop": 0, "none": 0,
                                  "vendor_A": 0, "vendor_H": 0, "quest_A": 0, "quest_H": 0})
    s["total"] += 1
    s[kind] += 1
    if vendors:
        s["vendor_A"] += "A" in entry["vendorSides"]
        s["vendor_H"] += "H" in entry["vendorSides"]
    if quests:
        s["quest_A"] += "A" in entry["questSides"]
        s["quest_H"] += "H" in entry["questSides"]

out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("recipe_sources.json")
out.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"{'Profesión':<15} {'recetas':>7} {'vendedor':>8} {'(A/H)':>8} {'misión':>7} {'(A/H)':>7} {'drop':>5} {'nada':>5}")
for prof in PROFS:
    s = summary.get(prof)
    if s:
        print(f"{prof:<15} {s['total']:>7} {s['vendor']:>8} {s['vendor_A']:>4}/{s['vendor_H']:<3} {s['quest']:>7} {s['quest_A']:>3}/{s['quest_H']:<3} {s['drop']:>5} {s['none']:>5}")
print("guardado en", out)
