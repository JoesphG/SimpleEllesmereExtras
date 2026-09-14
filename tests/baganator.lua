local FILE = "Baganator.lua"

local Widget = {}
Widget.__index = Widget
local function nop() end
local function W(kind, name)
    return setmetatable({ kind = kind, name = name, regions = {}, alpha = 1 }, Widget)
end
function Widget:IsObjectType(t)
    return self.kind == t
end
function Widget:IsForbidden()
    return false
end
function Widget:SetAlpha(a)
    self.alpha = a
end
function Widget:SetVertexColor(r, g, b, a)
    self.vr, self.vg, self.vb, self.va = r, g, b, a
end
function Widget:GetVertexColor()
    return self.vr or 0.64, self.vg or 0.21, self.vb or 0.93, self.va or 1
end
function Widget:GetNumMaskTextures()
    return 0
end
function Widget:SetTexCoord()
    self.cropped = true
end
function Widget:SetDrawLayer(l)
    self.layer = l
end
function Widget:SetShown(v)
    self.shown = v and true or false
end
function Widget:IsShown()
    return self.shown ~= false
end
function Widget:Show()
    self.shown = true
end
function Widget:Hide()
    self.shown = false
end
for _, m in ipairs({ "SetColorTexture", "SetPoint", "SetAllPoints" }) do
    Widget[m] = nop
end

-- A real hook, not a recording one. The quality border follows the ring by
-- hooking SetVertexColor/Show/Hide, so a stub that only remembers the call
-- cannot exercise it -- and would have passed while the feature was broken.
hooksecurefunc = function(obj, name, fn)
    local orig = obj[name]
    obj["__hook_" .. name] = fn
    obj[name] = function(...)
        local r = orig(...)
        fn(...)
        return r
    end
end
geterrorhandler = function()
    return function(e)
        _G.__err = tostring(e)
    end
end

local ffd = setmetatable({}, { __mode = "k" })
local skinCallback
EllesmereUI = {
    _GetFFD = function(f)
        ffd[f] = ffd[f] or {}
        return ffd[f]
    end,
    RegisterSkin = function(name, cb)
        skinCallback = cb
    end,
}
CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function(s, k, f)
            s[k] = f
        end,
    }
end

local calls = {}
local function rec(name)
    return function(...)
        calls[name] = (calls[name] or 0) + 1
        calls[name .. "_args"] = { ... }
    end
end
local WSkin
WSkin = {
    -- Mirrors the real primitive: FadeRegions over the button, sparing only
    -- the regions named in keepKeys. Without this the test cannot see the bug.
    Button = function(btn, keepKeys)
        calls.Button = (calls.Button or 0) + 1
        calls.lastKeep = keepKeys
        local keep = {}
        for _, k in ipairs(keepKeys or {}) do
            if btn[k] then
                keep[btn[k]] = true
            end
        end
        for _, r in ipairs(btn.regions or {}) do
            if not keep[r] then
                r.alpha = 0
            end
        end
    end,
    SquareIcon = function(icon)
        calls.SquareIcon = (calls.SquareIcon or 0) + 1
        icon.squared = true
        return true
    end,
    QualityBorder = function(owner, icon, r, g, b)
        calls.QualityBorder = (calls.QualityBorder or 0) + 1
        owner.borderColour = { r, g, b }
    end,
    Shell = function(frame)
        calls.Shell = (calls.Shell or 0) + 1
    end,
    Panel = rec("Panel"),
    Inset = rec("Inset"),
    EditBox = rec("EditBox"),
    Checkbox = rec("Checkbox"),
    Dropdown = rec("Dropdown"),
    Tab = rec("Tab"),
    ScrollBar = rec("ScrollBar"),
    CloseButton = rec("CloseButton"),
    PageButton = rec("PageButton"),
    Font = function(fs)
        calls.Font = (calls.Font or 0) + 1
        fs.fonted = true
    end,
}

local listener
local masque = false
Baganator = {
    API = {
        IsMasqueApplying = function()
            return masque
        end,
        Skins = {
            RegisterListener = function(fn)
                listener = fn
            end,
        },
    },
}

