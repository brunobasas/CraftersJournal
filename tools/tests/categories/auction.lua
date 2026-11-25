-- Casa de Subastas: escanear, precios, historial, compras y vender

local function OpenAH()
  AuctionFrame:Show()
  FireEvent("AUCTION_HOUSE_SHOW")
  RunTimers()
end

-- Un escaneo cancelado: el chat lleva la cuenta atrás de ese momento; el motivo guardado
-- no, porque el tooltip de Escanear lo enseña después ("Último intento (13:01): …") y ya
-- tiene su propia cuenta atrás, la de ahora: la de entonces se quedaba parada ("en 14:53")
local function CheckCancelSaid(printed, key)
  local text, again = ES.L[key], ES.L["Podrás volver a escanear en %s."]:match("^(.-)%%")
  local said
  for i = printed + 1, #PRINTS do
    if PRINTS[i]:find(text, 1, true) then said = PRINTS[i] end
  end
  expect(said, "el chat no dice «%s»", text)
  expect(said and said:find(again, 1, true), "el chat no dice cuándo se puede volver a escanear: %s", tostring(said))
  local fail = expect(ES:LastScanFail(), "junto al último escaneo no dice que se canceló")
  expect_eq(fail.reason, text, "motivo guardado para el tooltip (sin la cuenta atrás, que se queda parada)")
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
  CheckCancelSaid(0, "El servidor no respondió: solo permite un escaneo completo cada 15 min.")
  expect(ES.Scanner:SecondsUntilNextScan() > 0, "sin cuenta atrás tras no responder")
  expect(ES.db.scans[ES:RealmKey()] == nil, "guardó un escaneo sin respuesta")
end, { state = "empty" })

test("tu escaneo a medio leer al cerrar la AH: cuenta atrás en el chat, no en el motivo guardado", function()
  InstallAuctionator()
  AUCTIONS = { { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 } }
  OpenAH()
  local printed = #PRINTS
  ES.Scanner:Start()
  RunTimers(5)
  expect(ES.Scanner:IsBusy(), "el addon ya terminó de leer: la prueba no cierra a medio leer")
  AuctionFrame:Hide()
  FireEvent("AUCTION_HOUSE_CLOSED")
  RunTimers()
  CheckCancelSaid(printed, "Has cerrado la Casa de Subastas; escaneo cancelado. Déjala abierta hasta que termine.")
end, { state = "empty" })

-- GitHub: «último escaneo hace X h» justo después de escanear con Auctionator y cerrar la
-- AH. Auctionator ya tenía las subastas, pero el addon aún las leía: al cerrar se
-- cancelaba sin decir nada y la cabecera seguía con la hora del escaneo anterior
local CLOSED_MID_READ = "Has cerrado la Casa de Subastas antes de que Crafter's Journal terminara de leer el escaneo: sus precios no se han guardado. Déjala abierta hasta que termine (el botón Escanear muestra el progreso)."
local function CloseAHNow()
  AuctionFrame:Hide()
  FireEvent("AUCTION_HOUSE_CLOSED")
  RunTimers()
end

test("escaneo de Auctionator a medio leer al cerrar la AH: lo dice en el chat y junto al último escaneo", function()
  InstallAuctionator()
  AUCTIONS = { { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 } }
  local before = ES.db.scans[ES:RealmKey()]
  OpenMain()
  OpenAH()
  local printed = #PRINTS
  -- Auctionator lo pide por su cuenta (su botón Escanear o su escaneo automático)
  QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
  ES.Scanner:OnForeignScan("legacy")
  RunTimers(5) -- (las subastas llegan a los 3 s; el addon las lee cuando dejan de llegar)
  expect(ES.Scanner:IsBusy(), "el addon ya terminó de leer: la prueba no cierra a medio leer")
  CloseAHNow()
  expect(not ES.Scanner:IsBusy(), "sigue leyendo con la AH cerrada")
  expect(ES.db.scans[ES:RealmKey()] == before, "guardó un escaneo a medio leer")
  CheckCancelSaid(printed, CLOSED_MID_READ)
  ES:UpdateLastScan()
  expect(ES:GetMainFrame().lastScan:GetText():find(ES.L["Cancelado · último: "], 1, true),
    "la cabecera dice «%s» y no que se canceló", tostring(ES:GetMainFrame().lastScan:GetText()))
end, { state = "scan" })

-- Tras un /reload justo después de escanear, al abrir la AH Auctionator (u otro addon)
-- pide su escaneo automático: dentro del límite de 15 min el servidor no responde. El
-- addon se quedaba "escaneando" 2 min y reiniciaba la cuenta atrás desde esa petición
test("escaneo de otro addon dentro del límite de 15 min: no se espera ni mueve la cuenta atrás", function()
  InstallAuctionator()
  AUCTIONS = { { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 } }
  local last = time() - 60 -- (el escaneo de antes del /reload, guardado)
  ES.db.lastFullScan = { ["otro addon"] = last }
  OpenAH()
  local wait = ES.Scanner:SecondsUntilNextScan()
  expect(wait > 0, "la prueba espera el límite de 15 min activo")
  QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
  ES.Scanner:OnForeignScan("legacy")
  expect(not ES.Scanner:IsBusy(), "espera un escaneo que el servidor no va a mandar")
  expect_eq(ES.db.lastFullScan["otro addon"], last, "la cuenta atrás se reinició con una petición ignorada")
  RunTimers()
  expect(not ES.Scanner:IsBusy(), "se quedó escaneando")
end, { state = "scan" })

-- Un error al leer las subastas (datos raros del servidor, p. ej. justo tras un /reload)
-- rompía la cadena de pasos y el escaneo se quedaba "ocupado" para siempre: no se podía
-- volver a escanear ni anunciar. Ahora se apunta y se cancela
test("un error al leer las subastas no deja el escaneo bloqueado", function()
  InstallAuctionator()
  AUCTIONS = { { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 } }
  OpenAH()
  local read = ES.Scanner.ReadAuction
  ES.Scanner.ReadAuction = function() error("subasta rota") end
  QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
  ES.Scanner:OnForeignScan("legacy")
  RunTimers()
  ES.Scanner.ReadAuction = read
  expect(not ES.Scanner:IsBusy(), "el escaneo se quedó ocupado tras el error")
  -- (el error se apunta: aquí es el esperado, no un fallo de la prueba)
  local found = false
  for i = #RECORDED_ERRORS, 1, -1 do
    if RECORDED_ERRORS[i]:find("subasta rota", 1, true) then found = true table.remove(RECORDED_ERRORS, i) end
  end
  expect(found, "no se apuntó el error del escaneo")
end, { state = "empty" })

