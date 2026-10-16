local _, ES = ...

-- Tus ventas reales, leídas del buzón: los correos de la Casa de Subastas dicen
-- qué subastas TUYAS se vendieron (y por cuánto) y cuáles caducaron. No es una
-- estimación: son datos del jugador. Se usan en "Ganar dinero" para ajustar
-- cuántas fabricar y para mostrar lo que has ganado.
--
-- CraftersJournalDB.mail[personaje] = { seen = { [clave] = hora }, events = { {t, itemID, kind, money, name} } }
--   kind = "sold" | "expired"

local Mail = {}
ES.Mail = Mail

local KEEP = 30 * 86400 -- los correos duran 30 días
local STATS_WINDOW = 7 * 86400

local function Store()
  ES.db.mail = ES.db.mail or {}
  local char = ES:CharKey()
  local s = ES.db.mail[char]
  if not s then
    s = { seen = {}, events = {} }
    ES.db.mail[char] = s
  end
  return s
end

-- Nombre de objeto -> itemID, de los objetos de profesiones que el juego ya
-- conoce (los correos de venta solo traen el nombre)
local nameToID, builtAt = nil, 0
local function ItemIDByName(name)
  if not name then return nil end
  -- Si no está, puede que el juego no tuviera cargado el objeto al construir la
  -- tabla: se reconstruye, como mucho una vez por minuto
  if nameToID and not nameToID[name] and time() - builtAt > 60 then nameToID = nil end
  if not nameToID then
    builtAt = time()
    nameToID = {}
    for _, data in pairs(ES.Data) do
      if type(data) == "table" and data.recipes then
        for _, r in pairs(data.recipes) do
          if r.out then
            local n = ES:GetItemData(r.out[1])
            if n then nameToID[n] = r.out[1] end
          end
        end
      end
    end
  end
  return nameToID[name]
end

-- "Subasta vendida: %s" -> patrón que captura el nombre. Se escapan todos los
-- caracteres mágicos, también "%": así "%s" queda "%%s" y se cambia por la captura.
local function SubjectPattern(fmt)
  if not fmt then return nil end
  local escaped = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  return "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
end
Mail.SubjectPattern = SubjectPattern -- para pruebas

-- Lee el buzón y guarda los correos de subasta que aún no había visto
function Mail:Scan()
  if not GetInboxNumItems or not GetInboxHeaderInfo then return 0 end
  local soldPat = SubjectPattern(AUCTION_SOLD_MAIL_SUBJECT)
  local expiredPat = SubjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT)
  local s, now, added = Store(), time(), 0
  for i = 1, GetInboxNumItems() do
    local _, _, _, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
    if subject and daysLeft then
      local kind, name
      local sold = soldPat and subject:match(soldPat)
      local expired = expiredPat and subject:match(expiredPat)
      if sold then kind, name = "sold", sold elseif expired then kind, name = "expired", expired end
      if kind then
        -- Clave estable: el correo caduca siempre a la misma hora
        local expires = math.floor((now + daysLeft * 86400) / 3600)
        local key = table.concat({ kind, name, money or 0, expires }, "|")
        if not s.seen[key] then
          s.seen[key] = now
          local itemID = ItemIDByName(name)
          if kind == "expired" and GetInboxItem then
            local _, id = GetInboxItem(i, 1)
            if type(id) == "number" then itemID = id end
          end
          -- Momento de la venta: el correo dura 30 días desde que llega
          local when = math.min(now, now - (30 - daysLeft) * 86400)
          s.events[#s.events + 1] = { when, itemID or 0, kind, money or 0, name }
          added = added + 1
        end
      end
    end
  end
  -- Limpieza
  local keep = {}
  for _, e in ipairs(s.events) do if now - e[1] < KEEP then keep[#keep + 1] = e end end
  s.events = keep
  for k, t in pairs(s.seen) do if now - t > KEEP + 86400 then s.seen[k] = nil end end
  if added > 0 then
    self.stamp = (self.stamp or 0) + 1
    if ES.Earn then ES.Earn:Clear() end
  end
  return added
end

-- Cambia cuando hay correos nuevos (para cachés)
function Mail:Stamp() return self.stamp or 0 end

-- Ventas y caducadas de un objeto en los últimos 7 días (todos tus personajes del reino)
function Mail:Stats(itemID)
  if not ES.db.mail then return nil end
  local realm = "-" .. (GetRealmName() or "?")
  local now = time()
  local st = { sold = 0, expired = 0, money = 0 }
  for char, s in pairs(ES.db.mail) do
    if char:sub(-#realm) == realm then
      for _, e in ipairs(s.events) do
        if e[2] == itemID and now - e[1] < STATS_WINDOW then
          if e[3] == "sold" then st.sold, st.money = st.sold + 1, st.money + e[4] else st.expired = st.expired + 1 end
        end
      end
    end
  end
  return st
end

-- Resumen de los últimos 7 días (todos los objetos): vendidas, caducadas, oro
function Mail:Summary()
  local res = { sold = 0, expired = 0, money = 0, byItem = {} }
  if not ES.db.mail then return res end
  local realm = "-" .. (GetRealmName() or "?")
  local now = time()
  for char, s in pairs(ES.db.mail) do
    if char:sub(-#realm) == realm then
      for _, e in ipairs(s.events) do
        if now - e[1] < STATS_WINDOW then
          local b = res.byItem[e[5]] or { name = e[5], itemID = e[2], sold = 0, expired = 0, money = 0 }
          res.byItem[e[5]] = b
          if e[3] == "sold" then
            res.sold, res.money, b.sold, b.money = res.sold + 1, res.money + e[4], b.sold + 1, b.money + e[4]
          else
            res.expired, b.expired = res.expired + 1, b.expired + 1
          end
        end
      end
    end
  end
  return res
end

do
  local f = CreateFrame("Frame")
  ES.SafeRegister(f, "MAIL_INBOX_UPDATE")
  f:SetScript("OnEvent", function()
    if not ES.db then return end
    local n = Mail:Scan()
    if n > 0 and ES.RenderEarn then ES:RenderEarn() end
  end)
end
