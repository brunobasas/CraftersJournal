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

-- En combate o en mazmorras el juego da algunos números como "secretos" (issecretvalue):
-- convertirlos (tonumber, math.max...), compararlos u operar con ellos es un error de
-- taint. El asistente los convertía: "attempt to perform numeric conversion on a secret
-- number value (execution tainted by 'CraftersJournal')". Un secreto de mentira: una
-- tabla, que da error al convertirla igual que el de verdad
local SECRET = setmetatable({}, { __tostring = function() return "secreto" end })
local function SecretNav()
  issecretvalue = function(v) return rawequal(v, SECRET) end
  local function V(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
  CreateVector2D = V
  local maps = { [1414] = { mapID = 1414, mapType = 2, name = "Kalimdor" },
    [1453] = { mapID = 1453, mapType = 3, parentMapID = 1414, name = "Stormwind" } }
  local nav = { player = V(0.5, 0.5), facing = 0, speed = 7 }
  C_Map = {
    GetMapInfo = function(m) return maps[m] end,
    GetBestMapForUnit = function() return 1453 end,
    GetPlayerMapPosition = function(m) return m == 1414 and nav.player or nil end,
    GetWorldPosFromMapPos = function(m, v) return 0, V(v.x * 1000, v.y * 2000) end,
    GetMapPosFromWorldPos = function(_, w, m) return m, V(w.x / 1000, w.y / 2000) end,
  }
  GetPlayerFacing = function() return nav.facing end
  GetUnitSpeed = function() return 0, nav.speed end
  local npc = { name = "Georgio Bolero", map = 1414, x = 0.6, y = 0.5, side = "" }
  ES.Waypoints.NPC = function(id) return id == 777 and npc or nil end
  ES.db.prof = { Tailoring = {} }
  local lock = { from = 100, to = 120, started = 4242 }
  ES.RouteLock = function(_, k) return k == "Tailoring" and lock or nil end
  ES.RouteLines = function() return {
    { level = "110", title = "Entrenar Oficial", current = true, icon = 134400, go = function() return 777 end },
  } end
  ES.GetProfessionSkill = function() return 110, 150 end
  return nav, V
end

test("números secretos del juego (combate, mazmorras): el asistente no da error", function()
  A = ES.Assistant
  local nav, V = SecretNav()
  local ok, err = pcall(A.Update)
  expect(ok, "sin secretos ya falla: %s", tostring(err))
  local f = A.Frame()
  expect(tostring(f.nav.big._text):find("^100 yd"), "sin secretos, la flecha no marca 100 yd: %s", tostring(f.nav.big._text))
  local cases = {
    { "la velocidad", function() nav.speed = SECRET end, function() nav.speed = 7 end },
    { "hacia dónde miras", function() nav.facing = SECRET end, function() nav.facing = 0 end },
    { "tu posición", function() nav.player = V(SECRET, SECRET) end, function() nav.player = V(0.5, 0.5) end },
    { "el ratón", function() GetCursorPosition = function() return SECRET, SECRET end end,
      function() GetCursorPosition = function() return 0, 0 end end },
    { "el ancho del minimapa", function() Minimap.GetWidth = function() return SECRET end end,
      function() Minimap.GetWidth = nil end },
  }
  for _, c in ipairs(cases) do
    c[2]()
    local okU, errU = pcall(A.Update)
    local okT, errT = pcall(A.NavTick)
    local okS, errS = pcall(A.SlideTab, 0.1)
    expect(okU, "%s secreta: el asistente da error al actualizarse: %s", c[1], tostring(errU))
    expect(okT, "%s secreta: la flecha da error: %s", c[1], tostring(errT))
    expect(okS, "%s secreta: las pestañas dan error: %s", c[1], tostring(errS))
    c[3]()
  end
  -- Sin posición (secreta), como en una mazmorra: lo dice, sin flecha
  nav.player = V(SECRET, SECRET)
  A.NavTick()
  expect(f.nav.arrow._shown == false, "con la posición secreta se ve la flecha")
end)

test("la flecha pasa a otro PNJ del paso si queda claramente más cerca", function()
  A = ES.Assistant
  local nav = SecretNav()
  local npcs = {
    [777] = { name = "Lejos", map = 1414, x = 0.6, y = 0.5, side = "" },
    [778] = { name = "Cerca", map = 1414, x = 0.3, y = 0.5, side = "" },
  }
  ES.Waypoints.NPC = function(id) return npcs[id] end
  local pos = { 500, 1000 } -- (en el mundo: x * 1000, y * 2000)
  UnitPosition = function() return pos[1], pos[2], 0, 0 end
  local target = 777
  ES.RouteLines = function() return {
    { level = "110", title = "Compra 5× Mild Spices", current = true, icon = 134400, go = function() return target end },
  } end
  A.Update()
  local f = A.Frame()
  expect_eq(f.nav.go(), 777, "destino al empezar el paso")
  -- A medio camino: 778 está más cerca, pero no lo bastante
  target = 778
  pos[1] = 440
  A.Retarget()
  expect_eq(f.nav.go(), 777, "destino con 778 algo más cerca")
  -- Junto a 778
  pos[1] = 320
  A.Retarget()
  expect_eq(f.nav.go(), 778, "destino con 778 mucho más cerca")
end)

test("ojeando una compra de la AH con la AH abierta: el clic compra", function()
  A = ES.Assistant
  SecretNav()
  local bought, other = 0, 0
  ES.RouteLines = function() return {
    { level = "110", title = "Compra 5× Mild Spices", current = true, icon = 134400, buyRow = "vendor",
      onClick = function() other = other + 1 end },
    { level = "110", title = "Compra 146× Chunk of Boar Meat", icon = 134400, buyRow = "ah",
      onClick = function() bought = bought + 1 end },
    { level = "110", title = "Fabrica", icon = 134400, stepRecipe = "x" },
  } end
  A.Update()
  local f, st = A.Frame(), A.State()
  f.arrows.next._scripts.OnClick(f.arrows.next)
  expect_eq(st.peek, 2, "paso ojeado")
  f.banner._scripts.OnClick(f.banner, "LeftButton")
  expect_eq(bought, 1, "compras abiertas con el clic")
  expect_eq(other, 0, "clics al paso actual")
  -- Ojeando un paso sin compra: el clic vuelve al actual
  f.arrows.next._scripts.OnClick(f.arrows.next)
  expect_eq(st.peek, 3, "paso ojeado")
  f.banner._scripts.OnClick(f.banner, "LeftButton")
  expect(st.peek == nil, "el clic ojeando la fabricación no vuelve al paso actual")
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

-- Spec route-row-actions: el paso de aprender una receta dice cómo quitarla de la ruta
-- (Discord: quien no quería ir a por las Discolored buscaba cómo en las opciones)
test("el paso de aprender una receta dice cómo quitarla de la ruta", function()
  A = ES.Assistant
  FACTION = "Horde"
  StartRoute("Alchemy", 85, 125)
  A.Update()
  RunTimers()
  local f, st = A.Frame(), A.State()
  local idx
  for i, l in ipairs(st.steps) do
    if l.learnRow and l.trainerLearn and l.learnID == 1244645 then idx = idx or i end
  end
  idx = expect(idx, "el asistente no tiene el paso de aprender Lesser Discolored Healing Potion")
  if idx ~= st.index then A.Peek(idx) end
  ResetTooltip()
  f.banner._scripts.OnEnter(f.banner)
  local tip = table.concat(TOOLTIP, "\n")
  local want = ES.L["¿No quieres aprender esta receta? Abre la ruta en la ventana (el icono del addon, arriba en el asistente) y quítala con la X de su fila: la ruta busca otra."]
  expect(tip:find(want, 1, true), "el tooltip del paso no dice cómo quitarla:\n    %s", tip:gsub("\n", "\n    "))
  local quest = string.format(ES.L["Antes: una misión de %s"], "Apothecary Renferrel")
  expect(tip:find(quest, 1, true), "el tooltip del paso no avisa de la misión de Apothecary Renferrel")
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

-- Cuántas veces se hacen las filas de la ruta empezada (ES:RouteLines) desde ahora
local function CountRouteLines()
  local n, lines = 0, ES.RouteLines
  ES.RouteLines = function(...) n = n + 1 return lines(...) end
  return function() return n end
end

-- Antes el asistente y los avisos de tramo del chat hacían las mismas filas cada uno
-- con cada cambio de las bolsas (PR #8): ahora los avisos salen de las del asistente
test("cambio en las bolsas: las filas de la ruta se hacen una vez", function()
  A = ES.Assistant
  StartRoute("Tailoring", 1, 75)
  A.Update()
  RunTimers()
  ES.phaseState.Tailoring = ES.phaseState.Tailoring or {} -- (los avisos, en marcha: lo pone la subida de nivel)
  local built = CountRouteLines()
  local notices, given, phase = 0, 0, ES.PhaseNotices
  ES.PhaseNotices = function(self, profKey, lines, ...)
    notices = notices + 1
    if lines then given = given + 1 end
    return phase(self, profKey, lines, ...)
  end
  BAGS[2589] = (BAGS[2589] or 0) + 5
  FireEvent("BAG_UPDATE_DELAYED")
  RunTimers()
  expect_eq(built(), 1, "veces que se hacen las filas de la ruta")
  expect_eq(notices, 1, "pasadas de los avisos de tramo")
  expect_eq(given, 1, "pasadas de los avisos con las filas del asistente")
  expect(ES.phaseState.Tailoring.last, "los avisos de tramo no miraron el tramo")
end, { state = "scan" })

-- Questeando con una ruta empezada y la ventana cerrada, cada botín cambia las bolsas:
-- lo que trabaja el addon por cada cambio (miles de instrucciones de Lua), con algo que
-- la ruta no usa y con un material de la ruta. Si sube, el addon pesa más al questear
test("questeando: lo que trabaja el addon con cada botín", function()
  A = ES.Assistant
  StartRoute("Tailoring", 1, 150)
  A.Update()
  ES:HideMainFrame()
  RunTimers(120)
  local function Loot(itemID)
    BAGS[itemID] = (BAGS[itemID] or 0) + 1
    local ticks = 0
    debug.sethook(function() ticks = ticks + 1 end, "", 1000)
    local ok, err = pcall(function()
      FireEvent("BAG_UPDATE")
      FireEvent("BAG_UPDATE_DELAYED")
      RunTimers(5)
    end)
    debug.sethook()
    if not ok then error(err, 0) end
    return ticks
  end
  Loot(4865) -- (la primera vez puede preparar cosas: no cuenta)
  local other = Loot(4865)     -- Ruined Pelt: no es de la ruta
  local material = Loot(2589)  -- Linen Cloth: sí
  note("miles de instrucciones por botín: %d (algo que la ruta no usa), %d (un material de la ruta)", other, material)
  budget("miles de instrucciones por botín fuera de la ruta (Sastrería 1-150)", other, 0.2, 20)
  budget("miles de instrucciones por botín de la ruta (Sastrería 1-150)", material, 0.2, 20)
end, { state = "scan" })

-- Al salir del combate solo falta volver a poner el botón seguro: antes se rehacía la
-- ruta entera tras cada pelea (PR #8)
test("al salir del combate el asistente se repinta sin rehacer la ruta", function()
  A = ES.Assistant
  StartRoute("Tailoring", 1, 75)
  A.Update()
  RunTimers()
  local title = tostring(A.Frame().banner.title._text)
  local built = CountRouteLines()
  IN_COMBAT = true
  FireEvent("PLAYER_REGEN_DISABLED")
  IN_COMBAT = false
  FireEvent("PLAYER_REGEN_ENABLED")
  RunTimers()
  expect_eq(built(), 0, "veces que se hacen las filas de la ruta al salir del combate")
  expect(A.Frame():IsShown(), "el asistente se escondió")
  expect_eq(tostring(A.Frame().banner.title._text), title, "paso del banner")
end, { state = "scan" })
