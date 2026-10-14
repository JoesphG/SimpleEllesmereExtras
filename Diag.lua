-------------------------------------------------------------------------------
--  Diag.lua
--
--  `/seediag [FrameName]` -- find text that is truncated or spilling out of
--  the thing that holds it, without reading a screenshot.
--  `/seediag frames` -- count top-level frames by where they were created.
--
--  WHY THIS EXISTS
--
--  Every collision this addon has caused came from the same move: restyling a
--  region whose geometry was already computed from the old style, with nothing
--  re-measuring afterwards. A wider face at the same point size either gets
--  clipped, if the container has a width, or spills into the neighbour, if it
--  does not. Which of the two you get depends on the user's font file, so the
--  bug reproduces for some people and not others and screenshots disagree.
--
--  The vendor-side pack has `/euidiag` for the windows it walks. This is the
--  same idea for the frames this addon touches, and it is named differently
--  on purpose: two addons claiming one slash command means the later loader
--  wins silently.
--
--  WHAT IT REPORTS
--
--    TRUNCATED  the string does not fit its box and word wrap is off, so the
--               tail is gone. What a re-font does to a Baganator category
--               label, which is clamped to the icon grid beneath it.
--    OVERFLOW   the string's extent passes its parent's edge. What a re-font
--               does to a corner widget, which is corner-anchored with no
--               width for anything to clip against.
--
--  Both are measured off the live frames, so it reads whatever is actually on
--  screen: our skin, the vendor's, Baganator's own, or all three.
-------------------------------------------------------------------------------
local _, ns = ...

local MAX_DEPTH = 12
local TOLERANCE = 0.5
local MAX_REPORTED = 40

local issecret = ns.issecret

local function Num(v)
    if v == nil or issecret(v) then
        return nil
    end
    return type(v) == "number" and v or nil
end

-- Frames are named inconsistently and pooled ones are anonymous, so a path is
-- more use than a name: the nearest named ancestor plus the way down to here.
local function Path(region, depth)
    local name = region.GetName and region:GetName()
    if name then
        return name
    end
    local parent = region.GetParent and region:GetParent()
    if parent and depth > 0 then
        return Path(parent, depth - 1) .. "/?"
    end
    return "?"
end

local function FontOf(fs)
    local path, size = fs:GetFont()
    if issecret(path) or issecret(size) then
        return "secret", 0
    end
    path = tostring(path or "?")
    return path:match("([^\\/]+)$") or path, Num(size) or 0
end

local function Sample(fs)
    local text = fs.GetText and fs:GetText()
    if text == nil or issecret(text) then
        return ""
    end
    text = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "||")
    if #text > 32 then
        text = text:sub(1, 32) .. ".."
    end
    return text
end

-- Truncated: the text is wider than the box it is clipped to, and nothing will
-- wrap it onto a second line. IsTruncated is the client's own answer; the width
-- comparison is the fallback for a string it has not laid out yet.
local function Truncation(fs)
    if fs.IsTruncated then
        local ok, truncated = pcall(fs.IsTruncated, fs)
        if ok and truncated == true then
            return true
        end
    end
    if fs.GetWordWrap and fs:GetWordWrap() then
        return false
    end
    local box = Num(fs.GetWidth and fs:GetWidth())
    local text = Num(fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth())
    if not box or not text or box <= 0 then
        return false
    end
    return text > box + TOLERANCE
end

-- Overflow: the string's own extent passes the edge of the frame that holds
-- it. A corner-anchored string with no width set has nothing to clip it, so
-- this is the only way to see it going over.
local function Overflow(fs)
    local parent = fs.GetParent and fs:GetParent()
    if not (parent and parent.GetLeft) then
        return nil
    end
    local l, r = Num(fs:GetLeft()), Num(fs:GetRight())
    local pl, pr = Num(parent:GetLeft()), Num(parent:GetRight())
    if not (l and r and pl and pr) then
        return nil
    end
    if r > pr + TOLERANCE then
        return r - pr, "right"
    end
    if l < pl - TOLERANCE then
        return pl - l, "left"
    end
    return nil
end

