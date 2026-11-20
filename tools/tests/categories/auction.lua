-- Casa de Subastas: escanear, precios, historial, compras y vender

local function OpenAH()
  AuctionFrame:Show()
  FireEvent("AUCTION_HOUSE_SHOW")
  RunTimers()
end

-- (el addon no escanea por su cuenta: Escanear lanza el escaneo de Auctionator y el
-- addon lee esas subastas, ver Scanner.lua)
test("escaneo completo: guarda el precio por unidad más bajo de cada objeto", function()
  InstallAuctionator()
  AUCTIONS = {
    { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 },  -- 25 c/u
    { item = 2318, count = 10, buyout = 300, owner = "Pepe", tl = 4 }, -- 30 c/u
    { item = 2589, count = 20, buyout = 400, owner = "Luis", tl = 3 }, -- 20 c/u
    { item = 2589, count = 1, buyout = 18, owner = "Ana", tl = 2 },    -- 18 c/u
  }
  OpenAH()
  ES.Scanner:Start()
  RunTimers()
  expect(not ES.Scanner:IsBusy(), "el escaneo no termina")
  local scan = expect(ES.db.scans[ES:RealmKey()], "no se guardó el escaneo")
  expect_eq(scan.items[2318].minUnit, 25, "Light Leather")
  expect_eq(scan.items[2589].minUnit, 18, "Linen Cloth")
  expect_eq(scan.items[2318].quantity, 15, "Light Leather a la venta")
  expect_eq(scan.items[2589].listings, 2, "subastas de Linen Cloth")
  expect_eq(scan.total, 4, "subastas leídas")
  OpenMain()
end, { state = "empty" })

test("el servidor devuelve 0 subastas: no se borra el escaneo bueno", function()
  InstallAuctionator()
  local before = ES.db.scans[ES:RealmKey()]
  AUCTIONS = {}
  OpenAH()
  ES.Scanner:Start()
  RunTimers()
  expect_eq(AUCTIONATOR_FULL_SCANS, 1, "escaneos de Auctionator lanzados")
  expect(ES.db.scans[ES:RealmKey()] == before, "el escaneo vacío sustituyó al bueno")
end, { state = "scan" })

test("no se escanea dos veces en 15 minutos", function()
  InstallAuctionator()
  AUCTIONS = { { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 } }
  OpenAH()
  ES.Scanner:Start()
  RunTimers()
  expect_eq(AUCTIONATOR_FULL_SCANS, 1, "primer escaneo")
  OpenMain()
  ES:RefreshScanButtons()
  expect(ES:GetMainFrame().scanButton._enabled == false, "el botón Escanear se puede pulsar antes de 15 min")
  ES.Scanner:Start()
  expect_eq(AUCTIONATOR_FULL_SCANS, 1, "pidió otra vez antes de 15 min")
  NOW = NOW + 16 * 60
  ES.Scanner:Start()
  expect_eq(AUCTIONATOR_FULL_SCANS, 2, "pasados 15 min no deja escanear")
  RunTimers()
end, { state = "empty" })

