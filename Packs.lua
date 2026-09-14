-------------------------------------------------------------------------------
--  Packs.lua
--
--  Retheme windows toward the ElvUI look, on top of EllesmereUI's own packs.
--
--  Nothing here re-skins from scratch. EUI's GroupFinder pack already fades the
--  ring, keeps the icon and wires selection state; this only swaps the surface
--  treatment -- soft "Ui-Dialog-New-Background" card art at half alpha becomes
--  a flat themed plate with a 1px border and a squared, bordered icon.
--
--  HOW THIS USED TO LOAD, AND WHY IT NO LONGER DOES
--
--  Until 1.1.0 this file was loaded from EllesmereUI's own .toc, which put it
--  inside that addon's namespace and handed it `ns.WSkin` -- the whole window
--  engine. The price was a permanent edit to a vendor file. It now loads as an
--  ordinary addon and reaches the engine only through the published skin API,
--  with Chrome.lua supplying the handful of primitives that API does not
--  expose. WSkin below is that pair: the facade for everything it publishes,
--  our own code for the rest.
--
--  Load order is if anything better than it was. This used to register after
--  WindowPacks.lua so the engine applied it last; a separate addon loads after
--  the whole suite, so it still gets the last word.
--
--  WHERE /euilocal IS READ. Not here. This file used to return at file scope
--  on the switch, which worked because it read EllesmereUIDB -- another
--  addon's saved variables, fully loaded by the time our files ran. Our own
--  are not: they replace whatever exists at file scope when they load, so a
--  file-scope read always sees the default and a saved `off` would be lost.
--  The switch is read in Chrome.lua's Apply instead, which runs at login. Every
--  frame this file touches is touched from an apply, so nothing is skinned
--  when it is off; what remains is a few function definitions and /euidiag,
--  which has to keep working to be of any use.
-------------------------------------------------------------------------------
local _, ns = ...

local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local issecretvalue = issecretvalue or function()
    return false
end

local GetFFD = ns.FFD

-- Public names resolve through the facade at call time; the five the facade
-- does not publish are Chrome.lua's. See the note at the top of that file for
-- why they are ours and not EllesmereUI's.
local WSkin = setmetatable({
    Theme = ns.Theme,
    ResolveTheme = ns.ResolveTheme,
    RegisterWindow = ns.Register,
    CommonChrome = ns.CommonChrome,
    ControlsIn = ns.ControlsIn,
    ButtonsIn = ns.ButtonsIn,
    AddBorder = ns.AddBorder,
    IsForeignFrame = ns.IsForeignFrame,
    -- The engine's Shell took a per-window key; the facade curries one key for
    -- the whole addon instead, so our windows now share a style entry rather
    -- than carrying one each. Nothing read them apart, but a future per-window
    -- toggle would have to come from EllesmereUI rather than from here.
    Shell = function(frame, opts)
        return ns.S and ns.S.Shell(frame, opts)
    end,
}, {
    __index = function(_, k)
        return ns.S and ns.S[k]
    end,
})

-------------------------------------------------------------------------------
--  Font walker
--
--  EUI has no global font swap: the _G.STANDARD_TEXT_FONT override was removed
--  on purpose (see EllesmereUI_Startup.lua) because forcing the Latin-only
--  Expressway face broke CJK and Cyrillic glyphs everywhere. Fonts are applied
--  per string instead, through the locale-aware WSkin.Font -- and the
--  GroupFinder pack makes almost none of those calls, so that window keeps
--  Blizzard's face while the rest of the suite follows the user's choice.
--
--  This walks a window and re-fonts what it finds. Per-string, so the locale
--  fallback that made the global override dangerous still applies.
-------------------------------------------------------------------------------
-- Re-font one string, but never at the cost of the layout -- and never at the
-- cost of matching the string next to it.
--
-- WSkin.Font keeps the point size and swaps the face, and EUI's face is wider
-- per character than Blizzard's. Text that only just fitted then either clips
-- ("Back" -> "Bac") or WRAPS onto a line the widget has no room for
-- ("Start a Group" -> "Start a"), and the wrap is the sneaky one: a wrapped
-- string measures as fitting, so a width check alone reports success.
--
-- CONSISTENCY BEATS FIT, AND THAT IS THE WHOLE ORDERING.
--
-- Fitting a string means changing it -- a point smaller, or Blizzard's face
-- back. Do that per string and a pane comes out ragged, because whether a
-- string needed it depends on how long it happens to be: the spec page put
-- "Marksmanship" in Blizzard's face beside "Survival" in ours. Nobody reads a
-- pane one string at a time, so a fit that breaks the set is not a fit.
--
-- So the fit machinery is scoped to BUTTON LABELS, which is where a fixed
-- width genuinely eats a word, and where the string sits alone in its button
-- with no siblings to disagree with. Ordinary text gets our face at Blizzard's
-- size and is left to wrap, which is what EUI's own WSkin.Font calls do.
--
-- MEASURING HAS TO HAPPEN AFTER LAYOUT. A string walked on OnShow has not been
-- laid out yet -- GetNumLines and GetStringWidth answer for nothing -- so an
-- immediate check sees no problem and the text only breaks once the frame
-- settles. That is why clicking a button "fixed" it: the click forced the
-- relayout that made the truth visible. So the whole measure-swap-verify runs
-- one frame later, batched.
-- How far a button label may shrink before the clip is accepted. Ours is the
-- wider face, so a label that fitted Blizzard's exactly does not fit ours, and
-- the choice is between a smaller label and a truncated one -- "Dungeon
-- Finder" rendering as "Dungeon Find...". A point or two off is barely visible
-- next to a neighbour; a missing word always is. Past about a quarter off it
-- looks broken, and a label needing that much was never going to fit.
local MIN_SHRINK_RATIO = 0.75
local MIN_LABEL_SIZE = 8

