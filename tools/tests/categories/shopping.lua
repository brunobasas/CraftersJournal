-- Lista de compra: lo que pide la ruta empezada y lo que añades desde Ganar dinero o
-- la Calculadora; lo que llevas en las bolsas se descuenta al enseñarla

local function ItemsOf(status, kind)
  local out = {}
  for _, s in ipairs(status.lists) do
    if not kind or s.list.kind == kind then
      for _, e in ipairs(s.items) do out[e.it.itemID] = e end
    end
  end
  return out
end

for _, state in ipairs({ "empty", "scan", "full" }) do
  test("la pestaña se abre: " .. state, function()
    OpenPage("shopping")
    expect(ES:GetMainFrame().pages.shopping:IsShown(), "la página no se ve")
  end, { state = state })
end

test("lista añadida: pide solo lo que falta con lo que llevas", function()
  -- (datos completos: una lista con 10 Light Leather y 20 Linen Cloth; en las bolsas
  -- 4 Light Leather y 30 Linen Cloth)
  local items = ItemsOf(ES.Shopping.Status(), "money")
  local leather, linen = expect(items[2318], "falta Light Leather"), expect(items[2589], "falta Linen Cloth")
  expect_eq(leather.bought, 4, "Light Leather que llevas")
  expect_eq(leather.left, 6, "Light Leather que falta")
  expect_eq(linen.left, 0, "Linen Cloth que falta (llevas de sobra)")
  local id, n = ES.Shopping.NextToBuy(ES.Shopping.Status())
  expect_eq(id, 2318, "lo siguiente que comprar")
  expect_eq(n, 6, "cuántas")
  OpenPage("shopping")
end, { state = "full" })

