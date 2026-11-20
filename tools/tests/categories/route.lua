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

test("la comprobación de rutas detecta un nivel que baja", function()
  local plan = PlanRoute("FirstAid", 1, 75)
  expect(#plan.steps >= 2, "la ruta de prueba tiene pocos pasos")
  plan.steps[2].from = plan.steps[1].from - 1
  expect(#RouteProblems("FirstAid", plan, 1, 75) > 0, "no lo detectó")
end)
