-- Marco de las pruebas por categoría (tools/run_tests.py). Se carga después del
-- addon. Cada prueba corre con el addon recién cargado: el lanzador crea un Lua
-- nuevo por prueba, carga este archivo, los datos de prueba y la categoría, y
-- ejecuta solo esa prueba.
--
--   test("nombre", function() ... end)                 -- empieza con el estado "scan"
--   test("nombre", fn, { state = "empty" | "scan" | "full" })
--   test("nombre", fn, { boot = false })              -- la prueba llama a Boot(db) ella misma
--   test("nombre", fn, { known = "motivo" })          -- fallo conocido: no hace fallar el comando
--
--   expect(cond, "mensaje %s", ...)   expect_eq(sale, esperado, "qué")
--   expect_near(sale, esperado, margen, "qué")   no_error(fn, ...)   note("detalle %d", n)
--   snapshot("clave", valor)          -- compara con tools/tests/snapshots/<categoría>.json

TESTS = {}
NOTES = {}
SNAPSHOTS = {}
RECORDED_ERRORS = {}

function test(name, fn, opts)
  assert(type(name) == "string" and type(fn) == "function", "test(nombre, función)")
  TESTS[#TESTS + 1] = { name = name, fn = fn, opts = opts or {} }
end

local function fmt(msg, ...)
  if select("#", ...) > 0 then return string.format(msg, ...) end
  return tostring(msg)
end

function note(msg, ...) NOTES[#NOTES + 1] = fmt(msg, ...) end

function expect(cond, msg, ...)
  if not cond then error(fmt(msg or "no se cumple", ...), 2) end
  return cond
end

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function expect_eq(got, want, what)
  if got ~= want then
    error(string.format("%s: esperado %s, sale %s", what or "valor", show(want), show(got)), 2)
  end
end

function expect_near(got, want, tol, what)
  if type(got) ~= "number" or math.abs(got - want) > (tol or 0) then
    error(string.format("%s: esperado %s (±%s), sale %s", what or "valor", show(want), tostring(tol or 0), show(got)), 2)
  end
end

-- Número normal (ni nil, ni NaN, ni infinito)
function expect_finite(x, what)
  if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
    error(string.format("%s: no es un número normal (%s)", what or "valor", show(x)), 2)
  end
end

function no_error(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then error(err, 2) end
end

function snapshot(key, value)
  SNAPSHOTS[#SNAPSHOTS + 1] = { key = key, value = value }
end

-- Presupuesto: `value` (pasadas, segundos...) no puede pasar de la referencia guardada
-- en tools/tests/snapshots/<categoría>.json más un `tolerance` (0.2 = +20%) y un
-- `slack` fijo. Más bajo no falla (se avisa de que se puede actualizar la referencia).
-- La referencia se guarda o se pone al día con --update-snapshots
function budget(key, value, tolerance, slack)
  SNAPSHOTS[#SNAPSHOTS + 1] = { key = key, value = value, kind = "budget", tolerance = tolerance or 0.2, slack = slack or 0 }
end

-- Arranque: lo guardado (una tabla, o el nombre de un estado de Fixtures) y los
-- eventos de inicio, como el juego al entrar
function Boot(db)
  local stateName
  if type(db) == "string" then stateName, db = db, Fixtures.State(db) end
  -- Los errores que el addon se traga y apunta (ES:RecordError) también son fallos
  if not ES._recordWrapped then
    ES._recordWrapped = true
    local orig = ES.RecordError
    ES.RecordError = function(self, kind, msg, stack)
      RECORDED_ERRORS[#RECORDED_ERRORS + 1] = tostring(kind) .. ": " .. tostring(msg)
      return orig(self, kind, msg, stack)
    end
  end
  CraftersJournalDB = db
  FireEvent("ADDON_LOADED", "CraftersJournal")
  FireEvent("PLAYER_LOGIN")
  FireEvent("PLAYER_ENTERING_WORLD")
  if stateName then Fixtures.After(stateName) end
  RunTimers()
  return ES.db
end

-- Ayudas para la interfaz ----------------------------------------------------
-- Las pestañas de la ventana, y la página que abre cada una
TAB_PAGES = { home = "home", shopping = "shopping", money = "money", inventory = "inventory",
  invest = "invest", favor = "favor", calc = "calc", patterns = "patterns" }

function OpenMain()
  ES:ShowMainFrame()
  RunTimers()
  return ES:GetMainFrame()
end

-- La página de una profesión (ES.professionPages) por su clave ("Leatherworking")
function ProfessionPage(profKey)
  for _, p in ipairs(ES.professionPages or {}) do if p.profKey == profKey then return p end end
end

-- Empieza la ruta de una profesión (como el botón de la página): nivel actual `from`,
-- objetivo `to`. Devuelve la página y la ruta fijada
function StartRoute(profKey, from, to)
  SKILLS[ES.Data[profKey].skillLine] = { from, math.max(to, 75) }
  OpenPage(profKey)
  local page = ProfessionPage(profKey)
  page.toBox._text = tostring(to)
  if page.toBox._scripts.OnEnterPressed then page.toBox._scripts.OnEnterPressed(page.toBox) end
  RunTimers()
  expect(page.plan and #page.plan.steps > 0, "%s: la página no tiene ruta que empezar", profKey)
  ES:StartRoute(page)
  RunTimers()
  expect(ES:RouteLock(profKey), "%s: la ruta no se fijó", profKey)
  return page, ES:LockedPlan(profKey)
end

-- Ruta de una profesión sin la interfaz (lo que calcula la página)
function PlanRoute(profKey, from, to)
  local opts = ES:PlanOptions(profKey, from, to)
  return ES.Planner:Plan(ES.Data[profKey], opts)
end

-- Abre una página (por su clave: "home", "lw", "money"...) y vacía los temporizadores
function OpenPage(key)
  OpenMain()
  ES:SelectPage(key)
  RunTimers()
end

-- Claves de las 8 profesiones, en el orden de ES.PROFESSIONS
function ProfessionKeys()
  local t = {}
  for _, p in ipairs(ES.PROFESSIONS) do t[#t + 1] = p.key end
  return t
end

-- Todo el texto que hay en los marcos creados (para buscar lo que se pinta)
function AllText()
  local seen, out = {}, {}
  local function walk(t, depth)
    if type(t) ~= "table" or seen[t] or depth > 12 then return end
    seen[t] = true
    local s = rawget(t, "_text")
    if s then out[#out + 1] = s end
    for k, v in pairs(t) do
      if type(v) == "table" and k ~= "_parent" then walk(v, depth + 1) end
    end
  end
  walk(ES, 0)
  return table.concat(out, "\n")
end

function ResetTooltip() for i = #TOOLTIP, 1, -1 do TOOLTIP[i] = nil end end
