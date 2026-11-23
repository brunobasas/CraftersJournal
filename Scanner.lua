local _, ES = ...
local L = ES.L

-- Escaneo completo de la AH. El addon no lo pide: lo pide Auctionator (el botón
-- Escanear lanza el suyo) u otro addon, y el addon lee esas mismas subastas cuando
-- llegan, con cualquiera de las dos APIs:
--  * Clásica: QueryAuctionItems(getAll) + AUCTION_ITEM_LIST_UPDATE
--  * Moderna: C_AuctionHouse.ReplicateItems + REPLICATE_ITEM_LIST_UPDATE
-- Ambas devuelven los mismos campos en el mismo orden por subasta.

local Scanner = { state = "idle" }
ES.Scanner = Scanner

local BATCH_SIZE = 300   -- sin debugprofilestop: subastas por fotograma
local FRAME_BUDGET = 12  -- ms por fotograma procesando (~60 fps se mantiene jugable)
-- s esperando al servidor; si no responde, se abandona. Con 60 s, en los días de
-- lanzamiento (reinos llenos) se abandonaban escaneos que el servidor sí iba a mandar
local TIMEOUT = 120
-- s que el número de subastas debe quedarse quieto para darlas por recibidas: el
-- servidor las manda por tandas (un escaneo se quedó en 1024 justas con 2 s)
local STABLE_SECONDS = 4
local SERVER_LIMIT = 15 * 60

-- Límite del servidor: el de Forever no responde a un escaneo completo si el
-- anterior fue hace menos de 15 min, aunque el cliente diga que se puede. Así que
-- se cuentan 15 min desde cada petición (la de Auctionator o la de otro addon, que
-- ve el gancho: OnForeignScan) y el botón muestra la cuenta atrás: mejor esperar
-- viendo el tiempo que pulsar y que no pase nada.
-- El límite es de la CUENTA, no del personaje: un escaneo con un personaje gasta el
-- de todos.
-- CraftersJournalDB.lastFullScan["otro addon"] = hora de la última petición (de
-- versiones anteriores, cuando el addon escaneaba por su cuenta, puede haber también
-- una por personaje); cuenta la más reciente de todas.
local OTHER_ADDON = "otro addon"
local function LastFullScan()
  if type(ES.db.lastFullScan) ~= "table" then ES.db.lastFullScan = {} end
  return ES.db.lastFullScan
end

local function LastRequest()
  local last
  for _, t in pairs(LastFullScan()) do
    if type(t) == "number" and (not last or t > last) then last = t end
  end
  return last
end

function Scanner:SecondsUntilNextScan()
  if not ES.db then return 0 end
  local last = LastRequest()
  return last and math.max(0, SERVER_LIMIT - (time() - last)) or 0
end

local frame = CreateFrame("Frame")

-- (qué API seguir si no hay ganchos, ver StartWithAuctionator)
local function UseLegacyAPI()
  return QueryAuctionItems ~= nil
end

local function SetStatus(text)
  if text ~= Scanner.statusText and not text:find("%d+ / %d+") and not text:find("%d+ s") then
    ES:ScanLog("estado: " .. text) -- sin el contador de cada segundo
  end
  Scanner.statusText = text
end

function Scanner:IsBusy()
  return self.state ~= "idle"
end

-- Progreso del escaneo (0-1) para el botón de la cabecera: al pedir los datos,
-- WAIT_PROGRESS; al procesarlos, de ahí al 100% según las subastas leídas
local WAIT_PROGRESS = 0.05
local function SetProgress(p)
  Scanner.progress = p
  if ES.OnScanProgress then ES:OnScanProgress(p) end
end

