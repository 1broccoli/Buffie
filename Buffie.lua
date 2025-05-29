local AceAddon = LibStub("AceAddon-3.0")
local AceConsole = LibStub("AceConsole-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDB = LibStub("AceDB-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local AceTimer = LibStub("AceTimer-3.0")
Buffie = AceAddon:NewAddon("BuffieSettings", "AceConsole-3.0", "AceTimer-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")

local defaultThresholds = {
    {op = "<=", min = 0, sec = 10, color = {1, 0, 0}},
    {op = "<=", min = 1, sec = 0, color = {1, 1, 0}},
    {op = "<=", min = 60, sec = 0, color = {1, 1, 1}},
}

local function minsec_to_seconds(min, sec)
    return (tonumber(min) or 0) * 60 + (tonumber(sec) or 0)
end

local function seconds_to_minsec(seconds)
    local min = math.floor(seconds / 60)
    local sec = seconds % 60
    return min, sec
end

local function DeepCopyThresholds(src)
    local copy = {}
    for i, v in ipairs(src) do
        copy[i] = {
            op = v.op,
            min = v.min,
            sec = v.sec,
            color = {unpack(v.color)}
        }
    end
    return copy
end

local defaults = {
    profile = {
        fontSize = 12,
        displayMode = 1,
        colorThresholds = DeepCopyThresholds(defaultThresholds),
        iconScale = 1,
        iconAlpha = 1,
        timerAlpha = 1,
        iconSpacing = 4,
        buffsPerRow = 8,
        maxRows = 2,
        unlocked = false,
        anchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -205, -13},
        weaponAnchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -265, -13},
        debuffAnchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -205, -65},
        useStaticColor = false,
        staticColor = {1, 1, 1},
        -- Strobe feature defaults
        strobeEnabled = false,
        strobeIconHz = 0,      -- Hz, 0 = off
        strobeTextHz = 0,      -- Hz, 0 = off
        strobeThresholdMin = 0,
        strobeThresholdSec = 10,
        -- New layout and unlock defaults
        buffsUnlocked = false,
        weaponUnlocked = false,
        debuffUnlocked = false,
        weaponPerRow = 2,
        weaponIconSpacing = 4,
        weaponIconScale = 1,
        weaponIconAlpha = 1,
        debuffsPerRow = 8,
        debuffMaxRows = 2,
        debuffIconSpacing = 4,
        debuffIconScale = 1,
        debuffIconAlpha = 1,
    }
}

-- Table to track strobe phase per button
local strobeState = {}

local function SaveAnchorPosition(frameType)
    local frame, dbKey
    if frameType == "buff" then
        frame, dbKey = BuffAnchorFrame, "anchorPoint"
    elseif frameType == "weapon" then
        frame, dbKey = WeaponEnchantAnchorFrame, "weaponAnchorPoint"
    elseif frameType == "debuff" then
        frame, dbKey = DebuffAnchorFrame, "debuffAnchorPoint"
    end
    if not frame or not Buffie or not Buffie.db or not Buffie.db.profile then return end
    local point, relTo, relPoint, x, y = frame:GetPoint()
    local relToName = relTo and relTo.GetName and relTo:GetName() or "UIParent"
    Buffie.db.profile[dbKey] = {point, relToName, relPoint, x, y}
end

local function RestoreAnchorPosition(frameType)
    local db = Buffie and Buffie.db and Buffie.db.profile
    local frame, dbKey
    if frameType == "buff" then
        frame, dbKey = BuffAnchorFrame, "anchorPoint"
    elseif frameType == "weapon" then
        frame, dbKey = WeaponEnchantAnchorFrame, "weaponAnchorPoint"
    elseif frameType == "debuff" then
        frame, dbKey = DebuffAnchorFrame, "debuffAnchorPoint"
    end
    if frame and db and db[dbKey] then
        frame:ClearAllPoints()
        local ap = db[dbKey]
        local relTo
        if ap and ap[2] then
            relTo = _G[ap[2]]
            if not relTo then relTo = UIParent end
        else
            relTo = UIParent
        end
        frame:SetPoint(ap[1] or "TOPRIGHT", relTo, ap[3] or "TOPRIGHT", ap[4] or -205, ap[5] or -13)
    end
end

-- Helper to update anchor backdrop size based on settings
local function UpdateAnchorBackdrop(frame, anchorType)
    if not frame then return end
    local db = Buffie and Buffie.db and Buffie.db.profile or {}
    local scale, perRow, rows, spacing, w, h
    if anchorType == "buff" then
        scale = db.iconScale or 1
        perRow = db.buffsPerRow or 8
        rows = db.maxRows or 2
        spacing = db.iconSpacing or 4
        w = perRow * 32 * scale + (perRow-1) * spacing
        h = rows * 32 * scale + (rows-1) * spacing
    elseif anchorType == "weapon" then
        scale = db.weaponIconScale or 1
        perRow = db.weaponPerRow or 2
        spacing = db.weaponIconSpacing or 4
        w = perRow * 32 * scale + (perRow-1) * spacing
        h = 32 * scale
    elseif anchorType == "debuff" then
        scale = db.debuffIconScale or 1
        perRow = db.debuffsPerRow or 8
        rows = db.debuffMaxRows or 2
        spacing = db.debuffIconSpacing or 4
        w = perRow * 32 * scale + (perRow-1) * spacing
        h = rows * 32 * scale + (rows-1) * spacing
    end
    frame:SetSize(w or 40, h or 40)
end

-- Create anchor frames with dynamic backdrop sizing
local function CreateAnchorFrame(name, color, text, anchorType)
    local frame = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    UpdateAnchorBackdrop(frame, anchorType)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    if frame.SetBackdrop then
        frame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background"})
        frame:SetBackdropColor(unpack(color))
    end
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("CENTER")
    frame.text:SetText(text)
    frame:Hide()
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)

    local isDragging = false

    frame.UpdateBackdrop = function(self)
        UpdateAnchorBackdrop(self, anchorType)
    end

    frame:SetScript("OnShow", function(self)
        self:UpdateBackdrop()
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel(9999)
    end)
    frame:SetScript("OnHide", function(self)
        self:SetFrameStrata("DIALOG")
        self:SetFrameLevel(100)
    end)

    frame:SetScript("OnDragStart", function(self)
        isDragging = true
        self:StartMoving()
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel(9999)
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        isDragging = false
        if name == "BuffieAnchorFrame" then
            SaveAnchorPosition("buff")
        elseif name == "BuffieWeaponEnchantAnchorFrame" then
            SaveAnchorPosition("weapon")
        elseif name == "BuffieDebuffAnchorFrame" then
            SaveAnchorPosition("debuff")
        end
        Buffie:SaveAllSettings()
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel(9999)
    end)
    frame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            isDragging = true
            self:StartMoving()
            self:SetFrameStrata("TOOLTIP")
            self:SetFrameLevel(9999)
        end
    end)
    frame:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then
            self:StopMovingOrSizing()
            isDragging = false
            if name == "BuffieAnchorFrame" then
                SaveAnchorPosition("buff")
            elseif name == "BuffieWeaponEnchantAnchorFrame" then
                SaveAnchorPosition("weapon")
            elseif name == "BuffieDebuffAnchorFrame" then
                SaveAnchorPosition("debuff")
            end
            Buffie:SaveAllSettings()
            self:SetFrameStrata("TOOLTIP")
            self:SetFrameLevel(9999)
        end
    end)

    function frame:SafeRestoreAnchorPosition()
        if not isDragging then
            if name == "BuffieAnchorFrame" then
                RestoreAnchorPosition("buff")
            elseif name == "BuffieWeaponEnchantAnchorFrame" then
                RestoreAnchorPosition("weapon")
            elseif name == "BuffieDebuffAnchorFrame" then
                RestoreAnchorPosition("debuff")
            end
        end
    end

    return frame
