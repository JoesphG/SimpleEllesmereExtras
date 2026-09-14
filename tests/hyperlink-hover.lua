local FILE = "HyperlinkHover.lua"

local Widget = {}
Widget.__index = Widget
local function nop() end
local created = {}
local function W(kind, name)
    local w = setmetatable({ kind = kind, name = name, scripts = {}, events = {} }, Widget)
    if name then
        _G[name] = w
    end
    created[#created + 1] = w -- the boot frame is anonymous; scan this, not _G
    return w
end
function Widget:HookScript(s, f)
    self.scripts[s] = f
end
function Widget:SetScript(s, f)
    self.scripts[s] = f
end
function Widget:RegisterEvent(e)
    self.events[e] = true
end
function Widget:UnregisterEvent(e)
    self.events[e] = nil
end
function Widget:IsForbidden()
    return false
end

local tip = { shown = false, owner = nil, link = nil, forbidden = false }
GameTooltip = setmetatable({
    IsForbidden = function()
        return tip.forbidden
    end,
    SetOwner = function(_, f, anchor)
        tip.owner, tip.anchor = f, anchor
    end,
    SetHyperlink = function(_, l)
        if l == "item:BOOM" then
            error("bad link")
        end
        tip.link = l
    end,
    Show = function()
        tip.shown = true
    end,
    Hide = function()
        tip.shown = false
        tip.link = nil
    end,
}, {})

local inCombat = false
InCombatLockdown = function()
    return inCombat
end
strmatch = string.match
local secrets = {}
issecretvalue = function(v)
    return secrets[v] == true
end
CreateFrame = function(k, n)
    return W(k, n)
end
local hooks = {}
hooksecurefunc = function(name, fn)
    hooks[name] = fn
end
SlashCmdList = {}
local printed = {}
print = function(...)
    local t = {}
    for i = 1, select("#", ...) do
        t[#t + 1] = tostring((select(i, ...)))
    end
    printed[#printed + 1] = table.concat(t, " ")
end

local chat1, chat2 = W("Frame", "ChatFrame1"), W("Frame", "ChatFrame2")
CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
FCF_OpenTemporaryWindow = nop
FCF_OpenNewWindow = nop
local ns = {}
CreateFrame = CreateFrame
    or function()
        return {
            RegisterEvent = function() end,
            SetScript = function(s, k, f)
                s[k] = f
            end,
        }
    end
assert(loadfile("Core.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile(FILE))("SimpleEllesmereExtras", ns)

local out = io.write
local fails = 0
local function check(n, ok, extra)
    if ok then
        out("  ok   " .. n .. "\n")
    else
        fails = fails + 1
        out("  FAIL " .. n .. (extra and (" -- " .. tostring(extra)) or "") .. "\n")
    end
end
out("HyperlinkHover test\n")

-- Boot
local boot
for _, f in ipairs(created) do
    if f.events and f.events.PLAYER_LOGIN then
        boot = f
    end
end
check("waits for PLAYER_LOGIN", boot ~= nil)
boot.scripts.OnEvent(boot)
check("hooked every chat frame", chat1.scripts.OnHyperlinkEnter and chat2.scripts.OnHyperlinkEnter)
check("hooked the wheel too", chat1.scripts.OnMouseWheel ~= nil)
check("catches temporary windows", hooks.FCF_OpenTemporaryWindow ~= nil)

local enter = chat1.scripts.OnHyperlinkEnter
local leave = chat1.scripts.OnHyperlinkLeave
local wheel = chat1.scripts.OnMouseWheel

-- Item preview
enter(chat1, "item:12345:0:0:0")
check("item link previews", tip.shown and tip.link == "item:12345:0:0:0", tip.link)
check("anchored to the cursor", tip.anchor == "ANCHOR_CURSOR")
leave(chat1)
check("hides on leave", tip.shown == false)

for _, l in ipairs({ "spell:100", "quest:5:2", "achievement:1", "keystone:1:2" }) do
    enter(chat1, l)
    check("previews " .. l:match("^[^:]+"), tip.shown == true)
    leave(chat1)
end

-- The whitelist is the point: these must NOT be handed to SetHyperlink.
for _, l in ipairs({ "player:Bob", "BNplayer:Bob", "channel:1", "url:http://x", "garrmission:1" }) do
    tip.shown = false
    enter(chat1, l)
    check("ignores " .. l:match("^[^:]+"), tip.shown == false)
end

-- Guards
inCombat = true
tip.shown = false
enter(chat1, "item:1")
check("no preview in combat", tip.shown == false)
inCombat = false

tip.forbidden = true
tip.shown = false
enter(chat1, "item:1")
check("respects a forbidden tooltip", tip.shown == false)
tip.forbidden = false

local secret = "item:secret"
secrets[secret] = true
tip.shown = false
enter(chat1, secret)
check("skips a secret link", tip.shown == false)

tip.shown = false
enter(chat1, nil)
check("survives a nil link", tip.shown == false)

-- A link SetHyperlink rejects must not error out of the chat frame's handler.
tip.shown = false
local ok = pcall(enter, chat1, "item:BOOM")
check("a rejected link does not error", ok == true)
check("and leaves no tooltip up", tip.shown == false)

-- Scrolling strands the tooltip otherwise: no OnHyperlinkLeave fires.
enter(chat1, "item:1")
check("preview up before scrolling", tip.shown == true)
wheel(chat1)
check("wheel closes the preview", tip.shown == false)

-- A leave from a different frame must not close this one's preview.
enter(chat1, "item:1")
chat2.scripts.OnMouseWheel(chat2)
check("another frame's wheel is ignored", tip.shown == true)
leave(chat1)

-- Toggle
check("defaults on", SimpleEllesmereExtrasDB.hyperlinkHover == nil)
SlashCmdList.EUIHOVER()
check("slash turns it off", SimpleEllesmereExtrasDB.hyperlinkHover == false)
tip.shown = false
enter(chat1, "item:1")
check("disabled means no preview", tip.shown == false)
SlashCmdList.EUIHOVER()
enter(chat1, "item:1")
check("slash turns it back on", tip.shown == true)

out(fails == 0 and "\nall checks passed\n" or ("\n" .. fails .. " failed\n"))
os.exit(fails == 0 and 0 or 1)
