-- Svartboken: popupen som visar vem som gav dig killing blow.
local _, ns = ...

local C = ns.C
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FADE_IN, FADE_OUT = 0.18, 0.6

local toast, moving

local function Text(parent, size, color, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, flags or "")
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function SavePosition(self)
    local point, _, relPoint, x, y = self:GetPoint()
    ns.db.settings.toastPos = { point, relPoint, x, y }
end

local function RestorePosition(self)
    self:ClearAllPoints()
    local p = ns.db.settings.toastPos
    if type(p) == "table" and p[1] then
        self:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        -- Under Blizzards dödsruta, som ligger överst på skärmen.
        self:SetPoint("TOP", UIParent, "TOP", 0, -270)
    end
end

local function OnUpdate(self, elapsed)
    if moving then return end
    self.elapsed = self.elapsed + elapsed
    if self:IsMouseOver() and self.elapsed > FADE_IN then
        self.elapsed = FADE_IN
        self:SetAlpha(1)
        return
    end
    local duration = ns.db.settings.toastSeconds
    if self.elapsed < FADE_IN then
        self:SetAlpha(self.elapsed / FADE_IN)
    elseif self.elapsed < duration then
        self:SetAlpha(1)
    elseif self.elapsed < duration + FADE_OUT then
        self:SetAlpha(1 - (self.elapsed - duration) / FADE_OUT)
    else
        self:Hide()
    end
    local flash = 1 - math.min(self.elapsed / 0.5, 1)
    self.flash:SetAlpha(flash * 0.35)
end

local function Build()
    local f = CreateFrame("Frame", "SvartbokenToast", UIParent)
    f:SetSize(372, 88)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])

    f.flash = f:CreateTexture(nil, "BORDER")
    f.flash:SetAllPoints()
    f.flash:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    f.flash:SetAlpha(0)

    f.bar = f:CreateTexture(nil, "ARTWORK")
    f.bar:SetPoint("TOPLEFT")
    f.bar:SetPoint("BOTTOMLEFT")
    f.bar:SetWidth(4)

    f.iconBorder = f:CreateTexture(nil, "ARTWORK")
    f.iconBorder:SetSize(60, 60)
    f.iconBorder:SetPoint("LEFT", 16, 0)
    f.iconBorder:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)

    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetPoint("TOPLEFT", f.iconBorder, 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", f.iconBorder, -1, 1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.label = Text(f, 10, C.accent, "OUTLINE")
    f.label:SetPoint("TOPLEFT", f.iconBorder, "TOPRIGHT", 12, -1)
    f.label:SetText("DÖDAD AV")

    f.killer = Text(f, 20, C.text, "OUTLINE")
    f.killer:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -3)
    f.killer:SetPoint("RIGHT", f, "RIGHT", -12, 0)

    f.detail = Text(f, 11, C.text)
    f.detail:SetPoint("TOPLEFT", f.killer, "BOTTOMLEFT", 0, -3)
    f.detail:SetPoint("RIGHT", f, "RIGHT", -12, 0)

    f.history = Text(f, 10, C.muted)
    f.history:SetPoint("TOPLEFT", f.detail, "BOTTOMLEFT", 0, -3)
    f.history:SetPoint("RIGHT", f, "RIGHT", -12, 0)

    f.note = Text(f, 11, C.gold)
    f.note:SetPoint("TOPLEFT", f.history, "BOTTOMLEFT", 0, -4)
    f.note:SetPoint("RIGHT", f, "RIGHT", -12, 0)

    f:SetScript("OnUpdate", OnUpdate)
    f:SetScript("OnMouseUp", function(self, button)
        if moving then return end
        if button == "LeftButton" and ns.ToggleWindow then
            self:Hide()
            ns.ToggleWindow(true)
        elseif button == "RightButton" then
            self:Hide()
        end
    end)
    f:SetScript("OnDragStart", function(self)
        if moving then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)

    RestorePosition(f)
    return f
end

local function GetToast()
    if not toast then toast = Build() end
    return toast
end

