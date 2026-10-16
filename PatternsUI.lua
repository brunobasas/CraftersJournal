local _, ES = ...
local L = ES.L

-- Pestaña "Colección de recetas" (Patterns): una tarjeta por profesión con cuántas
-- recetas del juego tienes ("15 / 235 recetas · 7%"). Al pulsarla se abre la
-- colección de esa profesión (CollectionUI.lua) en su propia página "pattern:<prof>".

local GREEN, GREY, GOLD = "|cff40ff40", "|cff9d9d9d", "|cffffd100"

function ES:CreatePatternsPage(page)
  local subtitle = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", 18, -2)
  subtitle:SetTextColor(0.75, 0.75, 0.75)
  subtitle:SetText(L["Todas las recetas que ofrece el juego en cada profesión: cuántas tienes y dónde conseguir las que faltan."])

  local line = page:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", 16, -20)
  line:SetPoint("TOPRIGHT", -16, -20)
  line:SetHeight(1)
  line:SetColorTexture(1, 0.82, 0, 0.25)

  local scroll = ES.UI.WheelScroll(page)
  scroll:SetPoint("TOPLEFT", 16, -28)
  scroll:SetPoint("BOTTOMRIGHT", -16, 12)
  page.content = CreateFrame("Frame", nil, scroll)
  page.content:SetSize(ES.UI.CARD_MIN_W * 2 + ES.UI.CARD_GAP, 1)
  scroll:SetScrollChild(page.content)
  page.scroll = scroll
  page.cards = {}
  page:SetScript("OnShow", function() ES:RenderPatterns() end)
  self.patternsPage = page
end

-- Página de la colección de una profesión
function ES:CreatePatternPage(page, profKey)
  local frame = CreateFrame("Frame", nil, page)
  frame:SetPoint("TOPLEFT", 10, -2)
  frame:SetPoint("BOTTOMRIGHT", -10, 4)
  ES:CreateCollectionView(frame, profKey)
  frame:Show() -- se refresca al mostrarse la página (OnShow de la vista)
  page.collectionFrame = frame
  self.patternPages = self.patternPages or {}
  self.patternPages[#self.patternPages + 1] = page
end

local function PatternTooltip(key, known, total, learned)
  return function(card)
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ES:ProfLabel(key))
    GameTooltip:AddLine(string.format(L["Tienes %d de las %d recetas del juego."], known, total), 0.8, 0.8, 0.8)
    if not learned then
      GameTooltip:AddLine(L["Este personaje no tiene la profesión."], 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Pulsa para ver todas sus recetas y dónde se consiguen."], 0.5, 0.8, 1)
    GameTooltip:Show()
  end
end

function ES:RenderPatterns()
  local page = self.patternsPage
  if not page or not page:IsVisible() then return end
  local entries = {}
  for order, prof in ipairs(ES.PROFESSIONS) do
    local data = ES.Data[prof.key]
    if data and ES:ProfessionVisible(prof) then
      local known, total = ES.Collection:Progress(prof.key)
      entries[#entries + 1] = { prof = prof, order = order, known = known, total = total,
        learned = ES:GetProfessionSkill(data.skillLine) ~= nil }
    end
  end
  -- Tus profesiones primero (las más completas antes), luego el resto
  table.sort(entries, function(a, b)
    if a.learned ~= b.learned then return a.learned end
    local pa, pb = a.known / math.max(1, a.total), b.known / math.max(1, b.total)
    if pa ~= pb then return pa > pb end
    return a.order < b.order
  end)
  local cards = {}
  for _, e in ipairs(entries) do
    local key = e.prof.key
    local pct = math.floor(e.known / math.max(1, e.total) * 100 + 0.5)
    cards[#cards + 1] = {
      key = key, name = ES:ProfLabel(key), icon = e.prof.icon or ES.ICON, learned = e.learned,
      cost = (e.known >= e.total and GREEN or GOLD) .. pct .. "%|r",
      level = string.format(L["%s%d|r de %d recetas"], e.learned and GOLD or GREY, e.known, e.total),
      note = e.learned and "" or (GREY .. L["No la tienes|r"]),
      tooltip = PatternTooltip(key, e.known, e.total, e.learned),
      onClick = function() ES:SelectPage("pattern:" .. key) end,
    }
  end
  ES.UI.RenderCards(page, cards)
end

-- Tras un escaneo: la colección que esté a la vista
function ES:RefreshPatternPages()
  self:RenderPatterns()
  for _, page in ipairs(self.patternPages or {}) do
    if page:IsVisible() then self:RefreshCollection(page.collectionFrame) end
  end
end
