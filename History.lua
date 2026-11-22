local _, ES = ...
local L = ES.L

-- Historial de escaneos de la AH.
--
-- No intenta deducir ventas: cuando una subasta desaparece entre dos escaneos
-- no se puede saber si se vendió, caducó o la retiraron (el cliente no da el
-- identificador de la subasta ni el vendedor). Solo guarda lo que es seguro:
--   snap:  foto de precio de los objetos de profesiones
--          ";itemID:mínimo:subastas:mediana:unidades;..."
--   stuck: de las subastas más baratas de cada objeto, cuántas siguen en el
--          escaneo siguiente (las que siguen no se han vendido, seguro)
--          ";itemID:siguen:baratas;..."
-- Lo usan las alertas de mercado (Market.lua) y la tendencia de precio.
--
-- ES.db.history[reino]: lista de { time, elapsed (s desde el escaneo anterior;
--   0 si no se pudo comparar), snap, stuck }
-- ES.db.track[reino]: { time, v = 3, packed } subastas del último escaneo por firma,
--   en una cadena (History.Pack; antes v = 2 con sigs = { [firma] = número }, que se
--   sigue leyendo: History.EachSig). Solo las cercanas al mínimo de su objeto
--   (History.NearMin); las versiones anteriores las guardaban todas y se leen igual

local History = {}
ES.History = History

local HOUR = 3600
local MAX_GAP = 24 * HOUR     -- con más separación todas pudieron caducar: comparar no dice nada
local STUCK_BAND = 1.10       -- "las más baratas": hasta un 10% por encima del mínimo
-- (ES.db.track guarda solo estas: también dan la competencia de Market.lua, que mira
-- hasta su WALL_BAND, así que STUCK_BAND no puede ser menor; lo comprueba una prueba)
History.STUCK_BAND = STUCK_BAND
-- Lo que usan las alertas y la tendencia son 7 días: guardar más solo hace
-- crecer los datos guardados (~18 KB por escaneo) y alarga la carga del juego
local HISTORY_MAX_AGE = 7 * 86400
local HISTORY_MAX = 200
History.MAX = HISTORY_MAX -- (Keys.lua, al juntar el historial de dos claves)

-- Solo seguimos los objetos de profesiones (materiales, fabricados, pergaminos)
-- para que los datos guardados no crezcan demasiado
local tracked
ES.MemPart("objetos de profesiones (los que sigue el historial)", function() return tracked end)

function History:IsTracked(itemID)
  -- (también lo que tienes en la cartera de inversiones: su escalera de precios da el
  -- precio del día sin que cuente una subasta suelta, Invest.lua)
  if ES.Invest and ES.Invest.IsTracked(itemID) then return true end
  if not tracked then
    tracked = {}
    for _, data in pairs(ES.Data) do
      if type(data) == "table" and data.recipes then
        for _, r in pairs(data.recipes) do
          for _, rq in ipairs(r.r) do tracked[rq[1]] = true end
          if r.out then tracked[r.out[1]] = true end
          if r.scroll then tracked[r.scroll] = true end
        end
      end
    end
  end
  return tracked[itemID]
end

-- Firma de una subasta: objeto, cantidad, precio de compra y vendedor ("?" si no se sabe).
-- Sin ":", ";" ni "=" en el vendedor: separan las firmas guardadas (History.Pack)
function History.Signature(itemID, count, buyout, owner)
  owner = owner and (tostring(owner):gsub("[:;=]", "?")) or "?"
  return itemID .. ":" .. count .. ":" .. (buyout or 0) .. ":" .. owner
end

-- Por cada firma guardamos cuántas subastas hay en cada categoría de tiempo
-- restante (1 corto .. 4 muy largo), empaquetado en un número: c1 + c2*1e3 + c3*1e6 + c4*1e9
local BASE = { 1, 1e3, 1e6, 1e9 }
local MAX_PER_BUCKET = 999 -- más desbordaría a la categoría siguiente

function History.AddAuction(sigs, sig, timeLeft)
  local bucket = (timeLeft >= 1 and timeLeft <= 4) and timeLeft or 1 -- desconocido: lo tratamos como corto
  local packed = sigs[sig] or 0
  local inBucket = math.floor(packed / BASE[bucket]) % 1000
  if inBucket < MAX_PER_BUCKET then
    sigs[sig] = packed + BASE[bucket]
  end
