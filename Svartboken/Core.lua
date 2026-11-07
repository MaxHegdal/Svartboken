-- Svartboken: data, hjälpfunktioner och statistik.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.PREFIX = "SVARTBOKEN"
ns.MAX_DEATHS = 2000
ns.MAX_NOTE = 120
ns.UNKNOWN = "Okänd"
ns.DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"

ns.C = {
    bg      = { 0.047, 0.047, 0.063, 0.97 },
    panel   = { 0.086, 0.086, 0.110, 1 },
    hover   = { 0.140, 0.140, 0.175, 1 },
    line    = { 0.190, 0.190, 0.230, 1 },
    accent  = { 0.860, 0.120, 0.180, 1 },
    text    = { 0.930, 0.930, 0.950, 1 },
    muted   = { 0.560, 0.560, 0.620, 1 },
    gold    = { 1.000, 0.780, 0.300, 1 },
}

local DEFAULTS = {
    toast = true,
    toastSeconds = 8,
    sync = true,
    guildSync = false,
    wanted = true,
    wantedSound = true,
    minimapAngle = 215,
    minimapHidden = false,
}

local MAX_DIAG = 200
local seen = {}

-- Klienten kan returnera "secret values" som addons inte får läsa eller skicka vidare.
function ns.Safe(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then
        return nil
    end
    return v
end

function ns.Clean(s, maxBytes)
    s = ns.Safe(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[%c|~]", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if maxBytes and #s > maxBytes then
        -- Klipp aldrig mitt i ett UTF-8-tecken.
        local cut = maxBytes
        while cut > 0 do
            local nextByte = s:byte(cut + 1)
            if nextByte and nextByte >= 0x80 and nextByte < 0xC0 then
                cut = cut - 1
            else
                break
            end
        end
        s = s:sub(1, cut)
    end
    if s == "" then return nil end
    return s
end

-- Forever-namn är "Förnamn Efternamn". Spelet skriver dem ibland med bindestreck (Anna-Berg),
-- och UnitName kan ge förnamn och efternamn som två värden. Här blir alla former samma namn.
function ns.PlayerName(name, surname)
    name = ns.Clean(name, 64)
    if not name then return nil end
    surname = ns.Clean(surname, 64)
    if surname then name = name .. " " .. surname end
    local first, second = name:match("^([^%s%-]+)[%s%-]+([^%s%-]+)")
    if first then return first .. " " .. second end
    return (name:gsub("[%s%-]+$", ""))
end

-- Luas lower() rör bara a-z, så Å, Ä och Ö måste göras om för hand.
function ns.Lower(s)
    return (s:lower():gsub("Å", "å"):gsub("Ä", "ä"):gsub("Ö", "ö"))
end

-- Negativt om a är äldre än b, positivt om a är nyare, nil om någon version är ogiltig.
function ns.CompareVersions(a, b)
    local a1, a2, a3 = tostring(a):match("^(%d+)%.(%d+)%.(%d+)$")
    local b1, b2, b3 = tostring(b):match("^(%d+)%.(%d+)%.(%d+)$")
    if not a1 or not b1 then return nil end
    local function Delta(x, y) return tonumber(x) - tonumber(y) end
    local d = Delta(a1, b1)
    if d == 0 then d = Delta(a2, b2) end
    if d == 0 then d = Delta(a3, b3) end
    return d
end

ns.VERSION = "0.0.0"
if C_AddOns and C_AddOns.GetAddOnMetadata then
    local ok, version = pcall(C_AddOns.GetAddOnMetadata, ADDON, "Version")
    if ok and type(version) == "string" then ns.VERSION = version end
end

-- Endast open world: aldrig i BG, arena, dungeon, raid eller scenario.
function ns.IsOpenWorld()
    local inInstance, instanceType = IsInInstance()
    if inInstance then return false end
    return instanceType == nil or instanceType == "none"
end

function ns.Print(msg)
    print("|cffdb1f2eSvartboken|r " .. tostring(msg))
end

function ns.Describe(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "<SECRET>" end
    return tostring(v)
end

-- Diagnoslogg i sparfilen, så att fel går att felsöka efter en /reload utan att kopiera ur chatten.
function ns.Diag(text)
    local db = ns.db
    if not db then return end
    local log = db.diag
    log[#log + 1] = date("%H:%M:%S ") .. tostring(text)
    while #log > MAX_DIAG do table.remove(log, 1) end
end

function ns.DescribeEvent(event)
    local keys, parts = {}, {}
    for key in pairs(event) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for i, key in ipairs(keys) do parts[i] = key .. "=" .. ns.Describe(event[key]) end
    return table.concat(parts, " ")
end

function ns.InitDB()
    if type(SvartbokenDB) ~= "table" then SvartbokenDB = {} end
    local db = SvartbokenDB
    db.deaths = type(db.deaths) == "table" and db.deaths or {}
    db.classes = type(db.classes) == "table" and db.classes or {}
    db.notes = type(db.notes) == "table" and db.notes or {}
    db.gang = type(db.gang) == "table" and db.gang or {}
    db.gangRemoved = type(db.gangRemoved) == "table" and db.gangRemoved or {}
    db.npcs = type(db.npcs) == "table" and db.npcs or {}
    db.diag = type(db.diag) == "table" and db.diag or {}
    db.settings = type(db.settings) == "table" and db.settings or {}
    for k, v in pairs(DEFAULTS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    db.settings.channelSync = nil
    ns.db = db
    wipe(seen)
    -- Äldre versioner sparade även mobs, miljöskada och okända mördare.
    for i = #db.deaths, 1, -1 do
        local d = db.deaths[i]
        if not d.killer or d.ktype == "npc" or d.ktype == "env" then
            table.remove(db.deaths, i)
        end
    end
    local hasDemo = false
    for _, d in ipairs(db.deaths) do
        if d.id then seen[d.id] = true end
        if d.demo then hasDemo = true end
    end
    -- En demo-anteckning utan demo-rader är en rest från en äldre version.
    if not hasDemo then
        for name, note in pairs(db.notes) do
            if note.demo then db.notes[name] = nil end
        end
    end
    -- Äldre versioner sparade gänget som Förnamn-Efternamn.
    for i, name in ipairs(db.gang) do
        db.gang[i] = ns.PlayerName(name) or name
    end
end

function ns.MakeId(victim, ts)
    return tostring(victim) .. ":" .. tostring(ts)
end

function ns.HasDeath(id)
    return seen[id] == true
end

-- Returnerar true om dödsfallet var nytt.
function ns.AddDeath(rec)
    if not rec.id or seen[rec.id] then return false end
    seen[rec.id] = true
    local deaths = ns.db.deaths
    deaths[#deaths + 1] = rec
    table.sort(deaths, function(a, b) return a.ts > b.ts end)
    while #deaths > ns.MAX_DEATHS do
        local removed = table.remove(deaths)
        if removed.id then seen[removed.id] = nil end
    end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

function ns.RemoveDeaths(predicate)
    local deaths = ns.db.deaths
    for i = #deaths, 1, -1 do
        if not predicate or predicate(deaths[i]) then
            local removed = table.remove(deaths, i)
            if removed.id then seen[removed.id] = nil end
        end
    end
    if ns.RefreshUI then ns.RefreshUI() end
end

-- Anteckningar hör till en mördare. Senaste ändringen vinner, även en borttagning.
function ns.GetNote(killer)
    local note = killer and ns.db.notes[killer]
    if note and note.text then return note end
    return nil
end

function ns.ApplyNote(killer, text, author, ts)
    local existing = ns.db.notes[killer]
    if existing and existing.ts >= ts then return false end
    ns.db.notes[killer] = { text = text, author = author, ts = ts }
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

-- Sparar din egen anteckning. Tom text tar bort den.
function ns.SaveNote(killer, text)
    text = ns.Clean(text, ns.MAX_NOTE)
    local existing = ns.db.notes[killer]
    local ts = GetServerTime()
    if existing and ts <= existing.ts then ts = existing.ts + 1 end
    ns.ApplyNote(killer, text, ns.playerName, ts)
    ns.BroadcastNote(killer)
end

function ns.PeriodCutoff(period)
    if period == "today" then
        local t = date("*t")
        return time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
    elseif period == "week" then
        return GetServerTime() - 7 * 86400
    end
    return 0
end

function ns.Filtered(period)
    local cutoff = ns.PeriodCutoff(period)
    local out = {}
    for _, d in ipairs(ns.db.deaths) do
        if d.ts >= cutoff then
            out[#out + 1] = d
        end
    end
    return out
end

local function TopEntry(map)
    local bestKey, bestCount = nil, 0
    for key, count in pairs(map) do
        if count > bestCount or (count == bestCount and bestKey and key < bestKey) then
            bestKey, bestCount = key, count
        end
    end
    return bestKey, bestCount
end
ns.TopEntry = TopEntry

-- Bygger topplistan med mördare och listan med gängmedlemmar.
function ns.BuildStats(deaths)
    local killers, members, killerList, memberList = {}, {}, {}, {}
    for _, d in ipairs(deaths) do
        local name = d.killer or ns.UNKNOWN
        local k = killers[name]
        if not k then
            k = { name = name, known = d.killer ~= nil, ktype = d.ktype, kclass = d.kclass,
                  count = 0, victims = {}, spells = {}, lastTs = 0 }
            killers[name] = k
            killerList[#killerList + 1] = k
        end
        k.count = k.count + 1
        k.kclass = k.kclass or d.kclass
        k.victims[d.victim] = (k.victims[d.victim] or 0) + 1
        if d.spell then k.spells[d.spell] = (k.spells[d.spell] or 0) + 1 end
        if d.ts > k.lastTs then
            k.lastTs, k.lastZone = d.ts, d.zone
        end

        local m = members[d.victim]
        if not m then
            m = { name = d.victim, class = d.vclass, deaths = 0, killers = {}, lastTs = 0 }
            members[d.victim] = m
            memberList[#memberList + 1] = m
        end
        m.deaths = m.deaths + 1
        m.class = m.class or d.vclass
        if d.ts > m.lastTs then m.lastTs = d.ts end
        if d.killer then m.killers[d.killer] = (m.killers[d.killer] or 0) + 1 end
    end

    table.sort(killerList, function(a, b)
        if a.known ~= b.known then return a.known end
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    table.sort(memberList, function(a, b)
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end
        return a.name < b.name
    end)
    for _, m in ipairs(memberList) do
        m.topKiller, m.topCount = TopEntry(m.killers)
    end
    return killerList, memberList
end

-- Antal gånger en mördare dödat dig och resten av gänget.
function ns.CountKills(killer, me)
    local mine, all = 0, 0
    if not killer then return mine, all end
    for _, d in ipairs(ns.db.deaths) do
        if d.killer == killer then
            all = all + 1
            if d.victim == me then mine = mine + 1 end
        end
    end
    return mine, all
end

-- En spelare heter ett eller två ord, beroende på om källan tar med efternamnet.
-- Tre ord eller flera bindestreck kan bara vara en mob.
function ns.CouldBePlayerName(name)
    if type(name) ~= "string" then return false end
    return name:find("^[^%s%-]+$") ~= nil or name:find("^[^%s%-]+ [^%s%-]+$") ~= nil
end

function ns.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return nil
end

function ns.NameColor(class, ktype)
    local r, g, b = ns.ClassColor(class)
    if r then return r, g, b end
    if ktype == "npc" or ktype == "env" then return 0.72, 0.72, 0.76 end
    return 0.93, 0.93, 0.95
end

function ns.FormatNumber(n)
    n = tonumber(n)
    if not n then return "" end
    local s = tostring(math.floor(n))
    while true do
        local replaced, count = s:gsub("^(%d+)(%d%d%d)", "%1 %2")
        s = replaced
        if count == 0 then return s end
    end
end

function ns.TimeAgo(ts)
    local diff = GetServerTime() - (ts or 0)
    if diff < 60 then return "nyss" end
    if diff < 3600 then return math.floor(diff / 60) .. " min" end
    if diff < 86400 then return math.floor(diff / 3600) .. " tim" end
    return math.floor(diff / 86400) .. " d"
end

function ns.SpellIcon(spellId)
    if spellId and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellId)
        tex = ok and ns.Safe(tex) or nil
        if tex then return tex end
    end
    return ns.DEFAULT_ICON
end
