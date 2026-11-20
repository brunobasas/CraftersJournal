local _, ES = ...
local L = ES.L

---------------------------------------------------------------------------
-- Pestaña Inversiones (Invest.lua, PriceHistory.lua):
--   cabecera: lo invertido, lo que vale hoy (y debajo, en pequeño, el neto tras la
--             comisión de la AH) y el beneficio realizado; a la derecha, el buscador
--   fichas:   dos por fila: precio de ahora, unidades y media, y a la derecha un
--             triángulo verde o rojo con el % desde tu media. "Revisa" y "Cerradas"
--             al final. Clic: el detalle
--   detalle:  cuatro cifras, la gráfica de los días de Auctionator y los movimientos
--             (filas como las de las rutas, con su X para borrarlos)
-- Un objeto se añade escribiendo su nombre en el buscador (Mayús+clic y arrastrar desde
-- las bolsas no funcionaban en el juego: se quitaron).
---------------------------------------------------------------------------
local Invest, PH = ES.Invest, ES.PriceHistory
local GREEN, RED, GREY, ORANGE, GOLD = "|cff40ff40", "|cffff4040", "|cff9d9d9d", "|cffff9933", "|cffffd100"
local DASH = "|cff888888—|r"
local BLUE_TIP = "|cff80ccff" -- (consejos: el azul de los de la pestaña Inventario)
-- Triángulos verde (sube) y rojo (baja), en gris (precio viejo) y el punto de la gráfica:
-- tools/gen_invest_arrows.py
local MEDIA = "Interface\\AddOns\\CraftersJournal\\Media\\Invest\\"
-- Fichas: dos por fila (con tres, nombres y precios se cortaban), con aire entre líneas
local CARD_H, CARD_GAP, SECTION_H = 78, 10, 28
local CARD_TEXT_X, CARD_CHANGE_W = 68, 122 -- texto tras el icono; hueco del triángulo y el %
local MAX_RESULTS = 8
local Money = function(c) return ES.Money(c) end

---------------------------------------------------------------------------
-- Selector de segmentos: un botón por opción, juntos en una barra, y el elegido en
-- dorado. Lo usan la ventana de compra o venta (precio total o por unidad) y la ventana
-- de opciones (Options.lua, kind = "segmented").
--   choices = { { value =, text = clave del texto } }; onSelect(value) al pulsar uno.
-- Devuelve el marco: f:SetValue(v) lo marca sin llamar a onSelect; f.value, el elegido
---------------------------------------------------------------------------
function ES.UI.Segmented(parent, choices, onSelect, segW, h)
  segW, h = segW or 96, h or 22
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetSize(segW * #choices + 2, h + 2)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  f:SetBackdropColor(0.08, 0.06, 0.04, 0.9)
  f:SetBackdropBorderColor(0.52, 0.38, 0.17, 1)
  f.buttons = {}
  for i, c in ipairs(choices) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(segW, h)
    b:SetPoint("LEFT", 1 + (i - 1) * segW, 0)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    if i > 1 then
      local sep = b:CreateTexture(nil, "BORDER")
      sep:SetPoint("TOPLEFT", 0, 0)
      sep:SetPoint("BOTTOMLEFT", 0, 0)
      sep:SetWidth(1)
      sep:SetColorTexture(0.52, 0.38, 0.17, 1)
    end
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetWordWrap(false)
    b.value, b.key = c.value, c.text
    b:SetScript("OnClick", function()
      f:SetValue(c.value)
      if onSelect then onSelect(c.value) end
    end)
    f.buttons[i] = b
  end
  function f:SetValue(v)
    self.value = v
    for _, b in ipairs(self.buttons) do
      local on = b.value == v
      b.text:SetText(L[b.key]) -- (el idioma puede haber cambiado)
      b.bg:SetColorTexture(0.68, 0.52, 0.20, on and 0.55 or 0)
      if on then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(0.72, 0.68, 0.60) end
    end
  end
  return f
end

-- Cómo se escribe el precio al apuntar una compra o venta: "total" (por defecto) o
-- "unit" (opción de Inversiones, Options.lua)
function ES:InvestPriceMode()
  return self.db and self.db.investPriceMode == "unit" and "unit" or "total"
end

local function ItemLabel(itemID) return (ES.UI.ItemLabel(itemID, L["Objeto "] .. itemID)) end
local function ItemIcon(itemID)
  local _, _, texture = ES:GetItemData(itemID)
  return texture or (GetItemIcon and GetItemIcon(itemID)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- "+27%", "-11%", "+2.900%"
local function Pct(x)
  local n = math.floor(math.abs(x) * 100 + 0.5)
  if n == 0 then return "0%" end
  return (x < 0 and "-" or "+") .. ES.Num(n) .. "%"
end

-- Un cambio (0,27 = +27 %): el triángulo (ruta de su textura, o nil si no se mueve) y
-- el % en verde (sube), rojo (baja) o gris (precio viejo)
local function ChangeParts(x, stale)
  if not x then return nil, DASH end
  if math.floor(math.abs(x) * 100 + 0.5) == 0 then return nil, GREY .. "0%|r" end
  local up = x > 0
  local color = stale and GREY or (up and GREEN or RED)
  return MEDIA .. (up and "Up" or "Down") .. (stale and "-Grey" or ""), color .. Pct(x) .. "|r"
end

-- Lo mismo dentro de un texto (tooltips)
local function Change(x, stale, size)
  local tex, text = ChangeParts(x, stale)
  size = size or 14
  return (tex and string.format("|T%s:%d:%d|t ", tex, size, size) or "") .. text
end

-- Pone un cambio en un triángulo (textura) y su texto. `farmed`: lo que tienes no te
-- costó nada (precio 0), no hay % desde tu media: "Farmeado"
local function SetChange(arrow, label, x, stale, farmed)
  local tex, text = ChangeParts(x, stale)
  if farmed then tex, text = nil, GREEN .. L["Farmeado"] .. "|r" end
  arrow.path = tex -- (pruebas)
  if tex then
    arrow:SetTexture(tex)
    arrow:Show()
  else
    arrow:Hide()
  end
  label:SetText(text)
end

-- Dinero con signo (verde ganas, rojo pierdes). Las monedas, siempre las del juego
-- (ES.Money), como en el resto del addon
local function SignedMoney(c)
  if not c then return DASH end
  if c >= 0.5 then return GREEN .. "+" .. Money(c) .. "|r" end
  if c <= -0.5 then return RED .. "-" .. Money(-c) .. "|r" end
  return Money(0)
end

local function Age(days)
  if days <= 0 then return L["hoy"] end
  if days == 1 then return L["ayer"] end
  return string.format(L["hace %d días"], days)
end

local function DateText(t)
  if date then return date("%d/%m", t) end
  return ""
end

-- Por qué no hay precio (con Auctionator, solo cuenta él; sin él, tus escaneos)
local function NoPriceText()
  if PH.Available() then return L["Sin precio: búscalo en Auctionator"] end
  return L["Sin precio: instala Auctionator"] -- (sin él, el addon ya no escanea)
end

-- De dónde sale un precio: "De tu escaneo de hoy" o "Del historial de Auctionator"
local function SourceText(source, age)
  if source == "auctionator" then return L["Del historial de Auctionator"] end
  return string.format(L["De tu escaneo de %s"], Age(age or 0))
end

-- Cuántas unidades había a ese precio (o menos) en el último escaneo completo, con su
-- escalera de precios, y desde cuánto el resto: así se ve si un precio muy bajo es una
-- subasta suelta o si el mercado ha bajado de verdad. nil si el escaneo es de hace más
-- de 12 h o no tiene el objeto
local DEPTH_MAX_AGE = 12 * 3600
local function DepthLine(itemID, price)
  local scan = price and ES.db and type(ES.db.scans) == "table" and ES.db.scans[ES:RealmKey()]
  local item = type(scan) == "table" and type(scan.items) == "table" and scan.items[itemID]
  local ladder = type(item) == "table" and item.ladder
  if type(ladder) ~= "table" or #ladder < 2 or not scan.time or time() - scan.time > DEPTH_MAX_AGE then return nil end
  local at, nextPrice = 0, nil
  for i = 1, #ladder - 1, 2 do
    local p, q = tonumber(ladder[i]), tonumber(ladder[i + 1])
    if p and q then
      if p <= price + 0.5 then
        at = at + q
      elseif not nextPrice then
        nextPrice = p
      end
    end
  end
  local ago = ES.TimeAgo(scan.time)
  if at == 0 then
    -- (una subasta nueva, después del escaneo)
    return string.format(L["Último escaneo (%s): nada a este precio; lo más barato, %s"], ago, Money(ladder[1]))
  end
  return string.format(L["Último escaneo (%s): %s u a este precio o menos"], ago, ES.Num(at))
    .. (nextPrice and string.format(L[" · el resto desde %s"], Money(nextPrice)) or "")
end
ES.InvestDepthLine = DepthLine -- (pruebas)

-- El consejo de instalar Auctionator: solo sin él, hasta que lo cierras con su X
local function ShowAuctionatorTip()
  return not PH.Available() and not ES.db.investNoAuctionatorTip
end

---------------------------------------------------------------------------
-- Ventana de compra o venta: cantidad, precio (por unidad o total) y, debajo, un
-- recuadro con lo que sale: total, por unidad y tu media antes y después; en venta,
-- la comisión de la AH, lo que cobras y el realizado
---------------------------------------------------------------------------
local entry
local OpenEntry

local function EntryValues(f)
  local n = Invest.ParseQty(f.qty:GetText())
  local price = ES.Calc.ParseMoney(f.price:GetText())
  if not n or not price then return n, price end
  local isTotal = f.mode == "total"
  local total = isTotal and price or price * n
  return n, price, total / n, total, isTotal
end

-- Filas del recuadro: { { key, label, value } }
local function SetSummary(f, rows)
  f.values = {} -- [key] = texto del valor (pruebas)
  for i, line in ipairs(f.lines) do
    local r = rows[i]
    line.label:SetText(r and r[2] or "")
    line.value:SetText(r and r[3] or "")
    if r then f.values[r[1]] = r[3] end
  end
end

local function UpdatePreview(f)
  local n, price, unit, total = EntryValues(f)
  f.err:SetText("")
  if not n or not price then
    SetSummary(f, {})
    f.hint:SetText(L["Escribe la cantidad y el precio (por ejemplo 2.5 = 2s 50c, o 1g 20s). Si lo has farmeado, 0."])
    return
  end
  f.hint:SetText("")
  local cur = Invest:Item(f.itemID)
  local rows = {
    { "total", f.kind == "sell" and L["Total de la venta"] or L["Total"], Money(total) },
    { "unit", L["Por unidad"], Money(unit) },
  }
  if f.kind == "buy" then
    local units, cost = cur.broken and 0 or cur.units, cur.broken and 0 or cur.cost
    local avg = (cost + total) / (units + n)
    if cur.avg and not cur.broken then
      rows[3] = { "avgBefore", L["Tu media ahora"], Money(cur.avg) }
      rows[4] = { "avgAfter", L["Tu media después"], GOLD .. Money(avg) .. "|r" }
    else
      rows[3] = { "avgAfter", L["Tu media"], GOLD .. Money(avg) .. "|r" }
    end
  else
    local cut = total * Invest.AH_CUT
    local net = total - cut
    rows[2] = { "cut", L["Comisión de la AH (5%)"], RED .. "-" .. Money(cut) .. "|r" }
    rows[3] = { "net", L["Cobras (neto)"], Money(net) }
    if n > cur.units then
      f.err:SetText(ORANGE .. string.format(L["Solo tienes %d para vender."], cur.units) .. "|r")
    elseif cur.avg then
      rows[4] = { "realized", L["Realizado"], SignedMoney(net - n * cur.avg) }
    end
  end
  SetSummary(f, rows)
end

local function SaveEntry(f)
  local _, price, _, _, isTotal = EntryValues(f)
  local ok, why, have = Invest:Add(f.itemID, f.kind, f.qty:GetText(), price, isTotal)
  if not ok then
    local text = why == "qty" and L["Escribe la cantidad: un número entero mayor que 0."]
      or why == "units" and string.format(L["Solo tienes %d para vender."], have or 0)
      or L["Escribe el precio: por ejemplo 2.5 (2s 50c) o 1g 20s."]
    f.err:SetText(ORANGE .. text .. "|r")
    return false
  end
  f:Hide()
  ES:RenderInvest()
  ES:RenderInvestItem()
  return true
end

local function EntryFrame()
  if entry then return entry end
  local f = CreateFrame("Frame", "CraftersJournalInvestEntry", UIParent, "BackdropTemplate")
  entry = f
  f:SetSize(380, 322)
  f:SetPoint("CENTER", 0, 60)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  -- (fondo opaco, el marrón de las pestañas: la página de detrás no se transparenta)
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 26,
    insets = { left = 7, right = 7, top = 7, bottom = 7 },
  })
  f:SetBackdropColor(0.13, 0.10, 0.07, 1)
  tinsert(UISpecialFrames, "CraftersJournalInvestEntry") -- (Escape la cierra)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(38, 38)
  f.icon:SetPoint("TOPLEFT", 22, -22)
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.kindLabel = ES.UI.Label(f, "", "GameFontNormal")
  f.kindLabel:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -1)
  f.title = ES.UI.Label(f, "", "GameFontHighlightLarge")
  f.title:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 10, 1)
  f.title:SetPoint("RIGHT", -22, 0)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)
  local line = f:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", 20, -70)
  line:SetPoint("TOPRIGHT", -20, -70)
  line:SetHeight(1)
  line:SetColorTexture(1, 0.82, 0, 0.25)

  local function Box(label, y, width)
    local l = ES.UI.Label(f, label, "GameFontNormal")
    l:SetPoint("TOPLEFT", 24, y)
    local b = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    b:SetSize(width, 24)
    b:SetPoint("TOPLEFT", 124, y + 5)
    b:SetAutoFocus(false)
    b:SetScript("OnTextChanged", function() UpdatePreview(f) end)
    b:SetScript("OnEscapePressed", function() f:Hide() end)
    b:SetScript("OnEnterPressed", function() SaveEntry(f) end)
    return b
  end
  f.qty = Box(L["Cantidad"], -88, 90)
  f.qty:SetMaxLetters(7)
  f.price = Box(L["Precio"], -122, 100)
  f.price:SetScript("OnTabPressed", function() f.qty:SetFocus() end)
  f.qty:SetScript("OnTabPressed", function() f.price:SetFocus() end)

  -- El precio escrito es el total o por unidad: un selector (empieza en el de las
  -- opciones, ES:InvestPriceMode, y se cambia para esta compra)
  f.modeSelect = ES.UI.Segmented(f, { { value = "total", text = "Total" }, { value = "unit", text = "Por unidad" } },
    function(mode) f:SetMode(mode) end, 64, 22)
  f.modeSelect:SetPoint("LEFT", f.price, "RIGHT", 10, 0)
  function f:SetMode(mode)
    self.mode = mode
    self.modeSelect:SetValue(mode)
    UpdatePreview(self)
  end

  -- Recuadro con lo que sale
  local B = ES.UI.BROWN.row
  local box = ES.UI.Panel(f, B[1], B[2], B[3], 1)
  box:SetPoint("TOPLEFT", 18, -150)
  box:SetPoint("TOPRIGHT", -18, -150)
  box:SetHeight(98)
  f.lines = {}
  for i = 1, 4 do
    local l = ES.UI.Label(box, "", "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", 14, -12 - (i - 1) * 20)
    l:SetTextColor(0.78, 0.74, 0.66)
    local v = ES.UI.Label(box, "", "GameFontHighlight")
    v:SetPoint("TOPRIGHT", -14, -10 - (i - 1) * 20)
    v:SetJustifyH("RIGHT")
    f.lines[i] = { label = l, value = v }
  end
  f.hint = ES.UI.Label(box, "", "GameFontDisableSmall")
  f.hint:SetPoint("LEFT", 14, 0)
  f.hint:SetPoint("RIGHT", -14, 0)
  f.hint:SetJustifyH("CENTER")

  f.err = ES.UI.Label(f, "", "GameFontHighlightSmall")
  f.err:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 4, -8)
  f.err:SetPoint("RIGHT", -22, 0)
  f.err:SetJustifyH("LEFT")

  f.ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.ok:SetSize(130, 26)
  f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -5, 20)
  f.ok:SetScript("OnClick", function() SaveEntry(f) end)
  f.cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.cancel:SetSize(130, 26)
  f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 5, 20)
  f.cancel:SetText(L["Cancelar"])
  f.cancel:SetScript("OnClick", function() f:Hide() end)
  f:Hide()
  return f
