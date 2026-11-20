-- Calculadora: cuánto ganas con una receta, como en una hoja de cálculo

local Calc

local function SetPrice(itemID, price, qty)
  local scan = ES.db.scans[ES:RealmKey()]
  qty = qty or 50
  scan.items[itemID] = { listings = 5, quantity = qty, minUnit = price, avgUnit = price, sellers = 3, topShare = 0.3,
    median = price, ladder = { price, qty } }
end

for _, state in ipairs({ "empty", "scan", "full" }) do
  test("la pestaña se abre: " .. state, function()
    OpenPage("calc")
    expect(ES:GetMainFrame().pages.calc:IsShown(), "la página no se ve")
  end, { state = state })
end

test("con un cálculo guardado, la pestaña lo pinta", function()
  ES.Calc:Add("Leatherworking", 2152)
  OpenPage("calc")
  RunTimers()
end, { state = "full" })

test("dinero escrito a mano: plata, oro y cobre", function()
  Calc = ES.Calc
  expect_eq(Calc.ParseMoney("2,7"), 270, "2,7 = 2s 70c")
  expect_eq(Calc.ParseMoney("2.7"), 270, "2.7")
  expect_eq(Calc.ParseMoney("1g 20s 5c"), 12005, "1g 20s 5c")
  expect_eq(Calc.ParseMoney("1o 20p 5c"), 12005, "en español")
  expect_eq(Calc.ParseMoney(""), nil, "vacío")
  expect_eq(Calc.ParseMoney("hola"), nil, "texto")
  expect_eq(Calc.FormatMoney(12005), "1g 20s 5c", "al revés")
  expect_eq(Calc.FormatMoney(0), "0c", "cero")
end, { boot = false })

test("una receta con precios conocidos: la cuenta hecha a mano", function()
  -- Light Armor Kit: 1 Light Leather (25c); el kit a 1000c en la AH
  local r = ES.Data.Leatherworking.recipes[2152]
  local kit = r.out[1]
  SetPrice(2318, 25, 500)
  SetPrice(2934, 100000, 500)
  SetPrice(kit, 1000, 40)
  local c = ES.Calc:Add("Leatherworking", 2152)
  c.qty = 10
  local res = ES.Calc:Compute(c)
  expect(res and not res.missing, "faltan precios")
  expect_eq(res.cost, 250, "materiales de 10 kits")
  expect_eq(res.outN, 10 * r.out[2], "unidades fabricadas")
  local sale = res.ahSale
  note("venta %s, comisión %s, depósito %s, beneficio en la AH %s", tostring(sale), tostring(res.cut), tostring(res.deposit), tostring(res.profitAH))
  expect(sale and sale <= 1000 and sale >= 990, "venta %s: la subasta más barata o justo por debajo", tostring(sale))
  expect_near(res.profitAH, sale * res.outN * 0.95 - 250, 0.5, "beneficio en la AH = venta - 5% - materiales")
  expect_near(res.profitTrade, sale * res.outN - 250, 0.5, "beneficio por el chat (sin comisión)")
  expect_near(res.profitVendor, ES:VendorSellPrice(kit) * res.outN - 250, 0.5, "beneficio al vendedor")
end, { state = "full" })

test("materiales de la AH: se compran subiendo por la escalera, como en las rutas", function()
  -- Light Armor Kit pide 1 Light Leather: 20 a la venta a 25c y 1000 a 40c
  local scan = ES.db.scans[ES:RealmKey()]
  scan.items[2318] = { listings = 30, quantity = 1020, minUnit = 25, median = 40, ladder = { 25, 20, 40, 1000 } }
  SetPrice(2934, 100000, 500)
  local c = ES.Calc:Add("Leatherworking", 2152)
  c.qty = 50
  local res = ES.Calc:Compute(c)
  -- 20 × 25c + 30 × 40c = 1700c (no 50 × 25c = 1250c)
  expect_eq(res.cost, 1700, "materiales de 50 kits")
  local row
  for _, r in ipairs(res.rows) do if r.itemID == 2318 then row = r end end
  expect(row and row.source == "ah", "Light Leather no sale de la AH")
  expect_eq(row.total, 1700, "total de Light Leather")
  expect_eq(row.price, 34, "precio medio por unidad")
  -- Más de lo que hay a la venta: el resto, a la mediana (como las rutas)
  scan.items[2318] = { listings = 2, quantity = 20, minUnit = 25, median = 30, ladder = { 25, 10, 30, 10 } }
  c.qty = 30
  -- 10 × 25 + 10 × 30 + 10 × 30 (mediana) = 850
  expect_eq(ES.Calc:Compute(c).cost, 850, "con menos a la venta de lo que hace falta")
end, { state = "full" })

