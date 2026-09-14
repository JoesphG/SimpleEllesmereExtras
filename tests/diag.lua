local FILE = "Diag.lua"

-- A frame stub with real geometry: the walker's whole job is arithmetic on
-- edges and string widths, so stubbing those away would prove nothing.
local Widget = {}
Widget.__index = Widget

local function W(kind, opts)
    local w = setmetatable(opts or {}, Widget)
    w.kind = kind
    w.regions = w.regions or {}
    w.children = w.children or {}
    return w
end

function Widget:IsObjectType(t)
    return self.kind == t
end
function Widget:IsForbidden()
    return self.forbidden == true
end
function Widget:IsShown()
    return self.shown ~= false
end
function Widget:GetName()
    return self.name
end
function Widget:GetParent()
    return self.parent
end
function Widget:GetRegions()
    return unpack(self.regions)
end
function Widget:GetChildren()
    return unpack(self.children)
end
function Widget:GetFont()
    return self.font or "Fonts\\FRIZQT__.TTF", self.size or 12, ""
end
function Widget:GetText()
    return self.text
end
function Widget:GetWidth()
    return self.width or 0
end
function Widget:GetUnboundedStringWidth()
    return self.stringWidth or 0
end
function Widget:GetWordWrap()
    return self.wrap == true
end
function Widget:GetLeft()
    return self.left
end
function Widget:GetRight()
    return self.right
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

local ns = {
    issecret = function(v)
        return v == "SECRET"
    end,
}
assert(loadfile(FILE))("SimpleEllesmereExtras", ns)

-- print belongs to the addon here, so the suite reports through io.write.
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

local function lastRun()
    local lines = {}
    for _, line in ipairs(printed) do
        lines[#lines + 1] = line
    end
    printed = {}
    return table.concat(lines, "\n")
end

out("Diag test\n")

-- Truncation: wider than its box with word wrap off. This is the Baganator
-- category label case, where the box comes from the icon grid, not the text.
local clipped = W("FontString", { text = "Consumables", width = 84, stringWidth = 97, wrap = false })
check("wider than its box with wrap off is truncated", ns.Diag.Truncation(clipped) == true)

clipped.wrap = true
check("the same string wraps instead when wrap is on", ns.Diag.Truncation(clipped) == false)

clipped.wrap = false
clipped.stringWidth = 80
check("a string that fits is not truncated", ns.Diag.Truncation(clipped) == false)

-- The client's own answer wins when it has one, because it knows about
-- ellipsis the width comparison cannot see.
local told = W("FontString", {
    width = 200,
    stringWidth = 10,
    IsTruncated = function()
        return true
    end,
})
check("IsTruncated is believed over the measurement", ns.Diag.Truncation(told) == true)

-- Overflow: extent past the parent's edge. The corner widget case, where the
-- string is corner-anchored and has no width for anything to clip against.
local slot = W("Button", { left = 100, right = 137 })
local count = W("FontString", { text = "12", parent = slot, left = 120, right = 144 })
local over, side = ns.Diag.Overflow(count)
check("a string past the right edge overflows", over ~= nil and side == "right", tostring(over))
check("by the right amount", over == 7, tostring(over))

count.left, count.right = 104, 130
check("a string inside the parent does not", ns.Diag.Overflow(count) == nil)

count.left, count.right = 92, 130
local _, leftSide = ns.Diag.Overflow(count)
check("the left edge counts too", leftSide == "left", tostring(leftSide))

-- Unpositioned frames answer nil for their edges, and nil is not a fault.
count.left, count.right = nil, nil
check("an unpositioned string is not reported", ns.Diag.Overflow(count) == nil)

-- Secret values must not be read as numbers.
local secret = W("FontString", { text = "SECRET", width = 10, stringWidth = 40, font = "SECRET", size = "SECRET" })
check("a secret font does not error", (pcall(ns.Diag.Truncation, secret)) == true)

-- The walk: it has to reach a nested child and count only visible strings.
local root = W("Frame", { name = "TestBag" })
local inner = W("Frame", { parent = root })
local bad = W("FontString", { text = "Consumables", width = 84, stringWidth = 97, parent = inner })
local good = W("FontString", { text = "Fine", width = 84, stringWidth = 40, parent = inner })
local hidden = W("FontString", { text = "Hidden", width = 10, stringWidth = 99, parent = inner, shown = false })
inner.regions = { bad, good, hidden }
root.children = { inner }
_G.TestBag = root

printed = {}
ns.Diag.Report("TestBag")
local report = lastRun()
check("the walk descends into children", report:find("TRUNCATED") ~= nil, report)
check("it names the offending text", report:find("Consumables", 1, true) ~= nil, report)
check("it counts only the visible strings", report:find("2 font strings", 1, true) ~= nil, report)
check("it reports one problem", report:find("1 with a problem", 1, true) ~= nil, report)

-- A forbidden frame is never touched.
local locked = W("Frame", { name = "LockedBag", forbidden = true })
locked.regions = { W("FontString", { text = "x", width = 1, stringWidth = 99 }) }
_G.LockedBag = locked
printed = {}
ns.Diag.Report("LockedBag")
check("a forbidden frame is skipped", lastRun():find("0 font strings", 1, true) ~= nil)

-- An unknown name must say so rather than error.
printed = {}
ns.Diag.Report("NoSuchFrame")
check("an unknown frame name is refused cleanly", lastRun():find("No bag frame", 1, true) ~= nil)

-- The slash command is wired to the same entry point.
check("slash command registered", SLASH_SEEDIAG1 == "/seediag" and SlashCmdList.SEEDIAG ~= nil)

out(fails == 0 and "\nall checks passed\n" or ("\n" .. fails .. " failed\n"))
os.exit(fails == 0 and 0 or 1)
