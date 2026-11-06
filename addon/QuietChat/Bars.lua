-- Quiet Chat's bars: the game's player and target frames are hidden; thin bars take their place.
--   * You: health and power (mana, rage, energy) just above the action bar, shown in combat or when not full.
--   * Your enemy: a health bar with its name at the top of the screen, shown while you fight it.
--   /quietchat bars    turn the bars off (the game's frames come back) or on again

local HIDE = { "PlayerFrame", "TargetFrame", "TargetFrameToT" }
local WIDTH, HEIGHT, GAP = 0.17, 5, 3    -- player bars: share of the screen's width, pixels tall, pixels apart
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

-- You: above the action bar, at the bottom centre
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
foeName:SetPoint("BOTTOM", foeBar, "TOP", 0, 4)

local function layout()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    mine:ClearAllPoints()
    mine:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, h * 0.30)
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

local function ratio(value, max)
    if not max or max <= 0 then return 0 end
    return value / max
end

-- Fade toward a target alpha a little each tick
local function fade(frame, want)
    local a = frame:GetAlpha()
    if math.abs(a - want) < 0.05 then frame:SetAlpha(want) else frame:SetAlpha(a + (want - a) * 0.35) end
end

local function update()
    local db = settings()
    if not db then return end
    local on = db.bars
    for _, name in ipairs(HIDE) do
        local f = _G[name]
        if f then f:SetAlpha(on and 0 or 1) end
    end
    if not on then
        mine:SetAlpha(0)
        foe:SetAlpha(0)
        return
    end
    local fighting = UnitAffectingCombat("player")

    -- You
    local hp = ratio(UnitHealth("player"), UnitHealthMax("player"))
    local powerType, token = UnitPowerType("player")
    local pw = ratio(UnitPower("player", powerType), UnitPowerMax("player", powerType))
    health:SetValue(hp)
    power:SetValue(pw)
    local c = PowerBarColor and (PowerBarColor[token] or PowerBarColor[powerType])
    if c then power:SetStatusBarColor(c.r, c.g, c.b) end
    -- Rage starts empty: it only matters in a fight. Mana and energy matter when not full.
    local powerShort = token ~= "RAGE" and pw < 0.999
    fade(mine, (fighting or hp < 0.999 or powerShort) and 1 or 0)

    -- Your enemy: only something you can attack, while you or it are fighting
    local enemy = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
    if enemy and (fighting or UnitAffectingCombat("target")) then
        foeBar:SetValue(ratio(UnitHealth("target"), UnitHealthMax("target")))
        local level = UnitLevel("target")
        foeName:SetText(format("%s  |cffaaaaaa%s|r", UnitName("target") or "", (level and level > 0) and level or "??"))
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

local tick = 0
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("DISPLAY_SIZE_CHANGED")
driver:RegisterEvent("UI_SCALE_CHANGED")
driver:SetScript("OnEvent", layout)
driver:SetScript("OnUpdate", function(_, dt)
    tick = tick + dt
    if tick > 0.1 then
        tick = 0
        update()
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