-- THE WRAP GETTER IS CanWordWrap. GetWordWrap does not exist.
--
-- Asking a FontString for GetWordWrap returns nil, and nil is not false, so
-- the `== false` test below never fired and every no-wrap label was measured
-- with GetStringWidth. That is the wrong measure by the file's own reasoning:
-- a string that cannot wrap CLIPS, and GetStringWidth answers for what is
-- left, so the label always measured as fitting. The fit machinery ran, found
-- nothing to do, and "Start a Group" kept rendering as "Start a Grou" -- along
-- with "Find a Grou", "Join as Grou" and "Sign U".
--
-- /euidiag printed the same nil for all ninety strings in a window and hid it
-- in plain sight; it reads through this now too.
--
-- nil means the client answered neither getter, so the caller must not assume.
local function WrapsOff(fs)
    local getter = fs.CanWordWrap or fs.GetWordWrap
    if not getter then
        return nil
    end
    local ok, wraps = pcall(getter, fs)
    if not ok or wraps == nil or issecretvalue(wraps) then
        return nil
    end
    return wraps == false
end

-- Forward: PadLabel installs the pin release, which re-queues the string.
local QueueRefont

-- Returns nil when the answer cannot be trusted yet, which is different from
-- "it fits". /euidiag caught exactly this: at flush time GetWidth() was still
-- 0, Overflowing said false, and a label overflowing by 0.8px was left alone.
--
-- noWrap is passed by the button-label path, which has just forbidden the wrap
-- itself and so does not need to ask: the measurement no longer depends on a
-- getter being present at all.
local function Overflowing(fs, baseLines, noWrap)
    local lines = fs:GetNumLines()
    if lines and not issecretvalue(lines) and baseLines and lines > baseLines then
        return true
    end

    local box = fs:GetWidth()
    if issecretvalue(box) then
        return false
    end
    if not box or box <= 0 then
        -- Not laid out yet. Say so rather than guessing.
        return nil
    end

    -- GetStringWidth answers for the text as laid out, and a string that cannot
    -- wrap lays out inside its box by definition: with the wrap forbidden,
    -- "Start a Group" is cut to "Start a Grou" and then measures as fitting.
    -- GetUnboundedStringWidth is what such a string actually needs.
    --
    -- Only for a string that cannot wrap, though. A paragraph that wraps by
    -- design is wider than its box on one line by definition, so measuring it
    -- unbounded calls every wrapping block in the UI an overflow; the line count
    -- above is what catches a paragraph that has genuinely outgrown its room.
    local wrapOff = noWrap
    if wrapOff == nil then
        wrapOff = WrapsOff(fs)
    end

    local width
    if fs.GetUnboundedStringWidth and wrapOff then
        width = fs:GetUnboundedStringWidth()
    else
        width = fs:GetStringWidth()
    end
    if not width or issecretvalue(width) then
        return nil
    end

    return width > box
end

-- Is this string a button's label? That is where fixed widths live, and where
-- a wider face does its damage.
local function IsButtonLabel(fs)
    local parent = fs.GetParent and fs:GetParent()
    if not (parent and parent.IsObjectType) then
        return false
    end
    if not (parent:IsObjectType("Button") or parent:IsObjectType("CheckButton")) then
        return false
    end

    -- It has to BE the button's label, not merely live on one.
    --
    -- A list ROW is a Button, and its columns are ordinary FontStrings hanging
    -- off it. Treating those as labels forbids their wrap, and a FontString
    -- that cannot wrap truncates with an ellipsis -- which is how a Premade
    -- Groups applicant's rating rendered as "29...". Blizzard sets a real
    -- label either through SetFontString or as .Text/.Label; a column is
    -- neither.
    if parent.GetFontString and parent:GetFontString() == fs then
        return true
    end
    return parent.Text == fs or parent.Label == fs
end

-- AN AUTO-SIZING LABEL MUST NEVER BE GIVEN A WIDTH.
--
-- A FontString with no width of its own sizes to its text and cannot truncate.
-- Pin one and it can: the text changes underneath, the pin stays, and with the
-- wrap forbidden the string renders an ellipsis. That is the trade window's
-- recipient gold reading "..." beside the coin -- a money denomination
-- auto-sizes, and Blizzard rewrites it whenever the other side moves money.
--
-- It does not recover on its own either, because Blizzard sets the
-- denomination BUTTON's width from its label's width: once the label is pinned
-- short the button is too, and the next pass has no room to widen into.
--
-- An auto-sizing string measures its box exactly at its text; one with a width
-- of its own does not. Judged at Blizzard's baseline, before our wider face
-- moves either number. nil means "not laid out, ask again" -- the same
-- distinction Overflowing draws, and for the same reason.
local function AutoSized(fs)
    local box, text = fs:GetWidth(), fs:GetStringWidth()
    if issecretvalue(box) or issecretvalue(text) then
        return nil
    end
    if not (box and text) or box <= 0 then
        return nil
    end
    return math.abs(box - text) < 1
end

-- A PIN IS PERMANENT; THE TEXT UNDER IT IS NOT.
--
-- PadLabel fixes the width it measured, and Blizzard rewrites labels in place:
-- a money denomination changes whenever the other side moves money, and the
-- PVP queue button swaps between "Join Battle" and "Join as Group" without the
-- window ever closing. A pin sized for one text clips the other, and no walk
-- runs to correct it.
--
-- So the pin lasts exactly as long as the text it was measured for. Releasing
-- restores auto-sizing (SetWidth(0)) and re-queues, which is what lets an
-- auto-sizing label be padded at all.
local function ReleasePinOnRewrite(fs)
    if fs.euiLocalRewriteHook then
        return
    end
    fs.euiLocalRewriteHook = true

    local function Release()
        if not fs.euiLocalPinned then
            return
        end
        fs.euiLocalPinned = nil
        fs.euiLocalAuto = nil -- the new text may sit differently in its box
        if fs.SetWidth then
            fs:SetWidth(0)
        end
        QueueRefont(fs)
    end

    for _, method in ipairs({ "SetText", "SetFormattedText" }) do
        if fs[method] then
            pcall(hooksecurefunc, fs, method, Release)
        end
    end
end