test("un precio escrito a mano manda hasta el siguiente escaneo", function()
  SetPrice(2318, 25, 500)
  SetPrice(2934, 100000, 500)
  local c = ES.Calc:Add("Leatherworking", 2152)
  c.prices[2318] = 40
  expect_eq(ES.Calc:Compute(c).cost, 40, "con el precio a mano")
  -- Escaneo nuevo (más reciente que el precio escrito): manda el escaneo
  NOW = NOW + 3600
  ES.db.scans[ES:RealmKey()].time = NOW
  expect_eq(ES.Calc:Compute(c).cost, 25, "tras escanear")
  expect_eq(c.prices[2318], nil, "el precio a mano caducado se quita")
end, { state = "full" })

test("Calculadora y Ganar dinero: mismo coste de materiales y misma venta", function()
  ES.db.earnMinProfit = 1
  ES.Earn:Clear()
  local res = ES.Earn:Ideas()
  local checked, diffs = 0, {}
  for _, idea in ipairs(res.ideas) do
    if idea.sellWhere == "ah" and not idea.cooldown then
      local e = idea.e
      local c = ES.Calc:Add(idea.profKey, e.id)
      c.qty = 1
      local calc = ES.Calc:Compute(c)
      checked = checked + 1
      if math.abs((calc.cost or -1) - e.cost) > 0.5 then
        diffs[#diffs + 1] = string.format("%s: materiales %s en la Calculadora, %s en Ganar dinero", e.recipe.name, tostring(calc.cost), tostring(e.cost))
      end
      if math.abs((calc.ahSale or -1) - (idea.price or -2)) > 0.5 then
        diffs[#diffs + 1] = string.format("%s: venta %s en la Calculadora, %s en Ganar dinero", e.recipe.name, tostring(calc.ahSale), tostring(idea.price))
      end
    end
  end
  expect(checked > 0, "ninguna idea de AH para comparar")
  note("%d recetas comparadas", checked)
  expect(#diffs == 0, "%d diferencias:\n    %s", #diffs, table.concat(diffs, "\n    "))
end, { state = "full" })

test("un intermedio con enfriamiento (Mooncloth) se compra hecho, como en la Colección", function()
  -- Sabes fabricar Mooncloth (2 Felcloth), pero es una cada pocos días: la Mooncloth Bag
  -- la contaba a 93s en vez de los 60g de la AH
  KNOWN_SPELLS[18560] = true
  SetPrice(14256, 4694)    -- Felcloth: 46s 94c
  SetPrice(14342, 609999)  -- Mooncloth: 60g 99s 99c
  local c = ES.Calc:Add("Tailoring", 18445) -- Mooncloth Bag
  c.qty = 1
  local res = ES.Calc:Compute(c)
  local m
  for _, x in ipairs(res.made) do if x.itemID == 14342 then m = x end end
  expect(m, "Mooncloth no sale como intermedio")
  expect(m.cooldown, "no sabe que tiene enfriamiento")
  expect_eq(m.mode, "buy", "cómo se consigue")
  expect_eq(m.craftCost, 2 * 4694, "fabricarla")
  -- La misma Mooncloth que la Colección
  local coll
  for _, e in ipairs(ES.Collection:Build("Tailoring").entries) do
    if e.id == 18445 then
      for _, rg in ipairs(e.reagents or {}) do if rg.item == 14342 then coll = rg.cost end end
    end
  end
  expect_eq(m.buyCost, coll, "Mooncloth en la Calculadora y en la Colección")
  -- Con un clic se fabrica (si tienes el enfriamiento listo), y otro la vuelve a comprar
  ES.Calc:ToggleVia(c, m)
  expect_eq(c.via[14342], "craft", "elegido fabricarla")
  res = ES.Calc:Compute(c)
  for _, x in ipairs(res.made) do if x.itemID == 14342 then m = x end end
  expect_eq(m.mode, "craft", "tras el clic")
  ES.Calc:ToggleVia(c, m)
  expect_eq(c.via[14342], nil, "vuelve a lo de por defecto")
  OpenPage("calc")
  RunTimers()
end, { state = "full" })

test("quitar un cálculo", function()
  local a = ES.Calc:Add("Leatherworking", 2152)
  local b = ES.Calc:Add("Tailoring", 2385)
  ES.Calc:Remove(b.id)
  expect(ES.Calc:Find(b.id) == nil, "sigue ahí")
  expect(ES.Calc:Find(a.id), "se fue el otro")
  OpenPage("calc")
end, { state = "full" })