local function Walk(frame, depth, seen, found, counted)
    if depth > MAX_DEPTH or not frame or seen[frame] then
        return
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return
    end
    seen[frame] = true

    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if
                region.IsObjectType
                and region:IsObjectType("FontString")
                and not (region.IsForbidden and region:IsForbidden())
                and region:IsShown()
            then
                counted.n = counted.n + 1
                local font, size = FontOf(region)
                local wrap = (region.GetWordWrap and region:GetWordWrap()) and "on" or "off"
                if Truncation(region) then
                    found[#found + 1] = ("  TRUNCATED  %s %q  box %.1f  text %.1f  %s %d wrap:%s"):format(
                        Path(region, 3),
                        Sample(region),
                        Num(region:GetWidth()) or 0,
                        Num(region.GetUnboundedStringWidth and region:GetUnboundedStringWidth()) or 0,
                        font,
                        size,
                        wrap
                    )
                else
                    local over, side = Overflow(region)
                    if over then
                        found[#found + 1] = ("  OVERFLOW   %s %q  %.1f past parent %s  %s %d"):format(
                            Path(region, 3),
                            Sample(region),
                            over,
                            side,
                            font,
                            size
                        )
                    end
                end
            end
        end
    end

    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            Walk(child, depth + 1, seen, found, counted)
        end
    end
end

-- No argument means the bag, which is what this was written for.
local function Target(name)
    if name ~= "" then
        return _G[name], name
    end
    for _, candidate in ipairs({
        "Baganator_SingleViewBackpackViewFrame",
        "Baganator_CategoryViewBackpackViewFrame",
        "BaganatorSingleViewBackpackViewFrame",
    }) do
        if _G[candidate] then
            return _G[candidate], candidate
        end
    end
end

-- `/seediag frames`: UIParent's direct children grouped by where they were
-- created. Thousands means something keeps creating frames; the top line says
-- which file and line. Walks EnumerateFrames because GetChildren on that many
-- overflows the stack.
local FRAMES_REPORTED = 10

local function Origin(frame)
    local loc = frame.GetSourceLocation and frame:GetSourceLocation()
    if type(loc) ~= "string" or issecret(loc) then
        return "?"
    end
    return loc:match("[Aa]dd[Oo]ns[/\\](.+)$") or loc
end

local function CountFrames()
    local byOrigin, total = {}, 0
    local frame = EnumerateFrames()
    while frame do
        local ok, top = pcall(function()
            return not frame:IsForbidden() and frame:GetParent() == UIParent
        end)
        if ok and top then
            total = total + 1
            local origin = Origin(frame)
            byOrigin[origin] = (byOrigin[origin] or 0) + 1
        end
        frame = EnumerateFrames(frame)
    end

    local sorted = {}
    for origin, n in pairs(byOrigin) do
        sorted[#sorted + 1] = { origin = origin, n = n }
    end
    table.sort(sorted, function(x, y)
        return x.n > y.n
    end)

    print(("SimpleEllesmereExtras diag: %d frames parented to UIParent."):format(total))
    for i = 1, math.min(#sorted, FRAMES_REPORTED) do
        print(("  %5d  %s"):format(sorted[i].n, sorted[i].origin))
    end
    return total, sorted
end

local function Report(input)
    local name = (input or ""):match("^%s*(.-)%s*$")
    if name == "frames" then
        CountFrames()
        return
    end
    local frame, label = Target(name)
    if not frame then
        print("SimpleEllesmereExtras diag: /seediag <FrameName>. No bag frame open to default to.")
        return
    end

    local found, counted = {}, { n = 0 }
    Walk(frame, 0, {}, found, counted)

    print(("SimpleEllesmereExtras diag: %s -- %d font strings, %d with a problem."):format(label, counted.n, #found))
    for i = 1, math.min(#found, MAX_REPORTED) do
        print(found[i])
    end
    if #found > MAX_REPORTED then
        print(("  ...and %d more."):format(#found - MAX_REPORTED))
    end
end

ns.Diag = { Report = Report, Truncation = Truncation, Overflow = Overflow, Walk = Walk, CountFrames = CountFrames }

_G.SLASH_SEEDIAG1 = "/seediag"
_G.SlashCmdList.SEEDIAG = Report