test("añadir lo mismo dos veces lo junta", function()
  local list = ES.Shopping.Add("calc", "x", {
    { itemID = 2592, quantity = 3, unit = 40, source = "ah" },
    { itemID = 2592, quantity = 2, unit = 40, source = "ah" },
    { itemID = 2589, quantity = 5, unit = 15, source = "craft" }, -- (lo que se fabrica no se compra)
  })
  expect_eq(#list.items, 1, "materiales en la lista")
  expect_eq(list.items[1].need, 5, "Wool Cloth juntado")
  expect_eq(list.items[1].unit, 40, "precio por unidad")
  expect_eq(ES.Shopping.Add("calc", "nada", { { itemID = 2592, quantity = 0 } }), nil, "una lista vacía no se añade")
end, { state = "full" })

test("añadir con la misma clave sustituye la anterior", function()
  ES.Shopping.Add("calc", "uno", { { itemID = 2592, quantity = 3, unit = 40 } }, { key = 7 })
  ES.Shopping.Add("calc", "dos", { { itemID = 2592, quantity = 9, unit = 40 } }, { key = 7 })
  local n, need = 0, nil
  for _, l in ipairs(ES.Shopping.Lists()) do if l.kind == "calc" and l.key == 7 then n = n + 1 need = l.items[1].need end end
  expect_eq(n, 1, "listas con la misma clave")
  expect_eq(need, 9, "la nueva")
end, { state = "full" })

test("Ganar dinero añade a la lista lo que compra el lote", function()
  ES.db.earnMinProfit = 1
  ES.Earn:Clear()
  local res = ES.Earn:Ideas()
  expect(#res.batch > 0, "sin lote")
  local shopping = res.shopping
  expect(shopping and #shopping > 0, "el lote no compra nada")
  local total = 0
  for _, it in ipairs(shopping) do
    expect(it.itemID and (it.quantity or it.need or 0) > 0, "material sin cantidad")
    total = total + (it.quantity or it.need)
  end
  note("el lote compra %d materiales (%d unidades)", #shopping, total)
end, { state = "full" })

test("ruta empezada: su lista sale sola y descuenta las bolsas", function()
  local page, plan = StartRoute("Tailoring", 1, 75)
  local status = ES.Shopping.Status()
  local items = ItemsOf(status, "phase")
  local first = next(items)
  expect(first, "la ruta empezada no tiene lista")
  local e = items[first]
  local need = e.it.need
  -- Con la mitad en las bolsas, falta la otra mitad
  BAGS[first] = math.floor(need / 2)
  ES.Earn:Clear()
  items = ItemsOf(ES.Shopping.Status(), "phase")
  expect_eq(items[first].left, need - math.floor(need / 2), "lo que falta con la mitad en las bolsas")
  note("material %d: pide %d, llevas %d", first, need, math.floor(need / 2))
  OpenPage("shopping")
end, { state = "scan" })

-- El modo de compra (por tramos o ruta entera) se ve y se elige ANTES de empezar la
-- ruta, y empezarla lo respeta. CurseForge: elegías la ruta viendo 326 Silk Cloth y al
-- empezarla la lista pasaba sola a "por tramos" (32): parecía que te la cambiaban

-- La vista Materiales de Sastrería 120-150 sin empezar la ruta
local function ShopView()
  SKILLS[ES.Data.Tailoring.skillLine] = { 120, 150 }
  OpenPage("Tailoring")
  local page = ProfessionPage("Tailoring")
  page.toBox._text = "150"
  if page.toBox._scripts.OnEnterPressed then page.toBox._scripts.OnEnterPressed(page.toBox) end
  RunTimers()
  ES:SelectProfessionView(page, "shop")
  RunTimers()
  expect(not ES:RouteLock("Tailoring"), "la ruta ya estaba empezada")
  return page
end

-- Las filas de materiales ("×N" y el objeto) de la vista
local function Materials(page)
  local t = {}
  for _, l in ipairs(page.lines) do if l.item then t[#t + 1] = tostring(l.level) .. " " .. l.item end end
  return table.concat(t, ", ")
end

-- Unidades que piden las filas de materiales de la vista ("×N")
local function MaterialUnits(page)
  local n = 0
  for _, l in ipairs(page.lines) do
    if l.item then n = n + (tonumber(tostring(l.level):match("(%d+)")) or 0) end
  end
  return n
end

test("sin empezar la ruta, Materiales dice el modo de compra y la lista lo sigue", function()
  local page = ShopView()
  local line = page.lines[1]
  expect(line and line.phaseLine and line.onClick, "la primera fila de Materiales no es la del modo de compra")
  expect(tostring(line.title):find("por tramos · Tramo", 1, true), "sin elegir nada debería decir por tramos y el tramo: «%s»", tostring(line.title))
  expect(tostring(line.sub):find("la ruta entera", 1, true), "debería decir que al pulsar se compra la ruta entera: «%s»", tostring(line.sub))
  line.tooltip(CreateFrame("Frame"))
  local stage = MaterialUnits(page)
  expect(stage > 0, "Materiales no tiene filas de materiales")
  -- (el clic en la fila, como en el juego): pasa a la ruta entera y la lista cambia
  page.rows[1]._scripts.OnClick(page.rows[1], "LeftButton")
  RunTimers()
  expect(tostring(page.rows[1].title._text):find("la ruta entera", 1, true), "la fila pintada no cambia: «%s»", tostring(page.rows[1].title._text))
  expect_eq(ES.db.prof.Tailoring.byPhase, false, "modo guardado tras pulsar")
  local whole = MaterialUnits(page)
  note("Materiales: primer tramo %d unidades · ruta entera %d", stage, whole)
  expect(whole > stage, "con ruta entera la lista debería pedir más que el primer tramo (%d y %d)", whole, stage)
  page.lines[1].onClick()
  RunTimers()
  expect_eq(ES.db.prof.Tailoring.byPhase, nil, "vuelve a por tramos (el de por defecto)")
  expect(tostring(page.lines[1].title):find("por tramos", 1, true), "la fila no vuelve a decir por tramos")
  expect_eq(MaterialUnits(page), stage, "unidades otra vez por tramos")
  expect(not ES:RouteLock("Tailoring"), "cambiar el modo empezó la ruta")
  expect(not (ES.db.prof.Tailoring.stocked), "la vista previa apuntó lo comprado")
end, { state = "scan" })

-- Lo que sale al empezar con ruta entera: un aviso con "Ruta entera", "Por tramos" y
-- "No volver a mostrar este aviso"
local function Notice() return CraftersJournalPostConfirm end

-- Unidades que pide la lista de la ruta empezada
local function PhaseUnits()
  local n = 0
  for _, s in ipairs(ES.Shopping.Status().lists) do
    if s.list.kind == "phase" then for _, e in ipairs(s.items) do n = n + e.it.need end end
  end
  return n
end

test("empezar la ruta respeta el modo elegido antes", function()
  -- Sin elegir nada: por tramos, sin aviso
  ShopView()
  StartRoute("Tailoring", 120, 150)
  expect_eq(ES.db.prof.Tailoring.byPhase, nil, "empezar la ruta no toca el modo")
  expect(ES.Shopping.ByPhase("Tailoring"), "sin elegir nada debería comprar por tramos")
  expect(not (Notice() and Notice()._shown), "por tramos no hay que avisar de nada")
  local phase = PhaseUnits()
  ES:StopRoute("Tailoring")
  -- Ruta entera elegida antes de empezar (la fila de Materiales)
  local page = ShopView()
  page.lines[1].onClick()
  RunTimers()
  StartRoute("Tailoring", 120, 150)
  expect_eq(ES.db.prof.Tailoring.byPhase, false, "empezar la ruta no toca el modo")
  local d = expect(Notice(), "con ruta entera no sale el aviso")
  expect(d._shown, "con ruta entera no sale el aviso")
  expect(tostring(d.text._text):find("asistente", 1, true), "el aviso no dice que se cambia en el asistente: «%s»", tostring(d.text._text))
  d.ok._scripts.OnClick(d.ok) -- "Ruta entera": sigue igual
  expect_eq(ES.db.prof.Tailoring.byPhase, false, "seguir con ruta entera")
  local whole = PhaseUnits()
  note("lista por tramos: %d unidades · ruta entera: %d", phase, whole)
  expect(phase > 0 and whole > phase, "con ruta entera la lista debería pedir más que el tramo (%d y %d)", whole, phase)
  -- Y la fila de Materiales con la ruta empezada dice lo mismo
  ES:SelectProfessionView(page, "shop")
  RunTimers()
  expect(tostring(page.lines[1].title):find("Ruta entera", 1, true), "con la ruta empezada la fila no dice ruta entera: «%s»", tostring(page.lines[1].title))
end, { state = "scan" })

test("el aviso de ruta entera: «Por tramos» cambia el modo y la casilla lo apaga", function()
  ES.db.prof.Tailoring = ES.db.prof.Tailoring or {}
  ES.db.prof.Tailoring.byPhase = false
  StartRoute("Tailoring", 120, 150)
  local d = expect(Notice(), "no sale el aviso")
  expect(d._shown, "no sale el aviso")
  d.check:SetChecked(true)
  d.cancel._scripts.OnClick(d.cancel) -- "Por tramos"
  expect_eq(ES.db.prof.Tailoring.byPhase, nil, "«Por tramos» vuelve a por tramos")
  expect_eq(ES.db.noWholeRouteNotice, true, "la casilla apaga el aviso")
  expect(not d._shown, "el aviso no se cierra")
  -- Apagado: otra ruta con ruta entera ya no avisa
  ES:StopRoute("Tailoring")
  ES.db.prof.Tailoring.byPhase = false
  StartRoute("Tailoring", 120, 150)
  expect(not d._shown, "apagado, sigue avisando")
  -- Y la opción lo vuelve a encender (Asistente de ruta)
  local opt
  for _, o in ipairs(ES.OPTIONS) do if o.key == "noWholeRouteNotice" then opt = o end end
  expect(opt and opt.cat == "assistant", "falta la opción del aviso en Asistente de ruta")
end, { state = "scan" })

-- Lo ya convertido cuenta en la lista de la ruta (spec route-shopping-mode). Discord:
-- convirtió las Greater Magic Essence en Lesser como pedía la ruta y la Lista de compra
-- volvió a pedir todas las Greater; Materiales y el asistente sí las contaban. Con los
-- precios de las pruebas, Encantamiento 110-130 (Greater Magic Wand) compra Greater
-- Magic Essence y las convierte en Lesser (1 -> 3)
local LESSER_MAGIC, GREATER_MAGIC = 10938, 10939

-- Empieza Encantamiento 110-130 y pone `lesser` Lesser Magic Essence en las bolsas.
-- Devuelve la ruta fijada
local function ConvertedRoute(lesser, byPhase)
  if byPhase == false then
    ES.db.prof.Enchanting = ES.db.prof.Enchanting or {}
    ES.db.prof.Enchanting.byPhase = false
  end
  local _, plan = StartRoute("Enchanting", 110, 130)
  local made = false
  for _, c in ipairs(plan.crafted or {}) do
    if c.itemID == LESSER_MAGIC and c.recipe and c.recipe.conversion then made = true end
  end
  expect(made, "la ruta de Encantamiento 110-130 ya no convierte Greater Magic Essence en Lesser")
  BAGS[GREATER_MAGIC], BAGS[LESSER_MAGIC] = 0, lesser
  ES.Earn:Clear()
  return plan
end

-- La fila de un material en la lista de la ruta empezada
local function PhaseRow(itemID)
  return expect(ItemsOf(ES.Shopping.Status(), "phase")[itemID], "la lista de la ruta no pide el objeto %d", itemID)
end

test("ruta empezada: las esencias ya convertidas cuentan como las que se compran", function()
  local plan = ConvertedRoute(36)
  local e = PhaseRow(GREATER_MAGIC)
  note("pide %d Greater Magic Essence; con 36 Lesser: tienes %d, faltan %d", e.it.need, e.bought, e.left)
  expect(e.it.need > 12, "el tramo pide solo %d Greater Magic Essence", e.it.need)
  expect_eq(e.bought, 12, "Greater Magic Essence que tienes (36 Lesser convertidas)")
  expect_eq(e.converted, 12, "las que vienen de lo convertido")
  expect_eq(e.left, e.it.need - 12, "Greater Magic Essence que faltan")
  -- (lo mismo que cuentan Materiales y el asistente)
  expect_eq(e.left, e.it.need - ES.RouteHave(plan, 110)(GREATER_MAGIC), "la lista no pide lo mismo que Materiales")
end)

test("ruta entera: las esencias ya convertidas también cuentan", function()
  ConvertedRoute(36, false)
  local e = PhaseRow(GREATER_MAGIC)
  expect(ES.Shopping.PhaseLists()[1].whole, "la lista no es de la ruta entera")
  expect_eq(e.bought, 12, "Greater Magic Essence que tienes (36 Lesser convertidas)")
  expect_eq(e.left, e.it.need - 12, "Greater Magic Essence que faltan")
end)

test("ruta empezada: las esencias convertidas de más no cuentan", function()
  local plan = ConvertedRoute(600)
  local cap = math.ceil(ES.Planner.CraftedNeedFrom(plan, LESSER_MAGIC, 110) - 0.001)
  local e = PhaseRow(GREATER_MAGIC)
  note("la ruta aún gasta %d Lesser; con 600 tienes %d Greater de %d", cap, e.bought, e.it.need)
  expect(cap < 600, "la ruta gasta %d Lesser Magic Essence", cap)
  expect_eq(e.bought, math.min(e.it.need, math.floor(cap / 3)), "Greater Magic Essence que tienes")
end)

test("lo convertido cuenta una vez: otra lista que pide las Lesser no las cuenta", function()
  ConvertedRoute(36)
  ES.Shopping.Add("money", "Lesser", { { itemID = LESSER_MAGIC, quantity = 10, unit = 100, source = "ah" } })
  local route = PhaseRow(GREATER_MAGIC)
  local other = expect(ItemsOf(ES.Shopping.Status(), "money")[LESSER_MAGIC], "falta la lista guardada")
  expect_eq(route.bought, 12, "Greater Magic Essence que tienes")
  expect_eq(other.bought, 0, "Lesser Magic Essence de la lista guardada (ya cuentan para la ruta)")
  expect_eq(other.left, 10, "Lesser Magic Essence que faltan en la lista guardada")
end)

test("una lista guardada no cuenta las Lesser como Greater", function()
  BAGS[GREATER_MAGIC], BAGS[LESSER_MAGIC] = 0, 36
  ES.Shopping.Add("money", "Greater", { { itemID = GREATER_MAGIC, quantity = 10, unit = 300, source = "ah" } })
  local e = expect(ItemsOf(ES.Shopping.Status(), "money")[GREATER_MAGIC], "falta la lista guardada")
  expect_eq(e.bought, 0, "Greater Magic Essence que tienes")
  expect_eq(e.left, 10, "Greater Magic Essence que faltan")
end)

test("con lo convertido, el botón de la AH compra solo lo que falta", function()
  ConvertedRoute(36)
  local e = PhaseRow(GREATER_MAGIC)
  local id, n = ES.Shopping.NextToBuy(ES.Shopping.Status(), GREATER_MAGIC)
  expect_eq(id, GREATER_MAGIC, "lo siguiente que comprar")
  expect_eq(n, e.it.need - 12, "cuántas Greater Magic Essence compra")
  expect(ES.Shopping.PendingAH() > 0, "no queda nada de la AH")
  -- La fila dice cuántas vienen de lo convertido
  OpenPage("shopping")
  local text = AllText()
  expect(text:find(string.format("tienes 12 de %d (12 de lo ya convertido)", e.it.need), 1, true),
    "la fila no dice lo convertido")
end)

---------------------------------------------------------------------------
-- Pergaminos de la AH en la lista de la ruta (spec route-shopping-mode). Con «ruta
-- entera» la lista solo llevaba materiales: tras comprarlo todo, el asistente volvía a
-- mandarte a la AH a por cada pergamino. Sastrería 100-175 con los pergaminos de la
-- Bolsa roja de lana (106-132) y de la Capa de seda azur (148-170) a 1c en la AH (más
-- barato que el vendedor: la mejor fuente es la AH). El de la Bolsa de componentes de
-- lana (100-106) sigue en el vendedor
---------------------------------------------------------------------------
local RED_BAG_SCROLL, AZURE_CLOAK_SCROLL, WOOL_POUCH_SCROLL = 5772, 7089, 253668
local RED_BAG, AZURE_CLOAK = 6688, 8786

local function ScrollsInAH()
  for _, scroll in ipairs({ RED_BAG_SCROLL, AZURE_CLOAK_SCROLL }) do
    ES.db.scans[ES:RealmKey()].items[scroll] = { listings = 1, quantity = 1, minUnit = 1, avgUnit = 1, median = 1, ladder = { 1, 1 } }
  end
end

-- Empieza Sastrería desde `from` hasta 175 con los pergaminos en la AH. byPhase = false:
-- ruta entera. Devuelve la ruta fijada
local function ScrollRoute(from, byPhase)
  ScrollsInAH()
  if byPhase == false then
    ES.db.prof.Tailoring = ES.db.prof.Tailoring or {}
    ES.db.prof.Tailoring.byPhase = false
  end
  local _, plan = StartRoute("Tailoring", from, 175)
  local uses = {}
  for _, st in ipairs(plan.steps) do uses[st.id] = true end
  expect(uses[RED_BAG] and (from > 148 or uses[AZURE_CLOAK]), "la ruta de Sastrería ya no usa las recetas de pergamino de la prueba")
  ES.Earn:Clear()
  return plan
end

local function RouteItems() return ItemsOf(ES.Shopping.Status(), "phase") end

test("ruta entera: la lista pide los pergaminos de la AH y no los de vendedor", function()
  ScrollRoute(100, false)
  expect(ES.Shopping.PhaseLists()[1].whole, "la lista no es de la ruta entera")
  local items = RouteItems()
  local red = expect(items[RED_BAG_SCROLL], "la lista no pide el pergamino de la Bolsa roja de lana")
  local cloak = expect(items[AZURE_CLOAK_SCROLL], "la lista no pide el pergamino de la Capa de seda azur")
  expect_eq(red.it.need, 1, "pergaminos de la Bolsa roja de lana")
  expect_eq(cloak.it.need, 1, "pergaminos de la Capa de seda azur")
  expect_eq(red.it.source, "ah", "de dónde se compra el pergamino")
  expect_eq(items[WOOL_POUCH_SCROLL], nil, "pide el pergamino de vendedor de la Bolsa de componentes de lana")
end)

test("por tramos: la lista pide solo el pergamino del tramo", function()
  ScrollRoute(110)
  expect(not ES.Shopping.PhaseLists()[1].whole, "la lista no es por tramos")
  local items = RouteItems()
  expect_eq(items[RED_BAG_SCROLL] and items[RED_BAG_SCROLL].it.need, 1, "pergamino del tramo (Bolsa roja de lana)")
  expect_eq(items[AZURE_CLOAK_SCROLL], nil, "pide el pergamino de un tramo posterior (Capa de seda azur)")
end)

test("ruta acabada: su lista guardada se quita sola", function()
  local list = ES.Shopping.Add("route", "vieja", { { itemID = 2589, quantity = 5, unit = 15 } }, { key = "Tailoring" })
  expect(list, "no se añadió")
  SKILLS[ES.Data.Tailoring.skillLine] = { 300, 300 }
  ES.Shopping.Status()
  for _, l in ipairs(ES.Shopping.Lists()) do expect(not (l.kind == "route" and l.key == "Tailoring"), "la lista de la ruta acabada sigue") end
end, { state = "full" })

---------------------------------------------------------------------------
-- Lo comprado en la AH que sigue en el correo: cuenta, y la fila lo dice (Discord:
-- "tienes 70 de 70" Mithril Bar sin tener ninguno en las bolsas no se entendía)
---------------------------------------------------------------------------
local MITHRIL_BAR, SOLID_STONE, MAGEWEAVE = 3860, 7912, 4338

-- Gana una subasta de n unidades con la AH abierta (el mensaje del juego)
local function WinAuction(itemID, n)
  ERR_AUCTION_WON_S = "You won an auction for %s"
  NOW = NOW + 1
  FireEvent("CHAT_MSG_SYSTEM", string.format("You won an auction for |cffffffff|Hitem:%d::|h[x]|h|rx%d", itemID, n))
end

-- Lo que dicen debajo del nombre las filas que se ven, una por línea
local function Subs(rows)
  local t = {}
  for _, r in ipairs(rows or {}) do
    if r:IsShown() then t[#t + 1] = tostring(r.sub:GetText()) end
  end
  return table.concat(t, "\n")
end

test("la lista de compra dice lo que sigue en el correo", function()
  BAGS[SOLID_STONE] = 8
  ES.Shopping.Add("calc", "Dazzling Mithril Rapier", {
    { itemID = MITHRIL_BAR, quantity = 70, unit = 500, source = "ah" },
    { itemID = SOLID_STONE, quantity = 20, unit = 140, source = "ah" },
    { itemID = MAGEWEAVE, quantity = 10, unit = 388, source = "ah" }, -- (algo por comprar: sale la lista de junto a la AH)
  })
  AuctionFrame:Show()
  FireEvent("AUCTION_HOUSE_SHOW")
  RunTimers()
  ES.ahOpen = true
  WinAuction(MITHRIL_BAR, 70)
  WinAuction(SOLID_STONE, 12)
  local items = ItemsOf(ES.Shopping.Status(), "calc")
  expect_eq(items[MITHRIL_BAR].bought, 70, "Mithril Bar que tienes")
  expect_eq(items[MITHRIL_BAR].mail, 70, "Mithril Bar en el correo")
  expect_eq(items[SOLID_STONE].bought, 20, "Solid Stone que tienes")
  expect_eq(items[SOLID_STONE].mail, 12, "Solid Stone en el correo (las 8 de las bolsas cuentan antes)")
  expect_eq(items[MAGEWEAVE].mail, nil, "Mageweave Cloth sin comprar")
  local L = ES.L
  local bar = string.format(L["tienes %d de %d"], 70, 70) .. " " .. string.format(L["(%d en el correo)"], 70)
  local stone = string.format(L["tienes %d de %d"], 20, 20) .. " " .. string.format(L["(%d en el correo)"], 12)
  -- Junto a la AH
  ES:RenderShopping()
  local mini = expect(ES.ShoppingMini and ES.ShoppingMini(), "sin la lista de junto a la AH")
  expect(mini:IsShown(), "la lista de junto a la AH no sale")
  local text = Subs(mini.rows)
  expect(text:find(bar, 1, true) and text:find(stone, 1, true), "junto a la AH no dice lo del correo:\n%s", text)
  -- En la pestaña
  OpenPage("shopping")
  text = Subs(ES.shoppingPage.rows)
  expect(text:find(bar, 1, true) and text:find(stone, 1, true), "la pestaña no dice lo del correo:\n%s", text)
  -- Recogido del buzón: lo mismo, sin nada del correo
  BAGS[MITHRIL_BAR], BAGS[SOLID_STONE] = 70, 20
  FireEvent("BAG_UPDATE_DELAYED")
  RunTimers()
  items = ItemsOf(ES.Shopping.Status(), "calc")
  expect(items[MITHRIL_BAR].bought == 70 and items[MITHRIL_BAR].mail == nil, "Mithril Bar recogido sigue en el correo")
  expect(items[SOLID_STONE].bought == 20 and items[SOLID_STONE].mail == nil, "Solid Stone recogido sigue en el correo")
  ES:RenderShopping()
  text = Subs(ES.shoppingPage.rows)
  expect(not text:find(string.format(L["(%d en el correo)"], 70), 1, true), "recogido y la fila sigue diciendo el correo:\n%s", text)
end)

-- Pergaminos de la AH (ver ScrollRoute): cuándo cuentan como comprados y cuándo dejan
-- de pedirse

test("pergamino comprado en la AH: en el correo cuenta como comprado", function()
  ScrollRoute(100, false)
  AuctionFrame:Show()
  FireEvent("AUCTION_HOUSE_SHOW")
  RunTimers()
  ES.ahOpen = true
  WinAuction(RED_BAG_SCROLL, 1)
  local e = expect(RouteItems()[RED_BAG_SCROLL], "la lista no pide el pergamino de la Bolsa roja de lana")
  expect_eq(e.bought, 1, "pergaminos que tienes")
  expect_eq(e.mail, 1, "pergaminos en el correo")
  expect_eq(e.left, 0, "pergaminos que faltan")
  local id = ES.Shopping.NextToBuy(ES.Shopping.Status(), RED_BAG_SCROLL)
  expect(id ~= RED_BAG_SCROLL, "el botón de la AH vuelve a comprar el pergamino que está en el correo")
end)

test("pergamino: al aprender la receta deja de pedirse", function()
  ScrollRoute(100, false)
  BAGS[RED_BAG_SCROLL] = 1
  local e = expect(RouteItems()[RED_BAG_SCROLL], "con el pergamino en las bolsas la fila desaparece antes de aprenderla")
  expect_eq(e.left, 0, "pergaminos que faltan con él en las bolsas")
  -- Lo usas: se aprende y el pergamino se gasta
  BAGS[RED_BAG_SCROLL] = 0
  KNOWN_SPELLS[RED_BAG] = true
  ES.CheckLearned()
  ES.Earn:Clear()
  expect_eq(RouteItems()[RED_BAG_SCROLL], nil, "la lista vuelve a pedir el pergamino de una receta aprendida")
  expect(RouteItems()[AZURE_CLOAK_SCROLL], "la lista deja de pedir el pergamino de la Capa de seda azur")
end)

test("pergamino: el de una receta quitada de la ruta no se pide", function()
  ES.db.prof.Tailoring = ES.db.prof.Tailoring or {}
  ES.db.prof.Tailoring.excluded = { [AZURE_CLOAK] = true } -- (la ✕ de su fila)
  ES.db.prof.Tailoring.byPhase = false
  ScrollsInAH()
  local _, plan = StartRoute("Tailoring", 100, 175)
  for _, st in ipairs(plan.steps) do expect(st.id ~= AZURE_CLOAK, "la ruta usa la Capa de seda azur quitada") end
  ES.Earn:Clear()
  local items = RouteItems()
  expect_eq(items[AZURE_CLOAK_SCROLL], nil, "pide el pergamino de la receta quitada")
  expect(items[RED_BAG_SCROLL], "deja de pedir el pergamino de la Bolsa roja de lana")
end)

test("pergamino: sin él a la venta en la AH, la lista no lo pide", function()
  -- (solo el de la Bolsa roja en la AH: el de la Capa de seda azur, al vendedor)
  ES.db.scans[ES:RealmKey()].items[RED_BAG_SCROLL] = { listings = 1, quantity = 1, minUnit = 1, avgUnit = 1, median = 1, ladder = { 1, 1 } }
  ES.db.scans[ES:RealmKey()].items[AZURE_CLOAK_SCROLL] = nil
  ES.db.prof.Tailoring = ES.db.prof.Tailoring or {}
  ES.db.prof.Tailoring.byPhase = false
  StartRoute("Tailoring", 100, 175)
  ES.Earn:Clear()
  local items = RouteItems()
  expect(items[RED_BAG_SCROLL], "no pide el pergamino que sí está en la AH")
  expect_eq(items[AZURE_CLOAK_SCROLL], nil, "pide un pergamino que no está a la venta en la AH")
end)

test("pergamino que también vende un PNJ: se compra en la AH con el botón de la lista", function()
  -- (con precio de vendedor, la lista lo mandaba al vendedor y el botón de la AH no lo compraba)
  ES.Data.VendorPrices[RED_BAG_SCROLL] = 500
  local plan = ScrollRoute(100, false)
  local e = expect(RouteItems()[RED_BAG_SCROLL], "la lista no pide el pergamino de la Bolsa roja de lana")
  expect_eq(e.it.source, "ah", "de dónde se compra el pergamino")
  expect_eq(e.it.unit, 1, "precio del pergamino (el de la AH)")
  local id, n = ES.Shopping.NextToBuy(ES.Shopping.Status(), RED_BAG_SCROLL)
  expect_eq(id, RED_BAG_SCROLL, "lo siguiente que compra el botón de la AH")
  expect_eq(n, 1, "cuántos pergaminos compra")
  expect(ES.Shopping.PendingAH() > 0, "no queda nada de la AH")
  -- Y las filas de compra de la ruta y del asistente lo compran en la AH
  local inAH = false
  for _, it in ipairs(ES.RouteBuy(plan, "Tailoring", 100).ah) do
    if it.itemID == RED_BAG_SCROLL then inAH = it.unit == 1 end
  end
  expect(inAH, "la compra en la AH de la ruta no lleva el pergamino a su precio de la AH")
end)

-- Los pergaminos que enseña Materiales sin empezar la ruta (con el modo elegido) y los que
-- pide la lista al empezarla
local function PreviewScrolls(byPhase)
  ScrollsInAH()
  ES.db.prof.Tailoring = ES.db.prof.Tailoring or {}
  if byPhase == false then ES.db.prof.Tailoring.byPhase = false else ES.db.prof.Tailoring.byPhase = nil end
  SKILLS[ES.Data.Tailoring.skillLine] = { 100, 175 }
  OpenPage("Tailoring")
  local page = ProfessionPage("Tailoring")
  page.toBox._text = "175"
  if page.toBox._scripts.OnEnterPressed then page.toBox._scripts.OnEnterPressed(page.toBox) end
  RunTimers()
  ES:SelectProfessionView(page, "shop")
  RunTimers()
  expect(not ES:RouteLock("Tailoring"), "la ruta ya estaba empezada")
  local seen = {}
  for _, l in ipairs(page.lines) do
    if l.item == RED_BAG_SCROLL or l.item == AZURE_CLOAK_SCROLL then seen[l.item] = true end
  end
  StartRoute("Tailoring", 100, 175)
  ES.Earn:Clear()
  local listed = {}
  for itemID in pairs(RouteItems()) do
    if itemID == RED_BAG_SCROLL or itemID == AZURE_CLOAK_SCROLL then listed[itemID] = true end
  end
  return seen, listed
end

test("sin empezar la ruta, Materiales enseña los pergaminos que pedirá la lista", function()
  local seen, listed = PreviewScrolls(false)
  expect(seen[RED_BAG_SCROLL] and seen[AZURE_CLOAK_SCROLL], "con ruta entera Materiales no enseña los dos pergaminos")
  for _, scroll in ipairs({ RED_BAG_SCROLL, AZURE_CLOAK_SCROLL }) do
    expect_eq(listed[scroll], seen[scroll], "la lista y Materiales no piden lo mismo del pergamino " .. scroll)
  end
  ES:StopRoute("Tailoring")
  -- Por tramos: los del primer tramo, y la lista lo mismo
  seen, listed = PreviewScrolls()
  expect(not seen[AZURE_CLOAK_SCROLL], "por tramos Materiales enseña el pergamino de un tramo posterior")
  for _, scroll in ipairs({ RED_BAG_SCROLL, AZURE_CLOAK_SCROLL }) do
    expect_eq(listed[scroll], seen[scroll], "por tramos, la lista y Materiales no piden lo mismo del pergamino " .. scroll)
  end
end)

test("comprar el pergamino en la AH: la fila de compra queda hecha y la receta, comprada", function()
  local plan = ScrollRoute(110)
  local function InAH()
    for _, it in ipairs(ES.RouteBuy(plan, "Tailoring", 110, { phase = true }).ah) do
      if it.itemID == RED_BAG_SCROLL then return it end
    end
  end
  expect(InAH(), "la compra en la AH del tramo no lleva el pergamino de la Bolsa roja de lana")
  local name = ES.Data.Tailoring.recipes[RED_BAG].name
  local function LearnTitle()
    for _, l in ipairs(ES:RouteLines("Tailoring")) do
      local t = tostring(l.title or "")
      if t:find(name, 1, true) and (t:find(ES.L["Conseguir receta: "], 1, true) or t:find(ES.L["Receta comprada: "], 1, true)) then return t end
    end
  end
  expect(tostring(LearnTitle()):find(ES.L["Conseguir receta: "], 1, true), "sin comprar, la fila de la receta no dice «Conseguir receta»")
  AuctionFrame:Show()
  FireEvent("AUCTION_HOUSE_SHOW")
  RunTimers()
  ES.ahOpen = true
  WinAuction(RED_BAG_SCROLL, 1)
  ES.Earn:Clear()
  expect_eq(InAH(), nil, "con el pergamino comprado, la compra en la AH lo sigue pidiendo")
  expect(tostring(LearnTitle()):find(ES.L["Receta comprada: "], 1, true), "comprado, la fila dice «%s»", tostring(LearnTitle()))
end)

test("las listas guardadas no llevan los pergaminos de la ruta", function()
  -- (una lista guardada es fija: al aprender la receta y gastarse el pergamino lo
  -- volvería a pedir. Los pergaminos van solo en la lista viva de la ruta)
  ScrollRoute(100, false)
  ES.db.earnMinProfit = 1
  ES.Earn:Clear()
  local res = ES.Earn:Ideas()
  local items = res.shopping and #res.shopping > 0 and res.shopping
    or { { itemID = 2592, quantity = 3, unit = 40, source = "ah" } }
  expect(ES.Shopping.Add("money", "lote", items), "no se añadió la lista guardada")
  for _, s in ipairs(ES.Shopping.Status().lists) do
    if s.list.kind ~= "phase" then
      for _, e in ipairs(s.items) do
        expect(e.it.itemID ~= RED_BAG_SCROLL and e.it.itemID ~= AZURE_CLOAK_SCROLL,
          "la lista guardada «%s» lleva el pergamino %d", tostring(s.list.title), e.it.itemID)
      end
    end
  end
  expect(RouteItems()[RED_BAG_SCROLL], "el pergamino dejó de estar en la lista de la ruta")
end)

test("ruta entera con los materiales comprados: sigue pidiendo el pergamino que falta", function()
  -- Con todo comprado, la ruta lo apunta (SetStocked) y, mientras puedas fabricar, no pide
  -- nada más (hold). El pergamino no cuenta para eso: si no, la lista lo dejaría de pedir
  -- o, sin él, nunca daría la compra por hecha
  local plan = ScrollRoute(100, false)
  for itemID, e in pairs(RouteItems()) do
    if itemID ~= RED_BAG_SCROLL and itemID ~= AZURE_CLOAK_SCROLL then BAGS[itemID] = e.it.need end
  end
  ES.Earn:Clear()
  ES.Shopping.Status()
  expect(ES.Planner.Stocked("Tailoring", plan, 100), "con los materiales comprados y sin los pergaminos, la compra no se da por hecha")
  -- (y lo que gasta el paso en el que estás, ya fabricado: puedes fabricarlo)
  for _, rq in ipairs(plan.steps[1].recipe.r) do BAGS[rq[1]] = math.max(BAGS[rq[1]] or 0, rq[2]) end
  ES.Earn:Clear()
  expect(ES.Planner.PhaseHold("Tailoring", plan, 100), "con todo comprado y el paso aprendido no se sigue con lo que llevas")
  local items = RouteItems()
  local red = expect(items[RED_BAG_SCROLL], "con todo comprado deja de pedir el pergamino de la Bolsa roja de lana")
  expect_eq(red.left, 1, "pergaminos de la Bolsa roja de lana que faltan")
  expect(items[AZURE_CLOAK_SCROLL] and items[AZURE_CLOAK_SCROLL].left == 1, "con todo comprado deja de pedir el pergamino de la Capa de seda azur")
end)
