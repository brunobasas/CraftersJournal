-- Inventario: qué vender de tus bolsas, dónde (vendedor o AH) y qué guardar

local function Entry(list, itemID)
  for _, e in ipairs(list) do if e.itemID == itemID then return e end end
end

for _, state in ipairs({ "empty", "scan", "full" }) do
  test("la pestaña se abre: " .. state, function()
    BAGS[2589], BAGS[2318], BAGS[4306] = 12, 5, 3
    OpenPage("inventory")
    expect(ES:GetMainFrame().pages.inventory:IsShown(), "la página no se ve")
  end, { state = state })
end

test("cada objeto: lo que se guarda y lo que se vende suman lo que llevas", function()
  BAGS[2589], BAGS[2318], BAGS[2592], BAGS[4306], BAGS[2934], BAGS[2320] = 40, 12, 20, 7, 30, 5
  local list = ES.Inventory:List()
  expect(#list > 0, "no propone nada")
  for _, e in ipairs(list) do
    local where = "objeto " .. e.itemID
    local sold = (e.vendorN or 0) + (e.ahN or 0) + (e.ahLater or 0)
    expect(e.keep >= 0 and e.keep <= e.count, "%s: guarda %s de %s", where, tostring(e.keep), tostring(e.count))
    expect(sold <= e.count - e.keep, "%s: vende %d y guarda %d de %d", where, sold, e.keep, e.count)
    expect_near(e.value, (e.ahN or 0) * (e.ahUnit or 0) + (e.vendorN or 0) * (e.vendorUnit or 0), 0.5, where .. ": valor")
    expect_finite(e.value, where .. ": valor")
  end
  note("%d objetos en la lista", #list)
end)

-- CurseForge: querían anunciar siempre a 2 h en vez de 8. Automática (por defecto): 24 h
-- lo que se vende bien y 8 h lo demás; fijada en las opciones, esa para todo, y el
-- depósito con ella
test("duración de las subastas: automática según las alertas, o la de las opciones", function()
  BAGS[2589], BAGS[2318], BAGS[2592], BAGS[4306], BAGS[2934], BAGS[2320] = 40, 12, 20, 7, 30, 5
  local function OnAH()
    local out = {}
    for _, e in ipairs(ES.Inventory:List()) do if e.hours then out[#out + 1] = e end end
    return out
  end
  local auto = OnAH()
  expect(#auto > 0, "ningún objeto tiene precio de la AH")
  for _, e in ipairs(auto) do
    expect_eq(e.hours, e.verdict == "good" and 24 or 8, "automática, objeto " .. e.itemID .. " (" .. tostring(e.verdict) .. ")")
  end
  for _, h in ipairs({ 2, 8, 24 }) do
    ES.db.auctionHours = h
    for _, e in ipairs(OnAH()) do
      local where = h .. " h, objeto " .. e.itemID
      expect_eq(e.hours, h, where)
      local perUnit = ES.Planner.AuctionCosts(ES:VendorSellPrice(e.itemID) or 0, { hours = h, neutral = ES:IsNeutralAH() })
      expect_near(e.depositUnit, perUnit, 0.001, where .. ": depósito")
    end
  end
  ES.db.auctionHours = "x" -- (un valor que no es una duración: automática)
  for _, e in ipairs(OnAH()) do expect_eq(e.hours, e.verdict == "good" and 24 or 8, "valor raro, objeto " .. e.itemID) end
  ES.db.auctionHours = nil
  note("%d objetos a la AH", #auto)
end)

test("lo que marcas para no vender nunca se guarda entero", function()
  BAGS[2318] = 12
  ES.Inventory.SetNeverSell(2318, true)
  local e = expect(Entry(ES.Inventory:List(), 2318), "Light Leather no sale en la lista")
  expect_eq(e.keep, 12, "Light Leather guardada")
  expect_eq(e.vendorN + e.ahN + (e.ahLater or 0), 0, "Light Leather vendida")
end)

test("lo gris va siempre al vendedor", function()
  BAGS[4306] = 7
  BAG_FLAGS[4306] = { quality = 0 }
  local e = expect(Entry(ES.Inventory:List(), 4306), "no sale en la lista")
  expect_eq(e.ahN, 0, "a la AH")
  expect_eq(e.vendorN, 7, "al vendedor")
end)

test("sin precio de la AH: al vendedor, y lo dice", function()
  BAGS[4306] = 7
  ES.db.scans[ES:RealmKey()].items[4306] = nil
  local e = expect(Entry(ES.Inventory:List(), 4306), "no sale en la lista")
  expect(e.noAH, "no dice que no hay precio de la AH")
  expect_eq(e.vendorN, 7, "al vendedor")
end)

test("precio de respaldo de Auctionator: solo en el modo de escaneo Auctionator", function()
  ES.db.scans[ES:RealmKey()].items[4306] = nil -- (tu escaneo no lo tiene)
  InstallAuctionator()
  AUCTIONATOR_LATEST = { [4306] = { price = 500, age = 0 } }
  local p = expect(ES.Market:AddonPrice(4306), "con Auctionator, sin su precio de respaldo")
  expect_eq(p.source, "Auctionator", "fuente")
  expect_eq(p.price, 500, "precio")
  ES:SetOption("noAuctionator", false)
  expect_eq(ES.Market:AddonPrice(4306), nil, "con la opción desactivada, se usa el precio de Auctionator")
end)

test("lo que pide tu ruta empezada se guarda", function()
  local page, plan = StartRoute("Tailoring", 1, 75)
  local need = ES.Planner.RouteNeed("Tailoring", plan, 1, { keep = true })
  local itemID, n = next(need)
  expect(itemID, "la ruta no pide nada")
  BAGS[itemID] = n.need + 3
  local e = expect(Entry(ES.Inventory:List(), itemID), "el material no sale en la lista")
  expect(e.keep >= math.ceil(n.need - 0.001), "guarda %d y la ruta pide %s", e.keep, tostring(n.need))
end)

test("el pergamino de un paso futuro de tu ruta se guarda", function()
  -- (spec route-shopping-mode: Sastrería 100-175 compra en la AH el pergamino de la Capa
  -- de seda azur, de 148. Comprado y en las bolsas, no se propone venderlo)
  local AZURE_CLOAK_SCROLL = 7089
  ES.db.scans[ES:RealmKey()].items[AZURE_CLOAK_SCROLL] = { listings = 1, quantity = 1, minUnit = 1, avgUnit = 1, median = 1, ladder = { 1, 1 } }
  local _, plan = StartRoute("Tailoring", 100, 175)
  local uses = false
  for _, st in ipairs(plan.steps) do if st.recipe.scroll == AZURE_CLOAK_SCROLL then uses = true end end
  expect(uses, "la ruta ya no usa la Capa de seda azur: la prueba no prueba nada")
  BAGS[AZURE_CLOAK_SCROLL] = 1
  local e = expect(Entry(ES.Inventory:List(), AZURE_CLOAK_SCROLL), "el pergamino no sale en el Inventario")
  expect_eq(e.keep, 1, "pergaminos que se guardan")
  expect_eq((e.vendorN or 0) + (e.ahN or 0) + (e.ahLater or 0), 0, "pergaminos que se proponen vender")
end)

---------------------------------------------------------------------------
-- Bolsa de componentes (la 5 en Forever): cuenta como las demás bolsas
---------------------------------------------------------------------------
test("bolsa de componentes: CarriedBags la incluye, y sin Enum no se toma la 1.ª del banco", function()
  local bags = ES.CarriedBags()
  expect_eq(bags[#bags], 5, "última bolsa con Enum.BagIndex.ReagentBag")
  expect_eq(ES.ReagentBag(), 5, "ES.ReagentBag")
  Enum = nil
  NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
  bags = ES.CarriedBags()
  expect_eq(#bags, 6, "bolsas con NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5")
  expect_eq(bags[#bags], 5, "última bolsa con NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5")
  NUM_TOTAL_EQUIPPED_BAG_SLOTS = nil
  bags = ES.CarriedBags()
  expect_eq(#bags, 5, "bolsas de un cliente sin bolsa de componentes")
  expect(ES.ReagentBag() == nil, "sin bolsa de componentes, ES.ReagentBag da %s", tostring((ES.ReagentBag())))
end)

test("bolsa de componentes: lo que hay en ella sale en la pestaña y se cuenta", function()
  BAGS[2589] = 10
  REAGENT_BAG[2589], REAGENT_BAG[2318] = 30, 12
  local cloth = expect(Entry(ES.Inventory:List(), 2589), "Linen Cloth no sale en la lista")
  expect_eq(cloth.count, 40, "Linen Cloth en las dos bolsas")
  local leather = expect(Entry(ES.Inventory:List(), 2318), "Light Leather (solo en la de componentes) no sale")
  expect_eq(leather.count, 12, "Light Leather")
  expect_eq(ES.Ledger.BagCount(2318), 12, "BagCount (lo que se anuncia en la AH)")
end)

test("bolsa de componentes: el vendedor vende lo que hay en ella", function()
  REAGENT_BAG[4306] = 7
  BAG_FLAGS[4306] = { quality = 0 }
  OpenPage("inventory")
  OpenMerchant({})
  local list = ES.VendorShop:SellList()
  local e = expect(Entry(list, 4306), "la ventana del vendedor no propone lo de la bolsa de componentes")
  expect_eq(e.n, 7, "unidades a vender")
  ES.VendorShop:Sell(list)
  RunTimers()
  expect(REAGENT_BAG[4306] == 0, "no se vendió (quedan %s)", tostring(REAGENT_BAG[4306]))
end)

test("bolsa de componentes: con las normales llenas, la pila partida va a ella", function()
  local free = C_Container.GetContainerNumFreeSlots
  C_Container.GetContainerNumFreeSlots = function(bag)
    if bag <= 4 then return 0, 0 end
    return free(bag)
  end
  REAGENT_BAG[2589] = 3
  local bag, slot = ES.Ledger.EmptySlot()
  expect_eq(bag, 5, "bolsa del hueco libre")
  expect_eq(slot, 2, "casilla del hueco libre (la 1 está ocupada)")
end)

test("vender al vendedor: con él abierto, el botón vende lo de esa sección", function()
  BAGS[4306] = 7
  BAG_FLAGS[4306] = { quality = 0 }
  OpenPage("inventory")
  OpenMerchant({})
  local sec = ES.Inventory:Sections()
  expect(sec.vendor and #sec.vendor > 0, "nada que vender al vendedor")
  ES.VendorShop:Sell(ES.VendorShop:SellList())
  RunTimers()
  expect(BAGS[4306] == 0, "no se vendió el gris (quedan %s)", tostring(BAGS[4306]))
end)
