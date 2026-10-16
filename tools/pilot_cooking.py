exec(open(__file__.replace("pilot_cooking.py", "harness.py"), encoding="utf-8").read())
print(run(r"""
local out = {}
local function clean(t) return (tostring(t or ""):gsub("|T[^|]+|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local e = CraftersJournalDB.scans[ES:RealmKey()].items[5482]
out[#out+1] = "Recipe: Kaldorei Spider Kabob en la AH: " .. (e and (e.minUnit .. "c, " .. e.listings .. " subastas") or "no hay")
local function Route(label)
  ES:GetMainFrame()
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Cooking" then page = p end end
  page.from = 75
  page.toBox._text = "150"
  page.detected = nil
  ES:CalculatePlan(page)
  ES:SelectProfessionView(page, "route")
  out[#out+1] = "== " .. label .. " (total " .. clean(page.stats.total._text) .. ")"
  for i = 1, #page.lines do
    local l = page.lines[i]
    out[#out+1] = string.format("   %-45s | %-70s | %s", clean(l.title):sub(1, 45), clean(l.sub):sub(1, 70), clean(l.value))
    if l.title and l.title:find("Conseguir receta") then
      TOOLTIP = {}
      page.rows[i]._scripts.OnEnter(page.rows[i])
      for _, t in ipairs(TOOLTIP) do out[#out+1] = "        tooltip: " .. clean(t) end
    end
  end
end
UnitFactionGroup = function() return "Alliance" end
Route("Sin Questie")
-- QuestieDB simulado: la receta (5482) la da la misión 4161 de la Alianza; nadie la vende
local NPCS = { [3607] = { "Androl Oakhand", { [141] = { { 56, 59 } } }, 141, "A" } }
LibQuestieDB = {
  RequireContract = function() return true end,
  Meta = { ItemMeta = { itemKeys = { vendors = 1, questRewards = 2 } },
           NpcMeta = { npcKeys = { name = 1, spawns = 2, zoneID = 3, friendlyToFaction = 4 } },
           QuestMeta = { questKeys = { name = 1, startedBy = 2, requiredLevel = 3, requiredRaces = 4 } } },
  Item = { GetAll = function(id) if id == 5482 then return { {}, { 4161 } } end return { {}, {} } end },
  Npc = { GetAll = function(id) return NPCS[id] end },
  Quest = { GetAll = function(id) if id == 4161 then return { "Recipe of the Kaldorei", { { 3607 } }, 5, 77 } end end },
  Support = { Get = function() return { private = { areaIdToUiMapId = "return { [141] = 1438 }", subZoneToParentZone = "return {}" } } end },
}
CreateVector2D = function(x, y) return { x = x, y = y } end
C_Map = {
  GetWorldPosFromMapPos = function(map, v) return 1, { GetXY = function() return v.x * 1000, v.y * 1000 end } end,
  GetMapInfo = function(map) return { name = map == 1438 and "Teldrassil" or ("Mapa " .. map) } end,
  CanSetUserWaypointOnMap = function() return true end, SetUserWaypoint = function() end,
  GetBestMapForUnit = function() return 1438 end, GetPlayerMapPosition = function() return nil end,
}
UnitPosition = function() return 500, 500, 0, 1 end
InCombatLockdown = function() return false end
TOOLTIP = {}
Route("Con Questie (Alianza)")
-- Icono de misión desactivado: la receta solo se compra
local cooking
for _, p in ipairs(ES.professionPages) do if p.profKey == "Cooking" then cooking = p end end
assert(cooking.questButton, "Cocina debería tener el icono de misión")
for _, p in ipairs(ES.professionPages) do
  assert(p.questButton, p.profKey .. " debería tener el icono de misión")
end
cooking.questButton._scripts.OnClick(cooking.questButton)
assert(ES.db.prof.Cooking.useQuests == false, "no se desactivó")
TOOLTIP = {}
Route("Con Questie (Alianza) y misiones DESACTIVADAS")
cooking.questButton._scripts.OnClick(cooking.questButton)
assert(ES.db.prof.Cooking.useQuests ~= false, "no se volvió a activar")
-- El pergamino de Cooked Crab Claw (2698) en la bolsa: gratis, "Aprender receta"
BAGS[2698] = 1
TOOLTIP = {}
Route("Con el pergamino de Cooked Crab Claw en la bolsa")
BAGS[2698] = nil
-- Ya sabes Kaldorei Spider Kabob (6412) y Cooked Crab Claw (2545): sin filas de aprender
KNOWN_SPELLS[6412], KNOWN_SPELLS[2545] = true, true
TOOLTIP = {}
Route("Sabiendo ya Kaldorei Spider Kabob y Cooked Crab Claw")
KNOWN_SPELLS = {}
UnitFactionGroup = function() return "Horde" end
local okP, p = pcall(function() return ES.Planner:Plan(ES.Data.Cooking, ES:PlanOptions("Cooking", 75, 150, nil)) end)
out[#out+1] = "Horda plan directo: " .. tostring(okP) .. " " .. (okP and string.format("pasos %d llega %d parado %s", #p.steps, p.reached, tostring(p.stoppedAt)) or tostring(p))
Route("Con Questie (Horda)")
return table.concat(out, "\n")
"""))
