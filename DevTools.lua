local _, ES = ...

---------------------------------------------------------------------------
-- Herramientas del desarrollador. ESTE ARCHIVO NO SE PUBLICA: en el .toc va dentro
-- de #@do-not-package@ (el empaquetador de CurseForge quita esas líneas) y .pkgmeta y
-- tools/package.py lo dejan fuera del zip. Los jugadores no tienen estos comandos.
--
--   /cj whatsnew            todas las novedades (como mucho 3), sin contar como vistas
--   /cj whatsnew 0.55.0     solo las de esa versión
--   /cj mem                 en qué se va la memoria del addon (estimado, por partes) y
--                           cuánto había en cada momento de la entrada
--   /cj mem clear           cuánto libera vaciar cada caché
--   /cj cpu                 empieza a cronometrar lo que corre aunque no abras la ventana
--                           (el asistente, las bolsas, el chat...); otra vez: el resultado
--   /cj cpu reset           vuelve a empezar
---------------------------------------------------------------------------

-- Bytes aproximados de un valor y lo que cuelga de él (Lua 5.1 de 64 bits: tabla 56,
-- casilla de array 16, nodo del hash 40 redondeado a potencia de 2, cadena 24 + largo).
-- `seen` comparte lo ya contado: lo que cuelga de dos sitios cuenta en el primero
local function Size(v, seen)
  local t = type(v)
  if t == "string" then
    if seen[v] then return 0 end
    seen[v] = true
    return 24 + #v
  end
  if t ~= "table" or seen[v] then return 0 end
  seen[v] = true
  local n = #v
  local hash = 0
  local bytes = 56 + n * 16
  for k, x in pairs(v) do
    if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then hash = hash + 1 end
    bytes = bytes + Size(k, seen) + Size(x, seen)
  end
  local nodes = 1
  while nodes < hash do nodes = nodes * 2 end
  return bytes + (hash > 0 and nodes * 40 or 0)
end

-- Memoria del addon ahora (KB), tras recoger la basura
local function AddonKB()
  collectgarbage("collect")
  local Update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
  local Usage = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
  if Update then Update() end
  return Usage and Usage("CraftersJournal") or 0
end

-- Cuándo crece: la memoria en cada momento de la entrada (para /cj mem)
local timeline = {}
local function Mark(label) timeline[#timeline + 1] = { label, AddonKB() } end
Mark("archivos cargados")
-- Lo que ocupan el código y sus constantes (estimado): la memoria con los archivos
-- cargados menos los datos que cuelgan de ES en ese momento. (Este archivo va casi al
-- final del .toc: lo que se carga después no cuenta, es poco)
local codeKB = math.max(0, timeline[1][2] - Size(ES, {}) / 1024)
do
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do f:RegisterEvent(e) end
  local entered
  f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "CraftersJournal" then return end
    Mark(event)
    if event == "PLAYER_ENTERING_WORLD" and not entered and C_Timer then
      entered = true
      for _, s in ipairs({ 3, 6, 10, 20, 40, 90 }) do C_Timer.After(s, function() Mark("+" .. s .. " s") end) end
    end
  end)
end

-- Cuánto libera vaciar cada caché que se puede vaciar sin romper nada (se rehace al usarla)
local function ClearReport()
  local function Freed(label, fn)
    local before = AddonKB()
    pcall(fn)
    ES:Print(string.format("  %6.2f MB  %s", (before - AddonKB()) / 1024, label))
  end
  ES:Print("Vaciando cachés (lo que libera cada una):")
  Freed("rutas de la portada (homePlanCache)", function() ES:ClearHomeCache() end)
  Freed("Ganar dinero (Earn)", function() ES.Earn:Clear() end)
  Freed("Merchant's Favor", function() ES.Favor.Clear() end)
  Freed("demanda de TSM", function() ES.Market.ClearTSM() end)
end

