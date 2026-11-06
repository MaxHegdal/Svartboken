-- Svartboken: tyst synk av dödsfall mellan gängets klienter.
local _, ns = ...

local WIRE_VERSION = "1"
local SEND_INTERVAL = 1.1
local MAX_QUEUE = 300
-- Över kölängden per minut, så att Dela historik alltid kommer fram helt.
local RATE_LIMIT_PER_MIN = 60
local SHARE_LIMIT = 30
local SHARE_NOTE_LIMIT = 20
local SHARE_MAX_AGE = 30 * 86400
local SHARE_COOLDOWN = 60
local MAX_GANG = 12
local OFFLINE_SECONDS = 120
local WHISPER_ERROR_WINDOW = 10
local PING, PONG = "P~1", "O~1"
local PONG_COOLDOWN = 5
local TEST_SECONDS = 6
local VERSION_REPLY_COOLDOWN = 60
local CHANNEL_NAME = "SvartbokenSync"
-- Vänta in General och Trade så att spelarens kanalnummer inte flyttas.
local JOIN_DELAY = 8
local JOIN_RETRY = 30
local JOIN_ATTEMPTS = 4

local ALLOWED_CHANNELS = { PARTY = true, RAID = true, GUILD = true, WHISPER = true, CHANNEL = true }
local ALLOWED_TYPES = { player = true, npc = true, env = true, unknown = true }

local queue = {}
local ticker
local received = {}
local lastShare = 0
local offlineUntil, heardAt, pingedAt, whisperedAt = {}, {}, {}, {}
local peers = {}
local joinToken = 0
local lastPong = 0
local activeTest
local versionAnnounced = false
local lastVersionReply = 0

