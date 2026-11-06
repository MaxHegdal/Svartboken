-- Svartboken: läser killing blow ur death recap. Aktiv endast i open world.
local _, ns = ...

local RETRY_DELAYS = { 0.1, 0.4, 0.8, 1.5, 3 }
local MAX_CLASS_CACHE = 1000
local LOGIN_GRACE = 3
local DEATH_DEDUPE = 5
local MAX_RECAP_AGE = 15
local MIN_EPOCH = 1000000000
local PLAYER_FLAG = 0x400 -- COMBATLOG_OBJECT_TYPE_PLAYER

local PASSIVE_EVENTS = {
    "PLAYER_DEAD",
    "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED",
    "CHAT_MSG_ADDON",
}

local frame = CreateFrame("Frame")
local active = false
local pending
local enteredAt = 0
local lastDeathAt = 0
local classCount = 0
local npcCount = 0
local warnedUnreadable = false

local Safe = ns.Safe

local function Field(t, key)
    return Safe(t[key])
end

local function GetRecapEvents()
    local recap = C_DeathRecap
    if not (recap and recap.HasRecapEvents and recap.GetRecapEvents) then return nil end
    local ok, has = pcall(recap.HasRecapEvents)
    if not ok or not Safe(has) then return nil end
    local ok2, events = pcall(recap.GetRecapEvents)
    events = ok2 and Safe(events) or nil
    if type(events) ~= "table" then return nil end
    if canaccesstable and not canaccesstable(events) then return nil end
    return events
end
ns.GetRecapEvents = GetRecapEvents

local function ClassFromGUID(guid)
    if GetPlayerInfoByGUID then
        local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
        class = ok and Safe(class) or nil
        if type(class) == "string" then return class end
    end
    return nil
end

-- Avgör om mördaren är en spelare, NPC eller miljön så långt datan räcker.
local function Classify(event, name)
    local guid = Field(event, "sourceGUID")
    if type(guid) == "string" then
        if guid:find("^Player%-") then
            return "player", ClassFromGUID(guid) or ns.db.classes[name]
        elseif guid:find("^Creature%-") or guid:find("^Vehicle%-") or guid:find("^GameObject%-") then
            return "npc"
        elseif guid:find("^Pet%-") then
            return "npc"
        end
    end
    local flags = Field(event, "sourceFlags")
    if type(flags) == "number" and flags ~= 0 and bit then
        if bit.band(flags, PLAYER_FLAG) ~= 0 then
            return "player", ns.db.classes[name]
        end
        return "npc"
    end
    if ns.db.classes[name] then
        return "player", ns.db.classes[name]
    end
    if ns.db.npcs[name] or not ns.IsFullName(name) then
        return "npc"
    end
    -- Två ord som aldrig setts: "Anna Berg" och "Bloodsail Raider" går inte att skilja på.
    return "unknown"
end

local function SourceName(event)
    if Field(event, "hideCaster") then return nil end
    local raw = ns.Clean(Field(event, "sourceName"), 64)
    if not raw then return nil end
    local guid = Field(event, "sourceGUID")
    local isPlayer = type(guid) == "string" and guid:find("^Player%-") ~= nil
    -- NPC-namn kan ha flera bindestreck och ska inte skrivas om, men Anna-Berg är en spelare.
    if isPlayer or raw:find("^[^%s%-]+%-[^%s%-]+$") then
        return ns.PlayerName(raw)
    end
    return raw
end

local function EnvironmentName(envType)
    if type(envType) ~= "string" then return "Miljön" end
    return _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. envType:upper()] or envType
end