end

function History.Unpack(packed)
  local counts, total = {}, 0
  for b = 4, 1, -1 do
    counts[b] = math.floor(packed / BASE[b])
    packed = packed - counts[b] * BASE[b]
    total = total + counts[b]
  end
  return counts, total
end

-- Lo mismo que Unpack, sin crear la tabla: las de "muy largo" (4) y el total
local function LongAndTotal(packed)
  local total, long = 0, 0
  for b = 4, 1, -1 do
    local c = math.floor(packed / BASE[b])
    packed = packed - c * BASE[b]
    total = total + c
    if b == 4 then long = c end
  end
  return long, total
end
-- Cuántas subastas hay en total en el número empaquetado (sin crear tablas)
function History.Total(packed)
  local _, total = LongAndTotal(packed)
  return total
end

-- Las subastas de un escaneo ([firma] = número) en una sola cadena, como se guardan
-- (v = 3): ";firma=número;firma=número...". El número cabe sin exponente: como mucho
-- 999.999.999.999 (AddAuction). Por bloques y sin una cadena "firma=número" por
-- subasta: con una tabla de todas, juntarla dejaba varias veces su tamaño en basura
local PACK_BLOCK = 512
function History.Pack(sigs)
  local parts, blocks, n = {}, {}, 0
  for sig, packed in pairs(sigs) do
    parts[n + 1], parts[n + 2], parts[n + 3], parts[n + 4] = ";", sig, "=", packed
    n = n + 4
    if n >= PACK_BLOCK then
      blocks[#blocks + 1] = table.concat(parts, "", 1, n)
      n = 0
    end
  end
  if n > 0 then blocks[#blocks + 1] = table.concat(parts, "", 1, n) end
  if #blocks == 0 then return ";" end
  return table.concat(blocks)
end

-- Objeto, cantidad y precio de compra de una firma (números), o nil sin precio de compra
local function SigPrice(sig)
  local item, count, buyout = sig:match("^(%d+):(%d+):(%d+):")
  count, buyout = tonumber(count), tonumber(buyout)
  if not (buyout and buyout > 0 and count and count > 0) then return nil end
  return tonumber(item), count, buyout
end

-- De las subastas de un escaneo ([firma] = número), solo las que se leen después: las
-- de precio por unidad hasta STUCK_BAND sobre el mínimo de su objeto (las "baratas" que
-- se comparan con el escaneo siguiente y la competencia). Las demás y las de solo puja
-- no las mira nadie: guardarlas eran ~2,4 MB y ~30 MB de basura en cada escaneo
-- `mins`: { [itemID] = precio por unidad más bajo } si ya se sabe (el escaneo lo lleva:
-- el mismo número que saldría de las firmas); si no, se calcula de las firmas
function History.NearMin(sigs, mins)
  local min = mins
  if not min then
    min = {}
    for sig in pairs(sigs) do
      local item, count, buyout = SigPrice(sig)
      if item and (not min[item] or buyout / count < min[item]) then min[item] = buyout / count end
    end
  end
  local out = {}
  for sig, packed in pairs(sigs) do
    local item, count, buyout = SigPrice(sig)
    if item and min[item] and buyout / count <= min[item] * STUCK_BAND then out[sig] = packed end
  end
  return out
end

-- Hasta qué precio por unidad mira History:Record, por objeto, las subastas del
-- escaneo anterior (`track`): { [itemID] = precio }. Al leer un escaneo nuevo, las
-- subastas más caras que eso y que tampoco pueden quedar cerca del mínimo nuevo no
-- necesitan firma (Scanner:Process)
function History.PrevReach(track)
  local min, reach = {}, {}
  History.EachPrice(track, function(item, count, buyout)
    if buyout > 0 and count > 0 and (not min[item] or buyout / count < min[item]) then min[item] = buyout / count end
  end)
  History.EachPrice(track, function(item, count, buyout)
    if buyout > 0 and count > 0 then
      local unit = buyout / count
      if unit <= min[item] * STUCK_BAND and (not reach[item] or unit > reach[item]) then reach[item] = unit end
    end
  end)
  return reach
end

-- Recorre las subastas del último escaneo de un reino (ES.db.track[reino]):
-- fn(firma, número empaquetado). Entiende los dos formatos guardados:
--   v = 3: packed = ";firma=número;firma=número..." (una sola cadena)
--   antes: sigs = { [firma] = número } (una clave por firma: ~5 MB con 60.000)
function History.EachSig(track, fn)
  if type(track) ~= "table" then return end
  if type(track.packed) == "string" then
    for sig, packed in track.packed:gmatch(";([^;=]+)=(%d+)") do fn(sig, tonumber(packed)) end
  elseif type(track.sigs) == "table" then
    for sig, packed in pairs(track.sigs) do fn(sig, tonumber(packed) or 0) end
  end
end

-- Como EachSig, pero da los números de la firma sin crearla: fn(objeto, cantidad,
-- precio de compra, número empaquetado). Recorrer la cadena firma a firma dejaba una
-- cadena por subasta más sus partes (Market: la competencia, en cada escaneo)
function History.EachPrice(track, fn)
  if type(track) ~= "table" then return end
  if type(track.packed) == "string" then
    for item, count, buyout, packed in track.packed:gmatch(";(%d+):(%d+):(%d+):[^;=]*=(%d+)") do
      fn(tonumber(item), tonumber(count), tonumber(buyout), tonumber(packed))
    end
  elseif type(track.sigs) == "table" then
    for sig, packed in pairs(track.sigs) do
      local item, count, buyout = sig:match("^(%d+):(%d+):(%d+):")
      if item then fn(tonumber(item), tonumber(count), tonumber(buyout), tonumber(packed) or 0) end
    end
  end
end

-- Entradas del historial de un reino (de la más antigua a la más nueva)
function History:Entries(key)
  key = key or ES:RealmKey()
  ES.db.history = ES.db.history or {}
  local history = ES.db.history[key]
  if not history then
    history = {}
    -- (con la clave provisional, mientras el juego no da el modo, Keys.lua: leer no crea
    -- nada; lo que se escriba sí, y pasa a la clave buena al llegar)
    if ES.Keys.IsPending(key) then return history end
    ES.db.history[key] = history
  end
  if not ES.db.historyCleaned then
    -- Versiones anteriores estimaban ventas: se borran esos datos (no eran fiables)
    for _, h in pairs(ES.db.history) do
      for _, e in ipairs(h) do e.sold, e.cancelled, e.expired, e.bulk, e.v = nil, nil, nil, nil, nil end
    end
    ES.db.sales = nil
    ES.db.historyCleaned = true
  end
  return history
end

local function Prune(history, now)
  while #history > 0 and (now - history[1].time > HISTORY_MAX_AGE or #history > HISTORY_MAX) do
    table.remove(history, 1)
  end
end

-- Guarda un escaneo. sigs: [firma] = subastas por categoría de tiempo restante
-- (ver AddAuction); snap: foto de precios. Devuelve los segundos desde el
-- escaneo anterior si se pudo comparar, o nil. `mins` (opcional): el precio por unidad
-- más bajo de cada objeto en este escaneo (History.NearMin)
function History:Record(key, sigs, snap, now, mins)
  ES.db.track = ES.db.track or {}
  local history = self:Entries(key)
  local prev = ES.db.track[key]
  -- (empaquetadas en una cadena: una tabla con una clave por firma ocupaba ~5 MB; y
  -- solo las cercanas al mínimo, las únicas que se leen: History.NearMin)
  ES.db.track[key] = { time = now, packed = History.Pack(History.NearMin(sigs, mins)), v = 3 }
  if prev and prev.v ~= 2 and prev.v ~= 3 then prev = nil end -- formato antiguo: no comparable

  local entry = { time = now, elapsed = 0, snap = snap }
  local elapsed = prev and (now - prev.time) or 0
  if prev and elapsed > 0 and elapsed <= MAX_GAP then
    -- Precio por unidad más barato de cada objeto en el escaneo anterior
    local minUnit = {}
    History.EachSig(prev, function(sig)
      local item, count, buyout = sig:match("^(%d+):(%d+):(%d+):")
      count, buyout = tonumber(count), tonumber(buyout)
      if buyout > 0 and count > 0 and (not minUnit[item] or buyout / count < minUnit[item]) then
        minUnit[item] = buyout / count
      end
    end)
    -- De las más baratas, cuántas siguen. Las que siguen no se han vendido; las
    -- que faltan pudieron venderse, caducar o retirarse (no se cuentan como nada)
    local rem, tot = {}, {}
    History.EachSig(prev, function(sig, packed)
      local item, count, buyout = sig:match("^(%d+):(%d+):(%d+):")
      count, buyout = tonumber(count), tonumber(buyout)
      if buyout > 0 and count > 0 and buyout / count <= minUnit[item] * STUCK_BAND then
        local prevLong, prevTotal = LongAndTotal(packed)
        local remaining = 0
        if sigs[sig] then
          -- Descontar las nuevas con la misma firma: sobran en total o en "muy
          -- largo" (el tiempo restante nunca sube)
          local nowLong, nowTotal = LongAndTotal(sigs[sig])
          local new = math.max(0, nowTotal - prevTotal, nowLong - prevLong)
          remaining = math.min(prevTotal, nowTotal - new)
        end
        tot[item] = (tot[item] or 0) + prevTotal
        rem[item] = (rem[item] or 0) + remaining
      end
    end)
    local parts = {}
    for item, n in pairs(tot) do parts[#parts + 1] = item .. ":" .. rem[item] .. ":" .. n end
    entry.stuck = ";" .. table.concat(parts, ";")
    entry.elapsed = elapsed
  end

  history[#history + 1] = entry
  Prune(history, now)
  return entry.elapsed > 0 and elapsed or nil
end

-- Escaneos guardados, comparaciones hechas y hora del primero
function History:Summary()
  local history = self:Entries()
  local comparisons = 0
  for _, entry in ipairs(history) do
    if entry.elapsed and entry.elapsed > 0 then comparisons = comparisons + 1 end
  end
  return #history, comparisons, history[1] and history[1].time
end

---------------------------------------------------------------------------
-- Señales de riesgo de un precio (sin necesidad de historial)
---------------------------------------------------------------------------
local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Lo que paga el vendedor: lo que dice el juego ahora (siempre al día: Forever cambia
-- precios, Bronze Dory pasó de 32s 53c a 4s 88c); si el juego aún no ha cargado el
-- objeto, se le pide y mientras vale el de los datos. Ya no se "aprende" de tus
-- ventas (Ledger.lua): adivinaba mal con dos ventas cobradas juntas
-- Objetos ya pedidos al juego en esta sesión: el cálculo de una ruta pregunta miles
-- de veces por los mismos (14.000 en Peletería de 88 a 300); basta con pedirlo una vez
local requested = {}
function ES:VendorSellPrice(itemID)
  local _, _, _, _, _, _, _, _, _, _, live = GetItemInfoCompat(itemID) -- (el 11.º: sin select, lo llama la ruta miles de veces)
  if live then return live end
  if not requested[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
    requested[itemID] = true
    pcall(C_Item.RequestLoadItemDataByID, itemID)
  end
  return ES.Data.SellPrices[itemID]
end

-- ¿El precio de venta es el de ahora (dado por el juego)? Si no, es el de los datos
-- y la ruta se recalcula cuando el juego cargue el objeto
function ES:SellPriceIsLive(itemID)
  return select(11, GetItemInfoCompat(itemID)) ~= nil
end

-- Devuelve un texto con los motivos si el precio de la AH parece poco fiable
function ES:PriceRisk(itemID, entry)
  if not entry or not entry.minUnit then return nil end
  local reasons = {}
  if (entry.listings or 0) >= 5 and entry.topShare and entry.topShare >= 0.6 then
    reasons[#reasons + 1] = string.format(L["un vendedor tiene el %d%% de las subastas"], math.floor(entry.topShare * 100 + 0.5))
  end
  local vendor = self:VendorSellPrice(itemID)
  if vendor and vendor > 0 and entry.minUnit > 5 * vendor then
    reasons[#reasons + 1] = string.format(L["se pide %dx su precio de vendedor"], math.floor(entry.minUnit / vendor))
  end
  if #reasons == 0 then return nil end
  return table.concat(reasons, "; ")
end
