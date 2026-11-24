local _, ES = ...
local L = ES.L

-- Página "Ganar dinero": qué fabricar hoy con las recetas que sabes (Earn.lua),
-- el lote recomendado, lo que se vende al vendedor (aparte) y lo descartado
-- por las alertas de mercado.

local GREEN, GREY, ORANGE = "|cff40ff40", "|cff999999", "|cffff9933"
local MORE_IDEAS = 15 -- además del lote
local MAX_AVOIDED = 8
local MAX_LEARNABLE = 10
-- Franja de cifras bajo la cabecera, la línea de estado y la lista
local STRIP_GAP, STRIP_H, STATUS_GAP, LIST_GAP = 6, 52, 4, 8
-- Distancia de la cabecera a la lista, con la línea de estado de `statusH` píxeles
local function ListGap(statusH)
  return STRIP_GAP + STRIP_H + STATUS_GAP + math.max(12, math.ceil(tonumber(statusH) or 12)) + LIST_GAP
end
-- De dónde se aprende (los mismos textos que la ruta, ProfessionUI.lua)
local LEARN_LABEL = ES.Localize({ trainer = "instructor", vendor = "receta del vendedor", scroll = "pergamino AH", favor = "Merchant's Favor",
  quest = "misión", ah = "pergamino en la AH", owned = "pergamino en tus bolsas" })

local function ItemLabel(itemID, fallback)
  return ES.UI.ItemLabel(itemID, fallback)
end

-- Cuándo, con el reloj y la zona horaria del ordenador del jugador (date() del juego) y
-- su ajuste de 12 o 24 horas (reloj del juego): "hoy 18:40", "mañana 9:15 PM",
-- "viernes 14:30" (nombres del día del propio cliente) o "21/11 14:30" a más de 6 días.
-- nil si no hay date() (fuera del juego)
function ES.LocalTimeLabel(when, now)
  if not date then return nil end
  local t = date("*t", when)
  local use24 = true
  if GetCVarBool then
    local ok, v = pcall(GetCVarBool, "timeMgrUseMilitaryTime")
    if ok and v == false then use24 = false end
  end
  local clock = use24 and string.format("%02d:%02d", t.hour, t.min)
    or string.format("%d:%02d %s", (t.hour + 11) % 12 + 1, t.min, t.hour < 12 and "AM" or "PM")
  local day = date("%Y-%m-%d", when)
  if day == date("%Y-%m-%d", now) then return string.format(L["hoy %s"], clock) end
  if day == date("%Y-%m-%d", now + 86400) then return string.format(L["mañana %s"], clock) end
  if when - now < 6 * 86400 then
    local names = CALENDAR_WEEKDAY_NAMES
    return ((names and names[t.wday]) or date("%A", when)) .. " " .. clock
  end
  return date("%d/%m", when) .. " " .. clock
end

