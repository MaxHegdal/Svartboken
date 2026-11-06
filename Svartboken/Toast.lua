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
