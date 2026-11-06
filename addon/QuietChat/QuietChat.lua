-- Quiet Chat: chat like a messenger.
--   * The game's chat window stays out of sight unless you open it to type.
--   * Messages meant for you (whispers, party, raid, instance, guild) pop up in a small box, then fade.
--   * A chat window holds everything (the last 400 lines, kept across /reload), with filters:
--     All, Whispers, Party, Guild, General, Trade, Say. Controller: D-pad left/right (or LB/RB) picks a
--     filter, D-pad up/down scrolls, B closes.
--   /qc                open or close the chat window (also a key binding: Key Bindings > Quiet Chat)
--   /quietchat         turn the hidden chat on or off
--   /quietchat test    a test line in the pop-up box
--   /quietchat bars    thin health / power / enemy bars instead of the player and target frames (Bars.lua)
--   /quietchat targets the LB / RB targeting pictures above the gamepad bar, hidden or shown (Tidy.lua)
--   /quietchat aim     spells go to the enemy under the centre dot, or the game's own aim (Aim.lua)

local DEFAULTS = { enabled = true, seconds = 15 }
local KEEP = 400            -- lines of history kept
local POPUP = { whisper = true, party = true, guild = true }

-- chat event → { filter, chat type for the colour, tag shown }
local EVENTS = {
    CHAT_MSG_WHISPER = { "whisper", "WHISPER", "From" },
    CHAT_MSG_WHISPER_INFORM = { "whisper", "WHISPER_INFORM", "To" },
    CHAT_MSG_BN_WHISPER = { "whisper", "BN_WHISPER", "From" },
    CHAT_MSG_BN_WHISPER_INFORM = { "whisper", "BN_WHISPER_INFORM", "To" },
    CHAT_MSG_PARTY = { "party", "PARTY", "Party" },
    CHAT_MSG_PARTY_LEADER = { "party", "PARTY_LEADER", "Party" },
    CHAT_MSG_RAID = { "party", "RAID", "Raid" },
    CHAT_MSG_RAID_LEADER = { "party", "RAID_LEADER", "Raid" },
    CHAT_MSG_RAID_WARNING = { "party", "RAID_WARNING", "Raid" },
    CHAT_MSG_INSTANCE_CHAT = { "party", "INSTANCE_CHAT", "Instance" },
    CHAT_MSG_INSTANCE_CHAT_LEADER = { "party", "INSTANCE_CHAT_LEADER", "Instance" },
    CHAT_MSG_GUILD = { "guild", "GUILD", "Guild" },
    CHAT_MSG_OFFICER = { "guild", "OFFICER", "Officer" },
    CHAT_MSG_SAY = { "say", "SAY", "Say" },
    CHAT_MSG_YELL = { "say", "YELL", "Yell" },
    CHAT_MSG_EMOTE = { "say", "EMOTE", nil },
    CHAT_MSG_CHANNEL = { "channel", "CHANNEL", nil },
}
local FILTERS = {
    { key = "all", label = "All" }, { key = "whisper", label = "Whispers" }, { key = "party", label = "Party" },
    { key = "guild", label = "Guild" }, { key = "general", label = "General" }, { key = "trade", label = "Trade" },
    { key = "say", label = "Say" },
}

local db
local filter = 1

---------------------------------------------------------------------------
-- One chat line: what to show, which filter it belongs to, its colour
---------------------------------------------------------------------------
local function colour(chatType)
    local info = ChatTypeInfo and ChatTypeInfo[chatType]
    if info then return info.r, info.g, info.b end
    return 1, 1, 1
end

local function short(name)
    if not name or name == "" then return "" end
    if Ambiguate and not name:find("|K", 1, true) then return Ambiguate(name, "short") end
    return name
end

local function makeLine(event, ...)
    local spec = EVENTS[event]
    local text, sender = ...
    text, sender = text or "", short(sender)
    local kind, chatType, tag = spec[1], spec[2], spec[3]
    if event == "CHAT_MSG_CHANNEL" then
        local channelName, index, base = select(4, ...), select(8, ...), select(9, ...)
        base = (base and base ~= "") and base or (channelName or ""):match("^%d+%.%s*(%S+)") or "Channel"
        kind = base:find("^General") and "general" or base:find("^Trade") and "trade" or "other"
        chatType = index and ("CHANNEL" .. index) or "CHANNEL"
        tag = base
    end
    local body
    if event == "CHAT_MSG_EMOTE" then
        body = sender .. " " .. text
    elseif sender ~= "" then
        body = format("[%s] %s: %s", tag, sender, text)
    else
        body = format("[%s] %s", tag, text)
    end
    return { t = time(), k = kind, c = chatType, s = body }
end

---------------------------------------------------------------------------
-- The pop-up box: messages to you, fading on their own, where the chat sits
---------------------------------------------------------------------------
local box = CreateFrame("ScrollingMessageFrame", "QuietChatBox", UIParent)
box:SetSize(430, 110)
box:SetPoint("BOTTOMLEFT", ChatFrame1, "BOTTOMLEFT", 0, 0)
box:SetFontObject(ChatFontNormal)
box:SetJustifyH("LEFT")
box:SetInsertMode("BOTTOM")
box:SetMaxLines(8)
box:SetFading(true)
box:SetFadeDuration(1.5)
box:SetTimeVisible(DEFAULTS.seconds)
box:SetFrameStrata("MEDIUM")
box:EnableMouse(false)