local function MemoryReport()
  local total = AddonKB()
  local seen, rows = {}, {}
  local function Add(name, v) rows[#rows + 1] = { name, Size(v, seen) } end
  -- Primero lo guardado (por clave), los datos y los textos (las páginas apuntan a
  -- ellos: así no se les cuentan); después las rutas calculadas de cada profesión, el
  -- resto de ES y las cachés de variables locales (ES.MemPart)
  for k, v in pairs(ES.db or {}) do Add("db." .. tostring(k), v) end
  Add("Data", ES.Data)
  Add("Locales", ES.Locales)
  local plans = {}
  for _, page in ipairs(ES.professionPages or {}) do plans[#plans + 1] = { page.plan, page.lines } end
  Add("rutas calculadas (páginas de profesión)", plans)
  Add("rutas de la portada (homePlanCache)", ES.homePlanCache)
  for k, v in pairs(ES) do
    if type(v) == "table" and k ~= "db" and k ~= "Data" and k ~= "Locales" and k ~= "MemParts" then Add("ES." .. tostring(k), v) end
  end
  for _, part in ipairs(ES.MemParts or {}) do
    local ok, v = pcall(part.get)
    if ok then Add("local: " .. part.name, v) end
  end
  rows[#rows + 1] = { "código y constantes (estimado al cargar)", codeKB * 1024 }
  table.sort(rows, function(a, b) return a[2] > b[2] end)
  local reached = 0
  for _, r in ipairs(rows) do reached = reached + r[2] end
  ES:Print(string.format("Memoria: %.1f MB en total (tras recoger la basura); %.1f MB localizados (estimado)",
    total / 1024, reached / 1048576))
  for i = 1, math.min(25, #rows) do
    if rows[i][2] < 50 * 1024 then break end
    ES:Print(string.format("  %6.2f MB  %s", rows[i][2] / 1048576, rows[i][1]))
  end
  ES:Print(string.format("  %6.2f MB  el resto (marcos de la ventana, funciones creadas al pintar...)",
    math.max(0, total / 1024 - reached / 1048576)))
  ES:Print("Al entrar (MB, tras recoger la basura):")
  local prev
  for _, m in ipairs(timeline) do
    ES:Print(string.format("  %6.2f  %s%s", m[2] / 1024, m[1],
      prev and string.format("  (%+.2f)", (m[2] - prev) / 1024) or ""))
    prev = m[2]
  end
end
ES.MemoryReport, ES.MemoryClearReport = MemoryReport, ClearReport -- (pruebas)

---------------------------------------------------------------------------
-- /cj cpu: cuánto tiempo se lleva lo que corre fuera de la ventana. Sin el perfilado
-- del juego (scriptProfile, que ralentiza todo): se cronometran con debugprofilestop
-- las funciones de abajo (las que se llamen por su tabla, ES.Assistant.Refresh...) y
-- el OnUpdate del asistente (la flecha, 20 veces por segundo). Con scriptProfile
-- activo (/console scriptProfile 1 y /reload), también el total del addon
---------------------------------------------------------------------------
local CPU_TARGETS = {
  { "Assistant", "Refresh", "asistente: releer la ruta" },
  { nil, "RefreshAfterBags", "bolsas cambiadas" },
  { nil, "RefreshAfterLearn", "receta aprendida" },
  { nil, "RouteLines", "filas de la ruta" },
  { "Earn", "Ideas", "Ganar dinero: ideas" },
  { "Planner", "Plan", "calcular una ruta" },
  { "Ledger", "OnChatLine", "chat: compras en la AH" },
  { "Market", "Index", "índice de mercado" },
}
local cpu = { stats = {}, installed = {} }

local function Count(s, t, ...)
  local d = debugprofilestop() - t
  s.n, s.ms = s.n + 1, s.ms + d
  if d > s.max then s.max = d end
  return ...
end

local function Stat(label)
  local s = cpu.installed[label]
  if not s then
    s = { label = label, n = 0, ms = 0, max = 0 }
    cpu.installed[label] = s
    cpu.stats[#cpu.stats + 1] = s
  end
  return s
end

local function InstallCPU()
  for _, t in ipairs(CPU_TARGETS) do
    local owner = t[1] and ES[t[1]] or ES
    local f = owner and owner[t[2]]
    if type(f) == "function" and not cpu.installed[t[3]] then
      local s = Stat(t[3])
      owner[t[2]] = function(...) return Count(s, debugprofilestop(), f(...)) end
    end
  end
  -- La flecha del asistente (su OnUpdate), si ya existe y no se ha cronometrado
  local frame = ES.Assistant and ES.Assistant.Frame and ES.Assistant.Frame()
  if frame and not cpu.installed["asistente: flecha (OnUpdate)"] and not (InCombatLockdown and InCombatLockdown()) then
    local h = frame:GetScript("OnUpdate")
    if h then
      local s = Stat("asistente: flecha (OnUpdate)")
      frame:SetScript("OnUpdate", function(self, elapsed) return Count(s, debugprofilestop(), h(self, elapsed)) end)
    end
  end
end

local function AddonCPU()
  if not (GetCVar and GetCVar("scriptProfile") == "1") then return nil end
  local Update = (C_AddOns and C_AddOns.UpdateAddOnCPUUsage) or UpdateAddOnCPUUsage
  local Usage = (C_AddOns and C_AddOns.GetAddOnCPUUsage) or GetAddOnCPUUsage
  if not (Update and Usage) then return nil end
  Update()
  return Usage("CraftersJournal")
end

local function ResetCPU()
  for _, s in ipairs(cpu.stats) do s.n, s.ms, s.max = 0, 0, 0 end
  cpu.started, cpu.addon0 = GetTime(), AddonCPU()
end

local function CPUReport()
  local secs = math.max(1, GetTime() - cpu.started)
  ES:Print(string.format("CPU en %d s (ms en total, ms por segundo, llamadas, la más larga):", secs))
  table.sort(cpu.stats, function(a, b) return a.ms > b.ms end)
  for _, s in ipairs(cpu.stats) do
    if s.n > 0 then
      ES:Print(string.format("  %8.1f ms  %6.2f ms/s  %6d×  máx %6.1f ms  %s", s.ms, s.ms / secs, s.n, s.max, s.label))
    end
  end
  local now = AddonCPU()
  if now and cpu.addon0 then
    ES:Print(string.format("  Todo el addon (scriptProfile): %.1f ms, %.2f ms/s", now - cpu.addon0, (now - cpu.addon0) / secs))
  else
    ES:Print("  (el total del addon: /console scriptProfile 1 y /reload; luego vuelve a desactivarlo, ralentiza)")
  end
end

-- /cj cpu: la primera vez empieza; las siguientes, el resultado. /cj cpu reset: de cero
local function CPUCommand(arg)
  if not debugprofilestop then return end
  InstallCPU()
  if not cpu.started or arg == "reset" then
    ResetCPU()
    ES:Print("Cronometrando. Juega un rato (questea, saquea...) y escribe /cj cpu para ver el resultado.")
    return
  end
  CPUReport()
end
ES.CPUCommand = CPUCommand -- (pruebas)

-- Lo llama el comando /cj (Core.lua) antes que los suyos. Devuelve true si era de aquí
function ES.DevCommand(msg)
  if msg:match("^mem%s*$") then MemoryReport() return true end
  if msg:match("^mem%s+clear%s*$") then ClearReport() return true end
  local cpuArg = msg:match("^cpu%s*(%S*)%s*$")
  if cpuArg then CPUCommand(cpuArg) return true end
  local version = msg:match("^whatsnew%s*(%S*)$")
  if not version then return false end
  local notes = {}
  for _, v in ipairs(ES.WHATS_NEW) do
    if version == "" or v.version == version then notes[#notes + 1] = v end
    if #notes >= 3 then break end
  end
  if #notes == 0 then
    ES:Print("No hay notas de la versión " .. version .. " en ES.WHATS_NEW (WhatsNew.lua).")
  else
    ES:ShowWhatsNew(notes, true)
  end
  return true
end