end
ES.InvestEntry = function() return entry end -- (pruebas)

-- Abre la ventana para apuntar una compra (kind = "buy") o venta ("sell") de itemID
function OpenEntry(itemID, kind)
  if type(itemID) ~= "number" then return end
  local f = EntryFrame()
  f.itemID, f.kind = itemID, kind == "sell" and "sell" or "buy"
  f.icon:SetTexture(ItemIcon(itemID))
  f.kindLabel:SetText(f.kind == "sell" and L["Nueva venta"] or L["Nueva compra"])
  f.title:SetText(ItemLabel(itemID))
  f.ok:SetText(f.kind == "sell" and L["Vender"] or L["Añadir"])
  f.qty:SetText("")
  f.price:SetText("")
  -- Precio total (por defecto) o por unidad: el que elegiste en las opciones (Inversiones)
  local total = ES:InvestPriceMode() == "total"
  if f.kind == "sell" then
    local cur = Invest:Item(itemID)
    if cur.units > 0 then f.qty:SetText(tostring(cur.units)) end
    if cur.price then
      f.price:SetText(ES.Calc.FormatMoney(total and cur.units > 0 and cur.price * cur.units or cur.price))
    end
  end
  f:SetMode(total and "total" or "unit")
  f:Show()
  f.qty:SetFocus()
end
ES.OpenInvestEntry = OpenEntry


---------------------------------------------------------------------------
-- Buscador: objetos con nombre que el addon conoce (materiales y productos de las
-- recetas, lo escaneado y lo de la cartera). Los nombres se leen UNA vez (la primera
-- búsqueda tras abrir la pestaña) en un índice; cada letra solo filtra el índice.
-- Antes cada letra volvía a pedir el nombre de miles de objetos (todo lo escaneado) y
-- el juego pedía al servidor los que no tenía: escribir iba muy lento
---------------------------------------------------------------------------
local candidates, nameIndex
local function ResetSearchIndex() candidates, nameIndex = nil, nil end

-- ¿El juego ya tiene cargado el objeto? (sin pedirlo al servidor; sin la función, no)
local function Cached(id)
  local f = C_Item and C_Item.IsItemDataCachedByID
  if not f then return false end
  local ok, yes = pcall(f, id)
  return ok and yes == true
end

-- ¿Seguro que no puede ir a la AH? (ligado al recogerlo o de misión). Solo se sabe de
-- lo que el juego ya tiene cargado: lo demás se da por bueno
local function NotForAH(id)
  if not Cached(id) then return false end
  local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local bind = select(14, GetInfo(id))
  return bind == 1 or bind == 4
end

