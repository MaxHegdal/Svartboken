-- Svartboken: huvudfönstret. Öppnas bara manuellt.
local _, ns = ...

local C = ns.C
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"

local WIDTH, HEIGHT = 740, 540
local ROW_HEIGHT, VISIBLE_ROWS = 30, 10
local PADDING = 16

local window
local state = { tab = "killers", period = "all", offset = 0, rows = {} }

local function Text(parent, size, color, flags, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, flags or "")
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Fill(parent, color, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return t
end

local function Button(parent, width, height, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b.bg = Fill(b, C.panel)
    b.bg:SetAllPoints()
    b.underline = Fill(b, C.accent, "ARTWORK")
    b.underline:SetPoint("BOTTOMLEFT")
    b.underline:SetPoint("BOTTOMRIGHT")
    b.underline:SetHeight(2)
    b.underline:Hide()
    b.text = Text(b, 11, C.muted, nil, "CENTER")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetText(label)

    function b:SetActive(isActive)
        self.isActive = isActive
        self.underline:SetShown(isActive)
        local color = isActive and C.text or C.muted
        self.text:SetTextColor(color[1], color[2], color[3], 1)
    end

    b:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1)
        self.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
        local color = self.isActive and C.text or C.muted
        self.text:SetTextColor(color[1], color[2], color[3], 1)
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Kolumner per flik: { x, bredd, justering }.
local COLUMNS = {
    killers = {
        { 12, 26, "LEFT" },     -- placering
        { 42, 190, "LEFT" },    -- namn
        { 236, 44, "RIGHT" },   -- antal
        { 296, 210, "LEFT" },   -- offer
        { 512, 180, "RIGHT" },  -- senast
    },
    log = {
        { 12, 44, "LEFT" },     -- tid
        { 60, 110, "LEFT" },    -- offer
        { 172, 150, "LEFT" },   -- mördare
        { 352, 140, "LEFT" },   -- spell
        { 496, 196, "RIGHT" },  -- zon
    },
    members = {
        { 12, 26, "LEFT" },     -- placering
        { 42, 170, "LEFT" },    -- namn
        { 216, 44, "RIGHT" },   -- antal
        { 276, 300, "LEFT" },   -- värsta fiende
        { 582, 110, "RIGHT" },  -- senast
    },
}

local function SetColor(fs, r, g, b)
    fs:SetTextColor(r, g, b, 1)
end

local function NoteTooltip(killer)
    if not killer then return end
    local note = ns.GetNote(killer)
    GameTooltip:AddLine(" ")
    if note then
        GameTooltip:AddLine(note.text, C.gold[1], C.gold[2], C.gold[3], true)
        GameTooltip:AddLine((note.author or "?") .. ", " .. ns.TimeAgo(note.ts), 0.6, 0.6, 0.65)
    end
    GameTooltip:AddLine("Klicka för att skriva en anteckning.", 0.6, 0.6, 0.65)
end

-- Rutan där anteckningen skrivs. Sparas och delas först när du trycker Spara.
local function BuildNoteEditor()
    local e = CreateFrame("Frame", nil, window)
    e:SetSize(440, 132)
    e:SetPoint("CENTER")
    e:SetFrameLevel(window:GetFrameLevel() + 40)
    e:EnableMouse(true)
    e:Hide()

    local bg = Fill(e, C.bg)
    bg:SetAllPoints()
    local edgeTop = Fill(e, C.accent, "ARTWORK")
    edgeTop:SetPoint("TOPLEFT")
    edgeTop:SetPoint("TOPRIGHT")
    edgeTop:SetHeight(2)
    local edgeBottom = Fill(e, C.line, "ARTWORK")
    edgeBottom:SetPoint("BOTTOMLEFT")
    edgeBottom:SetPoint("BOTTOMRIGHT")
    edgeBottom:SetHeight(1)

    e.title = Text(e, 13, C.text)
    e.title:SetPoint("TOPLEFT", 14, -14)
    e.title:SetPoint("RIGHT", e, "RIGHT", -14, 0)

    e.meta = Text(e, 10, C.muted)
    e.meta:SetPoint("TOPLEFT", e.title, "BOTTOMLEFT", 0, -3)
    e.meta:SetPoint("RIGHT", e, "RIGHT", -14, 0)

    local inputBg = CreateFrame("Frame", nil, e)
    inputBg:SetPoint("TOPLEFT", 14, -52)
    inputBg:SetPoint("TOPRIGHT", -14, -52)
    inputBg:SetHeight(28)
    local inputFill = Fill(inputBg, C.panel)
    inputFill:SetAllPoints()

    e.input = CreateFrame("EditBox", nil, inputBg)
    e.input:SetPoint("LEFT", 8, 0)
    e.input:SetPoint("RIGHT", -8, 0)
    e.input:SetHeight(24)
    e.input:SetFont(FONT, 12, "")
    e.input:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    e.input:SetAutoFocus(false)
    e.input:SetMaxBytes(ns.MAX_NOTE + 1)

    local function Save()
        ns.SaveNote(e.killer, e.input:GetText())
        e:Hide()
    end
    e.input:SetScript("OnEnterPressed", Save)
    e.input:SetScript("OnEscapePressed", function() e:Hide() end)

    local cancel = Button(e, 70, 24, "Avbryt", function() e:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT", -14, 14)
    local save = Button(e, 70, 24, "Spara", Save)
    save:SetPoint("RIGHT", cancel, "LEFT", -2, 0)
    local remove = Button(e, 80, 24, "Ta bort", function()
        ns.SaveNote(e.killer, "")
        e:Hide()
    end)
    remove:SetPoint("BOTTOMLEFT", 14, 14)
    e.remove = remove

    e:SetScript("OnHide", function() e.input:ClearFocus() end)
    return e
end

local function OpenNoteEditor(killer)
    if not killer then return end
    local e = window.noteEditor
    if not e then
        e = BuildNoteEditor()
        window.noteEditor = e
    end
    local note = ns.GetNote(killer)
    e.killer = killer
    e.title:SetText("Anteckning om " .. killer)
    if note then
        e.meta:SetText("Senast av " .. (note.author or "?") .. ", " .. ns.TimeAgo(note.ts))
    elseif ns.db.settings.sync then
        e.meta:SetText("Delas med gänget när du sparar")
    else
        e.meta:SetText("Synk är av, så anteckningen stannar hos dig")
    end
    e.input:SetText(note and note.text or "")
    e.remove:SetShown(note ~= nil)
    e:Show()
    e.input:SetFocus()
end

-- Gänglistan: namn som får dödsfall och anteckningar även utan grupp.
local GANG_ROWS = 12
local GANG_ROW_HEIGHT = 22

local function RenderGangPanel()
    local p = window and window.gangPanel
    if not p or not p:IsShown() then return end
    for i, row in ipairs(p.rows) do
        local name = ns.db.gang[i]
        row.name = name
        if name then
            row.label:SetText(name)
            local status, kind = ns.GangStatus(name)
            row.status:SetText(status)
            if kind == "good" then
                row.status:SetTextColor(0.35, 0.85, 0.45, 1)
            else
                row.status:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
            end
            row:Show()
        else
            row:Hide()
        end
    end
    p.empty:SetShown(#ns.db.gang == 0)

    if ns.testResult then
        p.channel:SetText(ns.testResult)
    elseif ns.ChannelActive() then
        local names = ns.ChannelPeers()
        if #names > 0 then
            p.channel:SetText("Kanal ansluten. Hörda: " .. table.concat(names, ", "))
        else
            p.channel:SetText("Kanal ansluten. Tryck Testa för att se vilka som svarar.")
        end
    elseif ns.db.settings.channelSync then
        p.channel:SetText("Kanalen är inte ansluten. Grupp och lista används så länge.")
    else
        p.channel:SetText("Kanalen är avstängd. Grupp och lista används.")
    end
end

local function BuildGangPanel()
    local p = CreateFrame("Frame", nil, window)
    p:SetSize(460, 146 + GANG_ROWS * GANG_ROW_HEIGHT)
    p:SetPoint("CENTER")
    p:SetFrameLevel(window:GetFrameLevel() + 40)
    p:EnableMouse(true)
    p:Hide()

    local bg = Fill(p, C.bg)
    bg:SetAllPoints()
    local edgeTop = Fill(p, C.accent, "ARTWORK")
    edgeTop:SetPoint("TOPLEFT")
    edgeTop:SetPoint("TOPRIGHT")
    edgeTop:SetHeight(2)
    local edgeBottom = Fill(p, C.line, "ARTWORK")
    edgeBottom:SetPoint("BOTTOMLEFT")
    edgeBottom:SetPoint("BOTTOMRIGHT")
    edgeBottom:SetHeight(1)

    local title = Text(p, 13, C.text)
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText("Gänglista")

    local hint = Text(p, 10, C.muted)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    hint:SetText("Alla med addonet hittar varandra själva. Listan är reserv om kanalen inte fungerar.")

    local inputBg = CreateFrame("Frame", nil, p)
    inputBg:SetPoint("TOPLEFT", 14, -52)
    inputBg:SetSize(226, 26)
    local inputFill = Fill(inputBg, C.panel)
    inputFill:SetAllPoints()

    p.input = CreateFrame("EditBox", nil, inputBg)
    p.input:SetPoint("LEFT", 8, 0)
    p.input:SetPoint("RIGHT", -8, 0)
    p.input:SetHeight(22)
    p.input:SetFont(FONT, 12, "")
    p.input:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    p.input:SetAutoFocus(false)
    p.input:SetMaxBytes(65)

    local function Add(name)
        local ok, reason = ns.AddGang(name)
        if ok then
            p.input:SetText("")
        else
            ns.Print(reason)
        end
        RenderGangPanel()
    end

    p.input:SetScript("OnEnterPressed", function(self) Add(self:GetText()) end)
    p.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addButton = Button(p, 76, 26, "Lägg till", function() Add(p.input:GetText()) end)
    addButton:SetPoint("LEFT", inputBg, "RIGHT", 2, 0)

    local targetButton = Button(p, 116, 26, "Lägg till target", function()
        if not UnitExists("target") or not ns.Safe(UnitIsPlayer("target")) then
            ns.Print("Ta en spelare i target först.")
            return
        end
        Add(ns.PlayerName(UnitName("target")))
    end)
    targetButton:SetPoint("LEFT", addButton, "RIGHT", 2, 0)

    p.rows = {}
    for i = 1, GANG_ROWS do
        local row = CreateFrame("Frame", nil, p)
        row:SetHeight(GANG_ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 14, -86 - (i - 1) * GANG_ROW_HEIGHT)
        row:SetPoint("RIGHT", p, "RIGHT", -14, 0)
        local rowBg = Fill(row, C.panel)
        rowBg:SetAllPoints()
        row.label = Text(row, 12, C.text)
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetWidth(200)
        row.status = Text(row, 10, C.muted, nil, "RIGHT")
        row.status:SetPoint("RIGHT", -30, 0)
        row.status:SetWidth(170)
        row.remove = Button(row, 22, GANG_ROW_HEIGHT - 2, "X", function()
            ns.RemoveGang(row.name)
            RenderGangPanel()
        end)
        row.remove:SetPoint("RIGHT")
        p.rows[i] = row
    end

    p.empty = Text(p, 12, C.muted, nil, "CENTER")
    p.empty:SetPoint("TOP", 0, -130)
    p.empty:SetText("Inga namn än.")

    local close = Button(p, 70, 24, "Stäng", function() p:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -14, 14)
    local test = Button(p, 90, 24, "Testa", function()
        local ok, reason = ns.RunSyncTest()
        if not ok then
            ns.testResult = reason
            ns.Print(reason)
        end
        RenderGangPanel()
    end)
    test:SetPoint("RIGHT", close, "LEFT", -2, 0)

    p.channel = Text(p, 10, C.muted)
    p.channel:SetPoint("BOTTOMLEFT", 14, 14)
    p.channel:SetPoint("RIGHT", test, "LEFT", -8, 0)
    p.channel:SetWordWrap(true)

    p:SetScript("OnShow", RenderGangPanel)
    p:SetScript("OnHide", function() p.input:ClearFocus() end)
    return p
end

local function ToggleGangPanel(forceShow)
    if not window.gangPanel then window.gangPanel = BuildGangPanel() end
    local p = window.gangPanel
    if p:IsShown() and not forceShow then
        p:Hide()
    else
        p:Show()
    end
end

local function RowTooltip(row)
    local data = row.data
    if not data then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if row.kind == "killers" then
        local r, g, b = ns.NameColor(data.kclass, data.ktype)
        GameTooltip:AddLine(data.name, r, g, b)
        GameTooltip:AddLine(data.count .. " dödsfall", 1, 1, 1)
        local spell, spellCount = ns.TopEntry(data.spells)
        if spell then
            GameTooltip:AddDoubleLine("Vanligaste attack", spell .. " (" .. spellCount .. ")", 0.6, 0.6, 0.65, 1, 1, 1)
        end
        if data.lastZone then
            GameTooltip:AddDoubleLine("Senast sedd", data.lastZone, 0.6, 0.6, 0.65, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        for victim, count in pairs(data.victims) do
            GameTooltip:AddDoubleLine(victim, count .. " ggr", 0.85, 0.85, 0.9, 1, 1, 1)
        end
        if data.known then NoteTooltip(data.name) end
    elseif row.kind == "log" then
        local r, g, b = ns.NameColor(data.kclass, data.ktype)
        GameTooltip:AddLine(data.killer or ns.UNKNOWN, r, g, b)
        GameTooltip:AddLine(date("%Y-%m-%d %H:%M", data.ts), 0.6, 0.6, 0.65)
        if data.spell then GameTooltip:AddDoubleLine("Attack", data.spell, 0.6, 0.6, 0.65, 1, 1, 1) end
        if data.amount and data.amount > 0 then
            GameTooltip:AddDoubleLine("Skada", ns.FormatNumber(data.amount), 0.6, 0.6, 0.65, 1, 1, 1)
        end
        if data.overkill and data.overkill > 0 then
            GameTooltip:AddDoubleLine("Overkill", ns.FormatNumber(data.overkill), 0.6, 0.6, 0.65, 1, 1, 1)
        end
        if data.subzone then GameTooltip:AddDoubleLine("Plats", data.subzone, 0.6, 0.6, 0.65, 1, 1, 1) end
        if data.assists and #data.assists > 0 then
            GameTooltip:AddDoubleLine("Assist", table.concat(data.assists, ", "), 0.6, 0.6, 0.65, 1, 1, 1)
        end
        NoteTooltip(data.killer)
    elseif row.kind == "members" then
        local r, g, b = ns.NameColor(data.class)
        GameTooltip:AddLine(data.name, r, g, b)
        GameTooltip:AddLine(data.deaths .. " dödsfall", 1, 1, 1)
        GameTooltip:AddLine(" ")
        for killer, count in pairs(data.killers) do
            GameTooltip:AddDoubleLine(killer, count .. " ggr", 0.85, 0.85, 0.9, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", parent, "RIGHT", -12, 0)

    row.bg = Fill(row, C.panel)
    row.bg:SetAllPoints()
    row.bar = row:CreateTexture(nil, "BORDER")
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT")
    row.accent:SetPoint("BOTTOMLEFT")
    row.accent:SetWidth(3)

    row.cols = {}
    for i = 1, 5 do
        row.cols[i] = Text(row, i == 2 and 13 or 11, C.text)
    end

    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1)
        RowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        local data = self.data
        if not data then return end
        if self.kind == "killers" and data.known then
            GameTooltip:Hide()
            OpenNoteEditor(data.name)
        elseif self.kind == "log" and data.killer then
            GameTooltip:Hide()
            OpenNoteEditor(data.killer)
        end
    end)
    return row
end

local function LayoutRow(row, kind)
    if row.kind == kind then return end
    row.kind = kind
    for i, col in ipairs(COLUMNS[kind]) do
        local fs = row.cols[i]
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", row, "LEFT", col[1], 0)
        fs:SetWidth(col[2])
        fs:SetJustifyH(col[3])
    end
end

local function VictimSummary(victims)
    local list = {}
    for name, count in pairs(victims) do
        list[#list + 1] = { name = name, count = count }
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    local parts = {}
    for i = 1, math.min(3, #list) do
        parts[i] = list[i].name .. " x" .. list[i].count
    end
    if #list > 3 then parts[#parts + 1] = "+" .. (#list - 3) end
    return table.concat(parts, ", ")
end

local function SetBar(row, fraction, r, g, b)
    local rowWidth = WIDTH - 2 * PADDING - 12
    row.bar:SetWidth(math.max(1, rowWidth * fraction))
    row.bar:SetColorTexture(r, g, b, 0.16)
    row.bar:Show()
    row.accent:SetColorTexture(r, g, b, 1)
end

local function FillKillerRow(row, k, rank, max)
    local r, g, b = ns.NameColor(k.kclass, k.ktype)
    SetBar(row, k.count / max, r, g, b)
    row.cols[1]:SetText(k.known and rank or "-")
    SetColor(row.cols[1], C.muted[1], C.muted[2], C.muted[3])
    row.cols[2]:SetText(k.name)
    SetColor(row.cols[2], r, g, b)
    row.cols[3]:SetText(k.count)
    SetColor(row.cols[3], C.text[1], C.text[2], C.text[3])
    -- Anteckningen tar offrens plats på raden. Offren syns fortfarande i tooltipen.
    local note = k.known and ns.GetNote(k.name)
    if note then
        row.cols[4]:SetText(note.text)
        SetColor(row.cols[4], C.gold[1], C.gold[2], C.gold[3])
    else
        row.cols[4]:SetText(VictimSummary(k.victims))
        SetColor(row.cols[4], C.muted[1], C.muted[2], C.muted[3])
    end
    row.cols[5]:SetText(ns.TimeAgo(k.lastTs) .. (k.lastZone and ("  ·  " .. k.lastZone) or ""))
    SetColor(row.cols[5], C.muted[1], C.muted[2], C.muted[3])
end

local function FillLogRow(row, d)
    local vr, vg, vb = ns.NameColor(d.vclass)
    local kr, kg, kb = ns.NameColor(d.kclass, d.ktype)
    row.bar:Hide()
    row.accent:SetColorTexture(kr, kg, kb, 1)
    row.cols[1]:SetText(ns.TimeAgo(d.ts))
    SetColor(row.cols[1], C.muted[1], C.muted[2], C.muted[3])
    row.cols[2]:SetText(d.victim)
    SetColor(row.cols[2], vr, vg, vb)
    row.cols[3]:SetText(d.killer or ns.UNKNOWN)
    SetColor(row.cols[3], kr, kg, kb)
    row.cols[4]:SetText(d.spell or "")
    SetColor(row.cols[4], C.text[1], C.text[2], C.text[3])
    row.cols[5]:SetText(d.zone or "")
    SetColor(row.cols[5], C.muted[1], C.muted[2], C.muted[3])
end

local function FillMemberRow(row, m, rank, max)
    local r, g, b = ns.NameColor(m.class)
    SetBar(row, m.deaths / max, r, g, b)
    row.cols[1]:SetText(rank)
    SetColor(row.cols[1], C.muted[1], C.muted[2], C.muted[3])
    row.cols[2]:SetText(m.name)
    SetColor(row.cols[2], r, g, b)
    row.cols[3]:SetText(m.deaths)
    SetColor(row.cols[3], C.text[1], C.text[2], C.text[3])
    row.cols[4]:SetText(m.topKiller and ("Värsta fiende: " .. m.topKiller .. " (" .. m.topCount .. ")") or "")
    SetColor(row.cols[4], C.muted[1], C.muted[2], C.muted[3])
    row.cols[5]:SetText(ns.TimeAgo(m.lastTs))
    SetColor(row.cols[5], C.muted[1], C.muted[2], C.muted[3])
end

local function RenderRows()
    local w = window
    local total = #state.rows
    local maxOffset = math.max(0, total - VISIBLE_ROWS)
    state.offset = math.min(state.offset, maxOffset)

    local max = 1
    for _, item in ipairs(state.rows) do
        max = math.max(max, item.count or item.deaths or 1)
    end

    for i, row in ipairs(w.rows) do
        local index = i + state.offset
        local item = state.rows[index]
        row.data = item
        if item then
            LayoutRow(row, state.tab)
            if state.tab == "killers" then
                FillKillerRow(row, item, index, max)
            elseif state.tab == "log" then
                FillLogRow(row, item)
            else
                FillMemberRow(row, item, index, max)
            end
            row:Show()
        else
            row:Hide()
        end
    end

    w.empty:SetShown(total == 0)
    w.slider:SetShown(maxOffset > 0)
    w.slider.updating = true
    w.slider:SetMinMaxValues(0, maxOffset)
    w.slider:SetValue(state.offset)
    w.slider.updating = false
end

local function Refresh()
    local w = window
    if not w or not w:IsShown() then return end

    local deaths = ns.Filtered(state.period)
    local killers, members = ns.BuildStats(deaths)

    w.stat1.value:SetText(#deaths)
    local uniqueKillers = 0
    for _, k in ipairs(killers) do
        if k.known then uniqueKillers = uniqueKillers + 1 end
    end
    w.stat2.value:SetText(uniqueKillers)

    local top = killers[1]
    if top and top.known then
        local r, g, b = ns.NameColor(top.kclass, top.ktype)
        w.stat3.value:SetText(top.name)
        w.stat3.value:SetTextColor(r, g, b, 1)
        w.stat3.sub:SetText(top.count .. " dödsfall")
    else
        w.stat3.value:SetText("-")
        w.stat3.value:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        w.stat3.sub:SetText("")
    end

    if state.tab == "killers" then
        state.rows = killers
    elseif state.tab == "log" then
        state.rows = deaths
    else
        state.rows = members
    end

    w.tabKillers:SetActive(state.tab == "killers")
    w.tabLog:SetActive(state.tab == "log")
    w.tabMembers:SetActive(state.tab == "members")
    w.periodToday:SetActive(state.period == "today")
    w.periodWeek:SetActive(state.period == "week")
    w.periodAll:SetActive(state.period == "all")

    local s = ns.db.settings
    w.toggleToast.text:SetText("Popup: " .. (s.toast and "på" or "av"))
    w.toggleSync.text:SetText("Synk: " .. (s.sync and "på" or "av"))
    w.toggleGuild.text:SetText("Guild: " .. (s.guildSync and "på" or "av"))
    w.toggleChannel.text:SetText("Kanal: " .. (s.channelSync and "på" or "av"))

    if ns.newerVersion then
        w.status:SetText("Ny version " .. ns.newerVersion .. " finns, kör Uppdatera-Svartboken")
        w.status:SetTextColor(C.gold[1], C.gold[2], C.gold[3], 1)
    else
        w.status:SetText((ns.IsActive() and "Aktiv i open world" or "Vilar i instans") .. "  ·  v" .. ns.VERSION)
    end
    RenderRows()
    RenderGangPanel()
end
ns.RefreshUI = Refresh

local function SelectTab(tab)
    state.tab, state.offset = tab, 0
    Refresh()
end

local function SelectPeriod(period)
    state.period, state.offset = period, 0
    Refresh()
end

local function CreateStat(parent, label, x, width)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(width, 58)
    s:SetPoint("TOPLEFT", x, -58)
    local bg = Fill(s, C.panel)
    bg:SetAllPoints()
    s.label = Text(s, 9, C.muted)
    s.label:SetPoint("TOPLEFT", 12, -9)
    s.label:SetText(label)
    s.value = Text(s, 19, C.text, "OUTLINE")
    s.value:SetPoint("TOPLEFT", s.label, "BOTTOMLEFT", 0, -5)
    s.value:SetPoint("RIGHT", s, "RIGHT", -70, 0)
    s.sub = Text(s, 10, C.muted, nil, "RIGHT")
    s.sub:SetPoint("BOTTOMRIGHT", -12, 12)
    return s
end

local function Build()
    local w = CreateFrame("Frame", "SvartbokenFrame", UIParent)
    w:SetSize(WIDTH, HEIGHT)
    w:SetPoint("CENTER")
    w:SetFrameStrata("HIGH")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.settings.windowPos = { point, relPoint, x, y }
    end)
    w:Hide()
    tinsert(UISpecialFrames, "SvartbokenFrame")

    local pos = ns.db.settings.windowPos
    if type(pos) == "table" and pos[1] then
        w:ClearAllPoints()
        w:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end

    local bg = Fill(w, C.bg)
    bg:SetAllPoints()
    local accent = Fill(w, C.accent, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    for _, side in ipairs({ { "BOTTOMLEFT", "BOTTOMRIGHT", "H" }, { "TOPLEFT", "BOTTOMLEFT", "V" }, { "TOPRIGHT", "BOTTOMRIGHT", "V" } }) do
        local edge = Fill(w, C.line, "BORDER")
        edge:SetPoint(side[1])
        edge:SetPoint(side[2])
        if side[3] == "H" then edge:SetHeight(1) else edge:SetWidth(1) end
    end

    local skull = w:CreateTexture(nil, "ARTWORK")
    skull:SetSize(28, 28)
    skull:SetPoint("TOPLEFT", PADDING, -16)
    skull:SetTexture(ns.DEFAULT_ICON)
    skull:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = w:CreateFontString(nil, "OVERLAY")
    title:SetFont(TITLE_FONT, 24, "")
    title:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    title:SetPoint("LEFT", skull, "RIGHT", 10, 0)
    title:SetText("SVARTBOKEN")

    w.status = Text(w, 10, C.muted, nil, "RIGHT")
    w.status:SetPoint("RIGHT", w, "TOPRIGHT", -52, -30)

    local close = Button(w, 26, 26, "X", function() w:Hide() end)
    close:SetPoint("TOPRIGHT", -PADDING, -16)

    local statWidth = (WIDTH - 2 * PADDING - 16) / 3
    w.stat1 = CreateStat(w, "DÖDSFALL", PADDING, statWidth)
    w.stat2 = CreateStat(w, "UNIKA MÖRDARE", PADDING + statWidth + 8, statWidth)
    w.stat3 = CreateStat(w, "VÄRSTA FIENDEN", PADDING + 2 * (statWidth + 8), statWidth)

    local navY = -126
    w.tabKillers = Button(w, 88, 26, "Topplista", function() SelectTab("killers") end)
    w.tabKillers:SetPoint("TOPLEFT", PADDING, navY)
    w.tabLog = Button(w, 88, 26, "Dödslogg", function() SelectTab("log") end)
    w.tabLog:SetPoint("LEFT", w.tabKillers, "RIGHT", 2, 0)
    w.tabMembers = Button(w, 88, 26, "Gänget", function() SelectTab("members") end)
    w.tabMembers:SetPoint("LEFT", w.tabLog, "RIGHT", 2, 0)

    w.periodAll = Button(w, 50, 26, "Allt", function() SelectPeriod("all") end)
    w.periodAll:SetPoint("TOPRIGHT", -PADDING, navY)
    w.periodWeek = Button(w, 60, 26, "7 dagar", function() SelectPeriod("week") end)
    w.periodWeek:SetPoint("RIGHT", w.periodAll, "LEFT", -2, 0)
    w.periodToday = Button(w, 50, 26, "Idag", function() SelectPeriod("today") end)
    w.periodToday:SetPoint("RIGHT", w.periodWeek, "LEFT", -2, 0)

    local list = CreateFrame("Frame", nil, w)
    list:SetPoint("TOPLEFT", PADDING, navY - 36)
    list:SetPoint("TOPRIGHT", -PADDING, navY - 36)
    list:SetHeight(ROW_HEIGHT * VISIBLE_ROWS)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #state.rows - VISIBLE_ROWS)
        state.offset = math.max(0, math.min(maxOffset, state.offset - delta))
        RenderRows()
    end)

    w.rows = {}
    for i = 1, VISIBLE_ROWS do
        w.rows[i] = CreateRow(list, i)
    end

    w.empty = Text(list, 13, C.muted, nil, "CENTER")
    w.empty:SetPoint("CENTER")
    w.empty:SetText("Inga dödsfall här. Skriv /sb demo för att se hur det ser ut.")

    w.slider = CreateFrame("Slider", nil, list)
    w.slider:SetOrientation("VERTICAL")
    w.slider:SetPoint("TOPRIGHT")
    w.slider:SetPoint("BOTTOMRIGHT", 0, 2)
    w.slider:SetWidth(6)
    w.slider:SetValueStep(1)
    w.slider:SetObeyStepOnDrag(true)
    local track = Fill(w.slider, C.panel)
    track:SetAllPoints()
    local thumb = Fill(w.slider, C.accent, "ARTWORK")
    thumb:SetSize(6, 40)
    w.slider:SetThumbTexture(thumb)
    w.slider:SetScript("OnValueChanged", function(self, value)
        if self.updating then return end
        state.offset = math.floor(value + 0.5)
        RenderRows()
    end)

    local footerY = 16
    w.toggleToast = Button(w, 78, 24, "", function()
        ns.db.settings.toast = not ns.db.settings.toast
        Refresh()
    end)
    w.toggleToast:SetPoint("BOTTOMLEFT", PADDING, footerY)
    w.toggleSync = Button(w, 72, 24, "", function()
        ns.db.settings.sync = not ns.db.settings.sync
        Refresh()
    end)
    w.toggleSync:SetPoint("LEFT", w.toggleToast, "RIGHT", 2, 0)
    w.toggleGuild = Button(w, 76, 24, "", function()
        ns.db.settings.guildSync = not ns.db.settings.guildSync
        Refresh()
    end)
    w.toggleGuild:SetPoint("LEFT", w.toggleSync, "RIGHT", 2, 0)

    w.gangButton = Button(w, 84, 24, "Gänglista", function() ToggleGangPanel() end)
    w.gangButton:SetPoint("LEFT", w.toggleGuild, "RIGHT", 2, 0)

    w.toggleChannel = Button(w, 76, 24, "", function()
        ns.SetChannelSync(not ns.db.settings.channelSync)
    end)
    w.toggleChannel:SetPoint("LEFT", w.gangButton, "RIGHT", 2, 0)

    local clear
    clear = Button(w, 60, 24, "Rensa", function()
        if clear.armed then
            clear.armed = false
            clear.text:SetText("Rensa")
            ns.RemoveDeaths()
        else
            clear.armed = true
            clear.text:SetText("Säker?")
            C_Timer.After(3, function()
                clear.armed = false
                clear.text:SetText("Rensa")
            end)
        end
    end)
    clear:SetPoint("BOTTOMRIGHT", -PADDING, footerY)

    local share = Button(w, 110, 24, "Dela historik", function()
        local count, notesOrReason = ns.ShareHistory(ns.playerName)
        if count then
            ns.Print("Delar " .. count .. " dödsfall och " .. notesOrReason .. " anteckningar med gänget.")
        else
            ns.Print(notesOrReason)
        end
    end)
    share:SetPoint("RIGHT", clear, "LEFT", -2, 0)

    w:SetScript("OnShow", Refresh)
    return w
end

function ns.ToggleWindow(forceShow)
    if not window then window = Build() end
    if window:IsShown() and not forceShow then
        window:Hide()
    else
        window:Show()
    end
end

function ns.OpenGangPanel()
    ns.ToggleWindow(true)
    ToggleGangPanel(true)
end

-- Liten knapp vid minimapen som går att dra runt kanten.
local function PositionMinimapButton(button)
    local angle = math.rad(ns.db.settings.minimapAngle)
    local radius = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.InitMinimapButton()
    if ns.minimapButton or not Minimap then return end
    local b = CreateFrame("Button", "SvartbokenMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ns.DEFAULT_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnClick", function() ns.ToggleWindow() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(button)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.settings.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
            PositionMinimapButton(button)
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Svartboken")
        GameTooltip:AddLine("Klicka för att öppna, dra för att flytta.", 0.7, 0.7, 0.75)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    PositionMinimapButton(b)
    b:SetShown(not ns.db.settings.minimapHidden)
    ns.minimapButton = b
end

function ns.ToggleMinimapButton()
    local s = ns.db.settings
    s.minimapHidden = not s.minimapHidden
    if ns.minimapButton then ns.minimapButton:SetShown(not s.minimapHidden) end
    return not s.minimapHidden
end

function Svartboken_OnCompartmentClick()
    ns.ToggleWindow()
end
