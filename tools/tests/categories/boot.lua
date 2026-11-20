-- Arranque y eventos: el addon carga y abre su ventana con cualquier cosa guardada,
-- y ningún evento que registra da error

-- Abre la ventana y pasa por todas las pestañas (sin errores, es lo que se comprueba)
-- (oneProf: solo la página de una profesión; las 8 cuestan, con precios, varios segundos)
local function VisitAllTabs(oneProf)
  OpenMain()
  for _, key in ipairs({ "home", "shopping", "money", "inventory", "favor", "calc", "patterns" }) do
    ES:SelectPage(key)
    RunTimers()
  end
  for _, prof in ipairs(oneProf and { "Leatherworking" } or ProfessionKeys()) do
    ES:SelectPage(prof)
    RunTimers()
  end
end

test("sin nada guardado: carga y abre la ventana", function()
  expect(ES.db and type(ES.db.scans) == "table", "no creó lo guardado")
  OpenMain()
  expect(ES:GetMainFrame():IsShown(), "la ventana no se abrió")
  VisitAllTabs()
end, { state = "empty" })

test("con un escaneo: todas las pestañas se abren", function() VisitAllTabs() end, { state = "scan" })
test("con datos completos: todas las pestañas se abren", function() VisitAllTabs() end, { state = "full" })

test("los datos de prueba son siempre los mismos", function()
  local function Same(a, b, path)
    if type(a) ~= type(b) then error(path .. ": " .. type(a) .. " / " .. type(b)) end
    if type(a) ~= "table" then
      if a ~= b then error(path .. ": " .. tostring(a) .. " / " .. tostring(b)) end
      return
    end
    for k, v in pairs(a) do Same(v, b[k], path .. "." .. tostring(k)) end
    for k in pairs(b) do if a[k] == nil then error(path .. "." .. tostring(k) .. ": falta en la primera") end end
  end
  Same(Fixtures.State("full"), Fixtures.State("full"), "full")
  Same(Fixtures.State("scan"), Fixtures.State("scan"), "scan")
end, { boot = false })

-- Formatos antiguos que el addon sabe migrar -----------------------------------