test("escaneo de otro addon sin respuesta aún al cerrar la AH: nada en el chat", function()
  InstallAuctionator()
  AUCTIONS = { { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 } }
  AH_RESPONDS = false
  OpenAH()
  local printed = #PRINTS
  QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
  ES.Scanner:OnForeignScan("legacy")
  RunTimers(5)
  CloseAHNow()
  AH_RESPONDS = true
  expect(not ES.Scanner:IsBusy(), "sigue esperando con la AH cerrada")
  expect_eq(#PRINTS, printed, "escribió en el chat por un escaneo que no llegó a empezar")
  expect(not ES:LastScanFail(), "marca cancelado un escaneo que no llegó a empezar")
end, { state = "scan" })

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

-- CurseForge: con los botones del addon ocultos, el botón Escanear de Auctionator no
-- actualizaba nada. Con la AH moderna, su botón y su autoscan hacen por defecto un
-- escaneo en modo resumen (solo mínimo y unidades), que el addon no usa: el addon solo
-- usa escaneos completos, lo detecta, enseña sus botones y avisa
test("modo resumen de Auctionator: se detecta por su configuración", function()
  local Summary = ES.Scanner.AuctionatorSummaryMode
  expect(type(Summary) == "function", "no hay Scanner.AuctionatorSummaryMode")
  expect(not Summary(), "sin Auctionator, en modo resumen")
  InstallAuctionator()
  expect(not Summary(), "Auctionator en modo completo, tomado por resumen")
  AUCTIONATOR_REPLICATE = false
  expect(Summary(), "Auctionator por defecto (resumen) no se detecta")
  -- AH clásica (sin IncrementalScan.Events): su botón siempre hace el completo
  Auctionator.IncrementalScan = {}
  expect(not Summary(), "con la AH clásica, en modo resumen")
  Auctionator.IncrementalScan = { Events = {} }
  -- Sin su API de configuración, o si da error: como antes
  local get = Auctionator.Config.Get
  Auctionator.Config.Get = nil
  expect(not Summary(), "sin Config.Get, en modo resumen")
  Auctionator.Config.Get = function() error("Auctionator: error simulado") end
  expect(not Summary(), "con Config.Get que falla, en modo resumen")
  Auctionator.Config = nil
  expect(not Summary(), "sin Config, en modo resumen")
  Auctionator.Config = { Options = {}, Get = get }
  expect(not Summary(), "sin la opción REPLICATE_SCAN, en modo resumen")
end, { state = "empty" })

-- Las líneas del tooltip de un botón (la 1, el título)
local function TooltipLines(button)
  local lines = {}
  local add = GameTooltip.AddLine
  GameTooltip.AddLine = function(_, t) lines[#lines + 1] = tostring(t) end
  button._scripts.OnEnter(button)
  GameTooltip.AddLine = add
  return lines
end

-- Quien escondió los botones de escanear: si con Auctionator no se puede actualizar el
-- addon (en modo resumen, o sin Auctionator), salen en gris y el tooltip dice lo que falta
local LOCKED_SUMMARY = "Auctionator está en modo resumen: su botón Escanear no actualiza Crafter's Journal. Activa en las opciones de Auctionator «%s», o vuelve a mostrar los botones de escanear en las opciones de Crafter's Journal."
local function ExpectLocked(button, text, where)
  expect(button:IsShown(), "%s: sigue oculto", where)
  expect(button._enabled == false, "%s: se puede pulsar", where)
  local lines = TooltipLines(button)
  expect_eq(lines[2], text, where .. ": lo primero del tooltip")
end

test("modo resumen de Auctionator: con los botones ocultos en las opciones, salen en gris con lo que falta", function()
  InstallAuctionator()
  AUCTIONATOR_REPLICATE = false
  ES:SetOption("noScanButtons", false) -- (ocultos en las opciones)
  local main = OpenMain()
  OpenAH()
  local header = main.scanButton
  local button = expect(CraftersJournalAHButton, "no hay botón encima de la AH")
  local text = string.format(ES.L[LOCKED_SUMMARY], "Use alternate slower scan mode by default")
  ExpectLocked(header, text, "botón de la cabecera")
  ExpectLocked(button, text, "botón de encima de la AH")
  -- (y el «usa este botón» del modo resumen no sale: no se puede pulsar)
  local used = ES.L["Auctionator está en modo resumen: su botón Escanear no actualiza Crafter's Journal. Usa este botón, o activa en las opciones de Auctionator «%s»."]:match("^(.-)%%")
  expect(not table.concat(TooltipLines(header), "\n"):find(used, 1, true), "el tooltip en gris dice que uses el botón")
  expect_eq(ES.db.noScanButtons, true, "se cambió la opción guardada")
  -- Al volver a activar la opción, normales: se pueden pulsar
  ES:SetOption("noScanButtons", true)
  expect(header._enabled == true, "con la opción activada, el botón de la cabecera sigue en gris")
  expect(button._enabled == true, "con la opción activada, el botón de encima de la AH sigue en gris")
  ES:SetOption("noScanButtons", false)
  expect(header._enabled == false, "al ocultarlos otra vez, el botón de la cabecera no se pone en gris")
  -- Auctionator en modo completo (su casilla marcada): al volver a abrir la AH, la opción manda
  AUCTIONATOR_REPLICATE = true
  AuctionFrame:Hide()
  FireEvent("AUCTION_HOUSE_CLOSED")
  RunTimers()
  OpenAH()
  expect(not header:IsShown(), "con Auctionator en modo completo, el botón de la cabecera sale aunque esté oculto")
  expect(not button:IsShown(), "con Auctionator en modo completo, el botón de encima de la AH sale aunque esté oculto")
  -- Y al revés con la ventana del addon cerrada: al abrirla, el de la cabecera sigue el modo
  AuctionFrame:Hide()
  FireEvent("AUCTION_HOUSE_CLOSED")
  RunTimers()
  main:Hide()
  AUCTIONATOR_REPLICATE = false
  OpenMain()
  expect(header:IsShown(), "al abrir el addon, el botón de la cabecera no sigue el modo de Auctionator")
end, { state = "empty" })

test("modo resumen de Auctionator: con los botones a la vista, se pueden pulsar como siempre", function()
  InstallAuctionator()
  AUCTIONATOR_REPLICATE = false
  local main = OpenMain()
  OpenAH()
  expect(main.scanButton._enabled == true, "el botón de la cabecera, en gris")
  expect(CraftersJournalAHButton._enabled == true, "el botón de encima de la AH, en gris")
  ES.Scanner:Start()
  expect_eq(AUCTIONATOR_FULL_SCANS, 1, "Escanear no pidió el escaneo completo de Auctionator")
  RunTimers()
end, { state = "empty" })

test("sin Auctionator: con los botones ocultos en las opciones, salen en gris y dicen que lo instales", function()
  ES:SetOption("noScanButtons", false)
  local main = OpenMain()
  OpenAH()
  local text = ES.L["Instala Auctionator para escanear la AH: el addon lee su escaneo completo."]
  ExpectLocked(main.scanButton, text, "botón de la cabecera")
  ExpectLocked(expect(CraftersJournalAHButton, "no hay botón encima de la AH"), text, "botón de encima de la AH")
end, { state = "empty" })

-- Avisos del addon en el chat que contienen `text`
local function PrintsWith(text)
  local n = 0
  for _, line in ipairs(PRINTS) do if line:find(text, 1, true) then n = n + 1 end end
  return n
end

test("modo resumen de Auctionator: su escaneo no se usa y se avisa una vez por sesión", function()
  InstallAuctionator()
  AUCTIONATOR_REPLICATE = false
  AUCTIONATOR_L_CONFIG_ALTERNATE_SCAN = "Modo de escaneo alternativo"
  -- (un hooksecurefunc mínimo, como el del juego, solo en esta prueba)
  hooksecurefunc = function(t, name, fn)
    if type(t) == "string" then t, name, fn = _G, t, name end
    local orig = t[name]
    t[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
  end
  local before = ES.db.scans[ES:RealmKey()]
  local wait = ES.Scanner:SecondsUntilNextScan()
  OpenMain()
  OpenAH()
  RunTimers()
  local frame = Auctionator.State.IncrementalScanFrameRef
  local warning = ES.L["Auctionator ha hecho un escaneo en modo resumen, que Crafter's Journal no usa (solo trae el precio mínimo de cada objeto). Para actualizar el addon, pulsa Escanear en Crafter's Journal, o activa en las opciones de Auctionator «%s»."]
  local text = string.format(warning, AUCTIONATOR_L_CONFIG_ALTERNATE_SCAN)
  -- Su botón Escanear (o su autoscan) lanza el resumen: el gancho avisa, una vez
  frame:InitiateScan()
  RunTimers()
  expect_eq(AUCTIONATOR_SUMMARY_SCANS, 1, "escaneos resumidos de Auctionator")
  expect_eq(PrintsWith(text), 1, "avisos en el chat tras el primer escaneo resumido")
  frame:InitiateScan()
  ES.Scanner:OnAuctionatorSummaryScan()
  RunTimers()
  expect_eq(PrintsWith(text), 1, "el aviso se repite en la misma sesión")
  -- Y el escaneo guardado, el límite de 15 min y el estado no cambian
  expect(ES.db.scans[ES:RealmKey()] == before, "el escaneo resumido cambió el escaneo guardado")
  expect_eq(ES.Scanner:SecondsUntilNextScan(), wait, "el escaneo resumido cuenta para el límite de 15 min")
  expect(not ES.Scanner:IsBusy(), "el addon se puso a leer el escaneo resumido")
end)

test("modo resumen de Auctionator: con los botones ocultos, el aviso del chat no dice que pulses Escanear", function()
  InstallAuctionator()
  AUCTIONATOR_REPLICATE = false
  ES:SetOption("noScanButtons", false)
  OpenMain()
  OpenAH()
  ES.Scanner:OnAuctionatorSummaryScan()
  local text = string.format(ES.L[LOCKED_SUMMARY], "Use alternate slower scan mode by default")
  expect_eq(PrintsWith(text), 1, "avisos en el chat con lo que falta activar")
  local press = ES.L["Auctionator ha hecho un escaneo en modo resumen, que Crafter's Journal no usa (solo trae el precio mínimo de cada objeto). Para actualizar el addon, pulsa Escanear en Crafter's Journal, o activa en las opciones de Auctionator «%s»."]:match("^(.-)%%")
  expect_eq(PrintsWith(press), 0, "el chat dice que pulses un botón en gris")
end, { state = "empty" })

test("modo resumen de Auctionator: el tooltip de los botones de escanear lo dice", function()
  InstallAuctionator()
  AUCTIONATOR_REPLICATE = false
  local main = OpenMain()
  OpenAH()
  local line = ES.L["Auctionator está en modo resumen: su botón Escanear no actualiza Crafter's Journal. Usa este botón, o activa en las opciones de Auctionator «%s»."]
  local text = string.format(line, "Use alternate slower scan mode by default") -- (sin su texto traducido)
  local function TooltipOf(button)
    local lines = {}
    local add = GameTooltip.AddLine
    GameTooltip.AddLine = function(_, t) lines[#lines + 1] = tostring(t) end
    button._scripts.OnEnter(button)
    GameTooltip.AddLine = add
    return table.concat(lines, "\n")
  end
  expect(TooltipOf(main.scanButton):find(text, 1, true), "el tooltip del botón de la cabecera no avisa del modo resumen")
  expect(TooltipOf(CraftersJournalAHButton):find(text, 1, true), "el tooltip del botón de encima de la AH no avisa del modo resumen")
  -- En modo completo, no
  AUCTIONATOR_REPLICATE = true
  expect(not TooltipOf(main.scanButton):find(text, 1, true), "con Auctionator en modo completo, el tooltip avisa del modo resumen")
end, { state = "empty" })

-- CurseForge: con el botón Escanear de Auctionator, los de Crafter's Journal sobraban.
-- Los dos (cabecera y encima de la AH) van con una opción, activada por defecto: el
-- usuario ve siempre el botón de escanear salvo que lo quite
local function ScanButtonsOption()
  for _, opt in ipairs(ES.OPTIONS) do
    if opt.key == "noScanButtons" then return opt end
  end
end

test("opción: los botones de escanear, a la vista por defecto en la cabecera y encima de la AH", function()
  InstallAuctionator()
  ES.db.scanButtons = nil -- (de la prueba en que venían desactivados: ya no cuenta)
  ES:MigrateWindowOptions()
  expect_eq(ES.db.noScanButtons, nil, "sin haber quitado nada, salen quitados")
  AUCTIONS = { { item = 2318, count = 5, buyout = 125, owner = "Ana", tl = 4 } }
  OpenMain()
  OpenAH()
  local header = ES:GetMainFrame().scanButton
  local button = expect(CraftersJournalAHButton, "no hay botón encima de la AH")
  local list = expect(ES.ahListButton, "no hay botón de la lista de compra")
  expect(ScanButtonsOption(), "no está la opción en la ventana de opciones")
  expect(header:IsShown(), "el botón de la cabecera no sale por defecto")
  expect(button:IsShown(), "el botón de encima de la AH no sale por defecto")
  expect(list._anchorTo == button, "la lista de compra no va junto al botón")
  -- Se quitan al momento, con la AH abierta: los dos
  ES:SetOption("noScanButtons", false)
  expect_eq(ES.db.noScanButtons, true, "opción guardada")
  expect(not header:IsShown(), "el botón de la cabecera sigue con la opción quitada")
  expect(not button:IsShown(), "el botón de encima de la AH sigue con la opción quitada")
  expect(list:IsShown(), "se fue también la lista de compra")
  expect(list._anchorTo == list:GetParent(), "la lista de compra no va a la esquina")
  -- "Último escaneo" sigue a la vista, en el sitio del botón
  local lastScan = ES:GetMainFrame().lastScan
  expect_eq(lastScan:GetNumPoints(), 1, "anclajes del último escaneo (no se movió al sitio del botón)")
  -- Sin los botones, el escaneo de Auctionator (su botón) se sigue leyendo
  QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
  ES.Scanner:OnForeignScan("legacy")
  RunTimers()
  local scan = expect(ES.db.scans[ES:RealmKey()], "sin los botones no se leyó el escaneo de Auctionator")
  expect_eq(scan.items[2318].minUnit, 25, "Light Leather")
  -- Al volver a abrir la AH siguen quitados
  AuctionFrame:Hide()
  FireEvent("AUCTION_HOUSE_CLOSED")
  RunTimers()
  OpenAH()
  expect(not button:IsShown(), "el botón vuelve al abrir otra vez la AH")
  -- Y vuelven al activarla
  ES:SetOption("noScanButtons", true)
  expect_eq(ES.db.noScanButtons, nil, "opción guardada")
  expect(header:IsShown(), "el botón de la cabecera no vuelve al activar la opción")
  expect(button:IsShown(), "el botón de encima de la AH no vuelve al activar la opción")
  expect(list._anchorTo == button, "la lista de compra no vuelve junto al botón")
end, { state = "empty" })

test("opción: quien quitó el botón de encima de la AH sigue sin los botones de escanear", function()
  local savedDB = ES.db
  -- Lo quitó antes (noAHButton): sigue sin ellos, cabecera incluida
  local m = { noAHButton = true }
  ES.db = m
  ES:MigrateWindowOptions()
  expect_eq(m.noScanButtons, true, "volvieron los botones que había quitado")
  expect_eq(m.noAHButton, nil, "queda la opción de antes")
  -- No lo quitó: siguen a la vista, aunque los apagara la prueba de desactivados por defecto
  m = { scanButtons = nil, noAHButton = false, sellWindowSplit = true }
  ES.db = m
  ES:MigrateWindowOptions()
  expect_eq(m.noScanButtons, nil, "se quitaron los botones sin pedirlo")
  expect(ES:ScanButtonsOn(), "los botones no salen")
  ES.db = savedDB
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

-- Sin enlace y sin el objeto en el juego, el pergamino se reconoce por su nombre real
-- (spec ah-purchase-tracking): «Recipe: Elixir of Detect Lesser Invisibility» enseña
-- Draught of Detect Lesser Invisibility, y quitarle el prefijo y buscar la receta no lo
-- encontraba. (Si cuenta de camino, la fila de la ruta pasa a comprada: Ledger.OnWay)
test("compra de un pergamino sin enlace: se reconoce por su nombre aunque no sea el de la receta", function()
  OpenAH()
  ES.ahOpen = true
  ERR_AUCTION_WON_S = "You won an auction for %s"
  UNCACHED[3832], UNCACHED[5640] = true, true
  local id, n = ES.Ledger.ParseAuctionWon("You won an auction for Recipe: Elixir of Detect Lesser Invisibility")
  expect(id == 3832 and n == 1, "no reconoce el pergamino de Draught of Detect Lesser Invisibility: %s %s", tostring(id), tostring(n))
  FireEvent("CHAT_MSG_SYSTEM", "You won an auction for Recipe: Elixir of Detect Lesser Invisibility")
  expect_eq(ES.Ledger.OnWay(3832), 1, "pergamino de camino al buzón")
  -- (el que se llama como la receta, como hasta ahora)
  id, n = ES.Ledger.ParseAuctionWon("You won an auction for Recipe: Rage Potion")
  expect(id == 5640 and n == 1, "no reconoce el pergamino de Rage Potion: %s %s", tostring(id), tostring(n))
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

-- El aviso "Compra detectada... cuenta ya para la ruta y la lista de compra" solo con lo
-- que piden la Lista de compra o una ruta empezada (salía con cualquier compra:
-- Stonescale Eel sin ruta ni lista)
local STONESCALE_EEL, LINEN_CLOTH = 13757, 2589
local function BuyAndSaid(itemID)
  local key = ES.L["Compra detectada: %s ×%d. Cuenta ya para la ruta y la lista de compra."]:match("^(.-)%%")
  local printed = #PRINTS
  OpenAH()
  ES.ahOpen = true
  ERR_AUCTION_WON_S = "You won an auction for %s"
  NOW = NOW + 1
  FireEvent("CHAT_MSG_SYSTEM", string.format("You won an auction for |cffffffff|Hitem:%d::|h[x]|h|rx1", itemID))
  local said = false
  for i = printed + 1, #PRINTS do
    if PRINTS[i]:find(key, 1, true) then said = true end
  end
  return said
end

test("compra en la AH: solo avisa si la pide la lista de compra o la ruta", function()
  expect(not BuyAndSaid(STONESCALE_EEL), "avisa de una compra que no pide nada")
  expect_eq(ES:HaveForShopping(STONESCALE_EEL), 1, "la compra no se apuntó (debe contar si luego se añade)")
  ES.Shopping.Add("calc", "peces", { { itemID = STONESCALE_EEL, quantity = 5, unit = 100, source = "ah" } })
  expect(BuyAndSaid(STONESCALE_EEL), "no avisa de un material de la lista de compra")
end)

test("compra en la AH: avisa de un material de la ruta empezada", function()
  StartRoute("Tailoring", 1, 75)
  expect(BuyAndSaid(LINEN_CLOTH), "no avisa de un material de la ruta empezada")
  expect(not BuyAndSaid(STONESCALE_EEL), "avisa de una compra que la ruta no pide")
end)

---------------------------------------------------------------------------
-- Lo comprado deja de contar al llegar a las bolsas aunque el addon esté cerrado
-- (Discord: sacaba del buzón las Mithril Bar compradas, las gastaba con el addon
-- cerrado y la lista seguía diciendo "tienes 70 de 70"; la ruta, 140 Mithril Ore)
---------------------------------------------------------------------------
local MITHRIL_BAR, MITHRIL_ORE, SILVERLEAF = 3860, 3858, 765

-- Gana una subasta de n unidades con la AH abierta (el mensaje del juego)
local function WinAuction(itemID, n)
  ERR_AUCTION_WON_S = "You won an auction for %s"
  NOW = NOW + 1 -- (dos compras iguales son dos mensajes, en fotogramas distintos)
  FireEvent("CHAT_MSG_SYSTEM", string.format("You won an auction for |cffffffff|Hitem:%d::|h[x]|h|rx%d", itemID, n))
end

-- Cierra la AH: sin ninguna ventana del addon que mire las bolsas
local function CloseAH()
  AuctionFrame:Hide()
  FireEvent("AUCTION_HOUSE_CLOSED")
  NOW = NOW + 60 -- (fuera ya del margen en que se lee el chat tras cerrarla)
  RunTimers()
end

-- Las bolsas pasan a tener n del objeto (lo que el juego avisa al terminar el cambio)
local function SetBags(itemID, n)
  BAGS[itemID] = n > 0 and n or nil
  FireEvent("BAG_UPDATE_DELAYED")
  RunTimers()
end

test("compra sacada del buzón y gastada con el addon cerrado: ya no cuenta", function()
  OpenAH()
  ES.ahOpen = true
  WinAuction(MITHRIL_BAR, 70)
  expect_eq(ES:HaveForShopping(MITHRIL_BAR), 70, "comprado y aún en el correo")
  CloseAH()
  SetBags(MITHRIL_BAR, 70) -- (sacadas del buzón)
  SetBags(MITHRIL_BAR, 0)  -- (gastadas fabricando)
  expect_eq(ES:HaveForShopping(MITHRIL_BAR), 0, "sigue contando lo que ya se gastó")
end)

test("varias compras sacadas y gastadas con el addon cerrado no se acumulan", function()
  for _ = 1, 2 do
    OpenAH()
    ES.ahOpen = true
    WinAuction(MITHRIL_ORE, 70)
    CloseAH()
    SetBags(MITHRIL_ORE, 70)
    SetBags(MITHRIL_ORE, 0)
  end
  expect_eq(ES:HaveForShopping(MITHRIL_ORE), 0, "Mithril Ore fantasma")
end)

test("gastar lo que ya tenías antes de recoger la compra no la confunde", function()
  BAGS[SILVERLEAF] = 10
  OpenAH()
  ES.ahOpen = true
  WinAuction(SILVERLEAF, 21)
  expect_eq(ES:HaveForShopping(SILVERLEAF), 31, "10 en las bolsas y 21 en el correo")
  CloseAH()
  SetBags(SILVERLEAF, 0)  -- (gastas las 10 que llevabas)
  SetBags(SILVERLEAF, 21) -- (sacas las 21 del buzón)
  expect_eq(ES:HaveForShopping(SILVERLEAF), 21, "las de las bolsas, ni más ni menos")
end)

test("la compra que sigue en el buzón cuenta aunque cambien las bolsas, hasta las 2 h", function()
  OpenAH()
  ES.ahOpen = true
  WinAuction(SILVERLEAF, 21)
  CloseAH()
  SetBags(2589, 5)  -- (otras cosas: botín, el vendedor...)
  SetBags(2589, 0)
  expect_eq(ES:HaveForShopping(SILVERLEAF), 21, "sin ir al buzón")
  NOW = NOW + 2 * 3600 + 1
  SetBags(2589, 3)
  expect_eq(ES:HaveForShopping(SILVERLEAF), 0, "pasadas 2 h")
  expect_eq(#(ES.charData.ahOnWay or {}), 0, "la compra caducada sigue guardada")
end)

test("sin compras de camino, cambiar las bolsas no crea nada", function()
  ES.charData.ahOnWay = nil
  SetBags(2589, 5)
  expect_eq(ES.charData.ahOnWay, nil, "crea la lista de camino")
end)

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
    -- (gone: las baratas que se van al día, las que había menos las que seguían)
    local gone = hours > 0 and (tot - rem) / hours * 24 or nil
    if exposure < 24 or hours < 6 then return { known = false, rem = rem, tot = tot, hours = hours, gone = gone } end
    local life = hazard > 0 and exposure / hazard or math.huge
    return { known = true, flag = life >= 24, life = life, rem = rem, tot = tot, hours = hours, gone = gone }
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

---------------------------------------------------------------------------
-- Escaneo grande con precios realistas (lighter-memory): memoria temporal del
-- escaneo y lo guardado en ES.db.track, con los mismos resultados
---------------------------------------------------------------------------
local BIG_SCAN = 150000

-- ¿Iguales, también dentro de las tablas?
local function SameDeep(a, b, what)
  if type(a) ~= "table" or type(b) ~= "table" then
    if a ~= b then error(string.format("%s: antes %s, ahora %s", what, tostring(a), tostring(b)), 0) end
    return
  end
  for k, v in pairs(a) do SameDeep(v, b[k], what .. "." .. tostring(k)) end
  for k, v in pairs(b) do
    if a[k] == nil then error(string.format("%s.%s: antes nada, ahora %s", what, tostring(k), tostring(v)), 0) end
  end
end

-- Precio por unidad más bajo de cada objeto seguido (con precio de compra)
local function MinUnits(auctions)
  local min = {}
  for _, a in ipairs(auctions) do
    if a.buyout > 0 and ES.History:IsTracked(a.item) then
      local u = a.buyout / a.count
      if not min[a.item] or u < min[a.item] then min[a.item] = u end
    end
  end
  return min
end

-- Hace un escaneo completo (con Auctionator) de `auctions`, 16 min después del anterior
local function DoScan(auctions)
  AUCTIONS = auctions
  NOW = NOW + 16 * 60
  AuctionFrame:Show()
  FireEvent("AUCTION_HOUSE_SHOW")
  RunTimers()
  ES.Scanner:Start()
  RunTimers()
  expect(not ES.Scanner:IsBusy(), "el escaneo no termina")
  AuctionFrame:Hide()
  FireEvent("AUCTION_HOUSE_CLOSED")
  RunTimers()
end

-- Memoria (MB) que crea un escaneo con el recolector parado: lo que el jugador ve
-- justo al acabar. (Sin dejar que el addon ayude al recolector mientras se mide)
local function ScanAllocMB(auctions)
  AUCTIONS = auctions
  local real = collectgarbage
  local before = KB()
  real("stop")
  collectgarbage = function(opt, ...)
    if opt == "step" or opt == "collect" then return false end
    return real(opt, ...)
  end
  local ok, err = pcall(DoScan, auctions)
  local peak = real("count")
  collectgarbage = real
  real("restart")
  if not ok then error(err, 0) end
  return (peak - before) / 1024
end

test("subastas realistas: unas pocas cerca del mínimo", function()
  local auctions = Fixtures.RealisticAuctions(BIG_SCAN)
  local min = MinUnits(auctions)
  local near, all = 0, 0
  for _, a in ipairs(auctions) do
    if a.buyout > 0 and min[a.item] then
      all = all + 1
      if a.buyout / a.count <= min[a.item] * 1.10 then near = near + 1 end
    end
  end
  local share = near / all
  note("%d subastas de objetos seguidos, %.0f %% cerca del mínimo", all, share * 100)
  expect(share >= 0.10 and share <= 0.30, "%.0f %% cerca del mínimo (se esperaba un 15-20 %%)", share * 100)
end, { state = "empty" })

-- Lo que creaban estos dos escaneos antes de lighter-memory (medido con ScanAllocMB y
-- el código de entonces): cada uno puede crear como mucho la mitad
local REF_ALLOC_MB = { 74.9, 88.4 }

test("escaneo grande: cada escaneo crea la mitad o menos de memoria que antes", function()
  InstallAuctionator()
  local first = Fixtures.RealisticAuctions(BIG_SCAN)
  local m1 = ScanAllocMB(first)
  local m2 = ScanAllocMB(Fixtures.RealisticAuctions(BIG_SCAN, first))
  note("1.er escaneo %.1f MB (antes %.1f), 2.º escaneo %.1f MB (antes %.1f), recolector parado",
    m1, REF_ALLOC_MB[1], m2, REF_ALLOC_MB[2])
  expect(m1 <= REF_ALLOC_MB[1] / 2, "el 1.er escaneo crea %.1f MB (tope %.1f)", m1, REF_ALLOC_MB[1] / 2)
  expect(m2 <= REF_ALLOC_MB[2] / 2, "el 2.º escaneo crea %.1f MB (tope %.1f)", m2, REF_ALLOC_MB[2] / 2)
end, { state = "empty" })

-- El resumen de cada objeto como lo guardaba el escaneo antes de lighter-memory (copia
-- de Scanner:Process, Finish y BuildLadder de entonces: no cambiarla con Scanner.lua)
local function RefSummary(auctions)
  local items = {}
  for _, a in ipairs(auctions) do
    local e = items[a.item]
    if not e then
      e = { listings = 0, quantity = 0, buyoutQty = 0, buyoutTotal = 0, owners = {} }
      items[a.item] = e
    end
    e.listings, e.quantity = e.listings + 1, e.quantity + a.count
    local owner = a.owner ~= "" and a.owner or "?"
    if owner ~= "?" then
      e.owners[owner] = (e.owners[owner] or 0) + 1
      e.knownOwners = (e.knownOwners or 0) + 1
    end
    if ES.History:IsTracked(a.item) and a.buyout > 0 then
      e.ladder = e.ladder or {}
      local unit = math.floor(a.buyout / a.count + 0.5)
      e.ladder[unit] = (e.ladder[unit] or 0) + a.count
    end
    if a.buyout > 0 then
      local unit = a.buyout / a.count
      if not e.minUnit or unit < e.minUnit then e.minUnit = unit end
      e.buyoutQty, e.buyoutTotal = e.buyoutQty + a.count, e.buyoutTotal + a.buyout
    end
  end
  local function Ladder(levels)
    if not levels then return nil end
    local prices, total = {}, 0
    for price, qty in pairs(levels) do prices[#prices + 1] = price total = total + qty end
    table.sort(prices)
    local median, acc = nil, 0
    for _, price in ipairs(prices) do
      acc = acc + levels[price]
      if acc >= total / 2 then median = price break end
    end
    local flat = {}
    for i = 1, math.min(#prices, 39) do flat[#flat + 1] = prices[i] flat[#flat + 1] = levels[prices[i]] end
    if #prices >= 40 then
      local qty, value = 0, 0
      for i = 40, #prices do qty = qty + levels[prices[i]] value = value + levels[prices[i]] * prices[i] end
      flat[#flat + 1] = math.floor(value / qty + 0.5)
      flat[#flat + 1] = qty
    end
    return flat, median
  end
  local out = {}
  for id, e in pairs(items) do
    local sellers, top = 0, 0
    for _, n in pairs(e.owners) do sellers = sellers + 1 if n > top then top = n end end
    local ladder, median = Ladder(e.ladder)
    out[id] = { listings = e.listings, quantity = e.quantity, minUnit = e.minUnit and math.floor(e.minUnit + 0.5) or nil,
      avgUnit = e.buyoutQty > 0 and math.floor(e.buyoutTotal / e.buyoutQty + 0.5) or nil, sellers = sellers > 0 and sellers or nil,
      topShare = (e.knownOwners or 0) * 2 >= e.listings and math.floor(top / e.knownOwners * 100 + 0.5) / 100 or nil,
      ladder = ladder, median = median }
  end
  return out
end

test("escaneo grande: el resumen guardado (escalera, vendedores, mediana) es el de antes", function()
  InstallAuctionator()
  local first = Fixtures.RealisticAuctions(30000)
  local second = Fixtures.RealisticAuctions(30000, first)
  DoScan(first)
  DoScan(second) -- (el segundo, con escaleras de otro tamaño que las del primero)
  local scan = ES.db.scans[ES:RealmKey()]
  local want, n, ladders = RefSummary(second), 0, 0
  SameDeep(want, scan.items, "items")
  for _, e in pairs(want) do
    n = n + 1
    if e.ladder then ladders = ladders + 1 end
  end
  note("%d objetos iguales, %d con escalera", n, ladders)
  expect(ladders > 1000, "pocos objetos con escalera: la prueba no comprueba nada")
end, { state = "empty" })

-- Las firmas de un escaneo como las montaba antes el escaneo: todas las subastas de los
-- objetos seguidos (Scanner:Process antes de lighter-memory)
local function FullSigs(auctions)
  local S, t = ES.History, {}
  for _, a in ipairs(auctions) do
    if S:IsTracked(a.item) then
      S.AddAuction(t, S.Signature(a.item, a.count, a.buyout, a.owner ~= "" and a.owner or "?"), a.tl)
    end
  end
  return t
end

-- "Baratas que siguen" como se calculaban antes, con todas las firmas del escaneo
-- anterior y del nuevo. Copia de History:Record antes de lighter-memory: no cambiarla
-- al cambiar History.lua
local function RefStuck(prev, sigs)
  local minUnit = {}
  for sig in pairs(prev) do
    local item, count, buyout = sig:match("^(%d+):(%d+):(%d+):")
    count, buyout = tonumber(count), tonumber(buyout)
    if buyout > 0 and count > 0 and (not minUnit[item] or buyout / count < minUnit[item]) then
      minUnit[item] = buyout / count
    end
  end
  local rem, tot = {}, {}
  for sig, packed in pairs(prev) do
    local item, count, buyout = sig:match("^(%d+):(%d+):(%d+):")
    count, buyout = tonumber(count), tonumber(buyout)
    if buyout > 0 and count > 0 and buyout / count <= minUnit[item] * 1.10 then
      local prevCounts, prevTotal = ES.History.Unpack(packed)
      local remaining = 0
      if sigs[sig] then
        local nowCounts, nowTotal = ES.History.Unpack(sigs[sig])
        local new = math.max(0, nowTotal - prevTotal, nowCounts[4] - prevCounts[4])
        remaining = math.min(prevTotal, nowTotal - new)
      end
      tot[item] = (tot[item] or 0) + prevTotal
      rem[item] = (rem[item] or 0) + remaining
    end
  end
  local parts = {}
  for item, n in pairs(tot) do parts[#parts + 1] = item .. ":" .. rem[item] .. ":" .. n end
  return ";" .. table.concat(parts, ";")
end

local function LastEntry() local h = ES.History:Entries() return h[#h] end

test("track: solo las subastas cerca del mínimo (100, 105 y 110 sí; 150 y solo puja no)", function()
  local S, sigs = ES.History, {}
  for _, price in ipairs({ 100, 105, 110, 150 }) do S.AddAuction(sigs, S.Signature(2318, 1, price, "Ana"), 4) end
  S.AddAuction(sigs, S.Signature(2318, 1, 0, "Ana"), 4)
  local key = ES:RealmKey()
  S:Record(key, sigs, ";1:1:1", NOW)
  local got = {}
  S.EachSig(ES.db.track[key], function(sig) got[#got + 1] = sig end)
  table.sort(got)
  expect_eq(table.concat(got, " "), "2318:1:100:Ana 2318:1:105:Ana 2318:1:110:Ana", "subastas guardadas")
end, { state = "empty" })

test("track: lo guardado cubre la competencia (STUCK_BAND >= WALL_BAND)", function()
  expect(ES.History.STUCK_BAND >= ES.Market.WALL_BAND,
    "History.STUCK_BAND (%s) es menor que Market.WALL_BAND (%s): la competencia saldría de menos subastas",
    tostring(ES.History.STUCK_BAND), tostring(ES.Market.WALL_BAND))
end, { state = "empty" })

test("track reducido: mismas baratas que siguen, competencia y señales que guardando todas", function()
  InstallAuctionator()
  local key = ES:RealmKey()
  local scans = { Fixtures.RealisticAuctions(30000) }
  scans[2] = Fixtures.RealisticAuctions(30000, scans[1])
  scans[3] = Fixtures.RealisticAuctions(30000, scans[2])
  for i, auctions in ipairs(scans) do
    DoScan(auctions)
    if i > 1 then
      local entry = LastEntry()
      expect(entry.stuck and #entry.stuck > 100, "escaneo %d: sin baratas que siguen", i)
      expect_eq(Parts(entry.stuck), Parts(RefStuck(FullSigs(scans[i - 1]), FullSigs(auctions))),
        "baratas que siguen del escaneo " .. i)
    end
  end
  -- Señales y competencia con lo guardado ahora, y con todas las subastas (como antes)
  local ids = {}
  for id in pairs(MinUnits(scans[3])) do ids[#ids + 1] = id end
  table.sort(ids)
  BuildIndexNow()
  local got = {}
  for _, id in ipairs(ids) do got[id] = { signals = ES.Market:Signals(id), wall = ES.Market:Wall(id) } end
  local track = ES.db.track[key]
  -- (otra hora: el índice se rehace; la hora de track no cuenta en ninguna señal)
  ES.db.track[key] = { time = track.time + 1, packed = ES.History.Pack(FullSigs(scans[3])), v = 3 }
  expect(#ES.db.track[key].packed > #track.packed * 2, "lo guardado no es más pequeño que todas las subastas")
  BuildIndexNow()
  local walls = 0
  for _, id in ipairs(ids) do
    SameDeep(ES.Market:Wall(id), got[id].wall, id .. ".wall")
    SameDeep(ES.Market:Signals(id), got[id].signals, id .. ".signals")
    if got[id].wall.known then walls = walls + 1 end
  end
  note("%d objetos comparados, %d con competencia", #ids, walls)
  expect(walls > 100, "pocos objetos con competencia: la prueba no comprueba nada")
end, { state = "empty" })

test("track: primer escaneo tras actualizar, con todas las subastas guardadas por la versión anterior", function()
  InstallAuctionator()
  local key = ES:RealmKey()
  local first = Fixtures.RealisticAuctions(30000)
  local second = Fixtures.RealisticAuctions(30000, first)
  local full1 = FullSigs(first)
  ES.History:Entries() -- (crea el historial del reino)
  ES.db.track = { [key] = { time = NOW, packed = ES.History.Pack(full1), v = 3 } }
  DoScan(second)
  local entry = LastEntry()
  expect(entry.stuck and #entry.stuck > 100, "no se comparó con lo guardado por la versión anterior")
  expect_eq(Parts(entry.stuck), Parts(RefStuck(full1, FullSigs(second))), "baratas que siguen")
  -- Lo nuevo, solo las cercanas al mínimo, y todas ellas
  local min, n = MinUnits(second), 0
  ES.History.EachSig(ES.db.track[key], function(sig)
    local id, count, buyout = sig:match("^(%d+):(%d+):(%d+):")
    id, count, buyout = tonumber(id), tonumber(count), tonumber(buyout)
    expect(buyout > 0 and buyout / count <= min[id] * 1.10, "guardada una subasta lejos del mínimo: %s", sig)
    n = n + 1
  end)
  local want = 0
  for _ in pairs(ES.History.NearMin(FullSigs(second))) do want = want + 1 end
  expect_eq(n, want, "subastas guardadas cerca del mínimo")
end, { state = "empty" })

test("track: con precios realistas, lo guardado ocupa 1/4 o menos que todas las subastas", function()
  InstallAuctionator()
  local auctions = Fixtures.RealisticAuctions(BIG_SCAN)
  DoScan(auctions)
  local kept = #ES.db.track[ES:RealmKey()].packed
  local all = #ES.History.Pack(FullSigs(auctions))
  note("guardado %.2f MB; todas %.2f MB (%.0f %%)", kept / 1048576, all / 1048576, kept / all * 100)
  expect(kept <= all / 4, "lo guardado es el %.0f %% de todas las subastas (tope 25 %%)", kept / all * 100)
end, { state = "empty" })

---------------------------------------------------------------------------
-- Tras un escaneo, el addon ayuda al recolector de basura (Jobs.CollectGarbage)
---------------------------------------------------------------------------
test("tras un escaneo grande, la basura se recoge en segundos", function()
  InstallAuctionator()
  local auctions = Fixtures.RealisticAuctions(BIG_SCAN)
  KB()
  collectgarbage("stop") -- (el recolector automático parado: solo recoge lo que ayude el addon)
  local ok, err = pcall(DoScan, auctions)
  RunTimers(10)
  local raw = collectgarbage("count")
  collectgarbage("restart")
  if not ok then error(err, 0) end
  local live = KB()
  note("al acabar %.1f MB; tras recoger toda la basura %.1f MB (+%.0f %%)", raw / 1024, live / 1024, (raw / live - 1) * 100)
  expect(raw <= live * 1.25, "quedan %.1f MB sin recoger sobre %.1f MB (tope 25 %%)", (raw - live) / 1024, live / 1024)
end, { state = "empty" })

test("ayudar al recolector: como mucho 2 ms por fotograma", function()
  local real, savedClock = collectgarbage, debugprofilestop
  local clock, steps, frames, worst = 0, 0, {}, 0
  debugprofilestop = function() return clock end
  collectgarbage = function(opt, ...)
    if opt ~= "step" then return real(opt, ...) end
    clock = clock + 0.3 -- (lo que tarda un paso)
    steps = steps + 1
    return false
  end
  local ok, err = pcall(function()
    ES.Jobs.CollectGarbage()
    for _ = 1, 20 do
      local before = clock
      local t = table.remove(TIMERS, 1)
      if not t then break end
      t.f()
      if clock - before > worst then worst = clock - before end
      frames[#frames + 1] = clock - before
    end
  end)
  collectgarbage, debugprofilestop = real, savedClock
  for i = #TIMERS, 1, -1 do TIMERS[i] = nil end
  if not ok then error(err, 0) end
  note("%d pasos en %d fotogramas; el más largo %.1f ms", steps, #frames, worst)
  expect(#frames > 1 and steps > 0, "no ayudó al recolector")
  expect(worst <= ES.Jobs.GC_BUDGET + 0.3 + 1e-9, "un fotograma de %.1f ms (tope %.1f + un paso)", worst, ES.Jobs.GC_BUDGET)
end, { state = "empty" })

test("ayudar al recolector: si el juego no deja, el escaneo se guarda igual y sin errores", function()
  InstallAuctionator()
  local real = collectgarbage
  local tried = 0
  collectgarbage = function(opt, ...)
    if opt == "step" then tried = tried + 1 error("collectgarbage: no permitido") end
    return real(opt, ...)
  end
  local ok, err = pcall(DoScan, Fixtures.RealisticAuctions(3000))
  collectgarbage = real
  if not ok then error(err, 0) end
  expect(tried > 0, "no llegó a intentarlo")
  expect(ES.db.scans[ES:RealmKey()], "no se guardó el escaneo")
  -- Y sin collectgarbage
  collectgarbage = nil
  ok, err = pcall(DoScan, Fixtures.RealisticAuctions(3000))
  collectgarbage = real
  if not ok then error(err, 0) end
  expect_eq(ES.db.scans[ES:RealmKey()].total, 3000, "no se guardó el segundo escaneo")
end, { state = "empty" })

test("ayudar al recolector: en combate espera a que acabe", function()
  InstallAuctionator()
  local real = collectgarbage
  local steps = 0
  collectgarbage = function(opt, ...)
    if opt == "step" then steps = steps + 1 return false end
    return real(opt, ...)
  end
  IN_COMBAT = true
  local ok, err = pcall(DoScan, Fixtures.RealisticAuctions(3000))
  local inCombat = steps
  IN_COMBAT = false
  if ok then ok, err = pcall(RunTimers, 5) end
  collectgarbage = real
  if not ok then error(err, 0) end
  expect_eq(inCombat, 0, "pasos del recolector en combate")
  expect(steps > 0, "al salir del combate no ayudó al recolector")
end, { state = "empty" })

-- (spec auction-house-detection) La neutral: subastador sin facción en una ciudad
-- goblin (Gadgetzan en Tanaris, 1446; Bahía del Botín en Tuercespina, 1434)
test("AH neutral: sin soporte, sin errores", function()
  NPC_FACTION = nil
  SetPlayerMap(1446)
  OpenAH()
  expect(ES.neutralAH, "no detecta la neutral")
  expect(not ES.ahOpen, "la neutral cuenta como AH abierta")
  NPC_FACTION = "Alliance"
end, { state = "scan" })

test("AH neutral: también en Bahía del Botín (Tuercespina)", function()
  NPC_FACTION = nil
  SetPlayerMap(1434)
  OpenAH()
  expect(ES.neutralAH, "no detecta la neutral de Bahía del Botín")
  expect(not ES.ahOpen, "la neutral cuenta como AH abierta")
end, { state = "scan" })

-- El subastador Skyborne de Valanaar (zona de WoW Forever) no tiene facción, pero
-- conecta con la AH de tu facción: antes contaba como la neutral y el addon no escaneaba
test("AH sin facción fuera de las ciudades goblin (Skyborne): es la de tu facción", function()
  local text = ES.L["Crafter's Journal aún no funciona en la Casa de Subastas neutral. Aquí no escanea ni abre sus ventanas; tus rutas y precios siguen siendo los de la Casa de Subastas de tu facción."]
  NPC_FACTION = nil
  SetPlayerMap(9999) -- (un mapa que no es Tuercespina, Tanaris ni Cuna del Invierno)
  OpenAH()
  expect(not ES.neutralAH, "Skyborne cuenta como la neutral")
  expect(ES.ahOpen, "Skyborne no cuenta como AH abierta")
  expect(not ES:IsNeutralAH(), "Skyborne usa la comisión de la neutral")
  local d = ES.ConfirmFrame and ES.ConfirmFrame()
  expect(not (d and d:IsShown() and d.text._text == text), "sale el aviso de la neutral en Skyborne")
end, { state = "scan" })

test("AH sin facción y el juego no da el mapa: es la de tu facción", function()
  NPC_FACTION = nil
  SetPlayerMap(nil)
  OpenAH()
  expect(not ES.neutralAH, "sin mapa cuenta como la neutral")
  expect(ES.ahOpen, "sin mapa no cuenta como AH abierta")
end, { state = "scan" })

-- El mapa queda en el diario del escaneo, para ver en el juego qué mapa da cada AH
test("al abrir la AH, el diario del escaneo apunta el mapa", function()
  SetPlayerMap(1453)
  OpenAH()
  local found
  for _, line in ipairs(ES.db.scanLog or {}) do
    if line:find("mapa 1453", 1, true) then found = true end
  end
  expect(found, "el diario no apunta el mapa: %s", table.concat(ES.db.scanLog or {}, " | "))
end, { state = "scan" })

-- Antes era una línea en el chat que pasaba desapercibida
test("AH neutral: una ventana avisa de que aún no funciona (una vez por sesión, se puede apagar)", function()
  local text = ES.L["Crafter's Journal aún no funciona en la Casa de Subastas neutral. Aquí no escanea ni abre sus ventanas; tus rutas y precios siguen siendo los de la Casa de Subastas de tu facción."]
  NPC_FACTION = nil
  SetPlayerMap(1446)
  OpenAH()
  local d = expect(ES.ConfirmFrame(), "no sale ninguna ventana")
  expect(d:IsShown(), "no sale la ventana del aviso")
  expect_eq(d.text._text, text, "texto del aviso")
  expect(d.ok:IsShown() and not d.cancel:IsShown(), "el aviso debería tener un solo botón (Aceptar)")
  -- Al cerrar la AH se va
  AuctionFrame:Hide()
  FireEvent("AUCTION_HOUSE_CLOSED")
  RunTimers()
  expect(not d:IsShown(), "el aviso sigue tras cerrar la AH")
  -- Una vez por sesión
  OpenAH()
  expect(not d:IsShown(), "el aviso sale en cada visita")
  -- En otra sesión vuelve; con "No volver a mostrar este aviso" ya no
  ES.neutralWarned = nil
  AuctionFrame:Hide()
  FireEvent("AUCTION_HOUSE_CLOSED")
  RunTimers()
  OpenAH()
  expect(d:IsShown(), "el aviso no vuelve en otra sesión")
  d.check:SetChecked(true)
  d.ok:GetScript("OnClick")(d.ok)
  expect(not d:IsShown(), "Aceptar no cierra el aviso")
  expect_eq(ES.db.noNeutralAHNotice, true, "la casilla no apaga el aviso")
  ES.neutralWarned = nil
  AuctionFrame:Hide()
  FireEvent("AUCTION_HOUSE_CLOSED")
  RunTimers()
  OpenAH()
  expect(not d:IsShown(), "el aviso sale apagado")
  NPC_FACTION = "Alliance"
end, { state = "scan" })

-- Anunciar en la AH (spec ah-posting) ---------------------------------------------
-- GitHub #10: cuando la AH pide confirmar un anuncio del addon (PostItem devuelve
-- needsConfirmation), el «Aceptar» del juego no hace nada con él: el addon esconde esa
-- ventana, pregunta con la suya y confirma con ConfirmPostItem / ConfirmPostCommodity

local POST_ITEM = 2318 -- Light Leather
local function Before(key) return (ES.L[key]:match("^(.-)%%")) end
local function SaidSince(from, text)
  for i = from + 1, #PRINTS do if PRINTS[i]:find(text, 1, true) then return PRINTS[i] end end
end

-- La AH de Forever simulada mientras dura `fn(ah)`. opts.needs: la AH pide confirmar;
-- opts.commodity: es un material; opts.confirmError: confirmar da error. ah.calls: las
-- llamadas a la AH con sus argumentos; ah.popup: la ventana de confirmación del juego
local function PostingAH(opts, fn)
  local saved = { C_AuctionHouse, ItemLocation, ES.IsAuctionHouseOpen, StaticPopup_Visible, StaticPopup_Hide }
  local ah = { calls = {}, popup = false }
  local function Call(name, needs, fails)
    return function(...)
      ah.calls[#ah.calls + 1] = { name, ... }
      if fails then error("Item not found") end
      if needs then
        ah.popup = true -- (el juego saca su ventana con el aviso)
        FireEvent("AUCTION_HOUSE_POST_WARNING")
      end
      return needs
    end
  end
  C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return true end,
    GetItemCommodityStatus = function() return opts.commodity and 2 or 1 end,
    PostItem = Call("PostItem", opts.needs), PostCommodity = Call("PostCommodity", opts.needs),
    ConfirmPostItem = Call("ConfirmPostItem", false, opts.confirmError),
    ConfirmPostCommodity = Call("ConfirmPostCommodity", false, opts.confirmError),
  }
  ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
  StaticPopup_Visible = function(name) return name == "AUCTION_HOUSE_POST_WARNING" and ah.popup end
  StaticPopup_Hide = function(name) if name == "AUCTION_HOUSE_POST_WARNING" then ah.popup = false end end
  ES.IsAuctionHouseOpen = function() return true end
  BAGS[POST_ITEM] = 5
  ES.Ledger.pendingPost, ES.Ledger.ahBusy = nil, nil
  local ok, err = pcall(fn, ah)
  local d = ES.ConfirmFrame()
  if d then d.pending = nil d:Hide() end
  ES.Ledger.pendingPost, BAGS[POST_ITEM] = nil, nil
  C_AuctionHouse, ItemLocation, ES.IsAuctionHouseOpen, StaticPopup_Visible, StaticPopup_Hide = unpack(saved, 1, 5)
  if not ok then error(err, 0) end
end

test("pregunta sin casilla (noCheck): siempre pregunta, y Escape la cancela", function()
  local yes, cancels = 0, 0
  ES.db.noPostConfirm = true -- (el aviso de anunciar apagado con su casilla)
  ES:Confirm({ key = "noPostConfirm", title = "T", text = "X", onYes = function() yes = yes + 1 end })
  expect_eq(yes, 1, "con la opción apagada, el aviso normal no se hace sin preguntar")
  ES:Confirm({ noCheck = true, title = "T", text = "X", onYes = function() yes = yes + 1 end,
    onCancel = function() cancels = cancels + 1 end })
  local d = ES.ConfirmFrame()
  expect(d._shown and yes == 1, "la pregunta sin casilla se hizo sin preguntar")
  expect(not d.check._shown and not d.note._shown, "la pregunta sin casilla enseña la casilla")
  d:Hide() -- (Escape)
  expect_eq(cancels, 1, "Escape no cancela la pregunta")
  ES.db.noPostConfirm = nil
  ES:Confirm({ key = "noPostConfirm", title = "T", text = "X", onYes = function() end, onNo = function() yes = -1 end })
  expect(d.check._shown, "el aviso normal ya no enseña su casilla")
  d:Hide()
  expect(yes ~= -1, "Escape hizo la acción de «No» (onNo)")
end, { state = "scan" })

-- Anuncia 5 a 1g cada uno, 24 h, y deja pasar el fotograma. Devuelve la pregunta del addon
local function Post()
  ES.Ledger:PostOnAH(POST_ITEM, 5, 10000, 24)
  RunTimers(0)
  local d = ES.ConfirmFrame()
  return d and d._shown and d.pending and d or nil
end

-- El panel de vender de la AH decía «2 × 8s 99c», su pregunta «a 8s» y anunciaba a 8s:
-- se perdían los cobres (Discord). Todo anuncio va con cobres (Forever los admite), y la
-- pregunta dice el mismo precio que la fila
test("anunciar con cobres: el panel de vender anuncia a 8s 99c, no a 8s", function()
  PostingAH({ commodity = true }, function(ah)
    ES.db.noPostConfirm = nil
    ES.AuctionSell.Post(POST_ITEM, 2, 899, 8)
    local d = expect(ES.ConfirmFrame(), "no sale la pregunta de anunciar")
    local text = tostring(d.text:GetText())
    expect(text:find(ES.Money(899), 1, true), "la pregunta no dice 8s 99c: %s", text)
    d.pending.onYes()
    local call = expect(ah.calls[1], "no llama a la AH")
    expect_eq(call[1], "PostCommodity", "llamada")
    expect_eq(call[5], 899, "precio anunciado")
    ES.Ledger.pendingPost = nil
    ES.Ledger:PostOnAH(POST_ITEM, 1, 12345, 2) -- (y el de BulkMoney, igual)
    call = expect(ah.calls[2], "no llama a la AH la segunda vez")
    expect_eq(call[5], 12345, "precio con cobres")
  end)
end, { state = "scan" })

-- La duración de las opciones (ES.db.auctionHours) vale también para lo que anuncia la
-- ruta (Sell.Post sin duración); sin fijar, 24 h. Y la pregunta dice esa duración
test("duración de las opciones: lo que anuncia la ruta va con ella (sin fijar, 24 h)", function()
  PostingAH({ commodity = true }, function(ah)
    ES.db.noPostConfirm = nil
    for i, case in ipairs({ { nil, 3, 24 }, { 2, 1, 2 }, { 8, 2, 8 }, { 24, 3, 24 } }) do
      ES.db.auctionHours = case[1]
      ES.Ledger.pendingPost = nil
      ES.AuctionSell.Post(POST_ITEM, 2, 899, nil) -- (como la ruta: SaleAction, ProfessionUI.lua)
      local d = expect(ES.ConfirmFrame(), "no sale la pregunta de anunciar")
      local text = tostring(d.text:GetText())
      expect(text:find("(" .. case[3] .. " h)", 1, true), "%s h: la pregunta no dice la duración: %s", tostring(case[1]), text)
      d.pending.onYes()
      local call = expect(ah.calls[i], "no llama a la AH")
      expect_eq(call[3], case[2], tostring(case[1]) .. " h: índice de duración de la AH")
      d:Hide()
    end
    ES.db.auctionHours = nil
  end)
end, { state = "scan" })

test("la AH pide confirmar un anuncio del addon: sale su pregunta, sin «no confirmó»", function()
  PostingAH({ needs = true }, function(ah)
    local from = #PRINTS
    local d = expect(Post(), "no sale la pregunta del addon")
    expect(not ah.popup, "la ventana de confirmación del juego sigue a la vista")
    expect(not d.check._shown, "la pregunta lleva la casilla «No volver a mostrar este aviso»")
    local text = tostring(d.text:GetText())
    expect(text:find("5", 1, true) and text:find("24", 1, true), "la pregunta no dice qué se anuncia: %s", text)
    RunTimers(10)
    expect(not SaidSince(from, Before("La Casa de Subastas no confirmó el anuncio de %s: míralo en Subastas.")),
      "con la pregunta abierta, el chat dice que la AH no confirmó el anuncio")
    expect(#ah.calls == 1, "se confirmó sin pulsar «Sí»")
  end)
end, { state = "scan" })

test("la AH no pide confirmar: no sale ninguna pregunta", function()
  PostingAH({}, function(ah)
    expect(not Post(), "sale una pregunta aunque la AH no pidió confirmar")
    FireEvent("AUCTION_HOUSE_AUCTION_CREATED")
    expect(ES.Ledger.pendingPost == nil, "el anuncio no se dio por hecho")
  end)
end, { state = "scan" })

test("«Sí» confirma el mismo anuncio y espera la respuesta de la AH", function()
  for _, commodity in ipairs({ false, true }) do
    PostingAH({ needs = true, commodity = commodity }, function(ah)
      local from = #PRINTS
      local d = expect(Post(), "no sale la pregunta del addon")
      d.ok:GetScript("OnClick")(d.ok)
      local post, confirm = ah.calls[1], expect(ah.calls[2], "«Sí» no confirmó el anuncio")
      expect_eq(confirm[1], commodity and "ConfirmPostCommodity" or "ConfirmPostItem", "lo que se llama al confirmar")
      for i = 2, 6 do expect(confirm[i] == post[i], "argumento %d distinto del anuncio: %s / %s", i - 1, tostring(confirm[i]), tostring(post[i])) end
      expect(not d._shown, "la pregunta sigue abierta tras «Sí»")
      FireEvent("AUCTION_HOUSE_AUCTION_CREATED")
      expect(SaidSince(from, Before("Anunciados %d de %s a %s cada uno (%d h).")), "confirmado, el chat no dice «Anunciados»")
      expect(ES.Ledger.pendingPost == nil, "tras crearse queda un anuncio pendiente")
    end)
  end
end, { state = "scan" })

test("«Sí» y la AH no responde: «no confirmó» a los 4 s del «Sí»", function()
  PostingAH({ needs = true }, function()
    local noConfirm = Before("La Casa de Subastas no confirmó el anuncio de %s: míralo en Subastas.")
    local from = #PRINTS
    local d = expect(Post(), "no sale la pregunta del addon")
    NOW = NOW + 3 -- (tardas 3 s en contestar; RunTimers solo avanza la hora hasta un temporizador)
    d.ok:GetScript("OnClick")(d.ok)
    NOW = NOW + 3.5 -- (6,5 s desde el anuncio, 3,5 desde el «Sí»)
    RunTimers(0)
    expect(not SaidSince(from, noConfirm), "«no confirmó» contando desde el anuncio, no desde el «Sí»")
    RunTimers(1)
    expect(SaidSince(from, noConfirm), "sin respuesta tras el «Sí», el chat no dice que la AH no confirmó")
  end)
end, { state = "scan" })

test("«Sí» y la AH rechaza el anuncio: el chat dice cuál fue el error", function()
  ERR_AUCTION_DATABASE_ERROR = ERR_AUCTION_DATABASE_ERROR or "Internal auction error" -- (texto del juego)
  PostingAH({ needs = true }, function()
    expect(ES.Ledger.IsAuctionError(ERR_AUCTION_DATABASE_ERROR), "el error de prueba no cuenta como de la AH: la prueba no prueba nada")
    local from = #PRINTS
    local d = expect(Post(), "no sale la pregunta del addon")
    d.ok:GetScript("OnClick")(d.ok)
    FireEvent("UI_ERROR_MESSAGE", 1, ERR_AUCTION_DATABASE_ERROR)
    expect(SaidSince(from, ERR_AUCTION_DATABASE_ERROR), "el chat no dice que la AH rechazó el anuncio confirmado")
    expect(ES.Ledger.pendingPost == nil, "tras el rechazo queda un anuncio pendiente")
  end)
end, { state = "scan" })

test("«Sí» y confirmar da error: lo dice y no queda nada pendiente", function()
  PostingAH({ needs = true, confirmError = true }, function()
    local from = #PRINTS
    local d = expect(Post(), "no sale la pregunta del addon")
    d.ok:GetScript("OnClick")(d.ok)
    expect(SaidSince(from, ES.L["No se pudo anunciar: "]), "el error al confirmar no sale en el chat")
    expect(ES.Ledger.pendingPost == nil, "tras el error queda un anuncio pendiente")
  end)
end, { state = "scan" })

test("«No», Escape o cerrar la AH cancelan el anuncio sin falsas alarmas", function()
  for _, how in ipairs({ "No", "Escape", "cerrar la AH" }) do
    PostingAH({ needs = true }, function(ah)
      local from = #PRINTS
      local d = expect(Post(), "%s: no sale la pregunta del addon", how)
      if how == "No" then d.cancel:GetScript("OnClick")(d.cancel)
      elseif how == "Escape" then d:Hide() -- (Escape esconde los UISpecialFrames)
      else FireEvent("AUCTION_HOUSE_CLOSED") end
      expect(not d._shown, "%s: la pregunta sigue abierta", how)
      expect(#ah.calls == 1, "%s: se confirmó el anuncio", how)
      expect(ES.Ledger.pendingPost == nil, "%s: el anuncio sigue pendiente", how)
      expect(SaidSince(from, Before("Anuncio cancelado: %s")), "%s: el chat no dice que se canceló", how)
      RunTimers(10)
      expect(not SaidSince(from, Before("La Casa de Subastas no confirmó el anuncio de %s: míralo en Subastas.")),
        "%s: el chat dice que la AH no confirmó el anuncio", how)
      -- Lo siguiente se anuncia sin «la AH está ocupada»
      local n = ES.Ledger:PostOnAH(POST_ITEM, 5, 10000, 24)
      expect(n > 0 and #ah.calls == 2, "%s: el siguiente anuncio no se hace", how)
    end)
  end
end, { state = "scan" })

test("un anuncio de la pantalla de Blizzard: su ventana de confirmar no se toca", function()
  PostingAH({}, function(ah)
    ah.popup = true -- (anuncio desde la pantalla del juego, que pide confirmar)
    FireEvent("AUCTION_HOUSE_POST_WARNING")
    RunTimers(0)
    expect(ah.popup, "el addon escondió la ventana de confirmar de un anuncio del juego")
    local d = ES.ConfirmFrame()
    expect(not (d and d._shown), "sale la pregunta del addon para un anuncio del juego")
  end)
end, { state = "scan" })

-- tools/earn_audit.py: cuántas de las subastas baratas se van al día (cota de ventas),
-- contadas tal cual: las que había menos las que seguían, por las horas observadas
test("estancado: las baratas que se van al día (gone)", function()
  local key, ITEM, t = ES:RealmKey(), 777001, time()
  ES.db.history = { [key] = {
    -- 2 h: de 10 baratas siguen 2 · 4 h: de 8 siguen 6
    { time = t - 4 * 3600, elapsed = 2 * 3600, stuck = ";" .. ITEM .. ":2:10" },
    { time = t - 60, elapsed = 4 * 3600, stuck = ";" .. ITEM .. ":6:8" },
  } }
  BuildIndexNow()
  local st = ES.Market:Stuck(ITEM)
  expect(st.known, "6 h y 52 subastas·hora: debería poder opinar")
  expect_near(st.gone, (18 - 8) / 6 * 24, 1e-6, "baratas que se van al día")
  -- Con todas idas, no se extrapola (la vida sí: -log de la supervivencia mínima)
  ES.db.history = { [key] = { { time = t - 60, elapsed = 6 * 3600, stuck = ";" .. ITEM .. ":0:5" } } }
  BuildIndexNow()
  expect_near(ES.Market:Stuck(ITEM).gone, 5 / 6 * 24, 1e-6, "todas idas: las que había")
  expect_eq(ES.Market:Stuck(999999).gone, nil, "sin datos: nil")
end, { state = "scan" })
