-- Quiet Chat's bars: the game's player and target frames are hidden; thin bars take their place.
--   * You: health and power (mana, rage, energy) just above the experience bar: faint out of combat, solid in combat.
--   * Your enemy: a health bar with its name at the top of the screen, shown while it is your target;
--     the debuffs you put on it as small icons under the bar, from the left.
--   /quietchat bars    turn the bars off (the game's frames come back) or on again

-- The game's frames this replaces. They are protected: an add-on may not change them in combat, so they are
-- hidden with a state driver (the game itself then keeps them hidden, fights included), set out of combat only.
local HIDE = { "PlayerFrame", "TargetFrame", "TargetFrameToT" }
local UNIT_WATCHED = { TargetFrame = true, TargetFrameToT = true }   -- shown by the game while their unit exists
local WIDTH, HEIGHT, GAP = 0.085, 5, 3   -- player bars: share of the screen's width, pixels tall, pixels apart
local ABOVE_XP = 0.028                   -- player bars' bottom edge: share of the screen's height (just above the XP bar)
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
local health = makeBar(mine, HEIGHT)
health:SetStatusBarColor(0.1, 0.8, 0.1)
local power = makeBar(mine, HEIGHT)

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

-- Your debuffs on the enemy (DoTs and the like): small icons under its bar, from the left, with the game's own
-- countdown numbers. Only the ones you cast: the game filters them ("PLAYER"), nothing here compares values.
local DOT_SIZE, DOT_GAP, DOT_MAX = 14, 2, 8
local dots, dotError = {}, nil
for i = 1, DOT_MAX do
    local d = CreateFrame("Frame", nil, foe)
    d:SetSize(DOT_SIZE, DOT_SIZE)
    d:SetPoint("TOPLEFT", foeBar, "BOTTOMLEFT", (i - 1) * (DOT_SIZE + DOT_GAP), -3)
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetAllPoints()
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.cd = CreateFrame("Cooldown", nil, d, "CooldownFrameTemplate")
    d.cd:SetAllPoints()
    d.cd:SetDrawEdge(false)
    d.cd:SetDrawSwipe(false)
    if d.cd.SetHideCountdownNumbers then d.cd:SetHideCountdownNumbers(false) end
    local numbers = d.cd.GetCountdownFontString and d.cd:GetCountdownFontString()
    if numbers then numbers:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE") end
    d:Hide()
    dots[i] = d
end

-- The time left goes to the cooldown frame as the game hands it over: a duration object where the game has one
-- (secret values), otherwise start and length.
local function setTime(d, aura)
    if C_UnitAuras.GetAuraDuration and d.cd.SetCooldownFromDurationObject then
        local ok = pcall(function()
            d.cd:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration(d.unit, aura.auraInstanceID))
        end)
        if ok then return end
    end
    if not pcall(function() d.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration) end) then
        d.cd:SetCooldown(0, 0)
    end
end

-- Forever may refuse add-ons the target's auras while they are secret (in combat). So several ways are tried, in
-- order, and the first that the game allows is kept: through "target", or through the target's nameplate unit
-- (where Plater reads them); "HARMFUL|PLAYER" (only yours) before "HARMFUL" (all debuffs).
local dotWay, dotWayTold = nil, false
local function unitsToTry()
    local units = { "target" }
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
    if plate and plate.namePlateUnitToken then units[2] = plate.namePlateUnitToken end
    return units
end
local function readAuras(unit, filter)
    if C_UnitAuras.GetUnitAuras then return C_UnitAuras.GetUnitAuras(unit, filter, DOT_MAX) end
    local list = {}
    for i = 1, DOT_MAX do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
        if not aura then break end
        list[i] = aura
    end
    return list
end
local function myDebuffs()
    local lastErr
    for _, unit in ipairs(unitsToTry()) do
        for _, filter in ipairs({ "HARMFUL|PLAYER", "HARMFUL" }) do
            local ok, list = pcall(readAuras, unit, filter)
            if ok then
                local way = (unit == "target" and "target" or "nameplate") .. " " .. filter
                if way ~= dotWay then dotWay, dotWayTold = way, false end
                return list, unit
            end
            lastErr = list
        end
    end
    error(lastErr)
end

local function showDots()
    local n = 0
    local list, unit = myDebuffs()
    for i, aura in ipairs(list) do
        if i > DOT_MAX then break end
        n = i
        local d = dots[i]
        d.unit = unit
        d.icon:SetTexture(aura.icon)
        setTime(d, aura)
        d:Show()
    end
    for i = n + 1, DOT_MAX do dots[i]:Hide() end
end

local function layout()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    mine:ClearAllPoints()
    mine:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, h * ABOVE_XP)
    mine:SetSize(w * WIDTH, HEIGHT * 2 + GAP)
    health:ClearAllPoints()
    health:SetPoint("TOPLEFT", mine, "TOPLEFT")
    health:SetPoint("TOPRIGHT", mine, "TOPRIGHT")
    power:ClearAllPoints()
    power:SetPoint("BOTTOMLEFT", mine, "BOTTOMLEFT")
    power:SetPoint("BOTTOMRIGHT", mine, "BOTTOMRIGHT")
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

    -- You: always there, faint out of combat (whether health is full can't be known: see fill)
    local powerType, token = UnitPowerType("player")
    local c = PowerBarColor and (PowerBarColor[token] or PowerBarColor[powerType])
    if c then power:SetStatusBarColor(c.r, c.g, c.b) end
    fill(health, UnitHealth("player"), UnitHealthMax("player"))
    fill(power, UnitPower("player", powerType), UnitPowerMax("player", powerType))
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
        -- If the game refuses the auras anyway: no icons, the error once in the box, and the bar carries on
        local ok, err = pcall(showDots)
        if not ok then
            for i = 1, DOT_MAX do dots[i]:Hide() end
            dotError = err
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
    if ok and dotError then ok, err, dotError = false, "debuff icons: " .. tostring(dotError), nil end
    if dotWay and not dotWayTold and UnitAffectingCombat("player") then
        dotWayTold = true
        report("debuff icons in combat via " .. dotWay)
    end
    if not ok and not reported[err] then
        reported[err] = true
        report("error: " .. tostring(err))
    end
    if shownAt and GetTime() - shownAt < 20 then
        mine:SetAlpha(1)
    end
end
local function onEvent(_, event)
    local ok, err = pcall(layout)
    if not ok then report("layout error: " .. tostring(err)) return end
    if event == "PLAYER_ENTERING_WORLD" then
        shownAt = GetTime()
        local l, b, w, h = mine:GetRect()
        report(format("loaded; bars at x %d, y %d, %d x %d; health bar %d wide; screen %d x %d",
            l or -1, b or -1, w or -1, h or -1, health:GetWidth() or -1, UIParent:GetWidth(), UIParent:GetHeight()))
    end
end

local tick = 0
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("DISPLAY_SIZE_CHANGED")
driver:RegisterEvent("UI_SCALE_CHANGED")
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
