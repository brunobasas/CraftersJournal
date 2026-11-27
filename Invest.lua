local _, ES = ...

---------------------------------------------------------------------------
-- Cartera de inversiones (pestaña Inversiones, InvestUI.lua): las compras y ventas
-- que apuntas a mano, y lo que salen con el precio de Auctionator (PriceHistory.lua).
--
-- Solo se guardan los movimientos; todo lo demás se calcula al leerlos (borrar uno
-- equivocado deja los números bien sin más). Método del precio medio: vender no
-- cambia la media de lo que queda; lo vendido cuenta como beneficio realizado, neto
-- de la comisión de la AH.
--
-- La cartera es de la CUENTA: la comparten todos tus personajes (a diferencia de las
-- rutas de las profesiones, que son de cada uno). Va por ruleset y bando, como la AH
-- (ES:RealmKey, Keys.lua).
-- ES.db.invest = { account = { [RealmKey] = cartera } }
-- (una versión de desarrollo tuvo también carteras por personaje, invest.chars: no se
-- leen)
-- cartera = { [itemID] = { moves = { { t, kind = "buy"|"sell", n, unit, total? }, ... } } }
--   unit: cobre por unidad; total: el total escrito (si se escribió así), que manda
---------------------------------------------------------------------------
local Invest = {}
ES.Invest = Invest

Invest.AH_CUT = 0.05 -- comisión de la AH de tu facción al vender

-- Icono de la pestaña: la bolsa de oro con gráfica si el cliente la trae (es de
-- Cataclysm: puede no estar en Forever); si no, la caja con cerradura
local CASHFLOW = "Interface\\Icons\\Achievement_GuildPerk_CashFlow"
local function HasFile(path)
  if not GetFileIDFromPath then return false end
  local ok, id = pcall(GetFileIDFromPath, path)
  return ok and id ~= nil
end
Invest.ICON = HasFile(CASHFLOW) and CASHFLOW or "Interface\\Icons\\INV_Box_02"

local function Table(t, k)
  if type(t[k]) ~= "table" then t[k] = {} end
  return t[k]
end

-- La cartera de la cuenta para este reino y facción
function Invest.Book()
  return Table(Table(Table(ES.db, "invest"), "account"), ES:RealmKey())
end

-- Cantidad escrita: entero mayor que 0, o nil
function Invest.ParseQty(text)
  local n = tonumber(strtrim(tostring(text or "")))
  if n and n > 0 and n == math.floor(n) and n < 1e7 then return n end
end

-- Cobre por unidad de una línea (unit, o total / n si se escribió el total)
local function Amount(m) return m.total or m.n * m.unit end

-- Lo que sale de unos movimientos con un precio de ahora (o sin él):
--   units, cost (de lo que tienes), avg, realized (neto de la comisión), sold, bought,
--   closed (vendido todo), broken (una venta de más unidades de las que había),
--   farmed (lo que tienes costó 0: apuntado a precio 0),
--   y con precio: price, value, cut, net, latent, latentPct, changePct
function Invest.Compute(moves, price)
  local units, cost, realized, sold, bought = 0, 0, 0, 0, 0
  local broken = false
  for _, m in ipairs(moves or {}) do
    local amount = Amount(m)
    if m.kind == "sell" then
      if m.n > units then
        broken = true
      else
        local avg = cost / units
        realized = realized + amount * (1 - Invest.AH_CUT) - m.n * avg
        cost = cost - m.n * avg
        units = units - m.n
        sold = sold + m.n
        if units == 0 then cost = 0 end -- (sin restos de redondeo)
      end
    else
      cost = cost + amount
      units = units + m.n
      bought = bought + m.n
    end
  end
  local r = { units = units, cost = cost, realized = realized, sold = sold, bought = bought,
    avg = units > 0 and cost / units or nil, broken = broken,
    closed = not broken and units == 0 and bought > 0 }
  -- Lo que tienes no te costó nada (apuntado a precio 0: farmeado): sin % desde tu media
  r.farmed = not broken and units > 0 and cost < 0.5 or nil
  if price and units > 0 and not broken then
    r.price = price
    r.value = units * price
    r.cut = r.value * Invest.AH_CUT
    r.net = r.value - r.cut
    r.latent = r.net - cost
    r.latentPct = cost > 0 and r.latent / cost or nil
    r.changePct = r.avg and r.avg > 0 and (price / r.avg - 1) or nil
  end
  return r
end

