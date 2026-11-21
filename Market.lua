local _, ES = ...
local L = ES.L

-- Señales de mercado de un objeto que funcionan con 1-2 escaneos al día, sin
-- intentar contar ventas. Cada una es una razón para NO fabricarlo:
--   estancado:      las subastas más baratas siguen ahí escaneo tras escaneo
--   precio clavado: el mínimo no se mueve desde hace un día Y hay muchas
--                   subastas apiñadas en él (no se puede bajar más)
--   más oferta:     cada día hay bastantes más unidades a la venta
-- La competencia (subastas en el mínimo) sola es normal en materiales, así que
-- se muestra como dato y solo cuenta dentro de "precio clavado".
-- Evitar = estancado, o precio clavado con más oferta. Ojo = una señal.

local Market = {}
ES.Market = Market

local HOUR, DAY = 3600, 86400
local WINDOW = 7 * DAY
local STUCK_LIFE_HOURS = 24     -- si las más baratas duran más que una subasta de 24 h: estancado
local STUCK_MIN_EXPOSURE = 24   -- subastas·hora observadas como mínimo para opinar
local STUCK_MIN_HOURS = 6       -- y al menos estas horas entre escaneos en total
local PRICE_TOLERANCE = 0.03    -- el mínimo "no se mueve" si cambia menos de un 3%
local PRICE_STUCK_DAYS = 1
local SUPPLY_AGE = 20 * HOUR    -- comparar con la foto de hace ~1 día
local SUPPLY_GROWTH = 0.5       -- +50% de unidades a la venta
local SUPPLY_MIN_UNITS = 10     -- y al menos 10 unidades más
local WALL_BAND = 1.05          -- "en el precio mínimo": hasta un 5% por encima
-- (sale de ES.db.track, que guarda solo hasta History.STUCK_BAND sobre el mínimo: no
-- puede ser mayor que eso; lo comprueba una prueba)
Market.WALL_BAND = WALL_BAND
local WALL_LISTINGS = 5
local MIN_SURVIVAL = 0.02       -- evita log(0) si desaparecen todas

-- Las fuentes del juego no tienen ✓/✗: iconos de "listo / no listo"
Market.ICON_BAD = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12|t "
Market.ICON_OK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t "
Market.ICON_NONE = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12|t "

Market.LABELS = ES.Localize({
  good = "|cff40ff40bien|r", watch = "|cffffd100ojo|r", avoid = "|cffff4040evitar|r", unknown = "|cff888888pocos datos|r",
})

