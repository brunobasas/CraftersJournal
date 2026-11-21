-- Datos generados (Data/*.lua): lo que el resto del addon da por hecho de ellos.
-- Si una prueba falla tras regenerar los datos, el generador ha cambiado algo.

local D

local function Each(fn)
  for _, prof in ipairs(ProfessionKeys()) do
    local data = ES.Data[prof]
    for id, r in pairs(data.recipes) do fn(prof, id, r) end
  end
end

local function Report(bad, what, max)
  if #bad == 0 then return end
  table.sort(bad)
  local shown = {}
  for i = 1, math.min(#bad, max or 12) do shown[i] = bad[i] end
  error(string.format("%d %s:\n    %s%s", #bad, what, table.concat(shown, "\n    "), #bad > #shown and "\n    …" or ""), 0)
end

test("las 8 profesiones tienen datos", function()
  for _, prof in ipairs(ProfessionKeys()) do
    local data = ES.Data[prof]
    expect(data and type(data.recipes) == "table" and next(data.recipes), "%s sin recetas", prof)
    expect(type(data.skillLine) == "number", "%s sin skillLine", prof)
    expect(#(data.ranks or {}) >= 3, "%s: rangos de instructor", prof)
    expect(#(data.trainers or {}) > 0, "%s sin instructores", prof)
  end
end, { boot = false })

test("recetas: los cuatro niveles de color en orden", function()
  local bad = {}
  Each(function(prof, id, r)
    local t = r.t
    local ok = type(t) == "table" and #t == 4
    if ok then
      for i = 1, 4 do ok = ok and type(t[i]) == "number" and t[i] >= 0 and t[i] <= 400 end
      ok = ok and t[1] <= t[2] and t[2] <= t[3] and t[3] <= t[4]
    end
    if not ok then
      bad[#bad + 1] = string.format("%s %d %s: t = {%s}", prof, id, tostring(r.name),
        type(t) == "table" and table.concat({ tostring(t[1]), tostring(t[2]), tostring(t[3]), tostring(t[4]) }, ", ") or tostring(t))
    end
  end)
  -- (hay alguna así en los datos del cliente: Coarse/Heavy Sharpening Stone. Se guarda
  -- la lista: una nueva sale como cambio de la instantánea)
  table.sort(bad)
  note("%d recetas con los colores desordenados", #bad)
  snapshot("recetas con los colores desordenados", bad)
end, { boot = false })

test("recetas: materiales y resultado con cantidades positivas", function()
  local bad = {}
  Each(function(prof, id, r)
    local where = string.format("%s %d %s", prof, id, tostring(r.name))
    if type(r.r) ~= "table" or #r.r == 0 then bad[#bad + 1] = where .. ": sin materiales" end
    for _, m in ipairs(r.r or {}) do
      if type(m[1]) ~= "number" or m[1] <= 0 or type(m[2]) ~= "number" or m[2] <= 0 then
        bad[#bad + 1] = string.format("%s: material {%s, %s}", where, tostring(m[1]), tostring(m[2]))
      end
    end
    -- (los encantamientos de equipo no dan objeto: sin out)
    if r.out and (type(r.out[1]) ~= "number" or r.out[1] <= 0 or type(r.out[2]) ~= "number" or r.out[2] <= 0) then
      bad[#bad + 1] = string.format("%s: resultado {%s, %s}", where, tostring(r.out[1]), tostring(r.out[2]))
    end
    if not r.out and prof ~= "Enchanting" then bad[#bad + 1] = where .. ": sin resultado" end
    if type(r.name) ~= "string" or r.name == "" then bad[#bad + 1] = where .. ": sin nombre" end
  end)
  Report(bad, "recetas con materiales o resultado raros")
end, { boot = false })

test("recetas: se aprenden de algún sitio", function()
  -- fee/train (instructor), basic (sola), trainer, scroll (pergamino: de dónde sale
  -- en Data/Sources.lua) o favor (Merchant's Favor)
  local bad = {}
  Each(function(prof, id, r)
    if not (r.fee or r.train or r.basic or r.trainer or r.scroll or r.favor or r.gone) then
      bad[#bad + 1] = string.format("%s %d %s", prof, id, tostring(r.name))
    end
  end)
  -- (de misión, especialización...: se guarda la lista, una nueva sale como cambio)
  table.sort(bad)
  note("%d recetas sin forma de aprenderlas en los datos", #bad)
  snapshot("recetas sin forma de aprenderlas", bad)
end, { boot = false })

-- Spec recipe-requirements. CurseForge: "filter and not include recipes that require a
-- specialization, like Tribal Leatherworking". Solo llevaban `spec` las de instructor de
-- especialización; los pergaminos que la piden (RequiredAbility del objeto en el
-- cliente) se colaban en la ruta: Frostsaber Boots en Peletería, Blazing Rapier en
-- Herrería
test("recetas de especialización: también las de pergamino llevan su especialización", function()
  local want = {
    { "Leatherworking", 19066, "Frostsaber Boots", "Tribal" },
    { "Leatherworking", 19059, "Volcanic Leggings", "Elemental" },
    { "Leatherworking", 19085, "Black Dragonscale Breastplate", "Dragonscale" },
    { "Blacksmithing", 16978, "Blazing Rapier", "Swordsmith" },
    { "Blacksmithing", 16973, "Enchanted Battlehammer", "Hammersmith" },
    { "Blacksmithing", 16970, "Dawn's Edge", "Axesmith" },
    { "Blacksmithing", 15296, "Dark Iron Plate", "Armorsmith" },
    { "Blacksmithing", 16995, "Heartseeker", "Weaponsmith" },
    { "Engineering", 23078, "Goblin Jumper Cables XL", "Goblin" },
    { "Engineering", 23129, "World Enlarger", "Gnomish" },
    { "Engineering", 23096, "Alarm-O-Bot", "Gnomish" },
    -- (de instructor de especialización: ya la llevaban)
    { "Engineering", 12758, "Goblin Rocket Helmet", "Goblin" },
  }
  local bad = {}
  for _, w in ipairs(want) do
    local r = ES.Data[w[1]].recipes[w[2]]
    if not r then bad[#bad + 1] = string.format("%s %d %s: no está en los datos", w[1], w[2], w[3])
    elseif r.spec ~= w[4] then
      bad[#bad + 1] = string.format("%s %s: spec = %s (pide %s)", w[1], w[3], tostring(r.spec), w[4])
    end
  end
  Report(bad, "recetas de especialización sin su marca")
  -- Toda la lista, por profesión: una que gana o pierde la marca sale como cambio
  local list = {}
  Each(function(prof, id, r)
    if r.spec then
      list[prof] = list[prof] or {}
      table.insert(list[prof], string.format("%s (%s)", r.nameEN or r.name, r.spec))
    end
  end)
  local n = 0
  for _, l in pairs(list) do table.sort(l) n = n + #l end
  note("%d recetas de especialización", n)
  snapshot("recetas de especialización", list)
end, { boot = false })

-- Expert Cookbook y Expert First Aid - Under Wraps no piden nivel (cliente de Forever,
-- RequiredLevel 0; un jugador aprendió Experto de Cocina a nivel 33). Artesano: las
-- misiones Clamlette Surprise y Triage piden 35 (QuestieDB)
test("rangos de Cocina y Primeros auxilios: Experto no pide nivel, Artesano pide 35", function()
  for _, prof in ipairs({ "Cooking", "FirstAid" }) do
    local levels = {}
    for _, rank in ipairs(ES.Data[prof].ranks) do levels[rank[1]] = rank[4] end
    expect_eq(levels[225], 0, prof .. ": nivel de personaje de Experto (225)")
    expect_eq(levels[300], 35, prof .. ": nivel de personaje de Artesano (300)")
  end
end, { boot = false })

-- Change reagents-from-other-professions. CurseForge: "76 Mithril Ore that could be
-- smelted, and it tells me to buy bars". Minería no es una profesión del addon, pero su
-- fundición está en Data/Mining.lua para que la ruta de Herrería pueda fundir
test("Minería: solo la fundición, con lo que fabrica cada receta", function()
  local data = ES.Data.Mining
  expect(data and type(data.recipes) == "table", "sin ES.Data.Mining")
  local function Has(id, name, out, reagents)
    local r = data.recipes[id]
    expect(r, "falta %s (%d)", name, id)
    expect_eq(r.out and r.out[1], out, name .. ": lo que fabrica")
    local got = {}
    for _, rq in ipairs(r.r) do got[rq[1]] = rq[2] end
    for item, qty in pairs(reagents) do expect_eq(got[item], qty, string.format("%s: material %d", name, item)) end
  end
  Has(10097, "Smelt Mithril", 3860, { [3858] = 1 })
  Has(2659, "Smelt Bronze", 2841, { [2840] = 1, [3576] = 1 })
  Has(3569, "Smelt Steel", 3859, { [3575] = 1, [3857] = 1 })
  local bad, n = {}, 0
  for id, r in pairs(data.recipes) do
    n = n + 1
    if not r.out then bad[#bad + 1] = string.format("%d %s: sin out", id, tostring(r.name)) end
    if type(r.r) ~= "table" or #r.r == 0 then bad[#bad + 1] = string.format("%d %s: sin materiales", id, tostring(r.name)) end
    if r.fee or r.scroll or r.train then bad[#bad + 1] = string.format("%d %s: con instructor o pergamino", id, tostring(r.name)) end
  end
  Report(bad, "recetas de Minería raras")
  note("%d recetas de fundición", n)
  for _, p in ipairs(ES.PROFESSIONS) do expect(p.key ~= "Mining", "Minería no es una profesión del addon") end
end, { boot = false })

-- Un PNJ con sitio: { nombre, facción, zona, x, y [, ...] }
local function HasPlace(npc)
  local e = ES.Data.NPCs[npc]
  return type(e) == "table" and type(e[1]) == "string" and type(e[3]) == "number" and e[3] > 0
    and type(e[4]) == "number" and type(e[5]) == "number"
end

test("instructores, vendedores, buzones y banqueros tienen sitio", function()
  local bad = {}
  local function Check(npc, what)
    if not HasPlace(npc) then
      local e = ES.Data.NPCs[npc]
      bad[#bad + 1] = string.format("%s %s (%s)", what, tostring(npc), e and tostring(e[1]) or "no está en ES.Data.NPCs")
    end
  end
  for _, prof in ipairs(ProfessionKeys()) do
    for _, tr in ipairs(ES.Data[prof].trainers) do Check(tr[1], "instructor de " .. prof) end
  end
  for item, list in pairs(ES.Data.MatVendors or {}) do
    for _, npc in ipairs(list) do Check(npc, "vendedor de " .. item) end
  end
  for _, npc in ipairs(ES.Data.Mailboxes or {}) do Check(npc, "buzón") end
  for _, npc in ipairs(ES.Data.Bankers or {}) do Check(npc, "banquero") end
  -- (los robots de ingeniero no tienen sitio fijo; se guarda la lista, uno nuevo sale
  -- como cambio de la instantánea)
  table.sort(bad)
  note("%d PNJ sin sitio", #bad)
  snapshot("PNJ sin sitio", bad)
end, { boot = false })

-- Los vendedores a los que puede llevar una ruta no mandan a nadie a la capital del otro
-- bando: la ruta solo elige los de tu bando o neutrales (WP.Usable), así que un neutral
-- ("") dentro de una capital llevaría allí a los dos bandos, y uno de un bando en la
-- capital del otro es un dato mal generado. Los de bando raro ("X") no salen en ninguna
-- ruta: solo se cuentan
local CAPITALS = { [1453] = "A", [1455] = "A", [1457] = "A", [1454] = "H", [1456] = "H", [1458] = "H" }
test("vendedores: ninguno lleva a la capital del otro bando", function()
  local bad, odd, seen = {}, {}, {}
  local function Check(npc, what)
    if seen[npc] then return end
    seen[npc] = true
    local e = ES.Data.NPCs[npc]
    if not e then return end -- (lo mira «instructores, vendedores... tienen sitio»)
    local capital, side = CAPITALS[e[3]], e[2]
    if capital and side ~= capital then
      bad[#bad + 1] = string.format("%s %d %s: bando %q en una capital de %s (mapa %d)", what, npc, tostring(e[1]), tostring(side), capital, e[3])
    elseif side ~= "A" and side ~= "H" and side ~= "" then
      odd[#odd + 1] = string.format("%d %s (%s)", npc, tostring(e[1]), tostring(side))
    end
  end
  for item, list in pairs(ES.Data.MatVendors or {}) do
    for _, npc in ipairs(list) do Check(npc, "vendedor de " .. item) end
  end
  for item, s in pairs(ES.Data.ItemSources or {}) do
    for _, npc in ipairs(s.v or {}) do Check(npc, "vendedor de " .. item) end
  end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  table.sort(odd)
  note("%d vendedores; de bando raro, nunca en rutas: %s", n, #odd > 0 and table.concat(odd, ", ") or "ninguno")
  Report(bad, "vendedores que mandarían a la capital del otro bando")
end, { boot = false })

test("fuentes: vendedores y misiones que existen", function()
  local bad = {}
  for item, s in pairs(ES.Data.ItemSources) do
    for _, v in ipairs(s.v or {}) do
      if not ES.Data.NPCs[v] then bad[#bad + 1] = string.format("objeto %d: vendedor %s", item, tostring(v)) end
    end
    for _, q in ipairs(s.q or {}) do
      if not ES.Data.Quests[q] then bad[#bad + 1] = string.format("objeto %d: misión %s", item, tostring(q)) end
    end
  end
  Report(bad, "fuentes que apuntan a lo que no existe")
end, { boot = false })

test("los pergaminos de receta tienen de dónde salir", function()
  local bad = {}
  Each(function(prof, id, r)
    if r.scroll and not (ES.Data.ItemSources[r.scroll] or r.favor or r.gone) then
      bad[#bad + 1] = string.format("%s %d %s: pergamino %s", prof, id, tostring(r.name), tostring(r.scroll))
    end
  end)
  -- (botín del mundo que QuestieDB no tiene: sale como «dónde: desconocido» en la
  -- Colección. Se guarda cuántos, por profesión: si crece, el generador ha perdido fuentes)
  local byProf = {}
  for _, line in ipairs(bad) do local prof = line:match("^(%S+)") byProf[prof] = (byProf[prof] or 0) + 1 end
  note("%d pergaminos sin fuente conocida", #bad)
  snapshot("pergaminos sin fuente, por profesión", byProf)
end, { boot = false })

test("cajas de Merchant's Favor: rellenos con objeto, cantidad y nombre", function()
  local bad = {}
  expect(#ES.Data.Crates > 0, "sin cajas")
  for _, c in ipairs(ES.Data.Crates) do
    if type(c.id) ~= "number" or type(c.favor) ~= "number" or c.favor <= 0 then bad[#bad + 1] = "caja " .. tostring(c.id) .. ": favor" end
    if type(c.fills) ~= "table" or #c.fills == 0 then bad[#bad + 1] = "caja " .. tostring(c.id) .. ": sin rellenos" end
    for _, f in ipairs(c.fills or {}) do
      if type(f[1]) ~= "number" or type(f[2]) ~= "number" or f[2] <= 0 then
        bad[#bad + 1] = string.format("caja %s: relleno {%s, %s}", tostring(c.id), tostring(f[1]), tostring(f[2]))
      elseif not ES.Data.ItemNames[f[1]] then
        bad[#bad + 1] = string.format("caja %s: relleno %d sin nombre", tostring(c.id), f[1])
      end
    end
  end
  Report(bad, "cajas raras")
end, { boot = false })

test("herramientas: cada una con su objeto", function()
  local bad = {}
  for id, t in pairs(ES.Data.Tools or {}) do
    if type(t) ~= "table" or type(t.item) ~= "number" then bad[#bad + 1] = "herramienta " .. tostring(id) end
  end
  Each(function(prof, id, r)
    for _, key in ipairs({ "tool", "tool2" }) do
      if r[key] and not ES.Data.Tools[r[key]] then
        bad[#bad + 1] = string.format("%s %d %s: %s %s no está en ES.Data.Tools", prof, id, tostring(r.name), key, tostring(r[key]))
      end
    end
  end)
  Report(bad, "herramientas sin datos")
end, { boot = false })

test("precios de vendedor: enteros positivos", function()
  local bad = {}
  for id, p in pairs(ES.Data.VendorPrices or {}) do
    if type(p) ~= "number" or p <= 0 or p ~= math.floor(p) then bad[#bad + 1] = string.format("%d: %s", id, tostring(p)) end
  end
  for id, p in pairs(ES.Data.SellPrices or {}) do
    if type(p) ~= "number" or p < 0 or p ~= math.floor(p) then bad[#bad + 1] = string.format("venta %d: %s", id, tostring(p)) end
  end
  Report(bad, "precios raros")
end, { boot = false })

test("la prueba de los colores detecta una receta desordenada", function()
  -- (en una copia en memoria: así se sabe que la de arriba de verdad comprueba)
  local id, r = next(ES.Data.Cooking.recipes)
  local saved = r.t
  r.t = { saved[1], saved[1] - 1, saved[3], saved[4] }
  local ok = saved[1] - 1 >= saved[1]
  local found = false
  Each(function(prof, rid, rr) if rid == id and rr.t[2] < rr.t[1] then found = true end end)
  r.t = saved
  expect(found and not ok, "no se detectó la receta desordenada")
end, { boot = false })
