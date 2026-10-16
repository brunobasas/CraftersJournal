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
-- historial por cada receta congelaría el juego):
--   points[item] = { {time, min, listings, quantity}, ... } de más antigua a más nueva
--   stuck[item]  = { {elapsed, siguen, baratas}, ... }
--   offers[item] = { {unit, count, n}, ... } del último escaneo
local cache

function Market:Index()
  local history = ES.History:Entries()
  local track = ES.db.track and ES.db.track[ES:RealmKey()]
  local last = history[#history]
  local stamp = (#history) .. ":" .. (last and last.time or 0) .. ":" .. (track and track.time or 0)
  if cache and cache.stamp == stamp then return cache end
  local now = time()
  cache = { stamp = stamp, points = {}, stuck = {}, offers = {} }
  for _, entry in ipairs(history) do
    if now - entry.time < WINDOW then
      if entry.snap then
        for id, m, l, q in entry.snap:gmatch(";(%d+):(%d+):(%d+):?%d*:?(%d*)") do
          id = tonumber(id)
          local list = cache.points[id]
          if not list then list = {} cache.points[id] = list end
          list[#list + 1] = { time = entry.time, min = tonumber(m), listings = tonumber(l), quantity = tonumber(q) }
        end
      end
      -- Comparaciones de al menos 15 min (antes 1 h: con escaneos seguidos se tiraban casi todas)
      if entry.stuck and entry.elapsed and entry.elapsed >= 15 * 60 then
        for id, r, t in entry.stuck:gmatch(";(%d+):(%d+):(%d+)") do
          id = tonumber(id)
          local list = cache.stuck[id]
          if not list then list = {} cache.stuck[id] = list end
          list[#list + 1] = { entry.elapsed, tonumber(r), tonumber(t) }
        end
      end
    end
  end
  for sig, packed in pairs(track and track.sigs or {}) do
    local id, count, buyout = sig:match("^(%d+):(%d+):(%d+):")
    id, count, buyout = tonumber(id), tonumber(count), tonumber(buyout)
    if buyout > 0 and count > 0 then
      local _, n = ES.History.Unpack(packed)
      local list = cache.offers[id]
      if not list then list = {} cache.offers[id] = list end
      list[#list + 1] = { buyout / count, count, n }
    end
  end
  return cache
end

-- Las más baratas que siguen tras cada escaneo -> cuánto tardan en irse (horas).
-- Las que se van pueden haber caducado o sido retiradas, así que el tiempo que
-- sale es como mucho el real: si aun así es largo, está estancado de verdad.
function Market:Stuck(itemID)
  local hazard, exposure, hours, rem, tot = 0, 0, 0, 0, 0
  for _, c in ipairs(self:Index().stuck[itemID] or {}) do
    local r, t = c[2], c[3]
    if t > 0 then
      local h = c[1] / HOUR
      hazard = hazard + t * -math.log(math.max(r / t, MIN_SURVIVAL))
      exposure = exposure + t * h
      hours = hours + h
      rem, tot = rem + r, tot + t
    end
  end
  if exposure < STUCK_MIN_EXPOSURE or hours < STUCK_MIN_HOURS then
    return { known = false, rem = rem, tot = tot, hours = hours }
  end
  local life = hazard > 0 and exposure / hazard or math.huge
  return { known = true, flag = life >= STUCK_LIFE_HOURS, life = life, rem = rem, tot = tot, hours = hours }
end

-- Días que lleva el precio mínimo sin moverse (más de un 3%)
function Market:PriceStuck(points)
  if #points < 2 then return { known = false } end
  local last = points[#points]
  local since = last.time
  for i = #points - 1, 1, -1 do
    if math.abs(points[i].min - last.min) > last.min * PRICE_TOLERANCE then break end
    since = points[i].time
  end
  local covered = (last.time - points[1].time) / DAY
  if covered < PRICE_STUCK_DAYS * 0.5 then return { known = false } end
  local days = (last.time - since) / DAY
  return { known = true, flag = days >= PRICE_STUCK_DAYS, days = days, price = last.min }
end

-- Unidades a la venta ahora frente a hace ~1 día
function Market:Supply(points)
  local last = points[#points]
  if not last or not last.quantity then return { known = false } end
  local old
  for i = #points - 1, 1, -1 do
    if points[i].quantity and last.time - points[i].time >= SUPPLY_AGE then old = points[i] break end
  end
  if not old then return { known = false } end
  local growth = (last.quantity - old.quantity) / math.max(old.quantity, 1)
  return { known = true, flag = growth >= SUPPLY_GROWTH and last.quantity - old.quantity >= SUPPLY_MIN_UNITS,
    from = old.quantity, to = last.quantity, growth = growth, hours = (last.time - old.time) / HOUR }
end

-- Subastas apiñadas en el precio mínimo del último escaneo
function Market:Wall(itemID)
  local offers = self:Index().offers[itemID]
  if not offers then return { known = false } end
  local min
  for _, o in ipairs(offers) do
    if not min or o[1] < min then min = o[1] end
  end
  local listings, units = 0, 0
  for _, o in ipairs(offers) do
    if o[1] <= min * WALL_BAND then
      listings, units = listings + o[3], units + o[2] * o[3]
    end
  end
  return { known = true, flag = listings >= WALL_LISTINGS, listings = listings, units = units, price = min }
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
local REF_DAYS, REF_GAP = 3, 6 * HOUR
local INFLATED, PREMIUM, DEFLATED = 1.5, 1.15, 1 / 1.5
Market.INFLATED, Market.PREMIUM = INFLATED, PREMIUM

-- Devuelve referencia, nº de días usados y hace cuántos días es el más reciente
-- Se guarda por escaneo (en el índice): los planes la piden muchas veces por objeto
local NO_REF = {}
function Market:ReferencePrice(itemID)
  local index = self:Index()
  index.refs = index.refs or {}
  local memo = index.refs[itemID]
  if memo then
    if memo == NO_REF then return nil end
    return memo[1], memo[2], memo[3]
  end
  local ref, n, ago = self:ComputeReference(index.points[itemID])
  index.refs[itemID] = ref and { ref, n, ago } or NO_REF
  return ref, n, ago
end

function Market:ComputeReference(points)
  if not points or #points < 2 then return nil end
  local last = points[#points].time
  local byDay = {}
  for _, p in ipairs(points) do
    if p.time <= last - REF_GAP then
      local day = math.floor(p.time / DAY)
      if not byDay[day] or p.min < byDay[day] then byDay[day] = p.min end
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

-- { price, current, ref, days, ago, inflated, deflated, noHistory } para vender ahora.
-- Sin historial, el mínimo actual (y se avisa: podría ser un pico).
function Market:FairPrice(itemID, currentMin)
  if not currentMin then return nil end
  local ref, days, ago = self:ReferencePrice(itemID)
  local fp = { price = currentMin, current = currentMin, ref = ref, days = days, ago = ago, noHistory = ref == nil }
  if ref and currentMin > ref * INFLATED then
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

Market.SIGNALS = 3   -- estancado, precio clavado, más oferta

-- Todas las señales de un objeto y el veredicto: good, watch, avoid o unknown
function Market:Signals(itemID)
  local points = self:Index().points[itemID] or {}
  local s = {
    stuck = self:Stuck(itemID),
    price = self:PriceStuck(points),
    supply = self:Supply(points),
    wall = self:Wall(itemID),   -- solo dato
  }
  s.nailed = { known = s.price.known, flag = s.price.flag and s.wall.flag or false }
  local flags, known = 0, 0
  for _, key in ipairs({ "stuck", "nailed", "supply" }) do
    if s[key].known then known = known + 1 end
    if s[key].flag then flags = flags + 1 end
  end
  s.flags, s.known = flags, known
  if s.stuck.flag or (s.nailed.flag and s.supply.flag) then
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
  -- Competencia: solo dato (tercer campo = informativa, sin icono)
  if w.known then
    lines[#lines + 1] = { string.format(L["Competencia: %d subastas (%d uds) en el precio mínimo"], w.listings, w.units), nil, true }
  else
    lines[#lines + 1] = { L["Competencia: no está en la AH ahora"], nil, true }
  end
  return lines
end

-- Añade la sección de señales a GameTooltip
function Market.AddToTooltip(itemID)
  local s = Market:Signals(itemID)
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine(L["Mercado"], Market.LABELS[s.verdict]
    .. string.format(L[" (%d de %d señales en contra)"], s.flags, Market.SIGNALS), 1, 0.82, 0, 1, 1, 1)
  for _, l in ipairs(Market.Describe(s)) do
    if l[3] then
      GameTooltip:AddLine("    " .. l[1], 0.6, 0.6, 0.6, true)
    else
      local r, g, b = 0.6, 0.6, 0.6
      if l[2] == true then r, g, b = 1, 0.4, 0.4 elseif l[2] == false then r, g, b = 0.6, 1, 0.6 end
      GameTooltip:AddLine((l[2] and Market.ICON_BAD or l[2] == false and Market.ICON_OK or Market.ICON_NONE) .. l[1], r, g, b, true)
    end
  end
  if s.verdict == "avoid" then
    GameTooltip:AddLine(s.stuck.flag and L["Las más baratas no se venden: aunque el margen parezca bueno, probablemente no lo venderás."]
      or L["Precio clavado y cada vez más oferta: aunque el margen parezca bueno, probablemente no lo venderás."], 1, 0.4, 0.4, true)
  end
  return s
end