function Scanner:Start()
  if self:IsBusy() then
    ES:Print(L["Ya hay un escaneo en curso."])
    return
  end
  if not ES:IsAuctionHouseOpen() then
    ES:Print(L["Abre la Casa de Subastas para analizarla."])
    return
  end

  -- No pedir lo que el servidor no va a contestar
  local wait = self:SecondsUntilNextScan()
  if wait > 0 then
    local msg = string.format(L["El servidor solo permite un escaneo completo cada 15 min: podrás volver a escanear en %s."], ES.Countdown(wait))
    ES:Print(msg)
    SetStatus(msg)
    return
  end

  -- El escaneo lo pide Auctionator y el addon lee esos mismos datos: un solo escaneo
  -- para los dos (el servidor solo deja uno cada 15 min, y si escanean los dos uno se
  -- queda sin respuesta), y Auctionator guarda su historial de precios, el que usa la
  -- pestaña Inversiones. Sin Auctionator no se escanea (el addon ya no pide el suyo)
  local problem = Scanner.AuctionatorProblem()
  if problem then
    ES:Print(problem)
    SetStatus(problem)
    return
  end
  self:StartWithAuctionator(Scanner.AuctionatorFrame())
end

---------------------------------------------------------------------------
-- Escanear con Auctionator. Su escaneo completo es el que lanza su botón Escanear
-- (Auctionator.State.FullScanFrameRef:InitiateScan; el marco lo crea al abrir la AH).
-- El gancho de QueryAuctionItems / ReplicateItems (OnForeignScan) lo sigue y lee esos
-- datos para todo el addon, como el escaneo de cualquier otro addon
---------------------------------------------------------------------------
function Scanner.AuctionatorFrame()
  local st = Auctionator and Auctionator.State
  local f = type(st) == "table" and st.FullScanFrameRef
  if type(f) == "table" and type(f.InitiateScan) == "function" then return f end
end

-- ¿Auctionator aún no deja otro escaneo? (su propia cuenta atrás, o ya escaneando)
function Scanner.AuctionatorWaits()
  local f = Scanner.AuctionatorFrame()
  if not f or type(f.CanInitiate) ~= "function" then return false end
  local ok, can = pcall(f.CanInitiate, f)
  return ok and not can
end

-- ¿Qué falta en Auctionator para poder escanear? nil si nada (la AH abierta y el
-- límite de 15 min se miran aparte)
function Scanner.AuctionatorProblem()
  if type(Auctionator) ~= "table" then
    return L["Instala Auctionator para escanear la AH: el addon lee su escaneo completo."]
  elseif not Scanner.AuctionatorFrame() then
    -- (su marco de escaneo lo crea al abrirse la AH)
    return L["Auctionator aún no está listo para escanear: espera un momento o vuelve a abrir la AH."]
  elseif Scanner.AuctionatorWaits() then
    return L["Auctionator aún no deja otro escaneo completo: espera a que acabe su cuenta atrás."]
  end
end

-- ¿El botón Escanear de Auctionator (y su autoscan) hará un escaneo en modo resumen?
-- Con la AH moderna (la de Forever) y su opción REPLICATE_SCAN desactivada, la de por
-- defecto, hace un resumen (C_AuctionHouse.SendBrowseQuery: solo el mínimo y las
-- unidades de cada objeto) y no el completo (ReplicateItems), y el addon solo usa
-- escaneos completos. Con la AH clásica siempre hace el completo. Si falta algo de su
-- configuración o da error: falso, como antes de mirarlo
function Scanner.AuctionatorSummaryMode()
  if type(Auctionator) ~= "table" then return false end
  local inc, cfg = Auctionator.IncrementalScan, Auctionator.Config
  -- (Events solo lo define Auctionator con la AH moderna)
  if type(inc) ~= "table" or type(inc.Events) ~= "table" then return false end
  if type(cfg) ~= "table" or type(cfg.Get) ~= "function" or type(cfg.Options) ~= "table" then return false end
  local option = cfg.Options.REPLICATE_SCAN
  if option == nil then return false end
  local ok, replicate = pcall(cfg.Get, option)
  return ok and not replicate
end

-- Nombre de la opción de Auctionator que hace que su botón haga el escaneo completo, en
-- el idioma del juego (Auctionator exporta sus textos como globales AUCTIONATOR_L_*)
local ALTERNATE_SCAN = "Use alternate slower scan mode by default"
function Scanner.AuctionatorScanOptionName()
  local name = AUCTIONATOR_L_CONFIG_ALTERNATE_SCAN
  return type(name) == "string" and name ~= "" and name or ALTERNATE_SCAN
