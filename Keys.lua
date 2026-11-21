local _, ES = ...

---------------------------------------------------------------------------
-- Claves de lo guardado: con qué se guarda lo de cada Casa de Subastas y lo de cada
-- personaje (spec saved-data-keys).
--
-- Desde el parche del cliente de Forever del 21/11/2026 el juego no dice el reino
-- (GetRealmName() vacío, GetRealmID() 0), y en Forever el reino era el servidor de
-- debajo, que Blizzard reparte y cambia. La AH es una por ruleset (Normal, PvP,
-- Roleplay...) y bando, y el cliente sí dice el ruleset: el modo de juego
-- (C_GameRules.GetCurrentGameModeRecordID: 14 PvP, 15 Normal). Así que:
--   ES:RealmKey() = "gm<modo>-<bando>" (antes "<reino>-<bando>")
--   ES:CharKey()  = "<nombre>-<GUID>"  (antes "<nombre>-<reino>")
-- Lo guardado con las claves de antes pasa a las nuevas al entrar (Migrate).
--
-- Nunca una clave vacía: si el cliente aún no da el modo, la última clave buena del
-- bando (ES.db.dataKey) y, sin ella, una provisional ("pending-<bando>") cuyo
-- contenido pasa a la buena cuando llega y que no se guarda al salir.
---------------------------------------------------------------------------
local Keys = {}
ES.Keys = Keys

local PENDING = "pending-"
local current -- clave de la AH en uso (se rehace con Keys.Refresh)
local good    -- current es la que da el cliente (no la última buena ni la provisional)

local function Faction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  if type(f) == "string" and f ~= "" then return f end
end

-- Número del modo de juego; nil: el cliente no tiene modos; false: aún no lo da
local function GameMode()
  local G = C_GameRules
  if not (G and G.GetCurrentGameModeRecordID) then return nil end
  local ok, id = pcall(G.GetCurrentGameModeRecordID)
  if ok and type(id) == "number" and id > 0 then return id end
  return false
end

local function RealmName()
  local r = GetRealmName and GetRealmName()
  if type(r) == "string" and r ~= "" then return r end
end

