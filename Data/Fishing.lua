-- Generado por tools/gen_fishing.py. No editar a mano.
-- Zonas: https://www.wow-professions.com/forever/fishing-leveling-guide (beta de Forever). Instructores, libro y misión: QuestieDB.
local _, ES = ...
ES.Data = ES.Data or {}

-- Pesca: se sube pescando (guide = tramos con las zonas); las recetas son las mejoras
-- de campamento que se fabrican (no dan puntos: camp = true)
ES.Data.Fishing = {
  skillLine = 356,
  -- { PNJ instructor, rangos que enseña: 1 aprendiz + 2 oficial }
  trainers = { { 1651, 3 }, { 1680, 3 }, { 1683, 3 }, { 1700, 3 }, { 2367, 3 }, { 2834, 3 }, { 3028, 3 }, { 3179, 3 }, { 3332, 3 }, { 3607, 3 }, { 4156, 3 }, { 4573, 3 }, { 5161, 3 }, { 5493, 3 }, { 5690, 3 }, { 5938, 3 }, { 5941, 3 }, { 7946, 3 }, { 12032, 3 }, { 12961, 3 }, { 14740, 3 }, { 251992, 3 }, { 255877, 3 }, { 260558, 3 } },
  expertBook = 16083, bookVendor = 2626,
  artisanQuest = 6607, artisanQuestName = "Nat Pagle, Angler Extreme", artisanNPC = 12919,
  extraNPCs = { 2626, 12919 },
  -- { desde, hasta, rango, habilidad y nivel que pide, { { mapa, zona } } }
  guide = {
    { from = 1, to = 75, rank = "apprentice", skill = 1, level = 1, zones = { { 1411, "Durotar" }, { 1412, "Mulgore" }, { 1420, "Tirisfal Glades" }, { 1429, "Elwynn Forest" }, { 1426, "Dun Morogh" }, { 1438, "Teldrassil" } } },
    { from = 75, to = 150, rank = "journeyman", skill = 50, level = 10, zones = { { 1454, "Orgrimmar" }, { 1458, "Undercity" }, { 1456, "Thunder Bluff" }, { 1453, "Stormwind City" }, { 1455, "Ironforge" }, { 1457, "Darnassus" }, { 1413, "The Barrens" }, { 1439, "Darkshore" }, { 1432, "Loch Modan" }, { 1421, "Silverpine Forest" }, { 1436, "Westfall" } } },
    { from = 150, to = 225, rank = "expert", skill = 125, level = 20, zones = { { 1445, "Dustwallow Marsh" }, { 1416, "Alterac Mountains" }, { 1417, "Arathi Highlands" }, { 1443, "Desolace" }, { 1434, "Stranglethorn Vale" }, { 1435, "Swamp of Sorrows" }, { 1441, "Thousand Needles" } } },
    { from = 225, to = 300, rank = "artisan", skill = 225, level = 35, zones = { { 1448, "Felwood" }, { 1444, "Feralas" }, { 1425, "The Hinterlands" }, { 1446, "Tanaris" }, { 1449, "Un'Goro Crater" }, { 1422, "Western Plaguelands" } } },
  },
  recipes = {
    [1229745] = { name = "Fish Bowl", t = { 1, 1, 1, 1 }, camp = true, r = { { 6291, 1 }, { 3371, 1 } } },
    [1262990] = { name = "Fishing Rack", t = { 1, 1, 1, 1 }, camp = true, scroll = 273141, train = 1, sq = 2, r = { { 4470, 2 }, { 8925, 1 }, { 8365, 2 } } },
    [1262998] = { name = "Fishing Hut", t = { 1, 1, 1, 1 }, camp = true, scroll = 273119, train = 1, sq = 2, r = { { 4470, 5 }, { 14048, 2 }, { 273295, 1 } } },
  },
}

-- Nombre de cada objeto (inglés, del cliente): se muestra mientras el juego no lo ha cargado
ES.Data.ItemNames = ES.Data.ItemNames or {}
ES.Data.ItemNames[3371] = "Empty Vial"
ES.Data.ItemNames[4470] = "Simple Wood"
ES.Data.ItemNames[6291] = "Raw Brilliant Smallfish"
ES.Data.ItemNames[8365] = "Raw Mithril Head Trout"
ES.Data.ItemNames[8925] = "Crystal Vial"
ES.Data.ItemNames[14048] = "Bolt of Runecloth"
ES.Data.ItemNames[16083] = "Expert Fishing - The Bass and You"
ES.Data.ItemNames[273295] = "Seasonal Fish Steaks"