local function IdeaTooltip(idea)
  return function(row)
    local e = idea.e
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine((ItemLabel(e.itemID, e.recipe.name)))
    GameTooltip:AddLine(ES:ProfLabel(idea.profKey) .. ES.SEP .. e.recipe.name, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(e.qty > 1 and string.format(L["Materiales (1 fabricación = %s uds):"], ES.Num(e.qty)) or L["Materiales (1 fabricación):"], 1, 0.82, 0)
    for _, rg in ipairs(e.reagents or {}) do
      GameTooltip:AddDoubleLine(string.format("%dx %s", rg.qty, (ItemLabel(rg.item, L["Objeto "] .. rg.item))), ES.Money(rg.cost), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    local W = { 0.8, 0.8, 0.8, 1, 1, 1 }
    -- Lo que se cobra es por unidad; si una fabricación da varias, también lo de todas
    -- (que cuadre con el coste y el beneficio por fabricación)
    local function Sale(unit)
      if (e.qty or 1) <= 1 then return ES.Money(unit) end
      return ES.Money(unit) .. GREY .. " ×" .. e.qty .. " = |r" .. ES.Money(unit * e.qty)
    end
    GameTooltip:AddDoubleLine(L["Coste por fabricación"], ES.Money(e.cost), unpack(W))
    if idea.sellWhere == "ah" then
      GameTooltip:AddDoubleLine(L["La más barata en la AH"], ES.Money(e.ahMin), unpack(W))
      ES.Market.AddFairToTooltip(e.fair)
      GameTooltip:AddDoubleLine(L["A la venta ahora"], string.format(L["%d subastas, %d uds"], e.listings, e.quantity), unpack(W))
      GameTooltip:AddDoubleLine(string.format(e.fair and e.fair.inflated and L["Te queda al precio de los últimos días (-%d%%, depósito)"]
        or L["Te queda igualando a la más barata (-%d%%, depósito)"], e.cut * 100), Sale(e.ahNet), unpack(W))
    else
      GameTooltip:AddDoubleLine(L["Vendedor te paga"], Sale(e.vendor), unpack(W))
    end
    GameTooltip:AddDoubleLine(L["Beneficio por fabricación"], GREEN .. "+" .. ES.Money(e.profit) .. "|r", unpack(W))
    if idea.crafts then
      GameTooltip:AddLine(" ")
      if idea.custom then
        GameTooltip:AddLine(string.format(L["Fabrica %d: la cantidad la elegiste tú (recomendadas: %d). Vuelve a la recomendada con el siguiente escaneo."],
          idea.crafts, idea.recommended or idea.crafts), 1, 0.82, 0, true)
        if idea.recommended and idea.wanted > idea.recommended then
          GameTooltip:AddLine(L["Más de lo recomendado: si no se venden, tienes el oro parado y puedes perder depósitos al caducar."], 1, 0.6, 0.2, true)
        end
      else
        GameTooltip:AddLine(string.format(L["Fabrica %d: %s"], idea.crafts, idea.why or ""), 1, 0.82, 0, true)
      end
      if idea.why2 then GameTooltip:AddLine(idea.why2, 0.6, 1, 0.6, true) end
      if idea.cdUnknown then
        GameTooltip:AddLine(L["No se sabe aún si su enfriamiento está listo: al abrir la profesión se comprueba (si no lo está, sale del lote)."], 1, 0.6, 0.2, true)
      end
      if idea.fewer then GameTooltip:AddLine(L["Menos de las que caben: con más, los materiales salen más caros y ya no compensa."], 1, 0.6, 0.2, true) end
      if idea.limit == "margin" then
        GameTooltip:AddLine(L["Hasta aquí: más allá, los materiales que quedan en la AH salen tan caros que la siguiente ya no compensa."], 0.8, 0.8, 0.8, true)
      elseif idea.limit == "supply" then
        GameTooltip:AddLine(L["Hasta aquí: no quedan más materiales a la venta en la AH."], 0.8, 0.8, 0.8, true)
      elseif idea.limit == "max" then
        GameTooltip:AddLine(string.format(L["Tope de %d fabricaciones: con más aún daría beneficio."], idea.crafts), 0.8, 0.8, 0.8, true)
      elseif idea.limit == "time" and not idea.shuffle then
        GameTooltip:AddLine(string.format(L["Hasta aquí: unos %d min de fabricar. Más fabricaciones aún darían beneficio, pero no compensa el tiempo."],
          math.floor(ES.Earn.VENDOR_TIME_BUDGET / 60)), 0.8, 0.8, 0.8, true)
      end
      -- Fabricar en cantidad: una hora de fabricar (o menos, si antes deja de compensar)
      if idea.shuffle and (idea.crafts or 0) > 0 then
        if idea.limit == "time" then
          GameTooltip:AddLine(L["Lo que cabe en una hora de fabricar: más horas aún darían beneficio. Compensa si fabricas sin estar delante."], 1, 0.82, 0, true)
        else
          GameTooltip:AddLine(string.format(L["Solo unos %d min de fabricar: es lo que deja en una hora."],
            math.max(1, math.floor((idea.seconds or 0) / 60 + 0.5))), 1, 0.82, 0, true)
        end
        if idea.noProf then
          GameTooltip:AddLine(string.format(L["No tienes %s: es para otro personaje."], ES:ProfLabel(idea.profKey)), 1, 0.6, 0.2, true)
        end
        if idea.learnable and e.learnSource == "unknown" then
          GameTooltip:AddLine(L["No se sabe dónde se consigue su receta (quizá un botín raro): sale por si tú o alguien de tu cuenta la tiene."], 1, 0.6, 0.2, true)
        end
        if (idea.stockCrafts or 0) > idea.crafts then
          GameTooltip:AddLine(string.format(L["En la AH hay para %d fabricaciones (~%d h): compensa comprar ya también lo de las horas siguientes."],
            idea.stockCrafts, math.max(1, math.floor((idea.stockHours or 0) + 0.5))), 0.6, 1, 0.6, true)
        end
        -- Precio máximo de compra de cada material de la AH (Earn.MaxPrices)
        if idea.maxPrices and #idea.maxPrices > 0 then
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(L["Compensa comprar hasta (con lo demás a lo de hoy):"], 1, 0.82, 0)
          for _, p in ipairs(idea.maxPrices) do
            GameTooltip:AddDoubleLine((ItemLabel(p.itemID, "#" .. p.itemID)),
              ES.Money(p.max) .. GREY .. ES.SEP .. string.format(L["hoy ~%s"], ES.Money(p.now)) .. "|r", 1, 1, 1, 1, 1, 1)
          end
        end
      end
      -- Lo intermedio que fabricas tú (de lo que compras): hay que hacerlo antes. Si
      -- no, la lista de compra pedía Heavy Stone sin decir que es para hacer el Heavy
      -- Blasting Powder que pide la receta (CurseForge)
      local first = {}
      for _, a in ipairs(idea.actions or {}) do
        if a.kind == "craft" and a.item ~= e.itemID and (a.qty or 0) > 0 then
          -- (de otra profesión, como fundir con Minería: se dice cuál)
          first[#first + 1] = string.format("%d× %s", math.ceil(a.qty - 0.001), (ItemLabel(a.item, "#" .. a.item)))
            .. (a.prof and (" (" .. ES:ProfLabel(a.prof) .. ")") or "")
        end
      end
      if #first > 0 and idea.crafts > 0 then
        GameTooltip:AddLine(string.format(L["Antes, fabrica tú: %s (la lista de compra pide sus materiales)."], table.concat(first, ", ")),
          1, 0.82, 0, true)
      end
      if idea.crafts > 0 then
        GameTooltip:AddDoubleLine(L["Inviertes"], ES.Money(idea.invest), unpack(W))
        -- De eso, lo que ya llevas: no lo pagas, pero cuenta a precio de la AH
        local bags = ES.Earn.FromBags(ES.Earn.Shopping({ idea }))
        if bags.value > 0 then
          GameTooltip:AddDoubleLine(L["  ya lo tienes"], ES.Money(bags.value), 0.6, 1, 0.6, 0.6, 1, 0.6)
          for i, it in ipairs(bags.items) do
            if i > 4 then break end
            GameTooltip:AddDoubleLine(string.format("    %d× %s", it.n, (ItemLabel(it.itemID, "#" .. it.itemID))), ES.Money(it.value), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
          end
          GameTooltip:AddDoubleLine(L["  pagas"], ES.Money(math.max(0, idea.invest - bags.value)), unpack(W))
        end
        GameTooltip:AddDoubleLine(L["Beneficio si se venden todas"], GREEN .. "+" .. ES.Money(idea.profit) .. "|r", unpack(W))
        if bags.value > 0 then
          GameTooltip:AddLine(L["Tus materiales cuentan a lo que valen en la AH: venderlos es la otra opción."], 0.6, 0.6, 0.6, true)
        end
      end
      if idea.sellWhere == "ah" then
        GameTooltip:AddLine(string.format(e.fair and e.fair.inflated and L["Anúncialos a %s (el precio de los últimos días, algo por encima)."]
          or L["Anúncialos a %s (1 cobre menos que la más barata)."], ES.Money(idea.price)), 0.8, 0.8, 0.8, true)
      end
    end
    if idea.learnable then
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine(string.format(L["Aprender (%s)"], LEARN_LABEL[e.learnSource] or "?"),
        (e.learnCost or 0) > 0 and ES.Money(e.learnCost) or (GREY .. "?|r"), 1, 0.82, 0, 1, 1, 1)
      GameTooltip:AddLine(idea.canLearn and string.format(L["Pide %s %d: ya puedes aprenderla."], ES:ProfLabel(idea.profKey), idea.need)
        or string.format(L["Pide %s %d (tienes %d)."], ES:ProfLabel(idea.profKey), idea.need, idea.rank),
        idea.canLearn and 0.4 or 1, idea.canLearn and 1 or 0.6, idea.canLearn and 0.4 or 0.2, true)
      if idea.payback then
        GameTooltip:AddLine(string.format(idea.cooldown and L["Tiene enfriamiento (una cada vez): lo que cuesta aprenderla se recupera en %d fabricaciones."]
          or L["Lo que cuesta aprenderla se recupera en %d fabricaciones."], idea.payback), 0.8, 0.8, 0.8, true)
      elseif idea.cooldown then
        GameTooltip:AddLine(L["Tiene enfriamiento: se puede fabricar una cada vez."], 0.8, 0.8, 0.8, true)
      end
    end
    if idea.sellWhere == "ah" then ES.Market.AddToTooltip(e.itemID, e.ahPrice or e.ahMin) end
    if idea.shopping then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L["Cada línea del vendedor se calcula por separado: si dos usan los mismos materiales, haz una."], 0.6, 0.6, 0.6, true)
    end
    if not idea.learnable and (idea.crafts or 0) > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(string.format(L["Clic: abrir la receta y fabricar %d (con la profesión cerrada, el primer clic la abre)."], idea.crafts), 0.5, 0.8, 1, true)
    end
    if idea.shopping then
      GameTooltip:AddLine(L["Clic derecho: añadir sus materiales a la lista de compra."], 0.5, 0.8, 1, true)
    end
    GameTooltip:Show()
  end
end

ES.UI.EarnTooltip = IdeaTooltip -- (también la ventana junto a la profesión, CraftWindowUI.lua)

-- ✕ de una fila: quitar la receta de Ganar dinero (se recupera con la fila del final)
local function HideRecipe(line, id)
  line.onSkip = function()
    ES.Earn.SetHidden(id, true)
    ES:RenderEarn()
    if ES.CraftWindow and ES.CraftWindow.Refresh then ES.CraftWindow:Refresh() end
  end
  line.skipTitle = L["Quitar de Ganar dinero"]
  line.skipTip = L["No volver a proponer esta receta aquí: por ejemplo, si pide una estación que no tienes. Se recupera con la fila de recetas quitadas, al final de la lista."]
  return line
end

-- Lo de una fabricación entre las unidades que da (Shadow Oil da 2): para las cifras
-- "/u", junto al precio de la AH, que es de una. Antes salía el coste de una
-- fabricación como "/u" y parecía vender con pérdida (CurseForge: aceites de Alquimia)
local function PerUnit(e, copper)
  return math.floor(copper / math.max(1, e.qty or 1) + 0.5)
end

-- "5× Shadow Oil (10 uds)": las fabricaciones y, si cada una da varias, las unidades
local function CraftsTitle(e, crafts, name)
  local title = string.format("%d× %s", crafts, name)
  if (e.qty or 1) > 1 then title = title .. GREY .. string.format(L[" (%d uds)"], crafts * e.qty) .. "|r" end
  return title
end

local function IdeaLineBase(idea, dim)
  local e = idea.e
  local name, texture = ItemLabel(e.itemID, e.recipe.name)
  local where = idea.sellWhere == "ah"
    and (string.format(L["AH %s/u (%d a la venta) · %s"], ES.Money(e.ahPrice or e.ahMin), e.quantity, ES.Market.LABELS[idea.verdict])
      .. (e.fair and e.fair.inflated and (ORANGE .. L[" · ahora inflado"] .. "|r") or ""))
    or string.format(L["vendedor %s/u"], ES.Money(e.vendor))
  local sub = string.format(L["%s · coste %s/u · %s"], ES:ProfLabel(idea.profKey), ES.Money(PerUnit(e, e.cost)), where)
  if dim then
    return { icon = texture or 134400, title = GREY .. (name or e.recipe.name) .. "|r", sub = sub,
      value = GREY .. "+" .. ES.Money(PerUnit(e, e.profit)) .. "/u|r", item = e.itemID, tooltip = IdeaTooltip(idea) }
  end
  if idea.crafts == 0 then
    -- Ya tienes las que tocan: no hay que fabricar, solo anunciarlas
    return { icon = texture or 134400, title = string.format(L["Ya tienes %d× %s"], idea.have, name or e.recipe.name),
      sub = sub, value = GREEN .. L["anúncialas"] .. "|r", item = e.itemID, tooltip = IdeaTooltip(idea) }
  end
  -- Clic: abre la receta en la ventana de la profesión y fabrica las que tocan, como
  -- los pasos de la ruta (ES:CraftRecipe: con la ventana cerrada, el primer clic la
  -- abre y el segundo fabrica; como mucho, las que dan los materiales que llevas)
  local onClick, onRightClick
  if not idea.learnable and (idea.crafts or 0) > 0 then
    onClick = function() ES:CraftRecipe(e.id, idea.crafts) end
  end
  if idea.shopping then
    -- Venta al vendedor: cada línea, su propia lista de compra (una por receta y día).
    -- Clic derecho: el clic es fabricar
    onRightClick = function()
      local day = date and date("%d/%m") or ""
      ES:AddToShopping("money", string.format(L["Ganar dinero: %d× %s"], idea.crafts, name or e.recipe.name), idea.shopping,
        { key = e.id .. ":" .. day, minusBags = true })
    end
  end
  -- Lote de la AH: botones − y + para elegir tú cuántas (Earn.StepQuantity). Por
  -- encima de lo recomendado, se dice en naranja
  local onStep
  if idea.cooldown then
    sub = sub .. (idea.cdUnknown and (ORANGE .. L[" · enfriamiento: ¿listo?"] .. "|r") or (GREEN .. L[" · enfriamiento listo"] .. "|r"))
  elseif idea.inBatch and idea.sellWhere == "ah" then
    onStep = function(delta)
      ES.Earn.StepQuantity(idea, delta)
      if ES.RenderEarn then ES:RenderEarn() end
    end
    if idea.custom and idea.recommended and idea.wanted > idea.recommended then
      sub = sub .. ORANGE .. string.format(L[" · más de lo recomendado (%d)"], idea.recommended) .. "|r"
    end
  end
  return { icon = texture or 134400, title = CraftsTitle(e, idea.crafts, name or e.recipe.name), sub = sub,
    value = ES.UI.Signed(-idea.profit), item = e.itemID, tooltip = IdeaTooltip(idea), onClick = onClick,
    onRightClick = onRightClick, onStep = onStep }
end

-- Cada idea, con su ✕ para quitarla de Ganar dinero
local function IdeaLine(idea, dim)
  return HideRecipe(IdeaLineBase(idea, dim), idea.e.id)
end

-- BulkMoney (BulkMoneyUI.lua): cada línea es una hora de fabricar (Earn:VendorShuffle):
-- el título, las fabricaciones de esa hora; la cifra, el oro por hora (lo que dejan).
-- Si deja de compensar antes de la hora, cuándo; si no la sabes, cómo se aprende
-- (con su propia ✕: quitarla de BulkMoney no la quita de Ganar dinero, Earn.SetBulkHidden)
function ES.UI.BulkMoneyLine(idea)
  local line = IdeaLineBase(idea)
  local id = idea.e.id
  line.onSkip = function()
    ES.Earn.SetBulkHidden(id, true)
    if ES.RenderBulkMoney then ES:RenderBulkMoney() end
  end
  line.skipTitle = L["Quitar de BulkMoney"]
  line.skipTip = L["No volver a proponer esta receta aquí: por ejemplo, si no sabes conseguir su patrón. No la quita de Ganar dinero. Se recupera con la fila de recetas quitadas, al final de la lista."]
  local e = idea.e
  line.value = GREEN .. "+" .. string.format(L["%s/h"], ES.Money(idea.profit or 0)) .. "|r"
  local minutes = math.max(1, math.floor((idea.seconds or 0) / 60 + 0.5))
  if minutes < 55 then
    line.sub = line.sub .. ES.SEP .. ORANGE .. string.format(L["se acaba en ~%d min"], minutes) .. "|r"
  elseif (idea.stockHours or 0) >= 1.5 then
    -- Hay material barato para más horas (Earn.StockFor): compensa comprarlo ya
    line.sub = line.sub .. ES.SEP .. GREEN .. string.format(L["en la AH hay para ~%d h"], math.floor(idea.stockHours + 0.5)) .. "|r"
  end
  if idea.learnable then
    local learn = (LEARN_LABEL[e.learnSource] or (e.learnSource == "basic" and L["al aprender la profesión"])
      or (e.learnSource == "rep" and L["Reputación"])
      or (e.learnSource == "unknown" and (ORANGE .. L["Fuente desconocida"] .. "|r")) or "?")
      .. ((e.learnCost or 0) > 0 and (" " .. ES.Money(e.learnCost)) or "")
    local req = idea.canLearn and (GREEN .. L["ya puedes"] .. "|r") or (ORANGE .. string.format(L["pide %d"], idea.need) .. "|r")
    line.sub = line.sub .. ES.SEP .. learn .. ES.SEP .. req
  end
  return line
end

function ES:CreateEarnPage(page)
  local Label = ES.UI.Label
  local head = ES.UI.CardHead(page, 70) -- (fondo y colores de Subir profesiones)
  local icon = head:CreateTexture(nil, "ARTWORK")
  icon:SetSize(44, 44)
  icon:SetPoint("LEFT", 12, 0)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local name = Label(head, L["Ganar dinero"], "GameFontNormalHuge")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 4)
  name:SetTextColor(0.96, 0.79, 0.25)
  page.subtitle = Label(head, "", "GameFontHighlightSmall")
  page.subtitle:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
  page.subtitle:SetPoint("RIGHT", -370, 0)
  page.subtitle:SetJustifyH("LEFT")

  -- Deslizador por escalones con el valor encima (también con la rueda). o = { steps,
  -- current() -> escalón, set(i) -> cambió?, text(v) -> etiqueta, title, help }
  local function StepSlider(parent, o)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(170, 38)
    box.label = Label(box, "", "GameFontHighlightSmall")
    box.label:SetPoint("TOP", 0, 0)
    local slider = CreateFrame("Slider", nil, box, "BackdropTemplate")
    slider:SetSize(160, 16)
    slider:SetPoint("BOTTOM", 0, 2)
    slider:SetOrientation("HORIZONTAL")
    slider:SetBackdrop({
      bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
      edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", edgeSize = 8,
      insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetMinMaxValues(1, #o.steps)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:EnableMouseWheel(true)
    -- (se recalcula al soltar o tras un momento quieto: arrastrar no recalcula en cada paso)
    local pending, wanted
    local function Apply()
      pending = nil
      if o.set(wanted) then ES:RenderEarn() end
    end
    slider:SetScript("OnValueChanged", function(self, value)
      if page.syncing then return end
      wanted = math.max(1, math.min(#o.steps, math.floor(value + 0.5)))
      box.label:SetText(o.text(o.steps[wanted]))
      if not pending then
        pending = true
        C_Timer.After(0.25, Apply)
      end
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
      self:SetValue(math.max(1, math.min(#o.steps, (wanted or o.current()) + (delta > 0 and 1 or -1))))
    end)
    slider:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
      GameTooltip:AddLine(o.title, 1, 0.82, 0)
      GameTooltip:AddLine(o.help, 1, 1, 1, true)
      GameTooltip:AddLine(L["Arrastra o usa la rueda del ratón."], 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Pintar el valor guardado (sin que cuente como moverlo)
    function box.Sync()
      box.label:SetText(o.text(o.steps[o.current()]))
      page.syncing = true
      slider:SetValue(o.current())
      page.syncing = nil
    end
    box.slider = slider
    return box
  end

  -- Beneficio mínimo de cada línea (Earn.MIN_LINE_STEPS)
  local minBox = StepSlider(head, {
    steps = ES.Earn.MIN_LINE_STEPS, current = ES.Earn.MinLineStep, set = ES.Earn.SetMinLineStep,
    text = function(v) return v > 0 and string.format(L["Mínimo: %s"], ES.Money(v)) or L["Sin mínimo"] end,
    title = L["Beneficio mínimo"],
    help = L["No se proponen recetas que, con todas las fabricaciones que tocan, dejen menos que esto (tampoco materiales para vender que valgan menos)."],
  })
  minBox:SetPoint("RIGHT", -12, 0)
  page.minBox, page.minLabel, page.minSlider = minBox, minBox.label, minBox.slider

  -- Los materiales del lote de hoy a la Lista de compra (ShoppingUI.lua)
  local addButton = CreateFrame("Button", nil, head, "UIPanelButtonTemplate")
  addButton:SetSize(170, 24)
  addButton:SetPoint("RIGHT", minBox, "LEFT", -6, 0)
  addButton:SetText(L["Añadir a la lista de compra"])
  addButton:SetScript("OnClick", function()
    local res = ES.Earn:Ideas()
    -- (una por día: volver a añadirla el mismo día la sustituye)
    local day = date and date("%d/%m") or ""
    ES:AddToShopping("money", string.format(L["Ganar dinero: lote del %s"], day), res.shopping,
      { key = day, minusBags = true })
  end)
  addButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(L["Añadir a la lista de compra"], 1, 0.82, 0)
    GameTooltip:AddLine(L["Los materiales del lote de hoy que te faltan (descontando lo que llevas) pasan a la pestaña Lista de compra, desde donde los compras con la AH abierta."], 1, 1, 1, true)
    GameTooltip:Show()
  end)
  addButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.addButton = addButton


  local strip = CreateFrame("Frame", nil, page)
  strip:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 4, -STRIP_GAP)
  strip:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -4, -STRIP_GAP)
  strip:SetHeight(STRIP_H)
  page.stats = {}
  -- Columnas: la de lo que inviertes es la más ancha (lleva debajo "ya tienes · pagas",
  -- con dos cantidades en monedas)
  local STATS = {
    { key = "invest", label = L["Inviertes en materiales"], x = 6,   w = 290 },
    { key = "profit", label = L["Beneficio si se vende todo"], x = 306, w = 230 },
    { key = "count",  label = L["Recetas en el lote"], x = 546, w = 200 },
  }
  for _, s in ipairs(STATS) do
    local label = Label(strip, s.label, "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", s.x, -2)
    label:SetWidth(s.w)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    local value = Label(strip, "", "GameFontHighlightLarge")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    page.stats[s.key] = value
  end
  -- Debajo de lo que inviertes: lo que ya llevas y lo que pagas (Earn.FromBags). Con el
  -- ratón, qué materiales son
  page.investBags = Label(strip, "", "GameFontDisableSmall")
  page.investBags:SetPoint("TOPLEFT", page.stats.invest, "BOTTOMLEFT", 0, -3)
  page.investBags:SetWidth(STATS[1].w - 8) -- (su columna: no se mete en la de Beneficio)
  page.investBags:SetJustifyH("LEFT")
  page.investBags:SetWordWrap(false)
  page.investHover = CreateFrame("Frame", nil, strip)
  page.investHover:SetPoint("TOPLEFT", page.stats.invest, "TOPLEFT", 0, 0)
  page.investHover:SetPoint("BOTTOMLEFT", page.investBags, "BOTTOMLEFT", 0, 0)
  page.investHover:SetWidth(STATS[1].w - 8)
  page.investHover:EnableMouse(true)
  page.investHover:SetScript("OnEnter", function(self)
    local bags = page.bags
    if not (bags and bags.value > 0) then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(L["Ya tienes parte de los materiales"], 1, 0.82, 0)
    for i, it in ipairs(bags.items) do
      if i > 10 then break end
      GameTooltip:AddDoubleLine(string.format("%d× %s", it.n, (ItemLabel(it.itemID, "#" .. it.itemID))), ES.Money(it.value), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["No los pagas, pero el beneficio los cuenta a lo que valen en la AH: venderlos es la otra opción. Contarlos gratis haría parecer rentable gastar materiales caros en cosas que valen menos."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  page.investHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.status = Label(page, "", "GameFontHighlightSmall")
  page.status:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 2, -STATUS_GAP)
  page.status:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
  page.status:SetJustifyH("LEFT")
  page.status:SetJustifyV("TOP")
  page.status:SetWordWrap(true) -- (larga, con el mínimo: en dos líneas, no cortada)
  if page.status.SetMaxLines then page.status:SetMaxLines(2) end

  local list = ES.UI.ListPanel(page, head, ListGap(12))
  page.head, page.list = head, list
  local scroll = ES.UI.WheelScroll(list)
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -8, 8)
  page.content = CreateFrame("Frame", nil, scroll)
  page.content:SetSize(ES.UI.LIST_WIDTH, 1)
  scroll:SetScrollChild(page.content)
  page.rows = {}
  page.empty = Label(page.content, "", "GameFontDisable")
  page.empty:SetPoint("TOP", 0, -30)
  page.empty:SetWidth(600)

  ES.SafeRegister(page, "GET_ITEM_INFO_RECEIVED")
  page:SetScript("OnEvent", function(self, _, itemID)
    -- (sin verse, nada: al abrirse se pinta entera, OnShow; y solo con los que faltaban)
    if ES.UI.WaitingForItem(self, itemID) and not self.refreshQueued and self:IsVisible() then
      self.refreshQueued = true
      C_Timer.After(0.5, function()
        self.refreshQueued = false
        if self:IsVisible() then ES:RenderEarn() end
      end)
    end
  end)
  page:SetScript("OnShow", function()
    ES.db.lastProf = "money" -- la lista de compra de la AH empieza por el lote
    ES:RenderEarn()
  end)
  self.earnPage = page
end

-- Secciones plegables: clic en el encabezado (+ / −) la pliega o despliega. Se
-- recuerda (ES.db.earnCollapsed[key]); plegada, dice cuántas filas tiene.
-- Añade el encabezado a `lines` y devuelve si hay que pintar sus filas
local PLUS = "|TInterface\\Buttons\\UI-PlusButton-Up:14:14:0:0|t "
local MINUS = "|TInterface\\Buttons\\UI-MinusButton-Up:14:14:0:0|t "
function ES.UI.EarnCollapsed(key)
  return ES.db.earnCollapsed and ES.db.earnCollapsed[key] or false
end
local function Section(lines, key, title, n)
  local collapsed = ES.UI.EarnCollapsed(key)
  lines[#lines + 1] = {
    section = (collapsed and PLUS or MINUS) .. title .. (collapsed and (GREY .. " (" .. n .. ")|r") or ""),
    onClick = function()
      ES.db.earnCollapsed = ES.db.earnCollapsed or {}
      ES.db.earnCollapsed[key] = not collapsed or nil
      ES:RenderEarn()
    end,
    tooltip = function(row)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:AddLine(title, 1, 0.82, 0)
      GameTooltip:AddLine(collapsed and L["Clic: desplegar"] or L["Clic: plegar"], 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end,
  }
  return not collapsed
end

function ES:RenderEarn()
  local page = self.earnPage
  if not page or not page:IsVisible() then return end
  local res = ES.Earn:Ideas()
  local Signed = ES.UI.Signed

  page.stats.invest:SetText(#res.batch > 0 and Signed(res.invest) or (GREY .. "—|r"))
  -- (al pintar, no en la caché de ideas: tus bolsas cambian sin que cambien los precios)
  page.bags = #res.batch > 0 and ES.Earn.FromBags(res.shopping) or nil
  if page.bags and page.bags.value > 0 then
    page.investBags:SetText(string.format(L["ya tienes %s · pagas %s"], ES.Money(page.bags.value),
      ES.Money(math.max(0, res.invest - page.bags.value))))
  else
    page.investBags:SetText("")
  end
  page.stats.profit:SetText(#res.batch > 0 and Signed(-res.profit) or (GREY .. "—|r"))
  page.stats.count:SetText(tostring(#res.batch))
  page.addButton:SetEnabled(#res.shopping > 0)
  page.minBox.Sync()
  local left, leftHidden = ES.Earn:Leftovers()
  local hidden = res.hidden + leftHidden

  local profs = {}
  for _, k in ipairs(res.profs) do profs[#profs + 1] = ES:ProfLabel(k) end
  page.subtitle:SetText(#profs > 0 and string.format(L["Con las %d recetas que sabes de %s."], res.known, table.concat(profs, ", "))
    or L["Este personaje no tiene profesiones de fabricación."])

  local status
  if not res.scanTime then
    status = ORANGE .. L["Sin escaneo de la AH: escanea para ver qué da beneficio.|r"]
  elseif time() - res.scanTime > ES.Earn.OLD_SCAN then
    status = ORANGE .. string.format(L["Precios de hace %d h: escanea antes de fabricar.|r"], math.floor((time() - res.scanTime) / 3600))
  else
    status = GREY .. string.format(L["Precios de la AH de hace %d min · beneficio igualando a la más barata (comisión y depósito descontados)|r"],
      math.floor((time() - res.scanTime) / 60))
  end
  if hidden > 0 then
    status = status .. GREY .. string.format(L[" · %d por debajo del mínimo de %s|r"], hidden, ES.Money(res.minLine))
  end
  page.status:SetText(status)
  -- La lista empieza debajo del estado, que puede ocupar una o dos líneas
  page.list:SetPoint("TOPLEFT", page.head, "BOTTOMLEFT", 0, -ListGap(page.status:GetStringHeight()))

  local lines = {}
  if #res.batch > 0 and Section(lines, "batch", L["Lote de hoy"], #res.batch) then
    for _, idea in ipairs(res.batch) do lines[#lines + 1] = IdeaLine(idea) end
    lines[#lines + 1] = { total = true, title = L["Total del lote"],
      sub = L["Para comprar sus materiales: Añadir a la lista de compra (arriba)."],
      value = Signed(-res.profit) }
  end
  -- Venta al vendedor: segura, sin límite de ventas, aparte del lote
  local nVendor = math.min(#res.vendor, MORE_IDEAS)
  if nVendor > 0 and Section(lines, "vendor", L["Venta segura al vendedor"], nVendor) then
    for i = 1, nVendor do lines[#lines + 1] = IdeaLine(res.vendor[i]) end
  end
  -- Las que no entraron en el lote (no siempre las siguientes: una puede quedarse fuera
  -- porque las anteriores ya compran sus materiales, y entonces quizá ya no llegue al mínimo)
  local more = {}
  for _, idea in ipairs(res.ideas) do
    if not idea.inBatch and #more < MORE_IDEAS and ES.Earn.LineValue(idea) >= res.minLine then more[#more + 1] = idea end
  end
  if #more > 0 and Section(lines, "more", L["Más opciones con beneficio"], #more) then
    for _, idea in ipairs(more) do lines[#lines + 1] = IdeaLine(idea) end
  end
  -- Recetas que no sabes y darían beneficio: qué merece la pena aprender
  local nLearn = math.min(#res.learnable, MAX_LEARNABLE)
  if nLearn > 0 and Section(lines, "learnable", L["Recetas que podrías aprender"], nLearn) then
    for i = 1, nLearn do
      local idea = res.learnable[i]
      local e = idea.e
      local name, texture = ItemLabel(e.itemID, e.recipe.name)
      local learn = (LEARN_LABEL[e.learnSource] or "?") .. ((e.learnCost or 0) > 0 and (" " .. ES.Money(e.learnCost)) or "")
      local req = idea.canLearn and (GREEN .. L["ya puedes"] .. "|r")
        or (ORANGE .. string.format(L["pide %d"], idea.need) .. "|r")
      -- (en la AH, cuántos hay a la venta y la alerta, como en el lote: se ve si hay mercado)
      local where = idea.sellWhere == "ah"
        and string.format(L["AH %s/u (%d a la venta) · %s"], ES.Money(e.ahPrice or e.ahMin), e.quantity or 0,
          ES.Market.LABELS[idea.verdict] or "")
        or string.format(L["vendedor %s/u"], ES.Money(e.vendor))
      if idea.cooldown then where = where .. L[" · con enfriamiento"] end
      lines[#lines + 1] = HideRecipe({ icon = texture or 134400, title = name or e.recipe.name,
        sub = string.format("%s" .. ES.SEP .. "%s" .. ES.SEP .. "%s" .. ES.SEP .. "%s", ES:ProfLabel(idea.profKey), learn, req, where),
        value = GREEN .. "+" .. ES.Money(PerUnit(e, e.profit)) .. "/u|r", item = e.itemID, tooltip = IdeaTooltip(idea) }, e.id)
    end
  end
  -- Enfriamientos (transmutaciones...) que sabes
  local cds = ES.Earn:Cooldowns()
  if #cds > 0 and Section(lines, "cooldowns", L["Enfriamientos"], #cds) then
    for _, c in ipairs(cds) do
      local name, texture = ItemLabel(c.recipe.out and c.recipe.out[1] or 0, c.recipe.name)
      local sub
      if c.unknown then
        sub = GREY .. L["Abre la profesión para saber si está listo"] .. "|r"
      elseif not c.ready then
        -- Con la hora exacta en tu reloj: "Listo viernes 14:30 (en 95 h)"
        local now = time()
        local at = ES.LocalTimeLabel(now + c.left, now)
        sub = at and string.format(L["Listo %s (en %d h)"], at, math.ceil(c.left / 3600))
          or string.format(L["Listo en %d h"], math.ceil(c.left / 3600))
      elseif c.inBatch then
        sub = GREEN .. L["Listo: está en el lote de hoy"] .. "|r"
      else
        sub = GREEN .. L["Listo: fabrícalo hoy"] .. "|r"
      end
      local id = c.id
      lines[#lines + 1] = { icon = texture or 134400, title = name or c.recipe.name, sub = sub,
        value = c.profit and (c.profit > 0 and Signed(-c.profit) or (GREY .. L["sin beneficio ahora|r"])) or "",
        item = c.recipe.out and c.recipe.out[1],
        -- Clic: abrir la receta y fabricar una (con la profesión abierta se sabe si está lista)
        onClick = (c.ready or c.unknown) and function() ES:CraftRecipe(id, 1) end or nil }
    end
  end
  local nAvoided = math.min(#res.avoided, MAX_AVOIDED)
  if nAvoided > 0 and Section(lines, "avoided", L["Con beneficio pero las alertas dicen evitar"], nAvoided) then
    for i = 1, nAvoided do lines[#lines + 1] = IdeaLine(res.avoided[i], true) end
  end
  -- Materiales que llevas y no usa ninguna receta que sabes: para vender
  local nLeft = math.min(#left, 10)
  if nLeft > 0 and Section(lines, "leftovers", L["Materiales que llevas y no usas (para vender)"], nLeft) then
    for i = 1, nLeft do
      local it = left[i]
      local name, texture = ItemLabel(it.itemID, L["Objeto "] .. it.itemID)
      local where = it.ahPrice and it.ahPrice * 0.95 > it.vendor
        and (string.format(L["AH %s/u"], ES.Money(it.ahPrice)) .. (it.fair and it.fair.inflated and (ORANGE .. L[" · ahora inflado"] .. "|r") or ""))
        or string.format(L["vendedor %s/u"], ES.Money(it.vendor))
      lines[#lines + 1] = { icon = texture or 134400, title = it.count .. "× " .. (name or ""), sub = where,
        value = ES.UI.Signed(-it.value), item = it.itemID,
        onClick = ES.ahOpen and function() ES:SearchAuction(it.itemID) end or nil }
    end
  end
  -- Recetas quitadas con la ✕: clic para volver a tenerlas todas en cuenta
  local removed = ES.Earn.HiddenList()
  if #removed > 0 then
    lines[#lines + 1] = {
      icon = "Interface\\Buttons\\UI-RefreshButton", iconSize = 16,
      title = string.format(L["Recetas quitadas de Ganar dinero: %d"], #removed),
      sub = L["Clic para volver a tenerlas en cuenta"],
      onClick = function()
        for _, r in ipairs(removed) do ES.Earn.SetHidden(r.id, false) end
        ES:RenderEarn()
        if ES.CraftWindow and ES.CraftWindow.Refresh then ES.CraftWindow:Refresh() end
      end,
      tooltip = function(row)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Quitadas de Ganar dinero"])
        for _, r in ipairs(removed) do GameTooltip:AddLine(r.name, 0.8, 0.8, 0.8) end
        GameTooltip:AddLine(L["Clic para volver a tenerlas en cuenta"], 0.5, 0.8, 1)
        GameTooltip:Show()
      end,
    }
  end
  page.empty:SetText(#lines == 0 and (#res.profs == 0 and L["Aprende una profesión de fabricación para ver ideas."]
    or not res.scanTime and L["Escanea la AH para ver qué da beneficio."]
    or L["Ninguna receta que sabes da beneficio con los precios actuales."]) or "")
  ES.UI.RenderLines(page, lines)
end