end

-- Anchor frame creators using the above
local function CreateBuffAnchor()
    if BuffAnchorFrame then return BuffAnchorFrame end
    BuffAnchorFrame = CreateAnchorFrame("BuffieAnchorFrame", {0, 0.5, 1, 0.7}, "Buffs\nDrag Me", "buff")
    return BuffAnchorFrame
end

local function CreateWeaponEnchantAnchor()
    if WeaponEnchantAnchorFrame then return WeaponEnchantAnchorFrame end
    WeaponEnchantAnchorFrame = CreateAnchorFrame("BuffieWeaponEnchantAnchorFrame", {0.3, 1, 0.3, 0.7}, "Weapon\nDrag Me", "weapon")
    return WeaponEnchantAnchorFrame
end

local function CreateDebuffAnchor()
    if DebuffAnchorFrame then return DebuffAnchorFrame end
    DebuffAnchorFrame = CreateAnchorFrame("BuffieDebuffAnchorFrame", {1, 0.5, 0, 0.7}, "Debuffs\nDrag Me", "debuff")
    return DebuffAnchorFrame
end

-- Add new anchorPoint defaults for weapon and debuff
local defaults = {
    profile = {
        fontSize = 12,
        displayMode = 1,
        colorThresholds = DeepCopyThresholds(defaultThresholds),
        iconScale = 1,
        iconAlpha = 1,
        timerAlpha = 1,
        iconSpacing = 4,
        buffsPerRow = 8,
        maxRows = 2,
        unlocked = false,
        anchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -205, -13},
        weaponAnchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -265, -13},
        debuffAnchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -205, -65},
        useStaticColor = false,
        staticColor = {1, 1, 1},
        -- Strobe feature defaults
        strobeEnabled = false,
        strobeIconHz = 0,      -- Hz, 0 = off
        strobeTextHz = 0,      -- Hz, 0 = off
        strobeThresholdMin = 0,
        strobeThresholdSec = 10,
        -- New layout and unlock defaults
        buffsUnlocked = false,
        weaponUnlocked = false,
        debuffUnlocked = false,
        weaponPerRow = 2,
        weaponIconSpacing = 4,
        weaponIconScale = 1,
        weaponIconAlpha = 1,
        debuffsPerRow = 8,
        debuffMaxRows = 2,
        debuffIconSpacing = 4,
        debuffIconScale = 1,
        debuffIconAlpha = 1,
    }
}

-- Table to track strobe phase per button
local strobeState = {}

local function SaveAnchorPosition()
    if not BuffAnchorFrame or not Buffie or not Buffie.db or not Buffie.db.profile then return end
    local point, relTo, relPoint, x, y = BuffAnchorFrame:GetPoint()
    local relToName = relTo and relTo.GetName and relTo:GetName() or "UIParent"
    Buffie.db.profile.anchorPoint = {point, relToName, relPoint, x, y}
end

local function RestoreAnchorPosition()
    local db = Buffie and Buffie.db and Buffie.db.profile
    if BuffAnchorFrame and db and db.anchorPoint then
        BuffAnchorFrame:ClearAllPoints()
        local ap = db.anchorPoint
        local relTo
        if ap and ap[2] then
            relTo = _G[ap[2]]
            if not relTo then
                print("Buffie: Anchor frame '" .. tostring(ap[2]) .. "' not found, defaulting to UIParent.")
                relTo = UIParent
            end
        else
            relTo = UIParent
        end
        BuffAnchorFrame:SetPoint(ap[1] or "TOPRIGHT", relTo, ap[3] or "TOPRIGHT", ap[4] or -205, ap[5] or -13)
    end
end
local function CreateBuffAnchor()
    if BuffAnchorFrame then return BuffAnchorFrame end
    BuffAnchorFrame = CreateFrame("Frame", "BuffieAnchorFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    -- Initial size, will be updated dynamically
    BuffAnchorFrame:SetSize(40, 40)
    BuffAnchorFrame:SetMovable(true)
    BuffAnchorFrame:EnableMouse(true)
    BuffAnchorFrame:RegisterForDrag("LeftButton")
    BuffAnchorFrame:SetClampedToScreen(true)
    if BuffAnchorFrame.SetBackdrop then
        BuffAnchorFrame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background"})
        BuffAnchorFrame:SetBackdropColor(0, 0.5, 1, 0.7)
    end
    BuffAnchorFrame.text = BuffAnchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    BuffAnchorFrame.text:SetPoint("CENTER")
    BuffAnchorFrame.text:SetText("Buffs\nDrag Me")
    BuffAnchorFrame:Hide()
    BuffAnchorFrame:SetFrameStrata("DIALOG")
    BuffAnchorFrame:SetFrameLevel(100)

    local isDragging = false

    -- Add UpdateBackdrop method for dynamic sizing
    function BuffAnchorFrame:UpdateBackdrop()
        local db = Buffie and Buffie.db and Buffie.db.profile or {}
        local scale = db.iconScale or 1
        local perRow = db.buffsPerRow or 8
        local rows = db.maxRows or 2
        local spacing = db.iconSpacing or 4
        local w = perRow * 32 * scale + (perRow-1) * spacing
        local h = rows * 32 * scale + (rows-1) * spacing
        self:SetSize(w or 40, h or 40)
    end

    BuffAnchorFrame:SetScript("OnShow", function(self)
        -- Always bring to top when shown
        self:UpdateBackdrop()
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel(9999)
    end)
    BuffAnchorFrame:SetScript("OnHide", function(self)
        -- Restore to normal when hidden
        self:SetFrameStrata("DIALOG")
        self:SetFrameLevel(100)
    end)

    BuffAnchorFrame:SetScript("OnDragStart", function(self)
        isDragging = true
        self:StartMoving()
    end)
    BuffAnchorFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        isDragging = false
        SaveAnchorPosition()
        Buffie:SaveAllSettings()
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel(9999)
    end)
    BuffAnchorFrame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            isDragging = true
            self:StartMoving()
        end
    end)
    BuffAnchorFrame:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then
            self:StopMovingOrSizing()
            isDragging = false
            SaveAnchorPosition()
            Buffie:SaveAllSettings()
            self:SetFrameStrata("TOOLTIP")
            self:SetFrameLevel(9999)
        end
    end)

    BuffAnchorFrame._originalRestoreAnchorPosition = RestoreAnchorPosition
    function BuffAnchorFrame:SafeRestoreAnchorPosition()
        if not isDragging then
            RestoreAnchorPosition()
        end
    end

    return BuffAnchorFrame
end

local function GetColorForTime(timeLeft, thresholds)
    -- Remove static color logic here, always use thresholds
    for _, entry in ipairs(thresholds) do
        local thresholdSec = minsec_to_seconds(entry.min, entry.sec)
        if entry.op == "<" and timeLeft < thresholdSec then
            return unpack(entry.color)
        elseif entry.op == "<=" and timeLeft <= thresholdSec then
            return unpack(entry.color)
        elseif entry.op == ">" and timeLeft > thresholdSec then
            return unpack(entry.color)
        elseif entry.op == ">=" and timeLeft >= thresholdSec then
            return unpack(entry.color)
        elseif entry.op == "=" and timeLeft == thresholdSec then
            return unpack(entry.color)
        end
    end
    return 1, 1, 1
