local _, ES = ...
local L = ES.L

-- Lo que el addon lee del juego al comprar, vender y entrenar (sin apuntar dinero:
-- el gasto real de la ruta se quitó porque se apuntaba mal con varias rutas):
--   AH: lo comprado cuenta ya, de camino al buzón (Ledger.OnWay, se borra solo)
--   instructor: el precio real de cada receta (Ledger:ReadTrainer, Planner.Fee)
--   vendedor: qué vende y a cuánto (la ventana de compra de VendorUI.lua)
-- Vender al vendedor y anunciar en la AH desde la vista Profit: siempre con un
-- clic del jugador que dice exactamente qué va a hacer. El addon no compra ni
-- vende nada sin ese clic.

local Ledger = {}
ES.Ledger = Ledger

-- Diario de lo que lee (para diagnosticar en el juego): ES.db.ledgerLog
local function Log(text)
  ES.db.ledgerLog = ES.db.ledgerLog or {}
  local log = ES.db.ledgerLog
  log[#log + 1] = (date and date("%H:%M:%S ") or "") .. text
  while #log > 60 do table.remove(log, 1) end
end
Ledger.Log = Log

-- Funciones de las bolsas: C_Container (cliente moderno) o las de siempre. Se buscan
-- al usarlas, no al cargar (así también valen las de las pruebas)
local function CC(name) return (C_Container and C_Container[name]) or _G[name] end
local function NumSlots(bag) local f = CC("GetContainerNumSlots") return f and f(bag) or 0 end
local function ContainerItemID(bag, slot) local f = CC("GetContainerItemID") return f and f(bag, slot) end
local function UseItem(bag, slot) local f = CC("UseContainerItem") if f then f(bag, slot) end end

-- Una casilla libre en una bolsa normal (no de hierbas, de encantamiento...): bag, slot.
-- Si están llenas, la de componentes (solo admite materiales: si no lo acepta, el
-- objeto se queda en el cursor y quien lo deja allí lo devuelve)
local function EmptySlot()
  local free = CC("GetContainerNumFreeSlots")
  for bag = 0, NUM_BAG_SLOTS or 4 do
    local n, family = 1, 0
    if free then n, family = free(bag) end
    if (n or 0) > 0 and (family or 0) == 0 then
      for slot = 1, NumSlots(bag) do
        if not ContainerItemID(bag, slot) then return bag, slot end
      end
    end
  end
  local reagent = ES.ReagentBag()
  if reagent then
    for slot = 1, NumSlots(reagent) do
      if not ContainerItemID(reagent, slot) then return reagent, slot end
    end
  end
end
Ledger.EmptySlot = EmptySlot -- (pruebas)

-- Unidades de un objeto en una casilla de las bolsas
local function SlotCount(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0
  end
  local _, count = GetContainerItemInfo(bag, slot)
  return count or 0
end

-- Casillas de las bolsas (no el banco; sí la de componentes) con este objeto: { {bag, slot, count} }
local function Slots(itemID)
  local list = {}
  for _, bag in ipairs(ES.CarriedBags()) do
    for slot = 1, NumSlots(bag) or 0 do
      if ContainerItemID(bag, slot) == itemID then
        list[#list + 1] = { bag = bag, slot = slot, count = SlotCount(bag, slot) }
      end
    end
  end
  return list
end

local function BagCount(itemID)
  local n = 0
  for _, s in ipairs(Slots(itemID)) do n = n + s.count end
  return n
end
Ledger.BagCount = BagCount

-- Profesión del instructor abierto (por la línea de habilidad de lo que enseña), o nil
local PROF_SPELLS = { Alchemy = 2259, Blacksmithing = 2018, Enchanting = 7411, Engineering = 4036,
  Leatherworking = 2108, Tailoring = 3908, Cooking = 2550, FirstAid = 3273 }
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return GetSpellInfo and (GetSpellInfo(id))
end
local function TrainerProfession()
  if not (GetNumTrainerServices and GetTrainerServiceSkillLine) then return nil end
  for i = 1, GetNumTrainerServices() or 0 do
    local line = GetTrainerServiceSkillLine(i)
    if line and line ~= "" then
      for key, spell in pairs(PROF_SPELLS) do
        if line == SpellName(spell) or line == ES:ProfLabel(key) then return key end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Precios reales del instructor: al abrirlo se lee lo que cobra y el nivel que pide
-- por cada receta y se guarda en CraftersJournalDB.trainerFees[spellID] =
-- { cost, skill, rep, time }. Forever ha cambiado precios y tiene recetas nuevas
-- sin precio conocido: lo visto en el juego manda sobre los datos (Planner.Fee)
---------------------------------------------------------------------------
-- Descuento del instructor por reputación (UnitReaction: 5 amistoso ... 8 exaltado)
local REP_DISCOUNT = { [5] = 0.05, [6] = 0.10, [7] = 0.15, [8] = 0.20 }

-- Precio sin el descuento de reputación (el que vale para todos)
local function BaseCost(seen)
  local d = REP_DISCOUNT[seen.rep or 0]
  return d and math.floor(seen.cost / (1 - d) + 0.5) or seen.cost
end
Ledger.BaseCost = BaseCost

-- Receta de la casilla `i` del instructor: por enlace (hechizo/encantamiento u objeto
-- fabricado) o por nombre (el del juego, en su idioma). `exact`: el instructor no es de
-- una profesión del addon (minería...): solo por el hechizo. Por el objeto, "Smelt
-- Gold" (Minería 155, Gold Bar) se tomaba por Transmute: Iron to Gold y la ruta la
-- aprendía a 155 (Discord: pide 225)
local function ServiceRecipe(i, profs, exact)
  local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
  local spell = link and tonumber(link:match("spell:(%d+)") or link:match("enchant:(%d+)"))
  local item = link and tonumber(link:match("item:(%d+)"))
  local name = GetTrainerServiceInfo and (GetTrainerServiceInfo(i))
  -- (el instructor habla el idioma del cliente, no el del addon)
  local set = ES.NamesFor(ES.DefaultLanguage())
  local names = set and set.spells or {}
  local byName = {}
  for _, key in ipairs(profs) do
    for id, r in pairs(ES.Data[key].recipes) do
      if spell == id then return id, r, key end
      if exact then -- (solo el hechizo: ver arriba)
      elseif item and r.out and r.out[1] == item then return id, r, key
      elseif name and (name == r.name or name == r.nameEN or name == names[id] or name == SpellName(id)) then
        byName[#byName + 1] = { id, r, key }
      end
    end
  end
  if #byName == 1 then return unpack(byName[1]) end -- con dos del mismo nombre no se adivina
end

-- La lista del instructor sigue sus filtros (disponibles / no disponibles / ya
-- sabidas): al abrirlo se muestran todos un momento para leer todas sus recetas y
-- se dejan como estaban. Solo al abrirlo (TRAINER_SHOW): cambiar un filtro lanza
-- TRAINER_UPDATE, que lee sin tocarlos (así no se repite sin fin)
local FILTERS = { "available", "unavailable", "used" }
-- Una vez: fuera lo leído de un instructor con un nivel menor que el de los datos del
-- juego. Son lecturas equivocadas de antes de ServiceRecipe(exact): un instructor de
-- minería apuntaba Smelt Gold (155, su precio) como Transmute: Iron to Gold. Se
-- vuelven a leer bien la próxima vez que abras el instructor de la profesión
function Ledger:CleanTrainerFees()
  local db = ES.db
  if not db or db.trainerFeesChecked or type(db.trainerFees) ~= "table" then
    if db then db.trainerFeesChecked = true end
    return 0
  end
  db.trainerFeesChecked = true
  local removed = 0
  for id, seen in pairs(db.trainerFees) do
    for _, p in ipairs(ES.PROFESSIONS or {}) do
      local r = ES.Data[p.key] and ES.Data[p.key].recipes and ES.Data[p.key].recipes[id]
      if r then
        if type(seen) == "table" and seen.skill and r.train and seen.skill < r.train then
          db.trainerFees[id] = nil
          removed = removed + 1
        end
        break
      end
    end
  end
  return removed
end

-- Forever (cliente moderno) pide true/false ("Missing on/off parameter" con 1/0: no
-- se leía nunca la lista entera); el clásico, 1/0
local function SetFilter(f, on)
  if not pcall(SetTrainerServiceTypeFilter, f, on) then SetTrainerServiceTypeFilter(f, on and 1 or 0) end
end

function Ledger:ReadAllTrainerServices()
  if not (GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter) then return self:ReadTrainer() end
  local hidden = {}
  for _, f in ipairs(FILTERS) do
    local shown = GetTrainerServiceTypeFilter(f)
    if not shown or shown == 0 then
      hidden[#hidden + 1] = f
      SetFilter(f, true)
    end
  end
  self.fullList = true -- (la lista entera: lo que no sale, este instructor no lo enseña)
  local ok, changed = pcall(self.ReadTrainer, self)
  self.fullList = nil
  for _, f in ipairs(hidden) do SetFilter(f, false) end
  if not ok then error(changed, 0) end
  return changed
end

function Ledger:ReadTrainer()
  if not (ES.db and GetNumTrainerServices and GetTrainerServiceCost) then return 0 end
  local prof = TrainerProfession()
  local profs = {}
  if prof then
    profs[1] = ES.Data[prof] and ES.Data[prof].recipes and prof or nil
  else
    for _, p in ipairs(ES.PROFESSIONS or {}) do
      if ES.Data[p.key] and ES.Data[p.key].recipes then profs[#profs + 1] = p.key end
    end
  end
  if #profs == 0 then return 0 end
  ES.db.trainerFees = ES.db.trainerFees or {}
  local rep = UnitReaction and UnitReaction("npc", "player") or nil
  local changed = 0
  local changedProfs = {}
  local listed, top, low = {}, 0, math.huge
  local guid = UnitGUID and UnitGUID("npc")
  local npc = guid and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
  for i = 1, GetNumTrainerServices() or 0 do
    local kind = GetTrainerServiceInfo and select(3, GetTrainerServiceInfo(i))
    if kind ~= "header" then
      local id, r, key = ServiceRecipe(i, profs, prof == nil) -- (sin profesión conocida: solo por el hechizo)
      local cost = id and GetTrainerServiceCost(i)
      if cost then
        local skill = GetTrainerServiceSkillReq and select(2, GetTrainerServiceSkillReq(i))
        local old = ES.db.trainerFees[id]
        if not old or old.cost ~= cost or old.skill ~= skill or old.rep ~= rep then
          changed = changed + 1
          changedProfs[key] = true
        end
        -- (npc: el instructor donde se vio, para llevarte a él: Forever enseña algunas
        -- solo en sitios concretos, como Stranglethorn)
        ES.db.trainerFees[id] = { cost = cost, skill = skill, rep = rep, prof = key, time = time(), npc = npc or (old and old.npc) }
        listed[id] = true
        -- Receta que el instructor solo enseña tras una misión (Discolored): si te la
        -- lista, ya la tienes desbloqueada. Por personaje (lo guardado es de la cuenta)
        local char = r and r.unlock and ES:CharKey()
        if char then
          if type(ES.db.unlockSeen) ~= "table" then ES.db.unlockSeen = {} end
          local mine = ES.db.unlockSeen[char]
          if type(mine) ~= "table" then mine = {} end
          ES.db.unlockSeen[char] = mine
          if not mine[id] then
            mine[id] = true
            changed = changed + 1
            changedProfs[key] = true
          end
        end
        if skill and skill > 0 then
          top = math.max(top, skill)
          low = math.min(low, skill)
        end
      end
    end
  end
  -- Recetas de instructor de los datos que no enseña ningún instructor visto (con su
  -- lista entera a la vista): Forever ha quitado o movido algunas (Green Iron
  -- Leggings) y la ruta pedía aprender algo que tu instructor no tiene. Solo dentro
  -- del tramo de niveles que enseña cada instructor visto (en Forever cada rango
  -- tiene los suyos: uno de Experto no dice nada de las de Oficial). Si otro
  -- instructor la enseña (en Stranglethorn, por ejemplo), vuelve
  if self.fullList and prof and top > 0 then
    local seen = ES.db.trainerListed or {}
    ES.db.trainerListed = seen
    seen[prof] = seen[prof] or { ranges = {}, ids = {} }
    local s = seen[prof]
    s.ranges = s.ranges or {}
    local key = low .. "-" .. top
    s.ranges[key] = { low, top }
    for id in pairs(listed) do s.ids[id] = true end
    -- "rank": el instructor de su rango no la tiene; Forever ha subido algunas al
    -- rango siguiente (Green Iron Leggings, de 130, la enseña el de Experto: Bengus
    -- Deepforge), así que la fila Entrenar lleva a ese. "gone": tampoco está en un
    -- instructor de más nivel que hayas visto: no se enseña, fuera de las rutas
    local function Covered(level)
      for _, rg in pairs(s.ranges) do
        if level >= rg[1] and level <= rg[2] then return true end
      end
      return false
    end
    local function Above(level)
      for _, rg in pairs(s.ranges) do
        if rg[1] > level then return true end
      end
      return false
    end
    ES.db.trainerMissing = ES.db.trainerMissing or {}
    local missing = ES.db.trainerMissing
    for id, r in pairs(ES.Data[prof].recipes) do
      -- (las que piden una misión, no: solo las enseñan unos PNJ concretos y antes de la
      -- misión ni ellos las listan; que no salgan no dice que Forever las quitara)
      local trainerRecipe = (r.fee or r.trainer) and not r.scroll and not r.basic and not r.favor and not r.unlock
      local level = r.train or 0
      local now = trainerRecipe and not s.ids[id] and Covered(level) and (Above(level) and "gone" or "rank") or nil
      if missing[id] ~= now then
        missing[id] = now
        changed = changed + 1
        changedProfs[prof] = true
      end
    end
    -- Tu ruta empezada pasa por una de ellas (aún no la has hecho): ya no se puede
    -- seguir; se suelta y se calcula otra desde tu nivel
    local lock = ES.RouteLock and ES:RouteLock(prof)
    if lock and lock.choice then
      local skill = ES:GetProfessionSkill(ES.Data[prof].skillLine) or lock.from
      for s, id in pairs(lock.choice) do
        if s >= skill and missing[id] == "gone" and not (ES.IsRecipeKnown and ES:IsRecipeKnown(id)) then
          ES:StopRoute(prof)
          ES:Print(string.format(L["Tu ruta de %s usaba %s, que este instructor no enseña: se calcula otra desde tu nivel."],
            ES:ProfLabel(prof), ES.Data[prof].recipes[id].name))
          changedProfs[prof] = true
          changed = changed + 1
          break
        end
      end
    end
  end
  if changed > 0 then
    Log(string.format("instructor%s: %d precios nuevos o cambiados", prof and (" de " .. prof) or "", changed))
    -- Las rutas de esas profesiones se rehacen con el precio real, también la fijada:
    -- el precio del instructor es un dato, no un precio de mercado (sus recetas no
    -- cambian, solo lo que cuesta aprenderlas)
    for key in pairs(changedProfs) do
      if ES.InvalidatePlan then ES:InvalidatePlan(key) end
      -- (y la guardada de otra sesión: va en su clave, ES:StableRouteKey)
      ES.db.trainerStamp = ES.db.trainerStamp or {}
      ES.db.trainerStamp[key] = (ES.db.trainerStamp[key] or 0) + 1
      if ES.lockedPlans then ES.lockedPlans[key] = nil end
      -- La ruta fijada, rehecha con lo que enseña de verdad el instructor, ya no sale
      -- (una receta suya a un nivel o rango que no toca): se suelta y se calcula otra
      -- desde tu nivel, en vez de quedarse vacía (el asistente se quedaba sin pasos)
      local lock = ES.RouteLock and ES:RouteLock(key)
      if lock and not lock.completed and ES.LockedPlan then
        local okPlan, plan = pcall(ES.LockedPlan, ES, key)
        if okPlan and plan and #plan.steps == 0 then
          ES:StopRoute(key)
          ES:Print(string.format(L["Tu ruta de %s ya no se puede seguir con lo que enseña este instructor: se calcula otra desde tu nivel."],
            ES:ProfLabel(key)))
        end
      end
    end
    if ES.RefreshProfessionPages then ES:RefreshProfessionPages() end
  end
  return changed
end

---------------------------------------------------------------------------
-- Aprender en el instructor abierto, desde la ruta (clic en el paso del asistente o
-- su fila): lo que toca y lo de "aprende también". Solo con tu clic y solo lo que está
-- disponible (tu nivel ya llega). targets = { { recipeID = id } | { rank = cap } }
---------------------------------------------------------------------------
local RANK_WORDS = { [150] = { "Journeyman" }, [225] = { "Expert" }, [300] = { "Artisan" }, [375] = { "Master" } }

function Ledger.TrainerOpen()
  return Ledger.trainerOpen and GetNumTrainerServices and (GetNumTrainerServices() or 0) > 0 or false
end

-- Índice del servicio del instructor abierto para `target`, o nil. No se exige que el
-- juego lo marque "available" (en Forever no lo encontraba: captura del 2026-11-17,
-- Elixir of Wisdom disponible y "no lo enseña"): solo se descarta lo ya aprendido, lo
-- que aún no te llega y las cabeceras. Sin saber de qué profesión es el instructor,
-- se busca en todas (como al leer sus precios)
local SKIP_KINDS = { header = true, used = true, unavailable = true }

-- La profesión misma ("Apprentice Tailoring"): por su hechizo (el del enlace) o por el
-- nombre (Apprentice, o el nombre de la profesión en el idioma del cliente). Devuelve
-- el índice y su tipo (unavailable: ya tienes dos profesiones principales)
function Ledger.ProfessionService(profKey)
  if not Ledger.TrainerOpen() then return nil end
  local spell = PROF_SPELLS[profKey]
  local profName = spell and SpellName(spell)
  for i = 1, GetNumTrainerServices() or 0 do
    local name, _, kind = GetTrainerServiceInfo(i)
    if kind ~= "header" and kind ~= "used" and name then
      local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
      local id = link and tonumber(link:match("spell:(%d+)"))
      if (spell and id == spell) or name:find("Apprentice", 1, true)
        or (profName and profName ~= "" and name:find(profName, 1, true)) then
        return i, kind
      end
    end
  end
end

function Ledger.TrainerService(target, rankName)
  if not Ledger.TrainerOpen() then return nil end
  if target.profession then
    local i, kind = Ledger.ProfessionService(target.profession)
    if i and not SKIP_KINDS[kind] then return i end
    return nil
  end
  local prof = TrainerProfession()
  local profs = {}
  if prof and ES.Data[prof] and ES.Data[prof].recipes then
    profs[1] = prof
  else
    for _, p in ipairs(ES.PROFESSIONS or {}) do
      if ES.Data[p.key] and ES.Data[p.key].recipes then profs[#profs + 1] = p.key end
    end
  end
  for i = 1, GetNumTrainerServices() or 0 do
    local name, _, kind = GetTrainerServiceInfo(i)
    if not SKIP_KINDS[kind] then
      if target.recipeID then
        if #profs > 0 and ServiceRecipe(i, profs, false) == target.recipeID then return i end
      elseif target.rank and name then
        local words = { rankName }
        for _, w in ipairs(RANK_WORDS[target.rank] or {}) do words[#words + 1] = w end
        for _, w in ipairs(words) do
          if w and w ~= "" and name:find(w, 1, true) then return i end
        end
      end
    end
  end
end

-- Aprende en el instructor abierto lo que haya de `targets`, de uno en uno (el
-- servidor ignora las compras muy seguidas). Devuelve cuántos encontró
function Ledger.LearnAtTrainer(targets)
  local queue = {}
  for _, t in ipairs(targets) do
    if Ledger.TrainerService(t, t.rankName) then queue[#queue + 1] = t end
  end
  if #queue == 0 then
    -- La profesión está en la lista pero no se puede aprender: ya tienes dos principales
    for _, t in ipairs(targets) do
      local i, kind
      if t.profession then i, kind = Ledger.ProfessionService(t.profession) end
      if i and kind == "unavailable" then
        ES:Print(string.format(L["No puedes aprender %s: ya tienes dos profesiones principales. Olvida una primero (desde su ventana de profesión)."],
          ES:ProfLabel(t.profession)))
        return 0
      end
    end
    ES:Print(L["Este instructor no lo enseña (o aún no te llega el nivel)."])
    -- (para diagnosticar en el juego: lo que buscaba y lo que el instructor ofrece)
    local want = {}
    for _, t in ipairs(targets) do want[#want + 1] = tostring(t.recipeID or ("rango " .. tostring(t.rank))) end
    Log("instructor: no encuentra " .. table.concat(want, ", ") .. " · profesión " .. tostring(TrainerProfession()))
    for i = 1, math.min(GetNumTrainerServices and GetNumTrainerServices() or 0, 40) do
      local name, sub, kind = GetTrainerServiceInfo(i)
      Log(string.format("  %d %s | %s | %s | %s", i, tostring(name), tostring(sub), tostring(kind),
        tostring(GetTrainerServiceItemLink and GetTrainerServiceItemLink(i))))
    end
    return 0
  end
  local function Next(k)
    local t = queue[k]
    if not t or not Ledger.TrainerOpen() then return end
    local i = Ledger.TrainerService(t, t.rankName) -- (los índices cambian al aprender)
    if i and BuyTrainerService then BuyTrainerService(i) end
    if queue[k + 1] and C_Timer then C_Timer.After(0.4, function() Next(k + 1) end) end
  end
  Next(1)
  return #queue
end

---------------------------------------------------------------------------
-- Vendedor abierto: qué vende y a cuánto (VendorUI.lua)
---------------------------------------------------------------------------
-- Objeto de la casilla `i` del vendedor abierto
local function MerchantItemID(i)
  local id = GetMerchantItemID and GetMerchantItemID(i)
  if not id and GetMerchantItemLink then
    local link = GetMerchantItemLink(i)
    id = link and tonumber(link:match("item:(%d+)"))
  end
  return id
end
Ledger.MerchantItemID = MerchantItemID

-- Precio, cuántos vienen por compra, cuántos quedan (-1 sin límite), si se compra con
-- oro. Forever (cliente moderno) usa C_MerchantFrame.GetItemInfo; el clásico, GetMerchantItemInfo
local function MerchantInfo(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = C_MerchantFrame.GetItemInfo(i)
    if info then
      return info.price, info.stackCount, info.numAvailable, info.isPurchasable ~= false and not info.hasExtendedCost
    end
  elseif GetMerchantItemInfo then
    local _, _, price, stack, avail, purchasable, _, ext = GetMerchantItemInfo(i)
    return price, stack, avail, purchasable ~= false and not ext
  end
end
Ledger.MerchantInfo = MerchantInfo

---------------------------------------------------------------------------
-- Lo que paga el vendedor: el precio que da el juego (o el de los datos), y nada
-- más. Antes se "aprendía" de tus ventas (el dinero que entraba tras vender), pero
-- el dinero entra por muchas cosas a la vez: dos ventas cobradas juntas dejaron
-- Barbaric Leggings a 63s 02c en vez de 31s 51c y Ganar dinero prometía el doble
-- (CurseForge). Con los datos del cliente de lanzamiento ya no hacía falta (de 120
-- objetos vendidos, todos coincidían): se quitó, y lo aprendido se borra al entrar
-- (Core.lua: ES.db.sellSeen)
---------------------------------------------------------------------------

-- ¿Se puede leer este texto? Un texto normal sí; uno "secreto" (mazmorras, combate:
-- issecretvalue) no se puede ni indexar ni comparar sin un error de taint
function Ledger.Readable(s)
  if type(s) ~= "string" then return false end
  if issecretvalue and issecretvalue(s) then return false end
  return true
end

-- ¿Hay que mirar el chat y los errores? Solo con la AH abierta, y unos segundos tras
-- cerrarla (el mensaje de la compra puede llegar justo después). Fuera de la AH
-- (mazmorras, combate...) el addon no lee nada del chat
local CHAT_GRACE = 30
local function Clock() return GetTime and GetTime() or time() end
function Ledger.Listening()
  if ES.IsAuctionHouseOpen and ES:IsAuctionHouseOpen() then return true end
  return Ledger.ahClosedAt ~= nil and Clock() - Ledger.ahClosedAt < CHAT_GRACE
end

do
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "PLAYER_ENTERING_WORLD",
    "MERCHANT_SHOW", "MERCHANT_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_POST_WARNING",
    "CHAT_MSG_SYSTEM", "UI_ERROR_MESSAGE",
    "PLAYER_MONEY", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "BAG_UPDATE_DELAYED" }) do
    ES.SafeRegister(f, e)
  end
  f:SetScript("OnEvent", function(_, event, ...)
    if not ES.db then return end
    -- Cambian las bolsas: lo comprado que ya llegó deja de contar como de camino,
    -- aunque no se vea ninguna ventana (Ledger.SweepOnWay)
    if event == "BAG_UPDATE_DELAYED" then
      Ledger.SweepOnWay()
      return
    end
    if event == "AUCTION_HOUSE_CLOSED" then
      Ledger.ahClosedAt = Clock()
      -- (la pregunta de confirmar se cierra con la AH: no se anuncia)
      if Ledger.pendingPost then Ledger:CancelAsked(Ledger.pendingPost) end
    end
    if event == "AUCTION_HOUSE_SHOW" then Ledger.ahClosedAt = nil end
    -- La AH pide confirmar un anuncio: si es el del addon (lo dice lo que devolvió
    -- PostItem: AskPost), fuera la ventana del juego, que no sabe confirmarlo y se
    -- vería con la del addon. En el fotograma siguiente: el juego la saca con este mismo
    -- evento. La de un anuncio desde la pantalla del juego no se toca
    if event == "AUCTION_HOUSE_POST_WARNING" then
      C_Timer.After(0, function()
        local p = Ledger.pendingPost
        if p and p.asking and StaticPopup_Visible and StaticPopup_Visible("AUCTION_HOUSE_POST_WARNING") then
          StaticPopup_Hide("AUCTION_HOUSE_POST_WARNING")
        end
      end)
      return
    end
    -- El chat y los errores solo importan en la AH (ver Ledger.Listening). Además, en
    -- mazmorras/combate el juego da los textos como "secretos": ni compararlos ni
    -- leerlos (error de taint)
    if event == "CHAT_MSG_SYSTEM" or event == "UI_ERROR_MESSAGE" then
      if not Ledger.Listening() then return end
      local message = event == "CHAT_MSG_SYSTEM" and (...) or select(2, ...)
      if not Ledger.Readable(message) then return end
    end
    -- Respuesta de la AH al anuncio pendiente (ver PostOnAH): creada, o un error en rojo
    if Ledger.pendingPost then
      if event == "AUCTION_HOUSE_AUCTION_CREATED" then
        Ledger:ConfirmPost(true)
        return
      elseif event == "CHAT_MSG_SYSTEM" and ERR_AUCTION_STARTED and (...) == ERR_AUCTION_STARTED then
        Ledger:ConfirmPost(true) -- ("Subasta creada.": por si el cliente no tiene el evento)
        return
      elseif event == "UI_ERROR_MESSAGE" then
        -- Solo un error de la AH (o sin dinero para el depósito) rechaza el anuncio:
        -- un "Out of range" o "Not enough mana" a la vez no tiene que ver con él
        local _, message = ...
        if Ledger.IsAuctionError(message) then
          Ledger:ConfirmPost(false, message)
          return
        end
      end
    end
    -- Compra ganada en la AH: cuenta ya, aunque esté en el correo (Ledger.OnWay). Por
    -- varias vías (la que funcione en cada cliente y con cada addon de la AH); la misma
    -- compra solo cuenta una vez (AddOnWay)
    if event == "CHAT_MSG_SYSTEM" then
      Ledger.OnChatLine((...), "sistema")
      return
    end
    -- Compra al precio de compra inmediata (AH clásica, PlaceAuctionBid): te cobran
    if event == "PLAYER_MONEY" then
      Ledger.ConfirmBid()
      return
    end
    -- AH moderna: compra de materiales confirmada
    if event == "COMMODITY_PURCHASE_SUCCEEDED" or event == "COMMODITY_PURCHASE_FAILED" then
      local p = Ledger.pendingCommodity
      Ledger.pendingCommodity = nil
      if p and event == "COMMODITY_PURCHASE_SUCCEEDED" and Ledger.AddOnWay(p.itemID, p.n, "AH moderna") then
        Ledger.RefreshOnWay()
      end
      return
    end
    if event == "UI_ERROR_MESSAGE" and Ledger.pendingBid and Ledger.IsAuctionError(select(2, ...)) then
      Ledger.pendingBid = nil -- (la compra no se hizo)
    end
    if event == "AUCTION_HOUSE_AUCTION_CREATED" or event == "UI_ERROR_MESSAGE" then return end
    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
      -- Se pulsó con la AH ocupada: avisa de que ya se puede (anunciar necesita un clic)
      local b = Ledger.ahBusy
      Ledger.ahBusy = nil
      if b and b.waiting and ES:IsAuctionHouseOpen() then
        ES:Print(L["La Casa de Subastas ya está lista: vuelve a pulsar."])
      end
      return
    end
    if event == "AUCTION_HOUSE_CLOSED" then Ledger.ahBusy = nil end
    if event == "MERCHANT_SHOW" or event == "MERCHANT_CLOSED" or event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_HOUSE_CLOSED" then
      -- La vista Profit cambia sus clics (vender al vendedor, anunciar en la AH)
      if ES.RefreshAfterBags then ES:RefreshAfterBags() end
    elseif event == "TRAINER_CLOSED" then
      Ledger.trainerOpen = nil
      if ES.Assistant and ES.Assistant.Refresh then ES.Assistant.Refresh() end -- (el clic vuelve a llevarte)
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
      Ledger.trainerOpen = true
      local ok, err = pcall(event == "TRAINER_SHOW" and Ledger.ReadAllTrainerServices or Ledger.ReadTrainer, Ledger)
      if not ok then Log("instructor: error leyendo precios: " .. tostring(err)) end
      -- (el paso de entrenar del asistente pasa a aprender con un clic)
      if ES.Assistant and ES.Assistant.Refresh then ES.Assistant.Refresh() end
    elseif event == "PLAYER_ENTERING_WORLD" then
      -- Compras de la AH "en el correo" de versiones anteriores: ya no se cuentan
      ES.db.mailBought, ES.db.ahOnWay = nil, nil
    end
  end)
end

---------------------------------------------------------------------------
-- Vender y anunciar (vista Profit): siempre desde un clic del jugador
---------------------------------------------------------------------------
function Ledger:MerchantOpen()
  return MerchantFrame and MerchantFrame:IsShown() and true or false
end

-- Cola de ventas: una casilla cada SELL_GAP. Todas en el mismo instante (17 Linen Belt,
-- que no se apilan: 17 ventas de golpe) el servidor se saltaba unas cuantas y había que
-- pulsar Vender todo varias veces (Discord). Antes de cada una se mira que el vendedor
-- siga abierto y la casilla tenga aún ese objeto; si está bloqueada (la venta anterior
-- aún no ha terminado), se espera
local SELL_GAP = 0.15
local SELL_MAX_WAIT = 10 -- veces que se espera a una casilla bloqueada antes de dejarla
Ledger.sellQueue = {}

local function SlotLocked(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.isLocked
  end
  if GetContainerItemInfo then return select(3, GetContainerItemInfo(bag, slot)) and true or false end
end

local function PumpSells()
  local q = Ledger.sellQueue
  local s = q[1]
  if not s or not Ledger:MerchantOpen() then
    Ledger.sellQueue, Ledger.selling = {}, nil
    return
  end
  if ContainerItemID(s.bag, s.slot) ~= s.itemID then
    table.remove(q, 1) -- (ya no está: vendido, movido o usado)
  elseif SlotLocked(s.bag, s.slot) and (s.waits or 0) < SELL_MAX_WAIT then
    s.waits = (s.waits or 0) + 1
  else
    UseItem(s.bag, s.slot)
    table.remove(q, 1)
  end
  if q[1] then C_Timer.After(SELL_GAP, PumpSells) else Ledger.selling = nil end
end

local function QueueSell(bag, slot, itemID)
  local q = Ledger.sellQueue
  for _, s in ipairs(q) do if s.bag == bag and s.slot == slot then return end end
  q[#q + 1] = { bag = bag, slot = slot, itemID = itemID }
  if not Ledger.selling then
    Ledger.selling = true
    PumpSells()
  end
end
Ledger.QueueSell = QueueSell -- (pruebas)

-- Vende hasta `n` unidades al vendedor abierto, pilas enteras que quepan en `n`
-- (en cola: ver arriba). Devuelve cuántas va a vender.
function Ledger:SellToVendor(itemID, n)
  if not self:MerchantOpen() or not CC("UseContainerItem") or n <= 0 then return 0 end
  local sold = 0
  local slots = Slots(itemID)
  for _, s in ipairs(slots) do
    if sold + s.count <= n then
      QueueSell(s.bag, s.slot, itemID)
      sold = sold + s.count
      s.used = true
    end
  end
  -- Lo que queda está en una pila más grande (17 y hay que vender 12): se parte. Las
  -- 12 van a una casilla libre y se vende esa pila; las otras 5 se quedan
  local left = n - sold
  if left > 0 then
    local from
    for _, s in ipairs(slots) do if not s.used and s.count > left then from = s break end end
    local bag, slot = EmptySlot()
    local split, pickup = CC("SplitContainerItem"), CC("PickupContainerItem")
    if from and bag and split and pickup and not (CursorHasItem and CursorHasItem()) then
      split(from.bag, from.slot, left)
      pickup(bag, slot)
      if CursorHasItem and CursorHasItem() then
        -- (la bolsa de componentes no lo admite: vuelve a su pila)
        ClearCursor()
        ES:Print(string.format(L["Vendidos %d de %d: para vender el resto hace falta un hueco libre en la bolsa (se parte la pila)."], sold, n))
        return sold
      end
      -- (el juego tarda un momento en dejar la pila nueva en su casilla)
      C_Timer.After(0.5, function()
        if self:MerchantOpen() and ContainerItemID(bag, slot) == itemID then QueueSell(bag, slot, itemID) end
      end)
      sold = n
    elseif from and not bag then
      ES:Print(string.format(L["Vendidos %d de %d: para vender el resto hace falta un hueco libre en la bolsa (se parte la pila)."], sold, n))
    else
      ES:Print(string.format(L["Vendidos %d de %d: el resto está en pilas más grandes de lo que hay que vender."], sold, n))
    end
  end
  return sold
end

-- Precio de anuncio en la AH de Forever: solo admite platas enteras (redondeo hacia abajo)
function Ledger.PostPrice(unit)
  unit = math.floor(unit or 0)
  return math.max(unit - unit % 100, 100)
end

---------------------------------------------------------------------------
-- Lo que tienes para la lista de compra y las filas de compra del asistente: lo que
-- llevas en las bolsas y lo comprado en la AH que viene por correo ("de camino"). Sin
-- eso, tras comprar había que ir al buzón antes de que contara (con varios materiales,
-- un viaje por compra).
-- La versión anterior (ES.db.ahOnWay) se apuntaba al comprar y se descontaba al
-- recogerlo; si se perdía un descuento se quedaba pegado (Discord: "48 en el correo"
-- sin nada en el buzón). Esta no depende de un descuento, se borra sola:
--   · lo que llega a las bolsas desde la compra deja de contar como "de camino"
--     (base = lo mínimo que había en las bolsas desde entonces: gastar no lo confunde);
--   · pasado ONWAY_TTL, fuera.
-- El correo no se lee (daba problemas, y lo que llega puede venir de otro sitio: un
-- intercambio, un alter): solo la compra y tus bolsas.
-- Se repasa en cada cambio de las bolsas (BAG_UPDATE_DELAYED, Ledger.SweepOnWay),
-- con el addon abierto o cerrado. Antes solo al pintar la lista, la ruta o el
-- asistente: sacarlo del buzón y gastarlo con todo cerrado no se veía y seguía
-- contando hasta las 2 h (Discord: "tienes 70 de 70" Mithril Bar sin tener ninguno).
-- Por personaje (ES.charData.ahOnWay = { { itemID, n, base, t } })
---------------------------------------------------------------------------
local ONWAY_TTL = 2 * 3600

local function OnWayList()
  local c = ES.charData
  if not c then return {} end
  c.ahOnWay = c.ahOnWay or {}
  return c.ahOnWay
end

-- Quita lo caducado y lo que ya llegó; devuelve las unidades de `itemID` aún de camino
function Ledger.OnWay(itemID)
  local list, now, left = OnWayList(), time(), 0
  for i = #list, 1, -1 do
    local e = list[i]
    if type(e) ~= "table" or not e.itemID or now - (e.t or 0) > ONWAY_TTL then
      table.remove(list, i)
    else
      local bags = BagCount(e.itemID)
      if bags < (e.base or 0) then e.base = bags end -- (gastaste de lo que tenías)
      local credit = (e.n or 0) - math.max(0, bags - (e.base or 0))
      if credit <= 0 then
        table.remove(list, i)
      elseif e.itemID == itemID then
        left = left + credit
      end
    end
  end
  return left
end

-- Repaso al cambiar las bolsas: baja la base de lo gastado y quita lo que ya llegó.
-- Sin compras de camino (lo normal) no hace nada, ni crea la lista. No repinta: las
-- vistas que se ven ya se repintan con el mismo evento
function Ledger.SweepOnWay()
  local list = ES.charData and ES.charData.ahOnWay
  if type(list) == "table" and #list > 0 then Ledger.OnWay(nil) end
end

-- Todo lo que sigue de camino: { [itemID] = unidades } (para el paso "Recoge el correo")
function Ledger.OnWayItems()
  Ledger.OnWay(nil) -- (limpia lo caducado y lo que ya llegó)
  local out = {}
  for _, e in ipairs(OnWayList()) do
    if not out[e.itemID] then out[e.itemID] = Ledger.OnWay(e.itemID) end -- (suma todas sus compras)
  end
  return out
end

local function Now() return GetTime and GetTime() or time() end

-- Compra en la AH confirmada: N unidades de camino al buzón. La misma compra llega por
-- varias vías (el mensaje del juego, el que escribe un addon como TSM, la API de la AH):
-- si otra vía ya la apuntó hace poco, no cuenta otra vez (si dice más unidades, solo
-- la diferencia: el mensaje del juego a veces no lleva la cantidad). La misma vía
-- repetida sí es otra compra. Devuelve true si apuntó algo
local DUP_WINDOW = 10
local recentBuys = {} -- [itemID] = { t, n, via = { [vía] = true } }
function Ledger.AddOnWay(itemID, n, via)
  if not (itemID and n and n > 0) then return false end
  via = via or "?"
  local now = Now()
  local r = recentBuys[itemID]
  local add = n
  if r and now - r.t < DUP_WINDOW and not r.via[via] then
    r.via[via] = true
    add = n - r.n
    if add <= 0 then
      Log(string.format("AH: %d× %d también por %s (ya contado)", n, itemID, via))
      return false
    end
    r.n = n
  else
    recentBuys[itemID] = { t = now, n = n, via = { [via] = true } }
  end
  local list = OnWayList()
  list[#list + 1] = { itemID = itemID, n = add, base = BagCount(itemID), t = time() }
  Log(string.format("AH: comprado %d× %d por %s (de camino al buzón)", add, itemID, via))
  -- Se dice en el chat: así se ve que la compra cuenta (y si algún día no sale, que no
  -- se detectó: queda Saltar en el asistente). Sin el texto del mensaje de la AH, que
  -- si no esta línea se leería otra vez como compra
  local name = (GetItemInfo and GetItemInfo(itemID)) or (ES.DataItemName and ES:DataItemName(itemID)) or tostring(itemID)
  if ES.Print then ES:Print(string.format(L["Compra detectada: %s ×%d. Cuenta ya para la ruta y la lista de compra."], name, add)) end
  return true
end

-- Una línea de chat: ¿dice que ganaste una subasta? (el mensaje del juego o el que
-- escribe un addon de la AH en su lugar, como TSM: "You won an auction for [x]x50 for
-- 35s 00c"). La misma línea en varias ventanas de chat cuenta una vez: llega a cada
-- ventana a la vez, en el mismo fotograma (GetTime() no cambia dentro de uno). Dos
-- compras iguales seguidas son dos mensajes del servidor, en fotogramas distintos, y
-- cuentan las dos (antes, con 2 s de margen, la segunda se perdía)
local lastLine, lastLineAt
function Ledger.OnChatLine(text, via)
  if not Ledger.Listening() or not Ledger.Readable(text) then return end
  local itemID, n = Ledger.ParseAuctionWon(text)
  if not itemID then return end
  local now = Now()
  if text == lastLine and now == lastLineAt then return end
  lastLine, lastLineAt = text, now
  if Ledger.AddOnWay(itemID, n, via) then Ledger.RefreshOnWay() end
end

-- AH clásica: comprar a precio de compra inmediata (PlaceAuctionBid con la puja igual
-- o mayor que ese precio) se gana al momento y te cobran: al bajar tu dinero, cuenta
function Ledger.OnPlaceBid(listType, index, bid)
  if not GetAuctionItemInfo then return end
  local info = { GetAuctionItemInfo(listType, index) }
  local count, buyout, itemID = info[3], info[10], info[17]
  if not (itemID and buyout and buyout > 0 and bid and bid >= buyout) then return end
  Ledger.pendingBid = { itemID = itemID, n = count or 1, money = GetMoney and GetMoney() or 0, t = Now() }
end

function Ledger.ConfirmBid()
  local p = Ledger.pendingBid
  if not p then return end
  Ledger.pendingBid = nil
  if Now() - p.t > 5 or not GetMoney or GetMoney() >= p.money then return end
  if Ledger.AddOnWay(p.itemID, p.n, "compra inmediata") then Ledger.RefreshOnWay() end
end

-- Se enganchan al cargar (antes que TSM y demás, que se cargan después por orden
-- alfabético y guardan su propia copia de la función)
if hooksecurefunc then
  if PlaceAuctionBid then
    hooksecurefunc("PlaceAuctionBid", function(...) pcall(Ledger.OnPlaceBid, ...) end)
  end
  if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
    hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, n)
      Ledger.pendingCommodity = itemID and { itemID = itemID, n = n or 1 } or nil
    end)
  end
  -- Lo que se escribe en las ventanas de chat (por si un addon cambia el mensaje del
  -- juego por el suyo, o lo escribe él)
  for i = 1, NUM_CHAT_WINDOWS or 10 do
    local cf = _G["ChatFrame" .. i]
    if cf and cf.AddMessage then
      hooksecurefunc(cf, "AddMessage", function(_, text) pcall(Ledger.OnChatLine, text, "chat") end)
    end
  end
end

-- Objeto por su nombre (en el idioma del cliente o en inglés): el del juego si lo tiene
-- en caché, si no, los nombres de los datos del addon
local nameToID
local function ItemIDByName(name)
  if not name or name == "" then return nil end
  local link = GetItemInfo and select(2, GetItemInfo(name))
  local id = link and tonumber(link:match("item:(%d+)"))
  if id then return id end
  if not nameToID then
    nameToID = {}
    for itemID, n in pairs(ES.Data.ItemNames or {}) do nameToID[n:lower()] = itemID end
    local set = ES.NamesFor and ES.DefaultLanguage and ES.NamesFor(ES.DefaultLanguage())
    for itemID, n in pairs(set and set.items or {}) do nameToID[n:lower()] = itemID end
  end
  if nameToID[name:lower()] then return nameToID[name:lower()] end
  -- Los pergaminos de receta ("Recipe: Rage Potion"): el mensaje del juego no lleva
  -- enlace y sus nombres no están en los datos; la receta sin el prefijo de su
  -- profesión ("Recipe: ", "Pattern: "...)
  local bare = name:match("^[^:]+:%s*(.+)$")
  if bare then
    bare = bare:lower()
    for _, p in ipairs(ES.PROFESSIONS or {}) do
      for _, r in pairs(ES.Data[p.key] and ES.Data[p.key].recipes or {}) do
        -- (r.name va en el idioma del addon; el mensaje, en el del cliente: también en inglés)
        if r.scroll and ((r.nameEN and r.nameEN:lower() == bare) or (r.name and r.name:lower() == bare)) then return r.scroll end
      end
    end
  end
end
Ledger.ItemIDByName = ItemIDByName -- (para pruebas)

-- "You won an auction for [Silverleaf]x21" (ERR_AUCTION_WON_S, en el idioma del
-- cliente): objeto y cuántos, o nil. Forever añade el precio detrás ("...x50 for
-- 10s 50c"): solo cuenta el principio fijo del mensaje, y lo que sigue al objeto y
-- su "xN" se ignora. El objeto, por su enlace o por su nombre
function Ledger.ParseAuctionWon(message)
  if type(message) ~= "string" then return nil end
  -- Sin colores (otros addons de chat los añaden; el enlace del objeto sigue: |H...|h)
  -- y el principio fijo en cualquier parte (por si algo va delante, como una hora)
  message = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local fmt = type(ERR_AUCTION_WON_S) == "string" and ERR_AUCTION_WON_S or "You won an auction for %s"
  local prefix = fmt:match("^(.-)%%s")
  if not prefix or prefix == "" then return nil end
  local at = message:find(prefix, 1, true)
  if not at then return nil end
  local what = message:sub(at + #prefix)
  local itemID, rest = what:match("|Hitem:(%d+)[^|]*|h.-|h|?r?(.*)$")
  local name
  itemID = tonumber(itemID)
  if not itemID then
    name, rest = what:match("^%[(.-)%](.*)$")
    if not name then name, rest = what:match("^(.-)%s*([xX×]%s*%d+.*)$") end
    if not name then name, rest = what, "" end
    name = name:gsub("%s+$", "")
    itemID = ItemIDByName(name)
  end
  local count = tonumber((rest or ""):match("^%s*[xX×]%s*(%d+)")) or 1
  -- (para diagnosticar en el juego: /cj, Informar de un error, lleva este registro)
  if not itemID and ES.db then Log("AH: compra sin reconocer el objeto: " .. what) end
  return itemID, count
end

function ES:HaveForShopping(itemID)
  return (self:ItemCount(itemID) or 0) + Ledger.OnWay(itemID)
end

local function RefreshOnWay()
  if ES.RefreshAfterBags then ES:RefreshAfterBags() end
  if ES.RenderShopping then ES:RenderShopping() end
  if ES.Assistant and ES.Assistant.Refresh then ES.Assistant.Refresh() end
end
Ledger.RefreshOnWay = RefreshOnWay

-- AH ocupada: cada cuánto se repite el aviso y cuándo se olvida un intento viejo (s)
local AH_BUSY_REPRINT, AH_BUSY_RESET = 10, 30
-- s que se espera la confirmación de un anuncio (AUCTION_HOUSE_AUCTION_CREATED o el
-- "Subasta creada." del chat) antes de darlo por hecho
local POST_CONFIRM_WAIT = 4
local WaitPost -- (más abajo, tras PostOnAH)

-- Duraciones de la AH, por su índice en C_AuctionHouse (1, 2, 3). Forever tiene
-- subastas de 2, 8 y 24 h (Planner.DURATIONS); el cliente moderno, de 12, 24 y 48.
-- Se pregunta al juego: el depósito de la 3 frente al de la 1 es 12 veces (2/8/24)
-- o 4 (12/24/48). Si no responde (o el depósito mínimo los iguala), 2/8/24.
local DURATION_SETS = { { 2, 8, 24 }, { 12, 24, 48 } }
function Ledger.DurationIndex(hours, AH, location, itemID, qty, commodity)
  if not Ledger.durationHours then
    local calc = AH and (commodity and AH.CalculateCommodityDeposit or AH.CalculateItemDeposit)
    if calc then
      local arg = commodity and itemID or location
      local ok1, d1 = pcall(calc, arg, 1, qty)
      local ok3, d3 = pcall(calc, arg, 3, qty)
      if ok1 and ok3 and type(d1) == "number" and type(d3) == "number" and d1 > 0 then
        local r = d3 / d1
        if r > 8 then Ledger.durationHours = DURATION_SETS[1]
        elseif r > 2.5 then Ledger.durationHours = DURATION_SETS[2] end
      end
    end
  end
  local set = Ledger.durationHours or DURATION_SETS[1]
  for i, h in ipairs(set) do
    if h >= (hours or 24) then return i, h end
  end
  return #set, set[#set]
end

-- Precios de la AH más viejos que esto: al anunciar se avisa en naranja (sin bloquear;
-- otros vendedores pueden haber bajado el precio)
Ledger.OLD_PRICES = 3600

-- Estado de los precios a los que se anuncia, para la ventana de vender y el
-- Inventario: "scanning" (no se anuncia hasta que acabe; con el % hecho),
-- "old" (con las horas) o nil (recientes o sin escaneo, que ya avisa cada ventana)
function Ledger:PostPriceState()
  if ES.Scanner and ES.Scanner:IsBusy() then
    return "scanning", math.floor((ES.Scanner.progress or 0) * 100)
  end
  local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
  if scan and scan.time and time() - scan.time > Ledger.OLD_PRICES then
    return "old", math.floor((time() - scan.time) / 3600)
  end
end

-- La línea en naranja de ese estado, o nil
function Ledger:PostPriceWarning()
  local state, n = self:PostPriceState()
  if state == "scanning" then
    return "|cffff9933" .. string.format(L["Escaneando la AH (%d%%): espera para anunciar al precio de ahora."], n) .. "|r"
  elseif state == "old" then
    return "|cffff9933" .. string.format(L["Precios de hace %d h: pueden haber cambiado. Escanea antes de anunciar."], n) .. "|r"
  end
end

-- Anuncia `n` unidades en la AH abierta a `unit` cobre cada una, en una subasta de
-- `hours` horas (24 por defecto; ver DurationIndex). Solo con la AH de Forever
-- (C_AuctionHouse); con la clásica, se anuncia a mano. Los materiales
-- (commodities) van en un solo anuncio; el resto, todos de una vez y, si la AH no
-- lo acepta, de uno en uno. Devuelve cuántos anunció.
function Ledger:PostOnAH(itemID, n, unit, hours)
  local AH = C_AuctionHouse
  if not (ES:IsAuctionHouseOpen() and AH and AH.PostItem and ItemLocation) then
    ES:Print(L["Anúncialo desde la ventana de la Casa de Subastas."])
    return 0
  end
  -- Escaneando (tuyo o el de otro addon al abrir la AH): el precio de la fila es el del
  -- escaneo anterior y en unos segundos llega el de ahora. Se espera (antes se
  -- anunciaba al precio viejo)
  if ES.Scanner and ES.Scanner:IsBusy() then
    ES:Print(string.format(L["Escaneando la AH (%d%%): espera a que acabe para anunciar al precio de ahora."],
      math.floor((ES.Scanner.progress or 0) * 100)))
    return 0
  end
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
    -- Ocupada: tras cada anuncio el servidor tarda un momento en aceptar otro (o otro
    -- addon está buscando). Se avisa una vez, no en cada clic, y cuando el juego dice
    -- que está lista. Nunca se anuncia con la AH ocupada: el servidor lo rechazaba en
    -- silencio y el chat decía "Anunciados" igualmente (antes se intentaba a los 3 s)
    local now = GetTime()
    local b = Ledger.ahBusy
    if not b or now - b.since > AH_BUSY_RESET then
      b = { since = now }
      Ledger.ahBusy = b
    end
    if not b.printed or now - b.printed > AH_BUSY_REPRINT then
      ES:Print(L["La Casa de Subastas está ocupada: vuelve a pulsar en un momento."])
      b.printed = now
    end
    b.waiting = true
    return 0
  end
  if Ledger.pendingPost then
    -- El anuncio anterior aún no está confirmado: uno cada vez
    ES:Print(L["La Casa de Subastas está ocupada: vuelve a pulsar en un momento."])
    return 0
  end
  Ledger.ahBusy = nil
  local slot
  for _, s in ipairs(Slots(itemID)) do
    local locked = C_Container and C_Container.GetContainerItemInfo and (C_Container.GetContainerItemInfo(s.bag, s.slot) or {}).isLocked
    if not locked then slot = s break end
  end
  if not slot or n <= 0 then return 0 end
  local qty = math.min(n, BagCount(itemID))
  local location = ItemLocation:CreateFromBagAndSlot(slot.bag, slot.slot)
  local commodity = false
  if AH.GetItemCommodityStatus then
    local ok, status = pcall(AH.GetItemCommodityStatus, location)
    local COMMODITY = Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2
    commodity = ok and status == COMMODITY
  end
  local price = Ledger.PostPrice(unit)
  local duration, postHours = Ledger.DurationIndex(hours, AH, location, itemID, qty, commodity)
  -- (con éxito, pcall devuelve true y lo que devuelva la AH: needsConfirmation)
  local ok, needs
  commodity = commodity and AH.PostCommodity ~= nil
  if commodity then
    ok, needs = pcall(AH.PostCommodity, location, duration, qty, price)
  else
    ok, needs = pcall(AH.PostItem, location, duration, qty, nil, price)
    if not ok and qty > 1 then -- no acepta varios de una vez: uno (el resto, con otro clic)
      qty = 1
      ok, needs = pcall(AH.PostItem, location, duration, 1, nil, price)
    end
  end
  if not ok then
    ES:Print(L["No se pudo anunciar: "] .. tostring(needs))
    return 0
  end
  -- "Anunciados" solo cuando la AH lo confirma (antes se decía al pedirlo, aunque el
  -- servidor lo rechazara); si da un error, se dice cuál (ver ConfirmPost). Con lo
  -- anunciado, por si la AH pide confirmarlo (AskPost)
  local p = { text = string.format(L["Anunciados %d de %s a %s cada uno (%d h)."], qty, ES:DataItemName(itemID) or itemID, ES.Money(price), postHours),
    name = ES:DataItemName(itemID) or tostring(itemID),
    itemID = itemID, location = location, duration = duration, qty = qty, price = price, hours = postHours,
    commodity = commodity }
  Ledger.pendingPost = p
  if needs then Ledger:AskPost(p) else WaitPost(p) end
  return qty
end

-- Espera la respuesta de la AH a `p`. Sin confirmación ni error: NO se da por hecho
-- (GitHub #6: un anuncio bloqueado salía como "Anunciados"); se dice que no hubo
-- respuesta, para mirarlo en la AH. Cada espera tiene su turno (p.wait): la del anuncio
-- no cuenta si la AH pidió confirmarlo, solo la que empieza con el "Sí" (AskPost)
function WaitPost(p)
  p.wait = (p.wait or 0) + 1
  local turn = p.wait
  C_Timer.After(POST_CONFIRM_WAIT, function()
    if Ledger.pendingPost == p and p.wait == turn and not p.asking then Ledger:ConfirmPost(nil) end
  end)
end

-- La AH pide confirmar el anuncio `p` (PostItem / PostCommodity devolvieron
-- needsConfirmation, normalmente por un precio raro). El "Aceptar" de la ventana del
-- juego solo confirma lo anunciado desde su pantalla: con un anuncio del addon no hacía
-- nada y a los 4 s salía "no confirmó" (GitHub #10). Se pregunta con la ventana del
-- addon, sin la casilla de no volver a mostrar: es el servidor quien lo pide, y
-- confirmar pide tu clic. La del juego se esconde (AUCTION_HOUSE_POST_WARNING)
function Ledger:AskPost(p)
  p.asking = true
  local label = ES.UI and ES.UI.ItemLabel and ES.UI.ItemLabel(p.itemID, p.name) or p.name
  ES:Confirm({
    noCheck = true, title = L["Confirmar anuncio"],
    text = string.format(L["La Casa de Subastas pide que confirmes este anuncio: %d × %s a %s cada uno (%d h)."],
      p.qty, label, ES.Money(p.price), p.hours),
    closeOn = "AUCTION_HOUSE_CLOSED",
    onYes = function() Ledger:ConfirmAsked(p) end,
    onCancel = function() Ledger:CancelAsked(p) end,
  })
end

-- "Sí": el mismo anuncio, confirmado (lo primero del clic: ver ES:Confirm)
function Ledger:ConfirmAsked(p)
  if Ledger.pendingPost ~= p or not p.asking then return end
  local AH = C_AuctionHouse
  local ok, err
  if p.commodity then
    ok, err = pcall(AH.ConfirmPostCommodity, p.location, p.duration, p.qty, p.price)
  else
    ok, err = pcall(AH.ConfirmPostItem, p.location, p.duration, p.qty, nil, p.price)
  end
  p.asking = nil
  if not ok then
    Ledger.pendingPost = nil
    ES:Print(L["No se pudo anunciar: "] .. tostring(err))
    if ES.AuctionSell then ES.AuctionSell:Refresh() end
    return
  end
  WaitPost(p)
end

-- "No", Escape o cerrar la AH con la pregunta abierta: no se anuncia
function Ledger:CancelAsked(p)
  if Ledger.pendingPost ~= p or not p.asking then return end
  Ledger.pendingPost = nil
  ES:Print(string.format(L["Anuncio cancelado: %s"], p.name))
  if ES.AuctionSell then ES.AuctionSell:Refresh() end
end

-- ¿Es `message` un error de la AH? Los textos del juego ERR_AUCTION_* (en el idioma
-- del cliente) y el de no tener dinero (el depósito). Se leen una vez de _G
local auctionErrors
function Ledger.IsAuctionError(message)
  if not Ledger.Readable(message) then return false end
  if not auctionErrors then
    auctionErrors = {}
    for k, v in pairs(_G) do
      if type(k) == "string" and type(v) == "string" and k:find("^ERR_AUCTION") then auctionErrors[v] = true end
    end
    if type(ERR_NOT_ENOUGH_MONEY) == "string" then auctionErrors[ERR_NOT_ENOUGH_MONEY] = true end
  end
  return auctionErrors[message] == true
end

-- Respuesta de la AH al último anuncio: ok (creado), false y el mensaje de error, o nil
-- (sin respuesta a tiempo: no se sabe si se anunció)
function Ledger:ConfirmPost(ok, message)
  local p = Ledger.pendingPost
  if not p then return end
  Ledger.pendingPost = nil
  if ok then
    ES:Print(p.text)
  elseif ok == nil then
    ES:Print(string.format(L["La Casa de Subastas no confirmó el anuncio de %s: míralo en Subastas."], p.name))
  else
    ES:Print(string.format(L["La Casa de Subastas no aceptó %s: %s"], p.name, tostring(message or "?")))
  end
  if ES.AuctionSell then ES.AuctionSell:Refresh() end
end
