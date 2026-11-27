local _, ES = ...

---------------------------------------------------------------------------
-- Historial de precios por día de Auctionator (pestaña Inversiones).
--
-- Auctionator guarda, por objeto y por día, el mínimo más bajo y el mínimo más alto
-- que vio ese día y las unidades a la venta (21 días por defecto). Se usa el mínimo
-- más bajo, el que enseña su ventana de historial. No es su API
-- pública: se lee Auctionator.Database:GetPriceHistory(itemID) con pcall y
-- comprobando cada fila. Si falla o cambia de forma, el objeto queda sin precio,
-- como sin Auctionator. No se guarda copia: solo lo que Auctionator tiene ahora.
--
-- En el modo de escaneo Auctionator, solo Auctionator (si no se puede leer su historial,
-- sin precio: nunca tus días). En modo Crafter's Journal, los precios por día de tus
-- escaneos con el addon (Invest.OwnDays). El mismo análisis para los dos.
--
-- PriceHistory:Get(itemID) -> nil (sin datos) o
--   { source = "auctionator" | "scans",
--     days = { { day, price, avail, time, dubious }, ... } (del más antiguo al más reciente),
--     now = { day, price, avail, age (días), stale, unconfirmed },
--     change4 = cambio de los últimos 4 días (0,1 = +10 %) o nil }
---------------------------------------------------------------------------
local PH = {}
ES.PriceHistory = PH

PH.STALE_DAYS = 3  -- más días: precio viejo (en gris)
PH.DIP = 0.5       -- un día por debajo de la mitad del anterior y del siguiente: dudoso
PH.SPIKE = 2       -- ...o por encima del doble de los dos: dudoso (un pico de un día)
PH.LAST_SPIKE = 3  -- hoy, más del triple de ayer: subida sin confirmar (no es el precio de ahora)
PH.SPIKE_UNITS = 20 -- ...salvo con al menos tantas unidades a la venta: el mercado está ahí
PH.GAP_DAYS = 3    -- en la gráfica, días válidos más separados no se unen
PH.CHANGE_DAYS, PH.CHANGE_MIN, PH.CHANGE_MAX = 4, 3, 5 -- "últimos 4 días": un día de hace 3 a 5

local DAY = 86400

local function Database()
  local db = Auctionator and Auctionator.Database
  if type(db) == "table" and type(db.GetPriceHistory) == "function" then return db end
end

-- ¿Los precios salen del historial de Auctionator? Sí en el modo de escaneo Auctionator
-- (es la única fuente: si su historial no se puede leer, sin precio, sin caer a tus
-- días); en modo Crafter's Journal, no: solo los días de tus escaneos
function PH.Available()
  return ES.Scanner ~= nil and ES.Scanner.UsesAuctionator()
end

-- Días desde el día 0 de Auctionator (su constante; si no está, 1-1-2020)
local function Day0()
  local c = Auctionator and Auctionator.Constants
  local d0 = type(c) == "table" and tonumber(c.SCAN_DAY_0)
  return d0 or 1577836800
end
function PH.Today() return math.floor((time() - Day0()) / DAY) end
-- Hora (para la fecha de una etiqueta) del día `day`
function PH.DayTime(day) return Day0() + day * DAY + DAY / 2 end

local memo = {} -- [itemID] = resultado o false (sin datos): se olvida al abrir la pestaña
function PH.Clear() memo = {} end
ES.MemPart("Inversiones: precios de Auctionator", function() return memo end)

-- Filas de Auctionator -> { { day, price, avail } } ordenadas por día (sin las malas)
local function ReadDays(itemID)
  local db = Database()
  if not db then return nil end
  local ok, rows = pcall(db.GetPriceHistory, db, tostring(itemID))
  if not ok or type(rows) ~= "table" then return nil end
  local byDay = {}
  for _, row in ipairs(rows) do
    if type(row) == "table" then
      local day = tonumber(row.rawDay)
      -- El precio del día es el que enseña la ventana de historial de Auctionator: el
      -- mínimo más bajo del día (minSeen). (Se usaba el mínimo más alto, maxSeen, que
      -- Auctionator tiene en una columna oculta: escaneando varias veces al día se
      -- quedaba con el más caro y no cuadraba, Pyrite a 2s 97c en vez de 1s 84c)
      local price = tonumber(row.minSeen) or tonumber(row.maxSeen)
      if day and price and price > 0 and price == price and price < math.huge then
        day = math.floor(day)
        if not byDay[day] or price < byDay[day].price then
          byDay[day] = { day = day, price = price, avail = tonumber(row.available), time = PH.DayTime(day) }
        end
      end
    end
  end
  local days = {}
  for _, d in pairs(byDay) do days[#days + 1] = d end
  table.sort(days, function(a, b) return a.day < b.day end)
  return days
end

-- El último mínimo que vio Auctionator (su último escaneo o búsqueda con el objeto) y
-- hace cuántos días: su API pública. { price, age } o nil
local function LatestPrice(itemID)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and type(api.GetAuctionPriceByItemID) == "function") then return nil end
  local ok, price = pcall(api.GetAuctionPriceByItemID, "CraftersJournal", itemID)
  price = ok and tonumber(price)
  if not price or price <= 0 or price ~= price or price == math.huge then return nil end
  local age = 0
  if type(api.GetAuctionAgeByItemID) == "function" then
    local okA, days = pcall(api.GetAuctionAgeByItemID, "CraftersJournal", itemID)
    age = okA and tonumber(days) or 0
  end
  return { price = price, age = math.max(0, math.floor(age)) }
end