end

-- Auctionator empieza un escaneo en modo resumen (su botón Escanear o su autoscan): el
-- addon no lo usa (solo trae el mínimo de cada objeto, ver AuctionatorSummaryMode).
-- Se dice en el chat una vez por sesión, con cómo tener uno completo
function Scanner:OnAuctionatorSummaryScan()
  ES:ScanLog("Auctionator empezó un escaneo en modo resumen (no se usa)")
  if self.summaryWarned then return end
  self.summaryWarned = true
  -- (con los botones escondidos, en gris: lo que falta, sin "pulsa Escanear")
  local lock = ES.ScanButtonsLock and ES:ScanButtonsLock()
  ES:Print(lock or string.format(L["Auctionator ha hecho un escaneo en modo resumen, que Crafter's Journal no usa (solo trae el precio mínimo de cada objeto). Para actualizar el addon, pulsa Escanear en Crafter's Journal, o activa en las opciones de Auctionator «%s»."],
    Scanner.AuctionatorScanOptionName()))
end

-- Gancho en el inicio del escaneo resumido de Auctionator (su marco lo crea al abrirse la
-- AH, como el del completo: se intenta al refrescar los botones con la AH abierta, antes
-- de su autoscan, que sale 2 s después). Una vez por marco
function Scanner:HookAuctionatorSummary()
  if not hooksecurefunc then return end
  local st = Auctionator and Auctionator.State
  local f = type(st) == "table" and st.IncrementalScanFrameRef
  if type(f) ~= "table" or type(f.InitiateScan) ~= "function" or f == self.hookedSummaryFrame then return end
  self.hookedSummaryFrame = f
  hooksecurefunc(f, "InitiateScan", function() Scanner:OnAuctionatorSummaryScan() end)
end

function Scanner:StartWithAuctionator(f)
  ES:ScanLog("escaneo con Auctionator")
  -- (el gancho sigue su escaneo en cuanto lo pide; launchingAuctionator: es tu escaneo,
  -- con sus mensajes en el chat)
  self.launchingAuctionator = true
  local ok, err = pcall(f.InitiateScan, f)
  -- Sin ganchos (hooksecurefunc no está), se sigue a mano
  if ok and not self:IsBusy() then self:OnForeignScan(UseLegacyAPI() and "legacy" or "modern") end
  self.launchingAuctionator = nil
  if not ok then ES:RecordError("scan", err) end
  ES:RefreshScanButtons()
end

