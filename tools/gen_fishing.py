"""Genera Data/Fishing.lua: la Pesca de WoW Forever.

La Pesca no fabrica nada para subir: se sube pescando en zonas según tu nivel. Por
eso, en vez de recetas con umbrales, lleva una guía por tramos (zonas, rangos, el
libro de Experto y la misión de Artesano) y, para la colección, las mejoras de
campamento que sí se fabrican (Fish Bowl, Fishing Rack, Fishing Hut).

Fuentes:
  - Zonas y requisitos: guía de wow-professions.com (cliente beta de Forever, 2026-10-15)
    https://www.wow-professions.com/forever/fishing-leveling-guide
  - Instructores, Old Man Heming, Nat Pagle, el libro y la misión: QuestieDB
  - Mejoras de campamento (materiales y planos): tablas del cliente (tools/wago)
Uso: python gen_fishing.py
"""
import csv
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ADDON = HERE.parent
WAGO = HERE / "wago"
sys.path.insert(0, str(HERE))
import questie  # noqa: E402

SKILL_LINE = 356
GUIDE_URL = "https://www.wow-professions.com/forever/fishing-leveling-guide"
TRAINER_SUBTITLES = {"Fishing Trainer", "Fishing Trainer & Supplies", "Junior Fishing Trainer", "Fisherman",
                     "Superior Fisherman"}
NPC_FLAG_TRAINER = 16
EXPERT_BOOK, BOOK_VENDOR = 16083, 2626      # Expert Fishing - The Bass and You, Old Man Heming
ARTISAN_QUEST, ARTISAN_NPC = 6607, 12919    # Nat Pagle, Angler Extreme; Nat Pagle
CAMP_SPELLS = [1229745, 1262990, 1262998]  # Fish Bowl, Fishing Rack, Fishing Hut

# Tramos de la guía: (desde, hasta, qué aprender, zonas como (uiMapID, nombre en inglés))
# Los nombres se leen del juego con C_Map (en el idioma del cliente); el inglés es por si no.
STEPS = [
    (1, 75, "apprentice", [(1411, "Durotar"), (1412, "Mulgore"), (1420, "Tirisfal Glades"), (1429, "Elwynn Forest"),
                           (1426, "Dun Morogh"), (1438, "Teldrassil")]),
    (75, 150, "journeyman", [(1454, "Orgrimmar"), (1458, "Undercity"), (1456, "Thunder Bluff"), (1453, "Stormwind City"),
                             (1455, "Ironforge"), (1457, "Darnassus"), (1413, "The Barrens"), (1439, "Darkshore"),
                             (1432, "Loch Modan"), (1421, "Silverpine Forest"), (1436, "Westfall")]),
    (150, 225, "expert", [(1445, "Dustwallow Marsh"), (1416, "Alterac Mountains"), (1417, "Arathi Highlands"),
                          (1443, "Desolace"), (1434, "Stranglethorn Vale"), (1435, "Swamp of Sorrows"),
                          (1441, "Thousand Needles")]),
    (225, 300, "artisan", [(1448, "Felwood"), (1444, "Feralas"), (1425, "The Hinterlands"), (1446, "Tanaris"),
                           (1449, "Un'Goro Crater"), (1422, "Western Plaguelands")]),
]
# Requisitos de cada rango (habilidad, nivel de personaje)
RANKS = {"apprentice": (1, 1), "journeyman": (50, 10), "expert": (125, 20), "artisan": (225, 35)}


