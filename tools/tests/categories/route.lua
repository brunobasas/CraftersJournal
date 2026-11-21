-- Subir profesiones: la portada, la página de cada profesión y las rutas que calcula
-- el planificador, con los precios fijos de tools/tests/fixtures.lua

local function Finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end

-- Lo que cumple cualquier ruta válida (devuelve los problemas, vacío si ninguno)
local function RouteProblems(prof, plan, from, to)
  local bad = {}
  local function Bad(...) bad[#bad + 1] = string.format(...) end
  if type(plan) ~= "table" then return { "no hay ruta" } end
  if plan.from ~= from or plan.to ~= to then Bad("de %s a %s (pedida de %d a %d)", tostring(plan.from), tostring(plan.to), from, to) end
  local recipes = ES.Data[prof].recipes
  local prevFrom, prevTo = from, from
  for i, s in ipairs(plan.steps) do
    local r = recipes[s.id]
    local where = string.format("paso %d (%s, %s-%s)", i, r and r.name or tostring(s.id), tostring(s.from), tostring(s.to))
    if not r then Bad("%s: receta que no es de %s", where, prof) end
    if not (s.from and s.to and s.from <= s.to) then Bad("%s: niveles al revés", where) end
    if s.from and s.from < prevFrom then Bad("%s: el nivel baja (antes %d)", where, prevFrom) end
    if s.from and s.from < from or (s.to and s.to > to) then Bad("%s: fuera de la ruta", where) end
    if not (Finite(s.crafts) and s.crafts > 0) then Bad("%s: fabricaciones %s", where, tostring(s.crafts)) end
    if not (Finite(s.unitCost) and s.unitCost >= 0) then Bad("%s: coste por fabricación %s", where, tostring(s.unitCost)) end
    if r then
      -- Gris al fabricarla: ya no da puntos
      if s.from >= r.t[4] then Bad("%s: gris a %d (gris desde %d)", where, s.from, r.t[4]) end
      -- Se aprende antes de usarla
      local learn = ES.Planner.LearnSkill(r, ES:PlanOptions(prof, from, to))
      if not learn then Bad("%s: no se puede aprender", where)
      elseif learn > s.from then Bad("%s: se aprende a %d y se usa a %d", where, learn, s.from) end
    end
    prevFrom, prevTo = s.from or prevFrom, s.to or prevTo
  end
  for _, k in ipairs({ "reagentCost", "fees", "resale", "net" }) do
    if not Finite(plan[k]) then Bad("%s = %s", k, tostring(plan[k])) end
  end
  if Finite(plan.reagentCost) and plan.reagentCost < 0 then Bad("materiales negativos: %s", plan.reagentCost) end
  if Finite(plan.fees) and plan.fees < 0 then Bad("instructor negativo: %s", plan.fees) end
  if Finite(plan.resale) and plan.resale < 0 then Bad("reventa negativa: %s", plan.resale) end
  -- El total es la suma de sus partes
  local sum = (plan.reagentCost or 0) + (plan.fees or 0) + (plan.toolsCost or 0) - (plan.resale or 0)
  if Finite(plan.net) and math.abs(plan.net - sum) > 1 then
    Bad("total %.0f y materiales + instructor + herramientas - reventa = %.0f", plan.net, sum)
  end
  if not (type(plan.reached) == "number" and plan.reached > from and plan.reached <= to) then
    Bad("llega a %s", tostring(plan.reached))
  end
  return bad
end

-- Si no llega al objetivo, ¿lo dice? (lo que ve el jugador: las filas de la página)
local function SaysWhyItStops(prof, from, to)
  SKILLS[ES.Data[prof].skillLine] = { from, to }
  local page
  OpenPage(prof)
  page = ProfessionPage(prof)
  page.toBox._text = tostring(to)
  if page.toBox._scripts.OnEnterPressed then page.toBox._scripts.OnEnterPressed(page.toBox) end
  RunTimers()
  local plan = page.plan
  expect(plan, "la página no tiene ruta")
  if plan.reached >= to then return true end
  -- La fila "El plan se queda en N" con su motivo
  for _, l in ipairs(page.lines or {}) do
    if tostring(l.title):find(L_STOP, 1, true) and tostring(l.title):find(tostring(plan.reached), 1, true) then
      return true, tostring(l.sub)
    end
  end
  return false, string.format("la ruta llega a %d de %d y la página no dice dónde se para ni por qué", plan.reached, to)
end
L_STOP = "El plan se queda en"

local function Summary(prof, plan)
  local recipes = ES.Data[prof].recipes
  local list = {}
  for _, s in ipairs(plan.steps) do
    local r = recipes[s.id]
    list[#list + 1] = string.format("%d-%d %s ×%d", s.from, s.to, r and (r.nameEN or r.name) or tostring(s.id), s.crafts)
  end
  return {
    reached = plan.reached, steps = #plan.steps, recipes = list,
    net = math.floor(plan.net + 0.5), fees = math.floor(plan.fees + 0.5),
    reagents = math.floor(plan.reagentCost + 0.5), resale = math.floor(plan.resale + 0.5),
  }
end

-- Interfaz ------------------------------------------------------------------------

local function VisitProfessions()
  OpenPage("home")
  for _, prof in ipairs(ProfessionKeys()) do
    ES:SelectPage(prof)
    RunTimers()
    local page = expect(ProfessionPage(prof), "falta la página de %s", prof)
    expect(page:IsShown(), "la página de %s no se ve", prof)
  end
  -- Flechas: dan la vuelta a todas las profesiones
  ES:SelectPage("Leatherworking")
  local seen = {}
  for _ = 1, #ProfessionKeys() do
    ES:SelectSiblingPage(1)
    RunTimers()
    seen[ES.db.lastPage] = true
  end
  for _, prof in ipairs(ProfessionKeys()) do expect(seen[prof], "las flechas no pasan por %s", prof) end
end

test("portada y páginas de profesión: usuario nuevo", VisitProfessions, { state = "empty" })
test("portada y páginas de profesión: con un escaneo", VisitProfessions, { state = "scan" })
test("portada y páginas de profesión: datos completos", VisitProfessions, { state = "full" })

test("sin escaneo, la ruta dice que escanees", function()
  OpenPage("Leatherworking")
  local page = ProfessionPage("Leatherworking")
  local text = AllText()
  expect(text:find("scan", 1, true) or text:find("Escanea", 1, true) or text:find("escane", 1, true),
    "no dice que hay que escanear")
end, { state = "empty" })

test("la página de una profesión calcula su ruta al abrirla", function()
  SKILLS[ES.Data.Tailoring.skillLine] = { 50, 75 }
  OpenPage("Tailoring")
  local page = ProfessionPage("Tailoring")
  expect_eq(page.from, 50, "nivel detectado")
  expect(page.plan and #page.plan.steps > 0, "no hay ruta en la página")
  local bad = RouteProblems("Tailoring", page.plan, page.plan.from, page.plan.to)
  expect(#bad == 0, "ruta de la página:\n    %s", table.concat(bad, "\n    "))
end)

-- CurseForge: "falta 105-135 de Encantamiento" tras dejar la ruta a medias. La lista
-- estaba bajada hasta el paso actual (la abre así el asistente); al dejar la ruta se
-- rehace desde tu nivel, más corta, y se quedaba desplazada más allá del final: las
-- primeras filas, arriba y fuera de la vista, y un hueco vacío debajo
test("ruta más corta tras dejarla: la lista no se queda desplazada más allá del final", function()
  local page = StartRoute("Tailoring", 1, 150)
  local longH = expect(page.content._height, "la lista no tiene alto")
  -- Bajada hasta el final de la ruta larga
  page.scroll:SetVerticalScroll(math.max(0, longH - page.scroll:GetHeight()))
  local before = page.scroll:GetVerticalScroll()
  -- Subes casi hasta el objetivo y dejas la ruta: se rehace desde ahí, mucho más corta
  SKILLS[ES.Data.Tailoring.skillLine] = { 140, 150 }
  FireEvent("SKILL_LINES_CHANGED")
  RunTimers()
  -- (lo que hace el botón Dejar ruta)
  ES:StopRoute("Tailoring")
  ES:ClearHomeCache()
  ES:CalculatePlan(page)
  RunTimers()
  expect_eq(page.plan.from, 140, "la ruta nueva empieza en tu nivel")
  local shortH = page.content._height
  expect(shortH < before, "la ruta nueva no es más corta (%s y antes bajada %s): la prueba no prueba nada", tostring(shortH), tostring(before))
  local range = math.max(0, shortH - page.scroll:GetHeight())
  local cur = page.scroll:GetVerticalScroll()
  expect(cur <= range, "desplazada %s con un máximo de %s: las primeras %s px de la ruta quedan fuera de la vista",
    tostring(cur), tostring(range), tostring(cur - range))
end, { state = "scan" })

-- CurseForge: "Profit ignora las Small Silk Pack". Estaban (la primera fila), pero la
-- lista seguía bajada como la de Materiales y quedaban arriba, fuera de la vista
test("al cambiar de vista la lista empieza arriba", function()
  local page = StartRoute("Tailoring", 1, 150)
  ES:SelectProfessionView(page, "shop")
  RunTimers()
  local h = expect(page.content._height, "la lista no tiene alto")
  page.scroll:SetVerticalScroll(math.max(0, h - page.scroll:GetHeight()))
  expect(page.scroll:GetVerticalScroll() > 0, "Materiales no se puede bajar: la prueba no prueba nada")
  ES:SelectProfessionView(page, "profit")
  RunTimers()
  expect_eq(page.scroll:GetVerticalScroll(), 0, "desplazamiento de Profit")
  -- Abierta desde el asistente, la vista Ruta sigue bajando hasta el paso actual
  SKILLS[ES.Data.Tailoring.skillLine] = { 140, 150 }
  FireEvent("SKILL_LINES_CHANGED")
  RunTimers()
  ES:SelectProfessionView(page, "route")
  RunTimers()
  expect_eq(page.scroll:GetVerticalScroll(), 0, "desplazamiento de Ruta al cambiar de vista")
  ES.Assistant.Update()
  ES.Assistant.OpenWindow("route")
  RunTimers()
  expect(page.scroll:GetVerticalScroll() > 0, "abierta desde el asistente no baja hasta el paso actual")
end, { state = "scan" })

-- Intermedios con la ruta empezada: la fila "Fabrica N× <Bolt>" pide los que da el paño
-- que pide la compra (por tramos: el del tramo). CurseForge: la compra del tramo pedía
-- 32 Silk Cloth y la fila "Fabrica 82× Bolt of Silk Cloth", los de toda la ruta. Con
-- los precios de las pruebas, la ruta de Sastrería 120-150 usa Bolt of Woolen Cloth

-- Ruta de Sastrería 120-150 empezada, con el modo de compra `byPhase` (nil: el de por
-- defecto, por tramos; false: ruta entera). Devuelve un resumen del primer intermedio
-- de la ruta: { item, whole (lo que gasta la ruta), row (lo que pide su fila), raw
-- (su material), per (material por unidad), buy (lo que pide la compra de ese material) }
local function PrepRoute(byPhase)
  ES.db.prof.Tailoring = ES.db.prof.Tailoring or {}
  ES.db.prof.Tailoring.byPhase = byPhase
  local page, plan = StartRoute("Tailoring", 120, 150)
  ES:SelectProfessionView(page, "route")
  RunTimers()
  local c = expect(plan.crafted[1], "la ruta de Sastrería 120-150 no fabrica intermedios: la prueba no prueba nada")
  local res = { page = page, plan = plan, item = c.itemID, whole = ES.Planner.CraftedTotal(c) }
  for _, l in ipairs(page.lines or {}) do
    if l.item == c.itemID and l.stepRecipe then res.row = tonumber(tostring(l.title):match("(%d+)×")) break end
  end
  expect(res.row, "no hay fila de fabricar %d en la vista Ruta", c.itemID)
  local rq = c.recipe.r[1]
  res.raw, res.per = rq[1], rq[2] / ((c.recipe.out and c.recipe.out[2]) or 1)
  local need = ES.Planner.RouteNeed("Tailoring", plan, 120)
  res.buy = need[res.raw] and need[res.raw].need or 0
  note("fila: %s × %d · compra: %d × %d (%s por unidad) · ruta entera: %d", tostring(res.row), res.item,
    res.buy, res.raw, tostring(res.per), res.whole)
  return res
end

-- La fila pide lo que da el material de la compra, redondeando hacia arriba
local function RowMatchesBuy(r)
  expect(r.buy > 0, "la compra no pide el material del intermedio")
  expect(r.row * r.per >= r.buy and r.row * r.per < r.buy + r.per,
    "la fila pide %d (son %s de material) y la compra %d", r.row, tostring(r.row * r.per), r.buy)
end

test("ruta empezada por tramos: la fila del intermedio pide lo del tramo, como la compra", function()
  local r = PrepRoute(nil)
  expect(r.row < r.whole, "la fila pide %d, los de toda la ruta (%d), no los del tramo", r.row, r.whole)
  RowMatchesBuy(r)
end, { state = "scan" })

test("ruta empezada con ruta entera: la fila del intermedio pide lo que queda de ruta", function()
  local r = PrepRoute(false)
  expect_eq(r.row, r.whole, "intermedios que pide la fila")
  RowMatchesBuy(r)
end, { state = "scan" })

test("cambiar de modo con la ruta empezada cambia la fila del intermedio", function()
  local r = PrepRoute(nil)
  local function Row()
    ES:RenderPlan(r.page)
    RunTimers()
    for _, l in ipairs(r.page.lines) do
      if l.item == r.item and l.stepRecipe then return tonumber(tostring(l.title):match("(%d+)×")) end
    end
  end
  ES.db.prof.Tailoring.byPhase = false
  expect_eq(Row(), r.whole, "con ruta entera")
  ES.db.prof.Tailoring.byPhase = nil
  expect_eq(Row(), r.row, "otra vez por tramos")
end, { state = "scan" })

-- Rutas de 1 a 300 de cada profesión, e instantánea ------------------------------

for _, prof in ipairs({ "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Cooking", "FirstAid" }) do
  test("ruta de 1 a 300: " .. prof, function()
    -- Lo que cuesta calcularla, en lo que no depende del equipo ni de lo que esté
    -- haciendo (con WoW abierto y las pruebas en paralelo, los segundos llegan a
    -- duplicarse sin cambiar nada): las pasadas del planificador y las instrucciones de
    -- Lua que ejecuta (con el mismo código, siempre las mismas). Una ruta que de golpe
    -- tarda mucho más se ve antes de publicar. Los segundos, solo como dato
    local ticks = 0
    local passes0, cpu0 = ES.Planner.passes, os.clock()
    debug.sethook(function() ticks = ticks + 1 end, "", 1000) -- (una llamada cada 1000 instrucciones)
    local ok, plan = pcall(PlanRoute, prof, 1, 300)
    debug.sethook()
    if not ok then error(plan, 0) end
    local passes, cpu = ES.Planner.passes - passes0, os.clock() - cpu0
    budget("pasadas 1-300 " .. prof, passes, 0.15, 5)
    budget("millones de instrucciones 1-300 " .. prof, math.floor(ticks / 100 + 0.5) / 10, 0.15, 2)
    note("%.1f s de CPU (solo informativo: depende del equipo y de la carga)", cpu)
    local bad = RouteProblems(prof, plan, 1, 300)
    note("%d pasos, llega a %s, total %.0f cobre%s", #plan.steps, tostring(plan.reached), plan.net,
      (plan.reached or 0) < 300 and (" · se para: " .. tostring(plan.why or plan.stuck or (plan.missingPrice and "falta precio de " .. tostring(next(plan.missingPrice))) or "info pendiente")) or "")
    expect(#bad == 0, "%s:\n    %s", prof, table.concat(bad, "\n    "))
    snapshot("ruta 1-300 " .. prof, Summary(prof, plan))
  end)
end

-- Desde un nivel intermedio con recetas aprendidas: no las vuelve a cobrar
for _, case in ipairs({ { "Leatherworking", 120 }, { "Tailoring", 150 }, { "Cooking", 100 }, { "Blacksmithing", 90 } }) do
  local prof, level = case[1], case[2]
  test(string.format("ruta desde %d con recetas aprendidas: %s", level, prof), function()
    local data = ES.Data[prof]
    SKILLS[data.skillLine] = { level, 300 }
    -- Aprendidas: las que se ponen naranjas antes de ese nivel
    local known = 0
    for id, r in pairs(data.recipes) do
      if r.t[1] <= level and (r.fee or r.basic) then KNOWN_SPELLS[id] = true known = known + 1 end
    end
    local to = math.min(300, level + 75)
    local plan = PlanRoute(prof, level, to)
    local bad = RouteProblems(prof, plan, level, to)
    for i, s in ipairs(plan.steps) do
      if KNOWN_SPELLS[s.id] and (s.fee or 0) > 0 then
        bad[#bad + 1] = string.format("paso %d: cobra %s por una receta aprendida (%s)", i, tostring(s.fee), tostring(data.recipes[s.id].name))
      end
    end
    note("%d recetas aprendidas; %d pasos hasta %d", known, #plan.steps, to)
    expect(#bad == 0, "%s desde %d:\n    %s", prof, level, table.concat(bad, "\n    "))
  end)
end

test("una ruta que no llega al objetivo dice por qué: Primeros auxilios", function()
  -- (a 270 lo que sigue son pergaminos de botín que no están en la AH de las pruebas)
  local ok, why = SaysWhyItStops("FirstAid", 225, 300)
  expect(ok, why)
  note("motivo: %s", why)
  expect(why:find("pergaminos", 1, true), "el motivo no dice que lo que sigue son pergaminos: «%s»", why)
  expect(why:find("Cataplasma poderosa", 1, true) or why:find("Torniquete", 1, true) or why:find(",", 1, true),
    "el motivo no nombra las recetas: «%s»", why)
end)

test("con el pergamino en la AH, deja de ser motivo de parada", function()
  -- Si un pergamino de los que faltan está en la AH, la ruta lo usa o, si no, ya no lo
  -- da como motivo de que no haya de dónde sacarlo
  local scan = ES.db.scans[ES:RealmKey()]
  for _, id in ipairs({ 1259345, 1259349, 1244436 }) do
    local r = ES.Data.FirstAid.recipes[id]
    if r and r.scroll then scan.items[r.scroll] = { listings = 1, quantity = 1, minUnit = 5000, avgUnit = 5000, median = 5000, ladder = { 5000, 1 } } end
  end
  local ok, why = SaysWhyItStops("FirstAid", 225, 300)
  expect(ok, why or "")
  -- (sin motivo: llega al objetivo)
  expect(why == nil, "con los pergaminos en la AH la ruta debería llegar a 300; se para: «%s»", tostring(why))
  local plan = ProfessionPage("FirstAid").plan
  expect_eq(plan.reached, 300, "nivel al que llega")
  note("llega a %d", plan.reached)
end)

-- Cuándo se calcula la ruta (spec route-recalculation) ----------------------------
-- CurseForge: "cada vez que abro el addon se calculan las rutas"

-- Como al salir del juego y volver a entrar: lo guardado se queda, la memoria no
local function Reload()
  ES.homePlanCache, ES.lastRoutes, ES.lockedPlans, ES.planFailed, ES.knownStamp = {}, {}, {}, {}, {}
  ES.planGen, ES.planGens = 0, {}
end

-- La ruta de la página de una profesión (nivel `from`, tope `cap`), ya calculada
local function PageRoute(prof, from, cap)
  SKILLS[ES.Data[prof].skillLine] = { from, cap }
  OpenPage(prof)
  local page = ProfessionPage(prof)
  RunTimers()
  local plan = expect(page.plan, "%s: la página no tiene ruta", prof)
  expect(#plan.steps > 0, "%s: la ruta no tiene pasos: la prueba no prueba nada", prof)
  return page, plan, page.detected and page.detected.cap
end

-- Búsquedas completas de ruta (el GPS) desde ahora. (Planner.passes no sirve para esto:
-- cada cálculo en segundo plano lo pone a 0 para su barra de progreso)
local function CountSearches()
  local P, n = ES.Planner, 0
  local gps = P.PlanGPS
  P.PlanGPS = function(...) n = n + 1 return gps(...) end
  return function() return n end
end

local function Card(prof)
  for _, c in ipairs(ES.homePage and ES.homePage.cards or {}) do
    if c.key == prof and c:IsShown() then return c end
  end
end
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local OPEN_TO_CALC = Plain(ES.L["Abrir para calcular|r"])

test("la portada no calcula rutas: dice «Abrir para calcular»", function()
  SKILLS[ES.Data.Tailoring.skillLine] = { 50, 75 }
  SKILLS[ES.Data.Leatherworking.skillLine] = { 60, 75 }
  local passes, searches = ES.Planner.passes, CountSearches()
  OpenPage("home")
  expect_eq(ES.Planner.passes - passes, 0, "pasadas del planificador al abrir la portada")
  expect_eq(searches(), 0, "rutas buscadas al abrir la portada")
  expect(not ES.Jobs.Queued("plan:"), "hay rutas en cola al abrir la portada")
  for _, prof in ipairs({ "Tailoring", "Leatherworking" }) do
    local card = expect(Card(prof), "no hay tarjeta de %s", prof)
    expect_eq(Plain(card.note:GetText()), OPEN_TO_CALC, "nota de la tarjeta de " .. prof)
  end
end, { state = "scan" })

test("la portada enseña el coste de una ruta ya calculada sin calcularla", function()
  local _, plan = PageRoute("Tailoring", 50, 75)
  local passes, searches = ES.Planner.passes, CountSearches()
  OpenPage("home")
  expect_eq(ES.Planner.passes - passes, 0, "pasadas del planificador al abrir la portada")
  expect_eq(searches(), 0, "rutas buscadas al abrir la portada")
  local card = expect(Card("Tailoring"), "no hay tarjeta de Sastrería")
  expect(Plain(card.note:GetText()) ~= OPEN_TO_CALC, "la tarjeta dice «%s» con la ruta calculada", OPEN_TO_CALC)
  expect(Plain(card.cost:GetText()):find("%d"), "la tarjeta no enseña el coste: «%s»", Plain(card.cost:GetText()))
  -- Tras recargar: la guardada, rehecha en una pasada
  Reload()
  passes = ES.Planner.passes
  ES:RenderHome()
  expect_eq(ES.Planner.passes - passes, 1, "pasadas para enseñar la ruta guardada")
  expect_eq(searches(), 0, "rutas buscadas tras recargar")
  expect(Plain(card.cost:GetText()):find("%d"), "tras recargar, la tarjeta no enseña el coste")
  note("coste: %s (%.0f)", Plain(card.cost:GetText()), plan.net)
end, { state = "scan" })

test("volver a abrir una profesión ya calculada no la calcula", function()
  PageRoute("Tailoring", 50, 75)
  ES:HideMainFrame()
  local searches = CountSearches()
  OpenPage("Tailoring")
  expect_eq(searches(), 0, "rutas buscadas al volver a abrirla")
end, { state = "scan" })

test("clave estable: cambia con las recetas sabidas, el instructor, el standing y la versión", function()
  SKILLS[ES.Data.Tailoring.skillLine] = { 50, 75 }
  SKILLS[ES.Data.Leatherworking.skillLine] = { 50, 75 }
  local function K(prof) return ES:StableRouteKey(prof or "Tailoring", 50, 75, 75) end
  local base, lw = K(), K("Leatherworking")
  expect_eq(K(), base, "sin cambiar nada")
  -- Recetas sabidas
  for id, r in pairs(ES.Data.Tailoring.recipes) do
    if r.fee and not KNOWN_SPELLS[id] then KNOWN_SPELLS[id] = true break end
  end
  ES.CheckLearned()
  local known = K()
  expect(known ~= base, "aprender una receta no cambia la clave")
  -- Precios de instructor (solo los de esa profesión)
  local recipes = {}
  for id, r in pairs(ES.Data.Tailoring.recipes) do
    if r.fee and #recipes < 2 then recipes[#recipes + 1] = { id = id, r = r } end
  end
  local services = {}
  for i, x in ipairs(recipes) do
    services[i] = { name = x.r.nameEN or x.r.name, kind = "available", cost = 4321 + i, skill = x.r.train or 1, spell = x.id }
  end
  GetNumTrainerServices = function() return #services end
  GetTrainerServiceInfo = function(i) local s = services[i] return s.name, "", s.kind end
  GetTrainerServiceCost = function(i) return services[i].cost end
  GetTrainerServiceSkillReq = function(i) return "Tailoring", services[i].skill, true end
  GetTrainerServiceSkillLine = function() return ES:ProfLabel("Tailoring") end
  GetTrainerServiceItemLink = function() return nil end
  GetTrainerServiceLink = function(i) return "|Hspell:" .. services[i].spell .. "|h[x]|h" end
  GetTrainerServiceTypeFilter = function() return true end
  SetTrainerServiceTypeFilter = function() end
  FireEvent("TRAINER_SHOW")
  RunTimers()
  FireEvent("TRAINER_CLOSED")
  RunTimers()
  local trainer = K()
  expect(trainer ~= known, "un precio de instructor nuevo no cambia la clave")
  expect_eq(K("Leatherworking"), lw, "clave de Peletería tras el instructor de Sastrería")
  -- Standing con las facciones que dan recetas
  local standing = ES.Standing
  ES.Standing = function() return 8 end
  expect(K() ~= trainer, "cambiar el standing no cambia la clave")
  ES.Standing = standing
  expect_eq(K(), trainer, "con el standing de antes")
  -- Versión del addon
  GetAddOnMetadata = function(_, field) if field == "Version" then return "99.0.0" end end
  expect(K() ~= trainer, "otra versión del addon no cambia la clave")
end, { state = "scan" })

test("ruta guardada: tras recargar se rehace en una pasada, con las mismas recetas y coste", function()
  local _, plan, cap = PageRoute("Tailoring", 150, 225)
  local saved = expect(ES.db.prof.Tailoring.lastRoute, "no se guardó la ruta")
  expect_eq(saved.key, ES:StableRouteKey("Tailoring", plan.from, plan.to, cap), "clave guardada")
  Reload()
  local passes = ES.Planner.passes
  local again = expect(ES:CachedPlan("Tailoring", plan.from, plan.to, cap), "tras recargar no se usa la ruta guardada")
  expect_eq(ES.Planner.passes - passes, 1, "pasadas del planificador para rehacerla")
  expect_eq(#again.steps, #plan.steps, "pasos")
  for i, s in ipairs(plan.steps) do
    expect_eq(again.steps[i].id, s.id, "receta del paso " .. i)
  end
  expect_near(again.net, plan.net, 1, "coste")
  -- Y la página la enseña sin buscarla
  Reload()
  ES:HideMainFrame()
  local searches = CountSearches()
  OpenPage("Tailoring")
  expect(ProfessionPage("Tailoring").plan, "la página no tiene ruta tras recargar")
  expect_eq(searches(), 0, "rutas buscadas al abrir la página tras recargar")
end, { state = "scan" })

test("ruta guardada: no se guarda si faltaban precios de vendedor", function()
  ES:StorePlan("Cooking", "k", "stable", { choice = { [1] = 2538 }, reached = 2, steps = {}, pendingItems = { [159] = true } })
  expect(not (ES.db.prof.Cooking and ES.db.prof.Cooking.lastRoute), "se guardó una ruta con precios pendientes")
  ES:StorePlan("Cooking", "k", "stable", { choice = { [1] = 2538 }, reached = 2, steps = {} })
  expect(ES.db.prof.Cooking.lastRoute, "no se guardó una ruta completa")
end, { state = "scan" })

test("ruta guardada que no se puede rehacer: se descarta y se calcula", function()
  local _, plan, cap = PageRoute("Tailoring", 50, 75)
  local saved = ES.db.prof.Tailoring.lastRoute
  saved.choice[plan.from] = 999999 -- (una receta que ya no está en los datos)
  Reload()
  expect(ES:CachedPlan("Tailoring", plan.from, plan.to, cap) == nil, "se usó una ruta guardada que no se puede rehacer")
  expect(ES.db.prof.Tailoring.lastRoute == nil, "la ruta guardada que no vale sigue guardada")
  ES:RequestPlan("Tailoring", plan.from, plan.to, cap)
  RunTimers()
  local again = expect(ES:CachedPlan("Tailoring", plan.from, plan.to, cap), "no se calcula una ruta nueva")
  expect(#again.steps > 0, "la ruta nueva no tiene pasos")
  expect(ES.db.prof.Tailoring.lastRoute, "no se guardó la ruta nueva")
end, { state = "scan" })

test("ruta guardada: deja de valer con escaneo nuevo, receta aprendida, otro nivel u otra versión", function()
  local _, plan, cap = PageRoute("Tailoring", 50, 75)
  local saved = ES.db.prof.Tailoring.lastRoute
  local function Reused(from)
    Reload()
    ES.db.prof.Tailoring.lastRoute = saved
    return ES:CachedPlan("Tailoring", from or plan.from, plan.to, cap) ~= nil
  end
  expect(Reused(), "sin cambios no se reutiliza")
  -- Subir de nivel
  expect(not Reused(plan.from + 1), "se reutiliza la ruta de %d para %d", plan.from, plan.from + 1)
  -- Escaneo nuevo
  local scan = ES.db.scans[ES:RealmKey()]
  scan.time = scan.time + 60
  expect(not Reused(), "se reutiliza tras un escaneo nuevo")
  scan.time = scan.time - 60
  expect(Reused(), "con el escaneo de antes no se reutiliza")
  -- Receta aprendida entre sesiones
  local learned
  for id, r in pairs(ES.Data.Tailoring.recipes) do
    if r.fee and not KNOWN_SPELLS[id] then learned = id break end
  end
  KNOWN_SPELLS[learned] = true
  expect(not Reused(), "se reutiliza tras aprender una receta")
  KNOWN_SPELLS[learned] = nil
  -- Versión nueva del addon
  GetAddOnMetadata = function(_, field) if field == "Version" then return "99.0.0" end end
  expect(not Reused(), "se reutiliza con otra versión del addon")
end, { state = "scan" })

test("ruta guardada que ya no vale: sirve de pista y no hace buscar más", function()
  local _, plan = PageRoute("Tailoring", 150, 225)
  local scan = ES.db.scans[ES:RealmKey()]
  scan.time = scan.time + 60 -- (la guardada ya no vale tal cual)
  Reload()
  local passes = ES.Planner.passes
  PlanRoute("Tailoring", plan.from, plan.to)
  local withHint = ES.Planner.passes - passes
  Reload()
  ES.db.prof.Tailoring.lastRoute = nil
  passes = ES.Planner.passes
  PlanRoute("Tailoring", plan.from, plan.to)
  local without = ES.Planner.passes - passes
  note("pasadas con la pista: %d · sin ella: %d", withHint, without)
  expect(withHint <= without, "con la pista guardada busca más (%d pasadas) que sin ella (%d)", withHint, without)
end, { state = "scan" })

-- Con "usar lo de las bolsas": solo los objetos de la ruta la invalidan
local function BagRoute(prof, from, cap)
  ES.db.prof[prof] = ES.db.prof[prof] or {}
  ES.db.prof[prof].useBags = true
  return PageRoute(prof, from, cap)
end

test("bolsas: lootear un objeto que la ruta no usa no la recalcula", function()
  local page, plan = BagRoute("Tailoring", 50, 75)
  local items = ES.RouteItems(plan)
  local other = 999001
  expect(not items[other], "el objeto de prueba está en la ruta")
  local searches = CountSearches()
  BAGS[other] = 5
  FireEvent("BAG_UPDATE_DELAYED")
  RunTimers()
  expect_eq(searches(), 0, "rutas buscadas tras lootear otra cosa")
  expect(page.plan == plan, "la ruta de la página cambió")
end, { state = "scan" })

test("bolsas: cambiar un material de la ruta la invalida solo en su profesión", function()
  local _, lwPlan, lwCap = BagRoute("Leatherworking", 50, 75)
  local lwItems = ES.RouteItems(lwPlan)
  local page, plan = BagRoute("Tailoring", 50, 75)
  local item
  for id in pairs(ES.RouteItems(plan)) do
    if not lwItems[id] then item = id break end
  end
  expect(item, "todos los objetos de Sastrería están en la ruta de Peletería: la prueba no prueba nada")
  local searches = CountSearches()
  BAGS[item] = (BAGS[item] or 0) + 3
  FireEvent("BAG_UPDATE_DELAYED")
  RunTimers()
  expect_eq(searches(), 1, "rutas buscadas tras conseguir " .. item .. " (de la ruta de Sastrería)")
  expect(page.plan ~= plan, "la página sigue con la ruta de antes")
  expect(ES:CachedPlan("Leatherworking", lwPlan.from, lwPlan.to, lwCap) == lwPlan, "la ruta de Peletería dejó de valer")
end, { state = "scan" })

test("bolsas: con la opción desactivada, nada de las bolsas invalida la ruta", function()
  local page, plan = PageRoute("Tailoring", 50, 75)
  expect(not ES.db.prof.Tailoring.useBags, "la opción está activada: la prueba no prueba nada")
  local item = next(ES.RouteItems(plan))
  local searches = CountSearches()
  BAGS[item] = (BAGS[item] or 0) + 3
  FireEvent("BAG_UPDATE_DELAYED")
  RunTimers()
  expect_eq(searches(), 0, "rutas buscadas tras cambiar un material de la ruta")
  expect(page.plan == plan, "la ruta de la página cambió")
end, { state = "scan" })

test("bolsas: la ruta guardada no vale si al entrar llevas otra cantidad de un material suyo", function()
  local _, plan, cap = BagRoute("Tailoring", 50, 75)
  local saved = expect(ES.db.prof.Tailoring.lastRoute, "no se guardó la ruta")
  expect(saved.bags, "la ruta guardada no apunta lo que llevabas")
  Reload()
  expect(ES:CachedPlan("Tailoring", plan.from, plan.to, cap), "con lo mismo en las bolsas no se reutiliza")
  local item = next(saved.bags)
  BAGS[item] = (BAGS[item] or 0) + 3
  Reload()
  expect(ES:CachedPlan("Tailoring", plan.from, plan.to, cap) == nil, "se reutiliza con otra cantidad de %d", item)
end, { state = "scan" })

-- Botones seguros de las filas (spec route-row-actions) ---------------------------
-- GitHub #11: el botón que usa el pergamino era hijo de la fila; un hijo protegido
-- vuelve protegida la ventana entera, y cerrarla en combate (Escape) daba "acción
-- bloqueada". Ahora es el botón compartido de la estrella (Waypoints.lua, HoverRow),
-- suelto en UIParent y colocado encima de la fila al pasar el ratón

-- Una fila de la lista de la página de Sastrería (dentro de la ventana), con `line`
local function WindowRow(line)
  local page = ProfessionPage("Tailoring")
  local row = ES.UI.CreateRow(page.content)
  ES.UI.StyleRow(row, line)
  return row
end
local function Enter(row) row:GetScript("OnEnter")(row) end
local function UseLine(itemID) return { title = "Aprender receta: X", icon = 134400, useItem = itemID } end
local function TrainerLine()
  local id = expect(ES.Waypoints.Trainers("Tailoring", 1)[1], "Sastrería no tiene instructores: la prueba no prueba nada")
  return { title = "Instructor", icon = 134400, go = function() return id end }
end

test("las filas no vuelven protegida la ventana (pergamino en la bolsa y estrella)", function()
  OpenPage("Tailoring")
  local main = ES:GetMainFrame()
  local useRow, starRow = WindowRow(UseLine(12345)), WindowRow(TrainerLine())
  local p = useRow
  while p and p ~= main do p = p:GetParent() end
  expect(p == main, "la fila no está dentro de la ventana: la prueba no prueba nada")
  Enter(useRow)
  Enter(starRow)
  Enter(useRow)
  expect(not main:IsProtected(), "un botón seguro cuelga de la ventana: cerrarla en combate da acción bloqueada")
end, { state = "scan" })

test("el botón compartido usa el objeto de la fila o pone la estrella, nunca las dos cosas", function()
  OpenPage("Tailoring")
  local useRow, starRow = WindowRow(UseLine(12345)), WindowRow(TrainerLine())
  Enter(useRow)
  local h = expect(ES.Waypoints.HoverButton(), "pasar el ratón por la fila del pergamino no pone el botón seguro")
  expect(h:GetParent() == UIParent, "el botón seguro no cuelga de UIParent")
  expect(h._shown and h.row == useRow, "el botón seguro no está sobre la fila del pergamino")
  expect_eq(h:GetAttribute("type"), "item", "tipo del botón sobre el pergamino")
  expect_eq(h:GetAttribute("item"), "item:12345", "objeto que usa")
  expect(h:GetAttribute("macrotext") == nil, "sobre el pergamino el botón aún lleva la macro de la estrella")
  -- Su clic usa el pergamino y nada más (sin la acción de la fila después)
  local clicked = false
  useRow:SetScript("OnClick", function() clicked = true end)
  h:GetScript("PostClick")(h, "LeftButton", false)
  expect(not clicked, "tras usar el pergamino, el clic también hizo lo de la fila")
  Enter(starRow)
  expect(h.row == starRow, "el botón no pasó a la fila del instructor")
  expect_eq(h:GetAttribute("type"), "macro", "tipo del botón sobre el instructor")
  expect(h:GetAttribute("item") == nil, "sobre el instructor el botón aún usa el pergamino")
  Enter(useRow)
  expect(h:GetAttribute("macrotext") == nil and h:GetAttribute("item") == "item:12345", "de vuelta al pergamino, el botón no lo usa")
end, { state = "scan" })

test("la fila cambia con el ratón encima: el botón usa lo de la fila nueva", function()
  OpenPage("Tailoring")
  local row = WindowRow(UseLine(12345))
  Enter(row)
  local h = ES.Waypoints.HoverButton()
  ES.UI.StyleRow(row, UseLine(67890))
  expect(h._shown and h:GetAttribute("item") == "item:67890", "repintada con otro pergamino, el botón usa el de antes: %s", tostring(h:GetAttribute("item")))
  ES.UI.StyleRow(row, { title = "Otra fila", icon = 134400 })
  expect(not h._shown and h.row == nil, "repintada sin objeto, el botón sigue sobre la fila con el pergamino")
end, { state = "scan" })

test("en combate no hay botón de usar objetos sobre las filas", function()
  OpenPage("Tailoring")
  local row = WindowRow(UseLine(12345))
  Enter(row)
  local h = ES.Waypoints.HoverButton()
  local ok, err = pcall(function()
    -- Al entrar en combate (en el evento aún se puede tocar) se suelta
    FireEvent("PLAYER_REGEN_DISABLED")
    IN_COMBAT = true
    expect(not h._shown and h:GetNumPoints() == 0, "al entrar en combate el botón sigue anclado a la fila")
    Enter(row)
    expect(not h._shown, "en combate el botón vuelve a ponerse sobre la fila")
    IN_COMBAT = false
    FireEvent("PLAYER_REGEN_ENABLED")
    Enter(row)
    expect(h._shown and h.row == row and h:GetAttribute("item") == "item:12345", "al salir de combate el botón no vuelve a la fila")
  end)
  IN_COMBAT = false
  if not ok then error(err, 0) end
end, { state = "scan" })

test("la comprobación de rutas detecta un nivel que baja", function()
  local plan = PlanRoute("FirstAid", 1, 75)
  expect(#plan.steps >= 2, "la ruta de prueba tiene pocos pasos")
  plan.steps[2].from = plan.steps[1].from - 1
  expect(#RouteProblems("FirstAid", plan, 1, 75) > 0, "no lo detectó")
end)

-- La ordenación final del GPS puntuaba las dos rutas en cada comparación (~40.000 con
-- Ingeniería 1-300) y una ordenación no puede ceder el fotograma: el juego se paraba
-- casi medio segundo (PR #8). Cada ruta se puntúa una vez
test("ordenar las rutas guardadas: cada una se puntúa una vez", function()
  local P = ES.Planner
  local scores, score = 0, P.RouteScore
  P.RouteScore = function(...) scores = scores + 1 return score(...) end
  local sort, worst, size = table.sort, 0, 0
  table.sort = function(t, cmp)
    local before = scores
    sort(t, cmp)
    if scores - before > worst then worst, size = scores - before, #t end
  end
  local ok, err = pcall(PlanRoute, "Cooking", 1, 300)
  table.sort, P.RouteScore = sort, score
  if not ok then error(err, 0) end
  expect(size > 1, "ninguna ordenación puntuó rutas: la prueba no prueba nada")
  note("la ordenación que más puntúa: %d puntuaciones para %d rutas", worst, size)
  expect(worst <= size, "%d puntuaciones para ordenar %d rutas", worst, size)
end)

-- Las alternativas de cada paso se calculan poco a poco, y con la ventana cerrada o en
-- combate seguían gastando hasta 8 ms de cada fotograma (PR #8): ahora esperan
test("alternativas de cada paso: esperan en combate y con la ventana cerrada", function()
  local page, plan = PageRoute("Tailoring", 1, 75)
  RunTimers()
  expect(plan.alts, "la ruta no calcula sus alternativas: la prueba no prueba nada")
  -- En combate
  plan.alts, plan.altsRunning = nil, nil
  IN_COMBAT = true
  ES:ComputeAlternatives(page, plan)
  RunTimers(5)
  expect(not plan.alts, "en combate se calcularon las alternativas")
  IN_COMBAT = false
  RunTimers(5)
  expect(plan.alts, "al salir del combate no se acabaron las alternativas")
  -- Con la ventana cerrada
  plan.alts, plan.altsRunning = nil, nil
  ES:HideMainFrame()
  ES:ComputeAlternatives(page, plan)
  RunTimers(5)
  expect(not plan.alts, "con la ventana cerrada se calcularon las alternativas")
  ES:GetMainFrame():Show()
  RunTimers(5)
  expect(page.plan ~= plan or plan.alts, "al abrir la ventana no se acabaron las alternativas")
end, { state = "scan" })

-- La ruta depende de la AH: la de otro ruleset (otro modo de juego, Keys.lua) no vale
-- aunque tenga el mismo escaneo
test("ruta guardada: no se reutiliza en otro ruleset", function()
  local _, plan, cap = PageRoute("Tailoring", 50, 75)
  local saved = expect(ES.db.prof.Tailoring.lastRoute, "no se guardó la ruta")
  local function Reused()
    Reload()
    ES.db.prof.Tailoring.lastRoute = saved
    return ES:CachedPlan("Tailoring", plan.from, plan.to, cap) ~= nil
  end
  expect(Reused(), "sin cambios no se reutiliza")
  ES.db.scans["gm15-Alliance"] = ES.db.scans[ES:RealmKey()] -- (el mismo escaneo en las dos AH)
  SetGameMode(15)
  RunTimers()
  expect(not Reused(), "la ruta del ruleset 14 se reutiliza en el 15")
  SetGameMode(14)
  RunTimers()
  expect(Reused(), "de vuelta en el 14 no se reutiliza")
end, { state = "scan" })