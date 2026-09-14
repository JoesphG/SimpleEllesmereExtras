-- Chrome.lua is the half of the old engine access that had to be rewritten to
-- stand outside EllesmereUI. It is new code, so it gets its own suite: the
-- pack suite injects recorders for these and would not notice them misbehaving.
local Widget = {}
Widget.__index = Widget

local function W(kind, name, parent)
    local w = setmetatable({ kind = kind, name = name, parent = parent, children = {}, regions = {} }, Widget)
    if name then
        _G[name] = w
    end
    if parent then
        parent.children[#parent.children + 1] = w
    end
    return w
end

function Widget:IsObjectType(t)
    if t == "Button" then
        return self.kind == "Button" or self.kind == "CheckButton" or self.kind == "DropdownButton"
    end
    return self.kind == t
end
function Widget:IsForbidden()
    return self.forbidden == true
end
function Widget:GetName()
    return self.name
end
function Widget:GetParent()
    return self.parent
end
function Widget:GetChildren()
    return unpack(self.children)
end
function Widget:CreateTexture()
    local t = W("Texture")
    self.regions[#self.regions + 1] = t
    return t
end
function Widget:ClearAllPoints()
    self.points = {}
end
function Widget:SetPoint(...)
    self.points = self.points or {}
    self.points[#self.points + 1] = { ... }
end
function Widget:SetJustifyH(j)
    self.justify = j
end
function Widget:GetFontString()
    return self.fontString
end
function Widget:GetText()
    return self.text
end
for _, m in ipairs({ "SetColorTexture", "SetHeight", "SetWidth" }) do
    Widget[m] = function() end
end

C_AddOns = {
    GetNumAddOns = function()
        return 2
    end,
    GetAddOnInfo = function(i)
        return i == 1 and "SomeOtherAddon" or "Blizzard_TabardUI"
    end,
    IsAddOnLoaded = function()
        return true
    end,
}
CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function() end,
    }
end
geterrorhandler = function()
    return function(e)
        _G.__err = tostring(e)
    end
end

-- The facade arrives from EllesmereUI's own dispatcher, so register the way it
-- does: Core hands RegisterSkin a callback at load and waits to be called.
local skinCallback
local ffd = setmetatable({}, { __mode = "k" })
EllesmereUI = {
    _GetFFD = function(f)
        ffd[f] = ffd[f] or {}
        return ffd[f]
    end,
    RegisterSkin = function(_, cb)
        skinCallback = cb
    end,
}

local ns = {}
assert(loadfile("Core.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile("Chrome.lua"))("SimpleEllesmereExtras", ns)

local calls = {}
-- The real primitives are idempotent, so a second walk re-calls them harmlessly
-- and a count alone cannot say WHICH widget was skinned. Keep the set too.
local skinned = {}
local function rec(name)
    return function(obj)
        calls[name] = (calls[name] or 0) + 1
        calls[name .. "_last"] = obj
        skinned[obj] = name
    end
end

local S = {
    EditBox = rec("EditBox"),
    Checkbox = rec("Checkbox"),
    Dropdown = rec("Dropdown"),
    ScrollBar = rec("ScrollBar"),
    Button = function(obj, keep)
        calls.Button = (calls.Button or 0) + 1
        calls.Button_last = obj
        calls.Button_keep = keep
        skinned[obj] = "Button"
    end,
    CloseButton = rec("CloseButton"),
    PageButton = function(_, glyph)
        calls.PageButton = (calls.PageButton or 0) + 1
        calls.PageGlyph = glyph
    end,
    GetPanelColor = function()
        return 0.06, 0.07, 0.08, 0.9
    end,
    GetFont = function()
        return "Interface\\Fonts\\Expressway.TTF", "OUTLINE"
    end,
    GetAccentColor = function()
        return 0.047, 0.824, 0.616
    end,
    OnLooksChanged = function(fn)
        calls.looks = fn
    end,
}

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

out("Chrome test\n")

-- REGISTRATION WAITS FOR THE FACADE. Applying from our own PLAYER_LOGIN would
-- race it: the facade is handed over from EllesmereUI's handler, and a pack
-- that ran first would call nil.
local applied = {}
ns.Register({
    key = "base",
    apply = function()
        applied.base = true
    end,
})
ns.Register({
    key = "lod",
    addons = { Blizzard_TabardUI = true },
    apply = function()
        applied.lod = true
    end,
})
check("nothing applies before the facade arrives", applied.base == nil and applied.lod == nil)

skinCallback(S)
check("the facade releases the queue", applied.base == true)
check("a load-on-demand window already loaded applies too", applied.lod == true)

-- Registering after login must not be dropped on the floor.
local late
ns.Register({
    key = "late",
    apply = function()
        late = true
    end,
})
check("a late registration applies immediately", late == true)

-- Each entry is isolated: one broken pack must not cost the others.
local after
ns.Register({
    key = "boom",
    apply = function()
        error("boom")
    end,
})
ns.Register({
    key = "after",
    apply = function()
        after = true
    end,
})
check("a pack that errors is contained", _G.__err ~= nil and after == true, _G.__err)

-- Theme comes from the getters, since the facade publishes no theme table.
local T = ns.Theme
check("panel colour read from the facade", T.bgR == 0.06 and T.bgA == 0.9, tostring(T.bgR))
check("font read from the facade", T.fontPath:find("Expressway") ~= nil, T.fontPath)
check("accent read from the facade", T.accG == 0.824, tostring(T.accG))
check("border defaults to black, which the facade cannot answer", T.brdR == 0)
check("looks changes re-resolve the theme", calls.looks == ns.ResolveTheme)

-- Border: the engine's version no-opped silently when EllesmereUI's
-- pixel-perfect API was missing, which is how every rail tile ended up with
-- border=false. Ours draws four edges and is idempotent.
local plate = W("Frame")
local edges = ns.AddBorder(plate)
check("border draws four edges", #edges == 4, #edges)
check("border is idempotent", ns.AddBorder(plate) == edges)

-- Controls: one walk, dispatched by type. A CheckButton answers true to
-- IsObjectType("Button"), so it has to be claimed before the button pass.
local win = W("Frame", "TabardFrame")
W("EditBox", nil, win)
W("CheckButton", nil, win)
W("Slider", nil, win)
local dd = W("Frame", "TabardFrameDropDown", win)
local plain = W("Button", nil, win)
plain.fontString = W("FontString")
plain.fontString.text = "Accept"
local pager = W("Button", nil, win)
win.NextPageButton = pager

-- An ICON button: no label, just art. Plating one alphas its texture regions,
-- which is what emptied the role icon in "Choose your Roles" and left a black
-- square with a tick on it.
local roleButton = W("Button", nil, win)
roleButton.Icon = W("Texture")

ns.ButtonsIn(win)
check("edit box skinned", calls.EditBox == 1, calls.EditBox)
check("check button skinned as a checkbox", calls.Checkbox == 1, calls.Checkbox)
check("check button not also plated as a button", calls.Button == 1, calls.Button)
check("slider skinned as a scroll bar", calls.ScrollBar == 1, calls.ScrollBar)
check("dropdown found by name", calls.Dropdown == 1, calls.Dropdown)
check("paging button gets the page glyph", calls.PageButton == 1 and calls.PageGlyph == ">", calls.PageGlyph)
check("the labelled button is the one that got plated", calls.Button_last == plain)
check("and the pager was not plated", skinned[pager] ~= "Button")
check("an icon button is left alone", skinned[roleButton] == nil)
check(
    "a plated button still spares its icon regions",
    (function()
        for _, k in ipairs(calls.Button_keep or {}) do
            if k == "Icon" then
                return true
            end
        end
        return false
    end)()
)
check("dd is reachable", dd ~= nil)

-- A frame belonging to another loaded addon is not ours to walk into.
local foreign = W("Frame", "SomeOtherAddonPanel", win)
local foreignBox = W("EditBox", nil, foreign)
ns.ControlsIn(win)
check("a foreign frame's controls are left alone", skinned[foreignBox] == nil, skinned[foreignBox])
check("IsForeignFrame judges by loaded addon name", ns.IsForeignFrame(foreign) == true)
check("and a Blizzard frame is not foreign", ns.IsForeignFrame(win) == false)

-- CommonChrome: close button, controls, and the title re-centred onto the
-- shell's top bar, which is where the engine leaves it.
local titled = W("Frame", "RaidInfoFrame")
titled.CloseButton = W("Button", nil, titled)
titled.TitleText = W("FontString")
EllesmereUI._GetFFD(titled).topBar = W("Frame")
ns.CommonChrome(titled, "RaidInfoFrame")
check("close button skinned as a close button", calls.CloseButton == 1, calls.CloseButton)
check("title re-centred", titled.TitleText.justify == "CENTER")
check("title anchored to the shell top bar", titled.TitleText.points[1][2] == EllesmereUI._GetFFD(titled).topBar)
check(
    "title centring is one-shot",
    (function()
        titled.TitleText.points = nil
        ns.CommonChrome(titled, "RaidInfoFrame")
        return titled.TitleText.points == nil
    end)()
)

-- /euilocal is read HERE, not at the pack's file scope: our saved variables do
-- not exist that early, so a file-scope read always answers with the default
-- and a saved `off` would be lost. Every pack goes through Apply, so this is
-- the one place the switch has to hold.
local gated
ns.PacksEnabled = function()
    return false
end
ns.Register({
    key = "gated",
    apply = function()
        gated = true
    end,
})
check("the switch being off stops a pack applying", gated == nil)

ns.PacksEnabled = function()
    return true
end
local ungated
ns.Register({
    key = "ungated",
    apply = function()
        ungated = true
    end,
})
check("and on lets it through", ungated == true)

out(fails == 0 and "\nall checks passed\n" or ("\n" .. fails .. " failed\n"))
os.exit(fails == 0 and 0 or 1)
