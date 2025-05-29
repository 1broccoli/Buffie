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
        useStaticColor = false,
        staticColor = {1, 1, 1},
        -- Strobe feature defaults
        strobeEnabled = false,
        strobeIconHz = 0,      -- Hz, 0 = off
        strobeTextHz = 0,      -- Hz, 0 = off
        strobeThresholdMin = 0,
        strobeThresholdSec = 10,
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

    BuffAnchorFrame:SetScript("OnDragStart", function(self)
        isDragging = true
        self:StartMoving()
    end)
    BuffAnchorFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        isDragging = false
        SaveAnchorPosition()
        Buffie:SaveAllSettings()
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
            if db.iconScale and button.SetScale then
                button:SetScale(db.iconScale)
            end
            if db.iconAlpha and button.SetAlpha then
                button:SetAlpha(db.iconAlpha)
            elseif button.icon and button.icon.SetAlpha then
                button.icon:SetAlpha(db.iconAlpha or 1)
            end

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
    local anchor = CreateBuffAnchor()
    local spacing = db.iconSpacing or 4
    local perRow = db.buffsPerRow or 8
    local maxRows = db.maxRows or 2
    local scale = db.iconScale or 1
    local iconSize = 32 * scale

    local parent = db.unlocked and anchor or UIParent
    local totalBuffs = BUFF_ACTUAL_DISPLAY or 32
    local shownCount = 0
    local maxBuffs = perRow * maxRows

    if anchor.SafeRestoreAnchorPosition then
        anchor:SafeRestoreAnchorPosition()
    else
        RestoreAnchorPosition()
    end

    if db.unlocked then
        local width = perRow * iconSize + (perRow-1)*spacing
        local height = maxRows * iconSize + (maxRows-1)*spacing
        anchor:SetSize(width, height)
        anchor:Show()
        anchor:SetFrameStrata("DIALOG")
        anchor:SetFrameLevel(100)
        anchor:EnableMouse(true)
    else
        anchor:Hide()
    end

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
            button:SetScale(scale)
            button:SetAlpha(db.iconAlpha or 1)
            button:Show()
            local row = math.floor((i-1) / perRow)
            local col = (i-1) % perRow
            if row == 0 and col == 0 then
                button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
            elseif col == 0 then
                local prevRowBtn = visibleBuffs[i - perRow]
                button:SetPoint("TOPRIGHT", prevRowBtn, "BOTTOMRIGHT", 0, -spacing)
            else
                local prevBtn = visibleBuffs[i - 1]
                button:SetPoint("RIGHT", prevBtn, "LEFT", -spacing, 0)
            end
            shownCount = shownCount + 1
            if db.unlocked then
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
                    -- Icon strobe (only icon)
                    if (db.strobeIconHz or 0) > 0 then
                        strobeState[button].iconPhase = (strobeState[button].iconPhase or 0) + elapsed
                        local freq = db.strobeIconHz
                        local alpha = 0.5 + 0.5 * math.sin(2 * math.pi * freq * strobeState[button].iconPhase)
                        if button.SetAlpha then button:SetAlpha(alpha) end
                        if button.icon and button.icon.SetAlpha then button.icon:SetAlpha(alpha) end
                    else
                        if button.SetAlpha then button:SetAlpha(db.iconAlpha or 1) end
                        if button.icon and button.icon.SetAlpha then button.icon:SetAlpha(db.iconAlpha or 1) end
                        strobeState[button].iconPhase = 0
                    end
                    -- Text strobe (only timer text)
                    if (db.strobeTextHz or 0) > 0 then
                        strobeState[button].textPhase = (strobeState[button].textPhase or 0) + elapsed
                        local freq = db.strobeTextHz
                        local alpha = 0.5 + 0.5 * math.sin(2 * math.pi * freq * strobeState[button].textPhase)
                        if button.duration and button.duration.SetAlpha then button.duration:SetAlpha(alpha) end
                    else
                        if button.duration and button.duration.SetAlpha then button.duration:SetAlpha(db.timerAlpha or 1) end
                        strobeState[button].textPhase = 0
                    end
                else
                    -- Reset to normal if above threshold
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
local aceguiTestTicker = nil
local aceguiTestTime = 125