-- Índice del historial por objeto, construido una vez por escaneo (recorrer el
-- historial por cada receta congelaría el juego). Guarda por objeto SOLO los totales
-- que usan las señales, no las filas: items[item] = un array de números (ver I_*).
-- Antes guardaba una tabla por dato (cada punto del historial, cada "baratas que
-- siguen", cada subasta): ~280.000 tablas y ~48 MB con 60 escaneos en la semana, todo
-- el rato aunque no se abriera la ventana. Ahora ocupa lo mismo con 5 escaneos que con
-- 200 (~0,7 MB con 2.000 objetos). Los puntos de cada objeto solo se guardan mientras
-- se construye (arrays planos), para lo que depende del último punto.
-- Construirlo es recorrer todo el historial de la semana: con 61 escaneos (3 MB) y
-- 56.000 subastas seguidas, ~350 ms de golpe, y crece con cada escaneo. En el juego se
-- hace en segundo plano, repartido entre fotogramas (BUILD_BUDGET por fotograma):
-- mientras, se usa el índice anterior (un escaneo atrás) o, recién entrado, uno vacío
-- ("pocos datos"); al acabar se repintan las ventanas una vez. Se empieza al entrar
-- y al acabar cada escaneo, así suele estar listo antes de que haga falta. Fuera del
-- juego (sin debugprofilestop), de golpe.
local cache
local EMPTY = { stamp = "", items = {}, empty = true }

-- Casillas del array de cada objeto (array y no campos con nombre: ~3 veces menos memoria)
local I_HAZARD, I_EXPOSURE, I_HOURS, I_REM, I_TOT = 1, 2, 3, 4, 5 -- estancado (sumas)
local I_POINTS, I_LAST_T, I_LAST_MIN, I_SINCE, I_FIRST_T = 6, 7, 8, 9, 10 -- precio clavado
local I_LAST_Q, I_OLD_Q, I_OLD_T = 11, 12, 13                     -- más oferta (false: no hay)
local I_REF, I_REF_N, I_REF_AGO = 14, 15, 16                       -- referencia (false: no hay)
local I_WALL_MIN, I_WALL_LISTINGS, I_WALL_UNITS = 17, 18, 19      -- competencia (false: no está)

local function NewItem()
  return { 0, 0, 0, 0, 0, 0, false, false, false, false, false, false, false, false, false, false, false, 0, 0 }
end
local BUILD_BUDGET = 3 -- ms por fotograma
local building       -- { stamp, co } mientras se construye
local servedStale    -- se dio un índice viejo (o vacío) mientras se construía el nuevo
local whenReady = {} -- lo que espera al índice nuevo (Market.WhenReady)

-- (con la clave de la AH: si cambia en la sesión, Keys.lua, el índice de la otra no vale
-- aunque las dos tengan los mismos escaneos, p. ej. ninguno)
local function Stamp()
  local key = ES:RealmKey()
  local history = ES.History:Entries()
  local track = ES.db.track and ES.db.track[key]
  local last = history[#history]
  return key .. ":" .. (#history) .. ":" .. (last and last.time or 0) .. ":" .. (track and track.time or 0), history, track
end

-- `pause()` se llama cada poco: en segundo plano cede el fotograma si se pasa del presupuesto
-- Precio de referencia de los puntos de un objeto (array plano: tiempo, mínimo,
-- cantidad, ... de más antiguo a más nuevo): mediana de los mínimos de cada día de los
-- últimos REF_DAYS días con escaneo, sin las últimas REF_GAP horas. Devuelve referencia,
-- nº de días usados y hace cuántos días es el más reciente, o nil
local REF_DAYS, REF_GAP = 3, 6 * HOUR
local function ComputeReference(list)
  if #list < 6 then return nil end -- (menos de 2 puntos)
  local last = list[#list - 2]
  local byDay = {}
  for i = 1, #list, 3 do
    local t, min = list[i], list[i + 1]
    if t <= last - REF_GAP then
      local day = math.floor(t / DAY)
      if not byDay[day] or min < byDay[day] then byDay[day] = min end
    end
  end
  local days = {}
  for day in pairs(byDay) do days[#days + 1] = day end
  if #days == 0 then return nil end
  table.sort(days, function(a, b) return a > b end) -- más recientes primero
  local mins = {}
  for i = 1, math.min(REF_DAYS, #days) do mins[i] = byDay[days[i]] end
  table.sort(mins)
  local n = #mins
  local ref = n % 2 == 1 and mins[(n + 1) / 2] or (mins[n / 2] + mins[n / 2 + 1]) / 2
  return ref, n, math.floor(last / DAY) - days[1]
end

-- Las sumas y comparaciones son las mismas, en el mismo orden, que cuando se
-- guardaban las filas: los resultados salen idénticos (prueba en auction.lua)
local function Build(stamp, history, track, pause)
  local now = time()
  local items = {}
  local idx = { stamp = stamp, items = items }
  local function Item(id)
    local it = items[id]
    if not it then it = NewItem() items[id] = it end
    return it
  end
  local points = {} -- [item] = { tiempo, mínimo, cantidad o false, ... } (solo al construir)
  local n = 0
  for _, entry in ipairs(history) do
    if now - entry.time < WINDOW then
      if entry.snap then
        for id, m, _, q in entry.snap:gmatch(";(%d+):(%d+):(%d+):?%d*:?(%d*)") do
          id = tonumber(id)
          local list = points[id]
          if not list then list = {} points[id] = list end
          local k = #list
          list[k + 1], list[k + 2], list[k + 3] = entry.time, tonumber(m), tonumber(q) or false
          n = n + 1
          if n % 256 == 0 then pause() end
        end
      end
      -- Comparaciones de al menos 15 min (antes 1 h: con escaneos seguidos se tiraban casi todas)
      -- Estancado: las sumas por objeto, en el orden del historial
      if entry.stuck and entry.elapsed and entry.elapsed >= 15 * 60 then
        local h = entry.elapsed / HOUR
        for id, r, t in entry.stuck:gmatch(";(%d+):(%d+):(%d+)") do
          r, t = tonumber(r), tonumber(t)
          if t > 0 then
            local it = Item(tonumber(id))
            it[I_HAZARD] = it[I_HAZARD] + t * -math.log(math.max(r / t, MIN_SURVIVAL))
            it[I_EXPOSURE] = it[I_EXPOSURE] + t * h
            it[I_HOURS] = it[I_HOURS] + h
            it[I_REM], it[I_TOT] = it[I_REM] + r, it[I_TOT] + t
          end
          n = n + 1
          if n % 256 == 0 then pause() end
        end
      end
    end
  end
  -- Lo que depende del último punto de cada objeto (precio clavado, más oferta, referencia)
  for id, list in pairs(points) do
    local it = Item(id)
    local li = #list - 2 -- (el último punto)
    local lastT, lastMin, lastQ = list[li], list[li + 1], list[li + 2]
    it[I_POINTS], it[I_LAST_T], it[I_LAST_MIN], it[I_FIRST_T] = #list / 3, lastT, lastMin, list[1]
    local since = lastT
    for i = li - 3, 1, -3 do
      if math.abs(list[i + 1] - lastMin) > lastMin * PRICE_TOLERANCE then break end
      since = list[i]
    end
    it[I_SINCE] = since
    it[I_LAST_Q] = lastQ
    if lastQ then
      for i = li - 3, 1, -3 do
        if list[i + 2] and lastT - list[i] >= SUPPLY_AGE then
          it[I_OLD_Q], it[I_OLD_T] = list[i + 2], list[i]
          break
        end
      end
    end
    local ref, days, ago = ComputeReference(list)
    if ref then it[I_REF], it[I_REF_N], it[I_REF_AGO] = ref, days, ago end
    points[id] = nil
    n = n + 1
    if n % 64 == 0 then pause() end
  end
  -- Competencia (subastas del último escaneo): el mínimo por unidad, y después cuántas
  -- subastas y unidades hay hasta WALL_BAND por encima
  local function Offer(fn)
    ES.History.EachPrice(track, function(id, count, buyout, packed)
      if buyout > 0 and count > 0 then fn(Item(id), buyout / count, count, packed) end
      n = n + 1
      if n % 256 == 0 then pause() end
    end)
  end
  Offer(function(it, unit)
    if not it[I_WALL_MIN] or unit < it[I_WALL_MIN] then it[I_WALL_MIN] = unit end
  end)
  Offer(function(it, unit, count, packed)
    if unit <= it[I_WALL_MIN] * WALL_BAND then
      local k = ES.History.Total(packed)
      it[I_WALL_LISTINGS], it[I_WALL_UNITS] = it[I_WALL_LISTINGS] + k, it[I_WALL_UNITS] + count * k
    end
  end)
  return idx
end

-- Listo el índice nuevo: lo que lo esperaba (el final de un escaneo) o, si alguien
-- usó el viejo entretanto, se repintan las ventanas con el nuevo
local function Ready()
  local waiting = whenReady
  whenReady = {}
  local stale = servedStale
  servedStale = nil
  for _, fn in ipairs(waiting) do pcall(fn) end
  if #waiting == 0 and stale and ES.RefreshAllViews then pcall(ES.RefreshAllViews, ES) end
end

local Step
function Step()
  local b = building
  if not b then return end
  local start = debugprofilestop()
  local ok, res = coroutine.resume(b.co, start)
  if not ok then
    building = nil
    if geterrorhandler then geterrorhandler()(res) end
    Ready()
    return
  end
  if coroutine.status(b.co) == "dead" then
    building = nil
    -- (si mientras tanto llegó otro escaneo, este ya es viejo: se hace el nuevo)
    if Stamp() == res.stamp then cache = res Ready() else Market:Index() end
    return
  end
  C_Timer.After(0, Step)
end

local function StartBuild(stamp, history, track)
  if building and building.stamp == stamp then return end
  local frameStart
  building = { stamp = stamp }
  building.co = coroutine.create(function(start)
    frameStart = start
    return Build(stamp, history, track, function()
      if debugprofilestop() - frameStart > BUILD_BUDGET then frameStart = coroutine.yield() end
    end)
  end)
  C_Timer.After(0, Step)
end

-- Las tres partes de la firma la última vez que coincidió con la del índice en uso:
-- iguales, la firma es la misma y no hace falta montar la cadena (un cálculo de ruta
-- pide el índice cientos de miles de veces). Lo mismo que Stamp, sin la cadena
local seenFor, seenKey, seenN, seenLast, seenTrack
function Market:Index()
  local key = ES:RealmKey()
  local history = ES.History:Entries()
  local track = ES.db.track and ES.db.track[key]
  local last = history[#history]
  local n, lastTime, trackTime = #history, last and last.time or 0, track and track.time or 0
  if cache and seenFor == cache and key == seenKey and n == seenN and lastTime == seenLast and trackTime == seenTrack then return cache end
  local stamp = key .. ":" .. n .. ":" .. lastTime .. ":" .. trackTime
  if cache and cache.stamp == stamp then
    seenFor, seenKey, seenN, seenLast, seenTrack = cache, key, n, lastTime, trackTime
    return cache
  end
  if not (debugprofilestop and C_Timer and coroutine) then
    cache = Build(stamp, history, track, function() end)
    return cache
  end
  StartBuild(stamp, history, track)
  servedStale = true
  return cache or EMPTY
end

-- ¿Se está construyendo el índice? Y `fn` cuando esté (al momento si ya lo está)
function Market.Building() return building ~= nil end
function Market.WhenReady(fn)
  if building then whenReady[#whenReady + 1] = fn else fn() end
end

-- Al entrar, el índice se prepara en segundo plano (unos segundos después, para no
-- sumarse a la carga del juego): cuando abras una ventana ya está
do
  local f = CreateFrame("Frame")
  ES.SafeRegister(f, "PLAYER_LOGIN")
  f:SetScript("OnEvent", function()
    if C_Timer then C_Timer.After(5, function() if ES.db then Market:Index() servedStale = nil end end) end
  end)
end

-- Las más baratas que siguen tras cada escaneo -> cuánto tardan en irse (horas).
-- Las que se van pueden haber caducado o sido retiradas, así que el tiempo que
-- sale es como mucho el real: si aun así es largo, está estancado de verdad.
function Market:Stuck(itemID)
  local hazard, exposure, hours, rem, tot = 0, 0, 0, 0, 0
  local it = self:Index().items[itemID]
  if it then
    hazard, exposure, hours, rem, tot = it[I_HAZARD], it[I_EXPOSURE], it[I_HOURS], it[I_REM], it[I_TOT]
  end
  if exposure < STUCK_MIN_EXPOSURE or hours < STUCK_MIN_HOURS then
    return { known = false, rem = rem, tot = tot, hours = hours }
  end
  local life = hazard > 0 and exposure / hazard or math.huge
  return { known = true, flag = life >= STUCK_LIFE_HOURS, life = life, rem = rem, tot = tot, hours = hours }
end

-- Días que lleva el precio mínimo sin moverse (más de un 3%)
-- (las cuentas se hacen al construir el índice: aquí solo se leen)
function Market:PriceStuck(itemID)
  local it = self:Index().items[itemID]
  if not it or it[I_POINTS] < 2 then return { known = false } end
  local covered = (it[I_LAST_T] - it[I_FIRST_T]) / DAY
  if covered < PRICE_STUCK_DAYS * 0.5 then return { known = false } end
  local days = (it[I_LAST_T] - it[I_SINCE]) / DAY
  return { known = true, flag = days >= PRICE_STUCK_DAYS, days = days, price = it[I_LAST_MIN] }
end

-- Unidades a la venta ahora frente a hace ~1 día
function Market:Supply(itemID)
  local it = self:Index().items[itemID]
  if not it or not it[I_LAST_Q] or not it[I_OLD_Q] then return { known = false } end
  local from, to = it[I_OLD_Q], it[I_LAST_Q]
  local growth = (to - from) / math.max(from, 1)
  return { known = true, flag = growth >= SUPPLY_GROWTH and to - from >= SUPPLY_MIN_UNITS,
    from = from, to = to, growth = growth, hours = (it[I_LAST_T] - it[I_OLD_T]) / HOUR }
end

-- Subastas apiñadas en el precio mínimo del último escaneo
function Market:Wall(itemID)
  local it = self:Index().items[itemID]
  if not it or not it[I_WALL_MIN] then return { known = false } end
  local listings = it[I_WALL_LISTINGS]
  return { known = true, flag = listings >= WALL_LISTINGS, listings = listings, units = it[I_WALL_UNITS],
    price = it[I_WALL_MIN] }
end

---------------------------------------------------------------------------
-- Precio de venta realista. El mínimo de un momento engaña: si se acaban las
-- baratas, el mínimo salta (Westfall Stew: 4s90 durante días, de golpe 23s) y
-- quien tenga historial no comprará a ese precio. Referencia = mediana de los
-- mínimos de los últimos REF_DAYS días CON escaneo (sirve aunque escanees días
-- sueltos), dentro del historial guardado (7 días) y sin contar las últimas
-- REF_GAP horas (el escaneo actual). Si el mínimo de ahora pasa de INFLATED veces
-- la referencia, se vende a referencia x PREMIUM (algo más por la falta de
-- existencias, pero un precio que se acepta), nunca por encima del mínimo actual.
---------------------------------------------------------------------------
local INFLATED, PREMIUM, DEFLATED = 1.5, 1.15, 1 / 1.5
local TSM_SUPPORTS = 0.9 -- venta media de TSM de al menos un 90% del mínimo de ahora: la subida es real
Market.INFLATED, Market.PREMIUM, Market.TSM_SUPPORTS = INFLATED, PREMIUM, TSM_SUPPORTS

-- Devuelve referencia, nº de días usados y hace cuántos días es el más reciente
-- (calculada al construir el índice: ComputeReference, arriba)
function Market:ReferencePrice(itemID)
  local it = self:Index().items[itemID]
  if not it or not it[I_REF] then return nil end
  return it[I_REF], it[I_REF_N], it[I_REF_AGO]
end

-- { price, current, ref, days, ago, inflated, deflated, noHistory } para vender ahora.
-- Sin historial, el mínimo actual (y se avisa: podría ser un pico).
function Market:FairPrice(itemID, currentMin)
  if not currentMin then return nil end
  local ref, days, ago = self:ReferencePrice(itemID)
  local fp = { price = currentMin, current = currentMin, ref = ref, days = days, ago = ago, noHistory = ref == nil }
  if ref and currentMin > ref * INFLATED then
    -- TSM sabe a cuánto se vende de verdad en la región: si se vende (sin poca demanda)
    -- y su venta media llega a lo de ahora, la subida es real y no se recorta (Star Ruby
    -- y Citrine subieron de golpe el 17-11: 300 y 1.300 a la venta al precio nuevo)
    local d = self:Demand(itemID)
    if d.known and not d.flag and d.avg and d.avg >= currentMin * TSM_SUPPORTS then
      fp.tsmSupported, fp.tsmAvg = true, d.avg
      return fp
    end
    fp.inflated = true
    fp.price = math.min(currentMin, math.floor(ref * PREMIUM + 0.5))
  elseif ref and currentMin < ref * DEFLATED then
    fp.deflated = true -- alguien malvende: hay que igualarlo igual para vender
  end
  return fp
end

-- Línea de tooltip sobre el precio de referencia (nada si no hay historial)
function Market.AddFairToTooltip(fp)
  if not fp then return end
  if fp.noHistory then
    GameTooltip:AddLine(L["Sin historial de este objeto: el precio de ahora podría ser un pico. Escanea otro día para confirmarlo."], 1, 0.6, 0.2, true)
    return
  end
  if fp.inflated then
    GameTooltip:AddLine(string.format(L["Precio inflado: ahora la más barata está a %s, pero los últimos días se vendía a ~%s (quedan pocas). Se cuenta a %s: más caro no lo compra quien mire el historial."],
      ES.Money(fp.current), ES.Money(fp.ref), ES.Money(fp.price)), 1, 0.6, 0.2, true)
    if fp.ago and fp.ago >= 2 then
      GameTooltip:AddLine(string.format(L["(el último escaneo con historial es de hace %d días)"], fp.ago), 0.7, 0.7, 0.7, true)
    end
  elseif fp.tsmSupported then
    GameTooltip:AddLine(string.format(L["Ha subido (los últimos días, ~%s), pero según TSM en la región se vende a ~%s: se cuenta al precio de ahora."],
      ES.Money(fp.ref), ES.Money(fp.tsmAvg)), 0.6, 1, 0.6, true)
  elseif fp.deflated then
    GameTooltip:AddLine(string.format(L["Más barato que de costumbre (~%s los últimos días): alguien malvende. Para vender ahora hay que igualarlo."],
      ES.Money(fp.ref)), 1, 0.82, 0, true)
  else
    GameTooltip:AddDoubleLine(L["Precio de los últimos días"], ES.Money(fp.ref), 0.8, 0.8, 0.8, 1, 1, 1)
  end
end

-- Precio al que anunciar: 1 cobre menos que la más barata; si está inflado, el realista
function Market.ListPrice(fp)
  if not fp then return nil end
  return fp.inflated and fp.price or math.max(1, fp.price - 1)
end

---------------------------------------------------------------------------
-- Demanda según TSM (Discord: "2 ventas al día según TSM"). Nuestras señales miran
-- tu AH con tus escaneos y no pueden contar ventas; la app de TSM sí las cuenta, pero
-- de toda la región (todos los reinos de Forever-EU, por ejemplo). Es una señal
-- aparte, con su origen a la vista: solo AÑADE prudencia (nunca quita una alerta de
-- tu escaneo), cuenta para el veredicto y pone tope a cuántas fabricar (Earn.lua).
-- Sin TSM, sin su app (TradeSkillMaster_AppHelper) o con la opción quitada
-- (ES.db.noTsmDemand), no hay señal y todo es como antes.
-- TSM redondea los valores a entero: la tasa (0-1) y los vendidos al día se piden
-- x1000, como hace su propio tooltip.
---------------------------------------------------------------------------
-- Umbrales: los elige el jugador en las opciones de Ganar dinero (deslizadores por
-- escalones; 0 = ese criterio no cuenta). Por defecto, tasa 0,15 (en Forever-EU, ~el
-- 20% de objetos que menos se vende) y 1 vendido al día en la región
Market.TSM_RATE_STEPS = { 0, 0.05, 0.1, 0.15, 0.25, 0.4, 0.6 }
Market.TSM_SOLD_STEPS = { 0, 0.25, 0.5, 1, 2, 5, 10 }
Market.TSM_MIN_RATE, Market.TSM_MIN_SOLD = 0.15, 1 -- (por defecto)
local TSM_LOW_PRICE = 0.75 -- aviso si la venta media es menos de esto de nuestro precio
Market.TSM_LOW_PRICE = TSM_LOW_PRICE
Market.TSM_SELL_DAYS = 2   -- tope del lote: lo que se vende en la región en estos días

local function Setting(key, default)
  local v = ES.db and ES.db[key]
  return type(v) == "number" and v >= 0 and v or default
end
function Market.TSMMinRate() return Setting("tsmMinRate", Market.TSM_MIN_RATE) end
function Market.TSMMinSold() return Setting("tsmMinSold", Market.TSM_MIN_SOLD) end

-- Número con 2 decimales como mucho (0,75 vendidos al día; tasa 0,3), coma salvo en inglés
function Market.Dec(x)
  if x >= 10 then return ES.Num(x) end
  local s = string.format("%.2f", x):gsub("0+$", ""):gsub("%.$", "")
  if ES.lang ~= "en" then s = s:gsub("%.", ",") end
  return s
end

local tsmMemo = {} -- itemID -> datos o false (los de TSM cambian al entrar, no al escanear)
function Market.ClearTSM() tsmMemo = {} end

-- ¿Se puede preguntar a TSM? (instalado y la opción puesta)
function Market.TSMOn()
  return TSM_API ~= nil and type(TSM_API.GetCustomPriceValue) == "function"
    and not (ES.db and ES.db.noTsmDemand)
end

local function TSMValue(source, itemID)
  local ok, v = pcall(TSM_API.GetCustomPriceValue, source, "i:" .. itemID)
  if ok and type(v) == "number" then return v end
end

-- { rate, sold, avg } de la región, o nil (sin TSM o sin datos de ese objeto)
function Market:TSMDemand(itemID)
  if not itemID or not Market.TSMOn() then return nil end
  local m = tsmMemo[itemID]
  if m == nil then
    local rate = TSMValue("DBRegionSaleRate * 1000", itemID)
    local sold = TSMValue("DBRegionSoldPerDay * 1000", itemID)
    -- (TSM da nil en vez de 0: con uno de los dos, el otro es ~0)
    m = (rate or sold) and { rate = (rate or 0) / 1000, sold = (sold or 0) / 1000,
      avg = TSMValue("DBRegionSaleAvg", itemID) } or false
    tsmMemo[itemID] = m
  end
  return m or nil
end

-- La señal: poca demanda si se vende poco de lo que se anuncia o menos de 1 al día
function Market:Demand(itemID)
  local d = self:TSMDemand(itemID)
  if not d then return { known = false, tsm = Market.TSMOn() } end
  local minRate, minSold = Market.TSMMinRate(), Market.TSMMinSold()
  return { known = true, tsm = true, flag = (minRate > 0 and d.rate < minRate) or (minSold > 0 and d.sold < minSold),
    rate = d.rate, sold = d.sold, avg = d.avg }
end

Market.SIGNALS = 3   -- estancado, precio clavado, más oferta (+ demanda de TSM, si hay datos)
local SIGNAL_KEYS = { "stuck", "nailed", "supply", "demand" }

-- Todas las señales de un objeto y el veredicto: good, watch, avoid o unknown
function Market:Signals(itemID)
  local s = {
    stuck = self:Stuck(itemID),
    price = self:PriceStuck(itemID),
    supply = self:Supply(itemID),
    wall = self:Wall(itemID),   -- solo dato
    demand = self:Demand(itemID),
  }
  s.nailed = { known = s.price.known, flag = s.price.flag and s.wall.flag or false }
  local flags, known = 0, 0
  for _, key in ipairs(SIGNAL_KEYS) do
    if s[key].known then known = known + 1 end
    if s[key].flag then flags = flags + 1 end
  end
  s.flags, s.known = flags, known
  s.total = Market.SIGNALS + (s.demand.known and 1 or 0)
  -- (poca demanda sola es "ojo"; con otra alerta en contra, evitar)
  if s.stuck.flag or (s.nailed.flag and s.supply.flag) or (s.demand.flag and flags >= 2) then
    s.verdict = "avoid"
  elseif flags >= 1 then
    s.verdict = "watch"
  elseif known >= 2 then
    s.verdict = "good"
  else
    s.verdict = "unknown"
  end
  return s
end

local function Hours(h)
  if h >= 48 then return ES.Num(math.floor(h / 24 + 0.5)) .. L[" días"] end
  return ES.Num(math.floor(h + 0.5)) .. " h"
end

-- Líneas para un tooltip: { texto, marcada (true/false/nil sin datos) }
function Market.Describe(s)
  local lines = {}
  local st = s.stuck
  if st.known then
    local life = st.life == math.huge and L["de las más baratas no se va ninguna"]
      or (L["las más baratas tardan ~"] .. Hours(st.life) .. L[" en irse"])
    lines[#lines + 1] = { string.format(L["Estancado: %s (%d de %d seguían en el siguiente escaneo)"],
      life, st.rem, st.tot), st.flag }
  else
    lines[#lines + 1] = { L["Estancado: faltan escaneos (bastan 1-2 al día durante un par de días)"], nil }
  end
  local p, w = s.price, s.wall
  if p.known then
    local text
    if s.nailed.flag then
      text = string.format(L["Precio clavado: el mínimo lleva %s sin moverse y hay %d subastas en él"],
        Hours(p.days * 24), w.listings)
    elseif p.flag then
      text = string.format(L["Precio clavado: no, el mínimo lleva %s quieto pero hay pocas subastas en él"],
        Hours(p.days * 24))
    else
      text = L["Precio clavado: no, el mínimo se ha movido en el último día"]
    end
    lines[#lines + 1] = { text, s.nailed.flag }
  else
    lines[#lines + 1] = { L["Precio clavado: falta historial de al menos medio día"], nil }
  end
  local o = s.supply
  if o.known then
    lines[#lines + 1] = { string.format(L["Más oferta: de %d a %d uds a la venta en %s (%+d%%)"],
      o.from, o.to, Hours(o.hours), math.floor(o.growth * 100 + 0.5)), o.flag }
  else
    lines[#lines + 1] = { L["Más oferta: falta una foto de hace ~1 día"], nil }
  end
  -- Demanda de TSM: solo si tienes TSM (sin él, ni se nombra)
  local d = s.demand
  if d and d.known then
    lines[#lines + 1] = { string.format(L["Demanda (TSM, región): ~%s vendidos al día, tasa de venta %s"],
      Market.Dec(d.sold), Market.Dec(d.rate)), d.flag }
  elseif d and d.tsm then
    lines[#lines + 1] = { L["Demanda (TSM): sin datos de este objeto (¿la app de TSM está al día?)"], nil }
  end
  -- Competencia: solo dato (tercer campo = informativa, sin icono)
  if w.known then
    lines[#lines + 1] = { string.format(L["Competencia: %d subastas (%d uds) en el precio mínimo"], w.listings, w.units), nil, true }
  else
    lines[#lines + 1] = { L["Competencia: no está en la AH ahora"], nil, true }
  end
  return lines
end

-- ¿La venta media de TSM está muy por debajo del precio al que contamos venderlo?
function Market.TSMLowPrice(s, price)
  local d = s and s.demand
  return d and d.known and d.avg and price and price > 0 and d.avg < price * TSM_LOW_PRICE or false
end

-- Añade la sección de señales a GameTooltip (`price`: al que contamos venderlo, por unidad)
function Market.AddToTooltip(itemID, price)
  local s = Market:Signals(itemID)
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine(L["Mercado"], Market.LABELS[s.verdict]
    .. string.format(L[" (%d de %d señales en contra)"], s.flags, s.total), 1, 0.82, 0, 1, 1, 1)
  for _, l in ipairs(Market.Describe(s)) do
    if l[3] then
      GameTooltip:AddLine("    " .. l[1], 0.6, 0.6, 0.6, true)
    else
      local r, g, b = 0.6, 0.6, 0.6
      if l[2] == true then r, g, b = 1, 0.4, 0.4 elseif l[2] == false then r, g, b = 0.6, 1, 0.6 end
      GameTooltip:AddLine((l[2] and Market.ICON_BAD or l[2] == false and Market.ICON_OK or Market.ICON_NONE) .. l[1], r, g, b, true)
    end
  end
  if Market.TSMLowPrice(s, price) then
    GameTooltip:AddLine(string.format(L["TSM: en la región se vende de media a %s, bastante menos que los %s con los que se cuenta aquí."],
      ES.Money(s.demand.avg), ES.Money(price)), 1, 0.6, 0.2, true)
  end
  if s.verdict == "avoid" then
    GameTooltip:AddLine(s.stuck.flag and L["Las más baratas no se venden: aunque el margen parezca bueno, probablemente no lo venderás."]
      or (s.nailed.flag and s.supply.flag) and L["Precio clavado y cada vez más oferta: aunque el margen parezca bueno, probablemente no lo venderás."]
      or L["Poca demanda según TSM y otra alerta en contra: aunque el margen parezca bueno, probablemente no lo venderás."], 1, 0.4, 0.4, true)
  end
  return s
end

---------------------------------------------------------------------------
-- Precios de otros addons (Auctionator, TSM) cuando tu escaneo no tiene el objeto.
-- Solo de respaldo y solo para decidir qué proponer vender (pestaña Inventario y la
-- ventana del vendedor): no se guardan en tus escaneos, no cuentan para el historial
-- ni para las señales de mercado (ese addon da un número, sin cantidades). Si el addon
-- no está o cambia su API, nil (pcall) y todo sigue como sin él.
-- Desactivable: ES.db.noAddonPrices (Options.lua)
---------------------------------------------------------------------------
local CALLER = "CraftersJournal"
local ADDON_PRICE_MAX_DAYS = 3 -- Auctionator: más viejo que esto no se usa

-- { price, source = "Auctionator" | "TSM", age (días, si se sabe) } o nil
function Market:AddonPrice(itemID)
  if not itemID or (ES.db and ES.db.noAddonPrices) then return nil end
  local atr = Auctionator and Auctionator.API and Auctionator.API.v1
  if atr and atr.GetAuctionPriceByItemID then
    local ok, price = pcall(atr.GetAuctionPriceByItemID, CALLER, itemID)
    if ok and type(price) == "number" and price > 0 then
      local age
      if atr.GetAuctionAgeByItemID then
        local okAge, days = pcall(atr.GetAuctionAgeByItemID, CALLER, itemID)
        if okAge and type(days) == "number" then age = days end
      end
      if not age or age <= ADDON_PRICE_MAX_DAYS then
        return { price = price, source = "Auctionator", age = age }
      end
    end
  end
  if TSM_API and TSM_API.GetCustomPriceValue then
    local ok, price = pcall(TSM_API.GetCustomPriceValue, "DBMinBuyout", "i:" .. itemID)
    if ok and type(price) == "number" and price > 0 then
      return { price = price, source = "TSM" }
    end
  end
  return nil
end