-- Empieza a esperar los datos del escaneo completo que acaba de pedir Auctionator u
-- otro addon, para leerlos cuando lleguen (ver OnForeignScan). No pide nada ni silencia
-- a nadie: ese addon necesita su evento. `before`: las subastas que había cuando lo pidió
function Scanner:Begin(api, before)
  self.api = api
  self.event = api == "legacy" and "AUCTION_ITEM_LIST_UPDATE" or "REPLICATE_ITEM_LIST_UPDATE"
  self.follow = true
  -- (el escaneo de Auctionator que pediste con Escanear: es tu escaneo)
  self.viaAuctionator = self.launchingAuctionator or nil

  ES:ScanLog((self.viaAuctionator and "leyendo el escaneo de Auctionator, API "
    or "leyendo el escaneo de otro addon, API ") .. self.api)
  self.state = "waiting"
  self.scanID = (self.scanID or 0) + 1
  self.key = ES:RealmKey() -- AH en la que empezó el escaneo
  self.requestTime = time()
  self.waited = 0
  self.gotEvent = false
  self.arrived = nil
  ES.SafeRegister(frame, self.event) -- si no existe, el sondeo de cada segundo detecta los datos igual
  ES:RefreshScanButtons()
  SetProgress(WAIT_PROGRESS)

  before = before or self:CountResults()

  -- Contador visible + sondeo por si el evento no llega
  local id = self.scanID
  local started = GetTime()
  local lastCount, stableTicks, changed = before, 0, false

  local function Tick()
    if self.scanID ~= id or self.state ~= "waiting" then return end
    local elapsed = math.floor(GetTime() - started)

    local count = self:CountResults()
    -- Llegan datos: cambió el número, o llegó el evento (con la API clásica el número
    -- puede ser el mismo que el del escaneo anterior)
    -- (una vez cambiado, sigue contando aunque vuelva al número de antes: el nuevo
    -- escaneo puede acabar con las mismas subastas que el anterior)
    changed = changed or count ~= before
    local arriving = count > 0 and (changed or self.gotEvent)
    -- (ya llegan: el otro addon las tiene, y cerrar la AH ahora las pierde, ver Abort)
    if arriving then self.arrived = true end
    if elapsed >= TIMEOUT and not arriving then
      -- Sin respuesta (p. ej. otro addon escaneó hace poco): se abandona y la
      -- cuenta atrás de 15 min ya corre desde esta petición
      self:Abort(L["El servidor no respondió: solo permite un escaneo completo cada 15 min."])
      return
    end
    self.waited = elapsed
    SetProgress(WAIT_PROGRESS) -- el botón muestra los segundos de espera

    -- Si el número de resultados cambió y se mantiene estable STABLE_SECONDS, procesamos
    -- (el evento no basta: llega con la primera tanda, y en Forever a veces ni llega)
    if arriving then
      if count == lastCount then
        stableTicks = stableTicks + 1
        if stableTicks >= STABLE_SECONDS then
          self:Process()
          return
        end
      else
        ES:ScanLog(string.format("llegando: %d subastas", count))
        stableTicks = 0
      end
    end
    lastCount = count

    SetStatus(self.viaAuctionator and string.format(L["Escaneando con Auctionator... %d s"], elapsed)
      or string.format(L["Leyendo el escaneo que pidió otro addon... %d s"], elapsed))
    C_Timer.After(1, Tick)
  end
  Tick()
end

function Scanner:CountResults()
  if self.api == "legacy" then
    return (GetNumAuctionItems("list")) or 0
  end
  return C_AuctionHouse.GetNumReplicateItems() or 0
end

-- `reason`: por qué se cancela, sin la cuenta atrás (la pone el chat al decirlo).
-- `closedAH`: se cancela porque cerraste la AH (Core.lua, AUCTION_HOUSE_CLOSED)
function Scanner:Abort(reason, closedAH)
  -- (guardando lo ya leído, ver Finish: no hace falta la AH y se termina)
  if not self:IsBusy() or self.state == "saving" then return end
  -- (las subastas del otro addon ya llegaban o se estaban leyendo)
  local arrived = self.arrived or self.state == "processing"
  frame:UnregisterAllEvents()
  self.state = "idle"
  self.arrived = nil
  self.scanID = (self.scanID or 0) + 1 -- invalida lotes pendientes
  if self.follow and not self.viaAuctionator and closedAH and arrived then
    -- El escaneo de otro addon (el botón Escanear de Auctionator, su escaneo automático)
    -- ya había llegado y el addon aún lo leía al cerrar la AH. Ese addon ya lo tiene y
    -- parece terminado: sin decirlo, "Último escaneo: hace 2 h" parecía un fallo al
    -- guardar (GitHub). Se dice en el chat y con "Cancelado" junto al último escaneo
    reason = L["Has cerrado la Casa de Subastas antes de que Crafter's Journal terminara de leer el escaneo: sus precios no se han guardado. Déjala abierta hasta que termine (el botón Escanear muestra el progreso)."]
    ES:ScanLog("AH cerrada a medio leer el escaneo de otro addon")
  elseif self.follow and not self.viaAuctionator then
    -- Leyendo el escaneo de otro addon, que aún no había llegado (el servidor no
    -- respondió, o cerraste la AH antes): no lo pediste tú, así que ni aviso en el chat
    -- ni "Cancelado" junto al último escaneo; solo el estado y el registro
    self.follow = nil
    ES:ScanLog("no se pudo leer el escaneo de otro addon: " .. tostring(reason))
    SetStatus(L["No se pudo leer el escaneo de otro addon. Puedes escanear tú cuando el botón lo permita."])
    ES:RefreshScanButtons()
    return
  end
  -- Para avisar junto a "Último escaneo" de que el último intento no acabó
  -- (si no, "hace 2 días" parece un fallo al guardar). Sin la cuenta atrás: el tooltip
  -- de Escanear lo enseña más tarde ("Último intento (13:01): …") junto a la suya, la de
  -- ahora, y la de entonces se quedaba parada ("en 14:53")
  if type(ES.db.lastScanFail) ~= "table" then ES.db.lastScanFail = {} end
  ES.db.lastScanFail[self.key or ES:RealmKey()] = { time = time(), reason = reason }
  self.follow, self.viaAuctionator = nil, nil
  if reason then
    -- En el chat, sí: es de ese momento y no cambia
    local wait = self:SecondsUntilNextScan()
    ES:Print(wait > 0 and (reason .. " " .. string.format(L["Podrás volver a escanear en %s."], ES.Countdown(wait))) or reason)
    SetStatus(reason)
  end
  ES:RefreshScanButtons()
