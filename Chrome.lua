-------------------------------------------------------------------------------
--  Chrome.lua
--
--  The pieces of EllesmereUI's window engine that its public skin API does not
--  hand out, rebuilt from the pieces it does.
--
--  WHY THIS FILE EXISTS
--
--  The window packs used to be loaded from EllesmereUI's own .toc, which put
--  them inside its addon namespace and handed them `ns.WSkin`: the whole
--  engine. As a separate addon we get `S`, and `S` is a whitelist -- Panel,
--  Inset, Button, Font, White, Shell, EditBox, Checkbox, Dropdown, ScrollBar,
--  Tab, CloseButton, PageButton, SquareIcon, the colour getters and
--  OnLooksChanged. Five things the packs used are not on it:
--
--    Theme / ResolveTheme   the colour and font table -> the getters below
--    RegisterWindow         apply-at-login registry    -> Register below
--    CommonChrome           a bundle of control skins  -> composed below
--    ButtonsIn              a button walker            -> written below
--    AddBorder              a 1px edge                 -> drawn below
--
--  NONE OF THIS IS ELLESMEREUI'S CODE. Its licence is all rights reserved with
--  no modification clause, so nothing here is copied or adapted from it; the
--  behaviour is matched from the outside using the published API. The colours
--  and the shell still come from them. The composition is ours, which is the
--  real cost of standing alone: if they restyle, this can drift and nothing
--  will say so.
-------------------------------------------------------------------------------
local _, ns = ...

local CreateFrame = CreateFrame
local issecretvalue = issecretvalue or function()
    return false
end

-------------------------------------------------------------------------------
--  Theme
--
--  Shaped like the engine's own table so the pack body reads unchanged:
--  `local T = WSkin.Theme; if not T.bgR then WSkin.ResolveTheme() end`.
--  Repopulated on OnLooksChanged, which is what the getters are for.
-------------------------------------------------------------------------------
local Theme = {}
ns.Theme = Theme

function ns.ResolveTheme()
    local S = ns.S
    if not S then
        return Theme
    end

    local r, g, b, a = S.GetPanelColor()
    Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA = r or 0.06, g or 0.06, b or 0.06, a or 1

    -- No border getter on the facade. The engine's own edge is near-black and
    -- the packs already defaulted these to 0, so black it is.
    Theme.brdR, Theme.brdG, Theme.brdB = 0, 0, 0

    local path, flag = S.GetFont()
    Theme.fontPath, Theme.fontFlag = path, flag or ""

    Theme.accR, Theme.accG, Theme.accB = S.GetAccentColor()
    return Theme
end

-------------------------------------------------------------------------------
--  Border
--
--  The engine's AddBorder went through EUI's pixel-perfect border API and
--  no-opped silently when that was unavailable, which is why the rail tiles
--  reported border=false. Ours always draws.
-------------------------------------------------------------------------------
function ns.AddBorder(frame, r, g, b, a)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) or not frame.CreateTexture then
        return
    end
    local d = ns.FFD(frame)
    if d.localBorder then
        return d.localBorder
    end

    ns.ResolveTheme()
    r, g, b = r or Theme.brdR or 0, g or Theme.brdG or 0, b or Theme.brdB or 0
    a = a or 1

    local edges = {}
    local function Edge(p1, p2, horizontal)
        local t = frame:CreateTexture(nil, "BORDER", nil, 7)
        t:SetColorTexture(r, g, b, a)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if horizontal then
            t:SetHeight(1)
        else
            t:SetWidth(1)
        end
        edges[#edges + 1] = t
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)

    d.localBorder = edges
    return edges
end

-------------------------------------------------------------------------------
--  Foreign frames
--
--  These walkers run over named Blizzard windows. A third-party frame parented
--  into one is not ours to skin -- its own addon has an opinion, and two
--  skinners on one widget fight. Judged by name prefix against the addons the
--  client says are loaded, which costs one pass and is then cached.
-------------------------------------------------------------------------------
local prefixes