-- Blizzards eget recap-fönster räknar events[1] som det dödande slaget.
function ns.ParseRecap(events)
    local first = events[1]
    if type(first) ~= "table" then return nil end

    local info = {
        stamp = Field(first, "timestamp"),
        spellId = Field(first, "spellId"),
        spell = ns.Clean(Field(first, "spellName"), 64),
        amount = Field(first, "amount"),
        overkill = Field(first, "overkill"),
        ktype = "unknown",
    }

    local eventType = Field(first, "event")
    if eventType == "ENVIRONMENTAL_DAMAGE" then
        info.killer = ns.Clean(EnvironmentName(Field(first, "environmentalType")), 64)
        info.ktype = "env"
        info.spell = nil
    else
        if eventType == "SWING_DAMAGE" then
            info.spell = ns.Clean(ACTION_SWING, 64) or "Närstrid"
            info.spellId = Constants and Constants.DeathRecapConsts
                and Constants.DeathRecapConsts.SWING_DAMAGE_SPELL_ID or info.spellId
        end
        info.killer = SourceName(first)
        if info.killer then
            info.ktype, info.kclass = Classify(first, info.killer)
        end
    end

    if type(info.amount) ~= "number" then info.amount = nil end
    if type(info.overkill) ~= "number" or info.overkill < 0 then info.overkill = nil end
    if type(info.spellId) ~= "number" then info.spellId = nil end

    local assists, added = {}, {}
    for i = 2, #events do
        local ev = events[i]
        if type(ev) == "table" then
            local name = SourceName(ev)
            local isMob = name and Classify(ev, name) == "npc"
            if name and not isMob and name ~= info.killer and not added[name] and #assists < 3 then
                added[name] = true
                assists[#assists + 1] = name
            end
        end
    end
    if #assists > 0 then info.assists = assists end
    return info
end

local function Finish(death, info)
    pending = nil
    if not info then
        -- Det går inte att veta om det var en spelare, så inget sparas. Säg till en gång.
        if not warnedUnreadable then
            warnedUnreadable = true
            ns.Print("Kunde inte läsa vem som dödade dig. Kör /sb debug och skicka utskriften.")
        end
        return
    end
    if type(info.stamp) == "number" then ns.db.lastKillStamp = info.stamp end
    -- Bara spelare räknas. Mobs och miljöskada ger varken rad, popup eller synk.
    if not info.killer or info.ktype == "npc" or info.ktype == "env" then return end
    local rec = {
        id = ns.MakeId(death.victim, death.ts),
        ts = death.ts,
        victim = death.victim,
        vclass = death.vclass,
        zone = death.zone,
        subzone = death.subzone,
        killer = info.killer,
        ktype = info.ktype,
        kclass = info.kclass,
        spell = info.spell,
        spellId = info.spellId,
        amount = info.amount,
        overkill = info.overkill,
        assists = info.assists,
        source = "self",
    }
    ns.AddDeath(rec)
    if ns.ShowToast then ns.ShowToast(rec) end
    ns.Broadcast(rec)
end

local function TryRead(death, attempt)
    if pending ~= death then return end
    local info
    local ok, events = pcall(GetRecapEvents)
    if ok and events then
        local parsedOk, parsed = pcall(ns.ParseRecap, events)
        if parsedOk then info = parsed end
    end
    -- Recapen kan vara kvar från förra dödsfallet, som kan ha skett i en BG vi inte läste.
    if info and type(info.stamp) == "number" then
        local isSame = info.stamp == ns.db.lastKillStamp
        local isOld = info.stamp > MIN_EPOCH and death.ts - info.stamp > MAX_RECAP_AGE
        if isSame or isOld then info = nil end
    end
    if info then
        Finish(death, info)
    elseif RETRY_DELAYS[attempt] then
        C_Timer.After(RETRY_DELAYS[attempt], function() TryRead(death, attempt + 1) end)
    else
        Finish(death, nil)
    end
end

local function OnPlayerDead()
    if not ns.IsOpenWorld() or pending then return end
    local now = GetTime()
    -- PLAYER_DEAD kan fyras vid inloggning om karaktären redan ligger död.
    if now - enteredAt < LOGIN_GRACE or now - lastDeathAt < DEATH_DEDUPE then return end
    lastDeathAt = now
    -- Den du slogs mot är ofta din target, och det hjälper att känna igen en mob.
    pcall(ns.ObserveUnit, "target")
    pcall(ns.ObserveUnit, "mouseover")

    local _, class = UnitClass("player")
    local death = {
        ts = GetServerTime(),
        victim = ns.playerName,
        vclass = Safe(class),
        zone = ns.Clean(GetRealZoneText(), 64),
        subzone = ns.Clean(GetSubZoneText(), 64),
    }
    pending = death
    TryRead(death, 1)
end

-- Kommer ihåg fiender du sett: klassen färgar spelarnas namn, och mobs kan sorteras bort.
function ns.ObserveUnit(unit)
    if not UnitExists(unit) or not Safe(UnitCanAttack("player", unit)) then return end
    local isPlayer = Safe(UnitIsPlayer(unit))
    if isPlayer == nil then return end
    local classes, npcs = ns.db.classes, ns.db.npcs
    if not isPlayer then
        -- Mobnamn skrivs inte om, eftersom de kan ha flera ord och bindestreck.
        local name = ns.Clean(UnitName(unit), 64)
        if not name or classes[name] or npcs[name] then return end
        npcCount = npcCount + 1
        if npcCount > MAX_CLASS_CACHE then
            wipe(npcs)
            npcCount = 1
        end
        npcs[name] = true
        return
    end
    local name = ns.PlayerName(UnitName(unit))
    local _, class = UnitClass(unit)
    class = Safe(class)
    if not name or type(class) ~= "string" then return end
    npcs[name] = nil
    if not classes[name] then
        classCount = classCount + 1
        if classCount > MAX_CLASS_CACHE then
            wipe(classes)
            classCount = 1
        end
    end
    classes[name] = class
end

local function UpdateActive()
    local shouldBeActive = ns.IsOpenWorld()
    if shouldBeActive == active then return end
    active = shouldBeActive
    for _, event in ipairs(PASSIVE_EVENTS) do
        if active then
            frame:RegisterEvent(event)
        else
            frame:UnregisterEvent(event)
        end
    end
    if active then
        ns.ResumeSync()
        ns.ScheduleChannelJoin()
    else
        pending = nil
        if ns.HideToast then ns.HideToast() end
    end
end

function ns.IsActive()
    return active
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ns.ADDON then
            ns.InitDB()
            for _ in pairs(ns.db.classes) do classCount = classCount + 1 end
            for _ in pairs(ns.db.npcs) do npcCount = npcCount + 1 end
            frame:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        ns.playerName = ns.PlayerName(UnitName("player"))
        ns.InitSync()
        if ns.InitMinimapButton then ns.InitMinimapButton() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        enteredAt = GetTime()
        UpdateActive()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        UpdateActive()
    elseif event == "PLAYER_DEAD" then
        OnPlayerDead()
    elseif event == "CHAT_MSG_ADDON" then
        ns.OnAddonMessage(...)
    elseif event == "PLAYER_TARGET_CHANGED" then
        pcall(ns.ObserveUnit, "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        pcall(ns.ObserveUnit, "mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        pcall(ns.ObserveUnit, (...))
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
