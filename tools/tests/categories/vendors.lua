-- Vendedores e instructores: comprar justo lo que falta y aprender con un clic

-- Un material de la lista de compra (la de la ruta entera) que se compra al vendedor
local function VendorMaterial()
  local best
  for _, s in ipairs(ES.Shopping.Status().lists) do
    for _, e in ipairs(s.items) do
      if e.it.source == "vendor" and (not best or e.it.itemID < best) then best = e.it.itemID end
    end
  end
  return best
end

-- La ruta de Sastrería de 1 a 125, con la lista de la ruta entera (no por tramos)
local function TailoringRoute()
  ES.db.prof.Tailoring = ES.db.prof.Tailoring or {}
  ES.db.prof.Tailoring.byPhase = false
  return StartRoute("Tailoring", 1, 125)
end

test("vendedor abierto sin ruta: ventana sin errores", function()
  OpenMerchant({ { item = 2320, price = 10 }, { item = 2324, price = 25 } })
  ES.VendorShop:Refresh()
  expect_eq(#ES.VendorShop:List(), 0, "sin ruta ni lista no hay nada que comprar")
  CloseMerchant()
end, { state = "scan" })

test("vendedor abierto: ofrece justo lo que falta y lo compra", function()
  TailoringRoute()
  local itemID = VendorMaterial()
  expect(itemID, "la ruta de Sastrería no pide nada de vendedor")
  local list
  OpenMerchant({ { item = itemID, price = ES.Data.VendorPrices[itemID] } })
  list = ES.VendorShop:List()
  local e = expect(list[1], "el vendedor no ofrece %d", itemID)
  expect_eq(e.itemID, itemID, "material")
  BAGS[itemID] = 1
  list = ES.VendorShop:List()
  e = list[1]
  expect_eq(e.qty, e.need - 1, "con 1 en las bolsas, lo que falta")
  ES.VendorShop:Buy(e)
  RunTimers()
  expect_eq(BAGS[itemID], e.need, "unidades tras comprar")
  local again = ES.VendorShop:List()[1]
  expect_eq(again and again.qty, 0, "tras comprar ya no falta nada")
  note("material %d: pedía %d", itemID, e.need)
end, { state = "scan" })

test("vendedor que también vende un pergamino que la ruta compra en la AH: no lo propone", function()
  -- (spec route-shopping-mode: el pergamino de la Bolsa roja de lana, a 1c en la AH, va
  -- a la Lista de compra con la AH; el vendedor de recetas no lo ofrece)
  local RED_BAG_SCROLL = 5772
  ES.db.scans[ES:RealmKey()].items[RED_BAG_SCROLL] = { listings = 1, quantity = 1, minUnit = 1, avgUnit = 1, median = 1, ladder = { 1, 1 } }
  ES.db.prof.Tailoring = ES.db.prof.Tailoring or {}
  ES.db.prof.Tailoring.byPhase = false
  StartRoute("Tailoring", 100, 175)
  local scroll
  for _, s in ipairs(ES.Shopping.Status().lists) do
    for _, e in ipairs(s.items) do if e.it.itemID == RED_BAG_SCROLL then scroll = e end end
  end
  expect(scroll, "la lista no pide el pergamino de la Bolsa roja de lana: la prueba no prueba nada")
  OpenMerchant({ { item = RED_BAG_SCROLL, price = 500 } })
  for _, e in ipairs(ES.VendorShop:List()) do
    expect(e.itemID ~= RED_BAG_SCROLL, "la ventana del vendedor propone el pergamino que la ruta compra en la AH")
  end
  CloseMerchant()
end, { state = "scan" })

test("vendedor que vende por lotes: compra lotes enteros", function()
  TailoringRoute()
  local itemID = VendorMaterial()
  expect(itemID, "sin material de vendedor")
  OpenMerchant({ { item = itemID, price = 50, batch = 5 } })
  local e = expect(ES.VendorShop:List()[1], "no lo ofrece")
  expect_eq(e.qty % 5, 0, "lotes de 5")
  expect(e.qty >= e.need, "compra %d y faltan %d", e.qty, e.need)
end, { state = "scan" })

test("instructor abierto: apunta los precios que enseña", function()
  -- Un instructor de Sastrería con dos recetas de los datos
  local recipes = {}
  for id, r in pairs(ES.Data.Tailoring.recipes) do
    if r.fee and #recipes < 2 then recipes[#recipes + 1] = { id = id, r = r } end
  end
  local services = {}
  for i, x in ipairs(recipes) do
    services[i] = { name = x.r.nameEN or x.r.name, kind = "available", cost = 1234 + i, skill = x.r.train or 1, spell = x.id }
  end
  GetNumTrainerServices = function() return #services end
  GetTrainerServiceInfo = function(i) local s = services[i] return s.name, "", s.kind end
  GetTrainerServiceCost = function(i) return services[i].cost end
  GetTrainerServiceSkillReq = function(i) return "Tailoring", services[i].skill, true end
  GetTrainerServiceSkillLine = function() return ES:ProfLabel("Tailoring") end -- (en el idioma del cliente)
  GetTrainerServiceItemLink = function() return nil end
  GetTrainerServiceLink = function(i) return "|Hspell:" .. services[i].spell .. "|h[x]|h" end
  GetTrainerServiceTypeFilter = function() return true end
  SetTrainerServiceTypeFilter = function() end
  FireEvent("TRAINER_SHOW")
  RunTimers()
  local fees = ES.db.trainerFees or {}
  local seen = 0
  for _, x in ipairs(recipes) do if fees[x.id] then seen = seen + 1 end end
  note("precios apuntados: %d de %d", seen, #recipes)
  expect_eq(seen, #recipes, "recetas con el precio del instructor")
  FireEvent("TRAINER_CLOSED")
end, { state = "scan" })

-- Filas de compra al vendedor: cada una lleva a quien vende todo lo suyo ------------
-- Discord: First Aid 140-150 (Simple Poultice, Horda) mandaba a Barkeep Morag a por
-- Mild Spices y Bottle of Dalaran Noir; Morag solo vende el Bottle

local MILD_SPICES, DALARAN_NOIR, MORAG = 2678, 2723, 5611
-- Vendedores inventados: A1 de la Alianza; H1, H2, H3 de la Horda
local A1, H1, H2, H3 = 990001, 990002, 990003, 990004

-- Personaje de la Horda con el escaneo de la AH (el escaneo se guarda por reino y
-- bando: hay que elegir el bando antes de arrancar)
local function BootHorde()
  FACTION = "Horde"
  Boot("scan")
end

-- Posiciones simuladas (sin ellas, entre varios vendedores no se elige ninguno): un
-- continente; cada mapa, 10 unidades más allá. Estás en `map` (x, y)
local function MockPositions(map, x, y)
  CreateVector2D = function(a, b) return { x = a, y = b } end
  C_Map = C_Map or {}
  C_Map.GetWorldPosFromMapPos = function(m, v)
    local wx, wy = m * 10 + v.x, v.y
    return 1, { GetXY = function() return wx, wy end }
  end
  UnitPosition = function() return map * 10 + x, y, 0, 1 end
end

-- Materiales inventados: 900001 lo venden A1 y H1; 900002, A1 y H2 (juntos, solo A1);
-- 900003 solo A1; 900004 solo H3; 900005, H3 y H2
local function FakeVendors()
  local N, M = ES.Data.NPCs, ES.Data.MatVendors
  N[A1] = { "Vendedor de la Alianza", "A", 1453, 0.5, 0.5 }
  N[H1] = { "Vendedor de la Horda 1", "H", 1454, 0.4, 0.4 }
  N[H2] = { "Vendedor de la Horda 2", "H", 1454, 0.6, 0.6 }
  N[H3] = { "Vendedor de la Horda 3", "H", 1454, 0.7, 0.7 }
  M[900001], M[900002], M[900003] = { A1, H1 }, { A1, H2 }, { A1 }
  M[900004], M[900005] = { H3 }, { H3, H2 }
end

local function Has(list, x)
  for _, v in ipairs(list or {}) do if v == x then return true end end
  return false
end

local function GroupsText(groups)
  local parts = {}
  for _, g in ipairs(groups) do parts[#parts + 1] = "{" .. table.concat(g, ",") .. "}" end
  return table.concat(parts, " ")
end

test("vendedor de una fila: solo cuentan los de tu bando", function()
  BootHorde()
  MockPositions(1454, 0.5, 0.5)
  FakeVendors()
  -- Solo A1 (Alianza) vende los dos: antes ganaba él y la fila se quedaba sin destino
  local v = ES.Waypoints.VendorFor({ 900001, 900002 })
  expect(v == H1 or v == H2, "la fila lleva a %s, no a un vendedor de la Horda", tostring(v))
end, { boot = false })

test("materiales de vendedor: un grupo por vendedor que los vende", function()
  BootHorde()
  MockPositions(1454, 0.544, 0.68) -- (en la posada de Orgrimmar, al lado de Morag)
  FakeVendors()
  local WP = ES.Waypoints
  local groups = WP.VendorGroups({ MILD_SPICES, DALARAN_NOIR })
  expect_eq(GroupsText(groups), "{2678} {2723}", "Mild Spices y Bottle (nadie vende los dos)")
  local spices = WP.VendorFor(groups[1])
  expect(spices and spices ~= MORAG and Has(WP.Vendors(MILD_SPICES), spices),
    "la fila de Mild Spices lleva a %s, que no las vende", tostring(spices))
  expect(Has(WP.Vendors(DALARAN_NOIR), WP.VendorFor(groups[2])), "la fila del Bottle no lleva a quien lo vende")
  -- Morag vende los dos: una sola fila
  expect_eq(GroupsText(WP.VendorGroups({ DALARAN_NOIR, 2596 })), "{2723,2596}", "dos que vende Morag")
  -- Lo que solo vende la Alianza, aparte y al final, sin destino
  groups = WP.VendorGroups({ 900003, 900004 })
  expect_eq(GroupsText(groups), "{900004} {900003}", "material sin vendedor de la Horda")
  expect_eq(WP.VendorFor(groups[2]), nil, "destino del grupo sin vendedor")
  -- Siempre el mismo reparto
  local ids = { MILD_SPICES, DALARAN_NOIR, 2596, 900001, 900002, 900005 }
  expect_eq(GroupsText(WP.VendorGroups(ids)), GroupsText(WP.VendorGroups(ids)), "dos llamadas iguales")
  note("%s", GroupsText(WP.VendorGroups(ids)))
end, { boot = false })

test("materiales de vendedor: lo que un vendedor no tenía pasa a otro grupo", function()
  BootHorde()
  MockPositions(1454, 0.5, 0.5)
  FakeVendors()
  local WP = ES.Waypoints
  expect_eq(GroupsText(WP.VendorGroups({ 900004, 900005 })), "{900004,900005}", "H3 vende los dos")
  WP.MarkVendorLacks(H3, 900005)
  local groups = WP.VendorGroups({ 900004, 900005 })
  expect_eq(GroupsText(groups), "{900004} {900005}", "H3 no tenía 900005")
  expect_eq(WP.VendorFor(groups[2]), H2, "900005, al otro que lo vende")
end, { boot = false })

test("filas de compra: una por vendedor cuando nadie lo vende todo", function()
  BootHorde()
  local function It(id) return { itemID = id, quantity = 1, need = 1, unit = 1, total = 1, source = "vendor" } end
  local groups = ES.UI.BuyGroups({ bank = {}, ah = {}, vendor = { It(MILD_SPICES), It(DALARAN_NOIR) } })
  local parts = {}
  for _, g in ipairs(groups) do
    local ids = {}
    for _, it in ipairs(g[2]) do ids[#ids + 1] = it.itemID end
    parts[#parts + 1] = g[1] .. ":" .. table.concat(ids, ",")
  end
  expect_eq(table.concat(parts, " "), "vendor:2678 vendor:2723", "filas")
end, { boot = false })

-- La ruta de First Aid de 140 a 150 por Simple Poultice (Horda, en Orgrimmar): la lana y
-- la Bruiseweed muy caras, para que no salgan Heavy Wool Bandage ni Healing Potion.
-- `known`: Simple Poultice ya aprendida (sin ella, la ruta pasa antes por el instructor
-- y lo del vendedor se compra al de al lado: ArrangeTrip)
local function PoulticeRoute(known)
  FACTION = "Horde"
  Fixtures.FIXED[2592], Fixtures.FIXED[2453], Fixtures.FIXED[3174] = 100000, 100000, 1
  if known then KNOWN_SPELLS[1259342] = true end
  Boot("scan")
  MockPositions(1454, 0.544, 0.68)
  local _, plan = StartRoute("FirstAid", 140, 150)
  expect_eq(plan.steps[1] and plan.steps[1].id, 1259342, "la ruta de prueba va por Simple Poultice")
end

-- Las filas de compra al vendedor de la ruta: [itemID] = fila (la de su material)
local function VendorRows()
  local rows = {}
  for _, l in ipairs(ES:RouteLines("FirstAid", { buy = true }) or {}) do
    if l.buyRow == "vendor" then
      for _, it in ipairs(l.buyItems) do rows[it.itemID] = l end
    end
  end
  return rows
end

for _, known in ipairs({ false, true }) do
  test("Simple Poultice: cada fila del vendedor lleva a quien vende lo suyo" .. (known and " (receta aprendida)" or " (al lado del instructor)"), function()
    PoulticeRoute(known)
    local WP = ES.Waypoints
    local rows = VendorRows()
    local spices, noir = rows[MILD_SPICES], rows[DALARAN_NOIR]
    expect(spices and noir, "faltan filas de Mild Spices o de Bottle")
    expect(spices ~= noir, "Mild Spices y Bottle en la misma fila: nadie vende los dos")
    local to = spices.go and spices.go()
    expect(to and to ~= MORAG and Has(WP.Vendors(MILD_SPICES), to), "la fila de Mild Spices lleva a %s", tostring(to))
    local toNoir = noir.go and noir.go()
    expect(Has(WP.Vendors(DALARAN_NOIR), toNoir), "la fila del Bottle lleva a %s", tostring(toNoir))
    note("Mild Spices: %s · Bottle: %s%s", WP.NPC(to).name, WP.NPC(toNoir).name, spices.nearTrainer and " (al lado del instructor)" or "")
  end, { boot = false })
end

test("Simple Poultice: saltar la fila de Mild Spices no salta la del Bottle", function()
  PoulticeRoute(true)
  local rows = VendorRows()
  expect(rows[MILD_SPICES].markHave, "la fila de Mild Spices no se puede saltar")
  rows[MILD_SPICES].markHave()
  rows = VendorRows()
  expect(rows[MILD_SPICES].skipped, "la fila de Mild Spices no sale como saltada")
  expect(not rows[DALARAN_NOIR].done, "la fila del Bottle también se saltó")
end, { boot = false })

-- (un hooksecurefunc mínimo, como el del juego: ProfessionUI.lua apunta las compras con él)
local function HookSecure()
  hooksecurefunc = function(t, name, fn)
    if type(t) == "string" then t, name, fn = _G, t, name end
    local orig = t[name]
    t[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
  end
end

test("Simple Poultice: cerrar a Morag no da por visitada la fila de Mild Spices", function()
  HookSecure()
  PoulticeRoute(true)
  local notEnough = ES.L["No había suficiente"]
  OpenMerchant({ { item = DALARAN_NOIR, price = 50 } }) -- (Morag: vende el Bottle, no las Mild Spices)
  BuyMerchantItem(1, 1)
  CloseMerchant()
  local rows = VendorRows()
  local spices, noir = rows[MILD_SPICES], rows[DALARAN_NOIR]
  expect(not spices.sub:find(notEnough, 1, true), "la fila de Mild Spices dice «No había suficiente»: %s", spices.sub)
  expect(not spices.done, "la fila de Mild Spices dejó de estar pendiente")
  expect(noir.sub:find(notEnough, 1, true), "la fila del Bottle no se dio por visitada: %s", noir.sub)
end, { boot = false })

test("Simple Poultice: cerrar a Morag sin comprar no dice «No había suficiente»", function()
  HookSecure()
  PoulticeRoute(true)
  local notEnough = ES.L["No había suficiente"]
  OpenMerchant({ { item = DALARAN_NOIR, price = 50 } })
  CloseMerchant()
  local noir = VendorRows()[DALARAN_NOIR]
  expect(not noir.sub:find(notEnough, 1, true), "la fila del Bottle dice «No había suficiente» sin comprar: %s", noir.sub)
end, { boot = false })

test("Simple Poultice: abrir a Morag deja como paso actual la fila del Bottle", function()
  PoulticeRoute(true)
  BAGS[3174] = 1000 -- (sin la compra de la AH delante: los dos recados son del vendedor)
  OpenMerchant({ { item = DALARAN_NOIR, price = 50 } })
  local cur
  for _, l in ipairs(ES:RouteLines("FirstAid", { buy = true }) or {}) do
    if l.current then cur = l break end
  end
  local id = cur and cur.buyItems and cur.buyItems[1] and cur.buyItems[1].itemID
  expect_eq(id, DALARAN_NOIR, "material de la fila actual con Morag abierto")
  CloseMerchant()
end, { boot = false })

test("vendedor con la lista sin cargar: no se apunta que le falta", function()
  PoulticeRoute(true)
  local guid, itemID = UnitGUID, GetMerchantItemID
  UnitGUID = function(u) if u == "npc" then return "Creature-0-0-0-0-" .. MORAG .. "-0" end return guid(u) end
  GetMerchantItemID = function() return nil end -- (el juego aún no lo ha cargado)
  OpenMerchant({ { item = DALARAN_NOIR, price = 50 } })
  local noir = VendorRows()[DALARAN_NOIR]
  local lacks = ES.Waypoints.vendorLacks[MORAG]
  expect(not (lacks and lacks[DALARAN_NOIR]), "Morag apuntado como sin Bottle antes de cargar su lista")
  expect(noir.onClick, "la fila del Bottle no compra aquí con la lista sin cargar")
  GetMerchantItemID = itemID
  CloseMerchant()
  UnitGUID = guid
end, { boot = false })

-- Cada venta o compra trae MERCHANT_UPDATE y BAG_UPDATE_DELAYED, y cada repintado repasa
-- todas tus bolsas (Inventory:List): antes se repintaba dos veces (PR #8)
test("vender o comprar: la ventana del vendedor se repinta una vez", function()
  OpenMerchant({ { item = 2320, price = 10 } })
  local V, n = ES.VendorShop, 0
  local refresh = V.Refresh
  V.Refresh = function(self, ...) n = n + 1 return refresh(self, ...) end
  FireEvent("MERCHANT_UPDATE")
  FireEvent("BAG_UPDATE_DELAYED")
  RunTimers()
  expect_eq(n, 1, "repintados de la ventana del vendedor por una venta")
  CloseMerchant()
end, { state = "scan" })