end

local displayModeList = {
    [0] = "Off",
    [1] = "min/sec (e.g. 2m 5s)",
    [2] = "mm:ss (e.g. 02:05)",
    [3] = "seconds only (e.g. 125s)",
    [4] = "minutes only (e.g. 2m)",
    [5] = "hours:minutes (e.g. 1:02h)",
    [6] = "h m s (e.g. 1h 2m 5s)",
}

local function FormatBuffieExample(timeLeft, displayMode)
    if displayMode == 0 then
        return ""
    elseif displayMode == 1 then
        if timeLeft >= 60 then
            return string.format("%dm %ds", math.floor(timeLeft / 60), timeLeft % 60)
        else
            return string.format("%ds", timeLeft)
        end
    elseif displayMode == 2 then
        -- mm:ss (e.g. 2:05), but show only seconds if < 60s
        if timeLeft < 60 then
            return string.format("%ds", timeLeft)
        else
            return string.format("%d:%02d", math.floor(timeLeft / 60), timeLeft % 60)
        end
    elseif displayMode == 3 then
        return string.format("%ds", timeLeft)
    elseif displayMode == 4 then
        -- minutes only, but show seconds if <= 60s
        if timeLeft <= 60 then
            return string.format("%ds", timeLeft)
        else
            return string.format("%dm", math.ceil(timeLeft / 60))
        end
    elseif displayMode == 5 then
        return string.format("%d:%02dh", math.floor(timeLeft / 3600), math.floor((timeLeft % 3600) / 60))
    elseif displayMode == 6 then
        local h = math.floor(timeLeft / 3600)
        local m = math.floor((timeLeft % 3600) / 60)
        local s = timeLeft % 60
        local t = ""
        if h > 0 then t = t .. h .. "h " end
        if m > 0 then t = t .. m .. "m " end
        if s > 0 or t == "" then t = t .. s .. "s" end
        return t
    end
end

local function FormatBuffie(timeLeft, displayMode)
    if displayMode == 0 then
        return
    elseif displayMode == 1 then
        -- min/sec (e.g. 2m 5s)
        if timeLeft >= 5400 then
            return string.format("%dh", math.floor(timeLeft / 3600))
        elseif timeLeft >= 3600 then
            return string.format("%dm", math.floor(timeLeft / 60))
        elseif timeLeft >= 60 then
            return string.format("%dm %ds", math.floor(timeLeft / 60), timeLeft % 60)
        else
            return string.format("%ds", timeLeft)
        end
    elseif displayMode == 2 then
        -- mm:ss (e.g. 2:05), but show only seconds if < 60s
        if timeLeft < 60 then
            return string.format("%ds", timeLeft)
        else
            local m = math.floor(timeLeft / 60)
            local s = timeLeft % 60
            return string.format("%d:%02d", m, s)
        end
    elseif displayMode == 3 then
        -- seconds only (e.g. 125s)
        return string.format("%ds", timeLeft)
    elseif displayMode == 4 then
        -- minutes only (e.g. 2m), but show seconds if < 60s
        if timeLeft < 60 then
            return string.format("%ds", timeLeft)
        else
            return string.format("%dm", math.floor(timeLeft / 60))
        end
    elseif displayMode == 5 then
        -- hours:minutes (e.g. 1:02h), but show seconds if < 60s, or minutes if < 3600s
        if timeLeft < 60 then
            return string.format("%ds", timeLeft)
        elseif timeLeft < 3600 then
            return string.format("%dm", math.floor(timeLeft / 60))
        else
            local h = math.floor(timeLeft / 3600)
            local m = math.floor((timeLeft % 3600) / 60)
            return string.format("%d:%02dh", h, m)
        end
    elseif displayMode == 6 then
        -- h m s (e.g. 1h 2m 5s), but don't show zero units
        local h = math.floor(timeLeft / 3600)
        local m = math.floor((timeLeft % 3600) / 60)
        local s = math.floor(timeLeft % 60)
        local t = ""
        if h > 0 then t = t .. h .. "h " end
        if m > 0 then t = t .. m .. "m " end
        if s > 0 or t == "" then t = t .. s .. "s" end
        return t:match("^%s*(.-)%s*$")
    end
end

function Buffie:HookBuffies()
    if self._hooked then return end
    self._hooked = true

    hooksecurefunc("AuraButton_UpdateDuration", function(button, timeLeft)
        if timeLeft then
            local db = Buffie.db.profile
            local formattedDuration = FormatBuffie(timeLeft, db.displayMode)
            if formattedDuration then
                button.duration:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
                button.duration:ClearAllPoints()
                button.duration:SetPoint("TOP", button, "BOTTOM", 0, -2)
                local r, g, b
                if db.useStaticColor and db.staticColor then
                    -- Color numbers with threshold, units with static color
                    local threshR, threshG, threshB = GetColorForTime(timeLeft, db.colorThresholds or defaultThresholds)
                    local sr, sg, sb = unpack(db.staticColor)
                    local out = formattedDuration
                    -- Only color the unit letters (h, m, s) with static color, numbers with threshold color
                    out = out:gsub("(%d+)([hms])", function(num, unit)
                        return ("|cff%02x%02x%02x%s|r|cff%02x%02x%02x%s|r"):
                            format(
                                math.floor(threshR*255), math.floor(threshG*255), math.floor(threshB*255), num,
                                math.floor(sr*255), math.floor(sg*255), math.floor(sb*255), unit
                            )
                    end)
                    -- Also color any standalone units (e.g. "m" or "s" not preceded by a digit)
                    out = out:gsub("([^%d])([hms])", function(prefix, unit)
                        return prefix .. ("|cff%02x%02x%02x%s|r"):
                            format(math.floor(sr*255), math.floor(sg*255), math.floor(sb*255), unit)
                    end)
                    button.duration:SetText(out)
                else
                    r, g, b = GetColorForTime(timeLeft, db.colorThresholds or defaultThresholds)
                    button.duration:SetTextColor(r, g, b)
                    button.duration:SetText(formattedDuration)
                end
                button.duration:SetAlpha(db.timerAlpha or 1)
            end
            -- Only apply buff icon settings to BuffButton, not DebuffButton
            if button:GetName() and button:GetName():find("^BuffButton") then
                if db.iconScale and button.SetScale then
                    button:SetScale(db.iconScale)
                end
                if db.iconAlpha and button.SetAlpha then
                    button:SetAlpha(db.iconAlpha)
                end
                if button.icon and button.icon.SetAlpha then
                    button.icon:SetAlpha(db.iconAlpha or 1)
                end
            end
            -- DebuffButton scale/alpha handled in LayoutBuffs
            -- Strobe logic: initialize strobe state if needed
            if not strobeState[button] then
                strobeState[button] = {iconPhase = 0, textPhase = 0}
            end
            strobeState[button].lastTimeLeft = timeLeft
        end
    end)
end

local function GetBuffButton(index)
    return _G["BuffButton"..index]
end