---------------------------------------------------------------------------
-- The chat window
---------------------------------------------------------------------------
local win = CreateFrame("Frame", "QuietChatWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
win:SetSize(660, 440)
win:SetPoint("CENTER", 0, 20)
win:SetFrameStrata("DIALOG")
win:SetToplevel(true)
win:EnableMouse(true)
win:Hide()
if win.SetBackdrop then
    win:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
end
tinsert(UISpecialFrames, "QuietChatWindow") -- Esc closes it

local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18)
title:SetText("Chat")

local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)

local log = CreateFrame("ScrollingMessageFrame", nil, win)
log:SetPoint("TOPLEFT", 22, -82)
log:SetPoint("BOTTOMRIGHT", -22, 40)
log:SetFontObject(ChatFontNormal)
log:SetJustifyH("LEFT")
log:SetInsertMode("BOTTOM")
log:SetMaxLines(KEEP)
log:SetFading(false)
log:EnableMouseWheel(true)
log:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
end)

local help = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
help:SetPoint("BOTTOM", 0, 18)
help:SetText("D-pad left / right: filter     up / down: scroll     B: close")

local buttons = {}
local function refresh()
    local want = FILTERS[filter].key
    for i, b in ipairs(buttons) do
        if i == filter then b:LockHighlight() else b:UnlockHighlight() end
    end
    log:Clear()
    for _, line in ipairs(db.history) do
        if want == "all" or line.k == want then
            log:AddMessage(format("|cff808080%s|r %s", date("%H:%M", line.t), line.s), colour(line.c))
        end
    end
    log:ScrollToBottom()
end

local function setFilter(i)
    filter = ((i - 1) % #FILTERS) + 1
    refresh()
end

local width = (660 - 44 - (#FILTERS - 1) * 4) / #FILTERS
for i, f in ipairs(FILTERS) do
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetPoint("TOPLEFT", 22 + (i - 1) * (width + 4), -46)
    b:SetText(f.label)
    b:SetScript("OnClick", function() setFilter(i) end)
    buttons[i] = b
end

-- The controller drives the window while it is open
win:SetScript("OnGamePadButtonDown", function(_, button)
    if button == "PADDLEFT" or button == "PADLSHOULDER" then
        setFilter(filter - 1)
    elseif button == "PADDRIGHT" or button == "PADRSHOULDER" then
        setFilter(filter + 1)
    elseif button == "PADDUP" then
        for _ = 1, 3 do log:ScrollUp() end
    elseif button == "PADDDOWN" then
        for _ = 1, 3 do log:ScrollDown() end
    elseif button == "PAD2" then
        win:Hide()
    end
    return false
end)
win:SetScript("OnShow", function(self)
    if self.EnableGamePadButton then pcall(self.EnableGamePadButton, self, true) end
    refresh()
end)
win:SetScript("OnHide", function(self)
    if self.EnableGamePadButton then pcall(self.EnableGamePadButton, self, false) end
end)

function QuietChat_Toggle()
    if not db then return end
    win:SetShown(not win:IsShown())
end
BINDING_HEADER_QUIETCHAT = "Quiet Chat"
BINDING_NAME_QUIETCHAT_TOGGLE = "Open / close the chat window"

---------------------------------------------------------------------------
-- The game's chat window: out of sight while the chat isn't open
---------------------------------------------------------------------------
-- By name: some of these may not exist in this version of the game
local PARTS = { "ChatFrame1", "ChatFrame1Tab", "GeneralDockManager", "ChatFrame1ButtonFrame",
                "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton", "ChatFrame1EditBox" }

local function chatOpen()
    local eb = ChatFrame1EditBox
    return eb and eb:IsShown() and eb:HasFocus()
end

local function apply()
    local show = (not db.enabled) or chatOpen()
    for _, name in ipairs(PARTS) do
        local f = _G[name]
        if f then f:SetAlpha(show and 1 or 0) end
    end
    box:SetShown(db.enabled and not show and not win:IsShown())
end

-- The game fades chat tabs in and out by itself: put our look back a few times a second
local elapsed = 0
local keeper = CreateFrame("Frame")
keeper:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed > 0.2 then
        elapsed = 0
        if db then apply() end
    end
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function remember(line)
    local h = db.history
    h[#h + 1] = line
    while #h > KEEP do table.remove(h, 1) end
    if win:IsShown() then
        local want = FILTERS[filter].key
        if want == "all" or line.k == want then
            log:AddMessage(format("|cff808080%s|r %s", date("%H:%M", line.t), line.s), colour(line.c))
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
for event in pairs(EVENTS) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= "QuietChat" then return end
        QuietChatDB = QuietChatDB or {}
        db = QuietChatDB
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        db.history = type(db.history) == "table" and db.history or {}
        box:SetTimeVisible(db.seconds)
        apply()
        return
    end
    if not db then return end
    local line = makeLine(event, ...)
    remember(line)
    if db.enabled and POPUP[line.k] then box:AddMessage(line.s, colour(line.c)) end
end)

SLASH_QUIETCHATWINDOW1 = "/qc"
SlashCmdList.QUIETCHATWINDOW = function() QuietChat_Toggle() end

SLASH_QUIETCHAT1 = "/quietchat"
SlashCmdList.QUIETCHAT = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "test" then
        box:AddMessage("[From] Quiet Chat: messages to you show here, then fade.", colour("WHISPER"))
        return
    elseif msg == "window" then
        QuietChat_Toggle()
        return
    elseif msg == "bars" then
        QuietChat_ToggleBars()
        return
    elseif msg == "targets" then
        QuietChat_ToggleTargets()
        return
    elseif msg == "aim" then
        QuietChat_ToggleAim()
        return
    end
    db.enabled = not db.enabled
    apply()
    print("Quiet Chat " .. (db.enabled and "on: the chat shows when you open it" or "off: the chat shows as usual"))
end
