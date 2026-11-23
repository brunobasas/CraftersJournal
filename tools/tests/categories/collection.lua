-- Colección de recetas: cuántas tienes de cada profesión y dónde conseguir las demás

for _, state in ipairs({ "empty", "scan", "full" }) do
  test("la portada y la colección de cada profesión se abren: " .. state, function()
    OpenPage("patterns")
    for _, prof in ipairs(ProfessionKeys()) do
      ES:SelectPage("pattern:" .. prof)
      RunTimers()
      expect(ES:GetMainFrame().pages["pattern:" .. prof]:IsShown(), "la colección de %s no se ve", prof)
    end
  end, { state = state })
end

test("las cuentas de una profesión cuadran", function()
  local known = {}
  local n = 0
  for id, r in pairs(ES.Data.Tailoring.recipes) do
    if r.fee and n < 7 then KNOWN_SPELLS[id], known[id], n = true, true, n + 1 end
  end
  SKILLS[ES.Data.Tailoring.skillLine] = { 120, 150 }
  local res = ES.Collection:Build("Tailoring")
  expect_eq(res.total, #res.entries, "total = recetas listadas")
  local k, sumTotal, sumKnown = 0, 0, 0
  for _, e in ipairs(res.entries) do
    if e.known then k = k + 1 end
    expect(e.known == (KNOWN_SPELLS[e.id] == true), "%s: sabida %s", tostring(e.recipe.name), tostring(e.known))
    expect(res.by[e.main], "%s: fuente %s desconocida", tostring(e.recipe.name), tostring(e.main))
  end
  for _, b in pairs(res.by) do sumTotal, sumKnown = sumTotal + b.total, sumKnown + b.known end
  expect_eq(res.known, k, "sabidas")
  expect_eq(res.known, 7, "sabidas (las 7 marcadas)")
  expect_eq(sumTotal, res.total, "suma por fuente")
  expect_eq(sumKnown, res.known, "sabidas por fuente")
  local pk, pt = ES.Collection:Progress("Tailoring")
  expect_eq(pk, 7, "progreso de la portada: sabidas")
  expect(pt >= res.total - 50 and pt > 0, "progreso de la portada: total %d (colección %d)", pt, res.total)
end)

test("una receta de instructor que no tienes: dónde y si ya puedes aprenderla", function()
  SKILLS[ES.Data.Tailoring.skillLine] = { 100, 150 }
  local res = ES.Collection:Build("Tailoring")
  local found
  for _, e in ipairs(res.entries) do
    if not e.known and e.recipe.fee and e.recipe.train and e.recipe.train <= 100 then found = e break end
  end
  expect(found, "ninguna receta de instructor por debajo de 100")
  local trainer = false
  for _, s in ipairs(found.sources) do if s.kind == "trainer" then trainer = true end end
  expect(trainer, "%s no dice que es de instructor", tostring(found.recipe.name))
  expect(found.learnableNow, "%s (instructor, nivel %d) no sale como que ya puedes aprenderla", tostring(found.recipe.name), found.recipe.train)
  expect(#res.next > 0, "sin «siguientes recetas»")
end)

-- Spec recipe-requirements: los pergaminos que piden especialización lo dicen, como las
-- de instructor (antes solo salía en las de instructor)
test("una receta de pergamino de especialización dice cuál pide", function()
  SKILLS[ES.Data.Leatherworking.skillLine] = { 250, 300 }
  OpenPage("patterns")
  ES:SelectPage("pattern:Leatherworking")
  RunTimers()
  local frame = ES:GetMainFrame().pages["pattern:Leatherworking"].collectionFrame
  expect(frame and frame.data, "la colección de Peletería no se ha pintado")
  local e
  for _, x in ipairs(frame.data.entries) do if x.id == 19066 then e = x end end -- Frostsaber Boots
  expect(e, "Frostsaber Boots no está en la colección de Peletería")
  expect(e.recipe.scroll, "Frostsaber Boots no es de pergamino: la prueba no prueba nada")
  ES:SelectCollectionEntry(frame, e)
  RunTimers()
  local want = string.format(ES.L["solo con la especialización %s"], "Tribal")
  expect(AllText():find(want, 1, true), "la ficha de Frostsaber Boots no dice «%s»", want)
end)

test("una receta de especialización que no tienes no sale como «puedes aprenderla ya»", function()
  SKILLS[ES.Data.Engineering.skillLine] = { 270, 300 }
  local function Entry()
    for _, e in ipairs(ES.Collection:Build("Engineering").entries) do
      if e.id == 12758 then return e end -- Goblin Rocket Helmet (instructor de Goblin, 245)
    end
  end
  local e = expect(Entry(), "Goblin Rocket Helmet no está en la colección")
  expect(not e.learnableNow, "sin Goblin Engineering, Goblin Rocket Helmet sale como «puedes aprenderla ya»")
  KNOWN_SPELLS[20222] = true -- Goblin Engineering
  expect(Entry().learnableNow, "con Goblin Engineering, Goblin Rocket Helmet no sale como «puedes aprenderla ya»")
end)

-- Spec recipe-search: en español la receta 6695 se llama «Mochila negra de seda» (como en
-- la ventana de profesión), pero lo que fabrica es la «Talega de seda negra» (5765)
local function SearchTailoring(text)
  ES:SetLanguage("es")
  OpenPage("patterns")
  ES:SelectPage("pattern:Tailoring")
  RunTimers()
  local frame = ES:GetMainFrame().pages["pattern:Tailoring"].collectionFrame
  expect(frame, "la colección de Sastrería no se ha pintado")
  frame.search:SetText(text)
  ES:RenderCollection(frame)
  for _, e in ipairs(frame.list or {}) do
    if e.id == 6695 then return e, frame end
  end
  return nil, frame
end

test("buscar «talega» en Recetas encuentra la Mochila negra de seda", function()
  local e, frame = SearchTailoring("talega")
  expect(e, "«talega» no encuentra la receta 6695 (%d recetas en la lista)", #(frame.list or {}))
  expect_eq(e.recipe.name, "Mochila negra de seda", "nombre que se muestra")
  expect(AllText():find("Mochila negra de seda", 1, true), "la fila no dice «Mochila negra de seda»")
end)

test("buscar en Recetas no depende de que el juego tenga el objeto cargado", function()
  UNCACHED[5765], UNCACHED[2325] = true, true -- Talega de seda negra y Tinte negro
  expect(SearchTailoring("tinte negro"), "sin caché, «tinte negro» (material) no encuentra la receta 6695")
  expect(SearchTailoring("talega"), "sin caché, «talega» no encuentra la receta 6695")
end)

-- Mooncloth Bag pide 1 Mooncloth, que se fabrica con 2 Felcloth pero tiene enfriamiento
-- (una cada pocos días). Salía a 93s (2 Felcloth) en vez de los 60g de la AH
local function SetPrice(itemID, price)
  ES.db.scans[ES:RealmKey()].items[itemID] = { listings = 5, quantity = 50, minUnit = price, avgUnit = price,
    sellers = 3, topShare = 0.3, median = price, ladder = { price, 50 } }
end

local function MoonclothCost()
  for _, e in ipairs(ES.Collection:Build("Tailoring").entries) do
    if e.id == 18445 then -- Mooncloth Bag
      for _, rg in ipairs(e.reagents or {}) do
        if rg.item == 14342 then return rg.cost, rg.kinds end
      end
    end
  end
end

test("un material con enfriamiento (Mooncloth) se compra en la AH, no se fabrica", function()
  SetPrice(14256, 4694)    -- Felcloth: 46s 94c
  SetPrice(14342, 609999)  -- Mooncloth: 60g 99s 99c
  local cost, kinds = MoonclothCost()
  expect_eq(cost, 609999, "Mooncloth de la Mooncloth Bag")
  expect(kinds and kinds.ah, "la Mooncloth no sale comprada en la AH")
  -- Si no hay ninguna a la venta, se fabrica igual (2 Felcloth)
  ES.db.scans[ES:RealmKey()].items[14342] = nil
  cost = MoonclothCost()
  expect_eq(cost, 2 * 4694, "sin Mooncloth en la AH: fabricada")
end)

test("las recetas sabidas se guardan por personaje", function()
  SKILLS[ES.Data.Cooking.skillLine] = { 50, 75 }
  for id in pairs(ES.Data.Cooking.recipes) do KNOWN_SPELLS[id] = true break end
  ES.Collection:SaveKnown("Cooking")
  local mine = ES.db.known and ES.db.known[ES:CharKey()]
  expect(mine and mine.Cooking and #mine.Cooking >= 1, "no se guardaron")
end)

-- Por nombre y GUID, no por reino (el cliente de Forever ya no lo da: Keys.lua). En
-- Forever dos personajes de la cuenta pueden llamarse igual
test("recetas sabidas: dos personajes con el mismo nombre, y el alter sale con su nombre", function()
  SKILLS[ES.Data.Cooking.skillLine] = { 50, 75 }
  local first
  for id in pairs(ES.Data.Cooking.recipes) do first = id break end
  KNOWN_SPELLS[first] = true
  local guid = UnitGUID
  UnitGUID = function(u) if u == "player" then return "Player-6940-0000AAAA" end end
  ES.Collection:SaveKnown("Cooking")
  UnitGUID = function(u) if u == "player" then return "Player-6945-0000BBBB" end end
  KNOWN_SPELLS[first] = nil
  ES.Collection:SaveKnown("Cooking")
  local a, b = ES.db.known["Bruno-Player-6940-0000AAAA"], ES.db.known["Bruno-Player-6945-0000BBBB"]
  expect(a and b, "no se guardaron aparte")
  expect(#a.Cooking == #b.Cooking + 1, "uno pisó al otro (%d y %d recetas)", #a.Cooking, #b.Cooking)
  -- El segundo (no la sabe) ve que el primero sí, con su nombre
  local e
  for _, x in ipairs(ES.Collection:Build("Cooking").entries) do if x.id == first then e = x end end
  UnitGUID = guid
  e = expect(e, "la receta no sale en la colección")
  expect_eq(table.concat(e.alts or {}, ","), "Bruno", "alters que la saben")
end)
