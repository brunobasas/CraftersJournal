local _, ES = ...
local L = ES.L

-- Panel del addon en Opciones > AddOns > Crafter's Journal.
-- En la copia de desarrollo (ES.DEV_BUILD) tiene el interruptor "Vista jugador",
-- para ver el addon como lo verá quien se lo baje de CurseForge (fuera de la
-- ventana del addon, así no sale en las capturas). En la versión publicada solo
-- muestra cómo abrir el addon.

local panel = CreateFrame("Frame")
panel.name = "Crafter's Journal"
ES.optionsPanel = panel

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Crafter's Journal")

local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
help:SetPoint("RIGHT", -16, 0)
help:SetJustifyH("LEFT")

if ES.DEV_BUILD then
  local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  check:SetSize(26, 26)
  check:SetPoint("TOPLEFT", help, "BOTTOMLEFT", -4, -18)
  check:SetScript("OnClick", function(self) ES:SetUserPreview(self:GetChecked() and true or false) end)
  check.label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  check.label:SetPoint("LEFT", check, "RIGHT", 2, 1)
  panel.devCheck = check
  local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, -6)
  note:SetPoint("RIGHT", -16, 0)
  note:SetJustifyH("LEFT")
  note:SetTextColor(0.75, 0.75, 0.75)
  panel.devNote = note
end

-- Textos al mostrarse (el idioma puede haber cambiado) y estado del interruptor
panel:SetScript("OnShow", function()
  help:SetText(L["Escribe /cj o pulsa el botón del minimapa para abrir el diario."])
  if panel.devCheck then
    panel.devCheck.label:SetText(L["Vista jugador: ver el addon como en CurseForge"])
    panel.devCheck:SetChecked(not ES.DEV)
    panel.devNote:SetText(L["Solo en tu copia de desarrollo. Marcado: sin Ganar dinero, Subastas, Pesca ni buscador, como en la versión publicada."])
  end
end)

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
  local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
  InterfaceOptions_AddCategory(panel)
end