-- A button label usually has no width of its own -- it is anchored to the
-- button's centre and auto-sizes to its text -- and the auto-size lands a
-- fraction under what the glyphs need: /euidiag measured 74.3px of "Start a
-- Group" in a 73.5px box. With the wrap forbidden that fraction costs a whole
-- character ("Start a Grou"), so widen the box before touching the font size.
--
-- Ignored by a string anchored on both LEFT and RIGHT: there the anchors set
-- the width and the shrink below is the only lever left.
local function PadLabel(fs)
    if not (IsButtonLabel(fs) and fs.SetWidth) then
        return false
    end

    -- Only refuse when the box could not be read at all: a pin computed from a
    -- box we never measured is a guess.
    --
    -- An auto-sizing label is NOT refused any more. It is the case this exists
    -- for -- its box lands a fraction under what the glyphs need, and with the
    -- wrap forbidden that fraction costs the whole last character. The blanket
    -- refusal was added for the trade window's money label, which auto-sizes
    -- and is rewritten whenever the other side moves money, and it threw out
    -- the fix along with the bug. The pin is released on any rewrite instead.
    if fs.euiLocalAuto == nil then
        return false
    end

    -- The wrap is already forbidden on a button label by the time this runs, so
    -- the unbounded width is the honest one.
    local want = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    if not want or issecretvalue(want) or want <= 0 then
        return false
    end

    -- Never wider than the button, or the text spills out of it instead.
    local parent = fs:GetParent()
    local room = parent.GetWidth and parent:GetWidth()
    if issecretvalue(room) then
        room = nil
    end

    local target = math.ceil(want) + 2
    if room and room > 0 and target > room then
        return false
    end

    fs:SetWidth(target)
    fs.euiLocalPinned = true
    ReleasePinOnRewrite(fs)
    return true
end

local function RefontFitted(fs)
    -- Remember Blizzard's own face, so repeat passes always compare against it
    -- rather than against our previous attempt.
    --
    -- Re-take it whenever the string is wearing something this file did not
    -- leave there: list rows come out of a POOL, and Blizzard re-fonts a
    -- recycled row. A baseline captured the first time we ever saw that
    -- FontString then pins it forever to whichever entry happened to sit in
    -- the row first, so one row renders differently to its neighbours.
    --
    -- Face, size AND flags, all three. Blizzard re-sizing a row without
    -- touching its face is the ordinary case, and comparing the face alone
    -- never notices: the row keeps being served the stale size for as long as
    -- it lives.
    local curFace, curSize, curFlags = fs:GetFont()
    if not (curFace and curSize and curSize > 0) or issecretvalue(curSize) then
        return
    end

    if curFace ~= fs.euiLocalApplied then
        -- A face this file did not leave here, so it is Blizzard's: take all
        -- of it as the new baseline.
        fs.euiLocalFace, fs.euiLocalSize, fs.euiLocalFlags = curFace, curSize, curFlags
    elseif curSize ~= fs.euiLocalAppliedSize or curFlags ~= fs.euiLocalAppliedFlags then
        -- Still our face, but a size or flag we did not set: Blizzard re-sized
        -- a pooled row under us. Follow it, but keep the recorded face -- ours
        -- is not a baseline to measure against.
        fs.euiLocalSize, fs.euiLocalFlags = curSize, curFlags
    end

    local face, size, flags = fs.euiLocalFace, fs.euiLocalSize, fs.euiLocalFlags

    -- Back to Blizzard's baseline, so what follows always starts from the same
    -- place no matter how many times this has run.
    fs:SetFont(face, size, flags)

    -- Taken at the baseline, and kept: after the first pass the string is
    -- wearing our face and its box may already be ours, so the comparison
    -- stops meaning anything.
    if fs.euiLocalAuto == nil then
        fs.euiLocalAuto = AutoSized(fs)
    end

    -- Measured with Blizzard's face still on, and only when it will be used.
    local isLabel = IsButtonLabel(fs)
    local baseLines
    if isLabel then
        baseLines = fs:GetNumLines()
        if issecretvalue(baseLines) then
            baseLines = nil
        end
    end

    -- Our face at Blizzard's size: WSkin.Font keeps the point size and swaps
    -- only the face, so on its own it can never make two strings disagree.
    WSkin.Font(fs)

    local settled = true

    -- THE FIT MACHINERY IS FOR BUTTON LABELS ONLY.
    --
    -- It used to run on every string, and that is what made whole panes look
    -- ragged. Each string decided its own fate: one that would not fit was
    -- shrunk a point, or handed back to Blizzard's face outright, while the
    -- string beside it kept ours. On the spec page that put "Marksmanship" in
    -- Blizzard's face next to "Survival" in ours, and set the three blurbs at
    -- different sizes. A per-STRING answer to what is really a per-PANE
    -- question.
    --
    -- A button label is the case where a fixed width genuinely eats a word
    -- ("Start a Group" -> "Start a"), and it sits alone inside its button
    -- rather than in a row of siblings, so fitting one costs no consistency.
    -- Everything else keeps our face at Blizzard's size and is allowed to
    -- wrap -- which is exactly what EUI's own WSkin.Font calls do.
    if isLabel then
        -- Deterministic and needs no measurement: some buttons are still not
        -- laid out a frame after their OnShow ("Accept" split into "Accep" /
        -- "t" on a freshly built invite popup). Worst case is a couple of
        -- clipped pixels rather than a lost word.
        if fs.SetWordWrap then
            fs:SetWordWrap(false)
        end
        if fs.SetMaxLines then
            fs:SetMaxLines(1)
        end

        local over = Overflowing(fs, baseLines, true)
        if over == nil then
            settled = false -- unmeasurable; caller retries
        elseif over and not (PadLabel(fs) and Overflowing(fs, baseLines, true) == false) then
            local floor = math.max(MIN_LABEL_SIZE, math.floor(size * MIN_SHRINK_RATIO))
            for trySize = size - 1, floor, -1 do
                local newFace, _, newFlags = fs:GetFont()
                fs:SetFont(newFace, trySize, newFlags)
                if Overflowing(fs, baseLines, true) == false then
                    break
                end
            end
            -- Deliberately NO fallback to Blizzard's face. Two faces side by
            -- side is a worse fault than a clipped pixel, and it is the one
            -- the old code actually shipped.
        end
    end

    -- Record all three, so the next pass can tell our own work from someone
    -- else's -- and so a size-only change by Blizzard is noticed.
    fs.euiLocalApplied, fs.euiLocalAppliedSize, fs.euiLocalAppliedFlags = fs:GetFont()
    return settled
end

-- One deferred pass per frame rather than a timer per string: a window walk
-- touches hundreds of them.
local queued, flushScheduled = {}, false