local ns = {}
assert(loadfile("Core.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile(FILE))("SimpleEllesmereExtras", ns)
-- EUI hands the facade over at PLAYER_LOGIN.
skinCallback(WSkin)

local fails = 0
local function check(n, ok, extra)
    if ok then
        print("  ok   " .. n)
    else
        fails = fails + 1
        print("  FAIL " .. n .. (extra and (" -- " .. tostring(extra)) or ""))
    end
end

print("Baganator skin test")
check("listener registered before PLAYER_LOGIN", listener ~= nil)

-- Item slot: the icon must be SPARED from the strip, then squared + bordered.
local slot = W("Button")
slot.icon = W("Texture")
slot.IconBorder = W("Texture")
slot.searchOverlay = W("Texture")
slot.ItemContextOverlay = W("Texture")
local strayArt = W("Texture")
slot.regions = { slot.icon, slot.IconBorder, slot.searchOverlay, slot.ItemContextOverlay, strayArt }
slot.SetItemButtonTexture = nop
listener({ regionType = "ItemButton", region = slot })
check("slot skinned via Button", calls.Button == 1)
check(
    "icon named in keepKeys, so the strip spares it",
    calls.lastKeep and calls.lastKeep[1] == "icon",
    calls.lastKeep and calls.lastKeep[1]
)
check("icon squared", slot.icon.squared == true)
check("Blizzard IconBorder hidden", slot.IconBorder.alpha == 0)
check("quality colour moved onto the border", slot.borderColour[1] == 0.64, slot.borderColour and slot.borderColour[1])

-- Baganator drives the ring directly and, for a COMMON item, sets it white
-- and then hides it. Reading that white once is what put a white border on
-- every slot; hidden must mean black.
slot.IconBorder:SetVertexColor(1, 1, 1, 1)
slot.IconBorder:Hide()
check(
    "hidden ring paints black, not white",
    slot.borderColour[1] == 0 and slot.borderColour[2] == 0 and slot.borderColour[3] == 0,
    table.concat({ tostring(slot.borderColour[1]), tostring(slot.borderColour[2]) }, ",")
)

-- ...and a later rarity must be picked up, because slots are pooled.
slot.IconBorder:SetVertexColor(0.0, 0.44, 0.87, 1)
slot.IconBorder:Show()
check(
    "border follows a later rarity",
    slot.borderColour[1] == 0.0 and slot.borderColour[2] == 0.44,
    tostring(slot.borderColour[2])
)
check("the ring itself stays invisible", slot.IconBorder.alpha == 0, slot.IconBorder.alpha)
check("re-texture hook installed for recycled slots", slot.__hook_SetItemButtonTexture ~= nil)

-- The regression this rework exists for. Baganator dims a non-matching slot
-- with searchOverlay:SetShown(true); alpha-ing that region means search stops
-- highlighting anything.
check("searchOverlay survives the strip", slot.searchOverlay.alpha ~= 0, slot.searchOverlay.alpha)
check(
    "searchOverlay named in keepKeys",
    (function()
        for _, k in ipairs(calls.lastKeep or {}) do
            if k == "searchOverlay" then
                return true
            end
        end
        return false
    end)()
)
check("searchOverlay drawn above our fill", slot.searchOverlay.layer == "OVERLAY", slot.searchOverlay.layer)
check("ItemContextOverlay survives too", slot.ItemContextOverlay.alpha ~= 0)
check("unrelated art is still stripped", strayArt.alpha == 0, strayArt.alpha)

-- And it must still be usable as a dim: shown for a miss, hidden for a hit.
slot.searchOverlay:SetShown(true)
check("dim can be shown for a non-match", slot.searchOverlay.shown == true)
slot.searchOverlay:SetShown(false)
check("dim can be hidden for a match", slot.searchOverlay.shown == false)

-- Idempotent: Baganator re-announces regions on refresh.
listener({ regionType = "ItemButton", region = slot })
check("slot skin is idempotent", calls.Button == 1, calls.Button)

-- Masque owns the slots when it is applying.
masque = true
local slot2 = W("Button")
slot2.icon = W("Texture")
listener({ regionType = "ItemButton", region = slot2 })
check("defers to Masque for slots", calls.Button == 1 and slot2.icon.squared ~= true)
masque = false

-- Window chrome
listener({ regionType = "ButtonFrame", region = W("Frame") })
check("bag window gets a Shell", calls.Shell == 1)
check("shell applied", calls.Shell == 1, calls.Shell)

listener({ regionType = "SearchBox", region = W("EditBox") })
listener({ regionType = "TrimScrollBar", region = W("Frame") })
listener({ regionType = "TopTabButton", region = W("Button") })
listener({ regionType = "CheckBox", region = W("CheckButton") })
listener({ regionType = "Dropdown", region = W("Frame") })
listener({ regionType = "InsetFrame", region = W("Frame") })
check(
    "chrome primitives all fired",
    calls.EditBox == 1
        and calls.ScrollBar == 1
        and calls.Tab == 1
        and calls.Checkbox == 1
        and calls.Dropdown == 1
        and calls.Inset == 1
)

listener({ regionType = "ScrollButton", region = W("Button"), tags = { "left" } })
check("scroll arrow uses the house page glyph", calls.PageButton == 1)

-- Category text
local label = W("FontString")
listener({ regionType = "CategoryLabel", region = label })
check("category label re-fonted", label.fonted == true)
local header = W("Frame")
header.Label = W("FontString")
listener({ regionType = "CategorySectionHeader", region = header })
check("section header re-fonted via .Label", header.Label.fonted == true)

local corner = W("FontString")
listener({ regionType = "CornerWidget", region = corner })
check("fontstring corner widget re-fonted", corner.fonted == true)
local cornerTex = W("Texture")
listener({ regionType = "CornerWidget", region = cornerTex })
check("texture corner widget left alone", cornerTex.fonted == nil)

-- Divider
local div = W("Texture")
listener({ regionType = "Divider", region = div })
check("divider recoloured without error", _G.__err == nil, _G.__err)

-- Unknown types must be ignored silently.
listener({ regionType = "SomethingNew", region = W("Frame") })
check("unknown regionType ignored", _G.__err == nil, _G.__err)

print(fails == 0 and "\nall checks passed" or ("\n" .. fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
