-- Ganar dinero: qué fabricar hoy con tus recetas porque da beneficio

local function Finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end

-- Precio de un objeto en el escaneo de las pruebas (y que no se pueda fabricar más barato)
local function SetPrice(itemID, price, qty)
  local scan = ES.db.scans[ES:RealmKey()]
  qty = qty or 50
  scan.items[itemID] = { listings = 5, quantity = qty, minUnit = price, avgUnit = price, sellers = 3, topShare = 0.3,
    median = price, ladder = { price, qty } }
end

local function Ideas()
  ES.db.earnMinProfit = 1 -- (todas las que dejan algo: la prueba es de las cuentas, no del mínimo)
  ES.Earn:Clear()
  return ES.Earn:Ideas()
end

for _, state in ipairs({ "empty", "scan", "full" }) do
  test("la pestaña se abre: " .. state, function()
    OpenPage("money")
    expect(ES:GetMainFrame().pages.money:IsShown(), "la página no se ve")
  end, { state = state })
end

test("sin profesiones ni escaneo: no propone nada", function()
  local res = Ideas()
  expect_eq(#res.batch, 0, "ideas sin escaneo")
end, { state = "empty" })

test("las cuentas de cada idea cuadran", function()
  local res = Ideas()
  expect(#res.batch > 0, "no hay ninguna idea en el lote (recetas sabidas: las primeras de 3 profesiones)")
  local invest, profit = 0, 0
  for _, idea in ipairs(res.batch) do
    local name = tostring(idea.e.recipe and idea.e.recipe.name)
    for _, k in ipairs({ "profit", "invest", "sale", "crafts" }) do
      expect_finite(idea[k], name .. ": " .. k)
    end
    expect(idea.crafts >= 0 and idea.crafts == math.floor(idea.crafts), "%s: %s fabricaciones", name, tostring(idea.crafts))
    expect(idea.invest >= 0, "%s: invierte %s", name, tostring(idea.invest))
    expect_near(idea.profit, idea.sale * idea.crafts - idea.invest, 0.5, name .. ": beneficio = venta × fabricaciones - inversión")
    invest, profit = invest + idea.invest, profit + idea.profit
    local e = idea.e
    if idea.sellWhere == "ah" then
      expect_near(e.ahNet, e.ahPrice * (1 - e.cut) - e.deposit, 0.01, name .. ": neto en la AH = precio - comisión - depósito")
      expect_near(e.cut, 0.05, 1e-9, name .. ": comisión de la AH de tu facción")
      expect_near(idea.sale, e.ahNet * e.qty, 0.01, name .. ": venta por fabricación")
    end
    expect_near(e.profit, math.max(e.vendor, e.ahNet or 0) * e.qty - e.cost, 0.5, name .. ": beneficio por fabricación")
  end
  expect_near(res.invest, invest, 0.5, "inversión del lote = suma de las líneas")
  expect_near(res.profit, profit, 0.5, "beneficio del lote = suma de las líneas")
  note("%d ideas en el lote, beneficio %.0f, invierte %.0f", #res.batch, res.profit, res.invest)
end, { state = "full" })

test("una idea con precios conocidos: la cuenta hecha a mano", function()
  -- Light Armor Kit (Peletería, 2152): 1 Light Leather. Light Leather a 25c y las
  -- chatarras para fabricarla, caras (así se compra); el kit, a 1000c en la AH
  local r = ES.Data.Leatherworking.recipes[2152]
  local kit = r.out[1]
  expect_eq(#r.r, 1, "materiales del kit")
  expect_eq(r.r[1][1], 2318, "material del kit")
  expect_eq(r.r[1][2], 1, "cantidad de Light Leather")
  SetPrice(2318, 25, 500)
  SetPrice(2934, 100000, 500) -- Ruined Leather Scraps
  SetPrice(kit, 1000, 40)
  KNOWN_SPELLS[2152] = true
  local res = Ideas()
  local idea
  for _, i in ipairs(res.ideas) do if i.e.id == 2152 then idea = i end end
  expect(idea, "el kit no sale en Ganar dinero")
  local e = idea.e
  local vendor = ES:VendorSellPrice(kit)
  -- A mano: depósito = venta al vendedor × 5% × 24 h / 2 (la fórmula de Classic, 24 h);
  -- neto = precio de venta × 95% - depósito; beneficio = neto - 25
  expect_near(e.deposit, vendor * 0.05 * 24 / 2, 0.01, "depósito de 24 h")
  expect_eq(e.cost, 25, "coste: una Light Leather")
  expect_eq(e.ahMin, 1000, "precio más bajo en la AH")
  note("precio de venta %s, depósito %s (venta al vendedor %s), neto %s, beneficio %s",
    tostring(e.ahPrice), tostring(e.deposit), tostring(vendor), tostring(e.ahNet), tostring(e.profit))
  expect(e.ahPrice <= 1000 and e.ahPrice >= 990, "precio de venta %s: el más bajo de la AH o justo por debajo", tostring(e.ahPrice))
  expect_near(e.ahNet, e.ahPrice * 0.95 - e.deposit, 0.01, "neto")
  expect_near(e.profit, e.ahNet - 25, 0.01, "beneficio por fabricación")
  expect_eq(idea.sellWhere, "ah", "se vende en la AH")
end, { state = "full" })

-- Reddit: una segunda cuenta fabricando y vendiendo al vendedor todo el día (~5 g/h).
-- «Venta segura al vendedor» corta a 20 min y pide oro por hora según tu nivel, y solo
-- mira lo que sabes: la pestaña BulkMoney enseña una hora de fabricar de cada receta, de
-- todas las profesiones, con el oro por hora como cifra. Gyrochronatom (Ingeniería,
-- 3961): 1 Iron Bar + 1 Gold Power Core (3 por Gold Bar); el vendedor paga 750c
test("BulkMoney: una hora de fabricar y sin saber la profesión", function()
  local GYRO = 3961
  local r = ES.Data.Engineering.recipes[GYRO]
  expect(r and r.out[1] == 4389, "Gyrochronatom no es la receta esperada")
  local vendor = ES:VendorSellPrice(4389)
  expect_eq(vendor, 750, "el vendedor paga el Gyrochronatom")
  SKILLS[ES.Data.Engineering.skillLine] = nil -- (sin Ingeniería)
  SetPrice(3575, 300, 5000)    -- Iron Bar
  SetPrice(3577, 900, 5000)    -- Gold Bar: 300c por Gold Power Core
  SetPrice(10558, 100000, 50)  -- Gold Power Core hecho, caro: se fabrica
  SetPrice(4389, 100000, 1)    -- en la AH, una sola cara (no cuenta: se mira el vendedor)
  SetPrice(2772, 100000, 50)   -- Iron Ore y Gold Ore, caras: no se funden
  SetPrice(2776, 100000, 50)
  local function Find()
    ES.Earn:Clear()
    for _, idea in ipairs(ES.Earn:VendorShuffle().list) do
      if idea.e.id == GYRO then return idea end
    end
  end
  local idea = expect(Find(), "no sale el Gyrochronatom en BulkMoney")
  expect(idea.learnable and idea.noProf, "no dice que es de una profesión que no tienes")
  -- Una hora de fabricar: más de lo que cabe en los 20 min de «Venta segura al
  -- vendedor», y no más de una hora (contando los Gold Power Core que se hacen por el camino)
  local cap = math.floor(ES.Earn.VENDOR_TIME_BUDGET / ES.Earn.CraftSeconds(GYRO))
  expect(idea.crafts > cap, "%d fabricaciones: cortadas a los 20 min (%d)", idea.crafts, cap)
  expect(idea.limit == "time" or idea.limit == "max", "para por %s, no por la hora ni el tope", tostring(idea.limit))
  expect(idea.seconds <= ES.Earn.SHUFFLE_SECONDS, "%.0f s de fabricar: más de una hora", idea.seconds)
  expect(idea.limit ~= "time" or idea.seconds > ES.Earn.SHUFFLE_SECONDS - 2 * ES.Earn.CraftSeconds(GYRO),
    "para por tiempo con solo %.0f s de fabricar", idea.seconds)
  -- A mano: 750 - 300 (Iron Bar) - 300 (un tercio de Gold Bar) = 150 por fabricación
  expect_near(idea.profit, 150 * idea.crafts, 1, "beneficio")
  -- De más a menos oro por hora
  local list = ES.Earn:VendorShuffle().list
  for i = 2, #list do
    expect(list[i - 1].profit >= list[i].profit, "sin ordenar: %s antes que %s", list[i - 1].e.recipe.name, list[i].e.recipe.name)
  end
  -- La fila: en la pestaña BulkMoney, con lo de esa hora como oro por hora; en Ganar
  -- dinero, ya no
  local function Row(page)
    for _, row in ipairs(page.rows or {}) do
      if row:IsShown() and row.item == 4389 then return row end
    end
  end
  ES.Earn:Clear()
  OpenPage("money")
  expect(not Row(ES.earnPage), "el Gyrochronatom sigue saliendo en Ganar dinero")
  OpenPage("bulk")
  local found = Row(ES.bulkPage)
  expect(found, "no sale la fila del Gyrochronatom en BulkMoney")
  local value = tostring(found.value:GetText())
  expect(value:find(string.format(ES.L["%s/h"], ES.Money(idea.profit)), 1, true), "la cifra no es el oro por hora: %s", value)
  expect(tostring(found.title:GetText()):find(idea.crafts .. "×", 1, true), "el título no dice las fabricaciones de la hora: %s",
    tostring(found.title:GetText()))
  -- Con Iron Bar cara ya no deja nada: fuera
  SetPrice(3575, 1000, 5000)
  expect(not Find(), "con Iron Bar a 10s sigue proponiendo el Gyrochronatom")
end, { state = "full" })

-- BulkMoney: lo que se compra al vendedor, con el descuento de tu reputación con tu
-- capital y, con la casilla, Bartering (-10%). Stonescale Oil (Alquimia, 17551): 1
-- Stonescale Eel (AH) + 1 Leaded Vial (vendedor); da 2
test("BulkMoney: descuento de ciudad y Bartering en lo que se compra al vendedor", function()
  local OIL, VIAL = 17551, 3372
  local r = ES.Data.Alchemy.recipes[OIL]
  expect(r and r.r[2][1] == VIAL and r.out[2] == 2, "Stonescale Oil no es la receta esperada")
  local vial = expect(ES.Data.VendorPrices[VIAL], "el Leaded Vial no se vende en un vendedor")
  SetPrice(13422, 180, 20000) -- Stonescale Eel
  SetPrice(VIAL, 100000, 10)  -- en la AH, caro: se compra al vendedor
  local oldStanding = ES.Standing
  local standing = 4 -- neutral con todas
  ES.Standing = function() return standing end
  local function Cost()
    ES.Earn:Clear()
    for _, idea in ipairs(ES.Earn:VendorShuffle().list) do
      if idea.e.id == OIL then return idea.e.cost end
    end
  end
  ES.db.bulkBartering = nil
  expect_eq(Cost(), 180 + vial, "sin descuento")
  ES.db.bulkBartering = true
  expect_eq(Cost(), 180 + math.floor(vial * 0.9 + 0.5), "con Bartering")
  standing = 6 -- honorable: -10%
  local total = ES.Earn.VendorDiscount()
  expect_near(total, 1 - 0.9 * 0.9, 1e-9, "honorable y Bartering")
  expect_eq(Cost(), 180 + math.floor(vial * 0.81 + 0.5), "honorable y Bartering")
  -- La pestaña dice qué descuento aplica
  OpenPage("bulk")
  local status = tostring(ES.bulkPage.status:GetText())
  expect(status:find("Bartering -10%", 1, true), "el estado no dice Bartering: %s", status)
  ES.db.bulkBartering = nil
  ES.Standing = oldStanding
end, { state = "full" })

-- BulkMoney con el Gyrochronatom (1 Iron Bar + 1 Gold Power Core, 3 por Gold Bar; el
-- vendedor paga 750c): Iron Bar a 300 y Gold Bar a 900 (ores, `ore` y `goldOre`)
local function GyroPrices(ore, goldOre)
  SetPrice(3575, 300, 5000)
  SetPrice(3577, 900, 5000)
  SetPrice(10558, 100000, 50)
  SetPrice(4389, 100000, 1)
  SetPrice(2772, ore, 5000)
  SetPrice(2776, goldOre, 5000)
end
local function FindBulk(id)
  ES.Earn:Clear()
  for _, idea in ipairs(ES.Earn:VendorShuffle().list) do
    if idea.e.id == id then return idea end
  end
end

-- Sin Minería ni Ingeniería: si el mineral sale más barato que la barra, BulkMoney lo
-- funde (Smelt Iron: 1 Iron Ore -> 1 Iron Bar) y lo dice
test("BulkMoney: funde el mineral si sale más barato que la barra", function()
  SKILLS[ES.Data.Engineering.skillLine] = nil
  GyroPrices(150, 100000) -- Iron Ore a 150: la mitad que la barra
  local idea = expect(FindBulk(3961), "no sale el Gyrochronatom")
  local smelt, ore
  for _, a in ipairs(idea.actions or {}) do
    if a.kind == "craft" and a.item == 3575 then smelt = a end
    if a.kind == "ah" and a.item == 2772 then ore = a end
  end
  expect(smelt and smelt.prof == "Mining", "no funde Iron Bar con Minería")
  expect(ore and math.abs(ore.qty - idea.crafts) < 1e-6, "no compra %d Iron Ore", idea.crafts)
  -- A mano: 750 - 150 (Iron Ore) - 300 (un tercio de Gold Bar) = 300 por fabricación
  expect_near(idea.profit, 300 * idea.crafts, 1, "beneficio fundiendo")
  -- Iron Ore a 290: ahorra 10c por barra, pero fundir cuesta tiempo y en la hora deja
  -- menos (datos reales del 24/11: 7g44/h comprando la barra, 5g48/h fundiendo)
  GyroPrices(290, 100000)
  idea = expect(FindBulk(3961), "no sale el Gyrochronatom con Iron Ore a 290")
  for _, a in ipairs(idea.actions or {}) do
    expect(not (a.kind == "craft" and a.item == 3575), "funde Iron Bar para ahorrar 10c: en la hora deja menos")
  end
  -- Con el mineral caro, compra la barra
  GyroPrices(100000, 100000)
  idea = expect(FindBulk(3961), "no sale el Gyrochronatom con el mineral caro")
  for _, a in ipairs(idea.actions or {}) do
    expect(not (a.kind == "craft" and a.item == 3575), "funde Iron Bar con Iron Ore a 10g")
  end
end, { state = "full" })

-- BulkMoney: cada fila dice también para cuántas horas hay ya en la AH por debajo del
-- precio máximo de cada material (las más caras, no), que lo limita el material que antes
-- se acaba. Una sola lista: una sección aparte, con otra cifra de oro para la misma
-- receta, confundía
test("BulkMoney: para cuántas horas hay en la AH por debajo del precio máximo", function()
  SKILLS[ES.Data.Engineering.skillLine] = nil
  GyroPrices(100000, 100000)
  -- Iron Bar: 2000 a 300, 1000 a 400 y 3000 a 500
  local scan = ES.db.scans[ES:RealmKey()]
  scan.items[3575] = { listings = 30, quantity = 6000, minUnit = 300, avgUnit = 400, sellers = 10, topShare = 0.2,
    median = 400, ladder = { 300, 2000, 400, 1000, 500, 3000 } }
  local idea = expect(FindBulk(3961), "no sale el Gyrochronatom")
  local max
  for _, p in ipairs(idea.maxPrices) do if p.itemID == 3575 then max = p.max end end
  expect(max and max >= 400 and max < 500, "precio máximo de Iron Bar: %s (la prueba espera entre 400 y 499)", tostring(max))
  -- Iron Bar (3000 por debajo del máximo) limita; Gold Bar, 5000 a 900, da para 15000
  expect_eq(idea.stockCrafts, 3000, "hay para: las Iron Bar de 300 y 400, no las de 500")
  local secs = idea.seconds / idea.crafts
  expect_near(idea.stockHours, 3000 * secs / 3600, 0.01, "horas para las que hay")
  expect(idea.stockHours >= 1.5, "la prueba espera que haya para más de una hora: %.2f h", idea.stockHours)
  -- Una sola fila del Gyrochronatom, la de la hora, y lo dice
  OpenPage("bulk")
  local found, count = nil, 0
  for _, row in ipairs(ES.bulkPage.rows) do
    if row:IsShown() and row.item == 4389 then found, count = row, count + 1 end
  end
  expect_eq(count, 1, "filas del Gyrochronatom")
  local sub = tostring(found.sub:GetText())
  -- (el «~» se pinta como un icono: se mira lo de antes y el número de horas)
  local before = ES.L["en la AH hay para ~%d h"]:match("^(.-)%s*~")
  expect(sub:find(before, 1, true) and sub:find(math.floor(idea.stockHours + 0.5) .. " h", 1, true),
    "el subtítulo no dice para cuántas horas hay: %s", sub)
end, { state = "full" })

-- BulkMoney, sin los filtros de Ganar dinero: sin el 10% de margen (al vendedor no hay
-- riesgo: Heavy Dynamite deja un 6% y sale) y con las recetas de cualquier origen
-- (Felblood Soul Bag, patrón de origen desconocido, +1g47 por bolsa con los precios del
-- 24/11: la fila lo dice)
test("BulkMoney: sin el 10% de margen y con recetas de origen desconocido", function()
  SKILLS[ES.Data.Engineering.skillLine], SKILLS[ES.Data.Tailoring.skillLine] = nil, nil
  -- Heavy Dynamite (3946): 2 Heavy Blasting Powder + 1 Wool Cloth -> 3, a 350 al vendedor
  SetPrice(4377, 400, 5000)   -- Heavy Blasting Powder
  SetPrice(2838, 100000, 50)  -- Heavy Stone, cara: la pólvora se compra
  SetPrice(2592, 191, 5000)   -- Wool Cloth
  SetPrice(4378, 100000, 1)
  local dyn = expect(FindBulk(3946), "Heavy Dynamite no sale (deja un 6 por ciento: el margen mínimo la quitaba)")
  expect_eq(dyn.e.cost, 2 * 400 + 191, "coste de Heavy Dynamite")
  expect(dyn.crafts > 0, "sin fabricaciones (la escalera pedía margen mínimo)")
  -- Felblood Soul Bag (1306545): 8 Felcloth + 6 Bolt of Runecloth; el vendedor, 8g
  local BAG = 1306545
  expect_eq(ES:VendorSellPrice(279271), 80000, "el vendedor paga la Felblood Soul Bag")
  SetPrice(14256, 5788, 588)    -- Felcloth
  SetPrice(14048, 2919, 2971)   -- Bolt of Runecloth
  SetPrice(14047, 100000, 50)   -- Runecloth, cara: el rollo se compra
  local bag = expect(FindBulk(BAG), "Felblood Soul Bag no sale (patrón de origen desconocido)")
  expect_eq(bag.e.learnSource, "unknown", "origen del patrón")
  expect_near(bag.profit / bag.crafts, 80000 - 8 * 5788 - 6 * 2919, 1, "beneficio por bolsa")
  OpenPage("bulk")
  local found
  for _, row in ipairs(ES.bulkPage.rows) do
    if row:IsShown() and row.item == 279271 then found = row end
  end
  expect(found, "no sale la fila de la Felblood Soul Bag")
  expect(tostring(found.sub:GetText()):find(ES.L["Fuente desconocida"], 1, true), "la fila no dice que el patrón es de origen desconocido: %s",
    tostring(found.sub:GetText()))
end, { state = "full" })

-- BulkMoney: el aspa de una fila la quita de BulkMoney (no de Ganar dinero) y la fila de
-- recetas quitadas la recupera. Al acabar un escaneo, la pestaña abierta se repinta con
-- los precios nuevos (RefreshAllViews)
test("BulkMoney: quitar una receta con el aspa, recuperarla y repintar tras el escaneo", function()
  SKILLS[ES.Data.Engineering.skillLine] = nil
  GyroPrices(100000, 100000)
  local idea = expect(FindBulk(3961), "no sale el Gyrochronatom")
  ES.UI.BulkMoneyLine(idea).onSkip()
  expect(not FindBulk(3961), "sigue el Gyrochronatom tras quitarlo")
  expect(ES.Earn.IsBulkHidden(3961) and not ES.Earn.IsHidden(3961), "se quitó también de Ganar dinero")
  OpenPage("bulk")
  local restore, gyroRow
  local want = string.format(ES.L["Recetas quitadas de BulkMoney: %d"], 1)
  for _, row in ipairs(ES.bulkPage.rows) do
    if row:IsShown() and tostring(row.title:GetText()):find(want, 1, true) then restore = row end
    if row:IsShown() and row.item == 4389 then gyroRow = row end
  end
  expect(not gyroRow, "la fila del Gyrochronatom sigue en la pestaña")
  expect(restore, "no sale la fila de recetas quitadas")
  restore:GetScript("OnClick")(restore)
  RunTimers()
  expect(not ES.Earn.IsBulkHidden(3961), "la fila de recetas quitadas no la recupera")
  expect(FindBulk(3961), "el Gyrochronatom no vuelve")
  -- Escaneo nuevo con Iron Bar cara: la pestaña abierta se repinta sin él
  OpenPage("bulk")
  local function Shown()
    for _, row in ipairs(ES.bulkPage.rows) do if row:IsShown() and row.item == 4389 then return true end end
    return false
  end
  expect(Shown(), "el Gyrochronatom no sale en la pestaña")
  SetPrice(3575, 100000, 5000)
  local scan = ES.db.scans[ES:RealmKey()]
  scan.time = scan.time + 60
  ES:RefreshAllViews()
  expect(not Shown(), "tras el escaneo, la pestaña sigue con los precios de antes")
end, { state = "full" })

-- Botón de anunciar (BulkPostUI.lua, desde BulkMoney): sueltas un objeto, pones un
-- precio y cada clic anuncia 1 unidad a 2 h a ese precio (Ledger:PostOnAH). Solo en la
-- copia de desarrollo, como la pestaña
test("BulkMoney: el botón de anunciar pone 1 unidad a 2 h al precio que eliges", function()
  local P = ES.BulkPost
  OpenPage("bulk")
  expect(not P.IsShown(), "el botón de anunciar sale sin pedirlo")
  -- (el simulador no guarda el estrato: se apunta el que pide el marco al crearse)
  local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
  local asked = {}
  local origCreate = CreateFrame
  CreateFrame = function(...)
    local f = origCreate(...)
    rawset(f, "SetFrameStrata", function(_, s) asked[#asked + 1] = s end)
    return f
  end
  local b = ES.bulkPage.postButton
  b:GetScript("OnClick")(b)
  CreateFrame = origCreate
  expect(P.IsShown() and P.DB().shown, "el botón de la pestaña no lo abre")
  -- Por encima de la ventana del addon (HIGH, en el centro): en MEDIUM salía detrás y no
  -- se veía al pulsar el botón
  expect(asked[1] and (STRATA[asked[1]] or 0) > STRATA.HIGH, "el marco va en %s: detrás de la ventana del addon (HIGH)",
    tostring(asked[1]))
  -- El objeto, soltado desde el cursor
  local cursor = 3575 -- Iron Bar
  GetCursorInfo = function() if cursor then return "item", cursor end end
  ClearCursor = function() cursor = nil end
  expect(P.DropFromCursor(), "no recoge el objeto del cursor")
  expect_eq(P.DB().itemID, 3575, "objeto")
  expect(cursor == nil, "el objeto se queda en el cursor")
  -- El precio, en sus casillas: oro, plata y cobre (1g 23s 45c)
  local f = P.Frame()
  f.gold:SetText("1")
  f.silver:SetText("23")
  f.copper:SetText("45")
  f.copper:GetScript("OnTextChanged")(f.copper, true)
  expect_eq(P.DB().price, 12345, "precio de las casillas")
  -- Sin la duración en los textos
  expect(not tostring(f.post:GetText()):find("h)", 1, true), "el botón sigue diciendo las horas: %s", tostring(f.post:GetText()))
  -- Anunciar: 1 unidad, 2 h, al precio puesto
  local posted
  ES.Ledger.PostOnAH = function(_, itemID, n, unit, hours) posted = { itemID, n, unit, hours } return n end
  BAGS[3575] = 0
  expect_eq(P.Post(), 0, "anuncia sin llevar ninguno")
  expect(not posted, "llama a la AH sin llevar ninguno")
  BAGS[3575] = 5
  expect_eq(P.Post(), 1, "anunciadas")
  expect(posted and posted[1] == 3575 and posted[2] == 1 and posted[3] == 12345 and posted[4] == 2,
    "anuncio: %s", posted and table.concat({ tostring(posted[1]), tostring(posted[2]), tostring(posted[3]), tostring(posted[4]) }, ", ") or "nada")
  -- Se cierra con su X y no vuelve solo
  P.Show(false)
  expect(not P.IsShown() and not P.DB().shown, "no se cierra")
  -- Lo publicado (sin DevTools.lua): no se abre
  ES.DevCommand = nil
  P.Show(true)
  expect(not P.IsShown(), "lo publicado abre el botón de anunciar")
end, { state = "full" })

-- Botón de anunciar: mientras la subasta está en la AH, en gris y «Selling» (no deja poner
-- otra); al venderse, «SOLD» y se puede anunciar otra. La venta llega, en la AH moderna
-- de Forever, con AUCTION_HOUSE_SHOW_NOTIFICATION / _FORMATTED_ (AuctionSold): la línea
-- del chat la escribe la interfaz sin CHAT_MSG_SYSTEM, y con solo el mensaje se quedaba
-- en «Selling» (lo vio el jugador). Si caduca (aviso o pasadas las horas de verdad: pedir
-- 2 h en Forever da 12), vuelve a estar listo
test("BulkMoney: el botón de anunciar dice Selling mientras está en la AH y SOLD al venderse", function()
  local P = ES.BulkPost
  OpenPage("bulk")
  P.Show(true)
  P.SetItem(3575) -- Iron Bar
  P.SetPrice(10000)
  BAGS[3575] = 5
  local posts = 0
  ES.Ledger.PostOnAH = function(_, itemID, n)
    posts = posts + 1
    ES.Ledger.pendingPost = { text = "anunciado", name = "Iron Bar", itemID = itemID, hours = 12 }
    return n
  end
  local function ButtonText() return tostring(P.Frame().post:GetText()) end
  expect_eq(P.Post(), 1, "anunciadas")
  expect_eq(P.State(), "posting", "esperando a la AH")
  -- La AH lo confirma: a la venta, en gris, hasta las 12 h de verdad (no 2)
  ES.Ledger:ConfirmPost(true)
  expect_eq(P.State(), "selling", "a la venta")
  local ends = P.DB().sale.ends - time()
  expect(ends > 11 * 3600 and ends <= 12 * 3600, "caduca en %d s: no con las 12 h de la AH", ends)
  expect(ButtonText():find(ES.L["En venta"], 1, true), "el botón no dice Selling: %s", ButtonText())
  expect_eq(P.Post(), 0, "deja anunciar otra con una a la venta")
  expect_eq(posts, 1, "llama a la AH con una a la venta")
  -- Un mensaje de otra cosa: nada
  ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
  ERR_AUCTION_EXPIRED_S = "Your auction of %s has expired."
  FireEvent("CHAT_MSG_SYSTEM", string.format(ERR_AUCTION_SOLD_S, "Linen Cloth"))
  FireEvent("AUCTION_HOUSE_SHOW_NOTIFICATION", P.NOTE_SOLD, "Linen Cloth")
  expect_eq(P.State(), "selling", "la venta de otro objeto la da por vendida")
  -- Se vende (el aviso de la AH moderna, con el nombre del cliente): SOLD, y se puede
  -- anunciar otra
  FireEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", P.NOTE_SOLD, (GetItemInfo(3575)))
  expect_eq(P.State(), "sold", "vendida")
  expect(ButtonText():find(ES.L["VENDIDO"], 1, true), "el botón no dice SOLD: %s", ButtonText())
  expect_eq(P.Post(), 1, "no deja anunciar otra tras venderse")
  expect_eq(posts, 2, "anuncios")
  -- La AH no lo acepta: listo otra vez
  ES.Ledger:ConfirmPost(false, "error")
  expect(not P.Busy(), "sigue en gris tras un anuncio que la AH no aceptó")
  -- Caduca sin mensaje (estabas desconectado): pasadas las horas, listo
  P.DB().sale = { state = "selling", itemID = 3575, ends = time() - 120 }
  expect_eq(P.State(), "expired", "caducada por tiempo")
  expect(not P.Busy(), "caducada sigue en gris")
  -- Cerrar el botón lo reinicia: al volver a abrirlo se puede anunciar (nunca se queda
  -- en gris sin salida)
  P.DB().sale = { state = "selling", itemID = 3575, ends = time() + 3600 }
  expect(P.Busy(), "la prueba espera una subasta a la venta")
  P.Show(false)
  P.Show(true)
  expect(not P.Busy(), "tras cerrarlo y abrirlo sigue en gris")
  expect(not tostring(P.Frame().post:GetText()):find(ES.L["En venta"], 1, true), "tras cerrarlo y abrirlo sigue diciendo Selling")
end, { state = "full" })

-- Botón de anunciar como cebo: cada anuncio que la AH acepta se apunta, con lo que tardó
-- en venderse. Vendido en menos de P.INSTANT s lo compró un sniper (el cebo de 30c se
-- vendía al instante una y otra vez, y nadie llegaba a rebajar por debajo): el chat lo dice
-- y sugiere subirlo; el umbral se busca entre el más caro comprado al instante y el más
-- barato que aguantó. «Usar» pone el precio sugerido
test("BulkMoney: el botón de anunciar apunta los cebos y sugiere subir el que compra un sniper", function()
  local P = ES.BulkPost
  OpenPage("bulk")
  P.Show(true)
  P.SetItem(3575) -- Iron Bar
  BAGS[3575] = 50
  ES.Ledger.PostOnAH = function(_, itemID, n)
    ES.Ledger.pendingPost = { text = "anunciado", name = "Iron Bar", itemID = itemID, hours = 12 }
    return n
  end
  local name = (GetItemInfo(3575))
  local f = P.Frame()
  local function Bait(price, sniped)
    P.SetPrice(price)
    expect_eq(P.Post(), 1, "cebo a " .. price)
    ES.Ledger:ConfirmPost(true)
    local log = P.Log()
    local e = log[#log]
    expect(e and e.price == price and e.itemID == 3575, "el cebo a %d no se apunta", price)
    if sniped then
      FireEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", P.NOTE_SOLD, name)
    else
      e.t = e.t - P.INSTANT - 5 -- (pasa el tiempo de un sniper sin venderse)
      P.DB().sale.state = "expired"
    end
    P.Refresh()
    return e
  end
  -- Sin cebos: nada que sugerir
  expect(not P.Summary(3575).suggest, "sugiere un precio sin cebos")
  expect(not f.use:IsShown(), "«Usar» sale sin cebos")
  -- 30c, comprado al instante: el chat lo dice y sugiere 45c (×1,5)
  local printed = #PRINTS
  local e = Bait(30, true)
  expect_eq(P.Outcome(e), "sniped", "vendido al instante")
  local s = P.Summary(3575)
  expect(s.n == 1 and s.sniped == 1, "resumen: %d cebos, %d al instante", s.n, s.sniped)
  expect_eq(s.suggest, 45, "sugerencia tras un cebo comprado al instante")
  local said
  local prefix = ES.L["Vendido en %d s: seguramente un sniper. Prueba el siguiente a %s."]:match("^(.-)%%")
  for i = printed + 1, #PRINTS do if PRINTS[i]:find(prefix, 1, true) then said = true end end
  expect(said, "el chat no dice que lo compró un sniper")
  -- La línea del marco lo cuenta y «Usar» pone el precio sugerido
  local line = tostring(f.baits.text:GetText())
  expect(line:find(string.format(ES.L["Cebos: %d, %d comprados al instante"], 1, 1), 1, true), "la línea no cuenta los cebos: %s", line)
  expect(f.use:IsShown(), "no sale «Usar» con una sugerencia")
  f.use:GetScript("OnClick")(f.use)
  expect_eq(P.DB().price, 45, "precio tras «Usar»")
  -- 45c aguanta: el umbral está entre 30 y 45, se prueba en medio (38c)
  e = Bait(45, false)
  expect_eq(P.Outcome(e), "held", "aguantó sin venderse")
  expect_eq(P.Summary(3575).suggest, 38, "sugerencia entre el comprado al instante y el que aguantó")
  -- 38c, comprado al instante: entre 38 y 45 (42c)
  Bait(38, true)
  expect_eq(P.Summary(3575).suggest, 42, "sugerencia al acercarse al umbral")
  -- 42c comprado: el hueco con 45 ya es pequeño, se queda en el que aguantó
  Bait(42, true)
  expect_eq(P.Summary(3575).suggest, 45, "sugerencia sin hueco")
  -- Al precio sugerido, sin «Usar»; el tooltip lista los cebos
  P.SetPrice(45)
  P.Refresh()
  expect(not f.use:IsShown(), "«Usar» sale con el precio ya puesto")
  P.BaitsTooltip(f.baits)
  -- Los cebos de otro objeto no cuentan; cerrar el botón no los borra; solo los últimos P.LOG_MAX
  expect_eq(P.Summary(2589).n, 0, "cebos de otro objeto")
  P.Show(false)
  P.Show(true)
  expect_eq(P.Summary(3575).n, 4, "cebos tras cerrar y abrir el botón")
  for i = 1, P.LOG_MAX + 5 do P.Log()[#P.Log() + 1] = { itemID = 2589, price = i, t = time() - 600 } end
  P.SetPrice(45)
  Bait(45, false)
  expect_eq(#P.Log(), P.LOG_MAX, "cebos apuntados")
end, { state = "full" })

-- BulkMoney: tu precio de un material (como en la Calculadora) sustituye al de la AH en
-- las cuentas; se escribe en la fila del material ("2.5" = 2s 50c) y vacío vuelve al de
-- la AH
test("BulkMoney: tu precio de un material cambia las cuentas y se escribe en su fila", function()
  SKILLS[ES.Data.Engineering.skillLine] = nil
  GyroPrices(100000, 100000) -- Iron Bar a 300, Gold Bar a 900 (300 por fabricación)
  local idea = expect(FindBulk(3961), "no sale el Gyrochronatom")
  expect_eq(idea.e.cost, 300 + 300, "coste con los precios de la AH")
  ES.Earn.SetBulkPrice(3575, 100) -- Iron Bar a 1s
  idea = expect(FindBulk(3961), "no sale el Gyrochronatom con tu precio")
  expect_eq(idea.e.cost, 100 + 300, "coste con tu precio de Iron Bar")
  local mat
  for _, m in ipairs(ES.Earn.BulkMaterials(ES.Earn:VendorShuffle())) do if m.itemID == 3575 then mat = m end end
  expect(mat and mat.mine == 100 and mat.ah == 300, "material: tu precio y el de la AH")
  -- En la pestaña: la fila del material lo dice; clic y escribir otro precio
  OpenPage("bulk")
  local page, row = ES.bulkPage, nil
  for _, r in ipairs(page.rows) do
    if r:IsShown() and r.item == 3575 and tostring(r.sub:GetText()):find(ES.L["a mano"], 1, true) then row = r end
  end
  expect(row, "la fila de Iron Bar no dice que el precio es tuyo")
  row.onClick()
  local box = page.priceBox
  expect(box:IsShown() and box:GetText() == "1s", "la casilla no se abre con tu precio: %s", tostring(box:GetText()))
  box:SetText("2.5")
  box:GetScript("OnEnterPressed")(box)
  expect_eq(ES.Earn.BulkPrice(3575), 250, "precio escrito")
  idea = expect(FindBulk(3961), "no sale el Gyrochronatom")
  expect_eq(idea.e.cost, 250 + 300, "coste con el precio escrito")
  -- Vacío: vuelve al de la AH
  for _, r in ipairs(page.rows) do if r:IsShown() and r.item == 3575 then row = r end end
  row.onClick()
  box:SetText("")
  box:GetScript("OnEnterPressed")(box)
  expect_eq(ES.Earn.BulkPrice(3575), nil, "precio borrado")
  idea = expect(FindBulk(3961), "no sale el Gyrochronatom")
  expect_eq(idea.e.cost, 300 + 300, "coste de vuelta con la AH")
end, { state = "full" })

-- Con gangas (BulkMoney): recetas que hoy no dejan nada vendiendo al vendedor pero sí
-- comprando sus materiales por debajo de un objetivo, con cuántas veces ha pasado en el
-- historial. Gyrochronatom con Iron Bar a 500 (750 - 500 - 300 = -50): el objetivo de Iron
-- Bar es 500 - 55 = 445 (lo que falta para dejar 5c); en el historial, 4 de 10 escaneos
-- con el mínimo a 400 (la mediana, por encima)
test("BulkMoney: con gangas, rentables comprando por debajo del objetivo según el historial", function()
  SKILLS[ES.Data.Engineering.skillLine] = nil
  GyroPrices(100000, 100000)
  SetPrice(3575, 500, 5000)
  local history = ES.History:Entries()
  for i = #history, 1, -1 do history[i] = nil end
  for i = 1, 10 do
    local min, median = i <= 4 and 400 or 500, i <= 4 and 480 or 520
    history[#history + 1] = { time = time() - (11 - i) * 3600, elapsed = 0, snap = string.format(";3575:%d:20:%d:5000", min, median) }
  end
  expect(not FindBulk(3961), "con Iron Bar a 500 el Gyrochronatom ya deja beneficio: la prueba no prueba nada")
  local b
  local res = ES.Earn:BulkBargains()
  for _, x in ipairs(res.list) do if x.e.id == 3961 then b = x end end
  expect(b, "el Gyrochronatom no sale en «Con gangas»")
  expect_eq(res.scans, 10, "escaneos del historial")
  local m = b.mats[1]
  expect_eq(m.itemID, 3575, "material")
  expect_near(m.target, 445, 0.01, "objetivo de Iron Bar")
  expect(m.minBelow == 4 and m.medBelow == 0, "veces por debajo: mínimo %d, mediana %d", m.minBelow, m.medBelow)
  expect_near(b.best, 750 - 400 - 300, 0.01, "lo que deja con lo más barato visto")
  -- En la pestaña
  OpenPage("bulk")
  local want = string.format(ES.L["gangas sueltas (%d de %d escaneos)"], 4, 10)
  local found = false
  for _, row in ipairs(ES.bulkPage.rows) do
    if row:IsShown() and row.item == 4389 and tostring(row.sub:GetText()):find(want, 1, true) then found = true end
  end
  expect(found, "no sale la fila del Gyrochronatom con las veces que hubo gangas")
  -- Sin gangas en el historial (nunca por debajo del objetivo), no sale. (Un escaneo nuevo:
  -- el historial leído se guarda hasta que llega otro)
  for i = 1, 10 do history[i].snap = ";3575:500:20:520:5000" end
  history[#history + 1] = { time = time(), elapsed = 0, snap = ";3575:500:20:520:5000" }
  res = ES.Earn:BulkBargains()
  for _, x in ipairs(res.list) do expect(x.e.id ~= 3961, "sale sin haber estado nunca por debajo del objetivo") end
end, { state = "full" })

-- Precio máximo de compra: hasta dónde pagar cada material de la AH y que aún deje
-- 5c por fabricación. Gyrochronatom: 150 de beneficio por fabricación, así que Iron
-- Bar (1 por fabricación) hasta 300 + 145 y Gold Bar (1/3) hasta 900 + 145 × 3. La
-- lista de compra lo lleva y lo dice
test("BulkMoney: precio máximo de compra de cada material y en la lista de compra", function()
  SKILLS[ES.Data.Engineering.skillLine] = { 200, 300 }
  KNOWN_SPELLS[3961], KNOWN_SPELLS[12584] = true, true -- Gyrochronatom y Gold Power Core
  GyroPrices(100000, 100000)
  local idea = expect(FindBulk(3961), "no sale el Gyrochronatom")
  local max = {}
  for _, p in ipairs(idea.maxPrices or {}) do max[p.itemID] = p.max end
  expect_eq(max[3575], 445, "Iron Bar")
  expect_eq(max[3577], 1335, "Gold Bar")
  -- En la lista de compra (clic derecho de la fila)
  local shopping = expect(idea.shopping, "una receta que sabes sin lista de compra")
  local list = expect(ES.Shopping.Add("money", "BulkMoney", shopping), "no se añadió la lista")
  local item
  for _, it in ipairs(list.items) do if it.itemID == 3575 then item = it end end
  expect(item and item.max == 445, "la lista no lleva el precio máximo de Iron Bar")
  OpenPage("shopping")
  local want = string.format(ES.L["compensa hasta %s/u"], ES.Money(445))
  local found = false
  for _, row in ipairs(ES.shoppingPage and ES.shoppingPage.rows or {}) do
    if row:IsShown() and row.item == 3575 and tostring(row.sub:GetText()):find(want, 1, true) then found = true end
  end
  expect(found, "la Lista de compra no dice hasta dónde compensa Iron Bar")
end, { state = "full" })

-- Spec recipe-requirements: «Recetas que podrías aprender» no propone las de una
-- especialización que no tienes (Frostsaber Boots pide Tribal Leatherworking)
test("recetas para aprender: solo las de tu especialización", function()
  local r = ES.Data.Leatherworking.recipes[19066] -- Frostsaber Boots
  expect(r and r.scroll and r.spec == "Tribal", "Frostsaber Boots no es un pergamino de Tribal: la prueba no prueba nada")
  SKILLS[ES.Data.Leatherworking.skillLine] = { 260, 300 }
  for _, m in ipairs(r.r) do SetPrice(m[1], 1, 5000) end -- materiales baratos
  SetPrice(r.scroll, 100, 1)                              -- el patrón, en la AH
  SetPrice(r.out[1], 500000, 40)                          -- lo fabricado, caro
  local function Offered()
    for _, idea in ipairs(Ideas().learnable) do
      if idea.e.id == 19066 then return true end
    end
    return false
  end
  expect(not Offered(), "sin Tribal Leatherworking propone aprender Frostsaber Boots")
  KNOWN_SPELLS[10660] = true
  expect(Offered(), "con Tribal Leatherworking no propone aprender Frostsaber Boots (la prueba no prueba nada)")
end, { state = "full" })

-- CurseForge: proponía aprender Mooncloth Shoulders por una sola subasta a 350g: con
-- una o dos subastas no se sabe si ese es el precio ni si hay mercado
test("recetas para aprender: con muy pocas subastas de lo fabricado no se proponen", function()
  local r = ES.Data.Leatherworking.recipes[19066] -- Frostsaber Boots
  SKILLS[ES.Data.Leatherworking.skillLine] = { 260, 300 }
  KNOWN_SPELLS[10660] = true
  for _, m in ipairs(r.r) do SetPrice(m[1], 1, 5000) end
  SetPrice(r.scroll, 100, 1)
  SetPrice(r.out[1], 500000, 40)
  local function Find()
    for _, idea in ipairs(Ideas().learnable) do
      if idea.e.id == 19066 then return idea end
    end
  end
  local items = ES.db.scans[ES:RealmKey()].items
  items[r.out[1]].listings = ES.Earn.LEARN_MIN_LISTINGS
  expect(Find(), "con %d subastas no propone aprender Frostsaber Boots (la prueba no prueba nada)", ES.Earn.LEARN_MIN_LISTINGS)
  -- Una sola subasta (una unidad), cara
  items[r.out[1]].listings, items[r.out[1]].quantity = 1, 1
  items[r.out[1]].ladder = { 500000, 1 }
  expect(not Find(), "con una sola subasta propone aprender Frostsaber Boots")
  -- La fila dice cuántos hay a la venta
  items[r.out[1]].listings, items[r.out[1]].quantity = 5, 40
  items[r.out[1]].ladder = { 500000, 40 }
  ES.Earn:Clear()
  OpenPage("money")
  local found
  for _, row in ipairs(ES.earnPage.rows or {}) do
    if row:IsShown() and row.item == r.out[1] then found = row end
  end
  expect(found, "no sale la fila de Frostsaber Boots en «Recetas que podrías aprender»")
  local sub = tostring(found.sub:GetText())
  local want = string.format(ES.L["AH %s/u (%d a la venta) · %s"], "", 40, ""):match("%((.-)%)")
  expect(sub:find(want, 1, true), "la fila no dice cuántos hay a la venta: %s", sub)
end, { state = "full" })

-- Spec recipe-requirements: con el icono de misión de la profesión desactivado, no se
-- propone aprender una receta que su instructor solo enseña tras una misión que no has
-- hecho (Discolored Healing Potion: Odd Child / Apothecary Renferrel)
test("recetas para aprender: sin la misión y con el icono desactivado, no salen las Discolored", function()
  local LESSER = 1244645
  local r = ES.Data.Alchemy.recipes[LESSER]
  expect(r and r.unlock, "Lesser Discolored Healing Potion no pide misión: la prueba no prueba nada")
  FACTION = "Alliance"
  SKILLS[ES.Data.Alchemy.skillLine] = { 100, 150 }
  for _, m in ipairs(r.r) do SetPrice(m[1], 1, 5000) end -- materiales baratos
  SetPrice(r.out[1], 500000, 40)                          -- lo fabricado, caro
  local function Offered()
    for _, idea in ipairs(Ideas().learnable) do
      if idea.e.id == LESSER then return true end
    end
    return false
  end
  expect(Offered(), "con el icono de misión activado no propone aprender Lesser Discolored (la prueba no prueba nada)")
  ES.db.prof = ES.db.prof or {}
  ES.db.prof.Alchemy = ES.db.prof.Alchemy or {}
  ES.db.prof.Alchemy.useQuests = false
  expect(not Offered(), "con el icono desactivado y sin la misión, propone aprender Lesser Discolored")
  QUESTS_DONE[92110] = true
  expect(Offered(), "con la misión hecha no propone aprender Lesser Discolored")
end, { state = "full" })

test("quitar una receta de Ganar dinero y recuperarla", function()
  local res = Ideas()
  local first = expect(res.batch[1], "sin ideas")
  local id = first.e.id
  ES.Earn.SetHidden(id, true)
  res = Ideas()
  for _, i in ipairs(res.ideas) do expect(i.e.id ~= id, "la receta quitada sigue en las ideas") end
  expect(res.removed >= 1, "no cuenta la quitada")
  ES.Earn.SetHidden(id, false)
  res = Ideas()
  local back = false
  for _, i in ipairs(res.ideas) do if i.e.id == id then back = true end end
  expect(back, "la receta no vuelve")
end, { state = "full" })

test("cambiar la cantidad de una línea con los botones", function()
  local res = Ideas()
  local idea
  for _, i in ipairs(res.batch) do if i.sellWhere == "ah" and not i.cooldown then idea = i break end end
  expect(idea, "sin ideas de AH en el lote")
  local before = idea.crafts
  ES.Earn.StepQuantity(idea, 5)
  res = Ideas()
  local after
  for _, i in ipairs(res.ideas) do if i.e.id == idea.e.id then after = i end end
  expect(after and after.custom, "la cantidad elegida no se guarda")
  expect_eq(after.crafts, before + 5, "fabricaciones tras +5")
  -- y la página se pinta con ella
  OpenPage("money")
end, { state = "full" })

-- Enfriamiento con el PC reiniciado después de transmutar: GetSpellCooldown da el inicio
-- desbordado (2^32 ms más tarde). Salía "Listo en 1195 h" con 59 min de verdad (Arcanite Bar)
test("enfriamiento empezado antes de arrancar el PC: las horas de verdad", function()
  local ARCANITE, WRAP = 17187, 2 ^ 32 / 1000
  local left = 59 * 60
  -- (transmutación: 1 día; empezó hace 23 h y 1 min, contado desde antes del arranque)
  GetSpellCooldown = function(id)
    if id == ARCANITE then return NOW - (86400 - left) + WRAP, 86400, 1 end
    return 0, 0, 1
  end
  expect_near(ES.Earn.CooldownLeft(ARCANITE), left, 1, "segundos que faltan")
  expect_near(ES.charData.cdReady[ARCANITE] - time(), left, 1, "lo guardado")
  -- Sin desbordar, igual
  GetSpellCooldown = function() return NOW - (86400 - left), 86400, 1 end
  expect_near(ES.Earn.CooldownLeft(ARCANITE), left, 1, "segundos que faltan (sin desbordar)")
  -- Lo guardado antes del arreglo (1193 h de más) no se fía: no se sabe
  GetSpellCooldown = function() return 0, 0, 1 end
  ES.charData.cdReady[ARCANITE] = time() + WRAP + left
  expect_eq(ES.Earn.CooldownLeft(ARCANITE), nil, "lo guardado con 1193 h de más")
  expect_eq(ES.charData.cdReady[ARCANITE], nil, "se borra lo guardado mal")
end, { state = "full" })

---------------------------------------------------------------------------
-- Con la ventana cerrada un rato se sueltan las cachés (lighter-memory, UI.lua)
---------------------------------------------------------------------------
local function KB()
  collectgarbage("collect")
  collectgarbage("collect")
  return collectgarbage("count")
end

-- Las ideas de Ganar dinero en texto (para comparar dos cálculos)
local function Digest(res)
  local t = {}
  for _, list in ipairs({ res.batch or {}, res.vendor or {} }) do
    for _, idea in ipairs(list) do
      t[#t + 1] = string.format("%s:%s:%s:%.4f:%.4f:%.4f", tostring(idea.profKey), tostring(idea.e.id), tostring(idea.crafts),
        idea.profit or 0, idea.invest or 0, idea.sale or 0)
    end
  end
  return table.concat(t, "\n"), #t
end

local function OpenMoney()
  ES.db.earnMinProfit = 1 -- (todas las que dejan algo)
  OpenPage("money")
  return ES.Earn:Ideas()
end

test("ventana cerrada un minuto: se sueltan las cachés de Ganar dinero", function()
  OpenMoney()
  -- Lo que ocupa la caché de Ganar dinero
  local with = KB()
  ES.Earn:Clear()
  local cache = with - KB()
  OpenMoney()
  ES:HideMainFrame()
  RunTimers(ES.IDLE_RELEASE - 5)
  local closed = KB()
  RunTimers(10)
  local freed = closed - KB()
  note("caché de Ganar dinero %.0f KB; liberado al minuto %.0f KB", cache, freed)
  expect(cache > 50, "la caché de Ganar dinero ocupa %.0f KB: la prueba no comprueba nada", cache)
  expect(freed >= cache * 0.9, "al minuto se liberan %.0f KB y la caché ocupaba %.0f KB", freed, cache)
end, { state = "full" })

test("ventana cerrada y abierta otra vez antes del minuto: Ganar dinero no se recalcula", function()
  local res = OpenMoney()
  ES:HideMainFrame()
  RunTimers(30)
  OpenMain()
  RunTimers(ES.IDLE_RELEASE)
  expect(ES.Earn:Ideas() == res, "Ganar dinero se recalculó al volver a abrir antes del minuto")
  -- Abrir y cerrar otra vez: cuenta el último cierre
  ES:HideMainFrame()
  RunTimers(30)
  expect(ES.Earn:Ideas() == res, "se soltó antes del minuto desde el último cierre")
  RunTimers(ES.IDLE_RELEASE)
  expect(ES.Earn:Ideas() ~= res, "no se soltó al minuto del último cierre")
end, { state = "full" })

test("ventana cerrada un minuto: la ruta empezada no se recalcula", function()
  local _, plan = StartRoute("Tailoring", 1, 75)
  local calls = 0
  local Plan = ES.Planner.Plan
  ES.Planner.Plan = function(...) calls = calls + 1 return Plan(...) end
  ES:HideMainFrame()
  local ok, err = pcall(RunTimers, ES.IDLE_RELEASE + 5)
  ES.Planner.Plan = Plan
  if not ok then error(err, 0) end
  expect(ES:LockedPlan("Tailoring") == plan, "la ruta fijada cambió al soltar las cachés")
  expect_eq(calls, 0, "rutas calculadas con la ventana cerrada")
end, { state = "full" })

test("soltadas las cachés, Ganar dinero da lo mismo al volver", function()
  local before, n = Digest(OpenMoney())
  ES:HideMainFrame()
  RunTimers(ES.IDLE_RELEASE + 5)
  local t = os.clock()
  local after = Digest(OpenMoney())
  note("%d líneas; recalcular al volver a abrir: %.0f ms (en el Lua de las pruebas)", n, (os.clock() - t) * 1000)
  expect(n > 0, "sin ideas: la prueba no comprueba nada")
  expect_eq(after, before, "ideas, cantidades y beneficios")
end, { state = "full" })

test("soltadas las cachés, la ventana de fabricar calcula sus ideas", function()
  local res = OpenMoney()
  local prof = expect(res.batch[1], "sin ideas").profKey
  local function List()
    local t = {}
    for _, idea in ipairs(ES.CraftWindow:List(prof)) do t[#t + 1] = idea.e.id .. "x" .. idea.crafts end
    return table.concat(t, " ")
  end
  local before = List()
  ES:HideMainFrame()
  RunTimers(ES.IDLE_RELEASE + 5)
  expect(ES.Earn:Ideas() ~= res, "no se soltó la caché")
  expect_eq(List(), before, "ideas de la ventana de fabricar de " .. prof)
  expect(before ~= "", "la ventana de fabricar no tiene ideas: la prueba no comprueba nada")
end, { state = "full" })

-- Las filas pintadas guardan sus funciones de clic, tooltip y − / +, y con ellas la idea
-- (y todo su cálculo): soltada la caché, seguían en memoria mientras no se repintara
test("soltadas las cachés, las filas de Ganar dinero no se quedan con las ideas", function()
  local res = OpenMoney()
  local idea
  for _, i in ipairs(res.batch) do if i.sellWhere == "ah" and not i.cooldown then idea = i break end end
  expect(idea, "sin ideas de AH en el lote (con botones - y +): la prueba no comprueba nada")
  local weak = setmetatable({ idea = idea }, { __mode = "v" })
  idea, res = nil, nil
  ES:HideMainFrame()
  RunTimers(ES.IDLE_RELEASE + 5)
  collectgarbage("collect")
  collectgarbage("collect")
  expect(weak.idea == nil, "la idea sigue en memoria tras soltar las cachés (la guarda una fila)")
  -- Al volver, la página se pinta entera otra vez
  OpenMoney()
  local shown = 0
  for _, row in ipairs(ES.earnPage.rows or {}) do if row:IsShown() then shown = shown + 1 end end
  expect(shown > 0, "al volver a abrir Ganar dinero no se pinta")
end, { state = "full" })

test("una fila que se repinta sin botones - y + suelta los de antes", function()
  OpenMoney()
  local page = ES.earnPage
  local withStep
  for _, row in ipairs(page.rows) do if row.onStep then withStep = row break end end
  expect(withStep, "ninguna fila con botones - y +: la prueba no comprueba nada")
  ES.UI.RenderLines(page, { { title = "a" }, { title = "b" } })
  for i, row in ipairs(page.rows) do
    expect(row.onStep == nil and row.onClick == nil and row.tooltip == nil, "la fila %d se queda con lo de antes", i)
  end
end, { state = "full" })

test("dinero: negativos, NaN e infinito no dan error al pintarse", function()
  for _, v in ipairs({ -12345, 0, 1, 99999999, 0 / 0, math.huge, -math.huge }) do
    no_error(ES.Money, v)
  end
end)
