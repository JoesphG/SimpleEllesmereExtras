-------------------------------------------------------------------------------
--  Baganator.lua
--
--  LOCAL PATCH -- not upstream. See .addon-patches/README.md.
--
--  Skins Baganator in the EUI house style. EUI's own Bags module replaces the
--  Blizzard bags, so it never touches Baganator; and Baganator's bundled ElvUI
--  skin calls into ElvUI's modules, which does nothing with ElvUI disabled.
--
--  Nothing here patches Baganator. It goes through Baganator's PUBLIC listener
--  (Baganator.API.Skins.RegisterListener) -- the same hook its own Masque
--  integration uses. Registration happens at file load, before PLAYER_LOGIN,
--  because Baganator builds its frames at PLAYER_LOGIN and a later listener
--  would miss every one of them.
--
--  Baganator runs its own selected skin first and the listeners after, so this
--  gets the last word whichever base skin is chosen. "Blizzard" is cleanest.
--
--  WHAT A SLOT'S REGIONS ARE FOR -- read before touching ICON_KEYS
--
--  An item slot's icon and its two overlays are texture REGIONS of the button,
--  so a blanket strip alphas them out along with the art. Each one is load
--  bearing:
--
--    icon               the item. Losing it left bags bordered, counted and
--                       apparently empty.
--    searchOverlay      Blizzard ItemButtonTemplate region. Baganator dims a
--                       non-matching slot with searchOverlay:SetShown(true),
--                       so alpha-ing it means SEARCH STOPS HIGHLIGHTING --
--                       every slot stays bright and nothing appears to filter.
--    ItemContextOverlay dims slots that are not valid targets while a socket
--                       or scrap window is open.
--
--  Baganator's own ElvUI skin carries the same warning about the search
--  overlay, so this is a known way for a skin to break its search.
--
--  ITEM SLOTS AND MASQUE. Masque exists for square item buttons and Baganator
--  already registers its slots with a Masque group. When Masque is applying,
--  the slots are left alone and only the window around them is skinned -- two
--  button skinners on one slot fight over the border.
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = EllesmereUI
if not (EUI and EUI._GetFFD and EUI.RegisterSkin) then
    return
end

-- EUI's public skin facade arrives at PLAYER_LOGIN (Core.lua). Primitives
-- resolve against it at call time; anything the facade lacks is nil.
local WSkin = setmetatable({}, {
    __index = function(_, k)
        return ns.S and ns.S[k]
    end,
})

local hooksecurefunc = hooksecurefunc

ns.issecret = ns.issecret or issecretvalue or function()
    return false
end

-- Regions on an item slot that must survive the strip. Order matters only in
-- that the icon lookup below reuses the first three.
local ICON_KEYS = { "icon", "Icon", "IconTexture" }
local KEEP_KEYS = { "icon", "Icon", "IconTexture", "searchOverlay", "ItemContextOverlay" }

local function MasqueOwnsSlots()
    local API = Baganator and Baganator.API
    return (API and API.IsMasqueApplying and API.IsMasqueApplying()) or false
end

local function TagSet(tags)
    local set = {}
    for _, tag in ipairs(tags or {}) do
        set[tag] = true
    end
    return set
end

local function SlotIcon(button)
    for _, key in ipairs(ICON_KEYS) do
        if button[key] then
            return button[key]
        end
    end
end

-------------------------------------------------------------------------------
--  Quality borders
--
--  EUI's QualityBorder can manage itself, repainting whenever
--  SetItemButtonQuality touches the button -- but Baganator does not use that
--  for bag slots. It drives the ring directly:
--
--      IconBorder:SetVertexColor(r, g, b, 1) ; IconBorder:Show()   -- rarity
--      IconBorder:SetVertexColor(1, 1, 1, 1) ; IconBorder:Hide()   -- common
--
--  Two consequences. The managed repaint never fires, so a colour read once at
--  skin time is frozen for the life of the slot; and a common item leaves the
--  ring set to WHITE before hiding it, so that frozen colour is white. That is
--  what put a white border on every slot.
--
--  So follow the ring's own methods instead. IsShown carries Baganator's
--  intent -- hidden means "no rarity" -- and hidden paints BLACK, matching the
--  1px black edge every other icon in the suite carries.
-------------------------------------------------------------------------------
local function PaintQuality(button, icon)
    local border = button.IconBorder
    local r, g, b = 0, 0, 0

    if border and border:IsShown() then
        local vr, vg, vb = border:GetVertexColor()
        if vr and not ns.issecret(vr) then
            r, g, b = vr, vg, vb
        end
    end

    if WSkin.QualityBorder then
        WSkin.QualityBorder(button, icon, r, g, b)
    end
