local _, ES = ...
local L = ES.L

---------------------------------------------------------------------------
-- Pestaña Merchant's Favor: tus Waylaid Crates y con qué llenarlas al menor coste, y
-- las cajas de la AH ordenadas por lo que cuesta cada punto de Favor (Favor.lua).
-- Clic en una fila: lo que hay que comprar, a la Lista de compra.
---------------------------------------------------------------------------
local GREEN, GREY, ORANGE, GOLD = "|cff40ff40", "|cff9d9d9d", "|cffff9933", "|cffffd100"
local ICON = "Interface\\Icons\\INV_Misc_Coin_17"
local TIER = ES.Localize({ [1] = "Aprendiz", [2] = "Oficial", [3] = "Experto", [4] = "Artesano" })
local KIND = ES.Localize({ Herbs = "Hierbas", ["Earthly Herbs"] = "Hierbas terrestres", ["Flowering Herbs"] = "Hierbas en flor",
  Ore = "Mineral", Textiles = "Textiles", Curiosities = "Curiosidades", Fabrics = "Tejidos", Ingots = "Lingotes", Parts = "Piezas" })

local function ItemLabel(itemID) return ES.UI.ItemLabel(itemID, "#" .. itemID) end

-- "Experto · Tejidos"
local function CrateName(c)
  return (TIER[c.tier] or "?") .. ES.SEP .. (KIND[c.kind] or c.kind)
end
ES.Favor.CrateName = CrateName

local function FavorText(c)
  return (c.guess and "~" or "") .. c.favor
end

-- "8× Bolt of Mageweave"
local function FillText(fill)
  return string.format("%d× %s", fill.n, (ItemLabel(fill.itemID)))
end