function Buffie:LayoutBuffs()
    if not self.db or not self.db.profile then return end
    local db = self.db.profile

    -- Defensive fallback for all layout variables
    local buffsPerRow = db.buffsPerRow or 8
    local maxRows = db.maxRows or 2
    local iconScale = db.iconScale or 1
    local iconAlpha = db.iconAlpha or 1
    local timerAlpha = db.timerAlpha or 1
    local iconSpacing = db.iconSpacing or 4

    local weaponPerRow = db.weaponPerRow or 2
    local weaponIconSpacing = db.weaponIconSpacing or 4
    local weaponIconScale = db.weaponIconScale or 1
    local weaponIconAlpha = db.weaponIconAlpha or 1

    local debuffsPerRow = db.debuffsPerRow or 8
    local debuffMaxRows = db.debuffMaxRows or 2
    local debuffIconSpacing = db.debuffIconSpacing or 4
    local debuffIconScale = db.debuffIconScale or 1
    -- local debuffIconAlpha = db.debuffIconAlpha or 1 -- REMOVE: no longer used

    local anchor = CreateBuffAnchor()
    local weaponAnchor = CreateWeaponEnchantAnchor()
    local debuffAnchor = CreateDebuffAnchor()
    local scale = iconScale
    local iconSize = 32 * scale

    -- Buffs
    local parent = db.buffsUnlocked and anchor or UIParent
    -- Weapon enchants
    local weaponParent = db.weaponUnlocked and weaponAnchor or UIParent
    -- Debuffs
    local debuffParent = db.debuffUnlocked and debuffAnchor or UIParent

    -- Restore anchor positions
    if anchor.SafeRestoreAnchorPosition then anchor:SafeRestoreAnchorPosition() end
    if weaponAnchor.SafeRestoreAnchorPosition then weaponAnchor:SafeRestoreAnchorPosition() end
    if debuffAnchor.SafeRestoreAnchorPosition then debuffAnchor:SafeRestoreAnchorPosition() end

    -- Show/hide anchors
    if db.buffsUnlocked then anchor:Show() else anchor:Hide() end
    if db.weaponUnlocked then weaponAnchor:Show() else weaponAnchor:Hide() end
    if db.debuffUnlocked then debuffAnchor:Show() else debuffAnchor:Hide() end

    -- Layout buffs (use only buff settings)
    local totalBuffs = BUFF_ACTUAL_DISPLAY or 32
    local shownCount = 0
    local maxBuffs = buffsPerRow * maxRows
    local buffScale = iconScale
    local buffSpacing = iconSpacing
    local buffAlpha = iconAlpha
    local buffPerRow = buffsPerRow
    local buffMaxRows = maxRows
    local buffIconSize = 32 * buffScale

    local visibleBuffs = {}
    for i = 1, totalBuffs do
        local button = _G["BuffButton"..i]
        if button then
            button:SetParent(parent)
            button:Show()
            if button:IsVisible() then
                table.insert(visibleBuffs, button)
            end
        end
    end

    for i = 1, #visibleBuffs do
        local button = visibleBuffs[i]
        if i <= maxBuffs then
            button:ClearAllPoints()
            button:SetScale(buffScale)
            button:SetAlpha(buffAlpha)
            button:Show()
            local row = math.floor((i-1) / buffPerRow)
            local col = (i-1) % buffPerRow
            if row == 0 and col == 0 then
                button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
            elseif col == 0 then
                local prevRowBtn = visibleBuffs[i - buffPerRow]
                button:SetPoint("TOPRIGHT", prevRowBtn, "BOTTOMRIGHT", 0, -buffSpacing)
            else
                local prevBtn = visibleBuffs[i - 1]
                button:SetPoint("RIGHT", prevBtn, "LEFT", -buffSpacing, 0)
            end
            if db.buffsUnlocked then
                button:EnableMouse(false)
            else
                button:EnableMouse(true)
            end
        else
            button:Hide()
        end
    end
    for i = #visibleBuffs+1, totalBuffs do
        local button = _G["BuffButton"..i]
        if button then button:Show() end
    end

    -- Layout weapon enchants (independent layout)
    for i = 1, 2 do
        local button = _G["TempEnchant"..i]
        if button then
            button:SetParent(weaponParent)
            if db.weaponUnlocked then
                button:ClearAllPoints()
                button:SetScale(weaponIconScale)
                button:SetAlpha(weaponIconAlpha)
                button:SetPoint("TOPRIGHT", weaponAnchor, "TOPRIGHT", -(i-1)*(32*weaponIconScale+weaponIconSpacing), 0)
                button:Show()
                button:EnableMouse(false)
            else
                button:SetScale(1)
                button:SetAlpha(1)
                button:EnableMouse(true)
            end
        end
    end

    -- Layout debuffs (independent layout, use only debuff settings)
    local totalDebuffs = DEBUFF_ACTUAL_DISPLAY or 16
    local debuffPerRow = debuffsPerRow
    local debuffMaxRows = debuffMaxRows
    local debuffScale = debuffIconScale
    local debuffIconSize = 32 * debuffScale
    local debuffSpacing = debuffIconSpacing
    -- local debuffAlpha = debuffIconAlpha -- REMOVE: no longer used
    local visibleDebuffs = {}
    for i = 1, totalDebuffs do
        local button = _G["DebuffButton"..i]
        if button then
            button:SetParent(debuffParent)
            button:Show()
            if button:IsVisible() then
                table.insert(visibleDebuffs, button)
            end
        end
    end
    for i = 1, #visibleDebuffs do
        local button = visibleDebuffs[i]
        if i <= debuffPerRow * debuffMaxRows then
            button:ClearAllPoints()
            button:SetScale(debuffScale)
            button:SetAlpha(1) -- Always fully opaque for now
            button:Show()
            local row = math.floor((i-1) / debuffPerRow)
            local col = (i-1) % debuffPerRow
            if row == 0 and col == 0 then
                button:SetPoint("TOPRIGHT", debuffAnchor, "TOPRIGHT", 0, 0)
            elseif col == 0 then
                local prevRowBtn = visibleDebuffs[i - debuffPerRow]
                button:SetPoint("TOPRIGHT", prevRowBtn, "BOTTOMRIGHT", 0, -debuffSpacing)
            else
                local prevBtn = visibleDebuffs[i - 1]
                button:SetPoint("RIGHT", prevBtn, "LEFT", -debuffSpacing, 0)
            end
            -- REMOVE: debuff icon alpha setting
            -- if button.icon and button.icon.SetAlpha then
            --     button.icon:SetAlpha(debuffAlpha)
            -- end
        else
            button:Hide()
        end
    end
    for i = #visibleDebuffs+1, totalDebuffs do
        local button = _G["DebuffButton"..i]
        if button then button:Show() end
    end
end

