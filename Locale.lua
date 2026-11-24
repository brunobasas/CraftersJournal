local _, ES = ...

-- Idiomas del addon. El texto del código está en español y sirve de clave:
-- L["texto"] devuelve la traducción del idioma elegido, o el propio texto si
-- no hay traducción (así nada se rompe si falta alguna).
--
-- El idioma se lee de CraftersJournalDB.lang al cargar (ADDON_LOADED); hasta
-- entonces, el del cliente. Cambiarlo recarga la interfaz: las tablas que se
-- crean al cargar los archivos se traducen donde se usan (L[TABLA[k]]).

-- `client`: el código de idioma del cliente (GetLocale) que corresponde a cada uno
ES.LANGS = {
  { key = "es", name = "Español",  client = "esES" },
  { key = "en", name = "English",  client = "enUS" },
  { key = "de", name = "Deutsch",  client = "deDE" },
  { key = "fr", name = "Français", client = "frFR" },
  { key = "ru", name = "Русский",  client = "ruRU" },
}
ES.Locales = {}

local CLIENT_LANG = { esES = "es", esMX = "es", deDE = "de", frFR = "fr", ruRU = "ru" }
function ES.DefaultLanguage()
  local loc = GetLocale and GetLocale() or "esES"
  return CLIENT_LANG[loc] or "en"
end

ES.lang = ES.DefaultLanguage()

-- Un texto sin traducir en alemán o francés sale en inglés, no en español (la clave):
-- lo entiende más gente. En inglés, si falta, el español (lo que hubo siempre)
ES.L = setmetatable({}, {
  __index = function(_, key)
    local t = ES.Locales[ES.lang]
    local v = t and t[key]
    if v then return v end
    if ES.lang ~= "es" and ES.lang ~= "en" then
      local en = ES.Locales.en
      v = en and en[key]
      if v then return v end
    end
    return key
  end,
})

-- Tablas de textos que se crean al cargar los archivos (antes de saber el idioma
-- guardado): se registran aquí con su texto original (en español) y se traducen
-- en ADDON_LOADED y cada vez que se cambia de idioma.
--   ES.Localize(tabla)            traduce todos sus valores de texto
--   ES.Localize(tabla, "campo")   traduce ese campo de cada fila
local registry = {}
function ES.Localize(t, field)
  local orig = {}
  for k, v in pairs(t) do
    if field then
      if type(v) == "table" and type(v[field]) == "string" then orig[v] = v[field] end -- por fila: sobrevive a quitar filas
    elseif type(v) == "string" then
      orig[k] = v
    end
  end
  registry[#registry + 1] = { t = t, field = field, orig = orig }
  return t
end

function ES.ApplyLocalization()
  local L = ES.L
  for _, p in ipairs(registry) do
    for k, text in pairs(p.orig) do
      if p.field then k[p.field] = L[text] else p.t[k] = L[text] end
    end
  end
end

-- Elegir idioma: se aplica al momento, sin recargar la interfaz (Forever no deja
-- que un addon la recargue): textos, nombres de recetas y objetos, y la ventana
-- se vuelve a crear con el idioma nuevo.
function ES:SetLanguage(lang)
  if lang == self.lang then return end
  self.lang = lang
  self.db.lang = lang
  ES.ApplyLocalization()
  self:LocalizeRecipeNames()
  if self.ReleaseUnusedNames then self.ReleaseUnusedNames() end -- (el idioma anterior, si ya no se usa)
  if self.ClearHomeCache then self:ClearHomeCache() end
  if self.RebuildMainFrame then self:RebuildMainFrame() end
end
