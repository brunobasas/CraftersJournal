-- Inversiones: la cartera (precio medio, beneficio, comisión, cuenta o personaje), el
-- historial de precios de Auctionator (simulado: InstallAuctionator, AUCTIONATOR_DAYS)
-- y la pestaña

local SILK, LOTUS, WOOL, PYRITE = 4306, 13468, 2592, 9258
local L = setmetatable({}, { __index = function(_, k) return ES.L[k] end }) -- (los textos, en el idioma de ahora)
local S, G = 100, 10000 -- 1 plata, 1 oro (en cobre)

-- Historial de Auctionator de un objeto: { [días atrás] = precio, ... }
local function Days(itemID, list)
  local t = {}
  for ago, price in pairs(list) do t[#t + 1] = { ago = ago, max = price, avail = 100 } end
  AUCTIONATOR_DAYS[itemID] = t
  ES.PriceHistory.Clear()
end

local function Buy(itemID, n, price, total)
  local ok, why = ES.Invest:Add(itemID, "buy", n, price, total)
  expect(ok, "la compra no se guarda: %s", tostring(why))
end

-- Un escaneo con el objeto `id` a la venta: ladder = { precio, cantidad, ... }
local function ScanWith(id, ladder, when)
  local scan = ES.db.scans[ES:RealmKey()]
  local qty = 0
  for i = 2, #ladder, 2 do qty = qty + ladder[i] end
  scan.items[id] = { minUnit = ladder[1], quantity = qty, listings = #ladder / 2, ladder = ladder }
  scan.time = when or NOW
  return scan
end

---------------------------------------------------------------------------
-- Historial de Auctionator
---------------------------------------------------------------------------
test("historial: sin Auctionator no hay precio y no hay errores", function()
  expect(not ES.PriceHistory.Available(), "dice que hay Auctionator")
  expect_eq(ES.PriceHistory:Get(SILK), nil, "historial sin Auctionator")
end)

test("historial: Auctionator que da error o filas con otra forma", function()
  InstallAuctionator()
  AUCTIONATOR_FAIL = true
  expect_eq(ES.PriceHistory:Get(SILK), nil, "con error")
  AUCTIONATOR_FAIL = nil
  ES.PriceHistory.Clear()
  AUCTIONATOR_ROWS = { { rawDay = "x", maxSeen = 100 }, { maxSeen = 100 }, { rawDay = "5" }, "fila", { rawDay = "6", maxSeen = -3 } }
  expect_eq(ES.PriceHistory:Get(SILK), nil, "sin filas válidas")
  ES.PriceHistory.Clear()
  AUCTIONATOR_ROWS = { { rawDay = tostring(AuctionatorToday()), maxSeen = 150 }, { rawDay = "?", maxSeen = 1 } }
  local h = expect(ES.PriceHistory:Get(SILK), "una fila buena entre malas: sin precio")
  expect_eq(h.now.price, 150, "precio de la fila buena")
  AUCTIONATOR_ROWS = "no es una tabla"
  ES.PriceHistory.Clear()
  expect_eq(ES.PriceHistory:Get(SILK), nil, "otra forma")
end)

test("historial: el precio del día es el que enseña Auctionator (el mínimo más bajo del día)", function()
  InstallAuctionator()
  -- Pyrite en el juego: hoy Auctionator vio 2s 97c y luego 1s 84c; su ventana dice 1s 84c
  -- (antes se usaba el mínimo más alto del día y salía 2s 97c: no cuadraba)
  AUCTIONATOR_DAYS[SILK] = { { ago = 0, min = 184, max = 297 }, { ago = 1, min = 225, max = 240 } }
  local h = expect(ES.PriceHistory:Get(SILK), "sin historial")
  expect_eq(h.now.price, 184, "precio de hoy")
  expect_eq(h.days[1].price, 225, "precio de ayer")
  expect_eq(h.now.age, 0, "antigüedad")
  expect(not h.now.stale, "hoy marcado como viejo")
end)

test("historial: el precio de ahora es el último mínimo que vio Auctionator", function()
  InstallAuctionator()
  -- Pyrite: hoy vio 1s 84c a primera hora (se vendió) y en su último escaneo 2s 30c
  AUCTIONATOR_DAYS[SILK] = { { ago = 0, min = 184, max = 297 }, { ago = 1, min = 225, max = 240 } }
  AUCTIONATOR_LATEST = { [SILK] = { price = 230, age = 0 } }
  local h = expect(ES.PriceHistory:Get(SILK), "sin historial")
  expect_eq(h.now.price, 230, "precio de ahora: el último mínimo, no el más bajo del día")
  expect_eq(h.days[#h.days].price, 230, "el punto de hoy en la gráfica, el mismo")
  expect_eq(h.days[1].price, 225, "ayer, el mínimo del día (como su ventana de historial)")
  -- El último escaneo con ese objeto fue hace 2 días: ese día lleva el último mínimo
  AUCTIONATOR_DAYS[SILK] = { { ago = 2, min = 200 }, { ago = 3, min = 210 } }
  AUCTIONATOR_LATEST = { [SILK] = { price = 215, age = 2 } }
  ES.PriceHistory.Clear()
  h = ES.PriceHistory:Get(SILK)
  expect(h.now.price == 215 and h.now.age == 2, "precio de hace 2 días: %s, %s", tostring(h.now.price), tostring(h.now.age))
  expect_eq(#h.days, 2, "días")
end)

test("historial: una bajada que rebota es un día dudoso", function()
  InstallAuctionator()
  -- Silk Cloth: 1s 90c hace 4 días, 20c hace 3 días y 1s 94c hoy
  Days(SILK, { [4] = 190, [3] = 20, [0] = 194 })
  local h = expect(ES.PriceHistory:Get(SILK), "sin historial")
  expect_eq(#h.days, 3, "días")
  expect(not h.days[1].dubious and h.days[2].dubious and not h.days[3].dubious, "el día de 20c debe ser el único dudoso")
  expect_eq(h.now.price, 194, "precio de ahora")
  -- El dudoso no cuenta para "últimos 4 días": compara con el de hace 4 días
  expect_near(h.change4, 194 / 190 - 1, 1e-9, "cambio de 4 días")
end)

test("historial: la bajada del último día se usa sin confirmar", function()
  InstallAuctionator()
  Days(SILK, { [1] = 190, [0] = 50 })
  local h = ES.PriceHistory:Get(SILK)
  expect_eq(h.now.price, 50, "precio de ahora")
  expect(h.now.unconfirmed, "no marca la bajada sin confirmar")
end)

test("historial: precio viejo y cambio de los últimos 4 días", function()
  InstallAuctionator()
  Days(LOTUS, { [5] = 10 * G })
  local h = ES.PriceHistory:Get(LOTUS)
  expect_eq(h.now.age, 5, "antigüedad")
  expect(h.now.stale, "de hace 5 días no sale como viejo")
  -- 10g 88s ahora y 12g 22s hace 4 días: -11 %
  Days(LOTUS, { [0] = 10 * G + 88 * S, [4] = 12 * G + 22 * S })
  h = ES.PriceHistory:Get(LOTUS)
  expect_eq(math.floor(h.change4 * 100 + 0.5), -11, "cambio de 4 días (%)")
  -- Sin un día de hace 3 a 5 días: desconocido
  Days(LOTUS, { [0] = 10 * G, [10] = 12 * G })
  h = ES.PriceHistory:Get(LOTUS)
  expect_eq(h.change4, nil, "sin dato cercano")
end)

test("historial: se vuelve a leer al acabar un escaneo de Auctionator", function()
  InstallAuctionator()
  Days(SILK, { [0] = 100 })
  ES.PriceHistory.Watch()
  expect_eq(ES.PriceHistory:Get(SILK).now.price, 100, "antes")
  AUCTIONATOR_DAYS[SILK] = { { ago = 0, max = 300 } }
  expect_eq(ES.PriceHistory:Get(SILK).now.price, 100, "lo leído se recuerda")
  AuctionatorUpdated()
  expect_eq(ES.PriceHistory:Get(SILK).now.price, 300, "tras el escaneo de Auctionator")
end)

---------------------------------------------------------------------------
-- Cartera: cálculos
---------------------------------------------------------------------------
test("cartera: dos compras a distinto precio dan el precio medio", function()
  Buy(SILK, 20, 2 * S)
  Buy(SILK, 20, 4 * S)
  local e = ES.Invest:Item(SILK)
  expect_eq(e.units, 40, "unidades")
  expect_eq(e.cost, 120 * S, "coste")
  expect_eq(e.avg, 3 * S, "precio medio")
end)

test("cartera: compra escrita como total", function()
  Buy(LOTUS, 3, 24 * G, true)
  local e = ES.Invest:Item(LOTUS)
  expect_eq(e.units, 3, "unidades")
  expect_eq(e.cost, 24 * G, "coste")
  expect_eq(e.moves[1].unit, 8 * G, "por unidad")
end)

test("cartera: cantidad o precio que no valen no se guardan", function()
  for _, bad in ipairs({ 0, -2, 1.5, "abc", "" }) do
    local ok, why = ES.Invest:Add(SILK, "buy", bad, 200)
    expect(not ok and why == "qty", "cantidad %s aceptada", tostring(bad))
  end
  local ok, why = ES.Invest:Add(SILK, "buy", 5, nil)
  expect(not ok and why == "price", "precio vacío aceptado")
  expect_eq(next(ES.Invest.Book()), nil, "se guardó algo")
end)

test("cartera: venta con el método del precio medio y su realizado", function()
  Buy(SILK, 20, 2 * S)
  Buy(SILK, 20, 4 * S)
  local ok = ES.Invest:Add(SILK, "sell", 15, 5 * S)
  expect(ok, "la venta no se guarda")
  local e = ES.Invest:Item(SILK)
  expect_eq(e.units, 25, "quedan")
  expect_near(e.avg, 3 * S, 1e-9, "la media no cambia")
  expect_near(e.cost, 75 * S, 1e-9, "coste de lo que queda")
  -- 75s cobrados - 3s 75c de comisión - 45s de coste = 26s 25c
  expect_near(e.realized, 26 * S + 25, 1e-9, "realizado")
  local ok2, why, have = ES.Invest:Add(SILK, "sell", 30, 5 * S)
  expect(not ok2 and why == "units" and have == 25, "vender 30 de 25: %s %s", tostring(why), tostring(have))
end)

test("cartera: valor, neto y latente con el precio de Auctionator", function()
  InstallAuctionator()
  Days(LOTUS, { [0] = 10 * G + 88 * S })
  Buy(LOTUS, 5, 45 * G, true)
  local e = ES.Invest:Item(LOTUS)
  expect_eq(e.value, 54 * G + 40 * S, "valor")
  expect_near(e.net, 51 * G + 68 * S, 0.5, "neto tras la AH")
  expect_near(e.latent, 6 * G + 68 * S, 0.5, "latente")
end)

test("cartera: borrar movimientos recalcula, y lo que no cuadra se marca", function()
  Buy(SILK, 20, 2 * S)
  Buy(SILK, 20, 4 * S)
  ES.Invest:Remove(SILK, 2)
  local e = ES.Invest:Item(SILK)
  expect_eq(e.units, 20, "unidades tras borrar")
  expect_eq(e.avg, 2 * S, "media tras borrar")
  ES.Invest:Add(SILK, "sell", 15, 5 * S)
  ES.Invest:Remove(SILK, 1)
  e = ES.Invest:Item(SILK)
  expect(e.broken, "una venta sin compra no se marca")
  local sum = ES.Invest:Summary()
  expect_eq(#sum.broken, 1, "en revisar")
  expect_eq(sum.totals.cost, 0, "no suma en la cabecera")
end)

test("cartera: vender todo pasa a cerradas y su realizado sigue sumando", function()
  Buy(SILK, 25, 3 * S)
  ES.Invest:Add(SILK, "sell", 25, 5 * S)
  local sum = ES.Invest:Summary()
  expect_eq(#sum.open, 0, "abiertas")
  expect_eq(#sum.closed, 1, "cerradas")
  expect_near(sum.totals.realized, 25 * 5 * S * 0.95 - 75 * S, 1e-9, "realizado en la cabecera")
end)

test("cartera: totales con un objeto sin precio y otro cerrado", function()
  InstallAuctionator()
  Days(LOTUS, { [0] = 10 * G })
  Buy(LOTUS, 2, 8 * G)
  Buy(PYRITE, 10, 2 * S)
  Buy(SILK, 10, 2 * S)
  ES.Invest:Add(SILK, "sell", 10, 3 * S)
  local t = ES.Invest:Summary().totals
  expect_eq(t.cost, 16 * G + 20 * S, "invertido (con y sin precio)")
  expect_eq(t.value, 20 * G, "valor (solo con precio)")
  expect_eq(t.missing, 1, "sin precio")
  expect_near(t.latent, 20 * G * 0.95 - 16 * G, 1e-9, "latente")
  expect_near(t.realized, 30 * S * 0.95 - 20 * S, 1e-9, "realizado (el cerrado)")
end)

---------------------------------------------------------------------------
-- Cartera de la cuenta (todos tus personajes)
---------------------------------------------------------------------------
test("cartera: siempre de la cuenta, la comparten todos tus personajes", function()
  Buy(SILK, 20, 2 * S)
  -- Otro personaje del mismo reino y facción: la misma cartera, y lo que apunta se ve
  -- con el primero
  UnitName = function() return "Otra" end
  UnitGUID = function() return "Player-1-00000002" end
  expect(ES.Invest.Book()[SILK], "otro personaje no ve la cartera de la cuenta")
  Buy(LOTUS, 1, G)
  -- (la opción de una cartera por personaje ya no existe; aunque quede guardada, no cuenta)
  ES.db.investPerChar = true
  local book = ES.Invest.Book()
  expect(book[SILK] and book[LOTUS], "la cartera no es la misma para todos")
  for _, o in ipairs(ES.OPTIONS) do expect(o.key ~= "investPerChar", "sigue la opción de una cartera por personaje") end
end)

test("cartera: otra facción, otra cartera", function()
  Buy(SILK, 20, 2 * S)
  FACTION = "Horde"
  ES.Keys.Reset() -- (otro personaje: otra sesión, la clave se vuelve a mirar)
  expect_eq(next(ES.Invest.Book()), nil, "la Horda ve la cartera de la Alianza")
end)

---------------------------------------------------------------------------
-- La pestaña
---------------------------------------------------------------------------
local function Page() return ES:GetMainFrame().pages.invest end
local function ItemPage() return ES:GetMainFrame().pages.investItem end
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end
local function CardOf(itemID)
  for i = 1, Page().shownCards or 0 do
    local c = Page().cards[i]
    if c.itemID == itemID and c:IsShown() then return c end
  end
end

for _, state in ipairs({ "empty", "scan", "full" }) do
  test("la pestaña se abre: " .. state, function()
    OpenPage("invest")
    expect(Page():IsShown(), "la página no se ve")
    local empty = next(ES.Invest.Book()) == nil
    expect((Page().empty:GetText() ~= "") == empty, "el texto de cartera vacía no cuadra con la cartera")
    if not empty then expect((Page().shownCards or 0) > 0, "con cartera no sale ninguna ficha") end
  end, { state = state })
end

local TIP = "Precios de tus últimos escaneos. Instala Auctionator para volver a escanear y tener el historial de precios."

test("pestaña: sin Auctionator, sin escaneos, aconseja Auctionator y enseña lo que no depende del precio", function()
  Buy(SILK, 20, 2 * S)
  OpenPage("invest")
  expect(Page().status:GetText():find(L[TIP], 1, true), "sin Auctionator no sale el consejo: %s", Page().status:GetText())
  expect(Page().tipClose:IsShown(), "el consejo sin su X")
  local c = expect(CardOf(SILK), "no hay ficha de Silk Cloth")
  expect(Plain(c.sub:GetText()):find("20 u", 1, true), "la ficha no dice las unidades: %s", c.sub:GetText())
  expect(Plain(c.price:GetText()):find(L["Sin precio: instala Auctionator"], 1, true), "sin precio: %s", c.price:GetText())
  expect_eq(Page().stats.cost:GetText(), ES.Money(40 * S), "invertido")
  -- La X: no vuelve a salir (se recuerda)
  Page().tipClose:GetScript("OnClick")(Page().tipClose)
  expect(ES.db.investNoAuctionatorTip and not Page().status:GetText():find(L[TIP], 1, true) and not Page().tipClose:IsShown(),
    "la X no quita el consejo")
  ES:SelectPage("home")
  OpenPage("invest")
  expect(not Page().status:GetText():find(L[TIP], 1, true), "el consejo vuelve tras cerrarlo")
end)

local SOURCE_AUCTIONATOR = "Precios del historial de Auctionator: se ponen al día cada vez que escaneas."

test("pestaña: con Auctionator, la línea dice que los precios son de su historial", function()
  InstallAuctionator()
  Buy(SILK, 20, 2 * S)
  OpenPage("invest")
  expect(not Page().status:GetText():find(L[TIP], 1, true) and not Page().tipClose:IsShown(), "con Auctionator sale el consejo")
  expect(Page().status:GetText():find(L[SOURCE_AUCTIONATOR], 1, true), "la línea no dice de dónde salen los precios: %s", Page().status:GetText())
  for _, o in ipairs(ES.OPTIONS) do expect(o.key ~= "noInvestAuctionator", "sigue la opción de usar el historial de Auctionator") end
end)

test("Mayús+clic en el objeto (detalle, ficha y fila) lo busca en la AH", function()
  Buy(LOTUS, 1, 9 * G)
  AuctionFrame:Show()
  FireEvent("AUCTION_HOUSE_SHOW")
  local searched = {}
  ES.SearchAuction = function(_, id) searched[#searched + 1] = id end
  OpenPage("invest")
  IsShiftKeyDown = function() return true end
  -- Ficha: busca y no abre el detalle
  local card = CardOf(LOTUS)
  card:GetScript("OnClick")(card)
  expect_eq(searched[1], LOTUS, "Mayús+clic en la ficha")
  expect_eq(ES.db.lastPage, "invest", "Mayús+clic en la ficha abre el detalle")
  -- Fila de la lista
  ES.db.investView = "list"
  ES:RenderInvest()
  local row = Page().rows[1]
  row:GetScript("OnClick")(row)
  expect_eq(searched[2], LOTUS, "Mayús+clic en la fila")
  -- Icono y nombre del detalle
  IsShiftKeyDown = function() return false end
  ES:ShowInvestItem(LOTUS)
  RunTimers()
  local b = ItemPage().itemButton
  b:GetScript("OnClick")(b)
  expect_eq(#searched, 2, "un clic sin Mayús en el icono busca en la AH")
  IsShiftKeyDown = function() return true end
  b:GetScript("OnClick")(b)
  expect_eq(searched[3], LOTUS, "Mayús+clic en el icono del detalle")
end)

test("tooltips: de dónde sale cada precio", function()
  Buy(LOTUS, 1, 9 * G)
  ES.Invest.RecordScan(ScanWith(LOTUS, { 10 * G, 50 }))
  local function Tip(itemID)
    ResetTooltip()
    local c = CardOf(itemID)
    c:GetScript("OnEnter")(c)
    return table.concat(TOOLTIP, "\n")
  end
  -- Sin Auctionator: de tu escaneo
  OpenPage("invest")
  expect(Tip(LOTUS):find(string.format(L["De tu escaneo de %s"], L["hoy"]), 1, true), "sin Auctionator: %s", Tip(LOTUS))
  -- Con Auctionator: de su historial
  InstallAuctionator()
  Days(LOTUS, { [0] = 12 * G })
  ES:SelectPage("home")
  OpenPage("invest")
  expect(Tip(LOTUS):find(L["Del historial de Auctionator"], 1, true), "con Auctionator: %s", Tip(LOTUS))
  -- El detalle: la celda Precio ahora
  ES:ShowInvestItem(LOTUS)
  RunTimers()
  ResetTooltip()
  local cell = ItemPage().boxes.now
  cell:GetScript("OnEnter")(cell)
  expect(table.concat(TOOLTIP, "\n"):find(L["Del historial de Auctionator"], 1, true), "celda Precio ahora")
end)

test("detalle: la línea de lo que tienes no se corta (quita partes y las enseña al pasar el ratón)", function()
  InstallAuctionator()
  Days(WOOL, { [0] = 163 })
  Buy(WOOL, 2, 10 * G)
  OpenPage("invest")
  local page = ItemPage()
  ES:ShowInvestItem(WOOL)
  RunTimers()
  local pos = page.position
  -- Con sitio de sobra: todo
  local full = Plain(pos:GetText())
  for _, key in ipairs({ "invertido", "neto tras la AH", "Si vendes" }) do
    expect(full:find(L[key], 1, true), "con sitio falta %s: %s", key, full)
  end
  -- Poco sitio (como en el juego, entre el título y los botones): fuera el neto y luego
  -- lo invertido; lo que tienes y Si vendes se quedan
  pos.GetWidth = function() return 300 end
  pos.GetStringWidth = function(self) return #Plain(self._text) * 5 end
  ES:RenderInvestItem()
  local short = Plain(pos:GetText())
  expect(#short * 5 <= 300, "sigue sin caber: %s", short)
  expect(not short:find(L["neto tras la AH"], 1, true), "no quitó el neto tras la AH: %s", short)
  expect(short:find(L["Si vendes"], 1, true) and short:find(string.format(L["Tienes %d u"], 2), 1, true),
    "quitó lo importante: %s", short)
  -- Al pasar el ratón, todo
  ResetTooltip()
  page.positionHit:GetScript("OnEnter")(page.positionHit)
  local tip = table.concat(TOOLTIP, "\n")
  for _, key in ipairs({ "invertido", "neto tras la AH", "Si vendes" }) do
    expect(tip:find(L[key], 1, true), "el tooltip no tiene %s", key)
  end
  pos.GetWidth, pos.GetStringWidth = nil, nil
end)

test("tooltip del precio: cuántas unidades había a ese precio en el último escaneo", function()
  InstallAuctionator()
  Days(WOOL, { [0] = 100, [1] = 128 })
  AUCTIONATOR_LATEST = { [WOOL] = { price = 100, age = 0 } }
  Buy(WOOL, 40, 128)
  -- Último escaneo de hace 5 min: 1 suelta a 1s, el resto desde 1s 25c
  local key = ES:RealmKey()
  ES.db.scans[key] = { time = NOW - 300, total = 41, unique = 1,
    items = { [WOOL] = { listings = 3, quantity = 41, minUnit = 100, ladder = { 100, 1, 125, 20, 130, 20 } } } }
  OpenPage("invest")
  local function Tip()
    ResetTooltip()
    local c = expect(CardOf(WOOL), "sin ficha")
    c:GetScript("OnEnter")(c)
    return table.concat(TOOLTIP, "\n")
  end
  local ago = ES.TimeAgo(NOW - 300)
  local want = string.format(L["Último escaneo (%s): %s u a este precio o menos"], ago, "1")
    .. string.format(L[" · el resto desde %s"], ES.Money(125))
  expect(Tip():find(want, 1, true), "la ficha no dice cuántas hay a ese precio: %s", Tip())
  -- El detalle: la celda Precio ahora
  ES:ShowInvestItem(WOOL)
  RunTimers()
  ResetTooltip()
  local cell = ItemPage().boxes.now
  cell:GetScript("OnEnter")(cell)
  expect(table.concat(TOOLTIP, "\n"):find(want, 1, true), "la celda Precio ahora no lo dice")
  -- Una subasta nueva después del escaneo, más barata que todo lo escaneado
  expect_eq(ES.InvestDepthLine(WOOL, 90),
    string.format(L["Último escaneo (%s): nada a este precio; lo más barato, %s"], ago, ES.Money(100)), "más barata que el escaneo")
  -- Todo al mismo precio: sin "el resto desde"
  expect_eq(ES.InvestDepthLine(WOOL, 200), string.format(L["Último escaneo (%s): %s u a este precio o menos"], ago, "41"), "todo por debajo")
  -- Escaneo de hace más de 12 h, o sin el objeto: nada
  ES.db.scans[key].time = NOW - 13 * 3600
  expect_eq(ES.InvestDepthLine(WOOL, 100), nil, "escaneo viejo")
  ES.db.scans[key].time = NOW
  expect_eq(ES.InvestDepthLine(LOTUS, 100), nil, "objeto que no salió en el escaneo")
end)

---------------------------------------------------------------------------
-- Precios de tus escaneos (solo sin Auctionator)
---------------------------------------------------------------------------

test("tus escaneos: el precio del día no cuenta una subasta suelta y se guarda al escanear", function()
  -- Lo de la cartera se sigue en el escaneo (su escalera de precios), aunque no sea de
  -- profesiones (900500: ninguna receta lo usa)
  expect(not ES.History:IsTracked(900500), "un objeto de fuera de las recetas ya se seguía")
  Buy(900500, 1, 100)
  expect(ES.History:IsTracked(900500), "lo de la cartera no se sigue en el escaneo")
  Buy(LOTUS, 2, 9 * G)
  -- Una suelta a 5g y 30 a 10g: cuenta la de 10g (hacen falta 2 unidades)
  ES:OnScanComplete(ScanWith(LOTUS, { 5 * G, 1, 10 * G, 30 }), true)
  RunTimers()
  expect(type(ES.db.investPrices[ES:RealmKey()][LOTUS]) == "string", "no se guarda el precio del día")
  local h = expect(ES.PriceHistory:Get(LOTUS), "sin precio tras escanear")
  expect_eq(h.source, "scans", "fuente")
  expect_eq(h.now.price, 10 * G, "precio del día")
  expect_eq(ES.Invest:Item(LOTUS).price, 10 * G, "precio de la ficha")
end)

test("tus escaneos: el último escaneo del día, un día nuevo se añade y se olvida lo de hace más de 30 días", function()
  Buy(LOTUS, 1, 9 * G)
  local DAY = 86400
  NOW = 400 * DAY + 3600 -- (la hora de las pruebas es de 1970: así "hace 40 días" no cae antes)
  ES.Invest.RecordScan(ScanWith(LOTUS, { 12 * G, 50 }, NOW - 40 * DAY))
  ES.Invest.RecordScan(ScanWith(LOTUS, { 11 * G, 50 }, NOW - 2 * DAY))
  ES.Invest.RecordScan(ScanWith(LOTUS, { 10 * G, 50 }, NOW - 2 * DAY + 60))
  ES.Invest.RecordScan(ScanWith(LOTUS, { 13 * G, 50 }, NOW))
  local days = ES.Invest.OwnDays(LOTUS)
  expect_eq(#days, 2, "días (el de hace 40 se olvida)")
  -- (el último del día: un escaneo raro se corrige con el siguiente)
  expect_eq(days[1].price, 10 * G, "el último escaneo del día")
  expect_eq(days[2].price, 13 * G, "hoy")
  local h = ES.PriceHistory:Get(LOTUS)
  expect_eq(h.now.age, 0, "precio de hoy")
end)

test("tus escaneos: un escaneo raro que dispara el precio no es el precio de ahora (Small Flame Sac a 1g)", function()
  local SAC, DAY = 4402, 86400
  NOW = 400 * DAY + 3600
  Buy(SAC, 40, 1203)
  -- Tres días a ~12s y hoy un escaneo con solo 1 a 12s y el resto a 1g
  for ago, p in pairs({ [3] = 1200, [2] = 1210, [1] = 1190 }) do
    ES.Invest.RecordScan(ScanWith(SAC, { p, 40, p + 100, 200 }, NOW - ago * DAY))
  end
  ES.Invest.RecordScan(ScanWith(SAC, { 1197, 1, 10000, 200 }, NOW))
  local h = ES.PriceHistory:Get(SAC)
  expect_eq(h.now.price, 1190, "precio de ahora: el último día bueno, no el pico de 1g")
  expect(h.days[#h.days].dubious and h.days[#h.days].spike, "el pico de hoy no sale como subida sin confirmar")
  -- Otro escaneo hoy, ya normal: lo corrige (cuenta el último del día)
  ES.Invest.RecordScan(ScanWith(SAC, { 1185, 30, 1250, 200 }, NOW + 60))
  h = ES.PriceHistory:Get(SAC)
  expect_eq(h.now.price, 1185, "otro escaneo hoy lo corrige")
  -- Un pico de un día en medio también es dudoso
  ES.Invest.RecordScan(ScanWith(SAC, { 9000, 200 }, NOW - 2 * DAY))
  h = ES.PriceHistory:Get(SAC)
  local mid
  for _, d in ipairs(h.days) do if d.price == 9000 then mid = d end end
  expect(mid and mid.dubious, "un pico de un día entre dos normales no sale como dudoso")
end)

test("tus escaneos: una subida de verdad se confirma al día siguiente", function()
  local SAC, DAY = 4402, 86400
  NOW = 400 * DAY + 3600
  Buy(SAC, 40, 1203)
  ES.Invest.RecordScan(ScanWith(SAC, { 1200, 40 }, NOW - 2 * DAY))
  ES.Invest.RecordScan(ScanWith(SAC, { 5000, 40 }, NOW - DAY))
  ES.Invest.RecordScan(ScanWith(SAC, { 5100, 40 }, NOW))
  local h = ES.PriceHistory:Get(SAC)
  expect_eq(h.now.price, 5100, "dos días seguidos arriba: es el precio de ahora")
  expect(not h.days[2].dubious, "la subida confirmada sale como dudosa")
end)

test("tus escaneos: el historial interno del addon no se mezcla (sus precios no cuadraban)", function()
  local key, LEATHER = ES:RealmKey(), 2318
  local S2 = ES.History
  for ago = 1, 3 do S2:Record(key, {}, ";" .. LEATHER .. ":" .. (20 + ago) .. ":5:22:40", NOW - ago * 86400) end
  Buy(LEATHER, 10, 20)
  expect_eq(ES.PriceHistory:Get(LEATHER), nil, "salen días del historial interno como si fueran tus escaneos")
end)

test("con Auctionator, solo Auctionator: tus escaneos no se mezclan", function()
  Buy(LOTUS, 1, 9 * G)
  Buy(SILK, 10, 2 * S)
  -- (los dos en el mismo escaneo: cada escaneo apunta todo lo de la cartera)
  ScanWith(LOTUS, { 10 * G, 50 })
  ES.Invest.RecordScan(ScanWith(SILK, { 3 * S, 50 }))
  InstallAuctionator()
  Days(LOTUS, { [0] = 12 * G, [2] = 11 * G, [3] = 11 * G + 50 * S })
  local lotus = ES.PriceHistory:Get(LOTUS)
  expect_eq(lotus.now.price, 12 * G, "el precio de Auctionator, no el de tu escaneo")
  expect_eq(#lotus.days, 3, "solo los días de Auctionator")
  for _, d in ipairs(lotus.days) do expect_eq(d.source, "auctionator", "fuente de cada día") end
  -- Silk Cloth sin datos en Auctionator: sin precio (no se usan tus escaneos)
  expect_eq(ES.PriceHistory:Get(SILK), nil, "Silk Cloth sin datos en Auctionator")
  OpenPage("invest")
  expect(Plain(CardOf(SILK).price:GetText()):find(L["Sin precio: búscalo en Auctionator"], 1, true), "ficha sin precio: %s", CardOf(SILK).price:GetText())
end)

test("escanear con el addon: con Auctionator no cambia los precios; sin él, los pone al día", function()
  Buy(LOTUS, 1, 9 * G)
  -- Sin Auctionator: tu escaneo pone el precio al momento
  OpenPage("invest")
  ES:OnScanComplete(ScanWith(LOTUS, { 14 * G, 50 }), true)
  RunTimers()
  expect(CardOf(LOTUS).price:GetText():find(ES.Money(14 * G), 1, true), "sin Auctionator, tras escanear: %s", CardOf(LOTUS).price:GetText())
  -- Con Auctionator: manda su historial
  InstallAuctionator()
  Days(LOTUS, { [1] = 12 * G })
  ES:OnScanComplete(ScanWith(LOTUS, { 15 * G, 50 }), true)
  RunTimers()
  expect(CardOf(LOTUS).price:GetText():find(ES.Money(12 * G), 1, true), "con Auctionator, el de su historial: %s", CardOf(LOTUS).price:GetText())
end)

test("pestaña: ficha que sube en verde, precio viejo en gris y cerradas", function()
  InstallAuctionator()
  Days(WOOL, { [0] = 163 })
  Days(LOTUS, { [5] = 10 * G })
  Buy(WOOL, 40, 128)
  Buy(LOTUS, 1, 9 * G)
  Buy(SILK, 10, 2 * S)
  ES.Invest:Add(SILK, "sell", 10, 3 * S)
  OpenPage("invest")
  local wool = expect(CardOf(WOOL), "sin ficha de Wool Cloth")
  expect(wool.price:GetText():find(ES.Money(163), 1, true), "Wool Cloth sin su precio: %s", wool.price:GetText())
  expect_eq(wool.change:GetText(), "|cff40ff40+27%|r", "Wool Cloth: % en verde")
  expect(wool.arrow.path and wool.arrow.path:match("\\Up$"), "Wool Cloth sin triángulo verde: %s", tostring(wool.arrow.path))
  local lotus = expect(CardOf(LOTUS), "sin ficha de Black Lotus")
  expect_eq(lotus.change:GetText(), "|cff9d9d9d+11%|r", "precio viejo: % en gris")
  expect(lotus.arrow.path and lotus.arrow.path:match("Up%-Grey$"), "precio viejo sin triángulo gris: %s", tostring(lotus.arrow.path))
  ResetTooltip()
  lotus:GetScript("OnEnter")(lotus)
  expect(table.concat(TOOLTIP, "\n"):find(string.format(L["Precio de %s: puede haber cambiado."], string.format(L["hace %d días"], 5)), 1, true),
    "el tooltip no dice de hace cuántos días es el precio")
  -- Con Auctionator instalado, solo la línea de estado (de dónde salen los precios) lo
  -- nombra: ni el subtítulo ni las fichas
  local page = Page()
  for _, fs in ipairs({ page.subtitle, wool.price, wool.sub, lotus.price, lotus.sub }) do
    expect(not (fs:GetText() or ""):find("Auctionator", 1, true), "texto que habla de Auctionator: %s", fs:GetText())
  end
  -- Cerradas: plegadas por defecto; al abrirlas, Silk Cloth con su realizado
  expect(not CardOf(SILK), "una cerrada sale entre las abiertas")
  expect_eq(Page().sections[1].text:GetText(), string.format(L["Cerradas (%d)"], 1), "sección de cerradas")
  Page().sections[1]:GetScript("OnClick")()
  local silk = expect(CardOf(SILK), "al abrir Cerradas no sale Silk Cloth")
  expect(Plain(silk.price:GetText()):find(L["Realizado"], 1, true), "la cerrada no dice su realizado")
end)

test("pestaña: el tooltip de una ficha desglosa la comisión de la AH", function()
  InstallAuctionator()
  Days(LOTUS, { [0] = 10 * G + 88 * S })
  Buy(LOTUS, 5, 45 * G, true)
  OpenPage("invest")
  local c = CardOf(LOTUS)
  ResetTooltip()
  c:GetScript("OnEnter")(c)
  local tip = table.concat(TOOLTIP, "\n")
  expect(tip:find(L["Valor bruto"] .. " | " .. ES.Money(54 * G + 40 * S), 1, true), "sin valor bruto:\n%s", tip)
  expect(tip:find(L["Comisión de la AH (5%)"] .. " | -" .. ES.Money(2 * G + 72 * S), 1, true), "sin comisión:\n%s", tip)
  expect(tip:find(L["Neto"] .. " | " .. ES.Money(51 * G + 68 * S), 1, true), "sin neto:\n%s", tip)
  expect(Page().stats.net:GetText():find(ES.Money(51 * G + 68 * S), 1, true), "neto bajo Vale hoy: %s", Page().stats.net:GetText())
  expect_eq(Page().stats.value:GetText(), ES.Money(54 * G + 40 * S), "vale hoy")
  -- Las monedas, siempre las del juego (las mismas que en la ruta y el resto del addon)
  local big = Page().stats.value:GetText()
  expect(big:find("UI-GoldIcon", 1, true) and not big:find("Coin-", 1, true), "vale hoy sin las monedas del juego: %s", big)
  expect(Page().stats.latent == nil, "la cabecera enseña el latente")
end)

test("vista de lista: una fila por objeto, se recuerda y abre el detalle", function()
  InstallAuctionator()
  Days(WOOL, { [0] = 163 })
  Buy(WOOL, 40, 128)
  Buy(SILK, 10, 2 * S)
  OpenPage("invest")
  expect(CardOf(WOOL) and (Page().shownRows or 0) == 0, "por defecto deben salir las fichas")
  Page().views.list:GetScript("OnClick")()
  expect_eq(ES.db.investView, "list", "vista guardada")
  expect_eq(Page().shownCards, 0, "fichas en la vista de lista")
  expect_eq(Page().shownRows, 2, "filas")
  expect(Page().listHeader:IsShown(), "sin los nombres de las columnas")
  local row
  for i = 1, Page().shownRows do if Page().rows[i].itemID == WOOL then row = Page().rows[i] end end
  row = expect(row, "sin fila de Wool Cloth")
  expect_eq(row.units:GetText(), "40", "unidades")
  expect_eq(row.avg:GetText(), ES.Money(128), "tu media")
  expect_eq(row.cost:GetText(), ES.Money(40 * 128), "invertido (antes solo en el tooltip)")
  expect(Page().listHeader.columns.cost, "sin la columna Invertido")
  expect_eq(Page().listHeader.columns.cost.text:GetText(), L["Invertido"], "título de la columna Invertido")
  expect_eq(row.price:GetText(), ES.Money(163), "precio")
  expect_eq(row.change:GetText(), "|cff40ff40+27%|r", "cambio")
  expect(row.arrow.path and row.arrow.path:match("\\Up$"), "sin triángulo verde")
  -- 40 × 1s 63c = 65s 20c; menos el 5 % = 61s 94c; menos 51s 20c invertidos = +10s 74c
  expect_eq(row.latent:GetText(), "|cff40ff40+" .. ES.Money(1074) .. "|r", "latente")
  -- Se recuerda al volver a la pestaña
  ES:SelectPage("home")
  OpenPage("invest")
  expect_eq(Page().shownRows, 2, "la lista no se recuerda")
  -- Clic: el detalle
  row = Page().rows[1]
  row:GetScript("OnClick")(row)
  RunTimers()
  expect_eq(ES.db.lastPage, "investItem", "clic en una fila")
  -- Volver a las fichas
  ES:SelectPage("invest")
  RunTimers()
  Page().views.grid:GetScript("OnClick")()
  expect(ES.db.investView == nil and Page().shownRows == 0 and CardOf(WOOL), "no vuelve a las fichas")
  expect(not Page().listHeader:IsShown(), "los nombres de las columnas se quedan en las fichas")
end)

test("vista de lista: las columnas (con Invertido) no se pisan y el nombre tiene sitio", function()
  local cols, nameX, nameRight = ES.InvestColumns()
  local keys = {}
  for i, c in ipairs(cols) do
    keys[i] = c[1]
    local nextCol = cols[i + 1]
    -- (de izquierda a derecha: la siguiente empieza al menos 10 px después de esta)
    if nextCol then
      expect(nextCol[2] - nextCol[3] >= c[2] + 10, "%s y %s se pisan", c[1], nextCol[1])
    end
  end
  expect_eq(table.concat(keys, ","), "units,avg,cost,price,change,latent", "columnas")
  expect(nameRight <= cols[1][2] - cols[1][3] - 10, "el nombre pisa la columna Tienes")
  expect(ES.UI.LIST_WIDTH + nameRight - nameX >= 130, "el nombre se queda sin sitio: %d px", ES.UI.LIST_WIDTH + nameRight - nameX)
end)

test("vista de lista: ordenar pulsando el nombre de una columna", function()
  InstallAuctionator()
  -- Wool: 40 u, +27 %; Silk: 10 u, -50 %; Pyrite: 5 u, sin precio
  Days(WOOL, { [0] = 163 })
  Days(SILK, { [0] = 1 * S })
  Buy(WOOL, 40, 128)
  Buy(SILK, 10, 2 * S)
  Buy(PYRITE, 5, 3 * S)
  ES.db.investView = "list"
  OpenPage("invest")
  local function Order()
    local ids = {}
    for i = 1, Page().shownRows do ids[i] = Page().rows[i].itemID end
    return table.concat(ids, ",")
  end
  local function Click(key) local b = Page().listHeader.columns[key] b:GetScript("OnClick")(b) end
  -- Por defecto: el latente, de más a menos (sin precio, al final)
  expect_eq(Order(), WOOL .. "," .. SILK .. "," .. PYRITE, "orden por defecto")
  Click("units")
  expect_eq(Order(), WOOL .. "," .. SILK .. "," .. PYRITE, "unidades, de más a menos")
  Click("units")
  expect_eq(Order(), PYRITE .. "," .. SILK .. "," .. WOOL, "unidades, al revés")
  expect(ES.db.investSort and ES.db.investSort.key == "units" and ES.db.investSort.asc, "el orden no se guarda")
  -- Invertido: Wool 51s 20c, Silk 20s, Pyrite 15s
  Click("cost")
  expect_eq(Order(), WOOL .. "," .. SILK .. "," .. PYRITE, "invertido, de más a menos")
  Click("cost")
  expect_eq(Order(), PYRITE .. "," .. SILK .. "," .. WOOL, "invertido, al revés")
  Click("price")
  expect_eq(Order(), WOOL .. "," .. SILK .. "," .. PYRITE, "precio, de más caro a más barato (sin precio, al final)")
  Click("price")
  expect_eq(Order(), SILK .. "," .. WOOL .. "," .. PYRITE, "precio al revés: sin precio sigue al final")
  Click("name")
  local names = {}
  for i = 1, Page().shownRows do names[i] = ES:ItemName(Page().rows[i].itemID):lower() end
  expect(names[1] <= names[2] and names[2] <= names[3], "nombre: de la A a la Z (%s)", table.concat(names, ", "))
  -- La columna elegida se marca
  local col = Page().listHeader.columns.name
  expect(col.arrow:IsShown() and not Page().listHeader.columns.units.arrow:IsShown(), "la columna activa no se marca")
  -- Se recuerda al volver
  ES:SelectPage("home")
  OpenPage("invest")
  expect_eq(ES.db.investSort.key, "name", "orden guardado")
end)

test("vista de lista: ocultar columnas en las opciones (como las pestañas)", function()
  InstallAuctionator()
  Days(WOOL, { [0] = 163 })
  Buy(WOOL, 40, 128)
  Buy(SILK, 10, 2 * S)
  ES.db.investView = "list"
  ES.db.investSort = { key = "cost", asc = false }
  OpenPage("invest")
  local C = ES.InvestListColumns
  local cols, _, nameRight = ES.InvestColumns()
  -- Sin nada oculto, cada columna donde siempre
  local at, right = C.Layout()
  for _, c in ipairs(cols) do
    expect(at[c[1]] and at[c[1]].right == c[2] and at[c[1]].width == c[3], "%s no está donde siempre", c[1])
  end
  expect_eq(right, nameRight, "borde del nombre sin ocultas")
  -- En las opciones, Inversiones: la lista de columnas, en su orden, todas visibles
  ES:OpenOptions("invest")
  RunTimers()
  local list
  for _, cb in ipairs(ES:OptionsWindow().checks) do
    if cb.option.key == "investHiddenColumns" then list = cb end
  end
  list = expect(list, "sin la lista de columnas en las opciones")
  local keys = {}
  for i, b in ipairs(list.items) do
    keys[i] = b.key
    expect(b:IsShown() and not b.hidden and not b.hiddenText:IsShown(), "%s sale oculta sin ocultarla", b.key)
  end
  expect_eq(table.concat(keys, ","), "units,avg,cost,price,change,latent", "columnas en las opciones")
  local function Click(key)
    for _, b in ipairs(list.items) do if b.key == key then b:GetScript("OnClick")(b) return b end end
    error("sin la columna " .. key)
  end
  -- Ocultar Invertido y Desde tu media: se guarda, se marca y la lista cambia al momento
  local cost = Click("cost")
  Click("change")
  expect(ES.db.investHiddenColumns and ES.db.investHiddenColumns.cost and ES.db.investHiddenColumns.change,
    "no se guardan las ocultas")
  expect(cost.hidden and cost.hiddenText:IsShown() and cost.shade:IsShown(), "Invertido no sale como oculta")
  local header = Page().listHeader
  expect(not header.columns.cost:IsShown() and not header.columns.change:IsShown(), "las ocultas siguen en la cabecera")
  expect(header.columns.units:IsShown() and header.columns.latent:IsShown(), "falta una columna visible en la cabecera")
  local row
  for i = 1, Page().shownRows do if Page().rows[i].itemID == WOOL then row = Page().rows[i] end end
  row = expect(row, "sin fila de Wool Cloth")
  expect(not row.cost:IsShown() and not row.change:IsShown() and not row.arrow:IsShown(), "la fila enseña las ocultas")
  expect(row.price:IsShown() and row.latent:IsShown() and row.units:IsShown(), "la fila esconde una visible")
  -- Las que quedan, juntas a la derecha; el nombre gana el sitio de las dos
  at, right = C.Layout()
  expect_eq(at.latent.right, -10, "Si vendes")
  expect_eq(at.price.right, -120, "Precio, donde iba Desde tu media")
  expect_eq(at.avg.right, -226, "Tu media")
  expect_eq(at.units.right, -332, "Tienes")
  expect_eq(right, nameRight + 96 + 84 + 20, "el nombre no gana el sitio")
  -- Ordenada por una columna oculta: por el nombre (marcado), sin olvidar la elegida
  expect(header.columns.name.arrow:IsShown(), "ordenada por una columna oculta")
  expect_eq(ES.db.investSort.key, "cost", "se pierde el orden elegido")
  -- Volver a mostrarlas: nada guardado y todo como siempre
  Click("cost")
  Click("change")
  expect_eq(ES.db.investHiddenColumns, nil, "quedan ocultas guardadas")
  expect(header.columns.cost:IsShown() and header.columns.cost.arrow:IsShown(), "Invertido no vuelve (con su orden)")
  expect(row.cost:IsShown() and row.change:IsShown(), "la fila no vuelve a enseñarlas")
  -- Lo guardado roto no rompe nada
  ES.db.investHiddenColumns = "roto"
  expect(not C.IsHidden("cost"), "guardado roto oculta columnas")
  ES:RenderInvest()
end)

-- Pulsa el segmento `value` de un selector (ES.UI.Segmented)
local function PickSegment(select, value)
  for _, b in ipairs(select.buttons) do
    if b.value == value then b:GetScript("OnClick")(b) return end
  end
  error("sin segmento " .. tostring(value))
end

test("ventana de compra: vista previa con la media nueva y guardar", function()
  Buy(SILK, 20, 2 * S)
  OpenPage("invest")
  ES.OpenInvestEntry(SILK, "buy")
  local f = ES.InvestEntry()
  PickSegment(f.modeSelect, "unit")
  f.qty:SetText("20")
  f.price:SetText("4s")
  f.qty:GetScript("OnTextChanged")(f.qty)
  local v = f.values
  expect_eq(v.total, ES.Money(80 * S), "total")
  expect_eq(v.unit, ES.Money(4 * S), "por unidad")
  expect_eq(v.avgBefore, ES.Money(2 * S), "tu media ahora")
  expect(v.avgAfter and v.avgAfter:find(ES.Money(3 * S), 1, true), "tu media después: %s", tostring(v.avgAfter))
  f.ok:GetScript("OnClick")(f.ok)
  expect(not f:IsShown(), "la ventana sigue abierta tras guardar")
  expect_eq(ES.Invest:Item(SILK).units, 40, "unidades tras guardar")
  -- Total en vez de por unidad
  ES.OpenInvestEntry(LOTUS, "buy")
  PickSegment(f.modeSelect, "unit")
  f.qty:SetText("3")
  f.price:SetText("24g")
  PickSegment(f.modeSelect, "total")
  expect_eq(f.mode, "total", "modo")
  f.ok:GetScript("OnClick")(f.ok)
  expect_eq(ES.Invest:Item(LOTUS).moves[1].unit, 8 * G, "compra por total")
end)

test("ventana de venta: comisión, realizado y vender de más", function()
  Buy(SILK, 20, 2 * S)
  Buy(SILK, 20, 4 * S)
  OpenPage("invest")
  ES.OpenInvestEntry(SILK, "sell")
  local f = ES.InvestEntry()
  expect_eq(f.qty:GetText(), "40", "propone vender todo")
  PickSegment(f.modeSelect, "unit")
  f.qty:SetText("15")
  f.price:SetText("5s")
  f.qty:GetScript("OnTextChanged")(f.qty)
  local v = f.values
  expect_eq(v.total, ES.Money(75 * S), "total de la venta")
  expect(v.cut and v.cut:find("-" .. ES.Money(3 * S + 75), 1, true), "comisión: %s", tostring(v.cut))
  expect_eq(v.net, ES.Money(71 * S + 25), "cobras (neto)")
  expect_eq(v.realized, "|cff40ff40+" .. ES.Money(26 * S + 25) .. "|r", "realizado")
  f.qty:SetText("50")
  f.qty:GetScript("OnTextChanged")(f.qty)
  expect(f.err:GetText():find(string.format(L["Solo tienes %d para vender."], 40), 1, true), "no avisa de vender de más")
  f.ok:GetScript("OnClick")(f.ok)
  expect(f:IsShown(), "guardó una venta de más")
  expect_eq(ES.Invest:Item(SILK).units, 40, "unidades")
  f.qty:SetText("0")
  f.ok:GetScript("OnClick")(f.ok)
  expect(f.err:GetText():find(L["Escribe la cantidad: un número entero mayor que 0."], 1, true), "cantidad 0 sin aviso")
end)

test("precio al apuntar: total por defecto, por unidad con la opción (selector en las opciones y en la ventana)", function()
  Buy(SILK, 40, 3 * S)
  OpenPage("invest")
  ES.OpenInvestEntry(LOTUS, "buy")
  local f = ES.InvestEntry()
  expect_eq(f.mode, "total", "por defecto, el total")
  expect_eq(f.modeSelect.value, "total", "el selector de la ventana marca el total")
  f.qty:SetText("3")
  f.price:SetText("24g")
  f.ok:GetScript("OnClick")(f.ok)
  expect_eq(ES.Invest:Item(LOTUS).moves[1].unit, 8 * G, "24g en total por 3: 8g cada una")
  -- En venta propone el total de todo al precio de ahora (40 × 3s = 1g 20s)
  local item = ES.Invest.Item
  ES.Invest.Item = function(self, id) local e = item(self, id) if id == SILK then e.price = 3 * S end return e end
  ES.OpenInvestEntry(SILK, "sell")
  expect_eq(f.price:GetText(), ES.Calc.FormatMoney(120 * S), "precio total propuesto")
  f:Hide()
  -- La opción, en Inversiones y como selector: por unidad
  local opt
  for _, o in ipairs(ES.OPTIONS) do if o.key == "investPriceMode" then opt = o end end
  expect(opt and opt.cat == "invest" and opt.kind == "segmented" and opt.default == "total", "la opción no es un selector de Inversiones con el total por defecto")
  ES:OpenOptions("invest")
  RunTimers()
  local row
  for _, cb in ipairs(ES:OptionsWindow().checks) do if cb.option.key == "investPriceMode" then row = cb end end
  row = expect(row, "la opción no está en la ventana")
  expect_eq(row.select.value, "total", "el selector de las opciones marca el total")
  PickSegment(row.select, "unit")
  expect_eq(ES.db.investPriceMode, "unit", "guardada")
  ES.OpenInvestEntry(SILK, "sell")
  ES.Invest.Item = item
  expect_eq(f.mode, "unit", "con la opción, por unidad")
  expect_eq(f.price:GetText(), ES.Calc.FormatMoney(3 * S), "precio por unidad propuesto")
  -- En la ventana se cambia solo para esta vez
  PickSegment(f.modeSelect, "total")
  expect_eq(f.mode, "total", "el selector de la ventana")
  expect_eq(ES.db.investPriceMode, "unit", "cambiarlo en la ventana no cambia la opción")
  f:Hide()
  -- Volver al total: no se guarda nada (es el de por defecto)
  PickSegment(row.select, "total")
  expect_eq(ES.db.investPriceMode, nil, "el de por defecto no se guarda")
end)

test("farmeado: precio 0 se apunta y dice Farmeado en vez del %", function()
  InstallAuctionator()
  Days(WOOL, { [0] = 163 })
  OpenPage("invest")
  ES.OpenInvestEntry(WOOL, "buy")
  local f = ES.InvestEntry()
  f.qty:SetText("20")
  f.price:SetText("")
  f.qty:GetScript("OnTextChanged")(f.qty)
  expect(f.hint:GetText():find(L["Escribe la cantidad y el precio (por ejemplo 2.5 = 2s 50c, o 1g 20s). Si lo has farmeado, 0."], 1, true),
    "la pista no dice que se puede poner 0")
  f.price:SetText("0")
  f.ok:GetScript("OnClick")(f.ok)
  expect(not f:IsShown(), "precio 0 no se guarda")
  local e = ES.Invest:Item(WOOL)
  expect(e.farmed, "no cuenta como farmeado")
  expect_eq(e.changePct, nil, "% desde tu media con media 0")
  -- 20 × 1s 63c menos el 5 %: todo es ganancia si vendes
  expect_eq(math.floor(e.latent + 0.5), math.floor(20 * 163 * 0.95 + 0.5), "si vendes")
  ES:RenderInvest()
  local card = expect(CardOf(WOOL), "sin ficha")
  expect_eq(Plain(card.change:GetText()), L["Farmeado"], "la ficha")
  expect(not card.arrow:IsShown(), "triángulo con lo farmeado")
  -- Comprar luego a precio normal: ya no es farmeado y vuelve el %
  Buy(WOOL, 20, 100)
  expect(not ES.Invest:Item(WOOL).farmed, "sigue farmeado tras comprar")
end)

test("elegir objeto: con el buscador (y solo con él)", function()
  OpenPage("invest")
  local box = Page().search
  box:SetText("silk")
  box:GetScript("OnTextChanged")(box)
  local found
  for _, r in ipairs(Page().searchResults or {}) do if r.id == SILK then found = true end end
  expect(found, "«silk» no encuentra Silk Cloth")
  local row = Page().results.rows[1]
  expect(Page().results:IsShown() and row.itemID, "no sale la lista de resultados")
  local first = row.itemID
  row:GetScript("OnClick")(row)
  local f = ES.InvestEntry()
  expect(f:IsShown() and f.itemID == first and f.kind == "buy", "elegir un resultado no abre su compra")
  f:Hide()
  -- (Mayús+clic y arrastrar se quitaron: no funcionaban en el juego. Ni su aviso, ni
  -- que soltar algo en la pestaña haga nada)
  expect(not AllText():find(L["o Mayús+clic en un objeto, o arrástralo aquí"], 1, true), "sigue el aviso de Mayús+clic y arrastrar")
  expect(Page().list:GetScript("OnReceiveDrag") == nil, "la lista sigue aceptando objetos arrastrados")
end)

test("buscador: escribir no vuelve a leer el nombre de todos los objetos", function()
  OpenPage("invest")
  local box = Page().search
  local calls = 0
  local orig = { ItemName = ES.ItemName, GetItemData = ES.GetItemData, DataItemName = ES.DataItemName }
  for k, f in pairs(orig) do ES[k] = function(...) calls = calls + 1 return f(...) end end
  local function Type(text)
    box:SetText(text)
    box:GetScript("OnTextChanged")(box)
  end
  Type("si")
  local first = calls
  calls = 0
  for _, text in ipairs({ "sil", "silk", "silk ", "silk c", "silk cl" }) do Type(text) end
  for k, f in pairs(orig) do ES[k] = f end
  note("primera búsqueda: %d nombres leídos; 5 letras más: %d", first, calls)
  expect(first > 500, "la primera búsqueda lee pocos objetos (%d): ¿falta el escaneo?", first)
  -- (cada letra solo debería leer los nombres de las filas que enseña)
  expect(calls <= 5 * 8 * 3, "5 letras más leen %d nombres (la primera, %d)", calls, first)
  local found
  for _, r in ipairs(Page().searchResults or {}) do if r.id == SILK then found = true end end
  expect(found, "«silk cl» no encuentra Silk Cloth")
end)

test("buscador: no pide al juego objetos que no tiene cargados, y busca en inglés y en el idioma del addon", function()
  -- Lo escaneado que no es de profesiones (sin nombre en los datos): 2.000 objetos, de
  -- los que el juego solo tiene cargado uno
  local items = ES.db.scans[ES:RealmKey()].items
  for id = 900001, 902000 do items[id] = { minUnit = 100, quantity = 5, listings = 1 } end
  ITEM_INFO[900001] = { name = "Tablilla rúnica" }
  C_Item = C_Item or {}
  C_Item.IsItemDataCachedByID = function(id) return id < 900000 or id == 900001 end
  OpenPage("invest")
  local asked = {}
  local orig = ES.GetItemData
  ES.GetItemData = function(self, id, ...) asked[id] = true return orig(self, id, ...) end
  local box = Page().search
  local function Type(text)
    box:SetText(text)
    box:GetScript("OnTextChanged")(box)
  end
  Type("si")
  local uncached, total, withName = 0, 0, 0
  local english = ES.Data.ItemNames or {}
  for id in pairs(asked) do
    total = total + 1
    if id > 900001 then uncached = uncached + 1 end
    if ES:DataItemName(id) or english[id] then withName = withName + 1 end
  end
  note("nombres pedidos al juego: %d (sin cargar: %d; con nombre en los datos: %d)", total, uncached, withName)
  expect_eq(uncached, 0, "objetos sin cargar pedidos al juego")
  -- (los que tienen nombre en los datos no se piden; solo las filas que se enseñan)
  expect(withName <= 8, "pide al juego el nombre de %d objetos que ya están en los datos", withName)
  local function Finds(text, id)
    Type(text)
    for _, r in ipairs(Page().searchResults or {}) do if r.id == id then return true end end
  end
  ES.GetItemData = orig
  expect(Finds("silk", SILK), "«silk» (inglés) no encuentra Silk Cloth")
  local es = ES:DataItemName(SILK)
  expect(es and Finds(es:lower():sub(1, 6), SILK), "el nombre del addon (%s) no encuentra Silk Cloth", tostring(es))
  expect(Finds("tablilla", 900001), "no encuentra lo escaneado que el juego ya tiene cargado")
end)

test("buscador: solo lo que se puede vender (lo que ha estado en la AH)", function()
  local LINEN_BOLT, RUNECLOTH = 2996, 14047
  local function Finds(text, id)
    local box = Page().search
    box:SetText(text)
    box:GetScript("OnTextChanged")(box)
    for _, r in ipairs(Page().searchResults or {}) do if r.id == id then return true end end
  end
  -- Bolt of Linen Cloth es de las recetas pero no está en el escaneo ni en Auctionator
  local items = ES.db.scans[ES:RealmKey()].items
  items[LINEN_BOLT], items[RUNECLOTH] = nil, nil
  OpenPage("invest")
  expect(not Finds("bolt of linen", LINEN_BOLT), "sale un objeto que no ha estado a la venta")
  expect(Finds("silk", SILK), "no sale Silk Cloth (en el escaneo)")
  -- Con precios en Auctionator, sí
  InstallAuctionator()
  AUCTIONATOR_DB[tostring(RUNECLOTH)] = {}
  ES:SelectPage("home")
  OpenPage("invest")
  expect(Finds("runecloth", RUNECLOTH), "no sale lo que tiene precio en Auctionator")
  -- Lo de tu cartera sale siempre
  Buy(LINEN_BOLT, 2, 50)
  ES:SelectPage("home")
  OpenPage("invest")
  expect(Finds("bolt of linen", LINEN_BOLT), "no sale lo que ya está en la cartera")
end)

test("buscador: sin escaneo ni Auctionator, lo de las recetas menos lo ligado y lo de misión", function()
  local LINEN_BOLT, ARMOR = 2996, 2300 -- (2300: Embossed Leather Vest, de las recetas)
  ITEM_INFO[ARMOR] = { name = "Embossed Leather Vest", bind = 1 }
  C_Item = C_Item or {}
  C_Item.IsItemDataCachedByID = function() return true end
  OpenPage("invest")
  local box = Page().search
  local function Finds(text, id)
    box:SetText(text)
    box:GetScript("OnTextChanged")(box)
    for _, r in ipairs(Page().searchResults or {}) do if r.id == id then return true end end
  end
  expect(Finds("bolt of linen", LINEN_BOLT), "sin escaneo no sale lo de las recetas")
  expect(not Finds("embossed leather vest", ARMOR), "sale un objeto ligado al recogerlo")
end, { state = "empty" })

test("gráfica: huecos sin unir y días dudosos sueltos", function()
  InstallAuctionator()
  -- Días 1-3 y 11-14 (contando desde el más antiguo), y uno dudoso en medio
  Days(SILK, { [13] = 200, [12] = 210, [11] = 205, [3] = 220, [2] = 30, [1] = 225, [0] = 230 })
  Buy(SILK, 10, 2 * S)
  OpenPage("invest")
  ES:ShowInvestItem(SILK)
  RunTimers()
  local chart = ItemPage().chart
  local today = AuctionatorToday()
  local joined = {}
  for _, s in ipairs(chart.segments) do joined[(today - s.from) .. "-" .. (today - s.to)] = true end
  expect(joined["13-12"] and joined["12-11"], "no une los primeros días")
  expect(not joined["11-3"], "une dos días con 8 días de hueco")
  expect(joined["3-1"] and joined["1-0"], "no une los últimos días saltando el dudoso")
  for _, s in ipairs(chart.segments) do
    expect(s.from ~= today - 2 and s.to ~= today - 2, "el día dudoso tiene línea")
  end
  expect_eq(#chart.segments, 4, "tramos")
  -- Curva suave: más tramos rectos que días unidos, y relleno debajo
  local shownLines, shownFills, shownDots = 0, 0, 0
  for _, l in ipairs(chart.lines) do if l:IsShown() then shownLines = shownLines + 1 end end
  for _, f in ipairs(chart.fills) do if f:IsShown() then shownFills = shownFills + 1 end end
  for _, d in ipairs(chart.dots) do if d:IsShown() then shownDots = shownDots + 1 end end
  expect(shownLines > #chart.segments * 2, "la curva no es suave: %d tramos para %d días unidos", shownLines, #chart.segments)
  expect(shownFills > 0, "sin relleno bajo la curva")
  -- Puntos: el día dudoso y el último (con su halo, anillo y centro); los demás, no
  expect_eq(shownDots, 1 + 3, "puntos dibujados")
end)

test("detalle: cifras iguales a la gráfica y a la ficha, y borrar recalcula", function()
  InstallAuctionator()
  Days(LOTUS, { [0] = 10 * G + 88 * S, [4] = 12 * G + 22 * S, [8] = 15 * G })
  Buy(LOTUS, 3, 8 * G)
  Buy(LOTUS, 2, 10 * G + 50 * S)
  OpenPage("invest")
  local card = CardOf(LOTUS)
  card:GetScript("OnClick")(card)
  RunTimers()
  local page = ItemPage()
  expect(page:IsShown(), "el detalle no se abre")
  expect_eq(ES.db.lastPage, "investItem", "página")
  expect_eq(ES:GetMainFrame().back:GetText(), L["Inversiones"], "botón Volver")
  local h = page.entry.history
  local last
  for _, d in ipairs(h.days) do if not d.dubious then last = d end end
  expect_eq(Plain(page.boxes.now.value:GetText()), Plain(ES.Money(last.price)), "Precio ahora = último punto de la gráfica")
  expect(card.price:GetText():find(ES.Money(last.price), 1, true), "la ficha no tiene el mismo precio")
  expect_eq(page.boxes.last4.value:GetText(), "|cffff4040-11%|r", "últimos 4 días")
  expect(page.boxes.last4.arrow.path and page.boxes.last4.arrow.path:match("\\Down$"), "últimos 4 días sin triángulo rojo")
  expect_eq(Plain(page.boxes.avg.value:GetText()), Plain(ES.Money(9 * G)), "tu media")
  -- Movimientos: filas como las de las rutas, la más reciente arriba
  local rows = page.movesList.rows
  expect(rows[1]:IsShown() and rows[2]:IsShown(), "no salen las dos compras")
  expect(Plain(rows[1].sub:GetText()):find("2 ", 1, true), "la primera fila no es la última compra: %s", rows[1].sub:GetText())
  -- Borrar la compra más reciente (su X) desde el detalle: pregunta antes
  rows[1].skip:GetScript("OnClick")(rows[1].skip)
  local d = ES.ConfirmFrame()
  expect(d:IsShown(), "borrar no pregunta")
  d.ok:GetScript("OnClick")(d.ok)
  expect_eq(ES.Invest:Item(LOTUS).units, 3, "unidades tras borrar")
  expect_eq(Plain(page.boxes.avg.value:GetText()), Plain(ES.Money(8 * G)), "media tras borrar")
  ES:SelectPage("invest")
  RunTimers()
  expect_eq(Page().stats.cost:GetText(), ES.Money(24 * G), "cabecera tras borrar")
end)

test("detalle: clic en un movimiento lo edita (cantidad y precio) y recalcula", function()
  Buy(LOTUS, 3, 8 * G)
  Buy(LOTUS, 2, 21 * G, true) -- (escrito en total: 21g por las 2)
  ES.Invest:Add(LOTUS, "sell", 5, 40 * G, true) -- (todo: cerrada)
  local t2 = ES.Invest:Item(LOTUS).moves[2].t
  OpenPage("invest")
  ES:ShowInvestItem(LOTUS)
  RunTimers()
  local page = ItemPage()
  local rows = page.movesList.rows
  -- Fila 2: la segunda compra (la más reciente arriba: venta, compra 2, compra 1)
  rows[2]:GetScript("OnClick")(rows[2], "LeftButton")
  local f = expect(ES.InvestEntry(), "no se abre la ventana")
  expect(f:IsShown(), "no se abre la ventana")
  expect_eq(f.editIndex, 2, "movimiento que se edita")
  expect_eq(f.kindLabel:GetText(), L["Editar compra"], "título")
  expect_eq(f.ok:GetText(), L["Guardar"], "botón")
  expect_eq(f.qty:GetText(), "2", "cantidad de la compra")
  expect_eq(f.mode, "total", "escrita en total: se edita en total")
  expect_eq(f.price:GetText(), ES.Calc.FormatMoney(21 * G), "precio de la compra")
  -- Tu media sin esta compra (8g) y con la nueva
  f.qty:SetText("5")
  f.price:SetText("50g")
  f.qty:GetScript("OnTextChanged")(f.qty)
  expect_eq(f.values.avgBefore, ES.Money(8 * G), "tu media sin el movimiento")
  f.ok:GetScript("OnClick")(f.ok)
  expect(not f:IsShown(), "la ventana sigue abierta tras guardar")
  local e = ES.Invest:Item(LOTUS)
  expect_eq(#e.moves, 3, "editar no añade un movimiento")
  expect(e.moves[2].kind == "buy" and e.moves[2].n == 5 and e.moves[2].total == 50 * G, "la compra no cambia")
  expect_eq(e.moves[2].t, t2, "la fecha se mantiene")
  expect_eq(e.units, 3, "unidades tras editar")
  expect_eq(Plain(page.boxes.avg.value:GetText()), Plain(ES.Money(74 * G / 8)), "media tras editar")
  -- Bajar la compra a 1 deja la venta de 5 sin unidades (3 + 1): no se guarda
  rows[2]:GetScript("OnClick")(rows[2], "LeftButton")
  f.qty:SetText("1")
  f.ok:GetScript("OnClick")(f.ok)
  expect(f:IsShown(), "guardó un cambio que deja una venta de más")
  expect(f.err:GetText():find(L["Con este cambio, una venta de después sería de más unidades de las que tenías."], 1, true), "sin aviso: %s", f.err:GetText())
  expect_eq(ES.Invest:Item(LOTUS).moves[2].n, 5, "la compra cambió")
  f:Hide()
  -- La venta: unidades que había para ella (8) y por unidad
  rows[1]:GetScript("OnClick")(rows[1], "LeftButton")
  expect_eq(f.kindLabel:GetText(), L["Editar venta"], "título de la venta")
  expect_eq(f.qty:GetText(), "5", "cantidad de la venta")
  f.qty:SetText("9")
  f.ok:GetScript("OnClick")(f.ok)
  expect(f.err:GetText():find(string.format(L["Solo tienes %d para vender."], 8), 1, true), "vender de más al editar: %s", f.err:GetText())
  PickSegment(f.modeSelect, "unit")
  f.qty:SetText("8")
  f.price:SetText("11g")
  f.ok:GetScript("OnClick")(f.ok)
  e = ES.Invest:Item(LOTUS)
  expect(e.moves[3].n == 8 and e.moves[3].unit == 11 * G and not e.moves[3].total, "la venta no cambia")
  expect(e.closed, "vender las 8 no la cierra")
  -- Una cantidad que no vale, como al apuntar
  expect_eq(select(2, ES.Invest:Update(LOTUS, 1, "0", 100)), "qty", "cantidad 0")
  expect_eq(select(2, ES.Invest:Update(LOTUS, 9, "1", 100)), "item", "movimiento que no existe")
end)

-- ¿Se escribió en el chat, desde `from`, algo con `text`?
local function SaidSince(from, text)
  for i = from + 1, #PRINTS do if PRINTS[i]:find(text, 1, true) then return PRINTS[i] end end
end

test("borrar un movimiento: pregunta siempre (se quita con la casilla o en las opciones) y lo dice en el chat", function()
  Buy(LOTUS, 3, 8 * G)
  Buy(LOTUS, 2, 21 * G, true)
  OpenPage("invest")
  ES:ShowInvestItem(LOTUS)
  RunTimers()
  local rows = ItemPage().movesList.rows
  -- La X pregunta; No no borra nada
  rows[1].skip:GetScript("OnClick")(rows[1].skip)
  local d = expect(ES.ConfirmFrame(), "borrar no pregunta")
  expect(d:IsShown(), "borrar no pregunta")
  expect(d.text:GetText():find(string.format(L["¿Borrar la compra de %d x %s por %s?"], 2, ES.UI.ItemLabel(LOTUS, ""), ES.Money(21 * G)), 1, true),
    "la pregunta no dice qué se borra: %s", d.text:GetText())
  d.cancel:GetScript("OnClick")(d.cancel)
  expect_eq(#ES.Invest:Item(LOTUS).moves, 2, "No borró el movimiento")
  -- Sí: lo borra y lo dice en el chat
  local from = #PRINTS
  rows[1].skip:GetScript("OnClick")(rows[1].skip)
  d.ok:GetScript("OnClick")(d.ok)
  expect_eq(#ES.Invest:Item(LOTUS).moves, 1, "Sí no borró el movimiento")
  expect(SaidSince(from, string.format(L["Compra borrada: %d x %s por %s."], 2, ES.UI.ItemLabel(LOTUS, ""), ES.Money(21 * G))),
    "el chat no dice que se borró")
  -- La casilla «No volver a mostrar» la apaga: la opción de Inversiones
  expect_eq(ES:OptionCategory("noInvestDeleteConfirm"), "invest", "la opción no está en Inversiones")
  Buy(LOTUS, 1, 9 * G)
  ES:RenderInvestItem()
  rows[1].skip:GetScript("OnClick")(rows[1].skip)
  d.check:SetChecked(true)
  d.ok:GetScript("OnClick")(d.ok)
  expect_eq(ES.db.noInvestDeleteConfirm, true, "la casilla no apaga la pregunta")
  rows[1].skip:GetScript("OnClick")(rows[1].skip) -- (la compra de 3: la última que queda)
  expect(not d:IsShown(), "pregunta con la opción apagada")
  expect_eq(ES.Invest:Item(LOTUS).moves[1], nil, "con la opción apagada no se borró")
end)

test("chat: comprar, vender y corregir un movimiento lo dicen en el chat", function()
  OpenPage("invest")
  local from = #PRINTS
  ES.OpenInvestEntry(SILK, "buy")
  local f = ES.InvestEntry()
  PickSegment(f.modeSelect, "total")
  f.qty:SetText("20")
  f.price:SetText("80s")
  f.ok:GetScript("OnClick")(f.ok)
  local name = ES.UI.ItemLabel(SILK, "")
  expect(SaidSince(from, string.format(L["Compra apuntada: %d x %s por %s."], 20, name, ES.Money(80 * S))), "la compra no sale en el chat")
  ES.OpenInvestEntry(SILK, "sell")
  PickSegment(f.modeSelect, "unit")
  f.qty:SetText("5")
  f.price:SetText("5s")
  f.ok:GetScript("OnClick")(f.ok)
  expect(SaidSince(from, string.format(L["Venta apuntada: %d x %s por %s."], 5, name, ES.Money(25 * S))), "la venta no sale en el chat")
  ES.OpenInvestEntry(SILK, "buy", 1)
  f.qty:SetText("10")
  f.ok:GetScript("OnClick")(f.ok)
  expect(SaidSince(from, string.format(L["Compra corregida: %d x %s por %s."], 10, name, ES.Money(80 * S))), "corregir no sale en el chat")
  -- Lo que no se guarda (vender de más) no se dice
  local before = #PRINTS
  ES.OpenInvestEntry(SILK, "sell")
  f.qty:SetText("99")
  f.ok:GetScript("OnClick")(f.ok)
  expect_eq(#PRINTS, before, "dijo en el chat una venta que no se guardó")
  f:Hide()
end)

test("pestaña: precios al día al volver a abrirla", function()
  InstallAuctionator()
  Days(SILK, { [0] = 200 })
  Buy(SILK, 10, 2 * S)
  OpenPage("invest")
  expect(CardOf(SILK).price:GetText():find(ES.Money(200), 1, true), "precio antes")
  ES:SelectPage("home")
  AUCTIONATOR_DAYS[SILK] = { { ago = 0, max = 300 } } -- (sin avisar: lo leído se recuerda)
  OpenPage("invest")
  expect(CardOf(SILK).price:GetText():find(ES.Money(300), 1, true), "al volver a abrirla no sale el precio nuevo")
end)

test("datos completos: la pestaña y el detalle de cada inversión, en cada idioma", function()
  OpenPage("invest")
  local sum = Page().summary
  expect(#sum.open == 3 and sum.totals.missing == 1, "la cartera de los datos completos no sale como se espera")
  ES:ShowInvestItem(4306)
  RunTimers()
  expect(ItemPage():IsShown(), "el detalle no se abre")
  for _, l in ipairs(ES.LANGS) do
    ES:SetLanguage(l.key)
    RunTimers()
    expect(ES:GetMainFrame():IsShown(), "al pasar a %s la ventana se cerró", l.key)
    expect_eq(ES.db.lastPage, "investItem", "página tras pasar a " .. l.key)
    expect_eq(ItemPage().entry and ItemPage().entry.itemID, 4306, "objeto del detalle en " .. l.key)
  end
end, { state = "full" })

test("arranque: lo guardado sin cartera o con una rota", function()
  Boot({ invest = "roto" })
  expect_eq(next(ES.Invest.Book()), nil, "cartera")
  Boot({ invest = { account = { ["Realm-Alliance"] = { [SILK] = { moves = "mal" } } } } })
  no_error(function() ES.Invest:Summary() end)
end, { boot = false })

-- Antes repintaba con cada objeto que llegaba del servidor (bolsas, chat, otros
-- addons), le faltara algo o no: solo lo hace cuando llega uno de los que faltaban
test("pestaña: solo repinta cuando llega un objeto que le faltaba", function()
  Buy(SILK, 10, 2 * S)
  Buy(LOTUS, 2, 8 * G)
  UNCACHED[LOTUS] = true
  OpenPage("invest")
  local n, render = 0, ES.RenderInvest
  ES.RenderInvest = function(...) n = n + 1 return render(...) end
  FireEvent("GET_ITEM_INFO_RECEIVED", 2589, true) -- (Linen Cloth: no está en la cartera)
  FireEvent("GET_ITEM_INFO_RECEIVED", SILK, true) -- (ya estaba cargado)
  RunTimers()
  expect_eq(n, 0, "repintados con objetos que no faltaban")
  expect(Page().pendingItems, "no apunta que falta el Black Lotus")
  UNCACHED[LOTUS] = nil
  FireEvent("GET_ITEM_INFO_RECEIVED", LOTUS, true)
  RunTimers()
  expect_eq(n, 1, "repintados al llegar el Black Lotus")
  expect(not Page().pendingItems, "sigue esperando objetos con todo cargado")
  FireEvent("GET_ITEM_INFO_RECEIVED", LOTUS, true)
  RunTimers()
  expect_eq(n, 1, "repintados con todo cargado")
end)

-- La AH es una por ruleset (modo de juego) y bando: cambiar de modo es otra cartera, y
-- con la pestaña abierta se ve la nueva (Keys.lua)
test("cartera: otro ruleset, otra cartera, y la pestaña se pone al día", function()
  Buy(SILK, 20, 2 * S)
  OpenPage("invest")
  expect(CardOf(SILK), "no sale la ficha de la cartera del ruleset 14")
  SetGameMode(15)
  RunTimers()
  expect_eq(ES:RealmKey(), "gm15-Alliance", "clave tras cambiar de modo")
  expect(not CardOf(SILK), "con el ruleset 15 sigue la cartera del 14")
  Buy(LOTUS, 1, G)
  SetGameMode(14)
  RunTimers()
  expect(CardOf(SILK), "al volver al 14 no sale su cartera")
  expect(not ES.Invest.Book()[LOTUS], "la compra del 15 salió en el 14")
end)