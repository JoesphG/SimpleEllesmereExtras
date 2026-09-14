-- Builds the REAL options window against a frame stub that raises on any
-- method it was not given, then walks every page twice.
--
-- It proves the window builds and redraws, not that it looks right. Twice
-- matters: widgets are pooled and reconfigured rather than rebuilt, so a
-- second pass is where a stale row or a missing Configure shows up.
--
-- Separate process from tests/model.lua, which installs no frames at all.
local frames = dofile("tests/frames.lua")
frames.install()

local ns = {}

SlashCmdList = {}
C_AddOns = {
    IsAddOnLoaded = function(name)
        return name == "Baganator"
    end,
}
DEFAULT_CHAT_FRAME = {
    GetFont = function()
        return "Fonts\\ARIALN.TTF", 13, ""
    end,
}
ReloadUI = function()
    _G.__reloaded = true
end

assert(loadfile("Core.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile("Gate.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile("UI/Model.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile("UI/Widgets.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile("UI/Panel.lua"))("SimpleEllesmereExtras", ns)

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

out("Panel test\n")

-- Skinned through EllesmereUI when it is there. The colours are the only thing
-- taken from it, so the window matches the suite instead of approximating it.
ns.S = {
    GetAccentColor = function()
        return 0.047, 0.824, 0.616
    end,
    GetPanelColor = function()
        return 0.06, 0.07, 0.08, 0.96
    end,
}

local ok, err = pcall(ns.Panel.Open)
check("the window builds", ok, err)
check("and is shown", ns.Panel.IsShown() == true)

-- Every page, twice. The second pass is the one that catches a pooled row that
-- was never reconfigured.
for pass = 1, 2 do
    for _, page in ipairs(ns.Model.Pages()) do
        local shown, e = pcall(ns.Panel.ShowPage, page.key)
        check(("pass %d: %s draws"):format(pass, page.key), shown, e)
    end
end

-- A switch clicked in the panel has to reach the saved table and come back.
ns.Panel.ShowPage("general")
local row
for _, page in ipairs(ns.Model.Pages()) do
    for _, section in ipairs(page.sections) do
        for _, r in ipairs(section.rows) do
            if r.label == "Emoji in chat" then
                row = r
            end
        end
    end
end
row.set(false)
check("a switch writes to the saved table", SimpleEllesmereExtrasDB.emoji == false)
local redrawn = pcall(ns.Panel.Refresh)
check("and the panel redraws on top of it", redrawn)
row.set(true)

-- Without EllesmereUI the window still has to build: the chat features work
-- without it, so the options for them must too.
ns.S = nil
local bare, bareErr = pcall(ns.Panel.Refresh)
check("it builds with no EllesmereUI at all", bare, bareErr)
ns.S = {}

-- Closing and reopening must not rebuild the window, because a WoW frame
-- cannot be destroyed and a second one would leak for the session.
ns.Panel.Close()
check("closes", ns.Panel.IsShown() == false)
local reopened = pcall(ns.Panel.Open)
check("reopens", reopened and ns.Panel.IsShown() == true)

-- The AddOns list entry.
ns.Panel.RegisterSettingsCategory()
check("registers a Blizzard settings category", frames.categoryRegistered == true)

-- /see toggles it.
check("slash command registered", SLASH_SEE1 == "/see" and SlashCmdList.SEE ~= nil)
SlashCmdList.SEE("")
check("slash closes an open window", ns.Panel.IsShown() == false)
SlashCmdList.SEE("")
check("and opens a closed one", ns.Panel.IsShown() == true)

out(fails == 0 and "\nall checks passed\n" or ("\n" .. fails .. " failed\n"))
os.exit(fails == 0 and 0 or 1)