local function Split(s, sep)
    local out, start = {}, 1
    while true do
        local a = s:find(sep, start, true)
        if not a then
            out[#out + 1] = s:sub(start)
            return out
        end
        out[#out + 1] = s:sub(start, a - 1)
        start = a + 1
    end
end

function ns.Encode(rec)
    local assists = {}
    for i, name in ipairs(rec.assists or {}) do
        if i > 3 then break end
        assists[#assists + 1] = (name:gsub(",", " "))
    end
    local function Build(assistText, subzone, spell)
        return table.concat({
            "D", WIRE_VERSION, tostring(rec.ts), rec.victim, rec.vclass or "",
            rec.killer or "", rec.ktype or "unknown", rec.kclass or "",
            spell or "", tostring(rec.spellId or 0),
            tostring(rec.amount or 0), tostring(rec.overkill or 0),
            rec.zone or "", subzone or "", assistText,
        }, "~")
    end
    local msg = Build(table.concat(assists, ","), rec.subzone, rec.spell)
    if #msg > 250 then msg = Build("", rec.subzone, rec.spell) end
    if #msg > 250 then msg = Build("", nil, rec.spell) end
    if #msg > 250 then msg = Build("", nil, nil) end
    if #msg > 250 then return nil end
    return msg
end

-- Avsändaren får bara rapportera sina egna dödsfall, och all text tvättas.
function ns.Decode(text, senderShort)
    local p = Split(text, "~")
    if #p < 15 or p[1] ~= "D" or p[2] ~= WIRE_VERSION then return nil end

    local ts = tonumber(p[3])
    local now = GetServerTime()
    if not ts or ts ~= math.floor(ts) or ts < now - 365 * 86400 or ts > now + 300 then return nil end

    local victim = ns.PlayerName(p[4])
    if not victim or victim ~= senderShort then return nil end

    local function Class(v)
        return (v ~= "" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[v]) and v or nil
    end
    local function Number(v)
        local n = tonumber(v)
        if not n or n < 0 or n > 1e10 then return 0 end
        return math.floor(n)
    end

    -- Bara spelare hör hemma i trackern, även om en äldre version skickar något annat.
    local killer = ns.PlayerName(p[6])
    if not ns.IsFullName(killer) or p[7] == "npc" or p[7] == "env" then return nil end
    local assists
    if p[15] ~= "" then
        assists = {}
        for _, name in ipairs(Split(p[15], ",")) do
            name = ns.Clean(name, 64)
            if name and #assists < 3 then assists[#assists + 1] = name end
        end
    end

    return {
        id = ns.MakeId(victim, ts),
        ts = ts,
        victim = victim,
        vclass = Class(p[5]),
        killer = killer,
        ktype = ALLOWED_TYPES[p[7]] and p[7] or "unknown",
        kclass = Class(p[8]),
        spell = ns.Clean(p[9], 64),
        spellId = Number(p[10]),
        amount = Number(p[11]),
        overkill = Number(p[12]),
        zone = ns.Clean(p[13], 64),
        subzone = ns.Clean(p[14], 64),
        assists = assists,
        source = "sync",
    }
end

function ns.EncodeNote(killer, note)
    local msg = table.concat({
        "N", WIRE_VERSION, tostring(note.ts), killer, note.author, note.text or "",
    }, "~")
    if #msg > 250 then return nil end
    return msg
end

-- Bara författaren själv kan skicka sin anteckning.
function ns.DecodeNote(text, senderShort)
    local p = Split(text, "~")
    if #p < 6 or p[1] ~= "N" or p[2] ~= WIRE_VERSION then return nil end
    local ts = tonumber(p[3])
    local now = GetServerTime()
    if not ts or ts ~= math.floor(ts) or ts < now - 365 * 86400 or ts > now + 300 then return nil end
    local killer = ns.Clean(p[4], 64)
    local author = ns.PlayerName(p[5])
    if not killer or not author or author ~= senderShort then return nil end
    return { killer = killer, author = author, ts = ts, text = ns.Clean(p[6], ns.MAX_NOTE) }
end

local function CanSend()
    if not ns.IsOpenWorld() then return false end
    if C_ChatInfo.InChatMessagingLockdown and ns.Safe(C_ChatInfo.InChatMessagingLockdown()) then
        return false
    end
    return true
end

local function ChannelId()
    if not GetChannelName then return nil end
    local ok, id = pcall(GetChannelName, CHANNEL_NAME)
    id = ok and ns.Safe(id) or nil
    if type(id) == "number" and id > 0 then return id end
    return nil
end

-- Kanalen är det som gör att alla med addonet hittar varandra utan inställningar.
function ns.ChannelActive()
    return ns.db.settings.channelSync and ChannelId() ~= nil
end

local function JoinChannel()
    local join = JoinTemporaryChannel or JoinChannelByName
    if join then pcall(join, CHANNEL_NAME) end
end

function ns.ScheduleChannelJoin()
    if not ns.db.settings.channelSync then return end
    -- Vid /reload ligger kanalen kvar, och då behövs bara versionen.
    if ChannelId() then
        C_Timer.After(JOIN_DELAY, function() ns.AnnounceVersion() end)
        return
    end
    joinToken = joinToken + 1
    local token, attempt = joinToken, 0
    local function Try()
        if token ~= joinToken or not ns.db.settings.channelSync or not ns.IsOpenWorld() or ChannelId() then
            return
        end
        attempt = attempt + 1
        JoinChannel()
        if attempt < JOIN_ATTEMPTS then C_Timer.After(JOIN_RETRY, Try) end
        C_Timer.After(1, function()
            ns.AnnounceVersion()
            if ns.RefreshUI then ns.RefreshUI() end
        end)
    end
    C_Timer.After(JOIN_DELAY, Try)
end

function ns.SetChannelSync(enabled)
    ns.db.settings.channelSync = enabled
    if enabled then
        if ns.IsOpenWorld() and not ChannelId() then JoinChannel() end
    else
        joinToken = joinToken + 1
        wipe(peers)
        if LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL_NAME) end
    end
    if ns.RefreshUI then ns.RefreshUI() end
end

-- Namnen på dem som addonet hört i kanalen, nyast först.
function ns.ChannelPeers()
    local list = {}
    for name in pairs(peers) do list[#list + 1] = name end
    table.sort(list, function(a, b)
        if peers[a] ~= peers[b] then return peers[a] > peers[b] end
        return a < b
    end)
    return list
end

local function GangKey(name)
    local full = ns.PlayerName(name)
    return full and ns.Lower(full) or nil
end

function ns.IsGang(name)
    local key = GangKey(name)
    if not key then return false end
    for _, member in ipairs(ns.db.gang) do
        if GangKey(member) == key then return true end
    end
    return false
end

-- Returnerar true, eller false och en förklaring.
function ns.AddGang(name)
    name = ns.PlayerName(name)
    if not name then return false, "Skriv ett spelarnamn, till exempel Anna Berg." end
    if GangKey(name) == GangKey(ns.playerName) then return false, "Det är du själv." end
    if ns.IsGang(name) then return false, name .. " finns redan i gänget." end
    if #ns.db.gang >= MAX_GANG then return false, "Gänget får ha högst " .. MAX_GANG .. " namn." end
    ns.db.gang[#ns.db.gang + 1] = name
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

function ns.RemoveGang(name)
    local key = GangKey(name)
    local removed = false
    for i = #ns.db.gang, 1, -1 do
        if GangKey(ns.db.gang[i]) == key then
            table.remove(ns.db.gang, i)
            removed = true
        end
    end
    if ns.RefreshUI then ns.RefreshUI() end
    return removed
end

local function IsOffline(key)
    return offlineUntil[key] ~= nil and GetServerTime() < offlineUntil[key]
end

-- Texten som visas bredvid namnet i gänglistan.
function ns.GangStatus(name)
    local key = GangKey(name)
    if IsOffline(key) then return "Offline", "muted" end
    if heardAt[key] then
        if pingedAt[key] and pingedAt[key] > heardAt[key] then return "Väntar på svar", "muted" end
        return "Svarade, " .. ns.TimeAgo(heardAt[key]), "good"
    end
    if pingedAt[key] then return "Inget svar än", "muted" end
    return "Inte testad", "muted"
end

local function InMyGroup(name)
    if not IsInGroup() then return false end
    local ok, inParty = pcall(UnitInParty, name)
    if ok and ns.Safe(inParty) then return true end
    local ok2, inRaid = pcall(UnitInRaid, name)
    return ok2 and ns.Safe(inRaid) ~= nil
end

local function Targets()
    -- Kanalen når alla, så grupp, guild och gänglista behövs bara om den inte fungerar.
    if ns.ChannelActive() then return { { channel = "CHANNEL" } } end
    local out = {}
    if IsInRaid() then
        out[#out + 1] = { channel = "RAID" }
    elseif IsInGroup() then
        out[#out + 1] = { channel = "PARTY" }
    end
    if ns.db.settings.guildSync and IsInGuild() then
        out[#out + 1] = { channel = "GUILD" }
    end
    for _, name in ipairs(ns.db.gang) do
        if not InMyGroup(name) and not IsOffline(GangKey(name)) then
            out[#out + 1] = { channel = "WHISPER", target = name }
        end
    end
    return out
end

-- Någon i gänget är offline: släng det som väntar till hen och vila en stund.
local function MarkOffline(key)
    offlineUntil[key] = GetServerTime() + OFFLINE_SECONDS
    for i = #queue, 1, -1 do
        if queue[i].target and GangKey(queue[i].target) == key then
            table.remove(queue, i)
        end
    end
    if ns.RefreshUI then ns.RefreshUI() end
end

-- Kanalen ska vara osynlig: inga "Joined Channel" i chatten.
local function ChannelNoticeFilter(_, _, _, _, _, channelName, _, _, _, _, baseName)
    channelName, baseName = ns.Safe(channelName), ns.Safe(baseName)
    if baseName == CHANNEL_NAME then return true end
    return type(channelName) == "string" and channelName:find(CHANNEL_NAME, 1, true) ~= nil
end

-- Viskar du någon offline kan servern svara med ett felmeddelande i chatten.
-- Det döljs bara för namn i gänget och bara precis efter att addonet viskat.
local function SystemMessageFilter(_, _, text)
    text = ns.Safe(text)
    if type(text) ~= "string" or not ERR_CHAT_PLAYER_NOT_FOUND_S then return false end
    local lowered = ns.Lower(text)
    local now = GetTime()
    for _, name in ipairs(ns.db.gang) do
        local key = GangKey(name)
        if whisperedAt[key] and now - whisperedAt[key] < WHISPER_ERROR_WINDOW then
            local spaced = ns.Lower(ERR_CHAT_PLAYER_NOT_FOUND_S:format(name))
            local hyphened = ns.Lower(ERR_CHAT_PLAYER_NOT_FOUND_S:format((name:gsub(" ", "-"))))
            if lowered == spaced or lowered == hyphened then
                MarkOffline(key)
                return true
            end
        end
    end
    return false
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function IsThrottle(result)
    local e = Enum and Enum.SendAddonMessageResult
    if not e then return false end
    return result == e.AddonMessageThrottle or result == e.ChannelThrottle
end

local function IsTargetOffline(result)
    local e = Enum and Enum.SendAddonMessageResult
    return e ~= nil and e.TargetOffline ~= nil and result == e.TargetOffline
end

local function PumpQueue()
    if #queue == 0 then
        StopTicker()
        return
    end
    if not CanSend() then
        -- Väntar tills du är tillbaka i open world.
        StopTicker()
        return
    end
    local entry = queue[1]
    local target = entry.target
    if entry.channel == "CHANNEL" then
        -- Kanalnumret kan ändras, så det slås upp precis innan det används.
        local id = ChannelId()
        if not id then
            table.remove(queue, 1)
            return
        end
        target = tostring(id)
    end
    if entry.target then whisperedAt[GangKey(entry.target)] = GetTime() end
    local result = C_ChatInfo.SendAddonMessage(ns.PREFIX, entry.msg, entry.channel, target)
    ns.lastSendResult = result
    if IsTargetOffline(result) and entry.target then
        MarkOffline(GangKey(entry.target))
    elseif not IsThrottle(result) then
        table.remove(queue, 1)
    end
end

local function EnsureTicker()
    if not ticker and #queue > 0 then
        ticker = C_Timer.NewTicker(SEND_INTERVAL, PumpQueue)
    end
end

function ns.ResumeSync()
    EnsureTicker()
end

-- Returnerar false om kön var full, så att Dela historik inte lovar mer än som skickas.
local function Enqueue(msg)
    local allQueued = true
    for _, target in ipairs(Targets()) do
        if #queue < MAX_QUEUE then
            queue[#queue + 1] = { msg = msg, channel = target.channel, target = target.target }
        else
            allQueued = false
        end
    end
    EnsureTicker()
    return allQueued
end

-- Knappen "Testa": frågar gänget om addonet svarar. Ett svar betyder att båda har varandra på listan.
function ns.PingGang()
    if not CanSend() then return false, "Går bara att testa i open world." end
    if ns.ChannelActive() then
        queue[#queue + 1] = { msg = PING, channel = "CHANNEL" }
        EnsureTicker()
        return true
    end
    if #ns.db.gang == 0 then return false, "Gänglistan är tom." end
    local now = GetServerTime()
    for _, name in ipairs(ns.db.gang) do
        local key = GangKey(name)
        offlineUntil[key] = nil
        pingedAt[key] = now
        if #queue < MAX_QUEUE then
            queue[#queue + 1] = { msg = PING, channel = "WHISPER", target = name }
        end
    end
    EnsureTicker()
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

function ns.Broadcast(rec)
    if not ns.db.settings.sync or rec.demo or not CanSend() then return end
    local msg = ns.Encode(rec)
    if msg then Enqueue(msg) end
end

local function FinishTest(test)
    activeTest = nil
    local names = {}
    for name in pairs(test.replies) do names[#names + 1] = name end
    table.sort(names)
    local text
    if #names > 0 then
        text = "Svarade: " .. table.concat(names, ", ")
    elseif test.viaChannel and test.echoed then
        text = "Kanalen fungerar, men ingen annan svarade. De andra behöver vara online, i open world och ha version 1.1.0 eller nyare."
    elseif test.viaChannel then
        text = "Ingen svarade och din egen signal kom inte tillbaka. Kör /sb debug och skicka utskriften."
    else
        text = "Ingen svarade. Båda måste ha varandra på gänglistan och vara online."
    end
    ns.testResult = text
    ns.Print(text)
    if ns.RefreshUI then ns.RefreshUI() end
end

-- Knappen "Testa": visar alltid ett resultat, även när ingen svarar.
function ns.RunSyncTest()
    if activeTest then return true end
    if not CanSend() then return false, "Går bara att testa i open world." end
    local viaChannel = ns.ChannelActive()
    if not viaChannel and ns.db.settings.channelSync then JoinChannel() end
    if not viaChannel and #ns.db.gang == 0 then
        return false, "Kanalen är inte ansluten och gänglistan är tom. Försök igen om några sekunder."
    end
    local ok, reason = ns.PingGang()
    if not ok then return false, reason end
    local test = { replies = {}, viaChannel = viaChannel }
    activeTest = test
    ns.testResult = "Testar, vänta några sekunder..."
    C_Timer.After(TEST_SECONDS + #queue * SEND_INTERVAL, function() FinishTest(test) end)
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

-- En gång per session berättar addonet vilken version det har, bara i den dolda kanalen.
function ns.AnnounceVersion()
    if versionAnnounced or not ns.ChannelActive() or not CanSend() then return end
    versionAnnounced = true
    queue[#queue + 1] = { msg = "V~1~" .. ns.VERSION, channel = "CHANNEL" }
    EnsureTicker()
end

local function OnPeerVersion(version)
    local delta = ns.CompareVersions(version, ns.VERSION)
    if not delta then return end
    if delta > 0 then
        if not ns.newerVersion or ns.CompareVersions(version, ns.newerVersion) > 0 then
            local first = ns.newerVersion == nil
            ns.newerVersion = version
            if first then
                ns.Print("En nyare version finns hos en kompis (" .. version .. "). Du har " .. ns.VERSION
                    .. ". Kör Uppdatera-Svartboken och starta om spelet.")
            end
            if ns.RefreshUI then ns.RefreshUI() end
        end
    elseif delta < 0 and CanSend() and ns.ChannelActive()
        and GetServerTime() - lastVersionReply >= VERSION_REPLY_COOLDOWN then
        lastVersionReply = GetServerTime()
        queue[#queue + 1] = { msg = "V~1~" .. ns.VERSION, channel = "CHANNEL" }
        EnsureTicker()
    end
end

function ns.BroadcastNote(killer)
    local note = ns.db.notes[killer]
    if not note or note.demo or not ns.db.settings.sync or not CanSend() then return end
    local msg = ns.EncodeNote(killer, note)
    if msg then Enqueue(msg) end
end

-- Knappen "Dela historik": skickar dina egna senaste dödsfall och anteckningar till gänget.
-- Returnerar antal köade dödsfall, eller nil och en förklaring.
function ns.ShareHistory(me)
    if not ns.db.settings.sync then return nil, "Synk är avstängd." end
    if not CanSend() then return nil, "Går bara att dela i open world." end
    if #Targets() == 0 then return nil, "Ingen att dela med. Gå med i en grupp eller fyll i gänglistan." end
    local now = GetServerTime()
    if now - lastShare < SHARE_COOLDOWN then
        return nil, "Vänta " .. (SHARE_COOLDOWN - (now - lastShare)) .. " sek."
    end
    lastShare = now
    local count = 0
    for _, d in ipairs(ns.db.deaths) do
        if count >= SHARE_LIMIT or now - d.ts > SHARE_MAX_AGE then break end
        if d.victim == me and not d.demo then
            local msg = ns.Encode(d)
            if msg then
                if not Enqueue(msg) then return count, 0 end
                count = count + 1
            end
        end
    end
    local notes = 0
    for killer, note in pairs(ns.db.notes) do
        if notes >= SHARE_NOTE_LIMIT then break end
        if note.author == me and not note.demo then
            local msg = ns.EncodeNote(killer, note)
            if msg then
                if not Enqueue(msg) then return count, notes end
                notes = notes + 1
            end
        end
    end
    return count, notes
end

local function AllowFromSender(sender)
    local now = GetServerTime()
    local bucket = received[sender]
    if not bucket or now - bucket.start >= 60 then
        bucket = { start = now, count = 0 }
        received[sender] = bucket
    end
    bucket.count = bucket.count + 1
    return bucket.count <= RATE_LIMIT_PER_MIN
end

function ns.OnAddonMessage(prefix, text, channel, sender)
    prefix, text, channel, sender = ns.Safe(prefix), ns.Safe(text), ns.Safe(channel), ns.Safe(sender)
    if prefix ~= ns.PREFIX or not text or not sender then return end
    if not ns.db.settings.sync or not ALLOWED_CHANNELS[channel] then return end
    if channel == "GUILD" and not ns.db.settings.guildSync then return end
    if channel == "CHANNEL" and not ns.db.settings.channelSync then return end

    local senderShort = ns.PlayerName(sender)
    if not senderShort then return end
    if senderShort == ns.playerName then
        -- Din egen signal i kanalen visar att den fungerar.
        if text == PING and channel == "CHANNEL" and activeTest then activeTest.echoed = true end
        return
    end
    -- Viskningar tas bara emot från namn du själv lagt till i gänget.
    local fromGang = ns.IsGang(senderShort)
    if channel == "WHISPER" and not fromGang then return end
    if not AllowFromSender(senderShort) then return end

    if fromGang then
        local key = GangKey(senderShort)
        heardAt[key] = GetServerTime()
        offlineUntil[key] = nil
    end
    if channel == "CHANNEL" then
        peers[senderShort] = GetServerTime()
    end

    if text == PING then
        if channel == "WHISPER" and CanSend() and #queue < MAX_QUEUE then
            queue[#queue + 1] = { msg = PONG, channel = "WHISPER", target = sender }
            EnsureTicker()
        elseif channel == "CHANNEL" and CanSend() and #queue < MAX_QUEUE
            and GetServerTime() - lastPong >= PONG_COOLDOWN then
            lastPong = GetServerTime()
            queue[#queue + 1] = { msg = PONG, channel = "CHANNEL" }
            EnsureTicker()
        end
        if ns.RefreshUI then ns.RefreshUI() end
        return
    elseif text == PONG then
        if activeTest then activeTest.replies[senderShort] = true end
        if ns.RefreshUI then ns.RefreshUI() end
        return
    end

    if text:sub(1, 4) == "V~1~" then
        OnPeerVersion(text:sub(5))
        return
    end

    if text:sub(1, 2) == "N~" then
        local note = ns.DecodeNote(text, senderShort)
        if note then ns.ApplyNote(note.killer, note.text, note.author, note.ts) end
        return
    end

    local rec = ns.Decode(text, senderShort)
    if rec then ns.AddDeath(rec) end
end

function ns.InitSync()
    C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemMessageFilter)
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", ChannelNoticeFilter)
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", ChannelNoticeFilter)
    end
end