local updateInterval = 0.1
local timeSinceLastUpdate = 0
local function TimerUpdater(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate > updateInterval then
        if Buffie and Buffie.UpdateBuffies then
            Buffie:UpdateBuffies()
        end
        timeSinceLastUpdate = 0
    end

    -- Strobe animation update
    local db = Buffie and Buffie.db and Buffie.db.profile
    if db and db.strobeEnabled and ((db.strobeIconHz or 0) > 0 or (db.strobeTextHz or 0) > 0) then
        local strobeThreshold = minsec_to_seconds(db.strobeThresholdMin or 0, db.strobeThresholdSec or 0)
        for i = 1, (BUFF_ACTUAL_DISPLAY or 32) do
            local button = _G["BuffButton"..i]
            if button and button:IsVisible() and strobeState[button] and button.timeLeft then
                local timeLeft = button.timeLeft or strobeState[button].lastTimeLeft or 0
                if timeLeft <= strobeThreshold then
                    -- Icon strobe: only affect icon if strobeIconHz > 0
                    if (db.strobeIconHz or 0) > 0 then
                        strobeState[button].iconPhase = (strobeState[button].iconPhase or 0) + elapsed
                        local freq = db.strobeIconHz
                        local iconAlpha = 0.5 + 0.5 * math.sin(2 * math.pi * freq * strobeState[button].iconPhase)
                        if button.SetAlpha then button:SetAlpha(iconAlpha) end
                        if button.icon and button.icon.SetAlpha then button.icon:SetAlpha(iconAlpha) end
                    else
                        -- Reset icon alpha if icon strobe is off
                        if button.SetAlpha then button:SetAlpha(db.iconAlpha or 1) end
                        if button.icon and button.icon.SetAlpha then button.icon:SetAlpha(db.iconAlpha or 1) end
                        strobeState[button].iconPhase = 0
                    end

                    -- Text strobe: only affect timer text if strobeTextHz > 0
                    if (db.strobeTextHz or 0) > 0 then
                        strobeState[button].textPhase = (strobeState[button].textPhase or 0) + elapsed
                        local freq = db.strobeTextHz
                        local textAlpha = 0.5 + 0.5 * math.sin(2 * math.pi * freq * strobeState[button].textPhase)
                        if button.duration and button.duration.SetAlpha then button.duration:SetAlpha(textAlpha) end
                    else
                        -- Reset text alpha if text strobe is off
                        if button.duration and button.duration.SetAlpha then button.duration:SetAlpha(db.timerAlpha or 1) end
                        strobeState[button].textPhase = 0
                    end
                else
                    -- Reset both icon and text alpha if above threshold
                    if button.SetAlpha then button:SetAlpha(db.iconAlpha or 1) end
                    if button.icon and button.icon.SetAlpha then button.icon:SetAlpha(db.iconAlpha or 1) end
                    if button.duration and button.duration.SetAlpha then button.duration:SetAlpha(db.timerAlpha or 1) end
                    strobeState[button].iconPhase = 0
                    strobeState[button].textPhase = 0
                end
            end
        end
    end
end

local aceguiFrame = nil

-- Ensure blizzardDefaults is always defined and valid
if not blizzardDefaults then
    blizzardDefaults = {
        fontSize = 12,
        displayMode = 0,
        iconScale = 1,
        iconAlpha = 1,
        timerAlpha = 1,
        colorThresholds = DeepCopyThresholds(defaultThresholds),
        iconSpacing = 4,
        buffsPerRow = 8,
        maxRows = 2,
        unlocked = false,
        anchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -205, -13},
        weaponAnchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -265, -13},
        debuffAnchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -205, -65},
        useStaticColor = false,
        staticColor = {1, 1, 1},
        strobeEnabled = false,
        strobeIconHz = 0,
        strobeTextHz = 0,
        strobeThresholdMin = 0,
        strobeThresholdSec = 10,
        buffsUnlocked = false,
        weaponUnlocked = false,
        debuffUnlocked = false,
        weaponPerRow = 2,
        weaponIconSpacing = 4,
        weaponIconScale = 1,
        weaponIconAlpha = 1,
        debuffsPerRow = 8,
        debuffMaxRows = 2,
        debuffIconSpacing = 4,
        debuffIconScale = 1,
        debuffIconAlpha = 1,
    }
end

function Buffie:ResetToBlizzard()
    local db = self.db and self.db.profile
    if not db or not blizzardDefaults then return end
    for k, v in pairs(blizzardDefaults) do
        if type(v) == "table" then
            if k == "colorThresholds" then
                db[k] = DeepCopyThresholds(v)
            else
                db[k] = {unpack(v)}
            end
        else
            db[k] = v
        end
    end
    self:RestoreAllSettings()
    self:UpdateBuffies()
end

local function SecureBuffFrameUpdateHook()
    if Buffie._buffFrameHooked then return end
    hooksecurefunc("BuffFrame_UpdateAllBuffAnchors", function()
        if Buffie and Buffie.db and Buffie.db.profile and (Buffie.db.profile.unlocked or true) then
            Buffie:LayoutBuffs()
        end
    end)
    Buffie._buffFrameHooked = true
end