end

local function FollowRing(button, icon)
    local border = button.IconBorder
    local d = EUI._GetFFD(button)
    if not border or d.localRingHook then
        return
    end
    d.localRingHook = true

    local function Repaint()
        PaintQuality(button, icon)
    end

    -- SetVertexColor covers Baganator's direct path AND SetItemButtonQuality,
    -- which colours the same ring underneath.
    for _, method in ipairs({ "SetVertexColor", "Show", "Hide" }) do
        if border[method] then
            pcall(hooksecurefunc, border, method, Repaint)
        end
    end
end

-------------------------------------------------------------------------------
--  Item slots
-------------------------------------------------------------------------------
local function SkinItemButton(button)
    if MasqueOwnsSlots() then
        return
    end

    local d = EUI._GetFFD(button)
    if d.localSlot then
        return
    end
    d.localSlot = true

    WSkin.Button(button, KEEP_KEYS)

    local icon = SlotIcon(button)
    if icon then
        WSkin.SquareIcon(icon, button)
    end

    -- The search dim sits over the slot, so it has to draw above our fill and
    -- border. Re-assert it rather than trust whatever layer it inherited.
    local search = button.searchOverlay
    if search then
        search:SetDrawLayer("OVERLAY", 7)
        search:SetColorTexture(0, 0, 0, 0.8)
        if search.SetAllPoints then
            search:SetAllPoints(button)
        end
    end

    -- Item quality on the slot border, which is the detail that most reads as
    -- skinned. Blizzard's ring goes away in favour of it.
    --
    -- The ring is alpha'd, never Hidden: Baganator drives it with Show/Hide and
    -- we read that state back, so hiding it ourselves would destroy the signal.
    local border = button.IconBorder
    if border and icon and WSkin.QualityBorder then
        border:SetAlpha(0)
        WSkin.QualityBorder(button, icon, 0, 0, 0)
        PaintQuality(button, icon)
        FollowRing(button, icon)
    end

    -- Baganator recycles slots and re-sets the texture, which resets the crop.
    if button.SetItemButtonTexture and not d.localSlotHook then
        d.localSlotHook = true
        hooksecurefunc(button, "SetItemButtonTexture", function()
            local i = SlotIcon(button)
            if i then
                pcall(i.SetTexCoord, i, 0.08, 0.92, 0.08, 0.92)
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Text: colour only, never the font
--
--  Baganator sizes a category label from GetUnboundedStringWidth at layout
--  time and clamps it to the width of the icon grid beneath it, with word wrap
--  off (CategoryViews/Packing.lua, CategoryViews/Components.lua). A face with
--  wider glyphs at the same point size therefore buys nothing but ellipsis.
--  Corner widgets are worse: corner-anchored on a slot with no width at all,
--  so a wider face spills into the neighbouring slot with nothing to clip it.
--
--  WSkin.Font keeps the point size and swaps only the face, so the width delta
--  is whatever the user's font file happens to be -- unpredictable in both
--  direction and size, which is why this reproduced inconsistently.
--
--  Baganator's own skins agree: Blizzard and Dark leave text alone, NDui
--  recolours it, ElvUI puts its one font change behind an opt-in, and GW2 is
--  alone in swapping the face -- sizing it DOWN when it does.
--
--  RESOLVE THE FONTSTRING FIRST. The region handed over for a label or a
--  header is the Button (labelsPool is a CreateFramePool("Button", ...)), and
--  a Button is not a FontInstance. The old code passed it straight to
--  WSkin.Font, which bails on anything without GetFont, so both of those
--  skinners were doing nothing at all.
-------------------------------------------------------------------------------
local function FontStringOf(region)
    if not region then
        return nil
    end
    if region.IsObjectType and region:IsObjectType("FontString") then
        return region
    end
    if region.GetFontString then
        return region:GetFontString()
    end
end

local function ColorText(region)
    local fs = FontStringOf(region)
    if not fs or not WSkin.White then
        return
    end
    local accent = WSkin.GetAccentColor
    if accent then
        WSkin.White(fs, accent())
    else
        WSkin.White(fs)
    end
end

-------------------------------------------------------------------------------
--  Per-region skinners, keyed by Baganator's own regionType
-------------------------------------------------------------------------------
local skinners = {
    ItemButton = SkinItemButton,

    ButtonFrame = function(frame)
        WSkin.Shell(frame)
    end,

    Dialog = function(frame)
        WSkin.Panel(frame)
        if frame.CloseButton then
            WSkin.CloseButton(frame.CloseButton)
        end
    end,

    InsetFrame = function(frame)
        WSkin.Inset(frame)
    end,

    Button = function(frame)
        WSkin.Button(frame)
    end,

    IconButton = function(frame)
        WSkin.Button(frame, ICON_KEYS)
        local icon = SlotIcon(frame)
        if icon then
            WSkin.SquareIcon(icon, frame)
        end
    end,

    SearchBox = function(frame)
        WSkin.EditBox(frame)
    end,

    EditBox = function(frame)
        WSkin.EditBox(frame)
    end,

    CheckBox = function(frame)
        WSkin.Checkbox(frame)
    end,

    Dropdown = function(frame)
        WSkin.Dropdown(frame)
    end,

    TabButton = function(frame)
        WSkin.Tab(frame)
    end,

    TopTabButton = function(frame)
        WSkin.Tab(frame)
    end,

    -- The character / bank tabs down the side: an icon tile, not a text tab.
    SideTabButton = function(frame)
        if frame.Background then
            frame.Background:SetAlpha(0)
        end
        WSkin.Panel(frame, { noBg = true })
        if frame.Icon then
            WSkin.SquareIcon(frame.Icon, frame)
        end
    end,

    TrimScrollBar = function(frame)
        WSkin.ScrollBar(frame)
    end,

    ScrollButton = function(frame, tags)
        if WSkin.PageButton then
            WSkin.PageButton(frame, tags.left and "<" or ">")
        end
    end,

    Slider = function(frame)
        WSkin.Panel(frame, { noBg = true })
    end,

    CategorySectionHeader = function(region)
        ColorText(region)
    end,

    CategoryLabel = function(region)
        ColorText(region)
    end,

    -- Deliberately nothing. Corner widgets are plugin-driven -- item level,
    -- stack counts, keystone level -- and several colour-code their own text,
    -- so a recolour would destroy the plugin's signal and a re-font overflows
    -- the slot. Baganator's Dark skin stubs this out for the same reason.
    CornerWidget = function() end,

    -- The rule between category sections: a faint hairline instead of
    -- Blizzard's tooltip divider art. The facade exposes no border colour.
    Divider = function(texture)
        texture:SetColorTexture(1, 1, 1, 0.12)
    end,
}

-------------------------------------------------------------------------------
--  Hook up
-------------------------------------------------------------------------------
-- Baganator builds its frames at PLAYER_LOGIN and the facade arrives at
-- PLAYER_LOGIN too, so regions that come first wait for it. Once login has
-- passed with no facade, skinning is off for this addon and nothing is kept.
local pending = {}

local function OnRegion(details)
    local skinner = skinners[details.regionType]
    if not skinner then
        return
    end
    if not ns.S then
        if not ns.loginDone then
            pending[#pending + 1] = details
        end
        return
    end

    -- Baganator pcalls its listeners, but be explicit: one odd region must not
    -- cost the rest of the bag.
    local ok, err = pcall(skinner, details.region, TagSet(details.tags))
    if not ok and err then
        geterrorhandler()(err)
    end
end

ns.OnSkin(function()
    local queued = pending
    pending = {}
    for _, details in ipairs(queued) do
        OnRegion(details)
    end
end)

local API = Baganator and Baganator.API and Baganator.API.Skins
if API and API.RegisterListener then
    API.RegisterListener(OnRegion)
end