local function StopTestTicker()
    if aceguiTestTicker then
        Buffie:CancelTimer(aceguiTestTicker)
        aceguiTestTicker = nil
    end
end

local function OpenAceGUIConfig()
    if aceguiFrame then
        StopTestTicker()
        aceguiFrame:Hide()
        aceguiFrame = nil
    end

    local db = Buffie.db.profile

    aceguiFrame = AceGUI:Create("Frame")
    aceguiFrame:SetTitle("Settings")
    aceguiFrame:SetStatusText("Buffie settings by Pegga")
    aceguiFrame:SetLayout("List")
    aceguiFrame:SetWidth(450)
    aceguiFrame:SetHeight(935)
    aceguiFrame:EnableResize(false)

    aceguiFrame:SetCallback("OnClose", function(widget)
        StopTestTicker()
        if aceguiFrame then
            aceguiFrame:Hide()
            aceguiFrame = nil
        end
    end)

    local displayDropdown = AceGUI:Create("Dropdown")
    displayDropdown:SetLabel("Display Mode")
    displayDropdown:SetList(displayModeList)
    displayDropdown:SetValue(db.displayMode)
    displayDropdown:SetWidth(200)
    displayDropdown:SetCallback("OnValueChanged", function(_,_,val)
        db.displayMode = val
        Buffie:UpdateBuffies()
        if aceguiFrame.exampleBox then
            local t = tonumber(aceguiFrame.exampleBox:GetText()) or aceguiTestTime
            aceguiFrame.exampleLabel:SetText("Example: |cff00ff00" .. FormatBuffieExample(t, db.displayMode) .. "|r")
        end
    end)
    aceguiFrame:AddChild(displayDropdown)

    local exampleGroup = AceGUI:Create("InlineGroup")
    exampleGroup:SetFullWidth(true)
    exampleGroup:SetLayout("Flow")
    exampleGroup:SetTitle("Preview")

    local exampleBox = AceGUI:Create("EditBox")
    exampleBox:SetLabel("Test Time (seconds)")
    exampleBox:SetWidth(120)
    exampleBox:SetText(tostring(aceguiTestTime))
    exampleGroup:AddChild(exampleBox)

    local exampleLabel = AceGUI:Create("Label")
    exampleLabel:SetText("Example: |cff00ff00" .. FormatBuffieExample(aceguiTestTime, db.displayMode) .. "|r")
    exampleLabel:SetWidth(250)
    exampleGroup:AddChild(exampleLabel)

    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetLayout("Flow")
    btnGroup:SetFullWidth(false)

    local startBtn = AceGUI:Create("Button")
    startBtn:SetText("Start")
    startBtn:SetWidth(80)
    btnGroup:AddChild(startBtn)

    local stopBtn = AceGUI:Create("Button")
    stopBtn:SetText("Stop")
    stopBtn:SetWidth(80)
    btnGroup:AddChild(stopBtn)

    exampleGroup:AddChild(btnGroup)

    aceguiFrame.exampleBox = exampleBox
    aceguiFrame.exampleLabel = exampleLabel

    local function updateExampleLabel(val)
        local t = tonumber(val) or 0
        aceguiTestTime = t
        if aceguiFrame and aceguiFrame.exampleLabel then
            aceguiFrame.exampleLabel:SetText("Example: |cff00ff00" .. FormatBuffieExample(t, db.displayMode) .. "|r")
        end
    end

    exampleBox:SetCallback("OnEnterPressed", function(_,_,val)
        updateExampleLabel(val)
    end)
    exampleBox:SetCallback("OnFocusLost", function(widget)
        updateExampleLabel(widget:GetText())
    end)

    local function tick()
        if not aceguiFrame then
            StopTestTicker()
            return
        end
        if aceguiTestTime > 0 then
            aceguiTestTime = aceguiTestTime - 1
            if aceguiFrame.exampleBox then
                aceguiFrame.exampleBox:SetText(tostring(aceguiTestTime))
            end
            if aceguiFrame.exampleLabel then
                aceguiFrame.exampleLabel:SetText("Example: |cff00ff00" .. FormatBuffieExample(aceguiTestTime, db.displayMode) .. "|r")
            end
        else
            StopTestTicker()
        end
    end

    startBtn:SetCallback("OnClick", function()
        StopTestTicker()
        aceguiTestTime = tonumber(aceguiFrame.exampleBox:GetText()) or 0
        if aceguiFrame.exampleLabel then
            aceguiFrame.exampleLabel:SetText("Example: |cff00ff00" .. FormatBuffieExample(aceguiTestTime, db.displayMode) .. "|r")
        end
        aceguiTestTicker = Buffie:ScheduleRepeatingTimer(tick, 1)
    end)

    stopBtn:SetCallback("OnClick", function()
        StopTestTicker()
    end)

    aceguiFrame:AddChild(exampleGroup)

    local fontSlider = AceGUI:Create("Slider")
    fontSlider:SetLabel("Font Size")
    fontSlider:SetSliderValues(8, 24, 1)
    fontSlider:SetValue(db.fontSize)
    fontSlider:SetWidth(320)
    fontSlider:SetCallback("OnValueChanged", function(_,_,val)
        db.fontSize = val
        Buffie:UpdateBuffies()
    end)
    aceguiFrame:AddChild(fontSlider)

    local iconScaleSlider = AceGUI:Create("Slider")
    iconScaleSlider:SetLabel("Buff Icon Scale")
    iconScaleSlider:SetSliderValues(0.5, 2, 0.01)
    iconScaleSlider:SetValue(db.iconScale or 1)
    iconScaleSlider:SetWidth(320)
    iconScaleSlider:SetCallback("OnValueChanged", function(_,_,val)
        db.iconScale = val
        Buffie:UpdateBuffies()
    end)
    aceguiFrame:AddChild(iconScaleSlider)

    local iconAlphaSlider = AceGUI:Create("Slider")
    iconAlphaSlider:SetLabel("Buff Icon Transparency")
    iconAlphaSlider:SetSliderValues(0, 1, 0.01)
    iconAlphaSlider:SetValue(db.iconAlpha or 1)
    iconAlphaSlider:SetWidth(320)
    iconAlphaSlider:SetCallback("OnValueChanged", function(_,_,val)
        db.iconAlpha = val
        Buffie:UpdateBuffies()
    end)
    aceguiFrame:AddChild(iconAlphaSlider)

    local timerAlphaSlider = AceGUI:Create("Slider")
    timerAlphaSlider:SetLabel("Timer Text Transparency")
    timerAlphaSlider:SetSliderValues(0, 1, 0.01)
    timerAlphaSlider:SetValue(db.timerAlpha or 1)
    timerAlphaSlider:SetWidth(320)
    timerAlphaSlider:SetCallback("OnValueChanged", function(_,_,val)
        db.timerAlpha = val
        Buffie:UpdateBuffies()
    end)
    aceguiFrame:AddChild(timerAlphaSlider)

    local thresholdsLabel = AceGUI:Create("Label")
    thresholdsLabel:SetText("Color Thresholds (minutes, seconds, operator, color):")
    aceguiFrame:AddChild(thresholdsLabel)

    local function RefreshThresholds()
        if aceguiFrame.thresholdsGroup then
            aceguiFrame.thresholdsGroup:Hide()
            aceguiFrame.thresholdsGroup = nil
        end

        local group = AceGUI:Create("SimpleGroup")
        group:SetFullWidth(true)
        group:SetLayout("List")
        aceguiFrame.thresholdsGroup = group
        aceguiFrame:AddChild(group)

        for i, entry in ipairs(db.colorThresholds) do
            local row = AceGUI:Create("InlineGroup")
            row:SetLayout("Flow")
            row:SetFullWidth(true)
            row:SetTitle("Threshold " .. i)

            local opDropdown = AceGUI:Create("Dropdown")
            opDropdown:SetLabel("Op")
            opDropdown:SetList({["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=", ["="] = "="})
            opDropdown:SetValue(entry.op or "<=")
            opDropdown:SetWidth(60)
            opDropdown:SetCallback("OnValueChanged", function(_,_,val)
                entry.op = val
                if Buffie and Buffie.UpdateBuffies and type(Buffie.UpdateBuffies) == "function" then
                    pcall(function() Buffie:UpdateBuffies() end)
                end
            end)
            row:AddChild(opDropdown)

            local minEdit = AceGUI:Create("EditBox")
            minEdit:SetLabel("Min")
            minEdit:SetWidth(50)
            minEdit:SetText(entry.min ~= nil and tostring(entry.min) or "0")
            minEdit:SetCallback("OnEnterPressed", function(_,_,val)
                local num = tonumber(val) or 0
                if num < 0 then num = 0 end
                entry.min = num
                minEdit:SetText(tostring(entry.min))
                if Buffie and Buffie.UpdateBuffies and type(Buffie.UpdateBuffies) == "function" then
                    pcall(function() Buffie:UpdateBuffies() end)
                end
            end)
            minEdit:SetCallback("OnFocusLost", function(widget)
                local num = tonumber(widget:GetText()) or 0
                if num < 0 then num = 0 end
                widget:SetText(tostring(num))
                entry.min = num
                if Buffie and Buffie.UpdateBuffies and type(Buffie.UpdateBuffies) == "function" then
                    pcall(function() Buffie:UpdateBuffies() end)
                end
            end)
            row:AddChild(minEdit)

            local secEdit = AceGUI:Create("EditBox")
            secEdit:SetLabel("Sec")
            secEdit:SetWidth(50)
            secEdit:SetText(entry.sec ~= nil and tostring(entry.sec) or "0")
            secEdit:SetCallback("OnEnterPressed", function(_,_,val)
                local num = tonumber(val) or 0
                if num < 0 then num = 0 end
                entry.sec = num
                secEdit:SetText(tostring(entry.sec))
                if Buffie and Buffie.UpdateBuffies and type(Buffie.UpdateBuffies) == "function" then
                    pcall(function() Buffie:UpdateBuffies() end)
                end
            end)
            secEdit:SetCallback("OnFocusLost", function(widget)
                local num = tonumber(widget:GetText()) or 0
                if num < 0 then num = 0 end
                widget:SetText(tostring(num))
                entry.sec = num
                if Buffie and Buffie.UpdateBuffies and type(Buffie.UpdateBuffies) == "function" then
                    pcall(function() Buffie:UpdateBuffies() end)
                end
            end)
            row:AddChild(secEdit)

            local colorPicker = AceGUI:Create("ColorPicker")
            colorPicker:SetLabel("Color")
            colorPicker:SetHasAlpha(false)
            colorPicker:SetColor(unpack(entry.color))
            colorPicker:SetCallback("OnValueChanged", function(_,_,r,g,b)
                entry.color = {r,g,b}
                if Buffie and Buffie.UpdateBuffies and type(Buffie.UpdateBuffies) == "function" then
                    pcall(function() Buffie:UpdateBuffies() end)
                end
            end)
            row:AddChild(colorPicker)

            group:AddChild(row)
        end
    end

    RefreshThresholds()

    local spacingSlider = AceGUI:Create("Slider")
    spacingSlider:SetLabel("Buff Icon Spacing: " .. tostring(db.iconSpacing or 4))
    spacingSlider:SetSliderValues(0, 32, 1)
    spacingSlider:SetValue(db.iconSpacing or 4)
    spacingSlider:SetWidth(320)
    spacingSlider:SetCallback("OnValueChanged", function(_,_,val)
        db.iconSpacing = val
        spacingSlider:SetLabel("Buff Icon Spacing: " .. tostring(val))
        Buffie:UpdateBuffies()
    end)
    aceguiFrame:AddChild(spacingSlider)

    local perRowSlider = AceGUI:Create("Slider")
    perRowSlider:SetLabel("Buffs Per Row: " .. tostring(db.buffsPerRow or 8))
    perRowSlider:SetSliderValues(1, 16, 1)
    perRowSlider:SetValue(db.buffsPerRow or 8)
    perRowSlider:SetWidth(320)
    perRowSlider:SetCallback("OnValueChanged", function(_,_,val)
        db.buffsPerRow = val
        perRowSlider:SetLabel("Buffs Per Row: " .. tostring(val))
        Buffie:UpdateBuffies()
    end)
    aceguiFrame:AddChild(perRowSlider)

    local maxRowsSlider = AceGUI:Create("Slider")
    maxRowsSlider:SetLabel("Max Rows: " .. tostring(db.maxRows or 2))
    maxRowsSlider:SetSliderValues(1, 8, 1)
    maxRowsSlider:SetValue(db.maxRows or 2)
    maxRowsSlider:SetWidth(320)
    maxRowsSlider:SetCallback("OnValueChanged", function(_,_,val)
        db.maxRows = val
        maxRowsSlider:SetLabel("Max Rows: " .. tostring(val))
        Buffie:UpdateBuffies()
    end)
    aceguiFrame:AddChild(maxRowsSlider)

    local unlockBtn = AceGUI:Create("Button")
    unlockBtn:SetText(db.unlocked and "Lock Buffs" or "Unlock Buffs")
    unlockBtn:SetWidth(160)
    unlockBtn:SetCallback("OnClick", function()
        db.unlocked = not db.unlocked
        unlockBtn:SetText(db.unlocked and "Lock Buffs" or "Unlock Buffs")
        if not db.unlocked then
            SaveAnchorPosition()
            Buffie:SaveAllSettings()
        end
        Buffie:UpdateBuffies()
    end)
    aceguiFrame:AddChild(unlockBtn)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save All Settings")
    saveBtn:SetWidth(160)
    saveBtn:SetCallback("OnClick", function()
        Buffie:SaveAllSettings()
        Buffie:RestoreAllSettings()
        Buffie:UpdateBuffies()
    end)
    aceguiFrame:AddChild(saveBtn)

    local resetBtn = AceGUI:Create("Button")
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetWidth(160)
    resetBtn:SetCallback("OnClick", function()
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
        Buffie:RestoreAllSettings()
        Buffie:UpdateBuffies()
    end)
    aceguiFrame:AddChild(resetBtn)

    local resetBlizzardBtn = AceGUI:Create("Button")
    resetBlizzardBtn:SetText("Reset to Blizzard Defaults")
    resetBlizzardBtn:SetWidth(200)
    resetBlizzardBtn:SetCallback("OnClick", function()
        Buffie:ResetToBlizzard()
        Buffie:RestoreAllSettings()
    end)
    aceguiFrame:AddChild(resetBlizzardBtn)

    local strobeGroup = AceGUI:Create("Group")
    strobeGroup:SetTitle("Strobe Effect")
    strobeGroup:SetLayout("Flow")
    strobeGroup:SetFullWidth(true)
    strobeGroup:SetOrder(9)

    local strobeEnabled = AceGUI:Create("CheckBox")
    strobeEnabled:SetLabel("Enable Strobe")
    strobeEnabled:SetValue(db.strobeEnabled)
    strobeEnabled:SetCallback("OnValueChanged", function(_, _, value)
        db.strobeEnabled = value
        Buffie:UpdateBuffies()
    end)
    strobeGroup:AddChild(strobeEnabled)

    local strobeIconHz = AceGUI:Create("Slider")
    strobeIconHz:SetLabel("Icon Strobe Speed (Hz, 0=off)")
    strobeIconHz:SetSliderValues(0, 5, 0.1)
    strobeIconHz:SetValue(db.strobeIconHz or 0)
    strobeIconHz:SetWidth(320)
    strobeIconHz:SetCallback("OnValueChanged", function(_,_,val)
        db.strobeIconHz = val
        Buffie:UpdateBuffies()
    end)
    strobeGroup:AddChild(strobeIconHz)

    local strobeTextHz = AceGUI:Create("Slider")
    strobeTextHz:SetLabel("Text Strobe Speed (Hz, 0=off)")
    strobeTextHz:SetSliderValues(0, 5, 0.1)
    strobeTextHz:SetValue(db.strobeTextHz or 0)
    strobeTextHz:SetWidth(320)
    strobeTextHz:SetCallback("OnValueChanged", function(_,_,val)
        db.strobeTextHz = val
        Buffie:UpdateBuffies()
    end)
    strobeGroup:AddChild(strobeTextHz)

    local strobeThresholdMin = AceGUI:Create("EditBox")
    strobeThresholdMin:SetLabel("Strobe Threshold Minutes")
    strobeThresholdMin:SetWidth(80)
    strobeThresholdMin:SetText(tostring(db.strobeThresholdMin or 0))
    strobeThresholdMin:SetCallback("OnEnterPressed", function(_,_,val)
        local num = tonumber(val) or 0
        if num < 0 then num = 0 end
        db.strobeThresholdMin = num
        strobeThresholdMin:SetText(tostring(db.strobeThresholdMin))
        Buffie:UpdateBuffies()
    end)
    strobeGroup:AddChild(strobeThresholdMin)

    local strobeThresholdSec = AceGUI:Create("EditBox")
    strobeThresholdSec:SetLabel("Strobe Threshold Seconds")
    strobeThresholdSec:SetWidth(80)
    strobeThresholdSec:SetText(tostring(db.strobeThresholdSec or 0))
    strobeThresholdSec:SetCallback("OnEnterPressed", function(_,_,val)
        local num = tonumber(val) or 0
        if num < 0 then num = 0 end
        db.strobeThresholdSec = num
        strobeThresholdSec:SetText(tostring(db.strobeThresholdSec))
        Buffie:UpdateBuffies()
    end)
    strobeGroup:AddChild(strobeThresholdSec)

    aceguiFrame:AddChild(strobeGroup)
end

local blizzardDefaults = {
    fontSize = 12,
    displayMode = 1,
    colorThresholds = DeepCopyThresholds(defaultThresholds),
    iconScale = 1,
    iconAlpha = 1,
    timerAlpha = 1,
    iconSpacing = 0,
    buffsPerRow = 8,
    maxRows = 2,
    unlocked = false,
    anchorPoint = {"TOPRIGHT", "UIParent", "TOPRIGHT", -205, -13},
}

function Buffie:ResetToBlizzard()
    local db = self.db.profile
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
                        name = "Test Timer",
                        inline = true,
                        order = 0,
                        args = {
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
                                order = 1,
                            },
                            testExample = {
                                type = "description",
                                name = function()
                                    if Buffie._testTicker then
                                        local now = GetTime()
                                        if not Buffie._testExampleLast or now - Buffie._testExampleLast >= 1 then
                                            Buffie._testExampleLast = now
                                            if Buffie._testTime and Buffie._testTime > 0 then
                                                Buffie._testTime = Buffie._testTime - 1
                                            end
                                        end
                                    end
                                    local tval = tonumber(Buffie._testTime or 125)
                                    local mode = Buffie.db.profile.displayMode
                                    return "|cff00ff00Example: " .. FormatBuffieExample(tval, mode) .. "|r"
                                end,
                                width = "full",
                                order = 2,
                            },
                            testStart = {
                                type = "execute",
                                name = "",
                                desc = "Play",
                                image = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
                                imageWidth = 20,
                                imageHeight = 20,
                                func = function()
                                    if Buffie._testTicker then Buffie:CancelTimer(Buffie._testTicker) end
                                    Buffie._testTime = tonumber(Buffie._testTime or 125)
                                    Buffie._testTicker = Buffie:ScheduleRepeatingTimer(function()
                                        if Buffie._testTime and Buffie._testTime > 0 then
                                            Buffie._testTime = Buffie._testTime - 1
                                        else
                                            if Buffie._testTicker then Buffie:CancelTimer(Buffie._testTicker) end
                                            Buffie._testTicker = nil
                                        end
                                    end, 1)
                                end,
                                width = 0.15,
                                order = 3,
                            },
                            testStop = {
                                type = "execute",
                                name = "",
                                desc = "Stop",
                                image = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
                                imageWidth = 20,
                                imageHeight = 20,
                                func = function()
                                    if Buffie._testTicker then Buffie:CancelTimer(Buffie._testTicker) end
                                    Buffie._testTicker = nil
                                end,
                                width = 0.15,
                                order = 4,
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
                        },
                    },
                    layout = {
                        type = "group",
                        name = "Layout",
                        order = 3,
                        inline = true,
                        args = {
                            iconSpacing = {
                                type = "range",
                                name = "Buff Icon Spacing",
                                min = 0, max = 32, step = 1,
                                get = function() return Buffie.db.profile.iconSpacing or 4 end,
                                set = function(_, val)
                                    Buffie.db.profile.iconSpacing = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 1,
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
                                order = 2,
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
                                order = 3,
                            },
                            unlocked = {
                                type = "toggle",
                                name = "Unlock Buffs (Drag Anchor)",
                                desc = "Unlock to move the buff anchor.",
                                get = function() return Buffie.db.profile.unlocked end,
                                set = function(_, val)
                                    Buffie.db.profile.unlocked = val
                                    Buffie:UpdateBuffies()
                                end,
                                order = 4,
                            },
                        },
                    },
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
                            strobeIconHz = {
                                type = "range",
                                name = "Icon Strobe Speed (Hz, 0=off)",
                                desc = "How many fades per second. 0 disables icon strobe.",
                                min = 0, max = 5, step = 0.1,
                                get = function() return Buffie.db.profile.strobeIconHz or 0 end,
                                set = function(_, val)
                                    Buffie.db.profile.strobeIconHz = val
                                end,
                                order = 2,
                                disabled = function() return not Buffie.db.profile.strobeEnabled end,
                            },
                            strobeTextHz = {
                                type = "range",
                                name = "Text Strobe Speed (Hz, 0=off)",
                                desc = "How many fades per second. 0 disables text strobe.",
                                min = 0, max = 5, step = 0.1,
                                get = function() return Buffie.db.profile.strobeTextHz or 0 end,
                                set = function(_, val)
                                    Buffie.db.profile.strobeTextHz = val
                                end,
                                order = 3,
                                disabled = function() return not Buffie.db.profile.strobeEnabled end,
                            },
                            strobeThresholdMin = {
                                type = "input",
                                name = "Strobe Threshold Minutes",
                                desc = "Buffs with less than this many minutes+seconds left will strobe.",
                                get = function() return tostring(Buffie.db.profile.strobeThresholdMin or 0) end,
                                set = function(_, val)
                                    local v = tonumber(val) or 0
                                    if v < 0 then v = 0 end
                                    Buffie.db.profile.strobeThresholdMin = v
                                end,
                                order = 4,
                                width = 0.5,
                                disabled = function() return not Buffie.db.profile.strobeEnabled end,
                            },
                            strobeThresholdSec = {
                                type = "input",
                                name = "Strobe Threshold Seconds",
                                desc = "Buffs with less than this many minutes+seconds left will strobe.",
                                get = function() return tostring(Buffie.db.profile.strobeThresholdSec or 0) end,
                                set = function(_, val)
                                    local v = tonumber(val) or 0
                                    if v < 0 then v = 0 end
                                    Buffie.db.profile.strobeThresholdSec = v
                                end,
                                order = 5,
                                width = 0.5,
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
end

function Buffie:UpdateBuffies()
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
    OpenAceGUIConfig()
end

SLASH_BDS1 = "/bds"
SlashCmdList["BDS"] = function()
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