local function MergeDefaults(profile, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" and type(profile[k]) == "table" then
            MergeDefaults(profile[k], v)
        elseif profile[k] == nil then
            if type(v) == "table" then
                if k == "colorThresholds" then
                    profile[k] = DeepCopyThresholds(v)
                else
                    local t = {}
                    MergeDefaults(t, v)
                    profile[k] = t
                end
            else
                profile[k] = v
            end
        end
    end
end

function Buffie:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("BuffieDB", defaults, true)
    local db = self.db.profile
    MergeDefaults(db, defaults.profile)
    if db.anchorPoint and type(db.anchorPoint[2]) ~= "string" then
        db.anchorPoint[2] = "UIParent"
    end

    AceConfig:RegisterOptionsTable("BuffieSettings", {
        name = "Buffie Settings",
        type = "group",
        args = {
            profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db),
            buffs = {
                type = "group",
                name = "Buffs",
                order = 1,
                args = {
                    testGroup = {
                        type = "group",
                        name = "Unlock Anchors",
                        inline = true,
                        order = 0,
                        args = {
                            buffsUnlocked = {
                                type = "toggle",
                                name = "Buffs",
                                desc = "Unlock to move the buff anchor.",
                                get = function() return Buffie.db.profile.buffsUnlocked end,
                                set = function(_, val)
                                    Buffie.db.profile.buffsUnlocked = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 10,
                            },
                            weaponUnlocked = {
                                type = "toggle",
                                name = "Weapon Enchants",
                                desc = "Unlock to move the weapon enchant anchor.",
                                get = function() return Buffie.db.profile.weaponUnlocked end,
                                set = function(_, val)
                                    Buffie.db.profile.weaponUnlocked = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 11,
                            },
                            debuffUnlocked = {
                                type = "toggle",
                                name = "Debuffs ",
                                desc = "Unlock to move the debuff anchor.",
                                get = function() return Buffie.db.profile.debuffUnlocked end,
                                set = function(_, val)
                                    Buffie.db.profile.debuffUnlocked = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 12,
                            },
                        },
                    },
                    displaySettings = {
                        type = "group",
                        name = "Timer Display Settings",
                        inline = true,
                        order = 1,
                        args = {
                            displayMode = {
                                type = "select",
                                name = "Timer Display Type",
                                desc = "Choose how Buffies are displayed.",
                                values = displayModeList,
                                get = function() return Buffie.db.profile.displayMode end,
                                set = function(_, val)
                                    Buffie.db.profile.displayMode = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 1,
                            },
                            fontSize = {
                                type = "range",
                                name = "Font Size",
                                min = 8, max = 24, step = 1,
                                get = function() return Buffie.db.profile.fontSize end,
                                set = function(_, val)
                                    Buffie.db.profile.fontSize = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 2,
                            },
                            timerAlpha = {
                                type = "range",
                                name = "Timer Text Transparency",
                                min = 0, max = 1, step = 0.01,
                                get = function() return Buffie.db.profile.timerAlpha or 1 end,
                                set = function(_, val)
                                    Buffie.db.profile.timerAlpha = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 3,
                            },
                            testTime = {
                                type = "input",
                                name = "Test Time (seconds)",
                                desc = "Enter a test time in seconds to preview the timer format.",
                                get = function() return tostring(Buffie._testTime or 125) end,
                                set = function(_, val)
                                    local t = tonumber(val) or 0
                                    Buffie._testTime = t
                                    Buffie._testExampleLast = nil
                                end,
                                width = 0.7,
                                order = 4,
                            },
                            testExample = {
                                type = "description",
                                name = function()
                                    local tval = tonumber(Buffie._testTime or 125)
                                    local mode = Buffie.db.profile.displayMode
                                    return "|cff00ff00Example: " .. FormatBuffieExample(tval, mode) .. "|r"
                                end,
                                width = "full",
                                order = 5,
                            },
                        },
                    },
                    iconSettings = {
                        type = "group",
                        name = "Buff Icon Settings",
                        inline = true,
                        order = 2,
                        args = {
                            iconScale = {
                                type = "range",
                                name = "Buff Icon Scale",
                                min = 0.5, max = 2, step = 0.01,
                                get = function() return Buffie.db.profile.iconScale or 1 end,
                                set = function(_, val)
                                    Buffie.db.profile.iconScale = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 1,
                            },
                            iconAlpha = {
                                type = "range",
                                name = "Buff Icon Transparency",
                                min = 0, max = 1, step = 0.01,
                                get = function() return Buffie.db.profile.iconAlpha or 1 end,
                                set = function(_, val)
                                    Buffie.db.profile.iconAlpha = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 2,
                            },
                            -- Layout section moved here:
                            iconSpacing = {
                                type = "range",
                                name = "Buff Icon Spacing",
                                min = 0, max = 32, step = 1,
                                get = function() return Buffie.db.profile.iconSpacing or 4 end,
                                set = function(_, val)
                                    Buffie.db.profile.iconSpacing = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 10,
                            },
                            buffsPerRow = {
                                type = "range",
                                name = "Buffs Per Row",
                                min = 1, max = 16, step = 1,
                                get = function() return Buffie.db.profile.buffsPerRow or 8 end,
                                set = function(_, val)
                                    Buffie.db.profile.buffsPerRow = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 11,
                            },
                            maxRows = {
                                type = "range",
                                name = "Max Rows",
                                min = 1, max = 8, step = 1,
                                get = function() return Buffie.db.profile.maxRows or 2 end,
                                set = function(_, val)
                                    Buffie.db.profile.maxRows = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 12,
                            },
                        },
                    },
                    weaponIconSettings = {
                        type = "group",
                        name = "Weapon Enchant Icon Settings",
                        inline = true,
                        order = 2.1,
                        args = {
                            weaponIconScale = {
                                type = "range",
                                name = "Weapon Icon Scale",
                                min = 0.5, max = 2, step = 0.01,
                                get = function() return Buffie.db.profile.weaponIconScale or 1 end,
                                set = function(_, val)
                                    Buffie.db.profile.weaponIconScale = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 1,
                            },
                            weaponIconAlpha = {
                                type = "range",
                                name = "Weapon Icon Transparency",
                                min = 0, max = 1, step = 0.01,
                                get = function() return Buffie.db.profile.weaponIconAlpha or 1 end,
                                set = function(_, val)
                                    Buffie.db.profile.weaponIconAlpha = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 2,
                            },
                            weaponIconSpacing = {
                                type = "range",
                                name = "Weapon Icon Spacing",
                                min = 0, max = 32, step = 1,
                                get = function() return Buffie.db.profile.weaponIconSpacing or 4 end,
                                set = function(_, val)
                                    Buffie.db.profile.weaponIconSpacing = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 3,
                            },
                            weaponPerRow = {
                                type = "range",
                                name = "Weapon Per Row",
                                min = 1, max = 2, step = 1,
                                get = function() return Buffie.db.profile.weaponPerRow or 2 end,
                                set = function(_, val)
                                    Buffie.db.profile.weaponPerRow = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 4,
                            },
                        },
                    },
                    debuffIconSettings = {
                        type = "group",
                        name = "Debuff Icon Settings",
                        inline = true,
                        order = 2.2,
                        args = {
                            debuffIconScale = {
                                type = "range",
                                name = "Debuff Icon Scale",
                                min = 0.5, max = 2, step = 0.01,
                                get = function() return Buffie.db.profile.debuffIconScale or 1 end,
                                set = function(_, val)
                                    Buffie.db.profile.debuffIconScale = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 1,
                            },
                            -- debuffIconAlpha slider removed
                            debuffIconSpacing = {
                                type = "range",
                                name = "Debuff Icon Spacing",
                                min = 0, max = 32, step = 1,
                                get = function() return Buffie.db.profile.debuffIconSpacing or 4 end,
                                set = function(_, val)
                                    Buffie.db.profile.debuffIconSpacing = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 2,
                            },
                            debuffsPerRow = {
                                type = "range",
                                name = "Debuffs Per Row",
                                min = 1, max = 16, step = 1,
                                get = function() return Buffie.db.profile.debuffsPerRow or 8 end,
                                set = function(_, val)
                                    Buffie.db.profile.debuffsPerRow = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 3,
                            },
                            debuffMaxRows = {
                                type = "range",
                                name = "Debuff Max Rows",
                                min = 1, max = 8, step = 1,
                                get = function() return Buffie.db.profile.debuffMaxRows or 2 end,
                                set = function(_, val)
                                    Buffie.db.profile.debuffMaxRows = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 4,
                            },
                        },
                    },
                    -- layout group removed from root args
                    thresholds = {
                        type = "group",
                        name = "Text Color",
                        order = 4,
                        inline = true,
                        args = {
                            desc = {
                                type = "description",
                                name = "Set color and operator for up to 3 thresholds. Buff timers will use the first matching threshold.",
                                order = 0,
                        },
                            testExample = {
                                type = "description",
                                name = function()
                                    local db = Buffie.db.profile
                                    local tvals = {
                                        minsec_to_seconds(db.colorThresholds[1].min or 0, db.colorThresholds[1].sec or 0),
                                        minsec_to_seconds(db.colorThresholds[2].min or 0, db.colorThresholds[2].sec or 0),
                                        minsec_to_seconds(db.colorThresholds[3].min or 0, db.colorThresholds[3].sec or 0),
                                    }
                                    local mode = db.displayMode
                                    local out = ""
                                    for i = 1, 3 do
                                        local c = db.colorThresholds[i] and db.colorThresholds[i].color or {1,1,1}
                                        local hex = ("|cff%02x%02x%02x"):format(
                                            math.floor((c[1] or 1)*255),
                                            math.floor((c[2] or 1)*255),
                                            math.floor((c[3] or 1)*255)
                                        )
                                        out = out .. string.format("%s%s|r", hex, FormatBuffieExample(tvals[i], mode))
                                        if i < 3 then out = out .. "   " end
                                    end
                                    return "Threshold Examples: " .. out
                                end,
                                order = 0.5,
                            },
                            useStaticColor = {
                                type = "toggle",
                                name = "Duration Text Color",
                                desc = "If checked, all timer duration text uses the selected color for seconds, minutes, hours below instead of threshold colors.",
                                get = function() return Buffie.db.profile.useStaticColor end,
                                set = function(_, val)
                                    Buffie.db.profile.useStaticColor = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 0.1,
                            },
                            staticColor = {
                                type = "color",
                                name = "sec/min/hour text Color",
                                desc = "Color used for all timer text when 'Duration Text Color' is checked.",
                                get = function()
                                    local c = Buffie.db.profile.staticColor or {1,1,1}
                                    return c[1], c[2], c[3]
                                end,
                                set = function(_, r, g, b)
                                    Buffie.db.profile.staticColor = {r, g, b}
                                    Buffie:UpdateBuffies()
                                end,
                                disabled = function() return not Buffie.db.profile.useStaticColor end,
                                order = 0.11,
                            },
                            threshold1_op = {
                                type = "select",
                                name = "Op",
                                width = 0.35,
                                values = {["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=", ["="] = "="},
                                get = function() local db = Buffie.db.profile; return (db.colorThresholds[1] or {}).op or "<=" end,
                                set = function(_, val)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[1] then db.colorThresholds[1] = {} end
                                    db.colorThresholds[1].op = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 1,
                            },
                            threshold1_min = {
                                type = "input",
                                name = "Min",
                                width = 0.55,
                                get = function() local db = Buffie.db.profile; return tostring((db.colorThresholds[1] or {}).min or 0) end,
                                set = function(_, val)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[1] then db.colorThresholds[1] = {} end
                                    db.colorThresholds[1].min = tonumber(val) or 0
                                    Buffie:UpdateBuffies()
                                end,
                                order = 2,
                            },
                            threshold1_sec = {
                                type = "input",
                                name = "Sec",
                                width = 0.55,
                                get = function() local db = Buffie.db.profile; return tostring((db.colorThresholds[1] or {}).sec or 0) end,
                                set = function(_, val)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[1] then db.colorThresholds[1] = {} end
                                    db.colorThresholds[1].sec = tonumber(val) or 0
                                    Buffie:UpdateBuffies()
                                end,
                                order = 3,
                            },
                            threshold1_color = {
                                type = "color",
                                name = "Color",
                                width = 0.55,
                                get = function()
                                    local db = Buffie.db.profile
                                    local c = (db.colorThresholds[1] or {}).color
                                    return c and c[1], c and c[2], c and c[3] or 1, 1, 1
                                end,
                                set = function(_, r, g, b)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[1] then db.colorThresholds[1] = {} end
                                    db.colorThresholds[1].color = {r, g, b}
                                    Buffie:UpdateBuffies()
                                end,
                                order = 4,
                            },
                            threshold1_spacer = {
                                type = "description",
                                name = "",
                                order = 4.5,
                            },
                            threshold2_op = {
                                type = "select",
                                name = "Op",
                                width = 0.35,
                                values = {["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=", ["="] = "="},
                                get = function() local db = Buffie.db.profile; return (db.colorThresholds[2] or {}).op or "<=" end,
                                set = function(_, val)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[2] then db.colorThresholds[2] = {} end
                                    db.colorThresholds[2].op = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 5,
                            },
                            threshold2_min = {
                                type = "input",
                                name = "Min",
                                width = 0.55,
                                get = function() local db = Buffie.db.profile; return tostring((db.colorThresholds[2] or {}).min or 0) end,
                                set = function(_, val)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[2] then db.colorThresholds[2] = {} end
                                    db.colorThresholds[2].min = tonumber(val) or 0
                                    Buffie:UpdateBuffies()

                                end,
                                order = 6,
                            },
                            threshold2_sec = {
                                type = "input",
                                name = "Sec",
                                width = 0.55,
                                get = function() local db = Buffie.db.profile; return tostring((db.colorThresholds[2] or {}).sec or 0) end,
                                set = function(_, val)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[2] then db.colorThresholds[2] = {} end
                                    db.colorThresholds[2].sec = tonumber(val) or 0
                                    Buffie:UpdateBuffies()
                                end,
                                order = 7,
                            },
                            threshold2_color = {
                                type = "color",
                                name = "Color",
                                width = 0.55,
                                get = function()
                                    local db = Buffie.db.profile
                                    local c = (db.colorThresholds[2] or {}).color
                                    return c and c[1], c and c[2], c and c[3] or 1, 1, 1
                                end,
                                set = function(_, r, g, b)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[2] then db.colorThresholds[2] = {} end
                                    db.colorThresholds[2].color = {r, g, b}
                                    Buffie:UpdateBuffies()
                                end,
                                order = 8,
                            },
                            threshold2_spacer = {
                                type = "description",
                                name = "",
                                order = 8.5,
                            },
                            threshold3_op = {
                                type = "select",
                                name = "Op",
                                width = 0.35,
                                values = {["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=", ["="] = "="},
                                get = function() local db = Buffie.db.profile; return (db.colorThresholds[3] or {}).op or "<=" end,
                                set = function(_, val)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[3] then db.colorThresholds[3] = {} end
                                    db.colorThresholds[3].op = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 9,
                            },
                            threshold3_min = {
                                type = "input",
                                name = "Min",
                                width = 0.55,
                                get = function() local db = Buffie.db.profile; return tostring((db.colorThresholds[3] or {}).min or 0) end,
                                set = function(_, val)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[3] then db.colorThresholds[3] = {} end
                                    db.colorThresholds[3].min = tonumber(val) or 0
                                    Buffie:UpdateBuffies()
                                end,
                                order = 10,
                            },
                            threshold3_sec = {
                                type = "input",
                                name = "Sec",
                                width = 0.55,
                                get = function() local db = Buffie.db.profile; return tostring((db.colorThresholds[3] or {}).sec or 0) end,
                                set = function(_, val)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[3] then db.colorThresholds[3] = {} end
                                    db.colorThresholds[3].sec = tonumber(val) or 0
                                    Buffie:UpdateBuffies()
                                end,
                                order = 11,
                            },
                            threshold3_color = {
                                type = "color",
                                name = "Color",
                                width = 0.55,
                                get = function()
                                    local db = Buffie.db.profile
                                    local c = (db.colorThresholds[3] or {}).color
                                    return c and c[1], c and c[2], c and c[3] or 1, 1, 1
                                end,
                                set = function(_, r, g, b)
                                    local db = Buffie.db.profile
                                    if not db.colorThresholds[3] then db.colorThresholds[3] = {} end
                                    db.colorThresholds[3].color = {r, g, b}
                                    Buffie:UpdateBuffies()
                                end,
                                order = 12,
                            },
                        },
                    },

                    strobeGroup = {
                        type = "group",
                        name = "Strobe Effect",
                        order = 0.9,
                        inline = true,
                        args = {
                            strobeEnabled = {
                                type = "toggle",
                                name = "Enable Strobe",
                                desc = "Enable strobe (fading) effect for expiring buffs.",
                                get = function() return Buffie.db.profile.strobeEnabled end,
                                set = function(_, val)
                                    Buffie.db.profile.strobeEnabled = val
                                end,
                                order = 1,
                            },
                            -- Move threshold inputs up
                            strobeThresholdMin = {
                                type = "input",
                                name = "Minutes",
                                desc = "Buffs with less than this threshold many minutes+seconds left will strobe.",
                                get = function() return tostring(Buffie.db.profile.strobeThresholdMin or 0) end,
                                set = function(_, val)
                                    local v = tonumber(val) or 0
                                    if v < 0 then v = 0 end
                                    Buffie.db.profile.strobeThresholdMin = v
                                end,
                                order = 2,
                                width = 0.5,
                                disabled = function() return not Buffie.db.profile.strobeEnabled end,
                            },
                            strobeThresholdSec = {
                                type = "input",
                                name = "Sec",
                                desc = "Buffs with less than this threshhold many minutes+seconds left will strobe.",
                                get = function() return tostring(Buffie.db.profile.strobeThresholdSec or 0) end,
                                set = function(_, val)
                                    local v = tonumber(val) or 0
                                    if v < 0 then v = 0 end
                                    Buffie.db.profile.strobeThresholdSec = v
                                end,
                                order = 3,
                                width = 0.5,
                                disabled = function() return not Buffie.db.profile.strobeEnabled end,
                            },
                            -- Move speed sliders down
                            strobeIconHz = {
                                type = "range",
                                name = "Icon & Text Speed",
                                desc = "How many fades per second. 0 disables icon strobe.",
                                min = 0, max = 5, step = 0.1,
                                get = function() return Buffie.db.profile.strobeIconHz or 0 end,
                                set = function(_, val)
                                    Buffie.db.profile.strobeIconHz = val
                                end,
                                order = 4,
                                disabled = function() return not Buffie.db.profile.strobeEnabled end,
                            },
                            strobeTextHz = {
                                type = "range",
                                name = "Text Speed",
                                desc = "How many fades per second.  0 disables text strobe.",
                                min = 0, max = 5, step = 0.1,
                                get = function() return Buffie.db.profile.strobeTextHz or 0 end,
                                set = function(_, val)
                                    Buffie.db.profile.strobeTextHz = val
                                end,
                                order = 5,
                                disabled = function() return not Buffie.db.profile.strobeEnabled end,
                            },
                        },
                    },
                },
            },
            actions = {
                type = "group",
                name = "Reset/Save",
                order = 5,
                args = {
                    saveAll = {
                        type = "execute",
                        name = "Save All Settings",
                        func = function()
                            Buffie:SaveAllSettings()
                            Buffie:RestoreAllSettings()
                            Buffie:UpdateBuffies()
                        end,
                        order = 1,
                    },
                    resetDefaults = {
                        type = "execute",
                        name = "Reset to Defaults",
                        func = function()
                            local db = Buffie.db.profile
                            -- Buffs
                            db.fontSize = 12
                            db.displayMode = 0
                            db.iconScale = 1
                            db.iconAlpha = 1
                            db.timerAlpha = 1
                            db.colorThresholds = DeepCopyThresholds(defaultThresholds)
                            db.iconSpacing = 4
                            db.buffsPerRow = 8
                            db.maxRows = 2
                            db.unlocked = false
                            db.anchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -205, -13}
                            db.buffsUnlocked = false
                            -- Weapon enchants
                            db.weaponAnchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -265, -13}
                            db.weaponUnlocked = false
                            db.weaponPerRow = 2
                            db.weaponIconSpacing = 4
                            db.weaponIconScale = 1
                            db.weaponIconAlpha = 1
                            -- Debuffs
                            db.debuffAnchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -205, -65}
                            db.debuffUnlocked = false
                            db.debuffsPerRow = 8
                            db.debuffMaxRows = 2
                            db.debuffIconSpacing = 4
                            db.debuffIconScale = 1
                            db.debuffIconAlpha = 1
                            -- Other
                            db.useStaticColor = false
                            db.staticColor = {1, 1, 1}
                            db.strobeEnabled = false
                            db.strobeIconHz = 0
                            db.strobeTextHz = 0
                            db.strobeThresholdMin = 0
                            db.strobeThresholdSec = 10
                            Buffie:RestoreAllSettings()
                            Buffie:UpdateBuffies()
                        end,
                        order = 2,
                    },
                    resetBlizzard = {
                        type = "execute",
                        name = "Reset to Blizzard Defaults",
                        func = function()
                            Buffie:ResetToBlizzard()
                            Buffie:RestoreAllSettings()
                        end,
                        order = 3,
                    },
                },
            },
        }
    })
    self.optionsFrame = AceConfigDialog:AddToBlizOptions("BuffieSettings", "Buffie")
    self:RegisterChatCommand("bds", "OpenConfig")
    self:RegisterChatCommand("Buffie", "OpenConfig")