-- Objetos del buscador: solo lo que puede ir a la AH. Lo que ha estado a la venta (tu
-- último escaneo y lo que tiene precios en Auctionator) seguro que sí; los ligados y
-- los de misión nunca salen ahí. Sin escaneo ni Auctionator, los materiales y productos
-- de las recetas, sin lo que el juego sabe que es ligado o de misión. Y siempre lo que
-- ya tienes en la cartera
local function Candidates()
  if candidates then return candidates end
  local set = {}
  local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
  for id in pairs(scan and scan.items or {}) do set[id] = true end
  local adb = Auctionator and Auctionator.Database and Auctionator.Database.db
  if type(adb) == "table" then
    pcall(function()
      for key in pairs(adb) do
        local id = tonumber(key) -- (las claves de equipo con variantes, "g:...", no)
        if id then set[id] = true end
      end
    end)
  end
  if next(set) == nil then
    for _, data in pairs(ES.Data) do
      if type(data) == "table" and data.recipes then
        for _, r in pairs(data.recipes) do
          for _, rq in ipairs(r.r or {}) do set[rq[1]] = true end
          if r.out then set[r.out[1]] = true end
        end
      end
    end
    for id in pairs(set) do if NotForAH(id) then set[id] = nil end end
  end
  for id in pairs(Invest.Book()) do set[id] = true end
  candidates = {}
  for id in pairs(set) do if type(id) == "number" then candidates[#candidates + 1] = id end end
  return candidates
end

-- { { id, name, low } }: los nombres de los datos del addon (en su idioma y en inglés:
-- "silk" y "seda" encuentran lo mismo), sin preguntar al juego. Lo escaneado que no está
-- en los datos, solo si el juego ya lo tiene cargado: pedir miles de objetos al
-- servidor (todo lo escaneado) hacía que el buscador fuera a tirones
local function NameIndex()
  if nameIndex then return nameIndex end
  nameIndex = {}
  local english = ES.Data.ItemNames or {}
  for _, id in ipairs(Candidates()) do
    local name, en = ES:DataItemName(id), english[id]
    if not name and not en and Cached(id) then name = (ES:GetItemData(id)) end
    name = name or en
    if name then
      local low = name:lower()
      if en and en ~= name then low = low .. "\n" .. en:lower() end
      nameIndex[#nameIndex + 1] = { id = id, name = name, low = low }
    end
  end
  return nameIndex
end

local function SearchItems(query)
  query = query:lower()
  local out = {}
  for _, e in ipairs(NameIndex()) do
    local at = e.low:find(query, 1, true)
    if at then out[#out + 1] = { id = e.id, name = e.name, starts = at == 1 or e.low:sub(at - 1, at - 1) == "\n" } end
  end
  table.sort(out, function(a, b)
    if a.starts ~= b.starts then return a.starts end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  return out
end

local function CreateSearch(page, head)
  local box = CreateFrame("EditBox", nil, head, "InputBoxTemplate")
  page.search = box
  box:SetSize(230, 22)
  box:SetPoint("TOPRIGHT", -18, -14)
  box:SetAutoFocus(false)
  local hint = ES.UI.Label(box, L["Añadir: escribe un nombre"], "GameFontDisableSmall")
  hint:SetPoint("LEFT", 4, 0)

  local list = CreateFrame("Frame", nil, page, "BackdropTemplate")
  page.results = list
  list:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 4, -2)
  list:SetWidth(300)
  list:SetFrameStrata("TOOLTIP")
  list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  list:SetBackdropColor(0.045, 0.042, 0.037, 0.995)
  list:SetBackdropBorderColor(0.48, 0.40, 0.27, 1)
  list:Hide()
  list.rows = {}

  local function Pick(itemID)
    box:SetText("")
    box:ClearFocus()
    list:Hide()
    OpenEntry(itemID, "buy")
  end
  page.pickItem = Pick

  local function Row(i)
    local row = list.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 22)
    row:SetPoint("TOPRIGHT", -5, -5 - (i - 1) * 22)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 4, 0)
    row.text = ES.UI.Label(row, "", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", function(self) if self.itemID then Pick(self.itemID) end end)
    list.rows[i] = row
    return row
  end

  local function Refresh()
    local text = strtrim(box:GetText() or "")
    hint:SetShown(text == "")
    if text:len() < 2 then list:Hide() return end
    local results = SearchItems(text)
    page.searchResults = results -- (pruebas)
    local shown = math.min(MAX_RESULTS, #results)
    for i = 1, shown do
      local row = Row(i)
      row.itemID = results[i].id
      row.icon:SetTexture(ItemIcon(results[i].id))
      row.text:SetText(ItemLabel(results[i].id))
      row:Show()
    end
    for i = shown + 1, #list.rows do list.rows[i]:Hide() end
    if shown == 0 then
      local row = Row(1)
      row.itemID = nil
      row.icon:SetTexture(nil)
      row.text:SetText(GREY .. L["Sin resultados"] .. "|r")
      row:Show()
      shown = 1
    end
    list:SetHeight(10 + shown * 22)
    list:Show()
  end
  box:SetScript("OnTextChanged", Refresh)
  box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() list:Hide() end)
  box:SetScript("OnEnterPressed", function(self)
    local first = list.rows[1]
    if list:IsShown() and first and first.itemID then Pick(first.itemID) else self:ClearFocus() end
  end)
  -- (el índice de nombres se prepara al pulsar en el buscador, no con la primera letra)
  box:SetScript("OnEditFocusGained", function() NameIndex() end)
  box:SetScript("OnEditFocusLost", function()
    C_Timer.After(0.2, function() if box:HasFocus() ~= true then list:Hide() end end)
  end)end

---------------------------------------------------------------------------
-- Fichas
---------------------------------------------------------------------------
-- Clic en una ficha o fila: el detalle. Con Mayús, buscarlo en la AH (o enlazarlo en el
-- chat), como en el resto del addon
local function InvestItemClick(itemID)
  if not itemID then return end
  if IsShiftKeyDown and IsShiftKeyDown() and ES:ItemShiftClick(itemID) then return end
  ES:ShowInvestItem(itemID)
end

local function CardTooltip(e)
  return function(card)
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ItemLabel(e.itemID))
    if e.broken then
      GameTooltip:AddLine(L["Hay una venta de más unidades de las que tenías: revisa los movimientos en el detalle."], 1, 0.6, 0.2, true)
    elseif e.closed then
      GameTooltip:AddLine(string.format(L["Vendido todo (%d u)."], e.sold), 1, 1, 1)
      GameTooltip:AddDoubleLine(L["Realizado"], SignedMoney(e.realized), 1, 0.82, 0, 1, 1, 1)
    else
      GameTooltip:AddDoubleLine(string.format(L["Tienes %d u"], e.units), string.format(L["media %s"], Money(e.avg)), 1, 1, 1, 1, 1, 1)
      GameTooltip:AddDoubleLine(L["Invertido"], Money(e.cost), 0.8, 0.8, 0.8, 1, 1, 1)
      local h = e.history
      if e.value then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(string.format(L["Precio (%s)"], Age(h.now.age)), Money(e.price), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine(SourceText(h.now.source, h.now.age), 0.5, 0.8, 1)
        local depth = DepthLine(e.itemID, e.price)
        if depth then GameTooltip:AddLine(depth, 0.8, 0.8, 0.8, true) end
        GameTooltip:AddDoubleLine(L["Valor bruto"], Money(e.value), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Comisión de la AH (5%)"], "-" .. Money(e.cut), 0.8, 0.8, 0.8, 1, 0.5, 0.5)
        GameTooltip:AddDoubleLine(L["Neto"], Money(e.net), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Si vendes"], SignedMoney(e.latent) .. (e.latentPct and (" (" .. Pct(e.latentPct) .. ")") or ""), 1, 0.82, 0, 1, 1, 1)
        if h.now.stale then
          GameTooltip:AddLine(string.format(L["Precio de %s: puede haber cambiado."], Age(h.now.age)), 0.6, 0.6, 0.6, true)
        end
        if h.now.unconfirmed then
          GameTooltip:AddLine(L["Bajada de hoy sin confirmar: puede ser una subasta suelta muy barata."], 1, 0.6, 0.2, true)
        end
        local last = h.days[#h.days]
        if last and last.spike then
          GameTooltip:AddLine(string.format(L["Subida sin confirmar a %s: no cuenta hasta que se repita otro día."], Money(last.price)), 1, 0.6, 0.2, true)
        end
      else
        GameTooltip:AddLine(NoPriceText(), 1, 0.6, 0.2, true)
      end
      if e.realized ~= 0 then
        GameTooltip:AddDoubleLine(L["Realizado"], SignedMoney(e.realized), 1, 0.82, 0, 1, 1, 1)
      end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Clic: ver el detalle"], 0.5, 0.8, 1)
    GameTooltip:AddLine(L["Mayús+clic: buscarlo en la AH"], 0.5, 0.8, 1)
    GameTooltip:Show()
  end
end

-- La paleta de las filas de las rutas (ES.UI.RowStyle, ProfessionUI.lua). Las fichas
-- y la lista la usan las dos (antes las fichas eran casi negras y la lista
-- transparente: no se parecían ni al resto del addon)
local ROW_BORDER, ROW_BORDER_HOVER = ES.UI.ROW_BORDER, ES.UI.ROW_BORDER_HOVER
local SUB_COLOR = ES.UI.SUB_COLOR
local RowStyle = ES.UI.RowStyle

local function CreateCard(parent)
  local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
  RowStyle(card)
  card.icon = card:CreateTexture(nil, "ARTWORK")
  card.icon:SetSize(44, 44)
  card.icon:SetPoint("LEFT", 12, 0)
  card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  -- Tres líneas con aire: nombre, precio y "N u · media X"
  card.name = ES.UI.Label(card, "", "GameFontNormal")
  card.name:SetPoint("TOPLEFT", CARD_TEXT_X, -13)
  card.name:SetPoint("RIGHT", -CARD_CHANGE_W, 0)
  card.name:SetJustifyH("LEFT")
  card.name:SetWordWrap(false)
  card.price = ES.UI.Label(card, "", "GameFontHighlight")
  card.price:SetPoint("TOPLEFT", CARD_TEXT_X, -33)
  card.price:SetPoint("RIGHT", -CARD_CHANGE_W, 0)
  card.price:SetJustifyH("LEFT")
  card.price:SetWordWrap(false)
  card.sub = ES.UI.Label(card, "", "GameFontHighlightSmall")
  card.sub:SetTextColor(unpack(SUB_COLOR))
  card.sub:SetPoint("BOTTOMLEFT", CARD_TEXT_X, 13)
  card.sub:SetPoint("RIGHT", -CARD_CHANGE_W, 0)
  card.sub:SetJustifyH("LEFT")
  card.sub:SetWordWrap(false)
  -- A la derecha, grande: el triángulo y el % desde tu media
  card.change = ES.UI.Label(card, "", "GameFontNormalLarge")
  card.change:SetPoint("RIGHT", -16, 0)
  card.change:SetJustifyH("RIGHT")
  card.arrow = card:CreateTexture(nil, "ARTWORK")
  card.arrow:SetSize(16, 16)
  card.arrow:SetPoint("RIGHT", card.change, "LEFT", -5, 1)
  card.arrow:Hide()
  card:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(unpack(ROW_BORDER_HOVER))
    if self.tooltip then self.tooltip(self) end
  end)
  card:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(unpack(ROW_BORDER))
    GameTooltip:Hide()
  end)
  card:SetScript("OnClick", function(self) InvestItemClick(self.itemID) end)
  return card
end

-- Lo que dice una ficha
local function FillCard(card, e)
  card.itemID, card.entry, card.tooltip = e.itemID, e, CardTooltip(e)
  card.icon:SetTexture(ItemIcon(e.itemID))
  card.icon:SetDesaturated(e.closed and true or false)
  card.name:SetText(ItemLabel(e.itemID))
  if e.broken then
    card.price:SetText(ORANGE .. L["Revisa los movimientos"] .. "|r")
    card.sub:SetText(string.format(L["%d movimientos"], #e.moves))
    SetChange(card.arrow, card.change, nil)
    card.change:SetText("")
  elseif e.closed then
    card.price:SetText(L["Realizado"] .. " " .. SignedMoney(e.realized))
    card.sub:SetText(string.format(L["Vendido todo · %d u"], e.sold))
    SetChange(card.arrow, card.change, nil)
    card.change:SetText("")
  else
    if e.price then
      card.price:SetText((e.stale and GREY or "") .. Money(e.price) .. (e.stale and "|r" or ""))
      SetChange(card.arrow, card.change, e.changePct, e.stale, e.farmed)
    else
      card.price:SetText(GREY .. NoPriceText() .. "|r")
      SetChange(card.arrow, card.change, nil)
      card.change:SetText("")
    end
    card.sub:SetText(string.format(L["%d u · media %s"], e.units, Money(e.avg)))
  end
end

---------------------------------------------------------------------------
-- Vista de lista: una fila fina por objeto, con columnas (los nombres arriba). Mismo
-- tooltip y mismo clic que las fichas
---------------------------------------------------------------------------
local LIST_ROW_H, LIST_ROW_GAP, LIST_HEAD_H = 30, 3, 22 -- (cada fila en su recuadro, como las de las rutas)
-- Columnas, desde el borde derecho de la fila: { campo, borde derecho, ancho }
local COLUMNS = {
  { "units",  -486, 60 },
  { "avg",    -372, 104 },
  { "price",  -258, 104 },
  { "change", -126, 120 },
  { "latent", -10,  104 },
}
local NAME_X, NAME_RIGHT = 36, -556

-- Orden de la lista: pulsando el nombre de una columna (ES.db.investSort = { key, asc };
-- se recuerda). Primer clic: el nombre de la A a la Z y los números de mayor a menor;
-- otro clic en la misma, al revés. Lo que no tiene valor (sin precio) va siempre al final
local SORT_VALUE = {
  name = function(e) return (ES:ItemName(e.itemID) or ""):lower() end,
  units = function(e) return e.units end,
  avg = function(e) return e.avg end,
  price = function(e) return e.price end,
  change = function(e) return e.changePct end,
  latent = function(e) return e.latent or (e.closed and e.realized) or nil end, -- (las cerradas: su realizado)
}
local function Sorting()
  local s = ES.db.investSort
  if type(s) == "table" and SORT_VALUE[s.key] then return s.key, s.asc == true end
  return "latent", false
end
local function SortEntries(list, key, asc)
  local f = SORT_VALUE[key]
  local v = {}
  for _, e in ipairs(list) do v[e] = f(e) end
  table.sort(list, function(a, b)
    local va, vb = v[a], v[b]
    if (va == nil) ~= (vb == nil) then return va ~= nil end
    if va ~= nil and va ~= vb then
      if asc then return va < vb end
      return va > vb
    end
    return a.itemID < b.itemID
  end)
end

local function ListHeader(parent)
  local h = CreateFrame("Frame", nil, parent)
  h:SetHeight(LIST_HEAD_H)
  h.columns = {}
  local function Column(key, title, right, width, left)
    local b = CreateFrame("Button", nil, h)
    b:SetHeight(LIST_HEAD_H)
    b:SetWidth(width)
    b.text = ES.UI.Label(b, title, "GameFontDisableSmall")
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.arrow:SetSize(9, 9)
    b.arrow:Hide()
    if left then
      b:SetPoint("LEFT", h, "LEFT", left, 0)
      b.text:SetPoint("LEFT", 0, 0)
      b.arrow:SetPoint("LEFT", b.text, "RIGHT", 4, 0)
    else
      b:SetPoint("RIGHT", h, "RIGHT", right, 0)
      b.text:SetPoint("RIGHT", 0, 0)
      b.arrow:SetPoint("RIGHT", b.text, "LEFT", -4, 0)
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0.25, 0.08)
    b:SetScript("OnClick", function()
      local cur, asc = Sorting()
      if cur == key then
        asc = not asc
      else
        asc = key == "name"
      end
      ES.db.investSort = { key = key, asc = asc }
      ES:RenderInvest()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(title)
      GameTooltip:AddLine(L["Clic: ordenar por esta columna (otro clic: al revés)."], 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h.columns[key] = b
  end
  Column("name", L["Objeto"], nil, 200, NAME_X)
  local titles = { units = L["Tienes"], avg = L["Tu media"], price = L["Precio"], change = L["Desde tu media"], latent = L["Si vendes"] }
  for _, c in ipairs(COLUMNS) do Column(c[1], titles[c[1]], c[2], c[3]) end
  -- La columna del orden, en dorado y con un triángulo que dice el sentido
  function h:Mark(key, asc)
    for k, b in pairs(self.columns) do
      local on = k == key
      b.text:SetTextColor(on and 1 or 0.6, on and 0.82 or 0.6, on and 0.25 or 0.6)
      b.arrow:SetShown(on)
      if on then
        b.arrow:SetTexture(MEDIA .. (asc and "Up-Grey" or "Down-Grey"))
        b.arrow:SetVertexColor(1, 0.82, 0.25)
      end
    end
  end
  local line = h:CreateTexture(nil, "ARTWORK")
  line:SetPoint("BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", 0, 0)
  line:SetHeight(1)
  line:SetColorTexture(1, 0.82, 0, 0.25)
  return h
end

local function CreateListRow(parent)
  local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
  row:SetHeight(LIST_ROW_H)
  RowStyle(row)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(22, 22)
  row.icon:SetPoint("LEFT", 8, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.name = ES.UI.Label(row, "", "GameFontHighlight")
  row.name:SetPoint("LEFT", NAME_X, 0)
  row.name:SetPoint("RIGHT", row, "RIGHT", NAME_RIGHT, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  for _, c in ipairs(COLUMNS) do
    local fs = ES.UI.Label(row, "", c[1] == "change" and "GameFontNormal" or "GameFontHighlightSmall")
    fs:SetPoint("RIGHT", row, "RIGHT", c[2], 0)
    fs:SetJustifyH("RIGHT")
    fs:SetWordWrap(false)
    row[c[1]] = fs
  end
  row.arrow = row:CreateTexture(nil, "ARTWORK")
  row.arrow:SetSize(13, 13)
  row.arrow:SetPoint("RIGHT", row.change, "LEFT", -4, 1)
  row.arrow:Hide()
  row:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(unpack(ROW_BORDER_HOVER))
    if self.tooltip then self.tooltip(self) end
  end)
  row:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(unpack(ROW_BORDER))
    GameTooltip:Hide()
  end)
  row:SetScript("OnClick", function(self) InvestItemClick(self.itemID) end)
  return row
end

-- Lo que dice una fila
local function FillListRow(row, e)
  row.itemID, row.entry, row.tooltip = e.itemID, e, CardTooltip(e)
  row.icon:SetTexture(ItemIcon(e.itemID))
  row.icon:SetDesaturated(e.closed and true or false)
  row.name:SetText(ItemLabel(e.itemID))
  row.arrow:Hide()
  if e.broken then
    row.units:SetText("")
    row.avg:SetText("")
    row.price:SetText(ORANGE .. L["Revisa los movimientos"] .. "|r")
    row.change:SetText("")
    row.latent:SetText("")
  elseif e.closed then
    row.units:SetText("0")
    row.avg:SetText("")
    row.price:SetText(GREY .. L["Realizado"] .. "|r")
    row.change:SetText("")
    row.latent:SetText(SignedMoney(e.realized))
  else
    row.units:SetText(ES.Num(e.units))
    row.avg:SetText(Money(e.avg))
    if e.price then
      row.price:SetText((e.stale and GREY or "") .. Money(e.price) .. (e.stale and "|r" or ""))
      SetChange(row.arrow, row.change, e.changePct, e.stale, e.farmed)
      row.latent:SetText(SignedMoney(e.latent))
    else
      row.price:SetText(DASH)
      row.change:SetText(DASH)
      row.latent:SetText(DASH)
    end
  end
end

local function SectionLabel(page, i)
  page.sections = page.sections or {}
  local s = page.sections[i]
  if s then return s end
  s = CreateFrame("Button", nil, page.content)
  s:SetHeight(SECTION_H)
  s.arrow = s:CreateTexture(nil, "ARTWORK")
  s.arrow:SetSize(14, 14)
  s.arrow:SetPoint("LEFT", 4, 0)
  s.text = ES.UI.Label(s, "", "GameFontNormal")
  s.text:SetPoint("LEFT", s.arrow, "RIGHT", 6, 0)
  page.sections[i] = s
  return s
end

function ES:CreateInvestPage(page)
  local Label = ES.UI.Label
  local head = ES.UI.CardHead(page, 66)
  page.head = head
  page.icon = head:CreateTexture(nil, "ARTWORK")
  page.icon:SetSize(44, 44)
  page.icon:SetPoint("LEFT", 12, 0)
  page.icon:SetTexture(Invest.ICON)
  page.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local name = Label(head, L["Inversiones"], "GameFontNormalHuge")
  name:SetPoint("TOPLEFT", page.icon, "TOPRIGHT", 12, 2)
  name:SetTextColor(0.96, 0.79, 0.25)
  page.subtitle = Label(head, L["Tu precio medio y lo que ganas con cada objeto."], "GameFontHighlightSmall")
  page.subtitle:SetPoint("BOTTOMLEFT", page.icon, "BOTTOMRIGHT", 12, 2)
  page.subtitle:SetPoint("RIGHT", -260, 0)
  page.subtitle:SetJustifyH("LEFT")
  page.subtitle:SetWordWrap(false)
  CreateSearch(page, head)

  -- Tres cifras con aire: invertido, vale hoy (con el neto tras la AH debajo, en
  -- pequeño) y realizado. El latente va en cada ficha y en el detalle
  local strip = CreateFrame("Frame", nil, page)
  strip:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 4, -8)
  strip:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -4, -8)
  strip:SetHeight(58)
  page.stats = {}
  for i, s in ipairs({ { key = "cost", label = L["Invertido"] }, { key = "value", label = L["Vale hoy"] },
    { key = "realized", label = L["Realizado"] } }) do
    local label = Label(strip, s.label, "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", (i - 1) * 250 + 8, -2)
    local value = Label(strip, "", "GameFontHighlightLarge")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    page.stats[s.key] = value
  end
  page.stats.net = Label(strip, "", "GameFontDisableSmall")
  page.stats.net:SetPoint("TOPLEFT", page.stats.value, "BOTTOMLEFT", 0, -4)
  -- Vista de fichas o de lista (ES.db.investView = "list"; se recuerda), a la derecha
  page.views = {}
  for i, v in ipairs({
    { key = "list", icon = "ViewList", title = L["Lista"], text = L["Una fila por objeto: muchas de un vistazo, con menos scroll."] },
    { key = "grid", icon = "ViewGrid", title = L["Fichas"], text = L["Dos por fila, con más detalle."] },
  }) do
    local b = CreateFrame("Button", nil, page)
    b:SetSize(20, 20)
    if i == 1 then
      b:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", -2, 2)
    else
      b:SetPoint("RIGHT", page.views[1], "LEFT", -6, 0)
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(MEDIA .. v.icon)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", -3, 3)
    hl:SetPoint("BOTTOMRIGHT", 3, -3)
    hl:SetColorTexture(1, 0.82, 0.25, 0.15)
    b.view = v.key
    b:SetScript("OnClick", function()
      ES.db.investView = v.key == "list" and "list" or nil
      ES:RenderInvest()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(v.title)
      GameTooltip:AddLine(v.text, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.views[v.key] = b
    page.views[i] = b
  end

  -- X del consejo de Auctionator (solo se ve con el consejo): no volver a enseñarlo
  page.tipClose = CreateFrame("Button", nil, page)
  page.tipClose:SetSize(14, 14)
  page.tipClose:SetPoint("RIGHT", page.views.grid, "LEFT", -12, 0)
  page.tipClose:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
  page.tipClose:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
  page.tipClose:SetScript("OnClick", function()
    ES.db.investNoAuctionatorTip = true
    GameTooltip:Hide()
    ES:RenderInvest()
  end)
  page.tipClose:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["No volver a mostrar este consejo"])
    GameTooltip:Show()
  end)
  page.tipClose:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.tipClose:Hide()

  page.status = Label(page, "", "GameFontHighlightSmall")
  page.status:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 4, -2)
  page.status:SetPoint("RIGHT", page.tipClose, "LEFT", -6, 0)
  page.status:SetJustifyH("LEFT")
  page.status:SetWordWrap(false)

  local list = ES.UI.ListPanel(page, head, 92)
  page.list = list
  local scroll = ES.UI.WheelScroll(list)
  scroll:SetPoint("TOPLEFT", 10, -10)
  scroll:SetPoint("BOTTOMRIGHT", -10, 10)
  page.scroll = scroll
  page.content = CreateFrame("Frame", nil, scroll)
  page.content:SetSize(ES.UI.LIST_WIDTH, 1)
  scroll:SetScrollChild(page.content)
  page.indicator = ES.UI.ScrollIndicator(scroll, page.content)
  page.cards, page.rows = {}, {}
  page.empty = Label(page.content, "", "GameFontDisable")
  page.empty:SetPoint("TOP", 0, -40)
  page.empty:SetWidth(560)

  page:SetScript("OnShow", function()
    PH.Clear()
    ResetSearchIndex()
    PH.Watch(function() ES:RenderInvest() ES:RenderInvestItem() end)
    ES:RenderInvest()
  end)
  -- Llegan nombres e iconos de objetos que faltaban
  ES.SafeRegister(page, "GET_ITEM_INFO_RECEIVED")
  page:SetScript("OnEvent", function(self)
    if self:IsVisible() and not self.refreshQueued then
      self.refreshQueued = true
      C_Timer.After(0.5, function() self.refreshQueued = false ES:RenderInvest() end)
    end
  end)
  self.investPage = page
end

function ES:RenderInvest()
  local page = self.investPage
  if not page or not page:IsVisible() then return end
  local sum = Invest:Summary()
  local t = sum.totals
  page.summary = sum -- (pruebas)
  page.stats.cost:SetText(Money(t.cost))
  page.stats.value:SetText(t.priced > 0 and Money(t.value) or DASH)
  page.stats.net:SetText(t.priced > 0 and (L["Neto tras la AH (5%)"] .. ": " .. Money(t.net)) or "")
  page.stats.realized:SetText(SignedMoney(t.realized))

  -- Sin Auctionator, el consejo (en azul, con su X): los precios son los de tus últimos
  -- escaneos y sin él no se escanea (Scanner.lua). Con él, de dónde salen los precios.
  -- Y cuántos no tienen precio
  local tip = ShowAuctionatorTip()
  page.tipClose:SetShown(tip)
  local missing = t.missing > 0 and string.format(L["%d sin precio: no cuentan en Vale hoy."], t.missing) or nil
  if tip then
    page.status:SetText(BLUE_TIP .. L["Precios de tus últimos escaneos. Instala Auctionator para volver a escanear y tener el historial de precios."] .. "|r")
  elseif PH.Available() then
    page.status:SetText(GREY .. L["Precios del historial de Auctionator: se ponen al día cada vez que escaneas."]
      .. (missing and ("  ·  " .. missing) or "") .. "|r")
  else
    page.status:SetText(missing and (GREY .. missing .. "|r") or "")
  end

  -- Ancho: el de la zona de la lista menos la guía de scroll (antes las fichas de la
  -- derecha quedaban debajo de la guía)
  local width = math.max(200, math.min(ES.UI.LIST_WIDTH, ES.UI.ListWidth(page) - 10))
  page.content:SetWidth(width)
  local cardW = math.floor((width - CARD_GAP) / 2)
  local asList = ES.db.investView == "list"
  page.views.list.icon:SetVertexColor(asList and 1 or 0.55, asList and 0.82 or 0.55, asList and 0.25 or 0.55)
  page.views.grid.icon:SetVertexColor(asList and 0.55 or 1, asList and 0.55 or 0.82, asList and 0.55 or 0.25)
  local y, n, s, nr = 0, 0, 0, 0
  local function PlaceRows(list)
    for _, e in ipairs(list) do
      nr = nr + 1
      local row = page.rows[nr] or CreateListRow(page.content)
      page.rows[nr] = row
      FillListRow(row, e)
      row:SetWidth(width)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, -y)
      row:Show()
      y = y + LIST_ROW_H + LIST_ROW_GAP
    end
    if #list > 0 then y = y + 4 end
  end
  local function Place(list)
    if asList then return PlaceRows(list) end
    for i, e in ipairs(list) do
      n = n + 1
      local card = page.cards[n] or CreateCard(page.content)
      page.cards[n] = card
      FillCard(card, e)
      card:SetSize(cardW, CARD_H)
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", ((i - 1) % 2) * (cardW + CARD_GAP), -(y + math.floor((i - 1) / 2) * (CARD_H + CARD_GAP)))
      card:Show()
    end
    if #list > 0 then y = y + math.ceil(#list / 2) * (CARD_H + CARD_GAP) end
  end
  local function Section(text, collapsible, collapsed, onClick)
    s = s + 1
    local h = SectionLabel(page, s)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", 0, -y)
    h:SetWidth(width)
    h.text:SetText(text)
    if collapsible then
      h.arrow:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
      h.arrow:Show()
    else
      h.arrow:Hide()
    end
    h:SetScript("OnClick", onClick)
    h:Show()
    y = y + SECTION_H + 4
  end

  -- Lista: los nombres de las columnas arriba
  local header = page.listHeader or ListHeader(page.content)
  page.listHeader = header
  if asList and (#sum.open + #sum.broken + #sum.closed) > 0 then
    local key, asc = Sorting()
    SortEntries(sum.open, key, asc)
    SortEntries(sum.closed, key, asc)
    header:Mark(key, asc)
    header:SetWidth(width)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", 0, 0)
    header:Show()
    y = y + LIST_HEAD_H
  else
    header:Hide()
  end

  Place(sum.open)
  if #sum.broken > 0 then
    Section(ORANGE .. string.format(L["Revisa los movimientos (%d)"], #sum.broken) .. "|r")
    Place(sum.broken)
  end
  if #sum.closed > 0 then
    local collapsed = ES.db.investClosedOpen ~= true
    Section(string.format(L["Cerradas (%d)"], #sum.closed), true, collapsed, function()
      ES.db.investClosedOpen = (ES.db.investClosedOpen ~= true) or nil
      ES:RenderInvest()
    end)
    if not collapsed then Place(sum.closed) end
  end
  for i = n + 1, #page.cards do page.cards[i]:Hide() end
  for i = nr + 1, #page.rows do page.rows[i]:Hide() end
  for i = s + 1, #(page.sections or {}) do page.sections[i]:Hide() end
  page.shownCards, page.shownRows = n, nr
  page.empty:SetText(n + nr == 0 and #sum.closed == 0
    and L["Tu cartera está vacía. Añade una compra: escribe el nombre del objeto en el buscador de arriba a la derecha."]
    or "")
  page.content:SetHeight(math.max(1, y))
  if page.indicator then page.indicator:Update() end
end

---------------------------------------------------------------------------
-- Gráfica de líneas (reutilizable): chart:SetDays(days)
--   days = { { day, price, avail, dubious }, ... } (del más antiguo al más reciente)
-- Una curva suave (Hermite monótona: no se pasa de los precios de verdad) con el área
-- de debajo en degradado que se apaga hacia abajo, el último día resaltado con su precio
-- en dorado, el precio más alto arriba a la izquierda y las fechas abajo.
-- El eje X es la fecha real; dos días válidos con más de PH.GAP_DAYS de separación
-- no se unen; los dudosos son puntos grises sueltos. chart.segments = { { from, to } }
-- (los días unidos). Cada día tiene su zona para el tooltip
---------------------------------------------------------------------------
local PLOT_L, PLOT_R, PLOT_T, PLOT_B = 20, 92, 26, 24
local FILL_STEP = 3   -- ancho de cada franja del relleno (px)
local CURVE_STEPS = 6 -- tramos rectos por cada día de la curva
local LINE_GOLD = { 1, 0.78, 0.20 }

-- Degradado vertical (arriba aTop, abajo aBottom) del dorado de la línea
local function Fade(tex, aTop, aBottom)
  local r, g, b = LINE_GOLD[1], LINE_GOLD[2], LINE_GOLD[3]
  tex:SetColorTexture(1, 1, 1, 1)
  if CreateColor and tex.SetGradient then
    if pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(r, g, b, aBottom), CreateColor(r, g, b, aTop)) then return end
  end
  if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, "VERTICAL", r, g, b, aBottom, r, g, b, aTop) then return end
  tex:SetColorTexture(r, g, b, (aTop + aBottom) / 2)
end

-- Curva por unos puntos { x, y } (en píxeles, x creciente): Hermite monótona
-- (Fritsch-Carlson). Devuelve los puntos de la curva, con CURVE_STEPS por tramo
local function SmoothCurve(pts)
  local n = #pts
  if n < 3 then return pts end
  local d, m = {}, {}
  for i = 1, n - 1 do d[i] = (pts[i + 1].y - pts[i].y) / math.max(1e-6, pts[i + 1].x - pts[i].x) end
  m[1], m[n] = d[1], d[n - 1]
  for i = 2, n - 1 do m[i] = (d[i - 1] * d[i] <= 0) and 0 or (d[i - 1] + d[i]) / 2 end
  for i = 1, n - 1 do
    if d[i] == 0 then
      m[i], m[i + 1] = 0, 0
    else
      local a, b = m[i] / d[i], m[i + 1] / d[i]
      local s = a * a + b * b
      if s > 9 then
        local t = 3 / math.sqrt(s)
        m[i], m[i + 1] = t * a * d[i], t * b * d[i]
      end
    end
  end
  local out = { pts[1] }
  for i = 1, n - 1 do
    local p, q = pts[i], pts[i + 1]
    local h = q.x - p.x
    for k = 1, CURVE_STEPS do
      local t = k / CURVE_STEPS
      local t2, t3 = t * t, t * t * t
      local y = (2 * t3 - 3 * t2 + 1) * p.y + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * q.y + (t3 - t2) * h * m[i + 1]
      out[#out + 1] = { x = p.x + h * t, y = y }
    end
  end
  return out
end

function ES.UI.LineChart(parent)
  local chart = CreateFrame("Frame", nil, parent)
  chart.plot = CreateFrame("Frame", nil, chart)
  chart.plot:SetPoint("TOPLEFT", PLOT_L, -PLOT_T)
  chart.plot:SetPoint("BOTTOMRIGHT", -PLOT_R, PLOT_B)
  chart.base = chart.plot:CreateTexture(nil, "BACKGROUND")
  chart.base:SetPoint("BOTTOMLEFT", 0, 0)
  chart.base:SetPoint("BOTTOMRIGHT", 0, 0)
  chart.base:SetHeight(1)
  chart.base:SetColorTexture(1, 0.82, 0.25, 0.18)
  chart.fills, chart.glows, chart.lines, chart.dots, chart.hits, chart.labels = {}, {}, {}, {}, {}, {}
  chart.message = ES.UI.Label(chart, "", "GameFontDisable")
  chart.message:SetPoint("CENTER", 0, 0)
  chart.message:SetWidth(460)

  local function Get(pool, i, make)
    local o = pool[i]
    if not o then o = make() pool[i] = o end
    return o
  end
  local function Label(i, template)
    local fs = Get(chart.labels, i, function() return ES.UI.Label(chart, "", "GameFontDisableSmall") end)
    fs:SetFontObject(template or "GameFontDisableSmall")
    fs:ClearAllPoints()
    fs:Show()
    return fs
  end
  local function Tex(pool, i, layer, sub)
    return Get(pool, i, function() return chart.plot:CreateTexture(nil, layer, nil, sub) end)
  end

  function chart:SetMessage(text) self.message:SetText(text or "") end

  function chart:SetDays(days)
    self.segments = {}
    local nf, nl, nd, nlab = 0, 0, 0, 0
    days = days or {}
    local valid = {}
    for _, d in ipairs(days) do if not d.dubious then valid[#valid + 1] = d end end
    local w = tonumber(self.plot:GetWidth()) or 0
    local h = tonumber(self.plot:GetHeight()) or 0
    if #valid > 0 and (w < 20 or h < 20) then
      -- (aún sin tamaño: al siguiente fotograma)
      C_Timer.After(0, function() if self:IsVisible() then self:SetDays(days) end end)
    elseif #valid > 0 then
      local x0, x1 = days[1].day, days[#days].day
      if x1 == x0 then x0, x1 = x0 - 1, x1 + 1 end
      local lo, hi = math.huge, 0
      for _, d in ipairs(valid) do lo, hi = math.min(lo, d.price), math.max(hi, d.price) end
      local pad = math.max((hi - lo) * 0.10, hi * 0.04, 1)
      local y0, y1 = math.max(0, lo - pad * 2), hi + pad
      local function X(day) return (day - x0) / (x1 - x0) * w end
      local function Y(p) return math.max(0, math.min(h, (p - y0) / (y1 - y0) * h)) end
      local canLine = self.plot.CreateLine ~= nil
      local function Line(pool, i, thickness, a)
        local l = Get(pool, i, function() return self.plot:CreateLine(nil, "ARTWORK") end)
        l:SetThickness(thickness)
        l:SetColorTexture(LINE_GOLD[1], LINE_GOLD[2], LINE_GOLD[3], a)
        l:Show()
        return l
      end

      -- Tramos de días unidos (sin huecos de más de PH.GAP_DAYS): cada uno, su curva
      local runs, run = {}, nil
      for _, d in ipairs(valid) do
        if run and d.day - run[#run].day <= PH.GAP_DAYS then
          self.segments[#self.segments + 1] = { from = run[#run].day, to = d.day }
          run[#run + 1] = d
        else
          run = { d }
          runs[#runs + 1] = run
        end
      end
      for _, r in ipairs(runs) do
        if #r >= 2 then
          local pts = {}
          for _, d in ipairs(r) do pts[#pts + 1] = { x = X(d.day), y = Y(d.price) } end
          local curve = SmoothCurve(pts)
          for i = 1, #curve do curve[i].y = math.max(0, math.min(h, curve[i].y)) end
          -- Relleno: franjas finas desde abajo hasta la curva, en degradado
          local j = 1
          local x = curve[1].x
          while x < curve[#curve].x do
            local step = math.min(FILL_STEP, curve[#curve].x - x)
            local mid = x + step / 2
            while j < #curve - 1 and curve[j + 1].x < mid do j = j + 1 end
            local a, b = curve[j], curve[j + 1]
            local fy = a.y + (b.y - a.y) * (mid - a.x) / math.max(1e-6, b.x - a.x)
            nf = nf + 1
            local f = Tex(self.fills, nf, "BORDER")
            f:ClearAllPoints()
            f:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", x, 0)
            f:SetSize(step, math.max(1, fy))
            Fade(f, 0.32, 0.02)
            f:Show()
            x = x + step
          end
          -- La línea, con un halo suave debajo
          if canLine then
            for i = 1, #curve - 1 do
              nl = nl + 1
              local glow = Line(self.glows, nl, 6, 0.16)
              glow:SetStartPoint("BOTTOMLEFT", self.plot, curve[i].x, curve[i].y)
              glow:SetEndPoint("BOTTOMLEFT", self.plot, curve[i + 1].x, curve[i + 1].y)
              local line = Line(self.lines, nl, 2.5, 1)
              line:SetStartPoint("BOTTOMLEFT", self.plot, curve[i].x, curve[i].y)
              line:SetEndPoint("BOTTOMLEFT", self.plot, curve[i + 1].x, curve[i + 1].y)
            end
          end
        end
      end

      -- Puntos: solo los días sueltos (sin otro al lado) y los dudosos (grises); el
      -- último, grande con su anillo. Todos los días tienen su zona para el tooltip
      local last = valid[#valid]
      local function Dot(x, y, size, r, g, b, a, sub)
        nd = nd + 1
        local dot = Tex(self.dots, nd, "OVERLAY", sub or 2)
        dot:SetTexture(MEDIA .. "Dot")
        dot:SetSize(size, size)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", self.plot, "BOTTOMLEFT", x, y)
        dot:SetVertexColor(r, g, b, a)
        dot:Show()
      end
      local alone = {}
      for _, r in ipairs(runs) do if #r == 1 then alone[r[1]] = true end end
      for i, d in ipairs(days) do
        local x, y = X(d.day), Y(d.price)
        if d.dubious then
          Dot(x, y, 6, 0.6, 0.6, 0.6, 0.9)
        elseif alone[d] and d ~= last then
          Dot(x, y, 7, LINE_GOLD[1], LINE_GOLD[2], LINE_GOLD[3], 1)
        elseif d.source == "scans" and d ~= last then
          -- (los días de tus escaneos, con un punto pequeño sobre la curva; los de
          -- Auctionator, solo la línea)
          Dot(x, y, 5, 1, 0.92, 0.6, 1)
        end
        local hit = Get(self.hits, i, function()
          local b = CreateFrame("Frame", nil, self.plot)
          b:SetSize(16, 16)
          b:EnableMouse(true)
          b:SetScript("OnEnter", function(s)
            local p = s.point
            if not p then return end
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:AddLine(DateText(p.time or PH.DayTime(p.day)))
            GameTooltip:AddLine(Money(p.price), 1, 1, 1)
            if p.avail then GameTooltip:AddLine(string.format(L["%s a la venta"], ES.Num(p.avail)), 0.8, 0.8, 0.8) end
            if p.source then
              GameTooltip:AddLine(p.source == "auctionator" and L["Del historial de Auctionator"] or L["De tu escaneo"], 0.5, 0.8, 1)
            end
            if p.spike then
              GameTooltip:AddLine(L["Subida sin confirmar: más del triple que el día anterior. No cuenta hasta que se repita otro día."], 0.6, 0.6, 0.6, true)
            elseif p.dubious and p.high then
              GameTooltip:AddLine(L["Día dudoso: mucho más caro que el día de antes y el de después. No cuenta."], 0.6, 0.6, 0.6, true)
            elseif p.dubious then
              GameTooltip:AddLine(L["Día dudoso: mucho más barato que el día de antes y el de después (una subasta suelta). No cuenta."], 0.6, 0.6, 0.6, true)
            end
            GameTooltip:Show()
          end)
          b:SetScript("OnLeave", function() GameTooltip:Hide() end)
          return b
        end)
        hit.point = d
        hit:ClearAllPoints()
        hit:SetPoint("CENTER", self.plot, "BOTTOMLEFT", x, y)
        hit:Show()
      end
      for i = #days + 1, #self.hits do self.hits[i]:Hide() end
      local lx, ly = X(last.day), Y(last.price)
      Dot(lx, ly, 22, LINE_GOLD[1], LINE_GOLD[2], LINE_GOLD[3], 0.22, 1) -- halo
      Dot(lx, ly, 12, LINE_GOLD[1], LINE_GOLD[2], LINE_GOLD[3], 1, 2)    -- anillo
      Dot(lx, ly, 6, 0.10, 0.07, 0.04, 1, 3)                              -- centro oscuro

      -- El precio más alto, arriba a la izquierda; el último, a su derecha en dorado
      nlab = nlab + 1
      local top = Label(nlab)
      top:SetPoint("BOTTOMLEFT", self.plot, "TOPLEFT", 0, 4)
      top:SetText(Money(hi))
      nlab = nlab + 1
      local lastLabel = Label(nlab, "GameFontNormal")
      lastLabel:SetPoint("LEFT", self.plot, "BOTTOMLEFT", lx + 14, ly)
      lastLabel:SetText(GOLD .. Money(last.price) .. "|r")
      -- Fechas abajo: la primera, la última y dos entre medias
      local marks = { days[1].day }
      local span = days[#days].day - days[1].day
      if span >= 6 then
        marks[#marks + 1] = days[1].day + math.floor(span / 3 + 0.5)
        marks[#marks + 1] = days[1].day + math.floor(span * 2 / 3 + 0.5)
      end
      if span > 0 then marks[#marks + 1] = days[#days].day end
      for i, day in ipairs(marks) do
        nlab = nlab + 1
        local fs = Label(nlab)
        local anchor = i == 1 and "TOPLEFT" or (i == #marks and span > 0) and "TOPRIGHT" or "TOP"
        fs:SetPoint(anchor, self.plot, "BOTTOMLEFT", X(day), -6)
        -- (la hora de cada día la da su fuente: Auctionator o tus escaneos)
        fs:SetText(DateText(days[1].time and (days[1].time + (day - days[1].day) * 86400) or PH.DayTime(day)))
      end
    else
      for i = 1, #self.hits do self.hits[i]:Hide() end
    end
    self.base:SetShown(#valid > 0)
    for i = nf + 1, #self.fills do self.fills[i]:Hide() end
    for i = nl + 1, #self.lines do self.lines[i]:Hide() self.glows[i]:Hide() end
    for i = nd + 1, #self.dots do self.dots[i]:Hide() end
    for i = nlab + 1, #self.labels do self.labels[i]:Hide() end
  end
  return chart
end

---------------------------------------------------------------------------
-- Detalle de un objeto
--   cabecera centrada: icono y nombre grandes; debajo, nivel, tipo y precio de vendedor
--   franja de cuatro cifras (precio ahora, tu media, desde tu media, últimos 4 días)
--   la gráfica, y los movimientos con + Compra / + Venta y el resumen de lo que tienes
---------------------------------------------------------------------------
local BLUE = "|cff71d5ff"

function ES:ShowInvestItem(itemID)
  self.investItemID = itemID
  local page = self.investItemPage
  if page and page:IsVisible() then
    self:RenderInvestItem()
  else
    self:SelectPage("investItem")
  end
end

-- Tooltip de un movimiento
local function MoveTooltip(m)
  return function(row)
    local amount = m.total or m.n * m.unit
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(m.kind == "sell" and L["Vendido"] or L["Comprado"])
    GameTooltip:AddDoubleLine(L["Cantidad"], tostring(m.n), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Por unidad"], Money(amount / m.n), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine(m.kind == "sell" and L["Total de la venta"] or L["Total"], Money(amount), 0.8, 0.8, 0.8, 1, 1, 1)
    if m.kind == "sell" then
      GameTooltip:AddDoubleLine(L["Comisión de la AH (5%)"], "-" .. Money(amount * Invest.AH_CUT), 0.8, 0.8, 0.8, 1, 0.5, 0.5)
      GameTooltip:AddDoubleLine(L["Cobras (neto)"], Money(amount * (1 - Invest.AH_CUT)), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:Show()
  end
end

function ES:CreateInvestItemPage(page)
  local Label = ES.UI.Label
  local DARK = { 0.085, 0.065, 0.045, 0.97 } -- (franja y gráfica: más oscuras que la página)

  -- Cabecera centrada
  local head = ES.UI.CardHead(page, 80)
  page.head = head
  page.name = Label(head, "", "GameFontNormalHuge")
  page.name:SetPoint("TOP", 26, -14)
  page.name:SetWordWrap(false)
  page.icon = head:CreateTexture(nil, "ARTWORK")
  page.icon:SetSize(42, 42)
  page.icon:SetPoint("RIGHT", page.name, "LEFT", -12, -6)
  page.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  -- Icono y nombre: el tooltip del objeto y, con Mayús+clic, buscarlo en la AH (o
  -- enlazarlo en el chat), como en el resto del addon (ES:ItemShiftClick)
  page.itemButton = CreateFrame("Button", nil, head)
  page.itemButton:SetPoint("LEFT", page.icon, "LEFT", 0, 0)
  page.itemButton:SetPoint("RIGHT", page.name, "RIGHT", 0, 0)
  page.itemButton:SetHeight(44)
  page.itemButton:RegisterForClicks("LeftButtonUp")
  page.itemButton:SetScript("OnClick", function()
    if ES.investItemID and IsShiftKeyDown and IsShiftKeyDown() then ES:ItemShiftClick(ES.investItemID) end
  end)
  page.itemButton:SetScript("OnEnter", function(self)
    if not ES.investItemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetHyperlink("item:" .. ES.investItemID)
    GameTooltip:AddLine(L["Mayús+clic: buscarlo en la AH"], 0.5, 0.8, 1)
    GameTooltip:Show()
  end)
  page.itemButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.info = Label(head, "", "GameFontHighlight")
  page.info:SetPoint("BOTTOM", head, "BOTTOM", 0, 13)
  page.info:SetTextColor(0.78, 0.76, 0.72)

  -- Franja de cuatro cifras: la etiqueta pequeña arriba y el valor grande, en celdas
  -- separadas por una línea fina
  local strip = ES.UI.Panel(page, DARK[1], DARK[2], DARK[3], DARK[4])
  strip:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
  strip:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -8)
  strip:SetHeight(64)
  page.boxes = {}
  local cells = { { "now", L["Precio ahora"] }, { "avg", L["Tu media"] },
    { "since", L["Desde tu media"], true }, { "last4", L["Últimos 4 días"], true } }
  local cellW = math.floor((ES.UI.LIST_WIDTH + 14) / #cells)
  for i, c in ipairs(cells) do
    local cell = CreateFrame("Frame", nil, strip)
    cell:SetPoint("TOPLEFT", (i - 1) * cellW, 0)
    cell:SetSize(cellW, 64)
    cell.label = Label(cell, c[2], "GameFontDisableSmall")
    cell.label:SetPoint("TOP", 0, -11)
    cell.value = Label(cell, "", "GameFontNormalHuge")
    cell.value:SetPoint("TOP", cell.label, "BOTTOM", c[3] and 11 or 0, -7)
    if c[3] then
      cell.arrow = cell:CreateTexture(nil, "ARTWORK")
      cell.arrow:SetSize(18, 18)
      cell.arrow:SetPoint("RIGHT", cell.value, "LEFT", -5, 1)
      cell.arrow:Hide()
    end
    if i > 1 then
      local sep = strip:CreateTexture(nil, "ARTWORK")
      sep:SetSize(1, 40)
      sep:SetPoint("LEFT", cell, "LEFT", 0, 0)
      sep:SetColorTexture(0.52, 0.38, 0.17, 0.6)
    end
    if c[1] == "now" then
      -- (de dónde sale el precio de ahora: tu escaneo o el historial de Auctionator)
      cell:EnableMouse(true)
      cell:SetScript("OnEnter", function(self)
        local h = page.entry and page.entry.history
        if not h then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddDoubleLine(L["Precio ahora"], Money(h.now.price), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddLine(SourceText(h.now.source, h.now.age), 0.5, 0.8, 1)
        local depth = DepthLine(ES.investItemID, h.now.price)
        if depth then GameTooltip:AddLine(depth, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
      end)
      cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    page.boxes[c[1]] = cell
  end

  -- Gráfica
  local chartPanel = ES.UI.Panel(page, DARK[1], DARK[2], DARK[3], DARK[4])
  chartPanel:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -8)
  chartPanel:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, -8)
  chartPanel:SetHeight(170)
  page.chart = ES.UI.LineChart(chartPanel)
  page.chart:SetPoint("TOPLEFT", 4, -4)
  page.chart:SetPoint("BOTTOMRIGHT", -4, 4)

  -- Movimientos: título y botones; debajo, lo que tienes; y las filas como las de las
  -- rutas (ES.UI.RenderLines), con scroll
  local L2 = ES.UI.BROWN.list
  local moves = ES.UI.Panel(page, L2[1], L2[2], L2[3], L2[4])
  moves:SetPoint("TOPLEFT", chartPanel, "BOTTOMLEFT", 0, -8)
  moves:SetPoint("BOTTOMRIGHT", -ES.UI.PAD, ES.UI.PAD)
  local title = Label(moves, L["Movimientos"], "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -11)
  page.sell = CreateFrame("Button", nil, moves, "UIPanelButtonTemplate")
  page.sell:SetSize(104, 22)
  page.sell:SetPoint("TOPRIGHT", -10, -7)
  page.sell:SetText(L["+ Venta"])
  page.sell:SetScript("OnClick", function() OpenEntry(ES.investItemID, "sell") end)
  page.buy = CreateFrame("Button", nil, moves, "UIPanelButtonTemplate")
  page.buy:SetSize(104, 22)
  page.buy:SetPoint("RIGHT", page.sell, "LEFT", -6, 0)
  page.buy:SetText(L["+ Compra"])
  page.buy:SetScript("OnClick", function() OpenEntry(ES.investItemID, "buy") end)
  page.position = Label(moves, "", "GameFontHighlightSmall")
  page.position:SetPoint("LEFT", title, "RIGHT", 16, 0)
  page.position:SetPoint("RIGHT", page.buy, "LEFT", -12, 0)
  page.position:SetJustifyH("LEFT")
  page.position:SetWordWrap(false)
  page.position:SetTextColor(0.78, 0.74, 0.66)
  -- (si no cabe todo, se quitan partes: al pasar el ratón, todas, ver RenderInvestItem)
  page.positionHit = CreateFrame("Frame", nil, moves)
  page.positionHit:SetAllPoints(page.position)
  page.positionHit:EnableMouse(true)
  page.positionHit:SetScript("OnEnter", function(self)
    local all = page.positionParts
    if not all or #all == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    for _, p in ipairs(all) do
      if p.label then
        GameTooltip:AddDoubleLine(p.label, p.value, 0.8, 0.8, 0.8, 1, 1, 1)
      else
        GameTooltip:AddLine(p.value, 1, 1, 1, true)
      end
    end
    GameTooltip:Show()
  end)
  page.positionHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local scroll = ES.UI.WheelScroll(moves, ES.UI.ROW_HEIGHT + ES.UI.ROW_GAP)
  scroll:SetPoint("TOPLEFT", 8, -36)
  scroll:SetPoint("BOTTOMRIGHT", -8, 8)
  local list = { scroll = scroll, rows = {} }
  list.content = CreateFrame("Frame", nil, scroll)
  list.content:SetSize(ES.UI.LIST_WIDTH - 16, 1)
  scroll:SetScrollChild(list.content)
  list.indicator = ES.UI.ScrollIndicator(scroll, list.content)
  page.movesList = list

  page:SetScript("OnShow", function()
    PH.Clear()
    PH.Watch(function() ES:RenderInvest() ES:RenderInvestItem() end)
    ES:RenderInvestItem()
  end)
  self.investItemPage = page
end

-- "Nivel de objeto 60 · Herb · Trade Goods · Vendedor: 10s" (lo que sepa el juego)
local function ItemInfo(itemID)
  local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local _, _, _, level, _, kind, subKind = GetInfo(itemID)
  local parts = {}
  if level and level > 1 then parts[#parts + 1] = string.format(L["Nivel de objeto %d"], level) end
  if subKind and subKind ~= "" and subKind ~= kind then parts[#parts + 1] = subKind end
  if kind and kind ~= "" then parts[#parts + 1] = BLUE .. kind .. "|r" end
  local vendor = ES:VendorSellPrice(itemID)
  if vendor and vendor > 0 then parts[#parts + 1] = L["Vendedor: "] .. Money(vendor) end
  return table.concat(parts, GREY .. "  ·  |r")
end

function ES:RenderInvestItem()
  local page = self.investItemPage
  local itemID = self.investItemID
  if not page or not page:IsVisible() then return end
  if not itemID then self:SelectPage("invest") return end
  local e = Invest:Item(itemID)
  page.entry = e -- (pruebas)
  local h = e.history
  page.icon:SetTexture(ItemIcon(itemID))
  page.name:SetText(ItemLabel(itemID))
  page.info:SetText(ItemInfo(itemID))
  page.sell:SetEnabled(e.units > 0 and not e.broken)

  -- Cuatro cifras (el precio de ahora es el último punto válido de la gráfica)
  local b = page.boxes
  if h then
    b.now.value:SetText((h.now.stale and GREY or GOLD) .. Money(h.now.price) .. "|r")
  else
    b.now.value:SetText(DASH)
  end
  b.avg.value:SetText(e.avg and ("|cffffffff" .. Money(e.avg) .. "|r") or DASH)
  SetChange(b.since.arrow, b.since.value, e.changePct, e.stale, e.farmed)
  SetChange(b.last4.arrow, b.last4.value, h and h.change4, h and h.now.stale)

  -- Gráfica
  local chart = page.chart
  if not h then
    chart:SetDays(nil)
    -- (sin Auctionator, la recomendación va aquí también: es cuando más se echa en falta)
    chart:SetMessage(PH.Available() and L["Auctionator aún no tiene precios de este objeto: búscalo o escanea con Auctionator."]
      or L["Sin precios de este objeto. Instala Auctionator para escanear la AH y ver su evolución."])
  else
    chart:SetDays(h.days)
    local valid = 0
    for _, d in ipairs(h.days) do if not d.dubious then valid = valid + 1 end end
    chart:SetMessage(valid < 2 and L["Hace falta otro día con precio para ver la evolución."] or "")
  end

  -- Lo que tienes, junto al título de los movimientos. Si no cabe (entre el título y los
  -- botones hay poco sitio: se cortaba "Si vendes"), se quita primero el neto tras la AH
  -- y luego lo invertido (drop: orden en que se quitan); al pasar el ratón, todo
  if e.broken then
    page.positionParts = nil
    page.position:SetText(ORANGE .. L["Hay una venta de más unidades de las que tenías: borra o corrige el movimiento que no cuadra."] .. "|r")
  else
    local parts = {
      { value = string.format(L["Tienes %d u"], e.units) },
      { label = L["invertido"], value = Money(e.cost), drop = 2 },
    }
    if e.value then
      parts[#parts + 1] = { label = L["neto tras la AH"], value = Money(e.net), drop = 1 }
      parts[#parts + 1] = { label = L["Si vendes"], value = SignedMoney(e.latent) .. (e.latentPct and (" (" .. Pct(e.latentPct) .. ")") or "") }
    end
    if e.realized ~= 0 or e.sold > 0 then parts[#parts + 1] = { label = L["Realizado"], value = SignedMoney(e.realized) } end
    page.positionParts = parts
    local function Text(maxDrop)
      local out = {}
      for _, p in ipairs(parts) do
        if not (p.drop and p.drop <= maxDrop) then out[#out + 1] = p.label and (p.label .. " " .. p.value) or p.value end
      end
      return table.concat(out, "  ·  ")
    end
    page.position:SetText(Text(0))
    local width = tonumber(page.position:GetWidth()) or 0
    for maxDrop = 1, 2 do
      if width <= 0 or (tonumber(page.position:GetStringWidth()) or 0) <= width then break end
      page.position:SetText(Text(maxDrop))
    end
  end

  -- Movimientos: el más reciente arriba, en filas como las de las rutas
  local lines = {}
  local icon = ItemIcon(itemID)
  for i = #e.moves, 1, -1 do
    local m = e.moves[i]
    local amount = m.total or m.n * m.unit
    local sell = m.kind == "sell"
    lines[#lines + 1] = {
      icon = icon, item = itemID,
      title = (sell and (RED .. L["Vendido"] .. "|r") or (GREEN .. L["Comprado"] .. "|r")) .. "  " .. GREY .. DateText(m.t) .. "|r",
      sub = string.format(L["%d u a %s"], m.n, Money(amount / m.n)),
      -- (lo que pagas en rojo, lo que cobras neto en verde)
      value = ES.UI.Signed(sell and -(amount * (1 - Invest.AH_CUT)) or amount),
      tooltip = MoveTooltip(m),
      onSkip = function()
        GameTooltip:Hide()
        Invest:Remove(itemID, i)
        ES:RenderInvestItem()
      end,
      skipTitle = L["Borrar este movimiento"],
      skipTip = L["Los números del objeto y de la cartera se recalculan sin él."],
    }
  end
  ES.UI.RenderLines(page.movesList, lines)
  if page.movesList.indicator then page.movesList.indicator:Update() end
  -- Sin movimientos (borrado el último): vuelve a la cartera
  if #lines == 0 then self:SelectPage("invest") end
end