-- El día de ese último mínimo lleva el último mínimo (no el más bajo del día): es el
-- precio de ahora, lo que se ve en la AH y en el tooltip de Auctionator. (El más bajo
-- del día podía ser una subasta de primera hora ya vendida: salía por debajo de la AH)
-- Los días anteriores, el mínimo de cada día, como su ventana de historial
local function WithLatest(itemID, days)
  local latest = LatestPrice(itemID)
  if not latest then return days end
  local day = PH.Today() - latest.age
  for _, d in ipairs(days) do
    if d.day == day then
      d.price, d.latest = latest.price, true
      return days
    end
  end
  days[#days + 1] = { day = day, price = latest.price, time = PH.DayTime(day), latest = true }
  table.sort(days, function(a, b) return a.day < b.day end)
  return days
end

-- Marca los días dudosos: los que se hunden (una subasta suelta muy barata) o se
-- disparan (un escaneo con pocas unidades baratas a la venta) un solo día. Y el
-- último, si es más del triple del anterior: subida sin confirmar (d.spike), que no
-- cuenta como precio de ahora hasta que se repita otro día. (Antes solo se miraban
-- las bajadas: un pico de hoy pasaba a ser el precio de ahora, Small Flame Sac a 1g)
-- Con muchas unidades a la venta (PH.SPIKE_UNITS, todas a ese precio o más) no es un
-- pico de cuatro subastas: es el precio del mercado y cuenta ya. (Elemental Fire: de
-- 48s a 1g 50s con 344 a la venta, y la ficha seguía diciendo 48s; Discord 2026-11-27)
-- Solo con el historial de Auctionator, que guarda las unidades de cada día
local function MarkDubious(days)
  for i = 2, #days - 1 do
    local d, a, b = days[i], days[i - 1].price, days[i + 1].price
    if d.price < a * PH.DIP and d.price < b * PH.DIP then
      d.dubious = true
    elseif d.price > a * PH.SPIKE and d.price > b * PH.SPIKE then
      d.dubious, d.high = true, true
    end
  end
  -- (comparado con el día anterior bueno, no con uno dudoso)
  local n = #days
  local prev
  for i = n - 1, 1, -1 do if not days[i].dubious then prev = days[i] break end end
  if prev and days[n].price > prev.price * PH.LAST_SPIKE then
    if (days[n].avail or 0) >= PH.SPIKE_UNITS then
      days[n].backed = true -- (subida con unidades detrás: cuenta)
    else
      days[n].dubious, days[n].high, days[n].spike = true, true, true
    end
  end
end

-- El día válido (no dudoso) más cercano a `target` entre `lo` y `hi` (incluidos)
local function NearestValid(days, target, lo, hi)
  local best
  for _, d in ipairs(days) do
    if not d.dubious and d.day >= lo and d.day <= hi then
      if not best or math.abs(d.day - target) < math.abs(best.day - target)
        or (math.abs(d.day - target) == math.abs(best.day - target) and d.day > best.day) then
        best = d
      end
    end
  end
  return best
end

-- today: el día de hoy en la cuenta de esos días (por defecto, la de Auctionator)
function PH.Analyze(days, today)
  if not days or #days == 0 then return nil end
  MarkDubious(days)
  local last
  for i = #days, 1, -1 do
    if not days[i].dubious then last = days[i] break end
  end
  if not last then return nil end
  today = today or PH.Today()
  local age = math.max(0, today - last.day)
  local now = { day = last.day, price = last.price, avail = last.avail, age = age, stale = age > PH.STALE_DAYS, source = last.source }
  -- El último día, sin un día después que diga si rebota: se usa avisando
  local n = #days
  if last == days[n] and n >= 2 and last.price < days[n - 1].price * PH.DIP then now.unconfirmed = true end
  local ref = NearestValid(days, last.day - PH.CHANGE_DAYS, last.day - PH.CHANGE_MAX, last.day - PH.CHANGE_MIN)
  return { days = days, now = now, change4 = ref and (last.price / ref.price - 1) or nil, ref4 = ref }
end

-- Historial analizado de un objeto, o nil. En el modo Auctionator, SOLO Auctionator
-- (h.source = "auctionator"): precio, gráfica y "últimos 4 días" son lo mismo que su
-- historial, y se ponen al día al escanear o buscar con Auctionator. En modo Crafter's
-- Journal, los precios por día de tus escaneos con el addon (h.source = "scans",
-- Invest.OwnDays).
-- (Se probó juntar las dos fuentes por día: con dos formas de medir el precio en una
-- misma gráfica, los precios no cuadraban con los de Auctionator)
function PH:Get(itemID)
  if not itemID then return nil end
  local m = memo[itemID]
  if m == nil then
    if PH.Available() then
      local days = WithLatest(itemID, ReadDays(itemID) or {})
      for _, d in ipairs(days) do d.source = "auctionator" end
      m = PH.Analyze(days)
      if m then m.source = "auctionator" end
    elseif ES.Invest then
      local days = ES.Invest.OwnDays(itemID)
      for _, d in ipairs(days) do d.source = "scans" end
      m = PH.Analyze(days, ES.Invest.Day())
      if m then m.source = "scans" end
    end
    memo[itemID] = m or false
  end
  return m or nil
end

-- Auctionator acaba de guardar precios (su escaneo): se vuelven a leer y la pestaña se
-- repinta si se ve. Su API pública lo avisa (si no la tiene, al volver a abrir la pestaña)
function PH.Watch(onUpdate)
  if PH.watching then return end
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and type(api.RegisterForDBUpdate) == "function") then return end
  PH.watching = true
  pcall(api.RegisterForDBUpdate, "CraftersJournal", function()
    PH.Clear()
    if onUpdate then onUpdate() end
  end)
end
