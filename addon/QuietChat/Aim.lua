-- Quiet Chat's aim: with a controller, spells go to the enemy under the centre dot right now.
--   SoftTargetForce 1        your target follows your aim (enemies)
--   SoftTargetMatchLocked 0  the aim doesn't stick to an enemy you attacked
--   SoftTargetEnemyArc 0     only what is straight ahead, not "nearby"
-- Set at every login, for every character (the game also keeps them per character on its servers).
--   /quietchat aim    turn this off (the values from before come back) or on again

local AIM = { SoftTargetForce = "1", SoftTargetMatchLocked = "0", SoftTargetEnemyArc = "0" }

local function apply()
    local db = QuietChatDB
    if not db or InCombatLockdown() then return end
    if db.aim == nil then db.aim = true end
    db.aimBefore = db.aimBefore or {}
    for cvar, value in pairs(AIM) do
        if db.aim then
            if db.aimBefore[cvar] == nil then db.aimBefore[cvar] = GetCVar(cvar) end
            SetCVar(cvar, value)
        elseif db.aimBefore[cvar] ~= nil then
            SetCVar(cvar, db.aimBefore[cvar])
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", apply)

function QuietChat_ToggleAim()
    local db = QuietChatDB
    if not db then return end
    if InCombatLockdown() then
        print("Quiet Chat: change the aim after this fight")
        return
    end
    db.aim = not db.aim
    apply()
    print("Quiet Chat aim " .. (db.aim and "on: spells go to the enemy under your aim"
        or "off: the game's own aim settings are back"))
end
