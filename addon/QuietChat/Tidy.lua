-- Quiet Chat's tidy-up: hides the LB / RB targeting pictures above the gamepad bar (the green and red
-- crosshairs, their backgrounds and their "pressed" glows). They are pictures only: LB and RB target the
-- same with or without them. The bar is protected, so this runs out of combat only.
--   /quietchat targets    show or hide them

local PARTS = { "LeftShoulderBackground", "LeftShoulderIcon", "LeftShoulderHighlight",
                "RightShoulderBackground", "RightShoulderIcon", "RightShoulderHighlight" }

local function apply()
    local db = QuietChatDB
    local unit = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
    if not db or not unit or InCombatLockdown() then return end
    if db.hideTargets == nil then db.hideTargets = true end
    for _, key in ipairs(PARTS) do
        local tex = unit[key]
        if tex then tex:SetAlpha(db.hideTargets and 0 or 1) end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")   -- after a fight, in case the game showed them again
f:SetScript("OnEvent", function()
    if GamepadMainActionBarFrame and GamepadMainActionBarFrame.SetShoulderIcons and not f.hooked then
        hooksecurefunc(GamepadMainActionBarFrame, "SetShoulderIcons", apply)   -- the game redraws them
        f.hooked = true
    end
    apply()
end)

function QuietChat_ToggleTargets()
    local db = QuietChatDB
    if not db then return end
    db.hideTargets = not db.hideTargets
    if InCombatLockdown() then
        print("Quiet Chat: the targeting pictures change after this fight")
    end
    apply()
end