end

function Scanner:ReadAuction(index)
  if self.api == "legacy" then
    return GetAuctionItemInfo("list", index)
  end
  return C_AuctionHouse.GetReplicateItemInfo(index)
end

-- Categoría de tiempo restante normalizada a 1 (corto) .. 4 (muy largo)
function Scanner:ReadTimeLeft(index)
  if self.api == "legacy" then
    return GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("list", index) or 0
  end
  if C_AuctionHouse.GetReplicateItemTimeLeft then
    local tl = C_AuctionHouse.GetReplicateItemTimeLeft(index)
    return tl and tl + 1 or 0
  end
  return 0
end

function Scanner:Process()
  frame:UnregisterEvent(self.event)
  self.state = "processing"

  local total, first
  if self.api == "legacy" then
    total = GetNumAuctionItems("list")
    first = 1
  else
    total = C_AuctionHouse.GetNumReplicateItems()
    first = 0
  end
  local last = first + total - 1
  ES:ScanLog(string.format("procesando %d subastas (%s)", total, self.gotEvent and "con evento" or "sin evento"))

  local items = {}
  local sigs = {}
  local id = self.scanID
  local index = first
  -- Firmas (History.Signature: una cadena por subasta) solo para las que se leen
  -- después (lighter-memory): las que pueden quedar cerca del mínimo de su objeto
  -- (hasta STUCK_BAND sobre el mínimo hasta ahora: el mínimo solo baja, así que una más
  -- cara ya no puede) y las que History:Record busca del escaneo anterior (hasta
  -- `reach` de su objeto). Las de solo puja no las mira nadie
  local History = ES.History
  local band = History.STUCK_BAND
  local reach = History.PrevReach(ES.db.track and ES.db.track[self.key or ES:RealmKey()])

  local function Step()
    if self.scanID ~= id then return end

    -- Por tiempo y no por número: procesa todo lo que quepa en FRAME_BUDGET ms
    -- por fotograma (en un PC rápido son miles de subastas, no 300)
    local started = debugprofilestop and debugprofilestop()
    local stop = last
    if not started then stop = math.min(index + BATCH_SIZE - 1, last) end
    local i = index
    while i <= stop do
      if started and (i - index) % 100 == 99 and debugprofilestop() - started > FRAME_BUDGET then
        stop = i
      end
      -- name, texture, count, quality, canUse, level, levelType, minBid,
      -- minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName,
      -- owner, ownerFullName, saleStatus, itemID, hasAllInfo
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID = self:ReadAuction(i)
      if itemID and itemID > 0 and count and count > 0 then
        local entry = items[itemID]
        if not entry then
          entry = { listings = 0, quantity = 0, buyoutQty = 0, buyoutTotal = 0, owners = {} }
          items[itemID] = entry
        end
        entry.listings = entry.listings + 1
        entry.quantity = entry.quantity + count
        local ownerKey = (owner and owner ~= "") and owner or "?"
        if ownerKey ~= "?" then
          entry.owners[ownerKey] = (entry.owners[ownerKey] or 0) + 1
          entry.knownOwners = (entry.knownOwners or 0) + 1
        end

        if History:IsTracked(itemID) then
          if buyout and buyout > 0 then
            local unit, min, r = buyout / count, entry.minUnit, reach[itemID]
            if not min or unit <= min * band or (r and unit <= r) then
              History.AddAuction(sigs, History.Signature(itemID, count, buyout, ownerKey), self:ReadTimeLeft(i))
            end
          end
          -- Escalera de precios: cuántas unidades hay a cada precio por unidad
          if buyout and buyout > 0 then
            entry.ladder = entry.ladder or {}
            local unit = math.floor(buyout / count + 0.5)
            entry.ladder[unit] = (entry.ladder[unit] or 0) + count
          end
        end
        if buyout and buyout > 0 then
          local unit = buyout / count
          if not entry.minUnit or unit < entry.minUnit then entry.minUnit = unit end
          entry.buyoutQty = entry.buyoutQty + count
          entry.buyoutTotal = entry.buyoutTotal + buyout
        end
      end
      i = i + 1
    end

    index = stop + 1
    SetStatus(string.format(L["Procesando subastas... %d / %d"], index - first, total))
    SetProgress(WAIT_PROGRESS + (1 - WAIT_PROGRESS) * (index - first) / math.max(1, total))

    if index > last then
      -- Si mientras se procesaba llegó otra tanda, se lee también
      local now = self:CountResults()
      if now > total then
        ES:ScanLog(string.format("llegaron más al procesar: %d -> %d", total, now))
        total = now
        last = first + total - 1
      end
    end
    if index <= last then
      C_Timer.After(0, Step)
    else
      self:Finish(items, sigs, total)
    end
  end

  Step()