local function Fill(f, rec)
    local r, g, b = ns.NameColor(rec.kclass, rec.ktype)
    f.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    f.iconBorder:SetColorTexture(r, g, b, 1)
    f.icon:SetTexture(ns.SpellIcon(rec.spellId))
    f.killer:SetText(rec.killer or ns.UNKNOWN)
    f.killer:SetTextColor(r, g, b, 1)

    local detail = {}
    if rec.spell then detail[#detail + 1] = rec.spell end
    if rec.amount and rec.amount > 0 then
        detail[#detail + 1] = ns.FormatNumber(rec.amount) .. " skada"
    end
    if rec.overkill and rec.overkill > 0 then
        detail[#detail + 1] = ns.FormatNumber(rec.overkill) .. " overkill"
    end
    if #detail == 0 then detail[1] = "Okänd attack" end
    f.detail:SetText(table.concat(detail, "  ·  "))

    local mine, all = ns.CountKills(rec.killer, rec.victim)
    local history = {}
    if rec.killer then
        history[#history + 1] = "Dödat dig " .. mine .. " ggr"
        if all > mine then history[#history + 1] = "gänget " .. all .. " ggr" end
    end
    if rec.assists and #rec.assists > 0 then
        history[#history + 1] = "assist: " .. table.concat(rec.assists, ", ")
    end
    f.history:SetText(table.concat(history, "  ·  "))

    local note = rec.note or (ns.GetNote(rec.killer) and ns.GetNote(rec.killer).text)
    f.note:SetText(note or "")
    f:SetHeight(note and 108 or 88)
end

function ns.ShowToast(rec, force)
    if not force and not ns.db.settings.toast then return end
    local f = GetToast()
    Fill(f, rec)
    f.elapsed = 0
    f:SetAlpha(0)
    f:Show()
end

function ns.HideToast()
    if toast and not moving then toast:Hide() end
end

-- /sb flytta: håll rutan framme så att den går att dra till rätt plats.
function ns.ToggleToastMove()
    local f = GetToast()
    moving = not moving
    if moving then
        Fill(f, ns.SampleDeath())
        f.label:SetText("DRA RUTAN  ·  /SB FLYTTA FÖR ATT LÅSA")
        f:SetAlpha(1)
        f:Show()
    else
        f.label:SetText("DÖDAD AV")
        f:Hide()
    end
    return moving
end

function ns.ResetToastPosition()
    ns.db.settings.toastPos = nil
    if toast then RestorePosition(toast) end
end

-- Efterlyst: någon som dödat gänget syns på en nameplate. En badge visas, och klick tar personen i target.
-- Target-knappar är skyddade och får inte ändras under strid, så klickytan är en egen osynlig
-- knapp bredvid den synliga rutan. Rutan kan då döljas när som helst, även i strid.
local MAX_BADGES = 3
local BADGE_WIDTH, BADGE_HEIGHT = 300, 44
local BADGE_TOP = -90
local BADGE_SECONDS = 20
local BADGE_GONE_SECONDS = 5
local ALERT_COOLDOWN = 60

local badges = {}
local marks = {}
local lastAlert = {}

local function DisarmBadge(badge)
    badge.wantsArm = false
    if InCombatLockdown() then
        badge.wantsDisarm = true
        return
    end
    badge.wantsDisarm = false
    badge.secure:SetAttribute("type", nil)
    badge.secure:SetAttribute("unit", nil)
    badge.secure:Hide()
end

local function ClearBadge(badge)
    badge.name, badge.unit = nil, nil
    badge.timer = (badge.timer or 0) + 1
    badge.visual:Hide()
    DisarmBadge(badge)
end

local function SetBadgeHint(badge)
    local hint = badge.summary
    if badge.isSample then
        hint = hint .. "  ·  Provruta"
    elseif badge.gone then
        hint = hint .. "  ·  Utom synhåll"
    elseif badge.wantsArm then
        hint = hint .. "  ·  Klick efter striden"
    else
        hint = hint .. "  ·  Klicka för target"
    end
    badge.detail:SetText(hint)
end

local function ArmBadge(badge)
    badge.wantsDisarm = false
    if InCombatLockdown() then
        badge.wantsArm = true
    else
        badge.wantsArm = false
        badge.secure:SetAttribute("type", "target")
        badge.secure:SetAttribute("unit", badge.unit)
        badge.secure:Show()
    end
    SetBadgeHint(badge)
end

local function StartBadgeTimer(badge, seconds)
    badge.timer = (badge.timer or 0) + 1
    local timer = badge.timer
    C_Timer.After(seconds, function()
        if badge.timer == timer then ClearBadge(badge) end
    end)
end

local function BuildBadge(index)
    local y = BADGE_TOP - (index - 1) * (BADGE_HEIGHT + 4)
    local visual = CreateFrame("Frame", nil, UIParent)
    visual:SetSize(BADGE_WIDTH, BADGE_HEIGHT)
    visual:SetPoint("TOP", UIParent, "TOP", 0, y)
    visual:SetFrameStrata("HIGH")
    visual:Hide()

    local bg = visual:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])

    local bar = visual:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(4)
    bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)

    local icon = visual:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("LEFT", 12, 0)
    icon:SetTexture(ns.DEFAULT_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local badge = { visual = visual, bg = bg }
    badge.name_ = Text(visual, 15, C.text, "OUTLINE")
    badge.name_:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
    badge.name_:SetPoint("RIGHT", visual, "RIGHT", -10, 0)
    badge.detail = Text(visual, 10, C.gold)
    badge.detail:SetPoint("TOPLEFT", badge.name_, "BOTTOMLEFT", 0, -3)
    badge.detail:SetPoint("RIGHT", visual, "RIGHT", -10, 0)

    -- Samma plats som rutan, men fäst i UIParent: en skyddad knapp får inte följa en vanlig ruta.
    local secure = CreateFrame("Button", "SvartbokenBadge" .. index, UIParent, "SecureActionButtonTemplate")
    secure:SetSize(BADGE_WIDTH, BADGE_HEIGHT)
    secure:SetPoint("TOP", UIParent, "TOP", 0, y)
    secure:SetFrameStrata("HIGH")
    secure:RegisterForClicks("LeftButtonUp")
    secure:SetAttribute("useOnKeyDown", false)
    secure:Hide()
    secure:HookScript("OnEnter", function()
        bg:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1)
    end)
    secure:HookScript("OnLeave", function()
        bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    end)
    secure:HookScript("OnClick", function()
        ns.Diag("efterlyst: klick på " .. ns.Describe(badge.name))
        ClearBadge(badge)
    end)
    badge.secure = secure
    return badge
end

-- Skyddade knappar kan bara skapas utanför strid, så de byggs redan vid inloggning.
function ns.InitWanted()
    if #badges > 0 or InCombatLockdown() then return end
    for i = 1, MAX_BADGES do
        badges[i] = BuildBadge(i)
    end
end

local function FindBadge(name)
    for _, badge in ipairs(badges) do
        if badge.name == name then return badge end
    end
    for _, badge in ipairs(badges) do
        if not badge.name then return badge end
    end
    return nil
end

local function ShowBadge(name, class, unit, summary, isSample)
    ns.InitWanted()
    local badge = FindBadge(name)
    if not badge then return nil end
    local r, g, b = ns.NameColor(class)
    badge.name, badge.unit, badge.summary = name, unit, summary
    badge.gone, badge.isSample, badge.wantsArm = false, isSample, false
    badge.name_:SetText(name)
    badge.name_:SetTextColor(r, g, b, 1)
    if unit then
        ArmBadge(badge)
    else
        SetBadgeHint(badge)
    end
    badge.visual:Show()
    StartBadgeTimer(badge, BADGE_SECONDS)
    return badge
end

local function HideMark(unit)
    local mark = marks[unit]
    if not mark then return end
    mark:Hide()
    mark:SetParent(UIParent)
end

local function MarkPlate(unit, count)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local mark = marks[unit]
    if not mark then
        mark = CreateFrame("Frame", nil, UIParent)
        mark:SetSize(60, 22)
        mark.icon = mark:CreateTexture(nil, "OVERLAY")
        mark.icon:SetSize(20, 20)
        mark.icon:SetPoint("LEFT")
        mark.icon:SetTexture(ns.DEFAULT_ICON)
        mark.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        mark.count = Text(mark, 14, C.accent, "OUTLINE")
        mark.count:SetPoint("LEFT", mark.icon, "RIGHT", 3, 0)
        marks[unit] = mark
    end
    mark:SetParent(plate)
    mark:ClearAllPoints()
    mark:SetPoint("BOTTOM", plate, "TOP", 0, 4)
    mark.count:SetText(count)
    mark:Show()
end

local function Summary(name)
    local mine, all = ns.CountKills(name, ns.playerName)
    local text = "Dödat dig " .. mine .. " ggr"
    if all > mine then text = text .. ", gänget " .. all end
    return text, all
end

function ns.OnNamePlateAdded(unit)
    if not ns.db.settings.wanted then return end
    if not UnitExists(unit) or not ns.Safe(UnitIsPlayer(unit)) then return end
    if not ns.Safe(UnitCanAttack("player", unit)) then return end
    local name = ns.PlayerName(UnitName(unit))
    if not name then return end
    local summary, all = Summary(name)
    if all == 0 then return end

    MarkPlate(unit, all)
    local now = GetServerTime()
    if lastAlert[name] and now - lastAlert[name] < ALERT_COOLDOWN then
        -- Samma person igen: håll bara klicket uppdaterat om badgen fortfarande visas.
        for _, badge in ipairs(badges) do
            if badge.name == name then
                badge.unit, badge.gone = unit, false
                ArmBadge(badge)
            end
        end
        return
    end
    lastAlert[name] = now

    local _, class = UnitClass(unit)
    ShowBadge(name, ns.Safe(class), unit, summary, false)
    ns.Diag("efterlyst: " .. name .. " på " .. tostring(unit) .. " strid=" .. tostring(InCombatLockdown()))
    if ns.db.settings.wantedSound and PlaySound and SOUNDKIT then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
    end
end

function ns.OnNamePlateRemoved(unit)
    HideMark(unit)
    for _, badge in ipairs(badges) do
        if badge.name and badge.unit == unit then
            badge.unit, badge.gone = nil, true
            DisarmBadge(badge)
            SetBadgeHint(badge)
            StartBadgeTimer(badge, BADGE_GONE_SECONDS)
        end
    end
end

function ns.OnCombatEnded()
    ns.InitWanted()
    for _, badge in ipairs(badges) do
        if badge.wantsDisarm then DisarmBadge(badge) end
        if badge.wantsArm and badge.unit then
            ArmBadge(badge)
            if badge.name then SetBadgeHint(badge) end
        end
    end
end

function ns.ClearWanted()
    for unit in pairs(marks) do HideMark(unit) end
    for _, badge in ipairs(badges) do ClearBadge(badge) end
end

-- /sb efterlyst test: visar hur det ser ut. Provrutan går inte att klicka på.
function ns.ShowWantedSample()
    return ShowBadge("Skugg Tass", "ROGUE", nil, "Dödat dig 3 ggr, gänget 7", true) ~= nil
end