function Keys.IsPending(key) return type(key) == "string" and key:sub(1, #PENDING) == PENDING end

-- La clave que da el cliente ahora mismo, o nil si no se puede saber
function Keys.FromClient()
  local faction = Faction()
  if not faction then return nil end
  local mode = GameMode()
  if mode then return "gm" .. mode .. "-" .. faction end
  -- (sin modo: el reino, si lo da; un cliente sin modos, o el modo que aún no llega)
  local realm = RealmName()
  if realm then return realm .. "-" .. faction end
end

---------------------------------------------------------------------------
-- Juntar lo de dos claves sin perder nada (y dos veces da lo mismo que una)
---------------------------------------------------------------------------
-- El más reciente: escaneos, subastas seguidas y el último escaneo fallido son fotos
-- de un momento, no se mezclan por dentro
local function Newer(dst, src)
  if type(dst) ~= "table" then return src end
  if type(src) ~= "table" then return dst end
  return (tonumber(src.time) or 0) > (tonumber(dst.time) or 0) and src or dst
end

-- Historial de escaneos: todas las entradas (una por hora), ordenadas, las más nuevas
local function MergeHistory(dst, src)
  if type(dst) ~= "table" then return src end
  if type(src) ~= "table" then return dst end
  local seen = {}
  for _, e in ipairs(dst) do if type(e) == "table" and e.time then seen[e.time] = true end end
  for _, e in ipairs(src) do
    if type(e) == "table" and e.time and not seen[e.time] then dst[#dst + 1] = e seen[e.time] = true end
  end
  table.sort(dst, function(a, b) return (tonumber(a.time) or 0) < (tonumber(b.time) or 0) end)
  local max = ES.History and ES.History.MAX or 200
  while #dst > max do table.remove(dst, 1) end
  return dst
end

-- Precios por día de Inversiones: { [itemID] = "día:precio;día:precio" }; un día que
-- está en los dos se queda con el de `dst` (la clave nueva)
local function MergeDays(dst, src)
  if type(dst) ~= "table" then return src end
  if type(src) ~= "table" then return dst end
  for id, s in pairs(src) do
    local map = {}
    for _, packed in ipairs({ s, dst[id] }) do
      if type(packed) == "string" then
        for day, price in packed:gmatch("(%d+):(%d+)") do map[tonumber(day)] = tonumber(price) end
      end
    end
    local days = {}
    for day in pairs(map) do days[#days + 1] = day end
    table.sort(days)
    local parts = {}
    for _, day in ipairs(days) do parts[#parts + 1] = day .. ":" .. map[day] end
    dst[id] = table.concat(parts, ";")
  end
  return dst
end

-- Cartera de Inversiones: { [itemID] = { moves = { ... } } }; todos los movimientos,
-- sin repetir (mismo momento, tipo, cantidad y precio) y en orden
local function MoveKey(m)
  return table.concat({ tostring(m.t), tostring(m.kind), tostring(m.n), tostring(m.unit), tostring(m.total) }, "|")
end
local function MergeBook(dst, src)
  if type(dst) ~= "table" then return src end
  if type(src) ~= "table" then return dst end
  for id, e in pairs(src) do
    local d = dst[id]
    if type(d) ~= "table" or type(d.moves) ~= "table" then
      dst[id] = e
    elseif type(e) == "table" and type(e.moves) == "table" then
      local seen = {}
      for _, m in ipairs(d.moves) do if type(m) == "table" then seen[MoveKey(m)] = true end end
      for _, m in ipairs(e.moves) do
        if type(m) == "table" and not seen[MoveKey(m)] then d.moves[#d.moves + 1] = m seen[MoveKey(m)] = true end
      end
      table.sort(d.moves, function(a, b) return (tonumber(a.t) or 0) < (tonumber(b.t) or 0) end)
    end
  end
  return dst
end

-- Recetas sabidas de un personaje: { [profesión] = { recetaID, ... } }; todas
local function MergeKnown(dst, src)
  if type(dst) ~= "table" then return src end
  if type(src) ~= "table" then return dst end
  for prof, list in pairs(src) do
    if type(list) == "table" then
      local d = type(dst[prof]) == "table" and dst[prof] or {}
      local seen = {}
      for _, id in ipairs(d) do seen[id] = true end
      for _, id in ipairs(list) do if not seen[id] then d[#d + 1] = id seen[id] = true end end
      dst[prof] = d
    end
  end
  return dst
end
Keys.Merge = { Newer = Newer, History = MergeHistory, Days = MergeDays, Book = MergeBook, Known = MergeKnown } -- (pruebas)

-- Las tablas de ES.db que van por la clave de la AH, con su forma de juntar
local MERGE = { scans = Newer, track = Newer, lastScanFail = Newer, history = MergeHistory, investPrices = MergeDays }
local function Tables(db)
  local list = {}
  for name, merge in pairs(MERGE) do
    if type(db[name]) == "table" then list[#list + 1] = { t = db[name], merge = merge } end
  end
  if type(db.invest) == "table" and type(db.invest.account) == "table" then
    list[#list + 1] = { t = db.invest.account, merge = MergeBook }
  end
  return list
end

-- Pasa lo de la clave `from` a `to` en todas las tablas, juntando. true si había algo
local function Move(db, from, to)
  if from == to then return false end
  local moved = false
  for _, e in ipairs(Tables(db)) do
    local src = e.t[from]
    if src ~= nil then
      e.t[to] = e.merge(e.t[to], src)
      e.t[from] = nil
      moved = true
    end
  end
  return moved
end
Keys.Move = Move -- (pruebas)

---------------------------------------------------------------------------
-- Migración: lo guardado con "<reino>-<bando>" y "<nombre>-<reino>"
---------------------------------------------------------------------------
-- El reino de una clave antigua de la AH ("<reino>-<bando>"), o nil si no lo es
local function LegacyRealm(key, faction)
  if type(key) ~= "string" then return nil end
  local suffix = "-" .. faction
  if #key <= #suffix or key:sub(-#suffix) ~= suffix then return nil end
  local realm = key:sub(1, -#suffix - 1)
  if realm == "" or realm:match("^gm%d+$") or realm .. "-" == PENDING then return nil end
  return realm
end

local function HasKey(db, key)
  for _, e in ipairs(Tables(db)) do if e.t[key] ~= nil then return true end end
  return false
end

-- Cuándo se usó por última vez una clave antigua (su escaneo o sus subastas)
local function LegacyTime(db, key)
  local s = type(db.scans) == "table" and db.scans[key]
  local t = type(db.track) == "table" and db.track[key]
  return math.max(type(s) == "table" and tonumber(s.time) or 0, type(t) == "table" and tonumber(t.time) or 0)
end

-- El reino antiguo de este personaje (diseño, decisión 4): el que da el cliente; si
-- no, el de sus claves "<nombre>-<reino>" (la usada más tarde, si hay varias); si no,
-- la única clave antigua del bando. nil si no se sabe
function Keys.OldRealm(db, faction)
  local realm = RealmName()
  if realm then return realm end
  local name = UnitName and UnitName("player")
  local best, bestTime
  if type(name) == "string" and name ~= "" then
    local prefix = name .. "-"
    local function Consider(char, when)
      if type(char) ~= "string" or char:sub(1, #prefix) ~= prefix then return end
      local r = char:sub(#prefix + 1)
      if r == "" or r:match("^Player%-") or not HasKey(db, r .. "-" .. faction) then return end
      when = tonumber(when) or LegacyTime(db, r .. "-" .. faction)
      if not best or when > bestTime then best, bestTime = r, when end
    end
    for char, t in pairs(type(db.lastFullScan) == "table" and db.lastFullScan or {}) do Consider(char, t) end
    for char in pairs(type(db.known) == "table" and db.known or {}) do Consider(char) end
  end
  if best then return best end
  local only
  for _, e in ipairs(Tables(db)) do
    for k in pairs(e.t) do
      local r = LegacyRealm(k, faction)
      if r then
        if only and only ~= r then return nil end -- (varias: no se adivina)
        only = r
      end
    end
  end
  return only
end

-- Lo de la AH: la clave provisional de esta sesión, la del reino antiguo y la vacía
-- ("-<bando>", la que se creó tras el parche) pasan a `fresh`
function Keys.Migrate(fresh, prev)
  local db, faction = ES.db, Faction()
  if not (db and faction) then return end
  db.keyMoved = type(db.keyMoved) == "table" and db.keyMoved or {}
  if Keys.IsPending(prev) then Move(db, prev, fresh) end
  Move(db, "-" .. faction, fresh)
  if fresh:match("^gm%d+%-") then
    local old = Keys.OldRealm(db, faction)
    local legacy = old and old .. "-" .. faction
    -- (una vez: lo que una clave antigua ya dio a otra clave nueva no se vuelve a repartir)
    if legacy and (db.keyMoved[legacy] == nil or db.keyMoved[legacy] == fresh) then
      Move(db, legacy, fresh)
      db.keyMoved[legacy] = fresh
    end
  end
end

-- Lo del personaje (las recetas sabidas, ES.db.known): "<nombre>-<reino>" y
-- "<nombre>-" pasan a "<nombre>-<GUID>"
function Keys.MigrateChar()
  local db = ES.db
  local char = ES:CharKey()
  if not (db and char) or type(db.known) ~= "table" then return end
  db.keyMoved = type(db.keyMoved) == "table" and db.keyMoved or {}
  local name = UnitName("player")
  local prefix = name .. "-"
  local olds = {}
  for k in pairs(db.known) do
    if k ~= char and k:sub(1, #prefix) == prefix and not k:sub(#prefix + 1):match("^Player%-") then
      olds[#olds + 1] = k
    end
  end
  -- Con varios reinos antiguos para el mismo nombre, solo el de este personaje
  local legacy = {}
  for _, k in ipairs(olds) do if k ~= prefix then legacy[#legacy + 1] = k end end
  local pick = legacy[1]
  if #legacy > 1 then
    local faction = Faction()
    local realm = faction and Keys.OldRealm(db, faction)
    pick = realm and db.known[prefix .. realm] and prefix .. realm or nil
  end
  for _, k in ipairs({ prefix, pick }) do
    if db.known[k] ~= nil and (db.keyMoved[k] == nil or db.keyMoved[k] == char) then
      db.known[char] = MergeKnown(db.known[char], db.known[k])
      db.known[k] = nil
      if k ~= prefix then db.keyMoved[k] = char end
    end
  end
end

---------------------------------------------------------------------------
-- La clave en uso
---------------------------------------------------------------------------
-- Lo que depende de la clave (al cambiar en la sesión)
local function Changed()
  if ES.Invest and ES.Invest.Dirty then ES.Invest.Dirty() end
  if ES.PriceHistory and ES.PriceHistory.Clear then ES.PriceHistory.Clear() end
  if ES.ClearHomeCache then ES:ClearHomeCache() end
  if ES.RenderInvest then ES:RenderInvest() end
  if ES.UpdateLastScan then ES:UpdateLastScan() end
end

-- Mira otra vez el cliente: al cargar, al entrar, al cambiar el modo de juego
function Keys.Refresh()
  local fresh, db = Keys.FromClient(), ES.db
  if not db then return fresh or (PENDING .. (Faction() or "?")) end -- (sin lo guardado aún: sin caché)
  if fresh then
    if fresh ~= current or not good then
      local prev = current
      current, good = fresh, true
      db.dataKey = type(db.dataKey) == "table" and db.dataKey or {}
      db.dataKey[Faction()] = fresh
      Keys.Migrate(fresh, prev)
      if prev ~= nil and prev ~= fresh then Changed() end
    end
    Keys.MigrateChar()
  elseif not current then
    local last = type(db.dataKey) == "table" and db.dataKey[Faction() or ""]
    current = (type(last) == "string" and last ~= "") and last or (PENDING .. (Faction() or "?"))
    good = false
  end
  return current
end

-- La clave de la AH: "gm<modo>-<bando>" (ver arriba)
function ES:RealmKey()
  return current or Keys.Refresh()
end

-- El personaje: "<nombre>-<GUID>" (nil si el juego aún no da el GUID: no se guarda nada)
function ES:CharKey()
  local name = UnitName and UnitName("player")
  local guid = UnitGUID and UnitGUID("player")
  if type(name) ~= "string" or name == "" or type(guid) ~= "string" or guid == "" then return nil end
  return name .. "-" .. guid
end

-- Para pruebas: olvida la clave en uso (como al cargar otra vez)
function Keys.Reset() current, good = nil, nil end

do
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ACTIVE_GAME_MODE_UPDATED", "PLAYER_LOGOUT" }) do
    ES.SafeRegister(f, e)
  end
  f:SetScript("OnEvent", function(_, event)
    if not ES.db then return end
    if event ~= "PLAYER_LOGOUT" then Keys.Refresh() return end
    -- Al salir: lo que siga en la clave provisional no se guarda
    for _, e in ipairs(Tables(ES.db)) do
      for k in pairs(e.t) do if Keys.IsPending(k) then e.t[k] = nil end end
    end
  end)
end
