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

test("ruta acabada: su lista guardada se quita sola", function()
  local list = ES.Shopping.Add("route", "vieja", { { itemID = 2589, quantity = 5, unit = 15 } }, { key = "Tailoring" })
  expect(list, "no se añadió")
  SKILLS[ES.Data.Tailoring.skillLine] = { 300, 300 }
  ES.Shopping.Status()
  for _, l in ipairs(ES.Shopping.Lists()) do expect(not (l.kind == "route" and l.key == "Tailoring"), "la lista de la ruta acabada sigue") end
end, { state = "full" })
