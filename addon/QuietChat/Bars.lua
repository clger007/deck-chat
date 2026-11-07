-- Quiet Chat's bars: the game's player and target frames are hidden; thin bars take their place.
--   * You: health and power (mana, rage, energy) as percentages either side of your character, green on the left,
--     the power colour on the right: faint out of combat, solid in combat.
--   * Your enemy: a health bar with its name at the top of the screen, shown while it is your target;
--     the debuffs you cast on it as small icons under the bar, drawn by the game (AuraContainer).
--   /quietchat bars    turn the bars off (the game's frames come back) or on again

-- The game's frames this replaces. They are protected: an add-on may not change them in combat, so they are
-- hidden with a state driver (the game itself then keeps them hidden, fights included), set out of combat only.
local HIDE = { "PlayerFrame", "TargetFrame", "TargetFrameToT" }
local UNIT_WATCHED = { TargetFrame = true, TargetFrameToT = true }   -- shown by the game while their unit exists
local SIDE, BELOW, FONT_SIZE = 0.07, 0.06, 18   -- your numbers: share of the screen's width out from the centre,
                                               -- share of its height below the centre, text size
local ENEMY_WIDTH, ENEMY_HEIGHT = 0.30, 8

local function settings()
    local db = QuietChatDB
    if not db then return nil end
    if db.bars == nil then db.bars = true end
    return db
end

local function makeBar(parent, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetColorTexture(0, 0, 0, 0.6)
    return bar
end

-- You: just above the experience bar, at the bottom centre
local mine = CreateFrame("Frame", "QuietChatPlayerBars", UIParent)
mine:SetFrameStrata("LOW")
mine:SetAlpha(0)
mine:SetAllPoints(UIParent)
local function makeNumber(justify)
    local text = mine:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", FONT_SIZE, "OUTLINE")
    text:SetShadowOffset(1, -1)
    text:SetJustifyH(justify)
    return text
end
local health = makeNumber("RIGHT")
health:SetTextColor(0.25, 1, 0.3)
local power = makeNumber("LEFT")

-- Your enemy: at the top centre, its name over it
local foe = CreateFrame("Frame", "QuietChatTargetBar", UIParent)
foe:SetFrameStrata("LOW")
foe:SetAlpha(0)
local foeBar = makeBar(foe, ENEMY_HEIGHT)
foeBar:SetStatusBarColor(0.8, 0.1, 0.1)
local foeName = foe:CreateFontString(nil, "OVERLAY", "GameFontNormal")
foeName:SetPoint("BOTTOM", foeBar, "TOP", -10, 4)
local foeLevel = foe:CreateFontString(nil, "OVERLAY", "GameFontDisable")
foeLevel:SetPoint("LEFT", foeName, "RIGHT", 6, 0)

-- Your debuffs on the enemy (DoTs and the like): small icons under its bar, from the left, with seconds left.
-- Add-ons may not read auras in combat, so the game draws them itself in an AuraContainer; this only says where,
-- how big, and which: "HARMFUL|PLAYER", the ones you cast. Clients without AuraContainer get no icons.
local DOT_SIZE, DOT_GAP, DOT_MAX = 14, 2, 8
local dots
local function makeDots()
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")) then
        return "this game has no AuraContainer"
    end
    local seconds = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and C_StringUtil.CreateNumericRuleFormatter()
    if seconds then   -- 45, then 3m from a minute on
        seconds:AddBreakpoint({ threshold = 0, step = 1, format = "%d" })
        seconds:AddBreakpoint({ threshold = 60, format = "%dm", components = { { div = 60, step = 1 } } })
    end
    local layout = { elementSpacing = DOT_GAP, lineSpacing = DOT_GAP, groupLineSpacing = DOT_GAP,
        elementWidth = DOT_SIZE, elementHeight = DOT_SIZE, maximumLineSize = math.huge }
    local c = CreateFrame("AuraContainer", "QuietChatTargetDebuffs", foe, "CustomAuraContainerTemplate")
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT", foeBar, "BOTTOMLEFT", 0, -3)
    c:AddAuraGroup("mine", "HARMFUL|PLAYER", {
        maxFrameCount = DOT_MAX,
        sortMethod = AuraContainerSortMethod.Default,
        sortDirection = AuraContainerSortDirection.Normal,
        layout = layout,
        initializeFrame = function(button)
            button:SetSize(DOT_SIZE, DOT_SIZE)
            button.Icon = button:CreateTexture(nil, "ARTWORK")
            button.Icon:SetAllPoints()
            button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            button:SetIcon(button.Icon)
            button.Seconds = button:CreateFontString(nil, "OVERLAY")
            button.Seconds:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
            button.Seconds:SetPoint("CENTER", 0, 0)
            button:SetDurationText(button.Seconds, { textFormatter = seconds })
        end,
    })
    c:SetAuraGroupLayout("mine", layout)
    c:SetFlowLayoutAnchorPoint("TOPLEFT")
    c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    c:SetFlowLayoutMaximumLineSize(math.huge)
    c:SetEnabled(true)
    c:SetUnit("target")
    dots = c
end

local function layout()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    health:ClearAllPoints()
    health:SetPoint("RIGHT", UIParent, "CENTER", -w * SIDE, -h * BELOW)
    power:ClearAllPoints()
    power:SetPoint("LEFT", UIParent, "CENTER", w * SIDE, -h * BELOW)
    foe:ClearAllPoints()
    foe:SetPoint("TOP", UIParent, "TOP", 0, -h * 0.07)
    foe:SetSize(w * ENEMY_WIDTH, ENEMY_HEIGHT + 20)
    foeBar:ClearAllPoints()
    foeBar:SetPoint("BOTTOMLEFT", foe, "BOTTOMLEFT")
    foeBar:SetPoint("BOTTOMRIGHT", foe, "BOTTOMRIGHT")
end

-- WoW Forever gives add-ons health and power as "secret values": they may be handed to a bar to draw, but
-- not calculated with or compared. So the bars get the raw values, and nothing here does arithmetic on them.
local function fill(bar, value, max)
    bar:SetMinMaxValues(0, max)
    bar:SetValue(value)
end

-- Fade toward a target alpha a little each tick
local function fade(frame, want)
    local a = frame:GetAlpha()
    if math.abs(a - want) < 0.05 then frame:SetAlpha(want) else frame:SetAlpha(a + (want - a) * 0.35) end
end

local hiddenState, pending = nil, false
local function hideFrames(on)
    if hiddenState == on then return end
    if InCombatLockdown() then pending = true return end
    for _, name in ipairs(HIDE) do
        local f = _G[name]
        if f then
            if on then
                if UNIT_WATCHED[name] and UnregisterUnitWatch then UnregisterUnitWatch(f) end
                RegisterStateDriver(f, "visibility", "hide")
            else
                UnregisterStateDriver(f, "visibility")
                if UNIT_WATCHED[name] and RegisterUnitWatch then RegisterUnitWatch(f) else f:Show() end
            end
        end
    end
    hiddenState, pending = on, false
end

local function update()
    local db = settings()
    if not db then return end
    local on = db.bars
    if pending or hiddenState ~= on then hideFrames(on) end
    if not on then
        mine:SetAlpha(0)
        foe:SetAlpha(0)
        return
    end
    local fighting = UnitAffectingCombat("player")

    -- You: always there, faint out of combat (whether health is full can't be known: see fill). The game turns
    -- health and power into a percentage (0-100) itself; the secret number goes straight into the text.
    local powerType, token = UnitPowerType("player")
    local c = PowerBarColor and (PowerBarColor[token] or PowerBarColor[powerType])
    if c then power:SetTextColor(c.r, c.g, c.b) end
    health:SetText(format("%d%%", UnitHealthPercent("player", true, CurveConstants.ScaleTo100)))
    power:SetText(format("%d%%", UnitPowerPercent("player", powerType, false, CurveConstants.ScaleTo100)))
    fade(mine, fighting and 1 or 0.45)

    -- Your enemy: anything you can attack, as soon as it is your target
    local enemy = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
    if enemy then
        fill(foeBar, UnitHealth("target"), UnitHealthMax("target"))
        -- Name and level go straight to the text (they may be secret values too: no joining or comparing)
        foeName:SetText(UnitName("target"))
        foeLevel:SetText(UnitLevel("target"))
        if UnitIsPlayer("target") or UnitReaction("player", "target") and UnitReaction("player", "target") <= 3 then
            foeBar:SetStatusBarColor(0.8, 0.1, 0.1)
        else
            foeBar:SetStatusBarColor(0.85, 0.7, 0.1)   -- neutral: yellow, as the game colours it
        end
        fade(foe, 1)
    else
        fade(foe, 0)
    end
end

-- Diagnosis: report any error of the bar code, once each, in the pop-up box (the chat window is hidden),
-- and the bars' place and size at load; show them for the first 20 seconds whatever the situation.
local reported, shownAt = {}, nil
local function report(text)
    if QuietChatBox then QuietChatBox:AddMessage("|cffff8080Quiet Chat bars:|r " .. text, 1, 0.8, 0.8) end
end
local function safeUpdate()
    local ok, err = pcall(update)
    if not ok and not reported[err] then
        reported[err] = true
        report("error: " .. tostring(err))
    end
    if shownAt and GetTime() - shownAt < 20 then
        mine:SetAlpha(1)
    end
end
local _, dotsWhy = pcall(makeDots)
local dotsTold = false
local function onEvent(_, event)
    local ok, err = pcall(layout)
    if not ok then report("layout error: " .. tostring(err)) return end
    if event == "PLAYER_TARGET_CHANGED" then
        if dots then
            local ok, err = pcall(function() dots:SetUnit("target") dots:UpdateAllAuras() end)
            if not ok and not reported[err] then reported[err] = true report("debuff icons: " .. tostring(err)) end
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        shownAt = GetTime()
        local l, b = health:GetCenter()
        if not dotsTold then
            dotsTold = true
            report(dots and "debuff icons on (AuraContainer)" or ("no debuff icons: " .. tostring(dotsWhy)))
        end
        report(format("loaded; health number at x %d, y %d; screen %d x %d",
            l or -1, b or -1, UIParent:GetWidth(), UIParent:GetHeight()))
    end
end

local tick = 0
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("DISPLAY_SIZE_CHANGED")
driver:RegisterEvent("UI_SCALE_CHANGED")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:SetScript("OnEvent", onEvent)
driver:SetScript("OnUpdate", function(_, dt)
    tick = tick + dt
    if tick > 0.1 then
        tick = 0
        safeUpdate()
    end
end)

function QuietChat_ToggleBars()
    local db = settings()
    if not db then return end
    db.bars = not db.bars
    update()
    print("Quiet Chat bars " .. (db.bars and "on: thin bars instead of the player and target frames"
        or "off: the game's player and target frames are back"))
end