-- A widget can still be unmeasurable a frame after its OnShow, so unresolved
-- strings are retried on a short ladder rather than abandoned.
local RETRY_AT = { 0.1, 0.5, 2 }

local function Flush(attempt)
    attempt = attempt or 0
    if attempt == 0 then
        flushScheduled = false
    end

    local batch = queued
    queued = {}

    local unresolved = {}
    for fs in pairs(batch) do
        if not (fs.IsForbidden and fs:IsForbidden()) then
            local ok, settled = pcall(RefontFitted, fs)
            if ok and settled == false then
                unresolved[fs] = true
            end
        end
    end

    local nextDelay = RETRY_AT[attempt + 1]
    if next(unresolved) and nextDelay then
        C_Timer.After(nextDelay, function()
            for fs in pairs(unresolved) do
                queued[fs] = true
            end
            Flush(attempt + 1)
        end)
    end
end

function QueueRefont(fs)
    queued[fs] = true
    if not flushScheduled then
        flushScheduled = true
        C_Timer.After(0, Flush)
    end
end

local function FontsIn(frame, depth)
    if not frame or (depth or 0) < 0 then
        return
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return
    end

    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("FontString") then
            QueueRefont(r)
        end
    end

    if (depth or 0) > 0 and frame.GetChildren then
        for i = 1, select("#", frame:GetChildren()) do
            FontsIn((select(i, frame:GetChildren())), depth - 1)
        end
    end
end

-------------------------------------------------------------------------------
--  Group Finder category rail (Dungeon Finder / Raid Finder / Premade Groups)
-------------------------------------------------------------------------------

-- Blizzard's rail icons are ROUND: a circular atlas held inside a MaskTexture,
-- with a separate gilded ring texture over it. Neither can be cropped square --
-- WSkin.SquareIcon bails outright on a masked texture, which is why an earlier
-- pass left them untouched. ElvUI's answer is to stop fighting the art and
-- substitute plain square icons, which is what this does.
-- Square stand-ins, matching ElvUI's choices.
local RAIL_ICONS = {
    groupfinder = {
        133076, -- inv_helmet_08                  -> Dungeon Finder
        133074, -- inv_helmet_06                  -> Raid Finder
        464820, -- achievement_general_stayclassy -> Premade Groups
    },
    pvp = {
        236396, -- achievement_bg_winwsg                     -> Quick Match
        236368, -- achievement_bg_killxenemies_generalsroom   -> Rated
        464820, -- achievement_general_stayclassy             -> Premade Groups
        236179, -- ability_hunter_focusedaim                  -> Training Grounds
    },
}

local function Unmask(icon)
    if not icon.GetNumMaskTextures then
        return
    end
    for i = icon:GetNumMaskTextures(), 1, -1 do
        local mask = icon:GetMaskTexture(i)
        if mask and icon.RemoveMaskTexture then
            pcall(icon.RemoveMaskTexture, icon, mask)
        end
    end
end

-- Cheap, runs on every show. EUI keeps the ring on this rail deliberately
-- (SkinCategoryButton is called with keepRing = true), and its selection
-- handler can bring art back, so the ring is pushed down again each time.
local function EnforceFlat(btn)
    local ring = btn.ring or btn.Ring
    if ring then
        ring:SetAlpha(0)
    end
    if btn.CircleMask then
        btn.CircleMask:SetAlpha(0)
    end

    local d = GetFFD(btn)
    if d.bg then
        d.bg:SetAlpha(0)
    end
end

