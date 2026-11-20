-- Asistente de ruta: el banner con el paso que toca de la ruta empezada

local A

local function Steps()
  local lines = ES:RouteLines("Tailoring", { buy = true })
  local current
  for _, l in ipairs(lines or {}) do if l.current then current = l end end
  return lines, current
end

test("sacar del banco: con las bolsas normales llenas, va a la de componentes", function()
  A = ES.Assistant
  local CC, moves = C_Container, {}
  -- Banco (-1): 20 Linen Cloth; bolsa 0: una casilla, ocupada; bolsa de componentes: vacía
  CC.GetContainerNumSlots = function(bag)
    if bag == -1 or bag == 0 then return 1 end
    if bag == 5 then return 16 end
    return 0
  end
  CC.GetContainerItemInfo = function(bag, slot)
    if bag == -1 and slot == 1 then return { itemID = 2589, stackCount = 20 } end
    if bag == 0 and slot == 1 then return { itemID = 2318, stackCount = 1 } end
  end
  CC.PickupContainerItem = function(bag, slot) moves[#moves + 1] = bag .. ":" .. slot end
  CursorHasItem = function() return false end
  A.SetBankOpen(true)
  local left = A.TakeFromBank({ { itemID = 2589, quantity = 20 } })
  expect_eq(left, 0, "unidades que no cupieron")
  expect_eq(table.concat(moves, " "), "-1:1 5:1", "movimientos (del banco a la bolsa de componentes)")
end)

test("sin ruta empezada no sale", function()
  A = ES.Assistant
  A.Update()
  local f = A.Frame()
  expect(not (f and f:IsShown()), "el asistente sale sin ruta")
end)

test("con una ruta empezada sale con el paso que toca", function()
  A = ES.Assistant
  StartRoute("Tailoring", 1, 75)
  A.Update()
  RunTimers()
  local f = expect(A.Frame(), "no hay ventana del asistente")
  expect(f:IsShown(), "con una ruta empezada el asistente debería verse")
  local st = A.State()
  local lines, current = Steps()
  expect(current, "la ruta no tiene paso actual")
  expect(#st.steps > 0, "el asistente no tiene pasos")
  local title = tostring(f.banner.title._text)
  expect(title == tostring(current.bannerTitle or current.title), "el banner dice «%s» y el paso actual de la ruta es «%s»",
    title, tostring(current.bannerTitle or current.title))
  note("paso: %s · %s", tostring(f.banner.level._text), title)
end, { state = "scan" })

test("flechas: ojear el paso siguiente y volver", function()
  A = ES.Assistant
  StartRoute("Tailoring", 1, 75)
  A.Update()
  local f, st = A.Frame(), A.State()
  if #st.steps < 2 then note("solo un paso: nada que ojear") return end
  local title = f.banner.title._text
  f.arrows.next._scripts.OnClick(f.arrows.next)
  expect(st.peek, "no ojea el siguiente")
  f.arrows.prev._scripts.OnClick(f.arrows.prev)
  expect(st.peek == nil and f.banner.title._text == title, "no vuelve al paso actual")
end, { state = "scan" })

test("al subir de nivel pasa al paso siguiente", function()
  A = ES.Assistant
  local page, plan = StartRoute("Tailoring", 1, 75)
  A.Update()
  local before = A.State().index
  local first = plan.steps[1]
  expect(first and plan.steps[2], "la ruta tiene un solo paso")
  SKILLS[ES.Data.Tailoring.skillLine] = { first.to, 75 }
  FireEvent("SKILL_LINES_CHANGED")
  RunTimers()
  A.Update()
  RunTimers()
  local _, current = Steps()
  local f = A.Frame()
  expect(A.State().index ~= before or tostring(f.banner.title._text) == tostring(current.bannerTitle or current.title),
    "el asistente no avanza al subir a %d", first.to)
  expect(tostring(f.banner.title._text) == tostring(current.bannerTitle or current.title), "el banner no es el paso actual")
end, { state = "scan" })

-- CurseForge: comprando por tramos, la compra pedía Silk Cloth para 8 Bolt y el
-- asistente decía "Craft 82× Bolt of Silk Cloth" (los de toda la ruta)
test("por tramos, el paso del intermedio pide lo del tramo", function()
  A = ES.Assistant
  local _, plan = StartRoute("Tailoring", 120, 150)
  A.Update()
  RunTimers()
  local c = expect(plan.crafted[1], "la ruta de Sastrería 120-150 no fabrica intermedios: la prueba no prueba nada")
  local step
  for _, l in ipairs(A.State().steps) do
    if l.item == c.itemID and l.stepRecipe then step = l end
  end
  step = expect(step, "el asistente no tiene el paso de fabricar %d", c.itemID)
  local n = tonumber(tostring(step.bannerTitle or step.title):match("(%d+)×"))
  local inPhase = ES.Planner.PhaseCraftedNeed(plan, c.itemID, 120)
  note("asistente: %s · tramo: %s · ruta entera: %d", tostring(n), tostring(inPhase), ES.Planner.CraftedTotal(c))
  expect(inPhase and inPhase < ES.Planner.CraftedTotal(c), "el tramo pide lo mismo que la ruta: la prueba no prueba nada")
  expect_eq(n, inPhase, "intermedios que pide el paso del asistente")
end, { state = "scan" })

test("en combate no se toca lo protegido", function()
  A = ES.Assistant
  StartRoute("Tailoring", 1, 75)
  IN_COMBAT = true
  FireEvent("PLAYER_REGEN_DISABLED")
  A.Update()
  IN_COMBAT = false
  FireEvent("PLAYER_REGEN_ENABLED")
  RunTimers()
end, { state = "scan" })
