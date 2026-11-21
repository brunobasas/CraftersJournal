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

-- Spec recipe-requirements. CurseForge: "filter and not include recipes that require a
-- specialization, like Tribal Leatherworking" (Frostsaber Boots en la ruta de Peletería)
test("sin especialización, ninguna ruta 1-300 usa recetas de especialización", function()
  -- (además de las que llevan `spec`, las dos que se colaban antes, por si la pierden)
  local KNOWN = { [19066] = "Tribal", [16978] = "Swordsmith" } -- Frostsaber Boots, Blazing Rapier
  local bad = {}
  for _, prof in ipairs(ProfessionKeys()) do
    local plan = PlanRoute(prof, 1, 300)
    for i, s in ipairs(plan.steps) do
      local r = ES.Data[prof].recipes[s.id]
      local spec = r and (r.spec or KNOWN[s.id])
      if spec then
        bad[#bad + 1] = string.format("%s paso %d %d-%d: %s (pide %s)", prof, i, s.from, s.to, r.nameEN or r.name, spec)
      end
    end
  end
  expect(#bad == 0, "%d pasos con recetas de especialización:\n    %s", #bad, table.concat(bad, "\n    "))
end)

test("con una especialización, solo se aprenden sus recetas", function()
  local LW, BS = ES.Data.Leatherworking, ES.Data.Blacksmithing
  ES.Planner.Annotate(LW)
  ES.Planner.Annotate(BS)
  local boots, volcanic, rapier = LW.recipes[19066], LW.recipes[19059], BS.recipes[16978]
  expect(boots and volcanic and rapier, "faltan Frostsaber Boots, Volcanic Leggings o Blazing Rapier en los datos")
  local opts = { includeScrolls = true }
  expect(ES.Planner.LearnSkill(boots, opts) == nil, "sin Tribal se puede aprender Frostsaber Boots")
  KNOWN_SPELLS[10660] = true -- Tribal Leatherworking
  expect(ES.Planner.LearnSkill(boots, opts), "con Tribal no se puede aprender Frostsaber Boots")
  expect(ES.Planner.LearnSkill(volcanic, opts) == nil, "con Tribal se puede aprender Volcanic Leggings (Elemental)")
  KNOWN_SPELLS[9787] = true -- Weaponsmith, sin Master Swordsmith
  expect(ES.Planner.LearnSkill(rapier, opts) == nil, "con Weaponsmith pero sin Master Swordsmith se puede aprender Blazing Rapier")
  KNOWN_SPELLS[17039] = true -- Master Swordsmith
  expect(ES.Planner.LearnSkill(rapier, opts), "con Master Swordsmith no se puede aprender Blazing Rapier")
end)

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
  -- Especializaciones (spec recipe-requirements: aprender Tribal cambia qué recetas sirven)
  KNOWN_SPELLS[10660] = true
  expect(K("Leatherworking") ~= lw, "aprender Tribal Leatherworking no cambia la clave")
  KNOWN_SPELLS[10660] = nil
  expect_eq(K("Leatherworking"), lw, "sin Tribal otra vez")
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
  -- Especialización aprendida entre sesiones
  KNOWN_SPELLS[9788] = true -- Armorsmith
  expect(not Reused(), "se reutiliza tras aprender una especialización")
  KNOWN_SPELLS[9788] = nil
  expect(Reused(), "sin la especialización otra vez no se reutiliza")
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

-- Materiales con recetas de otras profesiones (spec route-reagent-sources) -----------
-- CurseForge: "I have 76 Mithril Ore that could be smelted, and it tells me to buy bars".
-- La ruta solo fabricaba con recetas de la profesión que se sube

local ORE, BAR, SMELT = 3858, 3860, 10097 -- Mithril Ore, Mithril Bar, Smelt Mithril
local THORIUM_BAR, SMELT_THORIUM = 12359, 16153

-- Precio de un objeto en el escaneo de las pruebas (`qty` a la venta a ese precio)
local function SetPrice(itemID, unit, qty)
  qty = qty or 5000
  ES.db.scans[ES:RealmKey()].items[itemID] = { listings = 4, quantity = qty, minUnit = unit, avgUnit = unit,
    sellers = 3, topShare = 0.4, median = unit, ladder = { unit, qty } }
end

-- Aprende (o deja de saber) recetas, como al volver del instructor
local function Know(ids, known)
  for _, id in ipairs(ids) do KNOWN_SPELLS[id] = known ~= false or nil end
  ES.CheckLearned()
end

-- Lo que hace falta para conseguir `qty` de un objeto en la ruta de `prof` (sus acciones)
local function AcquireActions(prof, itemID, qty, from, to)
  local opts = ES:PlanOptions(prof, from or 175, to or 225)
  local ctx = ES.Planner.NewContext(ES.Data[prof], opts)
  local cost, _, _, actions = ES.Planner.RecipeCost(ctx, { r = { { itemID, qty } } }, 1, {})
  return actions or {}, cost
end
local function Find(actions, kind, item)
  for _, a in ipairs(actions) do
    if a.kind == kind and a.item == item then return a end
  end
end
local function Qty(actions, kind, item)
  local n = 0
  for _, a in ipairs(actions) do
    if a.kind == kind and a.item == item then n = n + a.qty end
  end
  return n
end

local function Shopping(plan, itemID)
  for _, it in ipairs(plan.shopping or {}) do if it.itemID == itemID then return it end end
end
local function Crafted(plan, itemID)
  for _, c in ipairs(plan.crafted or {}) do if c.itemID == itemID then return c end end
end

test("recetas de otras profesiones: con Smelt Mithril, Herrería puede fundir Mithril Bar; sin ella, no", function()
  local idx = ES:ForeignProducers("Blacksmithing")
  expect(not idx.producers[BAR], "sin saber Smelt Mithril ya está en el índice")
  expect_eq(idx.stamp, "", "firma sin recetas de otras profesiones")
  Know({ SMELT })
  idx = ES:ForeignProducers("Blacksmithing")
  local list = expect(idx.producers[BAR], "con Smelt Mithril, Mithril Bar no está en el índice de Herrería")
  expect_eq(list[1], SMELT, "receta que fabrica Mithril Bar")
  expect_eq(idx.prof[SMELT], "Mining", "profesión de Smelt Mithril")
  expect_eq(idx.stamp, tostring(SMELT), "firma")
  -- (Sastrería no usa Mithril Bar: su índice no la tiene ni cambia su firma)
  expect_eq(ES:ForeignProducers("Tailoring").stamp, "", "firma de Sastrería")
end, { state = "scan" })

test("un minero que sube Herrería funde el mineral y la compra pide mineral", function()
  SetPrice(ORE, 300)
  SetPrice(BAR, 1210)
  Know({ SMELT })
  local actions = AcquireActions("Blacksmithing", BAR, 40)
  local craft = expect(Find(actions, "craft", BAR), "no funde las Mithril Bar")
  expect_eq(craft.recipe, SMELT, "receta")
  expect_eq(craft.prof, "Mining", "profesión de la receta")
  expect_eq(Qty(actions, "ah", ORE), 40, "Mithril Ore comprado")
  expect_eq(Qty(actions, "ah", BAR), 0, "Mithril Bar comprado")
  -- La ruta entera: funde, la compra pide mineral y los pasos son de Herrería
  local plan = PlanRoute("Blacksmithing", 175, 225)
  local c = expect(Crafted(plan, BAR), "la ruta de Herrería 175-225 no funde Mithril Bar")
  expect_eq(c.prof, "Mining", "profesión de la fila de fundir")
  expect_eq(c.recipe and c.recipe.id, SMELT, "receta de la fila de fundir")
  expect(Shopping(plan, ORE), "la compra no pide Mithril Ore")
  expect(not Shopping(plan, BAR), "la compra pide Mithril Bar")
  local bad = RouteProblems("Blacksmithing", plan, 175, 225)
  expect(#bad == 0, "ruta:\n    %s", table.concat(bad, "\n    "))
  note("funde %d Mithril Bar; compra %d Mithril Ore", c.quantity, Shopping(plan, ORE).quantity)
end, { state = "scan" })

test("sin Minería, la ruta de Herrería compra las barras", function()
  SetPrice(ORE, 300)
  SetPrice(BAR, 1210)
  local actions = AcquireActions("Blacksmithing", BAR, 40)
  expect(not Find(actions, "craft", BAR), "funde sin saber Smelt Mithril")
  expect_eq(Qty(actions, "ah", BAR), 40, "Mithril Bar comprado")
  local plan = PlanRoute("Blacksmithing", 175, 225)
  for _, c in ipairs(plan.crafted) do
    expect(not c.prof, "fabrica %s con otra profesión (%s)", tostring(c.itemID), tostring(c.prof))
  end
  expect(not Shopping(plan, ORE), "la compra pide Mithril Ore")
  for id in pairs(plan.prepLearn or {}) do expect(not ES.Data.Mining.recipes[id], "propone aprender %d de Minería", id) end
end, { state = "scan" })

test("si la barra sale más barata que el mineral, la compra hecha", function()
  SetPrice(ORE, 1300)
  SetPrice(BAR, 1210)
  Know({ SMELT })
  local actions = AcquireActions("Blacksmithing", BAR, 40)
  expect(not Find(actions, "craft", BAR), "funde aunque la barra sale más barata")
  expect_eq(Qty(actions, "ah", BAR), 40, "Mithril Bar comprado")
  -- (y si ahorra menos de lo que se pide a un intermedio por fabricación, tampoco)
  SetPrice(ORE, 1208)
  expect(not Find(AcquireActions("Blacksmithing", BAR, 40), "craft", BAR), "funde por 2 cobres de ahorro por barra")
end, { state = "scan" })

test("un minero que no sabe Smelt Thorium compra Thorium Bar", function()
  SetPrice(10620, 100) -- Thorium Ore, muy barato
  SetPrice(ORE, 300)
  Know({ SMELT })
  local actions = AcquireActions("Blacksmithing", THORIUM_BAR, 20, 250, 300)
  expect(not Find(actions, "craft", THORIUM_BAR), "funde Thorium sin saber Smelt Thorium")
  expect_eq(Qty(actions, "ah", THORIUM_BAR), 20, "Thorium Bar comprado")
  Know({ SMELT_THORIUM })
  expect(Find(AcquireActions("Blacksmithing", THORIUM_BAR, 20, 250, 300), "craft", THORIUM_BAR), "sabiendo Smelt Thorium no funde")
end, { state = "scan" })

test("un peletero que sube Ingeniería hace el Heavy Leather con su receta de Peletería", function()
  local HEAVY = 4234
  local rid
  for id, r in pairs(ES.Data.Leatherworking.recipes) do
    if r.out and r.out[1] == HEAVY and not r.conversion and (not rid or id < rid) then rid = id end
  end
  expect(rid, "no hay receta de Heavy Leather en Peletería")
  local uses = false
  for _, r in pairs(ES.Data.Engineering.recipes) do
    for _, rq in ipairs(r.r) do if rq[1] == HEAVY then uses = true end end
  end
  expect(uses, "Ingeniería no usa Heavy Leather: la prueba no prueba nada")
  SKILLS[ES.Data.Leatherworking.skillLine] = { 150, 225 }
  SetPrice(HEAVY, 5000)
  for _, rq in ipairs(ES.Data.Leatherworking.recipes[rid].r) do SetPrice(rq[1], 20) end
  local actions = AcquireActions("Engineering", HEAVY, 10)
  expect(not Find(actions, "craft", HEAVY), "fabrica Heavy Leather sin saber la receta")
  Know({ rid })
  actions = AcquireActions("Engineering", HEAVY, 10)
  local craft = expect(Find(actions, "craft", HEAVY), "sabiendo la receta de Peletería no fabrica Heavy Leather")
  expect_eq(craft.prof, "Leatherworking", "profesión de la receta")
end, { state = "scan" })

test("Transmute: Arcanite no se usa si Arcanite Bar está en la AH", function()
  local ARCANITE, TRANSMUTE = 12360, 17187
  expect(ES.Data.Alchemy.recipes[TRANSMUTE], "no está Transmute: Arcanite en los datos")
  SKILLS[ES.Data.Alchemy.skillLine] = { 275, 300 }
  SetPrice(ARCANITE, 90000)
  for _, rq in ipairs(ES.Data.Alchemy.recipes[TRANSMUTE].r) do SetPrice(rq[1], 10) end
  Know({ TRANSMUTE })
  expect(ES:ForeignProducers("Blacksmithing").producers[ARCANITE], "Transmute: Arcanite no está en el índice: la prueba no prueba nada")
  local actions = AcquireActions("Blacksmithing", ARCANITE, 5, 275, 300)
  expect(not Find(actions, "craft", ARCANITE), "transmuta aunque Arcanite Bar está en la AH")
  expect_eq(Qty(actions, "ah", ARCANITE), 5, "Arcanite Bar comprado")
end, { state = "scan" })

test("con «usar lo de las bolsas», cuentan las barras y el mineral que llevas", function()
  SetPrice(ORE, 300)
  SetPrice(BAR, 1210)
  Know({ SMELT })
  ES.db.prof = ES.db.prof or {}
  ES.db.prof.Blacksmithing = { useBags = true }
  BAGS[BAR] = 17
  local only = AcquireActions("Blacksmithing", BAR, 312)
  expect_eq(Qty(only, "owned", BAR), 17, "barras de las bolsas")
  BAGS[ORE] = 76
  expect_eq(ES:PlanOptions("Blacksmithing", 175, 225).owned[ORE], 76, "mineral de las bolsas en la ruta")
  local both = AcquireActions("Blacksmithing", BAR, 312)
  expect_eq(Qty(both, "owned", BAR), 17, "barras de las bolsas")
  expect_eq(Qty(both, "owned", ORE), 76, "mineral de las bolsas")
  expect_eq(Qty(both, "ah", ORE) + Qty(both, "ah", BAR), 312 - 17 - 76, "lo que se compra")
  expect_eq(Qty(only, "ah", ORE) - Qty(both, "ah", ORE), 76, "mineral comprado de menos con el de las bolsas")
  -- Y la ruta tiene el mineral entre sus objetos (su cambio la invalida)
  local plan = PlanRoute("Blacksmithing", 175, 225)
  expect(Crafted(plan, BAR), "la ruta no funde: la prueba no prueba nada")
  expect(ES.RouteItems(plan)[ORE], "Mithril Ore no está entre los objetos de la ruta")
end, { state = "scan" })

test("clave estable: aprender Smelt Thorium cambia la de Herrería y no la de Sastrería", function()
  SKILLS[ES.Data.Blacksmithing.skillLine] = { 250, 300 }
  local function K(prof) return ES:StableRouteKey(prof, 250, 300, 300) end
  local bs, tail = K("Blacksmithing"), K("Tailoring")
  ES:InvalidatePlan("Tailoring")
  local tailGen = ES.planGens.Tailoring
  Know({ SMELT_THORIUM })
  expect(K("Blacksmithing") ~= bs, "aprender Smelt Thorium no cambia la clave de Herrería")
  expect_eq(K("Tailoring"), tail, "clave de Sastrería")
  expect_eq(ES.planGens.Tailoring, tailGen, "aprender Smelt Thorium rehace la ruta de Sastrería")
  -- Entre sesiones: la guardada no se reutiliza
  Know({ SMELT_THORIUM }, false)
  expect_eq(K("Blacksmithing"), bs, "sin Smelt Thorium otra vez")
end, { state = "scan" })

test("ruta que funde: minar más mineral la invalida y la guardada se rehace con las mismas filas", function()
  SetPrice(ORE, 300)
  SetPrice(BAR, 1210)
  Know({ SMELT })
  ES.db.prof = ES.db.prof or {}
  ES.db.prof.Blacksmithing = { useBags = true }
  BAGS[ORE] = 20
  local _, plan, cap = PageRoute("Blacksmithing", 175, 225)
  local c = expect(Crafted(plan, BAR), "la ruta de la página no funde: la prueba no prueba nada")
  local saved = expect(ES.db.prof.Blacksmithing.lastRoute, "no se guardó la ruta")
  expect_eq(saved.bags and saved.bags[ORE], 20, "mineral apuntado con la ruta")
  -- Rehecha tras recargar: las mismas filas de fundir
  Reload()
  local again = expect(ES:CachedPlan("Blacksmithing", plan.from, plan.to, cap), "tras recargar no se usa la ruta guardada")
  local c2 = expect(Crafted(again, BAR), "rehecha, la ruta no funde")
  expect_eq(c2.quantity, c.quantity, "barras que funde la ruta rehecha")
  expect_eq(c2.prof, "Mining", "profesión de la fila rehecha")
  -- Minar más mineral: ya no vale
  BAGS[ORE] = 35
  expect(not ES.RouteBagsMatch(saved.bags), "con más mineral la ruta sigue valiendo")
  Reload()
  expect(ES:CachedPlan("Blacksmithing", plan.from, plan.to, cap) == nil, "con más mineral se reutiliza la ruta guardada")
end, { state = "scan" })

-- Lo que cuesta calcular la ruta de un minero que sube Herrería sabiendo todas las
-- fundiciones, con todos los minerales en la AH (como las rutas de 1 a 300)
test("ruta de 1 a 300: Blacksmithing de un minero", function()
  local scan = ES.db.scans[ES:RealmKey()]
  local ids = {}
  for id, r in pairs(ES.Data.Mining.recipes) do
    ids[#ids + 1] = id
    for _, rq in ipairs(r.r) do
      if not scan.items[rq[1]] then SetPrice(rq[1], Fixtures.Price(rq[1]), 20 + (rq[1] % 7) * 10) end
    end
  end
  Know(ids)
  expect(next(ES:ForeignProducers("Blacksmithing").producers), "Herrería sin recetas de Minería: la prueba no prueba nada")
  local ticks = 0
  local passes0, cpu0 = ES.Planner.passes, os.clock()
  debug.sethook(function() ticks = ticks + 1 end, "", 1000)
  local ok, plan = pcall(PlanRoute, "Blacksmithing", 1, 300)
  debug.sethook()
  if not ok then error(plan, 0) end
  local passes, cpu = ES.Planner.passes - passes0, os.clock() - cpu0
  budget("pasadas 1-300 Blacksmithing de un minero", passes, 0.15, 5)
  budget("millones de instrucciones 1-300 Blacksmithing de un minero", math.floor(ticks / 100 + 0.5) / 10, 0.15, 2)
  note("%.1f s de CPU (solo informativo)", cpu)
  local bad = RouteProblems("Blacksmithing", plan, 1, 300)
  expect(#bad == 0, "ruta:\n    %s", table.concat(bad, "\n    "))
  local smelts = {}
  for _, c in ipairs(plan.crafted) do
    if c.prof then smelts[#smelts + 1] = string.format("%d× %s", c.quantity, ES:DataItemName(c.itemID) or c.itemID) end
  end
  table.sort(smelts)
  expect(#smelts > 0, "la ruta de un minero no funde nada")
  note("%d pasos, total %.0f cobre; funde %s", #plan.steps, plan.net, table.concat(smelts, ", "))
end, { state = "scan" })

-- La fila de fundir en la vista Ruta (y en el asistente, que usa las mismas filas)
local function SmeltLine(page)
  for _, l in ipairs(page.lines or {}) do
    if l.item == BAR and l.craftProf then return l end
  end
end

test("la fila de fundir dice que es con Minería, abre Smelt Mithril y su X hace comprar las barras", function()
  SetPrice(ORE, 300)
  SetPrice(BAR, 1210)
  Know({ SMELT })
  local page = PageRoute("Blacksmithing", 175, 225)
  local line = expect(SmeltLine(page), "no hay fila de fundir Mithril Bar en la vista Ruta")
  expect_eq(line.craftProf, "Mining", "profesión de la fila")
  expect(tostring(line.title):find(ES:ProfLabel("Mining"), 1, true), "la fila no dice que es con Minería: «%s»", tostring(line.title))
  -- Pasar el ratón y pulsarla, sin errores; el clic abre Smelt Mithril
  no_error(line.tooltip, CreateFrame("Frame"))
  local opened
  local open, craft = ES.OpenRecipe, ES.CraftRecipe
  ES.OpenRecipe = function(_, id) opened = id return true end
  ES.CraftRecipe = function(_, id) opened = id end
  BAGS[ORE] = 5
  expect_eq(ES.CraftableFromBags(SMELT), 5, "fundiciones que salen del mineral de las bolsas")
  no_error(line.onClick)
  ES.OpenRecipe, ES.CraftRecipe = open, craft
  expect_eq(opened, SMELT, "receta que abre el clic")
  -- El asistente lee las mismas filas (las de la ruta empezada)
  ES:StartRoute(page)
  RunTimers()
  local inAssistant
  for _, l in ipairs(ES:RouteLines("Blacksmithing") or {}) do
    if l.item == BAR and l.craftProf == "Mining" then inAssistant = l end
  end
  expect(inAssistant, "las filas del asistente no tienen la de fundir")
  expect(tostring(inAssistant.bannerTitle or inAssistant.title):find(ES:ProfLabel("Mining"), 1, true),
    "en el asistente la fila no dice que es con Minería")
  -- X: no fundir, comprar las barras
  line = expect(SmeltLine(page), "con la ruta empezada no hay fila de fundir")
  expect(line.onSkip, "la fila de fundir no tiene X")
  line.onSkip()
  RunTimers()
  expect(ES.db.prof.Blacksmithing.noCraft[BAR], "la X no apunta Mithril Bar en noCraft")
  local plan = expect(page.plan, "sin ruta tras la X")
  expect(not Crafted(plan, BAR), "tras la X la ruta sigue fundiendo")
  expect(not Shopping(plan, ORE), "tras la X la compra sigue pidiendo Mithril Ore")
  -- (sin fundir, la ruta puede dejar las recetas de Mithril: las que pidan barras, las compra)
  local actions = AcquireActions("Blacksmithing", BAR, 40)
  expect_eq(Qty(actions, "ah", BAR), 40, "tras la X, Mithril Bar comprado")
  expect(not Find(actions, "craft", BAR), "tras la X se sigue fundiendo")
end, { state = "scan" })

-- Lo que la ruta explica de sus cifras (spec route-explanations) ------------------
-- CurseForge: "is -11g after the vendor sale or only materials?", "why you suggest
-- something". Las cifras ya eran buenas; no se veía de dónde salían

-- Cobre de un texto con dinero (ES.Money: números con los iconos de oro, plata y cobre)
local function Copper(text)
  local n, found = 0, false
  for num, kind in tostring(text or ""):gmatch("(%d+)|TInterface\\MoneyFrame\\UI%-(%a+)Icon") do
    found = true
    n = n + tonumber(num) * (kind == "Gold" and 10000 or kind == "Silver" and 100 or 1)
  end
  return found and n or nil
end

-- Las líneas de un tooltip: AddLine tal cual y AddDoubleLine como "izquierda | derecha"
local function TooltipLines(fn, ...)
  local lines = {}
  local add, add2 = GameTooltip.AddLine, GameTooltip.AddDoubleLine
  GameTooltip.AddLine = function(_, t) lines[#lines + 1] = tostring(t) end
  GameTooltip.AddDoubleLine = function(_, a, b) lines[#lines + 1] = tostring(a) .. " | " .. tostring(b) end
  local ok, err = pcall(fn, ...)
  GameTooltip.AddLine, GameTooltip.AddDoubleLine = add, add2
  if not ok then error(err, 0) end
  return lines
end
local function LineStarting(lines, prefix)
  for _, l in ipairs(lines) do
    if l:sub(1, #prefix) == prefix then return l end
  end
end
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Las filas de los pasos de la vista Ruta, cada una con su paso: { { line, st } }
local function StepRows(page, plan)
  local out, k = {}, 0
  for _, l in ipairs(page.lines or {}) do
    if l.stepRecipe and tostring(l.level):find("–", 1, true) then
      k = k + 1
      out[#out + 1] = { line = l, st = plan.steps[k] }
    end
  end
  return out
end

-- El neto por fabricación que dice la línea de debajo de un paso (negativo si "ganas")
local function RowNet(sub)
  sub = Plain(sub)
  for _, key in ipairs({ "neto %s", "ganas %s" }) do
    local prefix = ES.L[key]:gsub("%%s.*$", "")
    local i = sub:find(prefix, 1, true)
    if i then
      local money = Copper(sub:sub(i + #prefix):match("^(.-)/") or "")
      if money then return key == "ganas %s" and -money or money end
    end
  end
end

test("la fila de cada paso dice su neto por fabricación, el que da la cifra de la fila", function()
  local page, plan = PageRoute("Tailoring", 50, 75)
  local rows = StepRows(page, plan)
  expect(#rows > 0 and rows[1].st, "no hay filas de pasos")
  local withSale = false
  for i, x in ipairs(rows) do
    local st, l = x.st, x.line
    if not l.done then
      local net = expect(RowNet(l.sub), "paso %d: la línea de debajo no dice el neto: «%s»", i, Plain(l.sub))
      expect_near(net, st.unitCost - st.unitValue, 1, "paso " .. i .. ": neto por fabricación")
      -- (la cifra de la fila: el neto por las fabricaciones del paso)
      local value = (Copper(l.value) or 0) * (Plain(l.value):find("^%+") and -1 or 1)
      expect_near(net * st.crafts, value, st.crafts + 1, "paso " .. i .. ": neto × fabricaciones frente a la cifra de la fila")
      -- (con venta, el neto no es el coste de los materiales: así se ve que no enseña ese)
      if st.unitValue >= 2 then withSale = true end
    end
  end
  expect(withSale, "ningún paso recupera nada vendiéndolo: la prueba no prueba lo del neto")
end, { state = "scan" })

test("el tooltip de un paso acaba con su cuenta: materiales, lo que se recupera y el neto", function()
  local page, plan = PageRoute("Tailoring", 50, 75)
  local x = expect(StepRows(page, plan)[1], "no hay filas de pasos")
  local lines = TooltipLines(x.line.tooltip, CreateFrame("Frame"))
  local mats = expect(LineStarting(lines, ES.L["Materiales"] .. " | "), "el tooltip no dice los materiales del paso")
  local back = expect(LineStarting(lines, ES.L["Se recupera vendiéndolo"] .. " | ") or LineStarting(lines, ES.L["Se recupera (vendido o guardado)"] .. " | "),
    "el tooltip no dice lo que se recupera")
  local net = expect(LineStarting(lines, ES.L["Neto"] .. " | ") or LineStarting(lines, ES.L["Ganas"] .. " | "), "el tooltip no dice el neto")
  local st = x.st
  expect_near(Copper(mats), st.crafts * st.unitCost, 1, "materiales del paso")
  expect_near(Copper(back), st.crafts * st.unitValue, 1, "lo que se recupera")
  expect_near(Copper(net), math.abs(st.total - st.fee), 1, "neto del paso")
  expect_near(Copper(net), Copper(x.line.value) or 0, 1, "el neto del tooltip y la cifra de la fila")
  note("%s · %s · %s", Plain(mats), Plain(back), Plain(net))
end, { state = "scan" })

test("el tooltip de un paso que guarda parte de lo que fabrica lo dice en lo que se recupera", function()
  local found
  for _, case in ipairs({ { "Tailoring", 1, 75 }, { "Tailoring", 75, 150 }, { "Leatherworking", 1, 75 }, { "Blacksmithing", 1, 75 } }) do
    local page, plan = PageRoute(case[1], case[2], case[3])
    for _, x in ipairs(StepRows(page, plan)) do
      local r = x.st and x.st.recipe
      if r and r.out and (plan.keptByItem[r.out[1]] or 0) > 0 then found = x break end
    end
    if found then break end
  end
  expect(found, "ninguna ruta de prueba guarda lo que fabrica un paso: la prueba no prueba nada")
  local lines = TooltipLines(found.line.tooltip, CreateFrame("Frame"))
  expect(LineStarting(lines, ES.L["Se recupera (vendido o guardado)"] .. " | "),
    "el tooltip de un paso que guarda lo que fabrica no dice «vendido o guardado»")
end, { state = "scan" })

-- El neto como lo escribe la ruta ("neto 46s" / "ganas 12s"), sin colores
local function NetLabel(net)
  if net <= -0.5 then return Plain(string.format(ES.L["ganas %s"], ES.Money(-net))) end
  return Plain(string.format(ES.L["neto %s"], ES.Money(math.max(0, net))))
end

test("cada alternativa dice cuánto más cuesta en total, con su neto y fabricaciones frente a los del paso", function()
  local page, plan = PageRoute("Tailoring", 50, 75)
  RunTimers(10)
  expect(plan.alts, "la ruta no calculó sus alternativas")
  local rows, checked = StepRows(page, plan), 0
  for i, x in ipairs(rows) do
    local list = plan.alts[i]
    if list and #list > 0 and not x.line.done then
      local lines = TooltipLines(x.line.tooltip, CreateFrame("Frame"))
      local st = x.st
      for n = 1, math.min(3, #list) do
        local alt = list[n]
        local r = ES.Data.Tailoring.recipes[alt.id]
        local head = expect(LineStarting(lines, string.format("%d. %s | ", n + 1, r.name)), "paso %d: no está la alternativa %s", i, r.name)
        if math.abs(alt.delta) >= 0.5 then
          local prefix = Plain(alt.delta > 0 and ES.L["+%s en total"] or ES.L["-%s en total"]):gsub("%%s.*$", "")
          expect(Plain(head):find(" | " .. prefix, 1, true), "paso %d, %s: la cifra no dice «en total»: «%s»", i, r.name, Plain(head))
          expect_near(Copper(head), math.abs(alt.delta), 1, "paso " .. i .. ", " .. r.name .. ": cifra de la alternativa")
        end
        -- La línea de debajo: su neto por fabricación y el del paso, y las fabricaciones
        local below
        for k, l in ipairs(lines) do if l == head then below = Plain(lines[k + 1]) end end
        local a = alt.step
        expect(below and below:find(NetLabel(a.unitCost - a.unitValue), 1, true), "paso %d, %s: sin su neto: «%s»", i, r.name, tostring(below))
        expect(below:find(NetLabel(st.unitCost - st.unitValue), 1, true), "paso %d, %s: sin el neto del paso: «%s»", i, r.name, below)
        expect(below:find(tostring(math.floor(a.crafts + 0.5)), 1, true), "paso %d, %s: sin sus fabricaciones: «%s»", i, r.name, below)
        checked = checked + 1
      end
    end
  end
  expect(checked > 0, "ningún paso con alternativas: la prueba no prueba nada")
  note("%d alternativas comprobadas", checked)
end, { state = "scan" })

local function Hover(frame)
  local fn = expect(frame and frame._scripts and frame._scripts.OnEnter, "el marco no tiene tooltip")
  return TooltipLines(fn, frame)
end

-- Lo corto de cómo elige la ruta, tal como sale en la línea de estado
local HOW_SHORT = Plain(ES.L["Precios de la AH de hace %d min · busca el menor neto: materiales menos ventas al vendedor"]):match("· (.*)$")

-- En la línea de estado, no en una línea aparte: dos líneas diciendo casi lo mismo
-- dejaban la página cargada
test("la línea de estado dice cómo elige la ruta, y su tooltip da el texto entero", function()
  local page = PageRoute("Tailoring", 50, 75)
  local status = Plain(page.status:GetText())
  expect(status:find(HOW_SHORT, 1, true), "la línea de estado no dice cómo elige la ruta: «%s»", status)
  expect(page.howLine == nil, "sigue la línea aparte bajo las cifras")
  local lines = Hover(page.statusHover)
  expect(LineStarting(lines, ES.L["Cómo elige la ruta"]), "al pasar el ratón no sale «Cómo elige la ruta»")
  expect(#lines >= 2 and #lines[2] > #HOW_SHORT, "el tooltip no da el texto entero")
end, { state = "scan" })

test("sin escaneo, la línea de estado no explica cómo elige la ruta", function()
  OpenPage("Tailoring")
  RunTimers()
  local page = expect(ProfessionPage("Tailoring"), "no hay página de Sastrería")
  expect(not Plain(page.status:GetText()):find(HOW_SHORT, 1, true), "sin escaneo dice cómo elige la ruta")
  expect_eq(#Hover(page.statusHover), 0, "líneas del tooltip sin escaneo")
end, { state = "empty" })

test("el tooltip del Total da su cuenta: materiales menos ventas más instructor", function()
  local page, plan = PageRoute("Tailoring", 50, 75)
  local lines = Hover(page.totalHover)
  local mats = expect(LineStarting(lines, ES.L["Materiales"] .. " | "), "sin materiales")
  local sales = expect(LineStarting(lines, ES.L["Ventas al vendedor"] .. " | "), "sin ventas al vendedor")
  local fees = expect(LineStarting(lines, ES.L["Instructor y herramientas"] .. " | "), "sin instructor y herramientas")
  local total = expect(LineStarting(lines, ES.L["Total"] .. " | ") or LineStarting(lines, ES.L["Ganas"] .. " | "), "sin total")
  local sign = LineStarting(lines, ES.L["Ganas"] .. " | ") and -1 or 1
  expect_near((Copper(mats) or 0) - (Copper(sales) or 0) + (Copper(fees) or 0), sign * (Copper(total) or 0), 2, "materiales - ventas + instructor")
  expect_near(sign * (Copper(total) or 0), plan.net, 1, "total del tooltip y de la ruta")
  expect(LineStarting(lines, ES.L["Cómo elige la ruta"]), "el tooltip del Total no explica cómo elige la ruta")
  note("%s · %s · %s · %s", Plain(mats), Plain(sales), Plain(fees), Plain(total))
end, { state = "scan" })

-- El margen de la compra en los tooltips de Materiales y de las filas de compra del
-- asistente. Ruta de Sastrería 120-150 empezada con el modo `byPhase` (nil: por tramos)
local MARGIN_PREFIX = Plain(ES.L["De media hacen falta %d y se piden %d (%d de margen), por si los puntos tardan en subir. Si te sobran, sirven para el tramo siguiente."]):match("^(.-)%%d")
local function MarginTooltips(byPhase)
  ES.db.prof.Tailoring = ES.db.prof.Tailoring or {}
  ES.db.prof.Tailoring.byPhase = byPhase
  local page, plan = StartRoute("Tailoring", 120, 150)
  local need = ES.Planner.RouteNeed("Tailoring", plan, 120)
  local found, rows = {}, 0
  local function Scan(lines)
    for _, l in ipairs(lines or {}) do
      if l.tooltip and (l.buyRow or l.item) then
        rows = rows + 1
        for _, t in ipairs(TooltipLines(l.tooltip, CreateFrame("Frame"))) do
          local s = Plain(t)
          local i = s:find(MARGIN_PREFIX, 1, true)
          if i then
            local avg, ask, extra = s:sub(i):match("(%d+)%D+(%d+)%D+(%d+)")
            found[#found + 1] = { avg = tonumber(avg), ask = tonumber(ask), extra = tonumber(extra), text = s }
          end
        end
      end
    end
  end
  ES:SelectProfessionView(page, "shop")
  RunTimers()
  Scan(page.lines)
  Scan(ES:RouteLines("Tailoring", { buy = true }))
  return found, need, rows
end

test("compra por tramos: el tooltip explica el margen (de media, lo que se pide y la diferencia)", function()
  local found, need, rows = MarginTooltips(nil)
  expect(rows > 0, "no hay filas de compra: la prueba no prueba nada")
  expect(#found > 0, "ninguna fila de compra explica el margen")
  for _, f in ipairs(found) do
    expect_eq(f.ask - f.avg, f.extra, "margen de «" .. f.text .. "»")
    local ok = false
    for _, n in pairs(need) do
      if n.expected and n.need == f.ask and math.ceil(n.expected - 0.001) == f.avg then ok = true end
    end
    expect(ok, "«%s» no cuadra con lo que pide la compra del tramo", f.text)
  end
  note("%s", found[1].text)
end, { state = "scan" })

test("con ruta entera, la compra no habla de margen", function()
  local found, _, rows = MarginTooltips(false)
  expect(rows > 0, "no hay filas de compra: la prueba no prueba nada")
  expect_eq(#found, 0, "filas que hablan de margen con ruta entera")
end, { state = "scan" })

-- Recetas en enfriamiento (Discord: la ruta de Sastrería pedía Mooncloth con ella en
-- enfriamiento). Las que se sabe que no están listas no salen en la ruta; las listas
-- o sin saber, sí. Vale para todas las profesiones (Earn.OnCooldown)
test("una receta en enfriamiento no sale en la ruta (Mooncloth)", function()
  local MOONCLOTH, FELCLOTH, MOONCLOTH_ITEM = 18560, 14256, 14342
  local r = expect(ES.Data.Tailoring.recipes[MOONCLOTH], "no está Mooncloth en los datos")
  expect(ES.Planner.Cooldown(r, MOONCLOTH), "Mooncloth sin enfriamiento")
  SKILLS[ES.Data.Tailoring.skillLine] = { 233, 300 }
  -- (barata de hacer y cara de vender: lista, la ruta la elige para su punto)
  SetPrice(FELCLOTH, 1)
  SetPrice(MOONCLOTH_ITEM, 500000)
  Know({ MOONCLOTH })
  ES.Earn.ResetCooldownRecipes()
  local function UsesMooncloth(plan)
    for _, st in ipairs(plan.steps) do
      if st.recipe == r or (st.recipe and st.recipe.id == MOONCLOTH) then return true end
    end
    for _, id in pairs(plan.choice) do if id == MOONCLOTH then return true end end
    return false
  end
  local readyKey = ES:StableRouteKey("Tailoring", 233, 250, 300)
  expect(UsesMooncloth(PlanRoute("Tailoring", 233, 250)), "lista, la ruta no usa Mooncloth: la prueba no prueba nada")
  -- En enfriamiento (leído al abrir la profesión): fuera de la ruta y otra clave
  ES.charData.cdReady = { [MOONCLOTH] = time() + 3 * 86400 }
  local opts = ES:PlanOptions("Tailoring", 233, 250)
  expect(opts.excluded and opts.excluded[MOONCLOTH], "en enfriamiento, Mooncloth no está entre las excluidas")
  expect(not (ES.db.prof and ES.db.prof.Tailoring and ES.db.prof.Tailoring.excluded
    and ES.db.prof.Tailoring.excluded[MOONCLOTH]), "el enfriamiento se apuntó como receta quitada a mano")
  expect(ES:StableRouteKey("Tailoring", 233, 250, 300) ~= readyKey, "el enfriamiento no cambia la clave de la ruta")
  expect(not UsesMooncloth(PlanRoute("Tailoring", 233, 250)), "en enfriamiento, la ruta usa Mooncloth")
  -- Lista otra vez: vuelve
  NOW = NOW + 4 * 86400
  expect_eq(ES:StableRouteKey("Tailoring", 233, 250, 300), readyKey, "clave con el enfriamiento ya pasado")
  expect(UsesMooncloth(PlanRoute("Tailoring", 233, 250)), "lista otra vez, la ruta no usa Mooncloth")
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
