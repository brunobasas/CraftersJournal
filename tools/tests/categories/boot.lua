-- Arranque y eventos: el addon carga y abre su ventana con cualquier cosa guardada,
-- y ningún evento que registra da error

-- Abre la ventana y pasa por todas las pestañas (sin errores, es lo que se comprueba)
-- (oneProf: solo la página de una profesión; las 8 cuestan, con precios, varios segundos)
local function VisitAllTabs(oneProf)
  OpenMain()
  for _, key in ipairs({ "home", "shopping", "money", "inventory", "invest", "favor", "calc", "patterns" }) do
    ES:SelectPage(key)
    RunTimers()
  end
  -- El detalle de cada inversión (si hay cartera)
  for itemID in pairs(ES.Invest.Book()) do
    ES:ShowInvestItem(itemID)
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
    noForeignScans = true, -- (opción "Leer los escaneos de otros addons": ya se leen siempre)
    investNoAuctionatorTip = true, -- (la X del consejo de instalar Auctionator: ya no hay consejo)
    noNeutralAHNotice = true, -- (el aviso de la AH neutral ya no es una opción)
    characters = { [guid] = {
      prof = { Leatherworking = { target = 225, useAH = false }, Tailoring = { target = 152 } },
      shopping = { { kind = "route", key = "Leatherworking", title = "vieja", items = {} },
                   { kind = "money", title = "mía", items = { { itemID = 2318, need = 5, unit = 25, source = "ah" } } } },
    } },
  })
  local db = ES.db
  expect(db.chars == nil and db.charsMigrated == nil, "chars sigue ahí")
  expect(db.sellSeen == nil and db.mail == nil and db.earnBudget == nil and db.activeAH == nil, "claves antiguas sin quitar")
  expect(db.noForeignScans == nil, "la opción de no leer los escaneos de otros addons sigue guardada")
  expect(db.investNoAuctionatorTip == nil, "la X del consejo de instalar Auctionator sigue guardada")
  expect(db.noNeutralAHNotice == nil, "el aviso de la AH neutral sigue apagado")
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

-- (con la clave de antes del parche, como Fixtures: al arrancar pasa a la nueva)
local function RealmKey() return "Realm-" .. FACTION end