local function Prefixes()
    if prefixes then
        return prefixes
    end
    prefixes = {}
    local API = C_AddOns
    local count = (API and API.GetNumAddOns and API.GetNumAddOns()) or 0
    for i = 1, count do
        local name = API.GetAddOnInfo(i)
        if name and not name:find("^Blizzard_") and API.IsAddOnLoaded(i) then
            prefixes[#prefixes + 1] = name
        end
    end
    return prefixes
end

function ns.IsForeignFrame(frame)
    local name = frame and frame.GetName and frame:GetName()
    if not name or issecretvalue(name) then
        return false
    end
    for _, prefix in ipairs(Prefixes()) do
        if name:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Control walkers
--
--  CommonChrome in the engine is a close button, then ControlsIn + PagingIn +
--  ScrollBarsIn, then a title re-centre. Same shape here, one walk instead of
--  three so a window is descended once.
-------------------------------------------------------------------------------
local CONTROL_DEPTH = 4

-- Regions a plate must spare even on a button that does carry a label, since
-- the strip behind S.Button alphas every texture it is not told to keep.
local ICON_KEYS = { "Icon", "icon", "IconTexture", "Texture" }

-- Does this button read as a text button? An icon button has no label, and
-- flattening it destroys the only thing it was.
local function Labelled(btn)
    local fs = btn.GetFontString and btn:GetFontString()
    if not fs or not fs.GetText then
        return false
    end
    local text = fs:GetText()
    if text == nil or issecretvalue(text) then
        return false
    end
    return tostring(text):match("%S") ~= nil
end

local PAGER_KEYS = {
    PrevPageButton = "<",
    PagingLeftButton = "<",
    NextPageButton = ">",
    PagingRightButton = ">",
}

local function IsPager(frame, name)
    local parent = frame.GetParent and frame:GetParent()
    if parent then
        for key, glyph in pairs(PAGER_KEYS) do
            if parent[key] == frame then
                return glyph
            end
        end
    end
    if not name then
        return nil
    end
    if name:find("PrevPage") or name:find("PageLeft") then
        return "<"
    end
    if name:find("NextPage") or name:find("PageRight") then
        return ">"
    end
end

local function SkinControl(obj)
    local S = ns.S
    if not S then
        return
    end
    local name = obj.GetName and obj:GetName()
    if name and issecretvalue(name) then
        name = nil
    end

    if obj:IsObjectType("EditBox") then
        S.EditBox(obj)
        return true
    end
    if obj:IsObjectType("Slider") then
        S.ScrollBar(obj)
        return true
    end
    -- Before the Button test below: a CheckButton answers true to both.
    if obj:IsObjectType("CheckButton") then
        S.Checkbox(obj)
        return true
    end
    if obj:IsObjectType("DropdownButton") or (name and name:find("[Dd]rop[Dd]own")) then
        S.Dropdown(obj)
        return true
    end
    if (name and name:find("ScrollBar")) or obj.Track then
        S.ScrollBar(obj)
        return true
    end

    if obj:IsObjectType("Button") then
        local page = IsPager(obj, name)
        if page and S.PageButton then
            S.PageButton(obj, page)
            return true
        end
    end
    return false
end

-- buttons = also skin plain buttons on the way (the engine's ButtonsIn pass).
local function Walk(frame, depth, buttons, seen)
    if not frame or depth < 0 or seen[frame] then
        return
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return
    end
    seen[frame] = true

    if not frame.GetChildren then
        return
    end
    for i = 1, select("#", frame:GetChildren()) do
        local child = select(i, frame:GetChildren())
        if child and not (child.IsForbidden and child:IsForbidden()) and not ns.IsForeignFrame(child) then
            local handled = SkinControl(child)
            if not handled and buttons and child:IsObjectType("Button") and ns.S then
                local d = ns.FFD(child)
                -- A close button has its own treatment; a list row is a Button
                -- that is not a button; and a button made of ART is somebody's
                -- icon. Plating one alphas its texture regions, which is what
                -- emptied the role icon in "Choose your Roles" and left a black
                -- square with a tick on it. A visible label is the signal that
                -- a button is a button, so that is what is required.
                if not d.localNotAButton and Labelled(child) then
                    ns.S.Button(child, ICON_KEYS)
                end
            end
            Walk(child, depth - 1, buttons, seen)
        end
    end
end

function ns.ControlsIn(frame)
    Walk(frame, CONTROL_DEPTH, false, {})
end

function ns.ButtonsIn(frame)
    Walk(frame, CONTROL_DEPTH, true, {})
end

function ns.CommonChrome(frame, prefix)
    local S = ns.S
    if not (frame and S) then
        return
    end

    for _, button in ipairs({
        frame.CloseButton,
        frame.ClosePanelButton,
        frame.TitleContainer and frame.TitleContainer.CloseButton,
        prefix and _G[prefix .. "CloseButton"],
    }) do
        if button then
            S.CloseButton(button)
            ns.FFD(button).localNotAButton = true
        end
    end

    ns.ControlsIn(frame)

    -- The title is anchored off a portrait the shell removed, so it lands off
    -- centre. The shell's own top bar is the honest thing to centre on; the
    -- engine keeps it on the frame data, and falls back to the frame itself.
    local d = ns.FFD(frame)
    if d.localTitleCentered then
        return
    end
    local title = (frame.TitleContainer and frame.TitleContainer.TitleText)
        or frame.TitleText
        or (prefix and _G[prefix .. "TitleText"])
    local bar = d.topBar or frame
    if title and title.ClearAllPoints then
        d.localTitleCentered = true
        title:ClearAllPoints()
        title:SetPoint("CENTER", bar, "CENTER", 0, 0)
        if title.SetJustifyH then
            title:SetJustifyH("CENTER")
        end
    end
end

-------------------------------------------------------------------------------
--  Window registry
--
--  The engine applied these from its own PLAYER_LOGIN handler. Ours waits for
--  the facade instead, which is the same moment and cannot arrive before it.
--  A load-on-demand window applies when its addon loads, or right away if it
--  is already in.
-------------------------------------------------------------------------------
local entries, loginDone = {}, false

local function Ready(entry)
    if not entry.addons then
        return true
    end
    local API = C_AddOns
    for addon in pairs(entry.addons) do
        if not (API and API.IsAddOnLoaded and API.IsAddOnLoaded(addon)) then
            return false
        end
    end
    return true
end

local function Apply(entry)
    if entry.done or not ns.S or not Ready(entry) then
        return
    end
    -- /euilocal, read here rather than at the pack's file scope: our saved
    -- variables do not exist yet when that runs. Every pack is registered
    -- through here, so this is the one place the switch has to hold.
    if ns.PacksEnabled and not ns.PacksEnabled() then
        return
    end
    entry.done = true
    local ok, err = pcall(entry.apply)
    if not ok and err then
        geterrorhandler()(err)
    end
end

function ns.Register(entry)
    entries[#entries + 1] = entry
    if loginDone then
        Apply(entry)
    end
end

ns.OnSkin(function()
    ns.ResolveTheme()
    loginDone = true
    for _, entry in ipairs(entries) do
        Apply(entry)
    end
    if ns.S.OnLooksChanged then
        ns.S.OnLooksChanged(ns.ResolveTheme)
    end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, name)
    for _, entry in ipairs(entries) do
        if entry.addons and entry.addons[name] then
            Apply(entry)
        end
    end
end)