-- Un movimiento nuevo con lo escrito, o nil y por qué ("qty", "price")
local function MakeMove(kind, n, price, isTotal, t)
  n = Invest.ParseQty(n)
  if not n then return nil, "qty" end
  price = tonumber(price)
  if not price or price < 0 or price ~= price or price == math.huge then return nil, "price" end
  local move = { t = t or time(), kind = kind == "sell" and "sell" or "buy", n = n }
  if isTotal then
    move.total = math.floor(price + 0.5)
    move.unit = math.floor(price / n + 0.5)
  else
    move.unit = math.floor(price + 0.5)
  end
  return move
end

-- Apunta una compra o venta. price: cobre (por unidad, o el total si isTotal).
-- Devuelve true, o false y por qué: "qty", "price", "units" (venta de más; y cuántas hay)
function Invest:Add(itemID, kind, n, price, isTotal)
  if type(itemID) ~= "number" then return false, "item" end
  local move, why = MakeMove(kind, n, price, isTotal)
  if not move then return false, why end
  local book = Invest.Book()
  local entry = book[itemID]
  if move.kind == "sell" then
    local have = entry and Invest.Compute(entry.moves).units or 0
    if move.n > have then return false, "units", have end
  end
  entry = entry or { moves = {} }
  book[itemID] = entry
  if type(entry.moves) ~= "table" then entry.moves = {} end
  entry.moves[#entry.moves + 1] = move
  Invest.Dirty()
  return true
end

-- Cambia la cantidad y el precio del movimiento i de un objeto (sigue siendo compra o
-- venta, con su fecha). Mismos motivos que Add; además, si el cambio deja una venta de
-- más unidades de las que había (y antes cuadraba): "units" y cuántas había para esa
-- venta (si es esta venta la que no cuadra) o "breaks" (una venta de después no cuadra)
function Invest:Update(itemID, i, n, price, isTotal)
  local entry = Invest.Book()[itemID]
  local old = entry and type(entry.moves) == "table" and entry.moves[i]
  if not old then return false, "item" end
  local move, why = MakeMove(old.kind, n, price, isTotal, old.t)
  if not move then return false, why end
  local moves = {}
  for k, m in ipairs(entry.moves) do moves[k] = k == i and move or m end
  if Invest.Compute(moves).broken and not Invest.Compute(entry.moves).broken then
    if move.kind == "sell" then
      local before = {}
      for k = 1, i - 1 do before[k] = entry.moves[k] end
      local have = Invest.Compute(before).units
      if move.n > have then return false, "units", have end
    end
    return false, "breaks"
  end
  entry.moves[i] = move
  Invest.Dirty()
  return true
end

-- Borra el movimiento i de un objeto (sin movimientos, el objeto sale de la cartera)
function Invest:Remove(itemID, i)
  local book = Invest.Book()
  local entry = book[itemID]
  if not entry or type(entry.moves) ~= "table" or not entry.moves[i] then return false end
  table.remove(entry.moves, i)
  if #entry.moves == 0 then book[itemID] = nil end
  Invest.Dirty()
  return true
end

---------------------------------------------------------------------------
-- Precios por día de tus escaneos (solo se usan en modo Crafter's Journal: PriceHistory.lua)
--
-- Al acabar cada escaneo del addon se apunta, por cada objeto que sigue el escaneo (los
-- de profesiones y los de alguna cartera de este reino, History:IsTracked), el precio de
-- ese día: el de la escalera donde hay "suficientes" unidades (así una subasta suelta muy
-- barata no cuenta), y si ese día se escanea más de una vez, el del último escaneo. Así,
-- un objeto que entra en la cartera ya trae sus días.
-- ES.db.investPrices[RealmKey][itemID] = "día:precio;día:precio..." (los últimos
-- PRICE_DAYS días, como el historial de Auctionator por defecto; los días, desde 1970:
-- siempre positivos). Se apuntan también en el modo Auctionator (del escaneo que lee el
-- addon, con su forma de medir el precio), por si un día pasas al de Crafter's Journal.
-- Son ~2.150 objetos por escaneo: una cadena por objeto, no una tabla por día
---------------------------------------------------------------------------
Invest.PRICE_DAYS = 21
Invest.DAY0 = 0
local DAY = 86400
function Invest.Day(t) return math.floor(((t or time()) - Invest.DAY0) / DAY) end
function Invest.DayTime(day) return Invest.DAY0 + day * DAY + DAY / 2 end

-- Objetos de todas las carteras de este reino (de la cuenta y de cada personaje): los
-- que el escaneo sigue (su escalera de precios) y de los que guarda el precio del día
-- (se llama por cada subasta del escaneo: la caché solo se rehace si cambia la cartera
-- o lo guardado; si cambia la clave de la AH, Keys.lua llama a Invest.Dirty)
local trackedSet, trackedDb
function Invest.Dirty() trackedSet = nil end
function Invest.Tracked()
  if trackedSet and trackedDb == ES.db then return trackedSet end
  local realm = ES.db and ES:RealmKey()
  trackedSet, trackedDb = {}, ES.db
  local inv = ES.db and type(ES.db.invest) == "table" and ES.db.invest
  if not inv then return trackedSet end
  local function From(book)
    if type(book) ~= "table" then return end
    for id, e in pairs(book) do
      if type(id) == "number" and type(e) == "table" then trackedSet[id] = true end
    end
  end
  if type(inv.account) == "table" then From(inv.account[realm]) end
  if type(inv.chars) == "table" then
    for _, c in pairs(inv.chars) do if type(c) == "table" then From(c[realm]) end end
  end
  return trackedSet
end
function Invest.IsTracked(itemID) return Invest.Tracked()[itemID] == true end

-- Precio del día de un objeto en un escaneo: donde la escalera reúne el 5 % de las
-- unidades a la venta (al menos 1, como mucho 5: con más, un mercado con pocas
-- unidades baratas daba un precio demasiado alto); sin escalera, el mínimo
Invest.SCAN_DEPTH = 5
function Invest.ScanPrice(entry)
  if type(entry) ~= "table" then return nil end
  local l = entry.ladder
  if type(l) == "table" and #l >= 2 then
    local total = 0
    for i = 2, #l, 2 do total = total + (tonumber(l[i]) or 0) end
    local need = math.max(1, math.min(Invest.SCAN_DEPTH, math.ceil(total * 0.05)))
    local acc = 0
    for i = 1, #l - 1, 2 do
      acc = acc + (tonumber(l[i + 1]) or 0)
      if acc >= need then return tonumber(l[i]) end
    end
  end
  local min = tonumber(entry.minUnit)
  return min and math.floor(min + 0.5) or nil
end

local function ParseDays(s)
  local map = {}
  if type(s) ~= "string" then return map end
  for day, price in s:gmatch("(%d+):(%d+)") do map[tonumber(day)] = tonumber(price) end
  return map
end

local function PackDays(map, today)
  local days = {}
  for day in pairs(map) do if day > today - Invest.PRICE_DAYS then days[#days + 1] = day end end
  table.sort(days)
  local parts = {}
  for _, day in ipairs(days) do parts[#parts + 1] = day .. ":" .. map[day] end
  return table.concat(parts, ";")
end

-- El precio `p` del día `today` en los días guardados `s`, sin tablas: lo de siempre (un
-- día nuevo, o otro escaneo el mismo día que el último) es añadir o cambiar el final y
-- quitar del principio lo de hace PRICE_DAYS días o más. nil si `s` tiene un día
-- posterior a `today` (un escaneo de otro día apuntado tarde): entonces, PackDays
local function AppendDay(s, today, p)
  if type(s) ~= "string" or s == "" then return today .. ":" .. p end
  -- (el último día: con ".*" delante el patrón va directo al último ";"; sin él, se
  -- probaba en cada posición de la cadena: ~60 ms por escaneo con 2.150 objetos)
  local head, lastDay = s:match("^(.*);(%d+):%d+$")
  if not lastDay then lastDay = s:match("^(%d+):%d+$") end
  local last = tonumber(lastDay)
  if not last or last > today then return nil end
  if last == today then
    s = head and (head .. ";" .. today .. ":" .. p) or (today .. ":" .. p)
  else
    s = s .. ";" .. today .. ":" .. p
  end
  local limit = today - Invest.PRICE_DAYS
  while true do
    local day, rest = s:match("^(%d+):%d+;(.*)$")
    if not day or tonumber(day) > limit then break end
    s = rest
  end
  return s
end

-- Apunta los precios de un escaneo
function Invest.RecordScan(scan)
  Invest.CommitScan(Invest.PrepareScan(scan))
end

-- Los precios de un escaneo, sin apuntarlos todavía: { [itemID] = días empaquetados },
-- o nil. Al guardar un escaneo (Scanner:WriteScan) se calcula repartido entre
-- fotogramas y se apunta con el resto de una vez (Invest.CommitScan): si el guardado se
-- corta a medias, no queda nada a medio escribir
function Invest.PrepareScan(scan)
  if type(scan) ~= "table" or type(scan.items) ~= "table" then return nil end
  local prices = ES.db.investPrices
  local root = prices and prices[ES:RealmKey()] or {}
  local today = Invest.Day(scan.time)
  local History = ES.History
  -- (al guardar un escaneo, cede el fotograma si se ha acabado: Scanner:Save)
  local Yield = ES.ScanYield or function() end
  local out = {}
  for id, entry in pairs(scan.items) do
    Yield()
    if History:IsTracked(id) then
      local p = Invest.ScanPrice(entry)
      if p and p > 0 then
        -- (el último escaneo del día: es el precio de ahora, y un escaneo raro se corrige
        -- con el siguiente. Con "el más alto del día", un escaneo con pocas unidades baratas
        -- dejaba todo el día un precio disparado: Small Flame Sac a 1g en vez de 12s)
        local s = AppendDay(root[id], today, p)
        if not s then
          local map = ParseDays(root[id])
          map[today] = p
          s = PackDays(map, today)
        end
        out[id] = s
      end
    end
  end
  return out
end

-- Apunta lo que calculó Invest.PrepareScan
function Invest.CommitScan(days)
  if not days then return end
  local root = Table(Table(ES.db, "investPrices"), ES:RealmKey())
  for id, s in pairs(days) do root[id] = s end
  if ES.PriceHistory then ES.PriceHistory.Clear() end
  if ES.RenderInvest then ES:RenderInvest() ES:RenderInvestItem() end -- (si se ven)
end

-- Días con precio de tus escaneos de un objeto: { { day, price, time } } (del más
-- antiguo al más reciente). Solo lo apuntado al escanear: rellenar con el historial
-- interno del addon (el mínimo bruto de cada escaneo) daba precios que no cuadraban
function Invest.OwnDays(itemID)
  local prices = ES.db and type(ES.db.investPrices) == "table" and ES.db.investPrices[ES:RealmKey()]
  local map = ParseDays(type(prices) == "table" and prices[itemID])
  local today = Invest.Day()
  local out = {}
  for day, price in pairs(map) do
    if day > today - Invest.PRICE_DAYS then out[#out + 1] = { day = day, price = price, time = Invest.DayTime(day) } end
  end
  table.sort(out, function(a, b) return a.day < b.day end)
  return out
end

-- Un objeto de la cartera con su precio (PriceHistory): Compute + itemID, moves, history
function Invest:Item(itemID)
  local entry = Invest.Book()[itemID]
  local moves = entry and type(entry.moves) == "table" and entry.moves or {}
  local history = ES.PriceHistory:Get(itemID)
  local r = Invest.Compute(moves, history and history.now.price)
  r.itemID, r.moves, r.history = itemID, moves, history
  r.stale = history and history.now.stale or false
  return r
end

-- Toda la cartera: { open = { ... }, closed = { ... }, broken = { ... }, totals }
-- totals = { cost, value, net, cut, latent, latentPct, realized, priced, missing }
--   cost: lo invertido en lo que tienes; value/net/latent: solo lo que tiene precio
function Invest:Summary()
  local open, closed, broken = {}, {}, {}
  local t = { cost = 0, costPriced = 0, value = 0, net = 0, cut = 0, latent = 0, realized = 0, priced = 0, missing = 0 }
  for itemID in pairs(Invest.Book()) do
    if type(itemID) == "number" then
      local e = self:Item(itemID)
      if e.broken then
        broken[#broken + 1] = e
      elseif e.closed then
        closed[#closed + 1] = e
        t.realized = t.realized + e.realized
      elseif e.units > 0 then
        open[#open + 1] = e
        t.cost = t.cost + e.cost
        t.realized = t.realized + e.realized
        if e.value then
          t.priced = t.priced + 1
          t.costPriced = t.costPriced + e.cost
          t.value, t.net, t.cut, t.latent = t.value + e.value, t.net + e.net, t.cut + e.cut, t.latent + e.latent
        else
          t.missing = t.missing + 1
        end
      end
    end
  end
  t.latentPct = t.costPriced > 0 and t.latent / t.costPriced or nil
  -- Lo que más gana primero; sin precio, al final (por lo invertido)
  table.sort(open, function(a, b)
    if (a.latent ~= nil) ~= (b.latent ~= nil) then return a.latent ~= nil end
    if a.latent and a.latent ~= b.latent then return a.latent > b.latent end
    if a.cost ~= b.cost then return a.cost > b.cost end
    return a.itemID < b.itemID
  end)
  table.sort(closed, function(a, b)
    if a.realized ~= b.realized then return a.realized > b.realized end
    return a.itemID < b.itemID
  end)
  table.sort(broken, function(a, b) return a.itemID < b.itemID end)
  return { open = open, closed = closed, broken = broken, totals = t }
end