end

function Buffie:SaveAllSettings()
end

function Buffie:RestoreAllSettings()
    local db = Buffie and Buffie.db and Buffie.db.profile
    if not db then return end
    if BuffAnchorFrame and db.anchorPoint then
        BuffAnchorFrame:ClearAllPoints()
        local ap = db.anchorPoint
        local relTo = ap and ap[2] and (_G[ap[2]] or UIParent) or UIParent
        BuffAnchorFrame:SetPoint(ap[1] or "TOPRIGHT", relTo, ap[3] or "TOPRIGHT", ap[4] or -205, ap[5] or -13)
    end
    if WeaponEnchantAnchorFrame and db.weaponAnchorPoint then
        WeaponEnchantAnchorFrame:ClearAllPoints()
        local ap = db.weaponAnchorPoint
        local relTo = ap and ap[2] and (_G[ap[2]] or UIParent) or UIParent
        WeaponEnchantAnchorFrame:SetPoint(ap[1] or "TOPRIGHT", relTo, ap[3] or "TOPRIGHT", ap[4] or -265, ap[5] or -13)
    end
    if DebuffAnchorFrame and db.debuffAnchorPoint then
        DebuffAnchorFrame:ClearAllPoints()
        local ap = db.debuffAnchorPoint
        local relTo = ap and ap[2] and (_G[ap[2]] or UIParent) or UIParent
        DebuffAnchorFrame:SetPoint(ap[1] or "TOPRIGHT", relTo, ap[3] or "TOPRIGHT", ap[4] or -205, ap[5] or -65)
    end
