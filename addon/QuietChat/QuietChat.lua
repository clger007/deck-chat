-- Quiet Chat: the chat window stays out of sight unless you open it to type. Messages meant for you
-- (whispers, party, raid, guild, instance) appear in a small box of their own, then fade. Public
-- channels (General, Trade...) never show unless you open the chat.
--   /quietchat         on / off
--   /quietchat test    show a test line in the box

local DEFAULTS = { enabled = true, seconds = 15 }

-- What reaches the box: the game's chat event → the chat type its colour comes from
local EVENTS = {
    CHAT_MSG_WHISPER = "WHISPER", CHAT_MSG_WHISPER_INFORM = "WHISPER_INFORM",
    CHAT_MSG_BN_WHISPER = "BN_WHISPER", CHAT_MSG_BN_WHISPER_INFORM = "BN_WHISPER_INFORM",
    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY_LEADER",
    CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID_LEADER", CHAT_MSG_RAID_WARNING = "RAID_WARNING",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT", CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT_LEADER",
    CHAT_MSG_GUILD = "GUILD", CHAT_MSG_OFFICER = "OFFICER",
}
local TAGS = {
    WHISPER = "From", WHISPER_INFORM = "To", BN_WHISPER = "From", BN_WHISPER_INFORM = "To",
    PARTY = "Party", PARTY_LEADER = "Party", RAID = "Raid", RAID_LEADER = "Raid", RAID_WARNING = "Raid",
    INSTANCE_CHAT = "Instance", INSTANCE_CHAT_LEADER = "Instance", GUILD = "Guild", OFFICER = "Officer",
}

local db

-- The box: a few lines that fade on their own, where the chat sits
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

-- The game's chat parts that stay out of sight while the chat isn't open (by name: some may not exist
-- in this version of the game)
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
    box:SetShown(db.enabled and not show)
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

local function add(chatType, text, sender)
    local info = ChatTypeInfo and ChatTypeInfo[chatType]
    local r, g, b = 1, 1, 1
    if info then r, g, b = info.r, info.g, info.b end
    local who = sender or ""
    if Ambiguate and who ~= "" and not who:find("|K", 1, true) then who = Ambiguate(who, "short") end
    local tag = TAGS[chatType] or chatType
    local line = (who ~= "" and format("[%s] %s: %s", tag, who, text)) or format("[%s] %s", tag, text)
    box:AddMessage(line, r, g, b)
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
        box:SetTimeVisible(db.seconds)
        apply()
        return
    end
    if not db or not db.enabled then return end
    local text, sender = ...
    add(EVENTS[event], text or "", sender)
end)

SLASH_QUIETCHAT1 = "/quietchat"
SlashCmdList.QUIETCHAT = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "test" then
        add("WHISPER", "Quiet Chat test: messages to you show here, then fade.", "Quiet Chat")
        return
    end
    db.enabled = not db.enabled
    apply()
    print("Quiet Chat " .. (db.enabled and "on: the chat shows when you open it" or "off: the chat shows as usual"))
end