local function Tooltip(o)
  return function(row)
    local c = o.crate
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine((ItemLabel(c.id)))
    GameTooltip:AddLine(string.format(L["Da %s de Merchant's Favor · pide nivel %d"], FavorText(c), c.level), 1, 1, 1)
    if c.guess then
      GameTooltip:AddLine(L["Cuánto Favor da esta caja no sale en las guías: es una estimación."], 1, 0.6, 0.2, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Se llena con uno de estos paquetes:"], 1, 0.82, 0)
    for _, f in ipairs(o.fills) do
      local mark = f == o.fill and (GREEN .. "> |r") or "   "
      local have = f.have >= f.n and (GREEN .. " " .. L["(lo tienes)"] .. "|r") or ""
      GameTooltip:AddDoubleLine(mark .. FillText(f) .. have, ES.Money(f.cost), 1, 1, 1, 1, 1, 1)
    end
    local priced = {}
    for _, f in ipairs(o.fills) do priced[f.itemID] = true end
    for _, f in ipairs(c.fills) do
      if not priced[f[1]] then
        GameTooltip:AddDoubleLine("   " .. string.format("%d× %s", f[2], (ItemLabel(f[1]))), GREY .. L["sin precio"] .. "|r", 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
      end
    end
    if o.fill then
      local crafts = ES.Favor.Crafts(o.fill)
      if #crafts > 0 then
        local parts = {}
        for _, x in ipairs(crafts) do parts[#parts + 1] = string.format("%d× %s", x.qty, (ItemLabel(x.itemID))) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["Antes, fabrica tú: %s (la lista de compra pide sus materiales)."], table.concat(parts, ", ")), 1, 0.82, 0, true)
      end
    end
    GameTooltip:AddLine(" ")
    if o.have > 0 then
      GameTooltip:AddLine(L["Llénala (clic derecho en la caja) y entrégala en el campamento de tu bando: Dokimi (Horda) o Marcy Baker (Alianza)."], 0.8, 0.8, 0.8, true)
    elseif o.onAH then
      GameTooltip:AddDoubleLine(L["La caja en la AH"], ES.Money(o.crateCost), 1, 0.82, 0, 1, 1, 1)
    end
    if o.fill then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(o.have > 0 and L["Clic: añadir el paquete a la lista de compra."]
        or L["Clic: añadir la caja y el paquete a la lista de compra."], 0.5, 0.8, 1, true)
    end
    GameTooltip:Show()
  end
end

-- Clic: lo que falta comprar (la caja si no la tienes, y el paquete) a la Lista de compra
local function AddToList(o)
  local items = ES.Favor.Purchases(o.fill)
  if o.have == 0 and o.onAH then
    table.insert(items, 1, { itemID = o.crate.id, quantity = 1, unit = o.crateCost, source = "ah" })
  end
  ES:AddToShopping("favor", string.format(L["Merchant's Favor: %s"], CrateName(o.crate)), items,
    { key = "favor:" .. o.crate.id, minusBags = true })
end

local function Line(o, mine)
  local c = o.crate
  local _, _, texture = ES:GetItemData(c.id)
  local title = (mine and o.have > 1 and (o.have .. "× ") or "") .. CrateName(c)
    .. GOLD .. "  " .. string.format(L["%s Favor"], FavorText(c)) .. "|r"
  local sub, value
  if not o.fill then
    sub = ORANGE .. L["Sin precio para ningún paquete: escanea la AH."] .. "|r"
    value = GREY .. "—|r"
  elseif mine then
    sub = string.format(L["llénala con %s (%s)"], FillText(o.fill), ES.Money(o.fill.cost))
      .. (o.haveFill and (ES.SEP .. GREEN .. L["ya lo tienes"] .. "|r") or "")
    value = ES.UI.Signed(o.fill.cost)
  else
    sub = string.format(L["caja %s + %s (%s)"], ES.Money(o.crateCost), FillText(o.fill), ES.Money(o.fill.cost))
      .. (o.haveFill and (ES.SEP .. GREEN .. L["ya tienes el paquete"] .. "|r") or "")
    value = string.format(L["%s/punto"], ES.Money(math.floor(o.perFavor + 0.5)))
  end
  return { icon = texture or (GetItemIcon and GetItemIcon(c.id)) or ICON, title = title, sub = sub, value = value,
    item = c.id, tooltip = Tooltip(o), onClick = o.fill and function() AddToList(o) end or nil }
end

function ES:CreateFavorPage(page)
  ES.UI.ListPage(page, "Merchant's Favor", ICON, {
    { key = "balance", label = L["Tu Merchant's Favor"] },
    { key = "cheapest", label = L["Punto más barato"] },
    { key = "crates", label = L["Cajas en tus bolsas"] },
  })
  page.subtitle:SetText(L["Llena una Waylaid Crate con uno de sus paquetes y entrégala en el campamento de tu bando: Dokimi (Horda) o Marcy Baker (Alianza)."])
  page.Render = function() ES:RenderFavor() end
  page:SetScript("OnShow", page.Render)
  -- Cambian tus bolsas o tu Favor: se repinta (si se ve)
  local f = CreateFrame("Frame")
  for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE" }) do ES.SafeRegister(f, ev) end
  f:SetScript("OnEvent", function() if page:IsVisible() then ES:RenderFavor() end end)
  self.favorPage = page
end

function ES:RenderFavor()
  local page = self.favorPage
  if not page or not page:IsVisible() then return end
  local list = ES.Favor:Options()
  local mine, market = {}, {}
  for _, o in ipairs(list) do
    if o.have > 0 then mine[#mine + 1] = o
    elseif o.perFavor then market[#market + 1] = o end
  end
  local balance = ES.Favor.Balance()
  page.stats.balance:SetText(balance and (GOLD .. balance .. "|r") or (GREY .. "—|r"))
  page.stats.cheapest:SetText(market[1] and ES.Money(math.floor(market[1].perFavor + 0.5)) or (GREY .. "—|r"))
  local crates = 0
  for _, o in ipairs(mine) do crates = crates + o.have end
  page.stats.crates:SetText(tostring(crates))

  local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
  if not scan then
    page.status:SetText(ORANGE .. L["Sin escaneo de la AH: escanea para ver lo que cuesta cada caja y cada paquete.|r"])
  else
    page.status:SetText(GREY .. string.format(L["Precios de la AH de hace %d min · tus materiales cuentan a lo que valen en la AH · clic en una fila: a la lista de compra|r"],
      math.floor((time() - scan.time) / 60)))
  end

  local lines = {}
  if #mine > 0 then
    lines[#lines + 1] = { section = L["Tus cajas: con qué llenarlas"] }
    for _, o in ipairs(mine) do lines[#lines + 1] = Line(o, true) end
  end
  if #market > 0 then
    lines[#lines + 1] = { section = L["Cajas en la AH: lo más barato por punto de Favor"] }
    for _, o in ipairs(market) do lines[#lines + 1] = Line(o, false) end
  end
  page.empty:SetText(#lines == 0 and (scan and L["No hay Waylaid Crates en la AH ni en tus bolsas."]
    or L["Escanea la AH para ver lo que cuesta cada caja."]) or "")
  ES.UI.RenderLines(page, lines)
end
