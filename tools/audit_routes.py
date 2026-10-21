"""Auditoría de rutas con los precios reales del último escaneo (SavedVariables).

Recorre todas las profesiones en varios tramos y marca lo que suele delatar un
fallo del planificador:
  - MEZCLA: un material comprado y fabricado a la vez
  - POCAS PROB: pasos con muchas fabricaciones por punto (receta casi gris)
  - CARO / MUCHAS COMPRAS / MUCHO MATERIAL / MUCHOS INTERMEDIOS: material o coste
    desproporcionado para los puntos que da
  - NO CUADRA: el total no es la suma de los pasos
  - con bolsas: que no use lo tuyo de más, no salga más cara ni llegue menos
No todo lo marcado es un fallo (una receta casi gris puede ser lo más barato de
verdad): es para revisarlo.

Uso:  python -X utf8 tools/audit_routes.py [--v1]   (--v1: con el planificador antiguo)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import run  # noqa: E402

print("=" * 70)
print("SIN BOLSAS")
print(run(("ES.Planner.USE_GPS = false\n" if "--v1" in sys.argv else "") + r"""
local out = {}
local function P(...) out[#out+1] = string.format(...) end
local function N(id) return ES:DataItemName(id) or tostring(id) end
local function M(c) return string.format("%.2fs", (c or 0) / 100) end

local PROFS = { "Leatherworking", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Enchanting", "Cooking", "FirstAid" }
local RANGES = { {1, 75}, {50, 100}, {75, 125}, {100, 150}, {150, 225}, {200, 225} }

local summary = {}
for _, prof in ipairs(PROFS) do
  local data = ES.Data[prof]
  if data and data.recipes then
    for _, rg in ipairs(RANGES) do
      local from, to = rg[1], rg[2]
      local opts = ES:PlanOptions(prof, from, to, nil)
      opts.owned = nil
      local ok, plan = pcall(ES.Planner.Plan, ES.Planner, data, opts)
      if not ok then
        P("!! %s %d-%d ERROR %s", prof, from, to, tostring(plan))
      else
        local points = (plan.reached or to) - from
        local flags = {}
        if plan.stoppedAt then flags[#flags+1] = "PARA en " .. plan.stoppedAt end
        -- Material total (unidades) a conseguir y por punto
        local units = 0
        for _, it in ipairs(plan.shopping) do units = units + it.quantity end
        local inter = 0
        for _, c in ipairs(plan.crafted) do inter = inter + c.quantity end
        local crafts = 0
        for _, st in ipairs(plan.steps) do crafts = crafts + st.crafts end
        -- Mezclas
        local craftedSet = {}
        for _, c in ipairs(plan.crafted) do craftedSet[c.itemID] = c.quantity end
        for _, it in ipairs(plan.shopping) do
          if craftedSet[it.itemID] and it.source == "ah" then
            flags[#flags+1] = string.format("MEZCLA %s (compra %d, fabrica %d)", N(it.itemID), it.quantity, craftedSet[it.itemID])
          end
        end
        -- Pasos: fabricaciones por punto, coste por punto, zigzag
        local costs = {}
        local short = 0
        for _, st in ipairs(plan.steps) do
          local pts = st.to - st.from
          local cpp = st.expected / pts
          local costpp = st.total / pts
          costs[#costs+1] = costpp
          if cpp > 2.5 then flags[#flags+1] = string.format("POCAS PROB %s %d-%d (%.1f fab/punto)", st.recipe.name, st.from, st.to, cpp) end
          if pts <= 2 then short = short + 1 end
          -- receta casi gris al empezar
          if st.firstChance and st.firstChance < 0.5 then flags[#flags+1] = string.format("AMARILLA/VERDE AL EMPEZAR %s %d (%.0f%%)", st.recipe.name, st.from, st.firstChance * 100) end
          -- reagentes por fabricación grandes
          local per = 0
          for _, r in ipairs(st.recipe.r) do per = per + r[2] end
          if per >= 10 and pts <= 10 then flags[#flags+1] = string.format("MUCHO MATERIAL %s %d-%d: %d por fab x%d fab", st.recipe.name, st.from, st.to, per, st.crafts) end
        end
        if short >= 3 then flags[#flags+1] = "ZIGZAG " .. short .. " pasos de <=2 puntos" end
        table.sort(costs)
        local med = costs[math.ceil(#costs / 2)] or 0
        for _, st in ipairs(plan.steps) do
          local costpp = st.total / (st.to - st.from)
          if med > 50 and costpp > med * 4 and costpp > 500 then
            flags[#flags+1] = string.format("CARO %s %d-%d (%s/punto vs mediana %s)", st.recipe.name, st.from, st.to, M(costpp), M(med))
          end
        end
        -- Cuadre del total
        local sum = 0
        for _, st in ipairs(plan.steps) do sum = sum + st.total end
        local expectNet = sum + (plan.toolsCost or 0)
        for _, rk in ipairs(plan.ranks) do expectNet = expectNet + rk.fee end
        if math.abs(expectNet - plan.net) > 2 then flags[#flags+1] = string.format("NO CUADRA net=%d suma=%d", plan.net, expectNet) end
        if inter > 0 and points > 0 and inter / points > 5 then flags[#flags+1] = string.format("MUCHOS INTERMEDIOS %d para %d puntos", inter, points) end
        if points > 0 and units / points > 12 then flags[#flags+1] = string.format("MUCHAS COMPRAS %d uds para %d puntos", units, points) end
        P("%-14s %3d-%3d net=%9s pts=%3d fab=%4d (%.1f/pt) compra=%5d uds (%.1f/pt) interm=%4d %s",
          prof, from, to, M(plan.net), points, crafts, points > 0 and crafts / points or 0, units, points > 0 and units / points or 0, inter,
          #flags > 0 and ("\n      - " .. table.concat(flags, "\n      - ")) or "")
      end
    end
  end
end
return table.concat(out, "\n")
"""))
print("=" * 70)
print("CON LA MITAD DE LO QUE COMPRA EN LAS BOLSAS")
print(run(("ES.Planner.USE_GPS = false\n" if "--v1" in sys.argv else "") + r"""
local out = {}
local function P(...) out[#out+1] = string.format(...) end
local function N(id) return ES:DataItemName(id) or tostring(id) end
local function M(c) return string.format("%.2fs", (c or 0) / 100) end
local PROFS = { "Leatherworking", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Enchanting", "Cooking", "FirstAid" }
local RANGES = { {50, 100}, {75, 125}, {100, 150}, {150, 200} }
for _, prof in ipairs(PROFS) do
  local data = ES.Data[prof]
  for _, rg in ipairs(RANGES) do
    local from, to = rg[1], rg[2]
    local o = ES:PlanOptions(prof, from, to, nil); o.owned = nil
    local base = ES.Planner:Plan(data, o)
    -- La mitad de lo que compraría, en las bolsas
    local owned = {}
    for _, it in ipairs(base.shopping) do
      if it.source == "ah" then owned[it.itemID] = math.floor(it.quantity / 2) end
    end
    local ob = ES:PlanOptions(prof, from, to, nil); ob.owned = owned
    local ok, plan = pcall(ES.Planner.Plan, ES.Planner, data, ob)
    if not ok then P("!! %s %d-%d ERROR %s", prof, from, to, tostring(plan)) else
      local flags = {}
      local crafted = {}
      for _, c in ipairs(plan.crafted) do crafted[c.itemID] = true end
      for _, it in ipairs(plan.shopping) do
        if crafted[it.itemID] and it.source == "ah" then flags[#flags+1] = "MEZCLA " .. N(it.itemID) end
      end
      -- No usar lo tuyo de más
      for _, it in ipairs(plan.owned or {}) do
        if it.quantity > (owned[it.itemID] or 0) + 0.5 then flags[#flags+1] = string.format("USA DE MAS %s %d > %d", N(it.itemID), it.quantity, owned[it.itemID] or 0) end
      end
      -- Gastando lo tuyo, la ruta no debería costar más oro que sin bolsas
      if plan.reached < base.reached then flags[#flags+1] = "LLEGA MENOS con bolsas" end
      if plan.net > base.net + 100 then flags[#flags+1] = string.format("MAS CARA con bolsas: %s vs %s", M(plan.net), M(base.net)) end
      local crafts, bcrafts = 0, 0
      for _, st in ipairs(plan.steps) do crafts = crafts + st.crafts end
      for _, st in ipairs(base.steps) do bcrafts = bcrafts + st.crafts end
      if crafts > bcrafts * 1.5 + 5 then flags[#flags+1] = string.format("MUCHAS MAS FABRICACIONES con bolsas: %d vs %d", crafts, bcrafts) end
      P("%-14s %3d-%3d sin=%9s con=%9s fab %d->%d %s", prof, from, to, M(base.net), M(plan.net), bcrafts, crafts,
        #flags > 0 and ("\n      - " .. table.concat(flags, "\n      - ")) or "")
    end
  end
end
return table.concat(out, "\n")
"""))