end

-- { [precio] = cantidad } -> { p1, q1, p2, q2, ... } ordenado de más barato a más
-- caro, y la mediana calculada con todos los precios. Para no guardar demasiado se
-- conservan MAX_LADDER_LEVELS niveles: lo que sobra se junta en el último a su
-- precio medio, así no se pierden existencias (antes se descartaba y la mediana
-- y las unidades a la venta salían por debajo de las reales).
local MAX_LADDER_LEVELS = 40
-- (tablas de trabajo, las mismas para todos los objetos: una nueva por objeto era
-- basura en cada escaneo; el resultado se crea al final con su tamaño justo)
local prices, flat = {}, {}
local function BuildLadder(levels)
  if not levels then return nil end
  local n, total = 0, 0
  for price, qty in pairs(levels) do
    n = n + 1
    prices[n] = price
    total = total + qty
  end
  for i = #prices, n + 1, -1 do prices[i] = nil end -- (lo del objeto anterior)
  table.sort(prices)
  local median, acc = nil, 0
  for _, price in ipairs(prices) do
    acc = acc + levels[price]
    if acc >= total / 2 then median = price break end
  end
  local m = 0
  for i = 1, math.min(n, MAX_LADDER_LEVELS - 1) do
    flat[m + 1], flat[m + 2] = prices[i], levels[prices[i]]
    m = m + 2
  end
  if n >= MAX_LADDER_LEVELS then
    local qty, value = 0, 0
    for i = MAX_LADDER_LEVELS, n do
      qty = qty + levels[prices[i]]
      value = value + levels[prices[i]] * prices[i]
    end
    flat[m + 1], flat[m + 2] = math.floor(value / qty + 0.5), qty
    m = m + 2
  end
  return { unpack(flat, 1, m) }, median
end