def rows(name):
    with open(WAGO / f"{name}.csv", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def trainers():
    questie.load_store()
    out = []
    for key in questie.store:
        m = re.match(r"X-Npc-(\d+)-S$", key)
        if not m:
            continue
        nid = int(m.group(1))
        r = questie.row("Npc", nid)
        sub = questie.field("Npc", nid, 14, r)
        flags = questie.field("Npc", nid, 15, r) or 0
        if isinstance(sub, str) and sub in TRAINER_SUBTITLES and int(flags) & NPC_FLAG_TRAINER:
            out.append(nid)
    return sorted(out)


def main():
    names = {int(r["ID"]): r["Name_lang"] for r in rows("SpellName_forever")}
    reagents = {}
    for r in rows("SpellReagents_forever"):
        reagents[int(r["SpellID"])] = [(int(r[f"Reagent_{k}"]), int(r[f"ReagentCount_{k}"])) for k in range(8)
                                       if int(r[f"Reagent_{k}"] or 0) and int(r[f"ReagentCount_{k}"] or 0)]
    scrolls = {int(r["Spell"]): int(r["ItemID"]) for r in rows("RecipeScrolls_forever")}
    items = {int(r["ID"]): r for r in rows("ItemSparse_forever")}
    quality = {i: int(r.get("OverallQualityID") or 1) for i, r in items.items()}

    tr = trainers()
    qr = questie.row("Quest", ARTISAN_QUEST)
    quest_name = questie.field("Quest", ARTISAN_QUEST, questie.QUEST["name"], qr) if qr else "Nat Pagle, Angler Extreme"
    out = [
        "-- Generado por tools/gen_fishing.py. No editar a mano.",
        f"-- Zonas: {GUIDE_URL} (beta de Forever). Instructores, libro y misión: QuestieDB.",
        "local _, ES = ...",
        "ES.Data = ES.Data or {}",
        "",
        "-- Pesca: se sube pescando (guide = tramos con las zonas); las recetas son las mejoras",
        "-- de campamento que se fabrican (no dan puntos: camp = true)",
        "ES.Data.Fishing = {",
        f"  skillLine = {SKILL_LINE},",
        "  -- { PNJ instructor, rangos que enseña: 1 aprendiz + 2 oficial }",
        "  trainers = { " + ", ".join("{ %d, 3 }" % n for n in tr) + " },",
        f"  expertBook = {EXPERT_BOOK}, bookVendor = {BOOK_VENDOR},",
        f"  artisanQuest = {ARTISAN_QUEST}, artisanQuestName = {lua_str(quest_name)}, artisanNPC = {ARTISAN_NPC},",
        f"  extraNPCs = {{ {BOOK_VENDOR}, {ARTISAN_NPC} }},",
        "  -- { desde, hasta, rango, habilidad y nivel que pide, { { mapa, zona } } }",
        "  guide = {",
    ]
    for lo, hi, rank, zones in STEPS:
        skill, level = RANKS[rank]
        z = ", ".join("{ %d, %s }" % (m, lua_str(n)) for m, n in zones)
        out.append(f'    {{ from = {lo}, to = {hi}, rank = "{rank}", skill = {skill}, level = {level}, zones = {{ {z} }} }},')
    out += ["  },", "  recipes = {"]
    used = set()
    for sid in CAMP_SPELLS:
        rg = reagents.get(sid)
        if not rg:
            continue
        parts = [f"name = {lua_str(names.get(sid, sid))}", "t = { 1, 1, 1, 1 }", "camp = true"]
        if sid in scrolls:
            parts.append(f"scroll = {scrolls[sid]}, train = 1, sq = {quality.get(scrolls[sid], 1)}")
        parts.append("r = { " + ", ".join("{ %d, %d }" % x for x in rg) + " }")
        used.update(i for i, _ in rg)
        out.append(f"    [{sid}] = {{ " + ", ".join(parts) + " },")
    out += ["  },", "}", "",
            "-- Nombre de cada objeto (inglés, del cliente): se muestra mientras el juego no lo ha cargado",
            "ES.Data.ItemNames = ES.Data.ItemNames or {}"]
    for i in sorted(used | {EXPERT_BOOK}):
        if i in items and items[i]["Display_lang"]:
            out.append(f"ES.Data.ItemNames[{i}] = {lua_str(items[i]['Display_lang'])}")
    out.append("")
    dest = ADDON / "Data" / "Fishing.lua"
    dest.write_text("\n".join(out), encoding="utf-8")
    print(f"{dest}: {len(tr)} instructores, {len(STEPS)} tramos, {len(CAMP_SPELLS)} mejoras de campamento")


if __name__ == "__main__":
    main()