test("formatos antiguos: se migran al cargar", function()
  local guid = UnitGUID("player")
  Boot({
    scans = {},
    minimap = { angle = 200 },                    -- (antes de LibDBIcon)
    chars = { ["Bruno-Realm"] = { prof = {} } },  -- (rutas por nombre, antes del GUID)
    charsMigrated = true,
    sellSeen = { [2318] = 10 }, sellSeenCleaned = true,
    mail = { x = 1 }, earnBudget = 100, activeAH = "Realm-Neutral", sellGear = true, useGPS = true,
    characters = { [guid] = {
      prof = { Leatherworking = { target = 225, useAH = false }, Tailoring = { target = 152 } },
      shopping = { { kind = "route", key = "Leatherworking", title = "vieja", items = {} },
                   { kind = "money", title = "mía", items = { { itemID = 2318, need = 5, unit = 25, source = "ah" } } } },
    } },
  })
  local db = ES.db
  expect(db.chars == nil and db.charsMigrated == nil, "chars sigue ahí")
  expect(db.sellSeen == nil and db.mail == nil and db.earnBudget == nil and db.activeAH == nil, "claves antiguas sin quitar")
  local c = db.characters[guid]
  expect_eq(c.prof.Leatherworking.target, nil, "objetivo 225 antiguo")
  expect_eq(c.prof.Leatherworking.useAH, nil, "useAH")
  expect_eq(c.prof.Tailoring.target, nil, "objetivo 152 (nivel + 150 antiguo)")
  expect_eq(#c.shopping, 1, "listas de ruta antiguas quitadas")
  expect_eq(c.shopping[1].kind, "money", "la lista que queda")
  expect(type(db.minimap) == "table", "minimapa")
  note("minimapa tras migrar: angle=%s minimapPos=%s", tostring(db.minimap.angle), tostring(db.minimap.minimapPos))
  VisitAllTabs()
end, { boot = false })

-- Lo guardado roto: cada caso por separado, para saber cuál falla --------------

local function RealmKey() return REALM .. "-" .. FACTION end

local BROKEN = {
  { "un escaneo sin objetos", function(db) db.scans[RealmKey()] = { time = NOW } end },
  { "un escaneo vacío", function(db) db.scans[RealmKey()] = {} end,
    check = function() expect(ES.db.scans[RealmKey()] == nil, "el escaneo vacío sigue guardado") end },
  { "escaneos que no son una tabla", function(db) db.scans = "roto" end },
  { "historial vacío del reino", function(db) db.history = { [RealmKey()] = {} } end },
  { "personaje vacío", function(db) db.characters = { [UnitGUID("player")] = {} } end },
  { "ajustes de profesión vacíos", function(db) db.characters = { [UnitGUID("player")] = { prof = { Leatherworking = {}, Tailoring = { lock = {} } } } } end,
    check = function() expect(ES:RouteLock("Tailoring") == nil, "la ruta fijada vacía sigue guardada") end },
  { "ruta fijada que no es una tabla", function(db) db.characters = { [UnitGUID("player")] = { prof = { Tailoring = { lock = true } } } } end,
    check = function() expect(ES:RouteLock("Tailoring") == nil, "la ruta fijada rota sigue guardada") end },
  { "ruta fijada buena: se queda", function(db) db.characters = { [UnitGUID("player")] = { prof = { Tailoring = { lock = { from = 1, to = 75, started = 5 } } } } } end,
    check = function() expect(ES:RouteLock("Tailoring"), "se quitó una ruta fijada con sus niveles") end },
  -- Última ruta guardada (settings.lastRoute, ver ES:StorePlan): se descarta y se calcula
  { "ruta guardada que no es una tabla", function(db) db.characters = { [UnitGUID("player")] = { prof = { Tailoring = { lastRoute = true } } } } end,
    check = function() ES:CachedPlan("Tailoring", 1, 75) expect(ES.db.prof.Tailoring.lastRoute == nil, "la ruta guardada rota sigue guardada") end },
  { "ruta guardada sin recetas", function(db) db.characters = { [UnitGUID("player")] = { prof = { Tailoring = { lastRoute = { key = "x", reached = 75 } } } } } end,
    check = function() ES:CachedPlan("Tailoring", 1, 75) expect(ES.db.prof.Tailoring.lastRoute == nil, "la ruta guardada sin recetas sigue guardada") end },
  { "ruta guardada con las recetas vacías", function(db) db.characters = { [UnitGUID("player")] = { prof = { Tailoring = { lastRoute = { key = "x", reached = 75, choice = {} } } } } } end,
    check = function() ES:CachedPlan("Tailoring", 1, 75) expect(ES.db.prof.Tailoring.lastRoute == nil, "la ruta guardada vacía sigue guardada") end },
  { "ruta guardada con recetas que no son números", function(db) db.characters = { [UnitGUID("player")] = { prof = { Tailoring = { lastRoute = { key = "x", reached = 75, choice = { [1] = "Linen" }, bags = 3 } } } } } end,
    check = function() ES:CachedPlan("Tailoring", 1, 75) expect(ES.db.prof.Tailoring.lastRoute == nil, "la ruta guardada rota sigue guardada") end },
  { "lista de compra sin materiales", function(db) db.characters = { [UnitGUID("player")] = { shopping = { { kind = "money", title = "x", items = {} } } } } end },
  { "cálculos vacíos", function(db) db.calcs = {} end,
    check = function() expect(ES.Calc:Add("Leatherworking", 2152).id == 1, "el primer cálculo no es el 1") end },
  { "cálculos con lista pero sin número siguiente", function(db) db.calcs = { list = { { id = 4, prof = "Leatherworking", recipe = 2152, qty = 1, prices = {} } } } end,
    check = function() expect_eq(ES.Calc:Add("Leatherworking", 2152).id, 5, "número del cálculo nuevo") end },
  { "cálculo sin receta", function(db) db.calcs = { nextID = 2, selected = 1, list = { { time = NOW } } } end },
  { "recetas sabidas vacías", function(db) db.known = { ["Bruno-Realm"] = {} } end },
  { "asistente vacío", function(db) db.assistant = {} end },
  { "registro de errores vacío", function(db) db.errorLog = {} end },
  { "precios de instructor vacíos", function(db) db.trainerFees = {} db.trainerUnknown = {} end },
  { "stock de vendedor vacío", function(db) db.vendorStock = { [1347] = {} } end },
  { "idioma desconocido", function(db) db.lang = "xx" end },
  { "página guardada que ya no existe", function(db) db.lastPage = "auctions" end },
  { "minimapa que no es una tabla", function(db) db.minimap = true end },
}

for _, case in ipairs(BROKEN) do
  test("lo guardado roto: " .. case[1], function()
    local db = Fixtures.State("scan")
    case[2](db)
    Boot(db)
    VisitAllTabs(true)
    if case.check then case.check() end
  end, { boot = false, known = case[3] })
end

-- Eventos ------------------------------------------------------------------------

-- Argumentos habituales de cada evento (los demás, sin argumentos)
local ARGS = {
  ADDON_LOADED = { "CraftersJournal" },
  CHAT_MSG_SYSTEM = { "Has aprendido a fabricar: Light Armor Kit." },
  CHAT_MSG_SKILL = { "Your skill in Leatherworking has increased to 50." },
  UI_ERROR_MESSAGE = { 0, "No puedes hacer eso ahora." },
  UNIT_SPELLCAST_SUCCEEDED = { "player", "Cast-3-0-0-0-2152-0000000000", 2152 },
  GET_ITEM_INFO_RECEIVED = { 2318, true },
  CURRENCY_DISPLAY_UPDATE = { 3402, 10, 1 },
  NEW_RECIPE_LEARNED = { 2152 },
  LEARNED_SPELL_IN_TAB = { 2152, 1 },
  TRAIT_CONFIG_UPDATED = { 1 },
  TRAIT_NODE_CHANGED = { 1 },
  TRAIT_TREE_CHANGED = { 1 },
  ADDON_ACTION_BLOCKED = { "OtroAddon", "UseAction()" },
  ADDON_ACTION_FORBIDDEN = { "OtroAddon", "UseAction()" },
}
-- PLAYER_LOGOUT va aparte: es el último del juego (guarda y suelta lo del personaje)
local LAST = { PLAYER_LOGOUT = true }

local function FireAll(withArgs)
  local fired = {}
  for _, e in ipairs(EVENT_ORDER) do
    if not LAST[e] then
      local ok, err
      if withArgs and ARGS[e] then ok, err = pcall(FireEvent, e, unpack(ARGS[e]))
      else ok, err = pcall(FireEvent, e) end
      if not ok then error(e .. (withArgs and " (con argumentos)" or " (sin argumentos)") .. ": " .. tostring(err), 0) end
      RunTimers()
      fired[#fired + 1] = e
    end
  end
  return fired
end

test("eventos sin argumentos, con la ventana cerrada", function()
  local fired = FireAll(false)
  expect(#fired >= 20, "pocos eventos registrados: %d", #fired)
  note("%d eventos: %s", #fired, table.concat(fired, " "))
end, { state = "full" })

test("eventos con sus argumentos, con la ventana cerrada", function() FireAll(true) end, { state = "full" })

test("eventos sin argumentos, con la ventana abierta en cada pestaña", function()
  for _, key in ipairs({ "home", "shopping", "money", "inventory", "favor", "calc", "patterns", "Leatherworking" }) do
    OpenPage(key)
    FireAll(false)
  end
end, { state = "full" })

test("eventos con sus argumentos, con la ventana abierta", function()
  OpenPage("Leatherworking")
  FireAll(true)
end, { state = "full" })

test("eventos sin profesiones ni escaneo (usuario nuevo)", function()
  FireAll(false)
  FireAll(true)
end, { state = "empty" })

test("salir del juego guarda lo del personaje", function()
  OpenPage("Leatherworking")
  ES.db.lastProf = "Leatherworking"
  FireEvent("PLAYER_LOGOUT")
  expect(ES.db.prof == nil, "lo del personaje sigue suelto en ES.db")
  expect_eq(ES.charData.lastProf, "Leatherworking", "última profesión guardada")
end, { state = "full" })