-- Resumen de lo leído (escaleras de precios y medianas de cada objeto), por tandas de
-- FRAME_BUDGET ms como la lectura: con 280.000 subastas son unos 6.500 objetos y de
-- golpe era un tirón al acabar (CurseForge: "se congela al abrir la AH" con el
-- escaneo de otro addon). Mientras, el estado es "saving": sigue ocupado (no se
-- escanea ni se anuncia con los precios de antes) pero cerrar la AH no lo cancela,
-- los datos ya están leídos
function Scanner:Finish(items, sigs, total)
  -- Un escaneo vacío es un fallo del servidor: guardarlo borraría los precios
  -- buenos y haría creer que todo se ha vendido
  if total == 0 then
    self.state = "idle"
    local msg = L["El servidor devolvió 0 subastas; no se guarda este escaneo. Inténtalo más tarde."]
    ES:Print(msg)
    SetStatus(msg)
    ES:RefreshScanButtons()
    return
  end

  self.state = "saving"
  local id = self.scanID
  local ids = {}
  for itemID in pairs(items) do ids[#ids + 1] = itemID end
  local saved, knownOwners, i = {}, 0, 1
  -- (el mínimo sin redondear de cada objeto con firmas: History:Record lo usa para
  -- quedarse con las cercanas, el mismo que saldría de las firmas)
  local mins = {}
  local t0 = debugprofilestop and debugprofilestop()
  local frames = 0

  local function Step()
    if self.scanID ~= id then return end
    frames = frames + 1
    local started = debugprofilestop and debugprofilestop()
    local stop = started and #ids or math.min(i + BATCH_SIZE - 1, #ids)
    while i <= stop do
      local itemID = ids[i]
      local e = items[itemID]
      knownOwners = knownOwners + (e.knownOwners or 0)
      local sellers, top = 0, 0
      for _, n in pairs(e.owners) do
        sellers = sellers + 1
        if n > top then top = n end
      end
      local ladder, median = BuildLadder(e.ladder)
      if e.minUnit and ES.History:IsTracked(itemID) then mins[itemID] = e.minUnit end
      saved[itemID] = {
        listings = e.listings,
        quantity = e.quantity,
        minUnit = e.minUnit and math.floor(e.minUnit + 0.5) or nil,
        avgUnit = e.buyoutQty > 0 and math.floor(e.buyoutTotal / e.buyoutQty + 0.5) or nil,
        sellers = sellers > 0 and sellers or nil,
        -- Solo fiable si conocemos el vendedor de al menos la mitad de las subastas
        topShare = (e.knownOwners or 0) * 2 >= e.listings
          and math.floor(top / e.knownOwners * 100 + 0.5) / 100 or nil,
        ladder = ladder,
        median = median,
      }
      i = i + 1
      if started and i % 50 == 0 and debugprofilestop() - started > FRAME_BUDGET then break end
    end
    if i <= #ids then
      C_Timer.After(0, Step)
      return
    end
    if t0 then
      ES:ScanLog(string.format("resumen: %d objetos en %d fotogramas, %.0f ms", #ids, frames, debugprofilestop() - t0))
    end
    self:Save(saved, #ids, knownOwners, sigs, total, mins)
  end
  Step()
end

-- Guarda el escaneo resumido (ver Finish) y avisa a las vistas
function Scanner:Save(saved, unique, knownOwners, sigs, total, mins)
  self.state = "idle"
  local now = time()
  local key = self.key or ES:RealmKey()
  local scan = { time = now, total = total, unique = unique, items = saved,
    ownerPct = total > 0 and math.floor(knownOwners / total * 100 + 0.5) or 0 }
  ES.db.scans[key] = scan

  -- Foto compacta de los objetos de profesiones para el historial:
  -- ";itemID:mínimo:subastas:mediana:unidades a la venta;..." (por bloques y sin una
  -- cadena por objeto, como History.Pack: menos basura al acabar el escaneo)
  local parts, blocks, n = {}, {}, 0
  for itemID, e in pairs(saved) do
    if e.minUnit and ES.History:IsTracked(itemID) then
      parts[n + 1], parts[n + 2], parts[n + 3], parts[n + 4], parts[n + 5] = ";", itemID, ":", e.minUnit, ":"
      parts[n + 6], parts[n + 7], parts[n + 8], parts[n + 9], parts[n + 10] = e.listings, ":", e.median or e.minUnit, ":", e.quantity
      n = n + 10
      if n >= 500 then blocks[#blocks + 1] = table.concat(parts, "", 1, n) n = 0 end
    end
  end
  if n > 0 then blocks[#blocks + 1] = table.concat(parts, "", 1, n) end
  local snap = #blocks > 0 and table.concat(blocks) or ";"
  ES.History:Record(key, sigs, snap, now, mins)
  local scans = ES.History:Summary()

  local msg = string.format(L["Escaneo completado: %d subastas, %d objetos distintos."], total, unique)
  local followed = self.follow
  local viaAuctionator = self.viaAuctionator
  if viaAuctionator then
    msg = msg .. L[" (con el escaneo de Auctionator)"]
  elseif followed then
    msg = msg .. L[" (con el escaneo que pidió otro addon)"]
  end
  self.follow, self.viaAuctionator = nil, nil
  if scans < 3 and viaAuctionator then
    msg = msg .. L[" Las alertas de mercado necesitan unos días de escaneos: con 1-2 al día basta."]
  end
  -- El escaneo de otro addon (el automático de Auctionator o de ForeverForge, cada vez
  -- que abres la AH) no escribe en el chat: se repetía en cada visita. Se ve en "Último
  -- escaneo: hace 0 min" y el estado. El de Auctionator que pediste con Escanear, sí
  if viaAuctionator then ES:Print(msg) end
  SetStatus(msg)
  ES:RefreshScanButtons()
  ES:OnScanComplete(scan, followed)
end

-- Auctionator (con su botón, el de Crafter's Journal o su escaneo automático),
-- ForeverForge_Auction, TSM... piden un escaneo completo: gasta los 15 min de la
-- cuenta. Se anota la barrera (el botón muestra la cuenta atrás real) y se leen esos
-- mismos datos cuando lleguen (Begin): es la única forma de tener los precios de la
-- AH, Crafter's Journal nunca pide un escaneo por su cuenta
function Scanner:OnForeignScan(api)
  if not ES.db then return end
  LastFullScan()[OTHER_ADDON] = time()
  ES:ScanLog("otro addon pidió un escaneo completo (API " .. api .. ")")
  if not self:IsBusy() then
    -- Lo que hay ahora, antes de que lleguen los datos nuevos (para no tomar por
    -- nuevas las subastas de un escaneo anterior)
    local saved = self.api
    self.api = api
    local ok, before = pcall(self.CountResults, self)
    self.api = saved
    before = ok and before or 0
    -- (ese addon suele pedirlo al abrirse la AH, quizá antes de que la marquemos
    -- abierta: se mira otra vez un momento después)
    local function Follow()
      if self:IsBusy() then return end
      if ES:IsAuctionHouseOpen() then self:Begin(api, before) end
    end
    if ES:IsAuctionHouseOpen() then Follow() return end
    C_Timer.After(0.3, Follow)
    SetStatus(string.format(L["Otro addon acaba de pedir un escaneo completo: el servidor no permitirá otro hasta dentro de %s."],
      ES.Countdown(self:SecondsUntilNextScan())))
  end
  if not self:IsBusy() then
    SetStatus(string.format(L["Otro addon acaba de pedir un escaneo completo: el servidor no permitirá otro hasta dentro de %s."],
      ES.Countdown(self:SecondsUntilNextScan())))
  end
  ES:RefreshScanButtons()
end

-- Ganchos sobre las dos APIs (se rehacen si algo cambia la función por otra)
function Scanner:InstallHooks()
  if not hooksecurefunc then return end
  if C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.ReplicateItems ~= self.hookedReplicate then
    hooksecurefunc(C_AuctionHouse, "ReplicateItems", function() Scanner:OnForeignScan("modern") end)
    self.hookedReplicate = C_AuctionHouse.ReplicateItems
  end
  if QueryAuctionItems and QueryAuctionItems ~= self.hookedQuery then
    hooksecurefunc("QueryAuctionItems", function(_, _, _, _, _, _, getAll)
      if getAll then Scanner:OnForeignScan("legacy") end
    end)
    self.hookedQuery = QueryAuctionItems
  end
end
pcall(Scanner.InstallHooks, Scanner)

frame:SetScript("OnEvent", function(_, event)
  -- Solo se anota: procesar aquí cogía solo la primera tanda; el sondeo de cada
  -- segundo procesa cuando el número de subastas deja de crecer
  if event == Scanner.event and Scanner.state == "waiting" and not Scanner.gotEvent then
    Scanner.gotEvent = true
    ES:ScanLog(string.format("evento %s: %d subastas", event, Scanner:CountResults()))
  end
end)