end

-- After any settings change that affects anchor area, update the anchor frame size if it exists:
function Buffie:UpdateBuffies()
    if BuffAnchorFrame and BuffAnchorFrame.UpdateBackdrop then BuffAnchorFrame:UpdateBackdrop() end
    if WeaponEnchantAnchorFrame and WeaponEnchantAnchorFrame.UpdateBackdrop then WeaponEnchantAnchorFrame:UpdateBackdrop() end
    if DebuffAnchorFrame and DebuffAnchorFrame.UpdateBackdrop then DebuffAnchorFrame:UpdateBackdrop() end
    self:LayoutBuffs()
end

function Buffie:OnEnable()
    SecureBuffFrameUpdateHook()
    self:HookBuffies()
    self:RestoreAllSettings()
    if not self.updater then
        self.updater = CreateFrame("Frame")
        self.updater:SetScript("OnUpdate", TimerUpdater)
    end
    if self.UpdateBuffies then
        self:UpdateBuffies()
    end
end

function Buffie:OpenConfig()
    -- Open our own AceGUI config window (not Blizzard options panel)
    if not AceGUI then return end
    if self._configFrame and self._configFrame:IsShown() then
        self._configFrame:Hide()
        self._configFrame = nil
        return
    end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Buffie Settings")
    frame:SetStatusText("Buffie settings by Pegga")
    frame:SetLayout("Fill")
    frame:SetWidth(600)
    frame:SetHeight(800)
    frame:EnableResize(false)
    self._configFrame = frame

    -- Embed the options table in the AceGUI frame without calling AddToBlizOptions again
    local group = AceGUI:Create("SimpleGroup")
    group:SetFullWidth(true)
    group:SetFullHeight(true)
    frame:AddChild(group)

    -- Open the options in our AceGUI frame
    AceConfigDialog:Open("BuffieSettings", group)
end

SLASH_BUFFIE1 = "/buffie"
SlashCmdList["BUFFIE"] = function()
    if Buffie and Buffie.OpenConfig then
        Buffie:OpenConfig()
    end
end

local function OnPlayerLogin()
    if Buffie and Buffie.OnEnable then
        Buffie:OnEnable()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", OnPlayerLogin)
