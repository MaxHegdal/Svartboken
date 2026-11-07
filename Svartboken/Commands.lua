-- Svartboken: slash-kommandon, testläge och felsökning.
local _, ns = ...

local DEMO_KILLERS = {
    { "Skugg Tass", "ROGUE", "Ambush" },
    { "Frost Magnus", "MAGE", "Frostbolt" },
    { "Bosse Brak", "WARRIOR", "Mortal Strike" },
    { "Natt Siv", "WARLOCK", "Shadow Bolt" },
}
local DEMO_VICTIMS = { { "Kompis Ek", "PALADIN" }, { "Bror Ek", "HUNTER" }, { "Syrran Ek", "PRIEST" } }
local DEMO_ZONES = { "Stranglethorn Vale", "Hillsbrad Foothills", "Tanaris", "Searing Gorge" }
local DEMO_NOTE = "Campar flightmastern i Booty Bay, går på den som är ensam"

function ns.SampleDeath()
    local killer = DEMO_KILLERS[1]
    return {
        victim = ns.playerName or "Du Själv",
        killer = killer[1],
        kclass = killer[2],
        ktype = "player",
        spell = killer[3],
        amount = 1245,
        overkill = 312,
        assists = { "Frost Magnus" },
        note = DEMO_NOTE,
    }
end

