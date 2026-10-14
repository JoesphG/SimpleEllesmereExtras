-- Executes Packs.lua against a stubbed EllesmereUI skin facade.
--
-- The facade half of the stub is the PUBLIC surface only -- what
-- EllesmereUI.RegisterSkin actually hands out. The five primitives the facade
-- does not publish are injected as Chrome.lua supplies them, and have their
-- own suite in tests/chrome.lua; here they are recorders, so a pack asking for
-- the wrong one shows up as a missing call rather than as somebody else's bug.
local FILE = "Packs.lua"

local Widget = {}
Widget.__index = Widget
local function nop() end
local function W(kind, name, parent)
    local w = setmetatable({
        kind = kind,
        name = name,
        parent = parent,
        regions = {},
        children = {},
        scripts = {},
        alpha = 1,
        level = 2,
        masks = {},
    }, Widget)
    if name then
        _G[name] = w
    end
    if parent then
        parent.children[#parent.children + 1] = w
    end
    return w
end
function Widget:CreateTexture(_, layer, _, sub)
    local t = W("Texture")
    t.layer, t.sub = layer, sub
    self.regions[#self.regions + 1] = t
    return t
end
function Widget:CreateFontString(_, layer)
    local f = W("FontString")
    f.layer = layer
    f.size = 12
    self.regions[#self.regions + 1] = f
    return f
end
function Widget:GetRegions()
    return unpack(self.regions)
end
function Widget:GetChildren()
    return unpack(self.children)
end
function Widget:IsObjectType(t)
    return self.kind == t
end
function Widget:IsForbidden()
    return false
end
function Widget:GetFrameLevel()
    return self.level
end
function Widget:SetFrameLevel(l)
    self.level = l
end
function Widget:SetScript(s, f)
    self.scripts[s] = f
end
function Widget:RegisterEvent(e)
    self.events = self.events or {}
    self.events[e] = true
end
function Widget:HookScript(s, f)
    self.scripts[s] = self.scripts[s] or {}
    table.insert(self.scripts[s], f)
end
function Widget:SetAlpha(a)
    self.alpha = a
end
function Widget:GetFont()
    return self.font or "blizz", self.size or 12, self.flags or ""
end
function Widget:SetFont(p, s, f)
    self.font, self.size, self.flags = p, s, f
end
function Widget:SetWordWrap(v)
    self.wraps = v and true or false
end
-- The client's getter is CanWordWrap. There is deliberately NO GetWordWrap
-- here: asking for one returns nil, and reading nil as "wraps" is the bug.
function Widget:CanWordWrap()
    return self.wraps ~= false
end
function Widget:SetText(t)
    t = tostring(t or "")
    self.text, self.textLen = t, #t
end
function Widget:GetText()
    return self.text
end
function Widget:SetMaxLines(n)
    self.maxLines = n
end
-- Width of the box; 0/nil means the string auto-sizes and cannot overflow.
function Widget:GetWidth()
    return self.boxWidth or self.w or 0
end
-- SetWidth(0) is how the client is told to go back to auto-sizing.
function Widget:SetWidth(w)
    self.boxWidth = (w and w > 0) and w or nil
end
-- EUIFont is modelled as 1.4x wider per point than Blizzard's face.
function Widget:GetStringWidth()
    local perChar = (self.font == "EUIFont") and 1.4 or 1.0
    local w = (self.textLen or 0) * (self.size or 12) * perChar
    -- A wrapping string never reports wider than its box.
    if self.wraps and self.boxWidth and self.boxWidth > 0 and w > self.boxWidth then
        return self.boxWidth
    end
    -- A no-wrap string is NOT clipped here. /euidiag measured "Practice" at
    -- 62px in a 61px box and "Arena" at 35 in 34, so the live client reports
    -- the full width and lets it overhang. The box is what lags.
    return w
end
-- What the string needs with no box at all -- unaffected by wrapping, which is
-- exactly why it is the wrong measure for a string that wraps on purpose.
function Widget:GetUnboundedStringWidth()
    local perChar = (self.font == "EUIFont") and 1.4 or 1.0
    return (self.textLen or 0) * (self.size or 12) * perChar
end
-- Wrapping strings spill onto extra lines instead of reporting extra width,
-- which is exactly how "Start a Group" hid its second word.
function Widget:GetNumLines()
    if not self.wraps or not self.boxWidth or self.boxWidth <= 0 then
        return 1
    end
    local perChar = (self.font == "EUIFont") and 1.4 or 1.0
    local w = (self.textLen or 0) * (self.size or 12) * perChar
    return math.max(1, math.ceil(w / self.boxWidth))
end
function Widget:GetNumMaskTextures()
    return #self.masks
end
function Widget:GetMaskTexture(i)
    return self.masks[i]
end
function Widget:RemoveMaskTexture(m)
    for i, v in ipairs(self.masks) do
        if v == m then
            table.remove(self.masks, i)
            break
        end
    end
end
function Widget:SetTexCoord()
    self.cropped = true
end
function Widget:SetTexture(t)
    self.texture = t
end
function Widget:GetParent()
    return self.parent
end
for _, m in ipairs({
    "SetAllPoints",
    "SetColorTexture",
    "SetPoint",
    "ClearAllPoints",
    "SetSize",
    "SetTextColor",
    "SetShadowOffset",
    "SetShadowColor",
    "Show",
    "Hide",
}) do
    Widget[m] = nop
end

local created = {}
function CreateFrame(kind, name, parent)
    local f = W(kind, name, parent)
    created[#created + 1] = f
    return f
end

-- EUI + WSkin stubs
local ffd = setmetatable({}, { __mode = "k" })
EllesmereUI = {
    _GetFFD = function(f)
        ffd[f] = ffd[f] or {}
        return ffd[f]
    end,
    PrimeFontShadow = nop,
}
local squared, bordered, looksCallbacks = {}, {}, {}
local shelled, chromed, walked, panelled = {}, {}, {}, {}
local panelOpts = {}
local calls = {}
local WSkin
WSkin = {
    Theme = { bgR = 0.06, bgG = 0.06, bgB = 0.06, bgA = 1, fontPath = "EUIFont", fontFlag = "" },
    ResolveTheme = nop,
    AddBorder = function(f)
        bordered[f] = true
        EllesmereUI._GetFFD(f).border = true
    end,
    -- The facade curries Shell per addon, so no window key reaches it. Packs
    -- passes its own key through as the first argument and the shim drops it.
    Shell = function(f)
        shelled[f] = true
    end,
    CommonChrome = function(f)
        chromed[f] = true
    end,
    ButtonsIn = function(f)
        walked[f] = true
    end,
    SquareIcon = function(icon, parent)
        if icon:GetNumMaskTextures() > 0 then
            return
        end -- mirrors the real bail-out
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        squared[icon] = true
        return true
    end,
    Font = function(fs)
        local _, size = fs:GetFont()
        fs:SetFont(WSkin.Theme.fontPath, size or 12, "")
    end,
    OnLooksChanged = function(fn)
        looksCallbacks[#looksCallbacks + 1] = fn
    end,
    AccentBarColor = function()
        return 0.05, 0.82, 0.62
    end,
    Panel = function(f, o)
        calls.Panel = (calls.Panel or 0) + 1
        panelled[f] = true
        panelOpts[f] = o
    end,
    ScrollBar = function(f)
        calls.ScrollBar = (calls.ScrollBar or 0) + 1
    end,
    RegisterWindow = function(e)
        WSkin._packs[#WSkin._packs + 1] = e
    end,
}
WSkin._packs = {}

-- The LFG rail: round icons held in a mask, plus a gilded ring.
local pve = W("Frame", "PVEFrame")
local gf = W("Frame", "GroupFinderFrame", pve)
for i = 1, 3 do
    local b = W("Button", nil, gf)
    b.icon = b:CreateTexture()
    b.icon.parent = b
    b.icon.masks = { W("MaskTexture") }
    b.ring = b:CreateTexture()
    local label = b:CreateFontString()
    label.size = 12
    gf["groupButton" .. i] = b
end
-- A template string that reports size 0 before layout.
local zero = pve:CreateFontString()
zero.size = 0

local pq = W("Frame", "PVPQueueFrame")
for i = 1, 4 do
    local b = W("Button", nil, pq)
    b.Icon = b:CreateTexture()
    b.Icon.parent = b
    b.Icon.masks = { W("MaskTexture") }
    b.Ring = b:CreateTexture()
    pq["CategoryButton" .. i] = b
end
W("Frame", "PVPUIFrame")

-- A ScrollBox: its rows do not exist until Update runs, which is how the
-- Premade Groups results kept Blizzard's font.
local searchPanel = W("Frame", nil, pve)
local box = W("Frame", "VeneerProbeScrollBox", searchPanel)
box.ScrollTarget = W("Frame", nil, box)
box.rowsBuilt = false
function box:Update()
    if self.rowsBuilt then
        return
    end
    self.rowsBuilt = true
    for i = 1, 3 do
        local row = W("Frame", nil, self.ScrollTarget)
        local fs = row:CreateFontString()
        fs.size = 12
        self["row" .. i] = fs
    end
end

-- A stock window EUI has no pack for.
local tabard = W("Frame", "TabardFrame")
local tLabel = tabard:CreateFontString()
tLabel.size = 14

-- EUI's card art, as SkinCategoryButton would have left it.
for i = 1, 3 do
    EllesmereUI._GetFFD(gf["groupButton" .. i]).bg = gf["groupButton" .. i]:CreateTexture()
end

-- Real, not a no-op: AttachScrollBoxes hooks a ScrollBox's Update through it,
-- and the whole point of the test is that the hook fires.
-- The font pass is deferred one frame. Collect the callbacks so the test can
-- run them deliberately, which also proves the deferral actually happens.
SlashCmdList = {}
_G.__deferred = {}
-- Must exist before any pack applies: the bubble pack bails without it.
_G.__bubbles = {}
C_ChatBubbles = {
    GetAllChatBubbles = function()
        return _G.__bubbles
    end,
}

_G.__tickers = {}
C_Timer = {
    After = function(_, fn)
        table.insert(_G.__deferred, fn)
    end,
    NewTicker = function(_, fn)
        local t = { fn = fn, cancelled = false }
        t.Cancel = function(self)
            self.cancelled = true
        end
        table.insert(_G.__tickers, t)
        return t
    end,
}
local function RunFrame()
    local batch = _G.__deferred
    _G.__deferred = {}
    for _, fn in ipairs(batch) do
        fn()
    end
end

function hooksecurefunc(obj, name, fn)
    local orig = obj[name]
    obj[name] = function(...)
        local r = orig(...)
        fn(...)
        return r
    end
end

-- Packs.lua builds its own WSkin: the facade for everything published, ns.*
-- for the rest. Both halves come from the one stub above.
local ffdFor = EllesmereUI._GetFFD
local ns = {
    S = WSkin,
    FFD = ffdFor,
    PacksEnabled = function()
        return true
    end,
    Theme = WSkin.Theme,
    ResolveTheme = WSkin.ResolveTheme,
    Register = WSkin.RegisterWindow,
    CommonChrome = WSkin.CommonChrome,
    ControlsIn = nop,
    ButtonsIn = WSkin.ButtonsIn,
    AddBorder = WSkin.AddBorder,
    IsForeignFrame = function()
        return false
    end,
}
assert(loadfile(FILE))("SimpleEllesmereExtras", ns)

local fails = 0
local function check(n, ok, extra)
    if ok then
        print("  ok   " .. n)
    else
        fails = fails + 1
        print("  FAIL " .. n .. (extra and (" -- " .. tostring(extra)) or ""))
    end
end

print("LocalPacks execution test")
-- 2 rail packs + one font pack per distinct owning addon.
check("packs registered", #WSkin._packs > 20, #WSkin._packs)
local baseFontPack, dupes = nil, {}
for _, p in ipairs(WSkin._packs) do
    if dupes[p.key] then
        dupes.clash = p.key
    end
    dupes[p.key] = true
    if p.key == "localfonts:base" then
        baseFontPack = p
    end
end
check("no duplicate keys", dupes.clash == nil, dupes.clash)
check("base-UI font pack keyed deterministically", baseFontPack ~= nil)
check(
    "every key is namespaced 'local'",
    (function()
        for _, p in ipairs(WSkin._packs) do
            if p.key:sub(1, 5) ~= "local" then
                return false
            end
        end
        return true
    end)()
)

local keys = {}
for _, p in ipairs(WSkin._packs) do
    keys[p.key] = p
end
check("unique keys, none of EUI's", keys.localgroupfinder and keys.localpvp)

-- A real StaticPopup, so "the vendor owns these now" is checked against
-- something our packs could actually have skinned.
_G.StaticPopup1 = W("Frame", "StaticPopup1", UIParent)
_G.StaticPopup1.button1 = W("Button", nil, _G.StaticPopup1)

-- Run the login packs (no addons key) and the PVPUI one.
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
for _, p in ipairs(WSkin._packs) do
    if p.addons and p.addons.Blizzard_PVPUI then
        p.apply()
    end
end

-- StaticPopup skinning is the vendor's now (_popupSkin, default on). The
-- OnShow hooks it doubled as were the only retry for LFGListApplicationDialog,
-- which is built on first use, so a self-owned ADDON_LOADED watcher replaces
-- them: without it that dialog gets one shot at login and is missed.
local dialogWatcher
for _, f in ipairs(created) do
    if f.events and f.events.ADDON_LOADED and f.scripts.OnEvent then
        dialogWatcher = f
    end
end
check("localdialogs retries on ADDON_LOADED", dialogWatcher ~= nil)
check("StaticPopups are left to the vendor", panelled[_G.StaticPopup1] ~= true)

local tile = gf.groupButton1
local d = EllesmereUI._GetFFD(tile)
check("EUI card art faded", d.bg.alpha == 0)
check("ring faded despite keepRing", tile.ring.alpha == 0)
check(
    "plate lives on a CHILD frame, not a region of the button",
    d.localPlateHost ~= nil and d.localPlateHost.parent == tile
)
local plateIsRegionOfButton = false
for _, r in ipairs(tile.regions) do
    if r == d.localPlate then
        plateIsRegionOfButton = true
    end
end
check("plate is out of reach of EUI's Restrip", not plateIsRegionOfButton)
check("border added", bordered[tile] == true)
check("icon unmasked", tile.icon:GetNumMaskTextures() == 0)
check("icon texture substituted", tile.icon.texture == 133076, tile.icon.texture)
check("icon squared after unmasking", squared[tile.icon] == true)

local pvpTile = pq.CategoryButton1
check("pvp rail flattened too", EllesmereUI._GetFFD(pvpTile).localPlate ~= nil)
check("pvp icon substituted", pvpTile.Icon.texture == 236396, pvpTile.Icon.texture)

-- Fonts. Deferred a frame, so tick it first.
RunFrame()
local label
for _, r in ipairs(tile.regions) do
    if r.kind == "FontString" then
        label = r
    end
end
check("font applied to window text", label.font == "EUIFont", label.font)
check("size-0 string left alone (SetFont at 0 renders nothing)", zero.font == nil, zero.font)

-- Idempotence: a second pass must not stack plates or re-substitute.
local hostBefore = d.localPlateHost
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
check("second pass is idempotent", EllesmereUI._GetFFD(tile).localPlateHost == hostBefore)

-- Stock windows: shell + EUI's own chrome pass + fonts.
check("stock window shelled", shelled[tabard] == true, tostring(shelled[tabard]))
check("stock window got CommonChrome", chromed[tabard] == true)
check("stock window buttons walked", walked[tabard] == true)
RunFrame()
check("stock window text re-fonted", tLabel.font == "EUIFont", tLabel.font)
check("absent stock windows are a no-op", _G.BarberShopFrame == nil)

-- A label that fits in Blizzard's face but overflows in ours must not be left
-- clipped: shrink a little, and fall back to Blizzard's face if it still will
-- not fit. This is the "Back" -> "Bac" regression.
-- The fit machinery is for button labels only, so a fixture that models one
-- has to hang off a real Button the way "Start a Group" does.
local function label(len, box)
    local btn = W("Button", nil, pve)
    -- As wide as the label's box: a real button bounds how far PadLabel can
    -- widen, which is what forces the shrink when there is genuinely no room.
    btn.w = box
    local fs = W("FontString")
    fs.parent, fs.size, fs.textLen, fs.boxWidth = btn, 12, len, box
    btn.regions = { fs }
    btn.Text = fs -- the button's actual label, which is what marks it as one
    return fs
end

-- Ordinary text: no Button parent, so it keeps our face at Blizzard's size and
-- is left to wrap.
local function plain(len, box)
    local fs = W("FontString")
    fs.size, fs.textLen, fs.boxWidth = 12, len, box
    return fs
end

local roomy = label(4, 200) -- 4 chars, plenty of room
local snug = label(4, 4 * 12 * 1.2) -- fits Blizzard; fits ours once shrunk
local tight = label(10, 10 * 12 * 1.0) -- exactly fits Blizzard and nothing else
local auto = label(40, 0) -- auto-sizing: no box, cannot overflow

-- The real regression: a button label that WRAPS rather than clipping, so a
-- width check alone sees no problem while the second line is cut off.
local wrapFits = label(13, 13 * 12 * 1.25) -- wraps in ours at 12, fits at 11
wrapFits.wraps = true
local wrapNever = label(13, 13 * 12 * 1.0) -- one line only in Blizzard's face
wrapNever.wraps = true

pve.regions = {}
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end

check("nothing re-fonted before the frame ticks", roomy.font == nil, roomy.font)
check("a deferred pass was scheduled", #_G.__deferred > 0)
RunFrame()

check("roomy label keeps our font", roomy.font == "EUIFont", roomy.font)
check("roomy label keeps its size", roomy.size == 12, roomy.size)
check("auto-sizing label keeps our font", auto.font == "EUIFont", auto.font)
check(
    "snug label shrank to fit",
    snug.font == "EUIFont" and snug.size < 12,
    tostring(snug.font) .. "@" .. tostring(snug.size)
)
check("snug label actually fits now", snug:GetStringWidth() <= snug:GetWidth())
-- Never handed back to Blizzard's face. A label sitting in a different font to
-- the one beside it is a worse fault than a clipped pixel, and reverting was
-- how whole panes ended up mixed.
check("unfittable label keeps our face", tight.font == "EUIFont", tight.font)
check("unfittable label stops at the shrink floor", tight.size == 9, tight.size)

check("wrapping label stayed on one line", wrapFits:GetNumLines() == 1, wrapFits:GetNumLines())
check(
    "wrapping label kept our font by shrinking",
    wrapFits.font == "EUIFont" and wrapFits.size < 12,
    tostring(wrapFits.font) .. "@" .. tostring(wrapFits.size)
)
check("unfittable wrapper keeps our face", wrapNever.font == "EUIFont", wrapNever.font)

-- A paragraph that wraps BY DESIGN is not overflowing: on one line it is wider
-- than its box by definition, and it is still on the same number of lines as
-- Blizzard's face put it. Measuring those unbounded reverted every wrapping
-- block in the UI to Blizzard's font.
local para = plain(40, 350)
para.wraps = true

pve.regions = { para }
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
RunFrame()

check("a paragraph that wraps by design keeps our font", para.font == "EUIFont", para.font)
check("and keeps its size", para.size == 12, para.size)

-- A string released between the walk and the deferred pass. Every method on it
-- raises then, IsForbidden included, and it must not take its neighbours down.
local released = plain(4, 200)
local survivor = plain(4, 200)
pve.regions = { released, survivor }
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
function released:IsForbidden()
    error("calling 'IsForbidden' on bad self (Wrong object type for function)")
end
check("a released string does not raise", pcall(RunFrame))
check("its neighbour is still re-fonted", survivor.font == "EUIFont", survivor.font)

-- THE SPEC-PAGE BUG. Ordinary strings side by side, one of them long enough
-- that our face will not fit it. The old code answered per STRING: the long one
-- was shrunk a point, or handed back to Blizzard's face outright, while its
-- neighbours kept ours -- so "Marksmanship" sat in a different font to
-- "Survival" and the three blurbs under them were set at different sizes.
-- Siblings must come out identical however long they are.
local specShort = plain(8, 8 * 12 * 1.4)
local specLong = plain(14, 14 * 12 * 1.0)
local specBlurb = plain(40, 350)
specBlurb.wraps = true

pve.regions = { specShort, specLong, specBlurb }
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
RunFrame()

check(
    "siblings share one face however long they are",
    specShort.font == "EUIFont" and specLong.font == "EUIFont" and specBlurb.font == "EUIFont",
    tostring(specShort.font) .. " / " .. tostring(specLong.font)
)
check(
    "siblings share one size however long they are",
    specShort.size == 12 and specLong.size == 12 and specBlurb.size == 12,
    tostring(specShort.size) .. " / " .. tostring(specLong.size)
)

-- Blizzard re-sizing a pooled row without touching its face. Comparing the
-- face alone never noticed, so the row went on being redrawn at the stale size.
specShort.size = 9
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
RunFrame()
check("a size-only change by Blizzard is followed", specShort.size == 9, specShort.size)

-- A string already wearing what the last pass left is not touched again. Every
-- ScrollBox Update re-queues its rows, and two SetFont calls per string per
-- update is a frame-time cost on a busy list.
local setFonts = 0
local realSetFont = Widget.SetFont
Widget.SetFont = function(fs, ...)
    -- An unmeasurable label is retried by design.
    if fs ~= auto then
        setFonts = setFonts + 1
    end
    return realSetFont(fs, ...)
end
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
RunFrame()
Widget.SetFont = realSetFont
check("an unchanged string is not re-fonted", setFonts == 0, setFonts)

-- A LIST ROW IS A BUTTON, AND ITS COLUMNS ARE NOT LABELS.
--
-- Blizzard builds the Premade Groups applicant list out of row Buttons with
-- plain FontStrings on them for Name / Role / iLvl / Rating. Treating those as
-- button labels forbids their wrap, and a FontString that cannot wrap
-- truncates with an ellipsis -- the rating rendered as "29...".
local row = W("Button", nil, pve)
row.w = 300
local rowLabel = W("FontString")
rowLabel.parent, rowLabel.size, rowLabel.textLen, rowLabel.boxWidth = row, 12, 4, 200
row.Text = rowLabel
local ratingCell = W("FontString")
ratingCell.parent, ratingCell.size, ratingCell.textLen, ratingCell.boxWidth = row, 12, 4, 30
row.regions = { rowLabel, ratingCell }

pve.regions = {}
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
RunFrame()

check("a row column is not forced onto one line", ratingCell.wraps ~= false, tostring(ratingCell.wraps))
check("a row column is not capped to one line", ratingCell.maxLines == nil, tostring(ratingCell.maxLines))
check("a row column keeps Blizzard's size", ratingCell.size == 12, ratingCell.size)
check("the row's own label is still treated as one", rowLabel.wraps == false, tostring(rowLabel.wraps))

-- "Dungeon Finder" on the Group Finder rail: 14 characters in a box that fits
-- Blizzard's face at 12 but not ours. Two shrink steps left it truncated to
-- "Dungeon Find..."; it has to keep shrinking until it fits.
local railBtn = W("Button", nil, pve)
railBtn.w = 14 * 12 * 1.15
local rail = W("FontString")
rail.parent, rail.size, rail.textLen, rail.boxWidth = railBtn, 12, 14, 14 * 12 * 1.15
railBtn.Text = rail
railBtn.regions = { rail }

pve.regions = {}
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
RunFrame()

check(
    "a long rail label shrinks rather than truncating",
    rail:GetStringWidth() <= rail:GetWidth(),
    rail.size .. "pt, " .. rail:GetStringWidth() .. " in " .. rail:GetWidth()
)
check("and it keeps our face", rail.font == "EUIFont", rail.font)
check("and stays within the shrink floor", rail.size >= 9, rail.size)

-- A button label must be forbidden from wrapping at all, measurement or no
-- measurement. This is the "Accept" -> "Accep"/"t" case on a popup that was
-- not laid out yet even a frame after its OnShow.
local btnLabel = label(6, 6 * 12 * 1.05)
btnLabel.wraps = true

local plainLabel = plain(6, 6 * 12 * 1.05)
plainLabel.wraps = true

pve.regions = { plainLabel }
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
RunFrame()

check("button label forbidden from wrapping", btnLabel.wraps == false, tostring(btnLabel.wraps))
check("button label capped at one line", btnLabel.maxLines == 1, tostring(btnLabel.maxLines))
check("non-button text may still wrap", plainLabel.wraps ~= false, tostring(plainLabel.wraps))
check("and is back on one line", wrapNever:GetNumLines() == 1, wrapNever:GetNumLines())

-- A button label that overflows by a fraction of a pixel: /euidiag measured
-- 74.3px of "Start a Group" in a 73.5px box, and with the wrap forbidden that
-- 0.8px costs the whole "p". Dropping a font point to buy it back is the wrong
-- lever -- the box is what is short.
local WANT = 13 * 12 * 1.4

local padParent = W("Button", nil, pve)
function padParent:IsObjectType(t)
    return t == "Button"
end
padParent.w = 400
local padLabel = label(13, WANT - 0.8)
padLabel.parent = padParent
padParent.Text = padLabel

-- The same label on a button with no room to give still has to shrink.
local crampedParent = W("Button", nil, pve)
function crampedParent:IsObjectType(t)
    return t == "Button"
end
crampedParent.w = WANT - 0.8
local crampedLabel = label(13, WANT - 0.8)
crampedLabel.parent = crampedParent
crampedParent.Text = crampedLabel

pve.regions = { padLabel, crampedLabel }
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
RunFrame()

check("hair-width button label kept its size", padLabel.size == 12, padLabel.size)
check(
    "hair-width button label had its box widened",
    padLabel:GetWidth() >= padLabel:GetStringWidth(),
    padLabel:GetWidth()
)
check(
    "padding never grows past the button",
    crampedLabel:GetWidth() <= crampedParent:GetWidth(),
    crampedLabel:GetWidth()
)
check(
    "cramped button label shrank instead",
    crampedLabel.font == "EUIFont" and crampedLabel.size < 12,
    tostring(crampedLabel.font) .. "@" .. tostring(crampedLabel.size)
)

-- A MONEY DENOMINATION: the label auto-sizes to its text and the button takes
-- its width from the label, so a pin traps both. Blizzard rewrites the text
-- whenever the other side moves money, and the pin is still there -- which is
-- how the trade window's recipient gold rendered as "...".
--
-- The box only catches up with the text at layout, exactly as in game: at
-- measure time it still reports what Blizzard's narrower face needed, so the
-- string looks like it is overflowing and asks to be padded.
local coinBtn = W("Button", nil, pve)
function coinBtn:IsObjectType(t)
    return t == "Button"
end
local coinText = W("FontString")
coinText.parent, coinText.size, coinText.textLen = coinBtn, 12, 1
coinBtn.regions = { coinText }
function coinBtn:GetFontString()
    return coinText
end
function coinText:GetWidth()
    return self.boxWidth or self.autoW or 0
end
function coinBtn:GetWidth()
    return coinText:GetWidth() + 13
end
local function CoinLayout()
    coinText.autoW = coinText:GetStringWidth()
end
CoinLayout()

pve.regions = { coinText }
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
RunFrame()

check("money label gets our face", coinText.font == "EUIFont", coinText.font)
-- It IS padded now: refusing to pad an auto-sizing label was what left
-- "Start a Grou" clipped. What makes the pin safe is that it does not outlive
-- the text it was measured for.
check("auto-sizing money label is padded to fit", coinText.boxWidth ~= nil, coinText.boxWidth)

-- The other side puts gold in. Blizzard rewrites the label in place.
coinText:SetText("1234")
check("a rewrite releases the pin", coinText.boxWidth == nil, coinText.boxWidth)
CoinLayout()
RunFrame()
check(
    "a longer amount fits once re-fitted",
    coinText:GetWidth() >= coinText:GetUnboundedStringWidth(),
    coinText:GetWidth() .. " < " .. coinText:GetUnboundedStringWidth()
)

-- THE "START A GROU" BUG, which is this one seen from the other side.
--
-- A button label with no width of its own. Once the wrap is forbidden the
-- string CLIPS, so GetStringWidth answers for what is left and the label
-- measures as fitting while its last character is gone. Only the unbounded
-- width tells the truth, and reaching it depended on a getter the client does
-- not have. Four buttons shipped like this: Start a Group, Find a Group,
-- Join as Group and Sign Up.
local signBtn = W("Button", nil, pve)
function signBtn:IsObjectType(t)
    return t == "Button"
end
signBtn.w = 400
local signText = W("FontString")
signText.parent, signText.size = signBtn, 12
signText:SetText("Sign Up")
signBtn.regions = { signText }
signBtn.Text = signText
function signText:GetWidth()
    return self.boxWidth or self.autoW or 0
end
-- Laid out against Blizzard's face, which is what the box still reports when
-- the swap happens.
signText.autoW = signText:GetStringWidth()

pve.regions = { signText }
for _, p in ipairs(WSkin._packs) do
    if not p.addons then
        p.apply()
    end
end
RunFrame()

check(
    "clipped label is seen as overflowing at all",
    signText.boxWidth ~= nil or signText.size < 12,
    tostring(signText.boxWidth) .. "@" .. tostring(signText.size)
)
check("clipped label was widened rather than shrunk", signText.size == 12, signText.size)
check(
    "and the whole word now fits",
    signText:GetWidth() >= signText:GetUnboundedStringWidth(),
    signText:GetWidth() .. " < " .. signText:GetUnboundedStringWidth()
)

-- Rows created after the walk must still get the font.
check("no rows before Update", box.row1 == nil)
box:Update()
check("Update created rows", box.row1 ~= nil)
RunFrame()
check("pooled row re-fonted on Update", box.row1.font == "EUIFont", box.row1 and box.row1.font)
check("every pooled row got it", box.row3 and box.row3.font == "EUIFont")

-- Recycled rows carry whatever Blizzard last set, so a later Update must
-- re-apply rather than bail on a guard.
box.row1.font = "BlizzFont"
box.rowsBuilt = true
box:Update()
RunFrame()
check("recycled row re-fonted again", box.row1.font == "EUIFont", box.row1.font)

-- ...and at the size Blizzard just gave it, not the one this row happened to
-- carry the first time it was ever walked. Caching that forever pins one row in
-- a list to a different size to its neighbours.
box.row1.font, box.row1.size = "BlizzFont", 9
box:Update()
RunFrame()
check("a re-fonted row follows Blizzard's new size", box.row1.size == 9, box.row1.size)

-- One GetChildren call per frame walked. Calling it again per child made each
-- walk quadratic in the row count, on every ScrollBox Update.
local childCalls = 0
local target = box.ScrollTarget
function target:GetChildren()
    childCalls = childCalls + 1
    return Widget.GetChildren(self)
end
box:Update()
target.GetChildren = nil
check("a walk asks a frame for its children once", childCalls == 1, childCalls)

-- Chat bubbles: anonymous, pooled, no event -- polled, and the poll must
-- retire itself when nothing is talking.
--
-- The body is found by its text, because the depth it sits at varies: assuming
-- "the first child, always" skinned neither player nor NPC bubbles.
local bubbleHolder = W("Frame")
bubbleHolder.Tail = W("Texture")
bubbleHolder.Center = W("Texture")
bubbleHolder:CreateFontString()
local bubble = W("Frame")
bubble.children = { bubbleHolder }

-- Same bubble, art and text on the frame the API handed back.
local flatBubble = W("Frame")
flatBubble.Tail = W("Texture")
flatBubble:CreateFontString()

-- And one nested a level deeper than the old code looked.
local deepBody = W("Frame")
deepBody:CreateFontString()
local deepMid = W("Frame")
deepMid.children = { deepBody }
local deepBubble = W("Frame")
deepBubble.children = { deepMid }

local tickers = _G.__tickers
check("bubble poll started once, not once per apply", #tickers == 1, #tickers)

_G.__bubbles = { bubble, flatBubble, deepBubble }
tickers[1].fn()
check("bubble skinned", panelled[bubbleHolder] == true)
check("bubble tail hidden", bubbleHolder.Tail.alpha == 0)
check("bubble panel adds no fill of its own", panelOpts[bubbleHolder] and panelOpts[bubbleHolder].noBg == true)
check("bubble gets a see-through fill instead", EllesmereUI._GetFFD(bubbleHolder).bg ~= nil)
check("art on the frame itself is skinned too", panelled[flatBubble] == true)
check("and its tail hidden", flatBubble.Tail.alpha == 0)
check("a body nested deeper is still found", panelled[deepBody] == true)
check(
    "the positioner is stripped, not panelled over the body",
    panelOpts[bubble] and panelOpts[bubble].noBg == true and panelOpts[bubble].noBorder == true
)

-- Skinning is once per bubble, not once per poll.
local n = calls.Panel
tickers[1].fn()
check("a skinned bubble is not re-panelled", calls.Panel == n, calls.Panel)

-- With nothing talking the ticker must retire rather than poll forever.
_G.__bubbles = {}
for _ = 1, 31 do
    tickers[1].fn()
end
check("idle poll retires itself", tickers[1].cancelled == true)

-- A theme change must repaint rather than be ignored.
check("registered a looks callback", #looksCallbacks > 0)
for _, fn in ipairs(looksCallbacks) do
    fn()
end
check("looks callbacks survive being fired", true)

print(fails == 0 and "\nall checks passed" or ("\n" .. fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