-- Deliberately NOT WSkin.Panel: Panel calls FadeRegions, which alphas every
-- texture region on the button -- the category icon included. The plate is
-- built by hand so the icon survives.
local function FlattenTile(btn, index, iconSet)
    if not btn or btn:IsForbidden() then
        return
    end

    EnforceFlat(btn)

    local d = GetFFD(btn)
    if d.localFlatTile then
        return
    end
    d.localFlatTile = true

    local T = WSkin.Theme
    if not T.bgR then
        WSkin.ResolveTheme()
    end

    -- The plate lives on a CHILD FRAME, not as a region of the button.
    --
    -- EUI's SkinCategoryButton ends with Register(btn, keep), which puts the
    -- button into the engine's _restrip list. Restrip re-runs FadeRegions over
    -- it and spares only PROTECT_KEYS ("bg", "hover", "selBar", ...). A plate
    -- created as a region of the button is not on that list and would be
    -- alpha'd away the next time the engine re-strips. FadeRegions walks a
    -- frame's own regions (plus its NineSlice) and never descends into child
    -- frames, so a plate parented one level down is out of its reach.
    local host = CreateFrame("Frame", nil, btn)
    host:SetAllPoints(btn)
    host:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
    d.localPlateHost = host

    local plate = host:CreateTexture(nil, "BACKGROUND", nil, -7)
    plate:SetColorTexture(T.bgR, T.bgG, T.bgB, T.bgA)
    plate:SetAllPoints(host)
    d.localPlate = plate

    -- Repaint on a theme change; the engine only refreshes what it owns.
    if WSkin.OnLooksChanged then
        WSkin.OnLooksChanged(function()
            if not T.bgR then
                WSkin.ResolveTheme()
            end
            plate:SetColorTexture(T.bgR, T.bgG, T.bgB, T.bgA)
        end)
    end

    -- EUI leaves these tiles unbordered ("the card art carries its own soft
    -- edge"), so claiming d.border here suppresses nothing of theirs.
    --
    -- AddBorder no-ops when EUI's pixel-perfect border API is unavailable, and
    -- it does so silently -- /euidiag reported border=false on every tile. Draw
    -- the edges ourselves if it did not take.
    WSkin.AddBorder(btn)
    if not d.border then
        local T2 = WSkin.Theme
        local br, bg, bb = T2.brdR or 0, T2.brdG or 0, T2.brdB or 0
        local function Edge(p1, p2, horizontal)
            local line = host:CreateTexture(nil, "BORDER")
            line:SetColorTexture(br, bg, bb, 1)
            line:SetPoint(p1)
            line:SetPoint(p2)
            if horizontal then
                line:SetHeight(1)
            else
                line:SetWidth(1)
            end
        end
        Edge("TOPLEFT", "TOPRIGHT", true)
        Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
        Edge("TOPLEFT", "BOTTOMLEFT", false)
        Edge("TOPRIGHT", "BOTTOMRIGHT", false)
        d.localEdges = true
    end

    local icon = btn.icon or btn.Icon
    if icon then
        Unmask(icon)

        local replacement = index and iconSet and iconSet[index]
        if replacement then
            icon:SetTexture(replacement)
        end

        icon:SetSize(40, 40)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", btn, "LEFT", 8, 0)

        -- Now that the mask is gone the crop and border will take.
        WSkin.SquareIcon(icon, btn)
    end
end

local function GroupFinderTile(i)
    return (GroupFinderFrame and GroupFinderFrame["groupButton" .. i]) or _G["GroupFinderFrameGroupButton" .. i]
end

local function PVPTile(i)
    return (PVPQueueFrame and PVPQueueFrame["CategoryButton" .. i]) or _G["PVPQueueFrameCategoryButton" .. i]
end

-- Both rails are the same EUI code path (SkinCategoryButton, called with
-- keepRing = true for each), so one routine serves both.
local function FlattenRail(getTile, iconSet)
    for i = 1, 5 do
        local btn = getTile(i)
        if btn then
            FlattenTile(btn, i, iconSet)

            -- EUI skins these lazily on first show. Our hook registers after
            -- theirs (this file loads later), so it runs after and the flat
            -- treatment wins. Both halves are idempotent.
            local d = GetFFD(btn)
            if not d.localFlatHook then
                d.localFlatHook = true
                btn:HookScript("OnShow", EnforceFlat)
                -- EUI re-derives a tile's selection visuals from its own
                -- OnClick hook, which can restore the card art on whichever
                -- tile you just selected. Ours has to run after that.
                btn:HookScript("OnClick", EnforceFlat)
            end
        end
    end
end

local function Skin_LocalGroupFinder()
    FlattenRail(GroupFinderTile, RAIL_ICONS.groupfinder)
end

-------------------------------------------------------------------------------
--  Registration
--
--  No `addons` key means "apply at PLAYER_LOGIN"; with one, the engine waits
--  for that Blizzard addon to load. Each pack is pcall-isolated by the engine,
--  so a window that changes shape upstream costs itself and nothing else.
--
--  Font walks are attached per window rather than done once globally: EUI has
--  no global font swap by design (see the Font walker note above), and windows
--  build their contents lazily, so each has to be walked when it opens.
-------------------------------------------------------------------------------

-- Deep enough to reach a row inside a ScrollBox:
-- window > panel > ScrollBox > ScrollTarget > row > child > FontString.
local FONT_DEPTH = 9

-- Walking from a ScrollBox itself needs far less.
local ROW_DEPTH = 5

-- frame name -> the Blizzard addon that owns it (nil = base UI, exists at login)
local FONT_WINDOWS = {
    { "PVEFrame" },
    { "PVPUIFrame", "Blizzard_PVPUI" },
    { "CommunitiesFrame", "Blizzard_Communities" },
    { "PlayerSpellsFrame", "Blizzard_PlayerSpells" },
    { "EncounterJournal", "Blizzard_EncounterJournal" },
    { "CollectionsJournal", "Blizzard_Collections" },
    { "AchievementFrame", "Blizzard_AchievementUI" },
    { "ProfessionsFrame", "Blizzard_Professions" },
    { "AuctionHouseFrame", "Blizzard_AuctionHouseUI" },
    { "GuildBankFrame", "Blizzard_GuildBankUI" },
    { "PVPMatchScoreboard", "Blizzard_PVPMatch" },
    { "PVPMatchResults", "Blizzard_PVPMatch" },
    { "DeathRecapFrame", "Blizzard_DeathRecap" },
    { "TaxiFrame", "Blizzard_TaxiUI" },
    { "FlightMapFrame", "Blizzard_FlightMap" },
    { "ClickBindingFrame", "Blizzard_ClickBindingUI" },
    { "ChannelFrame", "Blizzard_Channels" },
    { "WeeklyRewardsFrame", "Blizzard_WeeklyRewards" },
    { "ItemUpgradeFrame", "Blizzard_ItemUpgradeUI" },
    { "CharacterFrame" },
    { "InspectFrame", "Blizzard_InspectUI" },
    { "FriendsFrame" },
    { "WorldMapFrame" },
    { "QuestFrame" },
    { "GossipFrame" },
    { "MerchantFrame" },
    { "MailFrame" },
    { "TradeFrame" },
    { "MacroFrame", "Blizzard_MacroUI" },
    { "RaidInfoFrame" },
    { "SettingsPanel", "Blizzard_Settings" },
}

-- List rows come out of a ScrollBox POOL: created, recycled and re-texted long
-- after the window's OnShow, and a recycled row carries whatever font Blizzard
-- last set on it. A one-shot walk therefore misses every row -- which is why the
-- Premade Groups results kept Blizzard's face while the window around them did
-- not. Re-walk each box whenever it updates.
local function AttachScrollBoxes(frame, depth)
    if not frame or (depth or 0) < 0 then
        return
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return
    end

    -- A ScrollBox is recognisable by its ScrollTarget plus an Update method.
    if frame.ScrollTarget and frame.Update then
        local d = GetFFD(frame)
        if not d.localScrollFont then
            d.localScrollFont = true
            hooksecurefunc(frame, "Update", function(box)
                FontsIn(box, ROW_DEPTH)
            end)
        end
    end

    if frame.GetChildren then
        for i = 1, select("#", frame:GetChildren()) do
            AttachScrollBoxes((select(i, frame:GetChildren())), depth - 1)
        end
    end
end

-- Walk on show: a window's panels are built lazily, so a single pass at login
-- would miss most of the strings in it.
local function AttachFontWalk(frameName)
    local frame = _G[frameName]
    if not frame then
        return
    end

    local function Refont()
        FontsIn(frame, FONT_DEPTH)
        -- Panels appear over time, so re-scan for boxes on every show; the
        -- per-box guard keeps this to one hook each.
        AttachScrollBoxes(frame, FONT_DEPTH)
    end

    Refont()

    local d = GetFFD(frame)
    if not d.localFontHook then
        d.localFontHook = true
        if frame.HookScript then
            frame:HookScript("OnShow", Refont)
        end
        -- Follow a font change made in EUI's own options.
        if WSkin.OnLooksChanged then
            WSkin.OnLooksChanged(Refont)
        end
    end
end

do
    -- One pack per owning addon, so each waits for the right load event.
    local byAddon = {}
    for _, entry in ipairs(FONT_WINDOWS) do
        local frameName, addon = entry[1], entry[2]
        local bucket = byAddon[addon or false]
        if not bucket then
            bucket = {}
            byAddon[addon or false] = bucket
        end
        bucket[#bucket + 1] = frameName
    end

    -- Key off the addon name, not a counter: pairs() order varies per session
    -- and a stable key keeps these identifiable in the engine's window list.
    for addon, frameNames in pairs(byAddon) do
        WSkin.RegisterWindow({
            key = "localfonts:" .. (addon or "base"),
            addons = addon and { [addon] = true } or nil,
            apply = function()
                for _, frameName in ipairs(frameNames) do
                    AttachFontWalk(frameName)
                end
            end,
        })
    end
end

-------------------------------------------------------------------------------
--  Stock windows
--
--  Small Blizzard windows EUI has no pack for at all. These need no bespoke
--  work: a shell, EUI's own CommonChrome pass (close button, edit boxes and
--  dropdowns, paging arrows, scroll bars, title centering), its button walker,
--  and a font walk. CommonChrome and the walkers already refuse to descend
--  into other addons' frames via WSkin.IsForeignFrame.
--
--  Load-on-demand addon names are ElvUI's, which is the authoritative list.
-------------------------------------------------------------------------------
local STOCK_WINDOWS = {
    { "BarberShopFrame", "Blizzard_BarbershopUI" },
    { "StableFrame", "Blizzard_StableUI" },
    { "GuildControlUI", "Blizzard_GuildControlUI" },
    { "TimeManagerFrame", "Blizzard_TimeManager" },
    { "BattlefieldMapFrame", "Blizzard_BattlefieldMap" },
    { "TabardFrame" },
    { "PetitionFrame" },
    { "GuildRegistrarFrame" },
    { "HelpFrame" },
}

local function SkinStockWindow(frameName)
    local frame = _G[frameName]
    if not frame then
        return
    end

    local d = GetFFD(frame)
    if d.localStock then
        return
    end
    d.localStock = true

    WSkin.Shell(frame)
    WSkin.CommonChrome(frame, frameName)
    WSkin.ButtonsIn(frame)

    FontsIn(frame, FONT_DEPTH)
    AttachScrollBoxes(frame, FONT_DEPTH)

    if frame.HookScript then
        frame:HookScript("OnShow", function()
            FontsIn(frame, FONT_DEPTH)
            AttachScrollBoxes(frame, FONT_DEPTH)
        end)
    end
end

do
    local byAddon = {}
    for _, entry in ipairs(STOCK_WINDOWS) do
        local frameName, addon = entry[1], entry[2]
        local bucket = byAddon[addon or false]
        if not bucket then
            bucket = {}
            byAddon[addon or false] = bucket
        end
        bucket[#bucket + 1] = frameName
    end

    for addon, frameNames in pairs(byAddon) do
        WSkin.RegisterWindow({
            key = "localstock:" .. (addon or "base"),
            addons = addon and { [addon] = true } or nil,
            apply = function()
                for _, frameName in ipairs(frameNames) do
                    SkinStockWindow(frameName)
                end
            end,
        })
    end
end

WSkin.RegisterWindow({
    key = "localgroupfinder",
    apply = Skin_LocalGroupFinder,
})

WSkin.RegisterWindow({
    key = "localpvp",
    addons = { Blizzard_PVPUI = true },
    apply = function()
        FlattenRail(PVPTile, RAIL_ICONS.pvp)
    end,
})

-------------------------------------------------------------------------------
--  Chat bubbles
--
--  Nothing in EUI touches them, so they stay stock parchment while the rest of
--  the UI is flat and dark.
--
--  Bubbles are ANONYMOUS and pooled, created and destroyed constantly, and
--  there is no event for "a bubble appeared". C_ChatBubbles.GetAllChatBubbles
--  is the only way to find them, so they have to be polled.
--
--  The poll is not permanent. A chat event that can produce a bubble starts a
--  ticker; the ticker stops itself after a few consecutive empty passes. Idle,
--  this costs nothing at all.
-------------------------------------------------------------------------------
local BUBBLE_EVENTS = {
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_MONSTER_SAY",
    "CHAT_MSG_MONSTER_YELL",
    "CHAT_MSG_MONSTER_PARTY",
    "CHAT_MSG_MONSTER_EMOTE",
    "CHAT_MSG_MONSTER_WHISPER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local BUBBLE_POLL = 0.1
local BUBBLE_IDLE_STOP = 30 -- ~3s of no bubbles and the ticker retires

-- A bubble sits over the world rather than over the UI, so it wants to be
-- see-through -- but not as thin as WSkin.Panel's shared content wash, which is
-- meant for shading a panel that already has a solid frame behind it. Tune here.
local BUBBLE_ALPHA = 0.45

-- Which frame actually draws the bubble? Assuming "the first child, always"
-- skinned nothing at all: the depth varies by bubble, and a wrong guess bails
-- silently. Go by what owns the text instead -- that frame is the one carrying
-- the art around it.
local function BubbleBody(frame, depth)
    if not frame or frame:IsForbidden() then
        return nil
    end

    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("FontString") then
            return frame
        end
    end

    if depth <= 0 or not frame.GetChildren then
        return nil
    end
    for i = 1, select("#", frame:GetChildren()) do
        local body = BubbleBody((select(i, frame:GetChildren())), depth - 1)
        if body then
            return body
        end
    end
end

local function SkinBubble(bubble)
    if not bubble or bubble:IsForbidden() then
        return
    end

    local body = BubbleBody(bubble, 3) or bubble

    -- Guard on the body, not the frame the API handed back: bubbles are pooled
    -- and a reused frame can come back around a different body.
    local d = GetFFD(body)
    if d.localBubble then
        return
    end
    d.localBubble = true

    -- The art is a nine-slice of named pieces plus a Tail; fade the lot, keep
    -- the border, and lay our own fill behind the text at BUBBLE_ALPHA. Created
    -- after the Panel call, which fades every texture already on the frame.
    WSkin.Panel(body, { noBg = true })
    if body.Tail then
        body.Tail:SetAlpha(0)
    end
    if body.Center then
        body.Center:SetAlpha(0)
    end

    local bg = body:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetColorTexture(WSkin.Theme.bgR, WSkin.Theme.bgG, WSkin.Theme.bgB, BUBBLE_ALPHA)
    bg:SetAllPoints(body)
    d.bg = bg

    -- The outer frame is a positioner, but it can still carry art of its own.
    -- Strip it without a second panel on top of the body's.
    if body ~= bubble then
        WSkin.Panel(bubble, { noBg = true, noBorder = true })
    end

    FontsIn(body, 2)
end

do
    local ticker, idle

    local function Poll()
        local bubbles = C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles()
        local seen = false

        for _, bubble in pairs(bubbles or {}) do
            seen = true
            SkinBubble(bubble)
        end

        idle = seen and 0 or (idle or 0) + 1
        if idle >= BUBBLE_IDLE_STOP and ticker then
            ticker:Cancel()
            ticker = nil
        end
    end

    local function Wake()
        idle = 0
        if not ticker then
            ticker = C_Timer.NewTicker(BUBBLE_POLL, Poll)
        end
    end

    WSkin.RegisterWindow({
        key = "localchatbubbles",
        apply = function()
            if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then
                return
            end

            local watcher = CreateFrame("Frame")
            for _, event in ipairs(BUBBLE_EVENTS) do
                pcall(watcher.RegisterEvent, watcher, event)
            end
            watcher:SetScript("OnEvent", Wake)

            -- Something may already be on screen when we load in.
            Wake()
        end,
    })
end

-------------------------------------------------------------------------------
--  Popup dialogs
--
--  RolePollPopup and PVPReadyDialog: EUI has no pack for either.
--
--  LFGListApplicationDialog: EUI 9.1.4 added SkinApplicationDialog, but it is
--  gated on a truthiness test of EllesmereUIDB.reskinQueuePopup, so it does
--  nothing until that key is seeded. Kept here as the fallback; drop it if the
--  vendor skin turns out to be reliably on.
--
--  StaticPopups are the vendor's now (_popupSkin, reskinPopupsMenus, default
--  on) -- it skins the buttons and edit box and mirrors their enabled state.
--
--  Blizzard reuses these frames, so the skin is idempotent per frame and safe
--  to re-run on show.
-------------------------------------------------------------------------------
local function SkinRoleCheck(roleButton)
    if not roleButton then
        return
    end

    local check = roleButton.CheckButton or roleButton.checkButton
    if check then
        -- Some of these ship scaled to 0.7, which makes a skinned box blurry.
        if check.GetScale and check:GetScale() ~= 1 then
            check:SetScale(1)
        end
        WSkin.Checkbox(check)
    end

    -- The role art itself is the point of the widget; only its ring goes.
    WSkin.SquareIcon(roleButton.texture or roleButton.Icon or roleButton.icon, roleButton)
end

local function SkinDialog(frame, opts)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then
        return
    end

    local d = GetFFD(frame)
    if d.localDialog then
        return
    end
    d.localDialog = true

    WSkin.Panel(frame)
    WSkin.CommonChrome(frame, frame.GetName and frame:GetName() or nil)
    WSkin.ButtonsIn(frame)

    for _, key in ipairs(opts and opts.buttons or {}) do
        WSkin.Button(frame[key])
    end
    for _, key in ipairs(opts and opts.editBoxes or {}) do
        WSkin.EditBox(frame[key])
    end
    for _, key in ipairs(opts and opts.roles or {}) do
        SkinRoleCheck(frame[key])
    end

    FontsIn(frame, ROW_DEPTH)
end

local function Skin_LocalDialogs()
    -- "Choose your Roles" when you sign up for a premade group.
    SkinDialog(_G.LFGListApplicationDialog, {
        buttons = { "SignUpButton", "CancelButton" },
        editBoxes = { "Description" },
        roles = { "TankButton", "HealerButton", "DamagerButton" },
    })

    -- The leader's "what role are you?" poll.
    local poll = _G.RolePollPopup
    SkinDialog(poll, { buttons = { "AcceptButton" } })
    if poll then
        for _, key in ipairs({ "RoleButtonTank", "RoleButtonHealer", "RoleButtonDPS" }) do
            SkinRoleCheck(poll[key] or _G["RolePollPopup" .. key])
        end
    end

    SkinDialog(_G.PVPReadyDialog, { buttons = { "enterButton", "leaveButton" } })
end

WSkin.RegisterWindow({
    key = "localdialogs",
    apply = function()
        Skin_LocalDialogs()

        -- LFGListApplicationDialog is built on first use rather than at
        -- login, so re-run as addons come in. SkinDialog guards per frame.
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("ADDON_LOADED")
        watcher:SetScript("OnEvent", Skin_LocalDialogs)
    end,
})

-------------------------------------------------------------------------------
--  /euidiag -- report what this file actually found and did
--
--  Added because three rounds of inferring from screenshots produced three
--  wrong fixes. It prints the state the code is reacting to, in game, where
--  the layout is real.
-------------------------------------------------------------------------------
local function Say(...)
    print("|cff0cd29fEUI local|r:", ...)
end

local function Chain(frame)
    local names, hops = {}, 0
    while frame and hops < 10 do
        names[#names + 1] = frame.GetName and frame:GetName() or "<anon>"
        frame = frame.GetParent and frame:GetParent()
        hops = hops + 1
    end
    return table.concat(names, " < ")
end

local function DescribeString(label, fs)
    if not fs then
        Say("  " .. label .. ": |cffff5555missing|r")
        return
    end

    local face, size = fs:GetFont()
    Say(("  %s: %q"):format(label, tostring(fs:GetText())))
    Say(
        ("     font=%s size=%s lines=%s"):format(
            tostring(face and face:match("[^\\/]+$") or face),
            tostring(size),
            tostring(fs:GetNumLines())
        )
    )
    Say(
        ("     box=%.1f  text=%.1f  want=%.1f  wrap=%s  orig=%s"):format(
            fs:GetWidth() or -1,
            fs:GetStringWidth() or -1,
            (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or -1,
            tostring(WrapsOff(fs)),
            tostring(fs.euiLocalFace and fs.euiLocalFace:match("[^\\/]+$") or "not touched")
        )
    )
    Say("     parents: " .. Chain(fs:GetParent()))
end

local function DescribeTile(index, btn)
    if not btn then
        Say(("tile %d: |cffff5555not found|r"):format(index))
        return
    end

    local d = GetFFD(btn)
    local icon = btn.icon or btn.Icon or btn.IconTexture
    local ring = btn.ring or btn.Ring

    Say(
        ("tile %d: flattened=%s plate=%s border=%s"):format(
            index,
            tostring(d.localFlatTile == true),
            tostring(d.localPlateHost ~= nil),
            tostring(d.border == true)
        )
    )
    Say(
        ("   icon: %s  masks=%s  texture=%s"):format(
            icon and "yes" or "|cffff5555none|r",
            icon and icon.GetNumMaskTextures and tostring(icon:GetNumMaskTextures()) or "?",
            icon and tostring(icon:GetTexture()) or "-"
        )
    )
    Say(("   ring: %s alpha=%s"):format(ring and "yes" or "none", ring and tostring(ring:GetAlpha()) or "-"))
end

-- Walk a frame and report every FontString in it. This is the question that
-- matters for a clipped label: did our walker reach it at all, and if so what
-- does the layout actually measure?
local DUMP_ROW = "  %q  font=%s size=%s base=%s obj=%s lines=%s box=%.0f text=%.0f want=%.0f wrap=%s touched=%s"

local function DumpStrings(frame, depth, seen)
    if not frame or depth < 0 then
        return
    end
    seen = seen or {}
    if seen[frame] then
        return
    end
    seen[frame] = true

    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("FontString") then
            local text = r:GetText()
            if text and text ~= "" then
                local face, size = r:GetFont()
                -- base= is the baseline we measured against and obj= the size
                -- the string's FontObject asks for. A row that renders at a
                -- different size to its neighbours is one of the two
                -- disagreeing with size=, and which one says whose bug it is.
                local obj = r.GetFontObject and r:GetFontObject()
                local objSize
                if obj and obj.GetFont then
                    local _, s2 = obj:GetFont()
                    objSize = s2
                end
                Say(
                    DUMP_ROW:format(
                        tostring(text),
                        tostring(face and face:match("[^\\/]+$") or face),
                        tostring(size),
                        tostring(r.euiLocalSize),
                        tostring(objSize),
                        tostring(r:GetNumLines()),
                        r:GetWidth() or -1,
                        r:GetStringWidth() or -1,
                        (r.GetUnboundedStringWidth and r:GetUnboundedStringWidth()) or -1,
                        tostring(WrapsOff(r)),
                        r.euiLocalFace and "yes" or "|cffff5555NO|r"
                    )
                )
            end
        end
    end

    if frame.GetChildren then
        for i = 1, select("#", frame:GetChildren()) do
            DumpStrings((select(i, frame:GetChildren())), depth - 1, seen)
        end
    end
end

-- Bubbles are anonymous, so there is no name to point /euidiag at. Dump the
-- live ones instead: the shape, which frame we picked as the body, and whether
-- it got skinned.
local function DumpBubble(index, bubble, frame, depth)
    frame = frame or bubble
    depth = depth or 0

    local textures, strings = 0, 0
    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r.IsObjectType then
            if r:IsObjectType("Texture") then
                textures = textures + 1
            end
            if r:IsObjectType("FontString") then
                strings = strings + 1
            end
        end
    end

    local body = BubbleBody(bubble, 3)
    Say(
        ("%sbubble %d%s: %s  textures=%d strings=%d children=%d%s"):format(
            ("  "):rep(depth),
            index,
            depth > 0 and (" +" .. depth) or "",
            frame:GetName() or "<anon>",
            textures,
            strings,
            frame.GetChildren and select("#", frame:GetChildren()) or 0,
            frame == body and "  |cff00ff00<- body|r" or ""
        )
    )

    if depth == 0 then
        Say(("   skinned: %s"):format(tostring(body ~= nil and GetFFD(body).localBubble == true)))
    end

    if depth < 3 and frame.GetChildren then
        for i = 1, select("#", frame:GetChildren()) do
            DumpBubble(index, bubble, (select(i, frame:GetChildren())), depth + 1)
        end
    end
end

_G.SLASH_EUIDIAG1 = "/euidiag"
_G.SlashCmdList.EUIDIAG = function(input)
    local name = input and input:match("^%s*(%S+)%s*$")

    if name == "bubbles" then
        local bubbles = C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles()
        Say("---- chat bubbles ----")
        local count = 0
        for _, bubble in pairs(bubbles or {}) do
            count = count + 1
            DumpBubble(count, bubble)
        end
        if count == 0 then
            Say("  none on screen - say something, then run this within a few seconds")
        end
        return
    end

    if name then
        local frame = _G[name]
        if not frame then
            Say("no frame called " .. name .. " (open the window first)")
            return
        end
        Say("---- " .. name .. " ----")
        Say("  parents: " .. Chain(frame))
        Say("  shown: " .. tostring(frame.IsShown and frame:IsShown()))
        DumpStrings(frame, 6)
        Say(("  theme font: %s"):format(tostring(WSkin.Theme.fontPath and WSkin.Theme.fontPath:match("[^\\/]+$"))))
        return
    end

    Say("---- Group Finder rail ----")
    for i = 1, 4 do
        DescribeTile(i, GroupFinderTile(i))
    end

    Say("---- Premade Groups buttons ----")
    local panel = LFGListFrame and LFGListFrame.CategorySelection
    if not panel then
        Say("  CategorySelection not built yet - open Premade Groups first")
    else
        for _, key in ipairs({ "StartGroupButton", "FindGroupButton" }) do
            local b = panel[key]
            if b then
                DescribeString(key, b.Text or (b.GetFontString and b:GetFontString()))
            else
                Say("  " .. key .. ": |cffff5555missing|r")
            end
        end
    end

    Say(("---- theme: font=%s ----"):format(tostring(WSkin.Theme.fontPath and WSkin.Theme.fontPath:match("[^\\/]+$"))))
    Say("Point it at a window: |cff00ff00/euidiag LFGListInviteDialog|r")
    Say("Or at the live chat bubbles: |cff00ff00/euidiag bubbles|r")
end