local BROKEN = {
  { "un escaneo sin objetos", function(db) db.scans[RealmKey()] = { time = NOW } end },
  { "un escaneo vacío", function(db) db.scans[RealmKey()] = {} end,
    check = function()
      expect(ES.db.scans[RealmKey()] == nil and ES.db.scans[ES:RealmKey()] == nil, "el escaneo vacío sigue guardado")
    end },
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
  { "recetas desbloqueadas que no son una tabla", function(db) db.unlockSeen = true end },
  { "recetas desbloqueadas de un personaje que no son una tabla", function(db) db.unlockSeen = { ["Bruno-Player-1-00000001"] = 5 } end },
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
  QUEST_TURNED_IN = { 92110, 0, 0 },
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

-- Registro de errores (Core.lua) ------------------------------------------------
-- El addon no se pone delante del manejador de errores del juego: si no, su código
-- corría en los errores de otros addons y el juego le prohibía lo que venía después
-- (UseContainerItem al abrir una caja desde las bolsas, junto a EllesmereUI)
test("el addon no cambia el manejador de errores del juego", function()
  expect(geterrorhandler() == GAME_ERROR_HANDLER, "al cargar, el manejador es el del addon")
  FireEvent("PLAYER_ENTERING_WORLD")
  RunTimers()
  expect(geterrorhandler() == GAME_ERROR_HANDLER, "al entrar en el mundo, el manejador es el del addon")
end)

-- Lo que apuntó ES:RecordError a propósito en la prueba (si no, el lanzador lo da por fallo)
local function TakeRecorded()
  local list = {}
  for i = 1, #RECORDED_ERRORS do list[i] = RECORDED_ERRORS[i] end
  for i = #RECORDED_ERRORS, 1, -1 do RECORDED_ERRORS[i] = nil end
  return list
end

local L = ES.L

local function Printed(text)
  for _, p in ipairs(PRINTS) do if p:find(text, 1, true) then return true end end
  return false
end

test("/cj errores grabar: graba los errores de Lua del addon, no los ajenos", function()
  debugstack = function() return "pila de prueba" end
  SlashCmdList.CRAFTERSJOURNAL("errores grabar")
  local handler = geterrorhandler()
  expect(handler ~= GAME_ERROR_HANDLER and ES.RecordingLuaErrors(), "no se enganchó el manejador")
  expect(Printed(L["Grabando los errores de Lua del addon hasta la próxima recarga (/reload). Repite lo que fallaba y mira /cj errores."]),
    "no avisó de que graba")
  handler("Interface/AddOns/CraftersJournal/Core.lua:1: error de prueba")
  handler("Interface/AddOns/OtroAddon/OtroAddon.lua:1: error ajeno")
  -- Otra vez el comando: no se pone delante de sí mismo (si no, se llamaría en bucle)
  SlashCmdList.CRAFTERSJOURNAL("errors record")
  geterrorhandler()("Interface/AddOns/OtroAddon/OtroAddon.lua:2: otro ajeno")
  local log = ES.db.errorLog or {}
  expect_eq(#log, 1, "errores apuntados (solo el del addon)")
  expect_eq(log[1].kind, "lua", "tipo")
  expect(log[1].msg:find("error de prueba", 1, true), "mensaje apuntado: %s", log[1].msg)
  expect_eq(log[1].stack, "pila de prueba", "pila")
  expect_eq(#GAME_ERRORS, 3, "errores que llegan al manejador del juego")
  expect_eq(#TakeRecorded(), 1, "errores apuntados con ES:RecordError")
  PRINTS = {}
  SlashCmdList.CRAFTERSJOURNAL("errores")
  expect(Printed(L["Grabando los errores de Lua del addon hasta la próxima recarga (/reload)."]), "/cj errores no dice que está grabando")
end)

test("/cj errores sin grabar: no se apuntan errores de Lua y dice cómo grabarlos", function()
  -- (en una sesión normal nadie llama al manejador del addon: no está puesto)
  expect(not ES.RecordingLuaErrors(), "graba sin pedirlo")
  SlashCmdList.CRAFTERSJOURNAL("errores")
  expect(Printed(L["Ningún error registrado."]), "no dice que no hay errores")
  expect(Printed(L["Los errores de Lua del addon solo se graban con /cj errores grabar (hasta la próxima recarga)."]),
    "no dice cómo grabar los errores de Lua")
end)

test("acción prohibida al addon: se apunta siempre, sin grabar", function()
  FireEvent("ADDON_ACTION_FORBIDDEN", "CraftersJournal", "UseContainerItem()")
  FireEvent("ADDON_ACTION_FORBIDDEN", "CraftersJournal", "UseContainerItem()")
  FireEvent("ADDON_ACTION_FORBIDDEN", "OtroAddon", "UseContainerItem()")
  local log = ES.db.errorLog or {}
  expect_eq(#log, 1, "entradas")
  expect_eq(log[1].kind, "prohibida", "tipo")
  expect_eq(log[1].msg, "UseContainerItem()", "función")
  expect_eq(log[1].count, 2, "veces")
  expect_eq(#TakeRecorded(), 2, "apuntadas con ES:RecordError")
  SlashCmdList.CRAFTERSJOURNAL("errores")
  expect(Printed("[prohibida]|r x2"), "/cj errores no la lista")
end)

test("salir del juego guarda lo del personaje", function()
  OpenPage("Leatherworking")
  ES.db.lastProf = "Leatherworking"
  FireEvent("PLAYER_LOGOUT")
  expect(ES.db.prof == nil, "lo del personaje sigue suelto en ES.db")
  expect_eq(ES.charData.lastProf, "Leatherworking", "última profesión guardada")
end, { state = "full" })

-- Claves de lo guardado (Keys.lua, change ruleset-keys) ---------------------------
-- Desde el parche del cliente de Forever del 21/11/2026 el juego no da el reino: lo de
-- la AH va por modo de juego (ruleset) y bando, y lo del personaje por nombre y GUID

-- La clave de la AH con este cliente (como en una sesión nueva)
local function KeyFor(mode, faction, realm, noModes)
  GAME_MODE, FACTION, REALM = mode, faction, realm or ""
  local rules = C_GameRules
  if noModes then C_GameRules = nil end
  ES.Keys.Reset()
  local key = ES:RealmKey()
  C_GameRules = rules
  return key
end

test("claves: la de la AH es el modo de juego y el bando", function()
  expect_eq(KeyFor(14, "Alliance"), "gm14-Alliance", "PvP, Alianza")
  expect_eq(KeyFor(15, "Alliance"), "gm15-Alliance", "Normal, Alianza")
  expect_eq(KeyFor(14, "Horde"), "gm14-Horde", "PvP, Horda")
  expect_eq(KeyFor(0, "Alliance", "Realm", true), "Realm-Alliance", "cliente sin modos, con reino")
  expect_eq(ES:CharKey(), "Bruno-Player-1-00000001", "personaje")
end)

test("claves: sin modo al cargar, lo apuntado pasa a la clave buena cuando llega", function()
  GAME_MODE = 0
  Boot({})
  expect(ES.Keys.IsPending(ES:RealmKey()), "sin modo ni clave anterior, la clave no es la provisional: %s", ES:RealmKey())
  expect(ES.Invest:Add(4306, "buy", 5, 100), "no se apunta la compra")
  ES.History:Entries() -- (leer no crea nada)
  SetGameMode(14)
  RunTimers()
  expect_eq(ES:RealmKey(), "gm14-Alliance", "clave al llegar el modo")
  local book = ES.db.invest.account["gm14-Alliance"]
  expect(book and book[4306] and #book[4306].moves == 1, "la compra no pasó a la clave del modo")
  expect_eq(table.concat(BadKeys(ES.db), " "), "", "claves provisionales o vacías")
end, { boot = false })

test("claves: sin modo al cargar, se usa la última clave buena", function()
  GAME_MODE = 0
  Boot({ dataKey = { Alliance = "gm14-Alliance" }, scans = { ["gm14-Alliance"] = Fixtures.Scan() } })
  expect_eq(ES:RealmKey(), "gm14-Alliance", "clave sin modo")
  expect(ES.db.scans[ES:RealmKey()], "no se ve el escaneo de la última clave buena")
end, { boot = false })

test("claves: una sesión entera sin modo no guarda claves provisionales ni vacías", function()
  GAME_MODE = 0
  Boot({})
  ES.Invest:Add(4306, "buy", 5, 100)
  ES.Collection:SaveKnown("Cooking")
  FireEvent("PLAYER_LOGOUT")
  expect_eq(table.concat(BadKeys(ES.db), " "), "", "claves provisionales o vacías al salir")
end, { boot = false })

-- Antes llegaba un UNIT_SPELLCAST_SUCCEEDED por cada hechizo de cualquiera a tu
-- alrededor; los manejadores solo miran los tuyos (PR #8: RegisterUnitEvent)
test("hechizos lanzados: solo llegan los tuyos", function()
  local cast = { "Cast-3-0-0-0-2152-0000000000", 2152 }
  local mine = FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", unpack(cast))
  RunTimers()
  local others = FireEvent("UNIT_SPELLCAST_SUCCEEDED", "target", unpack(cast))
  RunTimers()
  expect(mine >= 2, "solo %d marcos reciben tus hechizos (Ganar dinero y las recetas con enfriamiento)", mine)
  expect_eq(others, 0, "marcos que reciben los hechizos de otro")
end)

-- Juntar lo de dos claves: no se pierde nada y dos veces da lo mismo que una
test("migración: juntar no pierde nada y es idempotente", function()
  local M = ES.Keys.Merge
  local function Copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = Copy(v) end
    return c
  end
  local function Twice(merge, dst, src) return merge(merge(Copy(dst), Copy(src)), Copy(src)) end
  -- Cartera: los movimientos de las dos, sin repetir el que está en ambas, en orden
  local a = { [1] = { moves = { { t = 10, kind = "buy", n = 5, unit = 100 }, { t = 30, kind = "sell", n = 2, unit = 150 } } } }
  local b = { [1] = { moves = { { t = 20, kind = "buy", n = 1, unit = 90 }, { t = 10, kind = "buy", n = 5, unit = 100 } } },
              [2] = { moves = { { t = 5, kind = "buy", n = 3, total = 300 } } } }
  local book = Twice(M.Book, a, b)
  expect_eq(#book[1].moves, 3, "movimientos del objeto 1")
  expect_eq(book[1].moves[1].t .. "," .. book[1].moves[2].t .. "," .. book[1].moves[3].t, "10,20,30", "orden")
  expect(book[2] and #book[2].moves == 1, "el objeto que solo estaba en una se perdió")
  -- Historial: todas las entradas, por hora
  local h = Twice(M.History, { { time = 1 }, { time = 3 } }, { { time = 2 }, { time = 3 } })
  expect_eq(#h, 3, "entradas del historial")
  -- Precios por día: todos los días; uno repetido se queda con el de la clave nueva
  local d = Twice(M.Days, { [7] = "100:5;102:7" }, { [7] = "101:6;102:9", [8] = "100:1" })
  expect_eq(d[7], "100:5;101:6;102:7", "días del objeto 7")
  expect_eq(d[8], "100:1", "días del objeto 8")
  -- Escaneo: el más reciente entero
  expect_eq(M.Newer({ time = 5, items = {} }, { time = 9, items = {} }).time, 9, "escaneo más reciente")
  expect_eq(M.Newer({ time = 9, items = {} }, { time = 5, items = {} }).time, 9, "no cambia por uno más viejo")
  -- Recetas sabidas: todas
  local k = Twice(M.Known, { Cooking = { 1, 2 } }, { Cooking = { 2, 3 }, Tailoring = { 4 } })
  expect_eq(#k.Cooking, 3, "recetas de Cocina")
  expect(k.Tailoring and #k.Tailoring == 1, "se perdió Sastrería")
end)

-- Lo guardado como el SavedVariables de un jugador tras el parche: la cartera, el
-- escaneo y sus precios con la clave del reino, una compra y recetas apuntadas después
-- con las claves vacías ("-Alliance", "Bruno-")
local OLD = "CAMWOW EU4 Realm 6 PvP"
local function PlayerDB()
  local function Moves(t, n) return { moves = { { t = t, kind = "buy", n = n, unit = 100 } } } end
  local book = {}
  for i, id in ipairs({ 249391, 4306, 2592, 13468, 9258, 2589, 2318, 4338 }) do book[id] = Moves(1795000000 + i, 10 * i) end
  local scan = Fixtures.Scan()
  scan.time = 1795217572
  return {
    scans = { [OLD .. "-Alliance"] = scan },
    track = { [OLD .. "-Alliance"] = { time = 1795217572, v = 3, packed = "" } },
    history = { [OLD .. "-Alliance"] = { { time = 1794644173, elapsed = 1, snap = "" } }, ["-Alliance"] = {} },
    invest = { account = { [OLD .. "-Alliance"] = book, ["-Alliance"] = { [4306] = Moves(1795300000, 5) } } },
    investPrices = { [OLD .. "-Alliance"] = { [4306] = "20770:197" } },
    known = { ["Bruno-" .. OLD] = { Cooking = { 2538 } }, ["Bruno-"] = { Tailoring = { 2963 } } },
    lastFullScan = { ["Bruno-" .. OLD] = 1795210979, ["otro addon"] = 1795217538 },
  }
end

test("migración: lo guardado con el reino vuelve a salir con el cliente sin reino", function()
  Boot(PlayerDB())
  local key = ES:RealmKey()
  expect_eq(key, "gm14-Alliance", "clave")
  local n = 0
  for _ in pairs(ES.Invest.Book()) do n = n + 1 end
  expect_eq(n, 8, "objetos de la cartera")
  expect_eq(#ES.Invest.Book()[4306].moves, 2, "movimientos de Silk Cloth (el de antes y el de después del parche)")
  expect(ES.db.scans[key] and ES.db.scans[key].time == 1795217572, "el escaneo no está en la clave nueva")
  expect_eq(ES.db.investPrices[key] and ES.db.investPrices[key][4306], "20770:197", "precios por día")
  expect_eq(#ES.History:Entries(), 1, "entradas del historial")
  local me = ES.db.known[ES:CharKey()]
  expect(me and me.Cooking and me.Tailoring, "las recetas sabidas no pasaron al personaje")
  OpenPage("invest")
  expect_eq(ES:GetMainFrame().pages.invest.shownCards, 8, "fichas en la pestaña Inversiones")
  -- No queda nada con las claves de antes ni vacías
  expect_eq(table.concat(BadKeys(ES.db), " "), "", "claves vacías")
  for name, t in pairs(KeyedTables(ES.db)) do
    for k in pairs(t) do expect(not tostring(k):find(OLD, 1, true), "queda %s/%s", name, tostring(k)) end
  end
  -- Entrar otra vez no cambia nada
  ES.Keys.Reset()
  FireEvent("PLAYER_LOGIN")
  FireEvent("PLAYER_ENTERING_WORLD")
  RunTimers()
  expect_eq(#ES.Invest.Book()[4306].moves, 2, "movimientos de Silk Cloth al entrar otra vez")
  expect_eq(#ES.History:Entries(), 1, "entradas del historial al entrar otra vez")
end, { boot = false })

-- Dos rulesets en la misma cuenta: cada reino antiguo va al ruleset de sus personajes
test("migración: cada reino antiguo va al ruleset de sus personajes", function()
  local scanPvP, scanNormal = Fixtures.Scan(), Fixtures.Scan()
  scanPvP.time, scanNormal.time = 1000, 2000
  local db = {
    scans = { ["Reino PvP-Alliance"] = scanPvP, ["Reino Normal-Alliance"] = scanNormal },
    known = { ["Bruno-Reino PvP"] = { Cooking = { 2538 } }, ["Ana-Reino Normal"] = { Cooking = { 2539 } } },
  }
  GAME_MODE = 14
  Boot(db)
  expect(ES.db.scans["gm14-Alliance"] and ES.db.scans["gm14-Alliance"].time == 1000, "el PvP no pasó al 14")
  expect(ES.db.scans["Reino Normal-Alliance"], "lo del reino Normal se tocó al entrar en PvP")
  -- Después entra Ana, del reino Normal, en el ruleset Normal
  UnitName = function() return "Ana" end
  UnitGUID = function(u) if u == "player" then return "Player-6945-0000BBBB" end end
  GAME_MODE = 15
  ES.Keys.Reset()
  FireEvent("PLAYER_LOGIN")
  RunTimers()
  expect(ES.db.scans["gm15-Alliance"] and ES.db.scans["gm15-Alliance"].time == 2000, "el Normal no pasó al 15")
  expect(ES.db.scans["gm14-Alliance"].time == 1000, "el 14 cambió")
  expect(ES.db.known["Ana-Player-6945-0000BBBB"], "las recetas de Ana no pasaron a su personaje")
end, { boot = false })

-- Sin pistas de a qué reino era el personaje, y con varios reinos antiguos: no se adivina
test("migración: con varios reinos antiguos y sin pistas, no se toca nada", function()
  local db = { scans = { ["Reino A-Alliance"] = Fixtures.Scan(), ["Reino B-Alliance"] = Fixtures.Scan() } }
  Boot(db)
  expect(ES.db.scans["Reino A-Alliance"] and ES.db.scans["Reino B-Alliance"], "se borró un reino antiguo")
  expect(not ES.db.scans["gm14-Alliance"], "se movió un reino antiguo sin saber cuál era")
end, { boot = false })