test("sin Auctionator, Escanear en gris, no pide nada y dice que lo instales", function()
  AUCTIONS = { { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 } }
  OpenAH()
  OpenMain()
  ES:RefreshScanButtons()
  expect(ES:GetMainFrame().scanButton._enabled == false, "el botón Escanear se puede pulsar sin Auctionator")
  local queried = false
  local saved = QueryAuctionItems
  QueryAuctionItems = function(...) queried = true return saved(...) end
  ES.Scanner:Start()
  RunTimers()
  QueryAuctionItems = saved
  expect(not queried, "el addon pidió su propio escaneo")
  expect(not ES.Scanner:IsBusy(), "se quedó escaneando")
  expect(ES.db.scans[ES:RealmKey()] == nil, "guardó un escaneo sin Auctionator")
  local msg = ES.L["Instala Auctionator para escanear la AH: el addon lee su escaneo completo."]
  expect(table.concat(PRINTS, "\n"):find(msg, 1, true), "el chat no dice que instales Auctionator")
  -- El tooltip del botón también lo dice
  local lines = {}
  local add = GameTooltip.AddLine
  GameTooltip.AddLine = function(_, text) lines[#lines + 1] = tostring(text) end
  ES:GetMainFrame().scanButton._scripts.OnEnter(ES:GetMainFrame().scanButton)
  GameTooltip.AddLine = add
  expect(table.concat(lines, "\n"):find(msg, 1, true), "el tooltip de Escanear no dice que instales Auctionator")
end, { state = "empty" })

test("con Auctionator sin su marco de escaneo aún: en gris y no se lanza nada", function()
  InstallAuctionator()
  Auctionator.State.FullScanFrameRef = nil -- (lo crea al abrirse la AH)
  OpenAH()
  OpenMain()
  ES:RefreshScanButtons()
  expect(ES:GetMainFrame().scanButton._enabled == false, "el botón Escanear se puede pulsar")
  ES.Scanner:Start()
  RunTimers()
  expect(not ES.Scanner:IsBusy(), "se quedó escaneando")
  expect(table.concat(PRINTS, "\n"):find(ES.L["Auctionator aún no está listo para escanear: espera un momento o vuelve a abrir la AH."], 1, true),
    "el chat no dice que espere a Auctionator")
end, { state = "empty" })

test("el escaneo automático de Auctionator se lee y pone la cuenta atrás", function()
  InstallAuctionator()
  AUCTIONS = { { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 } }
  OpenAH()
  local printed = #PRINTS
  -- Auctionator lo pide por su cuenta al abrir la AH (el gancho de QueryAuctionItems)
  QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
  ES.Scanner:OnForeignScan("legacy")
  expect(ES.Scanner:IsBusy(), "no sigue el escaneo de Auctionator")
  RunTimers()
  local scan = expect(ES.db.scans[ES:RealmKey()], "no se guardó el escaneo")
  expect_eq(scan.items[2318].minUnit, 25, "Light Leather")
  expect(ES.Scanner:SecondsUntilNextScan() > 0, "no cuenta para el límite de 15 min")
  for i = printed + 1, #PRINTS do
    expect(not PRINTS[i]:find(ES.L["Escaneo completado: %d subastas, %d objetos distintos."]:sub(1, 10), 1, true),
      "el escaneo automático escribió en el chat: %s", PRINTS[i])
  end
end, { state = "empty" })

test("con Auctionator, si el servidor no responde en 2 min se deja de esperar", function()
  InstallAuctionator()
  AUCTIONS = { { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 } }
  AH_RESPONDS = false
  OpenAH()
  ES.Scanner:Start()
  expect(ES.Scanner:IsBusy(), "no espera el escaneo de Auctionator")
  RunTimers(60)
  expect(ES.Scanner:IsBusy(), "a los 60 s ya no espera (los reinos llenos tardan)")
  RunTimers(70)
  AH_RESPONDS = true
  expect(not ES.Scanner:IsBusy(), "sigue esperando sin respuesta")
  expect(ES:LastScanFail(), "no avisa junto al último escaneo")
  expect(ES.Scanner:SecondsUntilNextScan() > 0, "sin cuenta atrás tras no responder")
  expect(ES.db.scans[ES:RealmKey()] == nil, "guardó un escaneo sin respuesta")
end, { state = "empty" })

test("con Auctionator, Escanear lanza su escaneo y el addon lo lee para todas las pestañas", function()
  InstallAuctionator()
  AUCTIONS = {
    { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 },
    { item = 2589, count = 20, buyout = 400, owner = "Luis", tl = 3 },
  }
  OpenAH()
  local own = 0
  local saved = QueryAuctionItems
  QueryAuctionItems = function(...) if not AUCTIONATOR_FULL_SCANS then own = own + 1 end return saved(...) end
  ES.Scanner:Start()
  expect_eq(AUCTIONATOR_FULL_SCANS, 1, "escaneos de Auctionator lanzados")
  expect_eq(own, 0, "el addon pidió su propio escaneo además del de Auctionator")
  RunTimers()
  QueryAuctionItems = saved
  expect(not ES.Scanner:IsBusy(), "no termina de leer el escaneo de Auctionator")
  local scan = expect(ES.db.scans[ES:RealmKey()], "no se guardó el escaneo")
  expect_eq(scan.items[2318].minUnit, 25, "Light Leather, del escaneo de Auctionator")
  expect(table.concat(PRINTS, "\n"):find(ES.L[" (con el escaneo de Auctionator)"], 1, true), "el chat no dice que fue con Auctionator")
  -- Y cuenta para el límite de 15 min
  expect(ES.Scanner:SecondsUntilNextScan() > 0, "el escaneo de Auctionator no cuenta para el límite")
end, { state = "empty" })

test("con Auctionator, Escanear en gris si Auctionator aún no deja otro escaneo", function()
  InstallAuctionator()
  AUCTIONATOR_WAITING = true
  OpenAH()
  OpenMain()
  ES:RefreshScanButtons()
  expect(ES:GetMainFrame().scanButton._enabled == false, "el botón Escanear se puede pulsar")
  ES.Scanner:Start()
  expect_eq(AUCTIONATOR_FULL_SCANS, nil, "lanzó el escaneo de Auctionator sin poder")
  expect(not ES.Scanner:IsBusy(), "se quedó escaneando")
end, { state = "empty" })

test("historial: tres escaneos y lo que se vendió entre ellos", function()
  local n, comparisons = ES.History:Summary()
  expect_eq(n, 3, "escaneos en el historial")
  expect_eq(comparisons, 2, "comparaciones")
end, { state = "full" })

test("precio de mercado: con un escaneo, el más bajo", function()
  local fp = ES.Market:FairPrice(2318, 25)
  expect(fp and fp.price, "sin precio")
  expect_eq(fp.price, 25, "precio de Light Leather")
  local sig = ES.Market:Signals(2318)
  expect(sig and sig.verdict, "sin veredicto de mercado")
end, { state = "scan" })

test("una compra en la AH cuenta para la lista de compra", function()
  OpenAH()
  ES.ahOpen = true
  ERR_AUCTION_WON_S = "You won an auction for %s"
  local id, n = ES.Ledger.ParseAuctionWon("You won an auction for |cffffffff|Hitem:765::|h[Silverleaf]|h|rx21")
  expect(id == 765 and n == 21, "no lee el mensaje: %s %s", tostring(id), tostring(n))
  FireEvent("CHAT_MSG_SYSTEM", "You won an auction for |cffffffff|Hitem:765::|h[Silverleaf]|h|rx21")
  expect_eq(ES:HaveForShopping(765), 21, "comprado y aún en el correo")
  BAGS[765] = 21
  expect_eq(ES:HaveForShopping(765), 21, "recogido: no cuenta dos veces")
end, { state = "full" })

test("dos compras iguales seguidas cuentan las dos", function()
  OpenAH()
  ES.ahOpen = true
  ERR_AUCTION_WON_S = "You won an auction for %s"
  local msg = "You won an auction for |cffffffff|Hitem:765::|h[Silverleaf]|h|rx5"
  FireEvent("CHAT_MSG_SYSTEM", msg)
  NOW = NOW + 1
  FireEvent("CHAT_MSG_SYSTEM", msg)
  expect_eq(ES:HaveForShopping(765), 10, "dos compras de 5")
end, { state = "full" })

test("al abrir la AH: lista de compra y ventana de vender sin errores", function()
  BAGS[2589], BAGS[2318] = 40, 12
  OpenAH()
  if ES.AuctionSell and ES.AuctionSell.Refresh then ES.AuctionSell:Refresh() end
  local mini = ES.ShoppingMini and ES.ShoppingMini()
  note("lista de compra junto a la AH: %s", mini and tostring(mini:IsShown()) or "no hay")
  AuctionFrame:Hide()
  FireEvent("AUCTION_HOUSE_CLOSED")
  RunTimers()
  expect(not ES.ahOpen, "la AH sigue contando como abierta al cerrarla")
end, { state = "full" })

---------------------------------------------------------------------------
-- Índice de mercado (Market.lua): memoria y mismos resultados
---------------------------------------------------------------------------
-- Memoria de Lua ocupada (KB), tras recoger la basura
local function KB()
  collectgarbage("collect")
  collectgarbage("collect")
  return collectgarbage("count")
end

-- El índice, construido de golpe (sin debugprofilestop no se reparte entre fotogramas)
local function BuildIndexNow()
  local saved = debugprofilestop
  debugprofilestop = nil
  local idx = ES.Market:Index()
  debugprofilestop = saved
  return idx
end

-- Las señales como se calculaban antes (una fila por dato del historial), para
-- comprobar que el índice por objeto da exactamente lo mismo. Copia de Market.lua
-- antes de reduce-market-memory: no cambiarla al cambiar Market.lua
local Ref = {}
do
  local HOUR, DAY = 3600, 86400
  local WINDOW = 7 * DAY
  function Ref.Build()
    local now = time()
    local history = ES.History:Entries()
    local track = ES.db.track and ES.db.track[ES:RealmKey()]
    local idx = { points = {}, stuck = {}, offers = {} }
    for _, entry in ipairs(history) do
      if now - entry.time < WINDOW then
        if entry.snap then
          for id, m, l, q in entry.snap:gmatch(";(%d+):(%d+):(%d+):?%d*:?(%d*)") do
            id = tonumber(id)
            local list = idx.points[id] or {}
            idx.points[id] = list
            list[#list + 1] = { time = entry.time, min = tonumber(m), listings = tonumber(l), quantity = tonumber(q) }
          end
        end
        if entry.stuck and entry.elapsed and entry.elapsed >= 15 * 60 then
          for id, r, t in entry.stuck:gmatch(";(%d+):(%d+):(%d+)") do
            id = tonumber(id)
            local list = idx.stuck[id] or {}
            idx.stuck[id] = list
            list[#list + 1] = { entry.elapsed, tonumber(r), tonumber(t) }
          end
        end
      end
    end
    local function each(fn)
      if not track then return end
      if type(track.sigs) == "table" then
        for sig, packed in pairs(track.sigs) do fn(sig, tonumber(packed)) end
      elseif type(track.packed) == "string" then
        for sig, packed in track.packed:gmatch(";([^;=]+)=(%d+)") do fn(sig, tonumber(packed)) end
      end
    end
    each(function(sig, packed)
      local id, count, buyout = sig:match("^(%d+):(%d+):(%d+):")
      id, count, buyout = tonumber(id), tonumber(count), tonumber(buyout)
      if buyout > 0 and count > 0 then
        local _, k = ES.History.Unpack(packed)
        local list = idx.offers[id] or {}
        idx.offers[id] = list
        list[#list + 1] = { buyout / count, count, k }
      end
    end)
    return idx
  end
  function Ref.Stuck(idx, itemID)
    local hazard, exposure, hours, rem, tot = 0, 0, 0, 0, 0
    for _, c in ipairs(idx.stuck[itemID] or {}) do
      local r, t = c[2], c[3]
      if t > 0 then
        local h = c[1] / HOUR
        hazard = hazard + t * -math.log(math.max(r / t, 0.02))
        exposure = exposure + t * h
        hours = hours + h
        rem, tot = rem + r, tot + t
      end
    end
    if exposure < 24 or hours < 6 then return { known = false, rem = rem, tot = tot, hours = hours } end
    local life = hazard > 0 and exposure / hazard or math.huge
    return { known = true, flag = life >= 24, life = life, rem = rem, tot = tot, hours = hours }
  end
  function Ref.PriceStuck(points)
    if #points < 2 then return { known = false } end
    local last = points[#points]
    local since = last.time
    for i = #points - 1, 1, -1 do
      if math.abs(points[i].min - last.min) > last.min * 0.03 then break end
      since = points[i].time
    end
    local covered = (last.time - points[1].time) / DAY
    if covered < 0.5 then return { known = false } end
    local days = (last.time - since) / DAY
    return { known = true, flag = days >= 1, days = days, price = last.min }
  end
  function Ref.Supply(points)
    local last = points[#points]
    if not last or not last.quantity then return { known = false } end
    local old
    for i = #points - 1, 1, -1 do
      if points[i].quantity and last.time - points[i].time >= 20 * HOUR then old = points[i] break end
    end
    if not old then return { known = false } end
    local growth = (last.quantity - old.quantity) / math.max(old.quantity, 1)
    return { known = true, flag = growth >= 0.5 and last.quantity - old.quantity >= 10,
      from = old.quantity, to = last.quantity, growth = growth, hours = (last.time - old.time) / HOUR }
  end
  function Ref.Wall(idx, itemID)
    local offers = idx.offers[itemID]
    if not offers then return { known = false } end
    local min
    for _, o in ipairs(offers) do if not min or o[1] < min then min = o[1] end end
    local listings, units = 0, 0
    for _, o in ipairs(offers) do
      if o[1] <= min * 1.05 then listings, units = listings + o[3], units + o[2] * o[3] end
    end
    return { known = true, flag = listings >= 5, listings = listings, units = units, price = min }
  end
  function Ref.Reference(points)
    if not points or #points < 2 then return nil end
    local last = points[#points].time
    local byDay = {}
    for _, p in ipairs(points) do
      if p.time <= last - 6 * HOUR then
        local day = math.floor(p.time / DAY)
        if not byDay[day] or p.min < byDay[day] then byDay[day] = p.min end
      end
    end
    local days = {}
    for day in pairs(byDay) do days[#days + 1] = day end
    if #days == 0 then return nil end
    table.sort(days, function(a, b) return a > b end)
    local mins = {}
    for i = 1, math.min(3, #days) do mins[i] = byDay[days[i]] end
    table.sort(mins)
    local n = #mins
    local ref = n % 2 == 1 and mins[(n + 1) / 2] or (mins[n / 2] + mins[n / 2 + 1]) / 2
    return ref, n, math.floor(last / DAY) - days[1]
  end
end

-- ¿Iguales campo a campo? (exactos: también los decimales)
local function SameTable(a, b, what)
  for k, v in pairs(a) do
    if b[k] ~= v then error(string.format("%s.%s: antes %s, ahora %s", what, tostring(k), tostring(v), tostring(b[k])), 2) end
  end
  for k, v in pairs(b) do
    if a[k] == nil then error(string.format("%s.%s: antes nada, ahora %s", what, tostring(k), tostring(v)), 2) end
  end
end

-- Compara, objeto a objeto, las señales y el precio de referencia con los de antes
local function CompareWithReference(ids)
  local ref = Ref.Build()
  BuildIndexNow()
  local checked, known = 0, { stuck = 0, price = 0, supply = 0, wall = 0, ref = 0 }
  local all = {}
  for _, id in ipairs(ids) do all[#all + 1] = id end
  all[#all + 1] = 999999 -- (uno sin ningún dato)
  for _, id in ipairs(all) do
    local s = ES.Market:Signals(id)
    local points = ref.points[id] or {}
    local want = { stuck = Ref.Stuck(ref, id), price = Ref.PriceStuck(points), supply = Ref.Supply(points), wall = Ref.Wall(ref, id) }
    for k, w in pairs(want) do
      SameTable(w, s[k], id .. "." .. k)
      if w.known then known[k] = known[k] + 1 end
    end
    local r1, n1, a1 = Ref.Reference(ref.points[id])
    local r2, n2, a2 = ES.Market:ReferencePrice(id)
    expect(r1 == r2 and n1 == n2 and a1 == a2, "%d: referencia antes %s/%s/%s, ahora %s/%s/%s",
      id, tostring(r1), tostring(n1), tostring(a1), tostring(r2), tostring(n2), tostring(a2))
    if r1 then known.ref = known.ref + 1 end
    local cur = 100 + id % 300
    SameTable(ES.Market:FairPrice(id, cur), ES.Market:FairPrice(id, cur), id .. ".fair") -- (sin errores)
    checked = checked + 1
  end
  -- (que la prueba mire de verdad: hay objetos con cada señal conocida)
  for k, n in pairs(known) do expect(n > 0, "ningún objeto con %s conocido: la prueba no lo comprueba", k) end
  return checked, known
end

test("índice de mercado: mismas señales y referencia que recorriendo el historial", function()
  local ids = Fixtures.BigMarket(40, 300, 4000)
  local checked, known = CompareWithReference(ids)
  note("%d objetos; conocidos: estancado %d, clavado %d, oferta %d, competencia %d, referencia %d",
    checked, known.stuck, known.price, known.supply, known.wall, known.ref)
end)

test("índice de mercado: 60 escaneos de 2.000 objetos caben en 2 MB", function()
  Fixtures.BigMarket(60, 2000, 60000)
  local before = KB()
  local idx = BuildIndexNow()
  local used = (KB() - before) / 1024
  note("índice: %.2f MB", used)
  expect(idx and not idx.empty, "no se construyó el índice")
  expect(used <= 2, "el índice ocupa %.1f MB (tope 2 MB)", used)
end)

test("índice de mercado: más escaneos no lo agrandan", function()
  Fixtures.BigMarket(30, 1000, 10000)
  local before = KB()
  BuildIndexNow()
  local m30 = KB() - before
  Fixtures.BigMarket(60, 1000, 10000)
  before = KB()
  BuildIndexNow()
  local m60 = KB() - before + m30 -- (el nuevo sustituye al de 30)
  note("30 escaneos: %.2f MB; 60 escaneos: %.2f MB", m30 / 1024, m60 / 1024)
  expect(m60 <= m30 * 1.5, "con 60 escaneos ocupa %.1fx lo de 30 (tope 1,5x)", m60 / m30)
end)

---------------------------------------------------------------------------
-- Subastas del último escaneo (ES.db.track): empaquetadas en una cadena (v = 3)
---------------------------------------------------------------------------
-- [firma] = número, como las arma el escaneo: `n` subastas distintas
local function MakeSigs(n, offset)
  local S, t = ES.History, {}
  for i = 1, n do
    local id = 100001 + i % 400
    local count = 1 + i % 20
    S.AddAuction(t, S.Signature(id, count, count * (50 + (i + (offset or 0)) % 37), i % 7 == 0 and "Ana" or "?"), 1 + i % 4)
  end
  return t
end

-- Las partes de una cadena ";a;b;c" ordenadas (el orden de pairs no importa)
local function Parts(s)
  local t = {}
  for p in (s or ""):gmatch("[^;]+") do t[#t + 1] = p end
  table.sort(t)
  return table.concat(t, ";")
end

test("track: se lee igual en el formato antiguo (tabla) y en el nuevo (cadena)", function()
  local sigs = MakeSigs(500)
  local function Read(track)
    local got = {}
    ES.History.EachSig(track, function(sig, packed) got[sig] = packed end)
    return got
  end
  local old = Read({ time = NOW, sigs = sigs, v = 2 })
  local new = Read({ time = NOW, packed = ES.History.Pack(sigs), v = 3 })
  local n = 0
  for sig, packed in pairs(sigs) do
    n = n + 1
    expect_eq(old[sig], packed, "antiguo " .. sig)
    expect_eq(new[sig], packed, "nuevo " .. sig)
  end
  for sig in pairs(new) do expect(sigs[sig], "firma de más al leer la cadena: %s", sig) end
  note("%d firmas", n)
  -- (el vendedor no puede romper la cadena)
  expect_eq(ES.History.Signature(1, 2, 3, "a:b;c=d"), "1:2:3:a?b?c?d", "firma con separadores")
end)

test("track: dos escaneos dan la misma comparación con el formato antiguo y el nuevo", function()
  local key = ES:RealmKey()
  local first, second = MakeSigs(2000), MakeSigs(1500, 3)
  local t1, t2 = NOW - 3600, NOW
  -- Escaneo anterior guardado por la versión de antes (v = 2) y uno nuevo
  ES.db.history[key], ES.db.track = {}, { [key] = { time = t1, sigs = first, v = 2 } }
  local elapsedOld = ES.History:Record(key, second, ";1:1:1", t2)
  local entryOld = ES.db.history[key][1]
  local track = ES.db.track[key]
  expect_eq(track.v, 3, "tras el primer escaneo, el formato nuevo")
  expect(type(track.packed) == "string" and track.sigs == nil, "se guarda la cadena y no la tabla")
  -- Los dos escaneos con la versión nueva
  ES.db.history[key], ES.db.track = {}, {}
  ES.History:Record(key, first, ";1:1:1", t1)
  local elapsedNew = ES.History:Record(key, second, ";1:1:1", t2)
  local entryNew = ES.db.history[key][2]
  expect(entryOld.stuck and #entryOld.stuck > 10, "la comparación no tiene baratas que siguen")
  expect_eq(Parts(entryNew.stuck), Parts(entryOld.stuck), "baratas que siguen")
  expect_eq(elapsedNew, elapsedOld, "tiempo desde el anterior")
  expect_eq(entryNew.elapsed, 3600, "elapsed")
end)

test("track: con el formato antiguo guardado, la competencia no cambia", function()
  local ids = Fixtures.BigMarket(10, 200, 3000) -- (deja track en el formato antiguo)
  local key = ES:RealmKey()
  BuildIndexNow()
  local old = {}
  for _, id in ipairs(ids) do old[id] = ES.Market:Wall(id) end
  local sigs = ES.db.track[key].sigs
  ES.db.track[key] = { time = NOW, packed = ES.History.Pack(sigs), v = 3 }
  NOW = NOW + 1 -- (otra marca: el índice se rehace)
  ES.db.history[key][#ES.db.history[key]].time = NOW
  BuildIndexNow()
  local known = 0
  for _, id in ipairs(ids) do
    SameTable(old[id], ES.Market:Wall(id), id .. ".wall")
    if old[id].known then known = known + 1 end
  end
  expect(known > 0, "ningún objeto en la AH: la prueba no comprueba nada")
end)

test("track: 60.000 subastas ocupan la mitad o menos en una cadena", function()
  local before = KB()
  local sigs = MakeSigs(60000)
  local asTable = KB() - before
  local packed = ES.History.Pack(sigs)
  sigs = nil
  local asString = KB() - before
  note("tabla %.2f MB, cadena %.2f MB (%d bytes)", asTable / 1024, asString / 1024, #packed)
  expect(asString <= asTable / 2, "la cadena ocupa %.1f MB y la tabla %.1f MB", asString / 1024, asTable / 1024)
end)

test("AH neutral: sin soporte, sin errores", function()
  NPC_FACTION = nil
  OpenAH()
  expect(ES.neutralAH, "no detecta la neutral")
  expect(not ES.ahOpen, "la neutral cuenta como AH abierta")
  NPC_FACTION = "Alliance"
end, { state = "scan" })
