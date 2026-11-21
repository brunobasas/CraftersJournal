-- Idiomas: el addon está escrito en español; cada texto se traduce por su clave
-- (el texto en español) en Locales/enUS.lua, deDE.lua y frFR.lua. Los nombres de
-- recetas y objetos de cada idioma, en Data/Names_*.lua (solo los que cambian
-- respecto al inglés: un hueco quiere decir «igual que en inglés»).

local function ReadFile(path)
  local f = assert(io.open(ADDON_DIR .. "/" .. path:gsub("\\", "/"), "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

-- Lo que no se traduce al pasar: %s, %d, %.1f..., colores |c...|r e iconos |T
local function Tokens(s)
  local t = {}
  for tok in s:gmatch("%%[-+ #0]*%d*%.?%d*[dsfxXq%%]") do t[#t + 1] = tok end
  for _ in s:gmatch("|c%x%x%x%x%x%x%x%x") do t[#t + 1] = "c" end
  for _ in s:gmatch("|r") do t[#t + 1] = "r" end
  for _ in s:gmatch("|T") do t[#t + 1] = "T" end
  return table.concat(t, " ")
end

-- Los textos que el código pide con L["..."] (literales), con dónde
local function UsedKeys()
  local used = {}
  for _, f in ipairs(TOC_FILES) do
    -- (Locale.lua no: su L["texto"] es un ejemplo en un comentario)
    if not f:match("^Libs") and not f:match("^Data") and not f:match("^Locales") and f ~= "Locale.lua" then
      local src = ReadFile(f)
      local line = 1
      local pos = 1
      for s, key, e in src:gmatch('()L%["(.-)"%]()') do
        if not key:find('\\', 1, true) then -- (las de comillas escapadas, aparte: raras)
          local _, nl = src:sub(pos, s):gsub("\n", "")
          line, pos = line + nl, s
          used[key] = used[key] or (f .. ":" .. line)
        end
      end
    end
  end
  return used
end

local function Sorted(t) table.sort(t) return t end

test("cada texto que pide el código está traducido al inglés", function()
  local used, missing, n = UsedKeys(), {}, 0
  for key, where in pairs(used) do
    n = n + 1
    if not ES.Locales.en[key] then missing[#missing + 1] = where .. ": " .. key end
  end
  note("%d textos distintos en el código", n)
  expect(n > 200, "se leyeron pocos textos (%d): ¿ha cambiado la forma de L[...]?", n)
  Sorted(missing)
  expect(#missing == 0, "%d textos sin inglés (salen en español):\n    %s", #missing, table.concat(missing, "\n    "):sub(1, 1500))
end, { boot = false })

test("alemán y francés: las mismas claves y el mismo formato que el inglés", function()
  for _, lang in ipairs({ "de", "fr" }) do
    local loc = expect(ES.Locales[lang], "falta ES.Locales.%s", lang)
    local missing, extra, bad = {}, {}, {}
    for key, en in pairs(ES.Locales.en) do
      local v = loc[key]
      if not v then missing[#missing + 1] = key
      elseif Tokens(v) ~= Tokens(en) then bad[#bad + 1] = key .. " -> " .. v end
    end
    for key in pairs(loc) do if not ES.Locales.en[key] then extra[#extra + 1] = key end end
    expect(#missing == 0, "%s: %d sin traducir: %s", lang, #missing, table.concat(Sorted(missing), " | "):sub(1, 600))
    expect(#extra == 0, "%s: %d que el inglés no tiene: %s", lang, #extra, table.concat(Sorted(extra), " | "):sub(1, 600))
    expect(#bad == 0, "%s: formato distinto del inglés: %s", lang, table.concat(Sorted(bad), " | "):sub(1, 600))
  end
end, { boot = false })

test("inglés: el mismo formato que el texto en español", function()
  local bad = {}
  for key, en in pairs(ES.Locales.en) do
    if Tokens(key) ~= Tokens(en) then bad[#bad + 1] = key .. " -> " .. en end
  end
  expect(#bad == 0, "%d traducciones con otros %%s/%%d/colores que el original:\n    %s", #bad, table.concat(Sorted(bad), "\n    "):sub(1, 1500))
end, { boot = false })

test("nombres de los datos: de recetas que existen y sin vacíos", function()
  local recipes = {}
  -- (también la fundición de Minería, Data/Mining.lua)
  for _, key in ipairs(ES:RecipeDataKeys()) do
    for id in pairs(ES.Data[key].recipes) do recipes[id] = true end
  end
  for _, lang in ipairs({ "es", "de", "fr" }) do
    local set = expect(ES.NamesFor(lang), "sin nombres en %s", lang)
    local orphan, empty, ns, ni = {}, {}, 0, 0
    for id, name in pairs(set.spells or {}) do
      ns = ns + 1
      if not recipes[id] then orphan[#orphan + 1] = tostring(id) end
      if type(name) ~= "string" or name == "" then empty[#empty + 1] = "receta " .. id end
    end
    for id, name in pairs(set.items or {}) do
      ni = ni + 1
      if type(name) ~= "string" or name == "" then empty[#empty + 1] = "objeto " .. id end
    end
    note("%s: %d recetas y %d objetos con nombre propio", lang, ns, ni)
    expect(ns > 1000 and ni > 1000, "%s: pocos nombres (%d recetas, %d objetos)", lang, ns, ni)
    expect(#empty == 0, "%s: nombres vacíos: %s", lang, table.concat(empty, ", "):sub(1, 400))
    expect(#orphan == 0, "%s: nombres de recetas que no están en los datos: %s", lang, table.concat(Sorted(orphan), ", "):sub(1, 400))
  end
end, { boot = false })

-- Huella de todos los nombres de un idioma: cuántos y un número que cambia si cambia
-- cualquier letra (sin guardar 18.000 nombres en la instantánea)
local function NamesDigest(set)
  local lines = {}
  for id, name in pairs(set.spells) do lines[#lines + 1] = "S" .. id .. "=" .. name end
  for id, name in pairs(set.items) do lines[#lines + 1] = "I" .. id .. "=" .. name end
  table.sort(lines)
  local s = table.concat(lines, "\n")
  local h = 0
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
  return { n = #lines, hash = h }
end

test("nombres de cada idioma: los mismos que antes", function()
  local out = {}
  for _, lang in ipairs({ "es", "de", "fr" }) do out[lang] = NamesDigest(ES.NamesFor(lang)) end
  snapshot("nombres", out)
  note("es %d, de %d, fr %d nombres", out.es.n, out.de.n, out.fr.n)
  expect_eq(ES.NamesFor("es").spells[12720], 'Caja goblin "Bum"', "nombre con comillas")
  expect_eq(ES.NamesFor("de").spells[12720], 'Goblin-"Bumm"-Kasten', "nombre con comillas en alemán")
end, { boot = false })

local function KB()
  collectgarbage("collect")
  collectgarbage("collect")
  return collectgarbage("count")
end

test("nombres: con el juego y el addon en inglés, los idiomas sin usar ocupan poco", function()
  GetLocale = function() return "enUS" end
  Boot({ lang = "en" })
  -- Al entrar no se ha convertido ninguno
  for _, lang in ipairs({ "es", "de", "fr" }) do
    expect(ES.NamesExpanded and not ES.NamesExpanded(lang), "%s convertido sin usarse", lang)
  end
  -- Lo que ocupan sin convertir (cadenas) frente a lo que ocupan convertidos
  local compact = 0
  for _, v in pairs(ES.Data.Names) do
    compact = compact + (type(v) == "string" and #v + 24 or math.huge)
  end
  local before = KB()
  for _, lang in ipairs({ "es", "de", "fr" }) do ES.NamesFor(lang) end
  local tables = KB() - before
  note("sin convertir %.2f MB; convertidos %.2f MB", compact / 1048576, tables / 1024)
  expect(compact <= 0.4 * tables * 1024, "sin convertir ocupan %.2f MB y convertidos %.2f MB (tope 40 %%)",
    compact / 1048576, tables / 1024)
end, { boot = false })

test("nombres: solo Core.lua lee ES.Data.Names (los demás, con ES.NamesFor)", function()
  local bad = {}
  for _, f in ipairs(TOC_FILES) do
    if f ~= "Core.lua" and not f:match("^Data") and not f:match("^Libs") and ReadFile(f):find("Data%.Names") then
      bad[#bad + 1] = f
    end
  end
  expect(#bad == 0, "leen ES.Data.Names directamente (es una cadena): %s", table.concat(bad, ", "))
end, { boot = false })

test("cambiar de idioma: se convierte el nuevo y se suelta el anterior", function()
  GetLocale = function() return "enUS" end
  Boot({ lang = "fr" })
  OpenPage("Leatherworking")
  expect(ES.NamesExpanded("fr"), "el francés, en uso, no está convertido")
  ES:SetLanguage("de")
  RunTimers()
  local de = ES.NamesFor("de").spells[2149]
  expect(de, "sin nombre en alemán para la receta 2149")
  expect_eq(ES.Data.Leatherworking.recipes[2149].name, de, "receta en alemán")
  expect(ES:GetMainFrame():IsShown(), "al cambiar de idioma la ventana se cerró")
  expect(ES.NamesExpanded("de"), "el alemán no está convertido")
  expect(not ES.NamesExpanded("fr"), "el francés sigue convertido tras dejarlo")
  expect(not ES.NamesExpanded("es"), "el español se convirtió sin usarse")
  -- Cuánto cuesta convertir un idioma (lo que tarda de más el cambio)
  local start = os.clock()
  ES.NamesFor("fr")
  local ms = (os.clock() - start) * 1000
  ES.ReleaseUnusedNames()
  expect(not ES.NamesExpanded("fr"), "no se suelta el francés")
  note("convertir el francés: %.1f ms (en el Lua de las pruebas)", ms)
  expect(ms < 200, "convertir un idioma tarda %.0f ms", ms)
end, { boot = false })

test("volver al idioma del cliente: se queda convertido y se suelta el otro", function()
  GetLocale = function() return "esES" end
  Boot({ lang = "de" })
  OpenMain()
  ES:SetLanguage("es")
  RunTimers()
  expect_eq(ES.Data.Leatherworking.recipes[2149].name, ES.NamesFor("es").spells[2149], "receta en español")
  expect(ES.NamesExpanded("es"), "el español (el del cliente) no está convertido")
  expect(not ES.NamesExpanded("de"), "el alemán sigue convertido tras dejarlo")
end, { boot = false })

test("instructor en el idioma del cliente con el addon en otro: reconoce las recetas", function()
  GetLocale = function() return "frFR" end
  Boot({ lang = "es" })
  -- Dos recetas de Sastrería que el instructor enseña por su nombre en francés (sin enlace)
  local fr = ES.NamesFor("fr").spells
  local recipes = {}
  for id, r in pairs(ES.Data.Tailoring.recipes) do
    if r.fee and fr[id] and #recipes < 2 then recipes[#recipes + 1] = { id = id, r = r } end
  end
  expect_eq(#recipes, 2, "recetas de prueba")
  local services = {}
  for i, x in ipairs(recipes) do
    services[i] = { name = fr[x.id], kind = "available", cost = 1234 + i, skill = x.r.train or 1 }
  end
  GetNumTrainerServices = function() return #services end
  GetTrainerServiceInfo = function(i) local s = services[i] return s.name, "", s.kind end
  GetTrainerServiceCost = function(i) return services[i].cost end
  GetTrainerServiceSkillReq = function(i) return "Tailoring", services[i].skill, true end
  GetTrainerServiceSkillLine = function() return ES:ProfLabel("Tailoring") end
  GetTrainerServiceItemLink = function() return nil end
  GetTrainerServiceTypeFilter = function() return true end
  SetTrainerServiceTypeFilter = function() end
  FireEvent("TRAINER_SHOW")
  RunTimers()
  local fees = ES.db.trainerFees or {}
  for _, x in ipairs(recipes) do
    expect(fees[x.id], "no reconoce «%s» (%d) por su nombre en francés", fr[x.id], x.id)
  end
  FireEvent("TRAINER_CLOSED")
  expect(ES.NamesExpanded("fr") and ES.NamesExpanded("es"), "el francés y el español deben estar convertidos")
  expect(not ES.NamesExpanded("de"), "el alemán se convirtió sin usarse")
end, { boot = false })

test("cambiar de idioma: textos, recetas y números", function()
  ES:SetLanguage("de")
  expect_eq(ES.L["Lista de compra"], "Einkaufsliste", "texto en alemán")
  expect_eq(ES.Num(2.5), "2,5", "coma decimal en alemán")
  ES:SetLanguage("en")
  expect_eq(ES.L["Lista de compra"], ES.Locales.en["Lista de compra"], "texto en inglés")
  expect_eq(ES.Data.Leatherworking.recipes[2149].name, "Handstitched Leather Boots", "receta con su nombre original")
  expect_eq(ES.Num(2.5), "2.5", "punto decimal en inglés")
  ES:SetLanguage("es")
  expect_eq(ES.L["Lista de compra"], "Lista de compra", "texto en español")
end)

-- El juego nunca libera ventanas: cada cambio de idioma dejaba otra ventana entera
-- atendiendo las bolsas, los objetos que llegan... y guardando sus rutas (PR #8)
test("cambiar de idioma: la ventana vieja deja de atender eventos y suelta sus rutas", function()
  local page = StartRoute("Tailoring", 1, 75)
  RunTimers()
  local before = FireEvent("GET_ITEM_INFO_RECEIVED", 2589, true)
  RunTimers()
  for _, l in ipairs(ES.LANGS) do
    ES:SetLanguage(l.key)
    RunTimers()
  end
  ES:SetLanguage("es")
  RunTimers()
  expect(ES:GetMainFrame():IsShown(), "la ventana se cerró")
  expect_eq(FireEvent("GET_ITEM_INFO_RECEIVED", 2589, true), before, "marcos que reciben GET_ITEM_INFO_RECEIVED")
  RunTimers()
  expect(not page:IsEventRegistered("GET_ITEM_INFO_RECEIVED"), "la página vieja de Sastrería sigue atendiendo GET_ITEM_INFO_RECEIVED")
  expect(page.plan == nil, "la página vieja sigue con su ruta")
  local new = ProfessionPage("Tailoring")
  expect(new and new ~= page, "no hay página nueva de Sastrería")
end, { state = "scan" })

-- Cambiar de idioma con cada pestaña abierta (la ventana se vuelve a crear)
for _, page in ipairs({ "home", "shopping", "money", "inventory", "invest", "favor", "calc", "patterns", "Leatherworking", "pattern:Tailoring" }) do
  test("cambiar de idioma con la página «" .. page .. "» abierta", function()
    OpenPage(page)
    for _, l in ipairs(ES.LANGS) do
      local lang = l.key
      ES:SetLanguage(lang)
      RunTimers()
      expect(ES:GetMainFrame():IsShown(), "al pasar a %s la ventana se cerró", lang)
      expect_eq(ES.db.lastPage, page, "página tras pasar a " .. lang)
    end
  end, { state = "full" })
end
