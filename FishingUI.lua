local _, ES = ...
local L = ES.L

-- Página de la Pesca. No hay ruta de fabricación: se sube pescando, así que la
-- página es la guía por tramos (Data/Fishing.lua): qué rango aprender y dónde, y
-- en qué zonas pescar. El tramo en el que estás va marcado.

local GOLD, GREEN, GREY = "|cffffd100", "|cff40ff40", "|cff9d9d9d"
local MAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local RANK_LABEL = ES.Localize({ apprentice = "Aprendiz", journeyman = "Oficial", expert = "Experto", artisan = "Artesano" })

-- Nombre de una zona en el idioma del cliente (o el inglés de los datos)
function ES.ZoneLabel(mapID, fallback)
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  return info and info.name or fallback
end

-- Tramo de la guía para tu nivel de Pesca
function ES.FishingStep(data, skill)
  for _, step in ipairs(data.guide) do
    if skill < step.to then return step end
  end
  return data.guide[#data.guide]
end

function ES:CreateFishingPage(page, profKey)
  local Panel, Label = ES.UI.Panel, ES.UI.Label
  local data = ES.Data[profKey]
  page.data, page.profKey, page.rows, page.lines = data, profKey, {}, {}

  local head = Panel(page)
  head:SetPoint("TOPLEFT", 10, -2)
  head:SetPoint("TOPRIGHT", -10, -2)
  head:SetHeight(66)
  local icon = head:CreateTexture(nil, "ARTWORK")
  icon:SetSize(44, 44)
  icon:SetPoint("LEFT", 12, 0)
  icon:SetTexture("Interface\\Icons\\Trade_Fishing")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local name = Label(head, ES:ProfLabel(profKey), "GameFontNormalHuge")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 2)
  name:SetTextColor(0.96, 0.79, 0.25)
  page.levelText = Label(head, "", "GameFontHighlight")
  page.levelText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 12, 0)
  local hint = Label(head, L["Se sube pescando: no hace falta fabricar nada. Necesitas una caña y, si los peces se escapan, cebos."], "GameFontHighlightSmall")
  hint:SetPoint("LEFT", page.levelText, "RIGHT", 16, 0)
  hint:SetPoint("RIGHT", -12, 0)
  hint:SetJustifyH("LEFT")
  hint:SetTextColor(0.75, 0.75, 0.75)

  local list = Panel(page, 0.07, 0.05, 0.03, 0.9)
  list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
  list:SetPoint("BOTTOMRIGHT", -10, 4)
  local scroll = ES.UI.WheelScroll(list)
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -8, 8)
  page.content = CreateFrame("Frame", nil, scroll)
  page.content:SetSize(ES.UI.LIST_WIDTH, 1)
  scroll:SetScrollChild(page.content)
  page.scroll = scroll
  page.empty = Label(page.content, "", "GameFontDisable")
  page.empty:SetPoint("TOP", 0, -30)

  page:SetScript("OnShow", function(self) ES:RenderFishing(self) end)
  self.fishingPage = page
end

function ES:RenderFishing(page)
  local data = page.data
  local WP = ES.Waypoints
  local skill = self:GetProfessionSkill(data.skillLine)
  page.levelText:SetText(string.format(L["Nivel %s%d|r"], GOLD, skill or 1) .. (skill and "" or (GREY .. L[" (no la tienes)|r"])))
  local current = ES.FishingStep(data, skill or 1)
  local lines = {}
  for _, step in ipairs(data.guide) do
    local here = step == current
    local done = (skill or 0) >= step.to
    lines[#lines + 1] = { section = string.format("%d-%d · %s%s", step.from, step.to, RANK_LABEL[step.rank],
      here and (GREEN .. L["  ← estás aquí"] .. "|r") or done and (GREY .. L["  (hecho)"] .. "|r") or "") }
    -- Cómo conseguir el rango
    local req = string.format(L["Pide Pesca %d y nivel %d"], step.skill, step.level)
    if step.rank == "apprentice" or step.rank == "journeyman" then
      lines[#lines + 1] = { icon = BOOK_ICON, title = string.format(L["Aprender %s en el instructor de Pesca"], RANK_LABEL[step.rank]),
        sub = req, go = WP.Target("trainer", page.profKey, step.rank == "apprentice" and 75 or 150) }
    elseif step.rank == "expert" then
      local book = ES:ItemName(data.expertBook) or (L["Objeto "] .. data.expertBook)
      lines[#lines + 1] = { icon = BOOK_ICON, title = L["Libro: "] .. book,
        sub = req .. L[" · lo vende Old Man Heming (Bahía del Botín), también en la AH"], item = data.expertBook,
        go = function() return WP.Nearest({ data.bookVendor }) end }
    else
      local q = WP.Quest(data.artisanQuest)
      lines[#lines + 1] = { icon = ES.QUEST_ICON, title = L["Misión: "] .. (q and q.name or data.artisanQuestName),
        sub = req .. L[" · Nat Pagle, en el Marjal Revolcafango"], go = function() return WP.Nearest({ data.artisanNPC }) end }
    end
    -- Dónde pescar
    for _, z in ipairs(step.zones) do
      lines[#lines + 1] = { icon = MAP_ICON, title = ES.ZoneLabel(z[1], z[2]), sub = L["Pesca aquí en este tramo"] }
    end
  end
  page.lines = lines
  ES.UI.RenderLines(page, lines)
end
