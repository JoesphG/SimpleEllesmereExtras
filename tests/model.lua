-- The options panel as data. No frames, so this runs under plain Lua and
-- asserts on the model directly -- which is the whole reason Model.lua creates
-- none. Panel.lua is covered separately, in tests/panel.lua.
local ns = {}

SlashCmdList = {}
CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function() end,
        UnregisterEvent = function() end,
    }
end
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

assert(loadfile("Core.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile("Gate.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile("UI/Model.lua"))("SimpleEllesmereExtras", ns)

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

local function Find(label)
    for _, page in ipairs(ns.Model.Pages()) do
        for _, section in ipairs(page.sections) do
            for _, row in ipairs(section.rows) do
                if row.label == label then
                    return row, page
                end
            end
        end
    end
end

out("Model test\n")

ns.S = {} -- EllesmereUI present
local pages = ns.Model.Pages()
check("three pages", #pages == 3, #pages)
check("general is first", pages[1].key == "general", pages[1].key)

-- Every switch round-trips through the saved table. A row that reads one key
-- and writes another is the classic options-panel bug.
for _, label in ipairs({
    "Link preview on hover",
    "Emoji in chat",
    "Missing enchant or gem alert",
    "Baganator skin",
    "Window packs",
}) do
    local row = Find(label)
    if not row then
        check("row exists: " .. label, false)
    else
        check("defaults on: " .. label, row.get() == true)
        row.set(false)
        check("writes through: " .. label, ns.Model.Pages() and Find(label).get() == false)
        row.set(true)
        check("and back: " .. label, Find(label).get() == true)
    end
end

-- Every pack has a row, and the master switch disables them rather than hiding
-- them: a control that vanishes reads as a bug, one greyed with a reason does not.
for _, pack in ipairs(ns.PACKS) do
    local row = Find(pack.label)
    check("pack row: " .. pack.label, row ~= nil and row.kind == "check")
end

local fonts = Find("Fonts across windows")
check("a pack is enabled while the master switch is on", fonts.disabled() == nil)
Find("Window packs").set(false)
check("master off disables a pack row", fonts.disabled() ~= nil, tostring(fonts.disabled()))
check("and says why", tostring(fonts.disabled()):find("master") ~= nil, fonts.disabled())
Find("Window packs").set(true)

-- Emoji size falls back to the chat font rather than showing a stale constant.
local size = Find("Emoji size")
check("size row is a slider", size.kind == "slider")
check("unset size shows the chat font size", size.get() == 13, size.get())
size.set(20)
check("setting it pins the value", size.get() == 20, size.get())
SimpleEllesmereExtrasDB.emojiSize = nil

-- Without EllesmereUI nothing that skins is applied, however its switch reads.
ns.S = nil
check("skins report unavailable", ns.SkinsAvailable() == false)
check("the gear alert row says so", tostring(Find("Missing enchant or gem alert").disabled()):find("not loaded") ~= nil)
check("status text says so", ns.StatusText():find("not loaded") ~= nil, ns.StatusText())
ns.S = {}

check("status counts the packs applied", ns.StatusText():find("6 of 6") ~= nil, ns.StatusText())
Find("Fonts across windows").set(false)
check("and follows a pack being switched off", ns.StatusText():find("5 of 6") ~= nil, ns.StatusText())

-- Every command is listed WITH what it does. The page used to be a bare
-- comma-separated list of names, which tells a reader nothing.
local commands = 0
for _, page in ipairs(ns.Model.Pages()) do
    for _, section in ipairs(page.sections) do
        for _, row in ipairs(section.rows) do
            if row.kind == "command" then
                commands = commands + 1
                check("command starts with a slash: " .. tostring(row.label), tostring(row.label):sub(1, 1) == "/")
                check("command is described: " .. tostring(row.label), (row.desc or ""):find("%S") ~= nil)
            end
        end
    end
end
check("every slash command this addon owns is listed", commands == 9, commands)

out(fails == 0 and "\nall checks passed\n" or ("\n" .. fails .. " failed\n"))
os.exit(fails == 0 and 0 or 1)