local function AddDemoData()
    local now = GetServerTime()
    for i = 1, 24 do
        local killer = DEMO_KILLERS[(i * i) % #DEMO_KILLERS + 1]
        local victim = DEMO_VICTIMS[i % #DEMO_VICTIMS + 1]
        local ts = now - i * 5400
        ns.AddDeath({
            id = "demo:" .. i,
            ts = ts,
            victim = victim[1],
            vclass = victim[2],
            killer = killer[1],
            kclass = killer[2],
            ktype = "player",
            spell = killer[3],
            amount = 900 + i * 37,
            overkill = i * 11,
            zone = DEMO_ZONES[i % #DEMO_ZONES + 1],
            demo = true,
        })
    end
    local name = DEMO_KILLERS[1][1]
    if not ns.db.notes[name] then
        ns.db.notes[name] = { text = DEMO_NOTE, author = DEMO_VICTIMS[1][1], ts = now - 3600, demo = true }
    end
    if ns.RefreshUI then ns.RefreshUI() end
end

local function RemoveDemoData()
    for name, note in pairs(ns.db.notes) do
        if note.demo then ns.db.notes[name] = nil end
    end
    ns.RemoveDeaths(function(d) return d.demo end)
end

local Describe = ns.Describe

-- Skriver ut exakt vad klienten ger addonet, så att det går att felsöka i spelet.
local function Debug()
    local inInstance, instanceType = IsInInstance()
    ns.Print("Build: " .. Describe((select(1, GetBuildInfo()))) .. "  Interface: " .. Describe((select(4, GetBuildInfo()))))
    ns.Print("Open world: " .. tostring(ns.IsOpenWorld()) .. "  Aktiv: " .. tostring(ns.IsActive())
        .. "  Instans: " .. Describe(inInstance) .. "/" .. Describe(instanceType))
    if C_ChatInfo.InChatMessagingLockdown then
        ns.Print("Chat lockdown: " .. Describe(C_ChatInfo.InChatMessagingLockdown()))
    end
    local rawName, rawSecond = UnitName("player")
    ns.Print("Version: " .. ns.VERSION .. "  Namn: " .. Describe(ns.playerName)
        .. "  UnitName: " .. Describe(rawName) .. " / " .. Describe(rawSecond))
    ns.Print("Senaste sändning: " .. Describe(ns.lastSendResult))
    if not C_DeathRecap then
        ns.Print("C_DeathRecap saknas i den här klienten.")
        return
    end
    ns.Print("HasRecapEvents: " .. Describe(C_DeathRecap.HasRecapEvents()))
    local events = ns.GetRecapEvents()
    if not events then
        ns.Print("Inga läsbara recap-events. Dö en gång och kör /sb debug igen.")
        return
    end
    ns.Print("Antal recap-events: " .. #events)
    if type(events[1]) == "table" then
        local keys = {}
        for k in pairs(events[1]) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            ns.Print("  " .. k .. " = " .. Describe(events[1][k]))
        end
    end
end

local function SetFlag(key, value, label)
    if value == "on" or value == "på" then
        ns.db.settings[key] = true
    elseif value == "off" or value == "av" then
        ns.db.settings[key] = false
    else
        ns.db.settings[key] = not ns.db.settings[key]
    end
    ns.Print(label .. ": " .. (ns.db.settings[key] and "på" or "av"))
    if ns.RefreshUI then ns.RefreshUI() end
end

local function Help()
    ns.Print("/sb  öppna eller stäng fönstret")
    ns.Print("/sb test  visa popupen en gång")
    ns.Print("/sb flytta  flytta popupen")
    ns.Print("/sb popup | synk | guild [på/av]")
    ns.Print("/sb efterlyst test  visa provruta  ·  /sb efterlyst [på/av]  ·  /sb efterlyst ljud [på/av]")
    ns.Print("/sb synktest  samma som knappen Testa")
    ns.Print("/sb gäng  öppna gänglistan  ·  /sb gäng add Anna Berg  ·  /sb gäng del Anna Berg")
    ns.Print("/sb demo  lägg till påhittade rader  ·  /sb demo av  ta bort dem")
    ns.Print("/sb minimap  visa eller dölj minimapknappen")
    ns.Print("/sb debug  visa vad klienten ger addonet")
end

SLASH_SVARTBOKEN1 = "/svartboken"
SLASH_SVARTBOKEN2 = "/sb"
SlashCmdList.SVARTBOKEN = function(input)
    -- Namn ska behålla sina versaler, så bara kommandot och argumentet för jämförelse görs om.
    local cmd, rawArg = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = ns.Lower(cmd)
    local arg = ns.Lower(rawArg)
    if cmd == "" then
        ns.ToggleWindow()
    elseif cmd == "synktest" then
        local ok, reason = ns.RunSyncTest()
        if not ok then ns.Print(reason) end
    elseif cmd == "gäng" or cmd == "gang" then
        local action, name = rawArg:match("^(%S+)%s+(.+)$")
        action = action and ns.Lower(action)
        if action == "add" then
            local ok, reason = ns.AddGang(name)
            ns.Print(ok and (ns.PlayerName(name) .. " är med i gänget.") or reason)
        elseif action == "del" then
            ns.Print(ns.RemoveGang(name) and (name .. " är borttagen.") or (name .. " finns inte i gänget."))
        else
            ns.OpenGangPanel()
        end
    elseif cmd == "test" then
        ns.ShowToast(ns.SampleDeath(), true)
    elseif cmd == "flytta" or cmd == "move" then
        if arg == "reset" then
            ns.ResetToastPosition()
            ns.Print("Popupen är tillbaka på standardplatsen.")
        else
            ns.Print(ns.ToggleToastMove() and "Dra rutan dit du vill ha den. Skriv /sb flytta för att låsa." or "Popupen är låst.")
        end
    elseif cmd == "efterlyst" then
        if arg == "test" then
            ns.ShowWantedSample()
        elseif arg == "ljud" or arg == "ljud på" or arg == "ljud av" then
            SetFlag("wantedSound", arg:match("^ljud (.+)$"), "Efterlyst-ljud")
        else
            SetFlag("wanted", arg, "Efterlyst")
            if not ns.db.settings.wanted then ns.ClearWanted() end
        end
    elseif cmd == "popup" then
        SetFlag("toast", arg, "Popup")
    elseif cmd == "synk" or cmd == "sync" then
        SetFlag("sync", arg, "Synk")
    elseif cmd == "guild" then
        SetFlag("guildSync", arg, "Guild-synk")
    elseif cmd == "demo" then
        if arg == "av" or arg == "off" then
            RemoveDemoData()
            ns.Print("Demo-raderna är borttagna.")
        else
            AddDemoData()
            ns.Print("Demo-rader tillagda. /sb demo av tar bort dem.")
            ns.ToggleWindow(true)
        end
    elseif cmd == "minimap" then
        ns.Print("Minimapknapp: " .. (ns.ToggleMinimapButton() and "på" or "av"))
    elseif cmd == "debug" then
        Debug()
    else
        Help()
    end
end
