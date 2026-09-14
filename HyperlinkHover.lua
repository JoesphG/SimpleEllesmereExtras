-------------------------------------------------------------------------------
--  HyperlinkHover.lua
--
--  LOCAL PATCH -- not upstream. Tracked in AddOns/.git; see
--  .addon-patches/README.md. Own code, written against the Blizzard API; the
--  behaviour is modelled on ElvUI's chat hyperlink hover but none of its code
--  is used here.
--
--  Preview an item (or spell, quest, achievement...) by hovering its link in
--  chat, instead of having to click it and dismiss a window.
--
--  WHY THIS STILL EXISTS ALONGSIDE EUI 9.1.4
--
--  9.1.4 ships a hover of its own (EllesmereUIChat.lua, OnHyperlinkEnter), so
--  this file was retired on 2026-09-02 and brought straight back: the vendor's
--  is OFF by default -- CHAT_DEFAULTS carries hideTooltipOnHover = true and
--  nothing overrides it -- so retiring this removed the feature outright
--  instead of handing it over.
--
--  Four things this does that the vendor's does not. Re-check the list before
--  retiring it again:
--
--    * hides the tooltip on mouse wheel (see OnMouseWheel below).
--    * refuses in combat, the one path where reading a link can taint the
--      tooltip chain.
--    * pcalls SetHyperlink, so a malformed link cannot error out of the chat
--      frame's own script handler.
--    * covers mount, transmogappearance and transmogillusion too.
--
--  Both can run at once, if the vendor's is switched on in EUI's chat options:
--  the tooltip is just set twice, same owner and same link. Harmless.
--
--  WHY THIS HOOKS BLIZZARD'S CHAT FRAMES, NOT OURS
--
--  EllesmereUIChat renders its own text but deliberately leaves Blizzard's
--  message frames alive underneath with their hit-zones armed -- see the note
--  at the top of EllesmereUIChat_Engine.lua. Hyperlink interaction is served
--  from those frames, so OnHyperlinkEnter fires there and that is what we hook.
--  Hooking our own render layer would catch nothing.
--
--  Off with `/euihover`; the setting is account-wide and defaults on.
-------------------------------------------------------------------------------
local _, ns = ...

local GameTooltip = GameTooltip
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local strmatch = strmatch

local issecretvalue = issecretvalue or function()
    return false
end

-- Link types worth previewing. Deliberately a whitelist: chat also carries
-- player, channel, BNplayer and URL links, and handing those to SetHyperlink
-- produces either nothing or an error.
local PREVIEWABLE = {
    achievement = true,
    apower = true,
    currency = true,
    enchant = true,
    glyph = true,
    instancelock = true,
    item = true,
    keystone = true,
    mount = true,
    quest = true,
    spell = true,
    talent = true,
    transmogappearance = true,
    transmogillusion = true,
    unit = true,
}

local function Enabled()
    return ns.DB().hyperlinkHover ~= false
end

-- The frame whose link is currently previewed, so a stray leave from another
-- frame cannot close someone else's tooltip.
local showingFor

local function HidePreview()
    if showingFor then
        showingFor = nil
        GameTooltip:Hide()
    end
end

local function OnHyperlinkEnter(frame, link)
    if not Enabled() then
        return
    end

    -- Reading a link mid-combat is the one path that can taint the tooltip
    -- chain, and a preview is never worth that.
    if InCombatLockdown() then
        return
    end
    if GameTooltip:IsForbidden() then
        return
    end

    -- 12.x: a link carrying restricted data comes back secret, and a secret
    -- cannot be pattern-matched.
    if link == nil or issecretvalue(link) then
        return
    end

    local kind = strmatch(link, "^([^:]+)")
    if not (kind and PREVIEWABLE[kind]) then
        return
    end

    GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")

    -- A malformed or unsupported link must not error out of the chat frame's
    -- own script handler.
    if not pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
        GameTooltip:Hide()
        return
    end

    GameTooltip:Show()
    showingFor = frame
end

local function OnHyperlinkLeave()
    HidePreview()
end

-- Scrolling slides the text out from under the cursor without ever firing
-- OnHyperlinkLeave, which would strand the tooltip on screen.
local function OnMouseWheel(frame)
    if showingFor == frame then
        HidePreview()
    end
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------

local hooked = {}

local function Hook(frame)
    if not frame or hooked[frame] then
        return
    end
    hooked[frame] = true

    frame:HookScript("OnHyperlinkEnter", OnHyperlinkEnter)
    frame:HookScript("OnHyperlinkLeave", OnHyperlinkLeave)
    frame:HookScript("OnMouseWheel", OnMouseWheel)
end

local function HookAll()
    for _, name in ipairs(_G.CHAT_FRAMES or {}) do
        Hook(_G[name])
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    HookAll()

    -- Whisper and pet-battle windows are created on demand and are not in
    -- CHAT_FRAMES at login, so catch them as they open. Hook is idempotent.
    if _G.FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            HookAll()
        end)
    end
    if _G.FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", function()
            HookAll()
        end)
    end
end)

-------------------------------------------------------------------------------
--  Toggle
-------------------------------------------------------------------------------

_G.SLASH_EUIHOVER1 = "/euihover"
_G.SlashCmdList.EUIHOVER = function()
    ns.DB().hyperlinkHover = not Enabled()
    HidePreview()

    print(
        "|cff0cd29fSimpleEllesmereExtras|r: chat link preview "
            .. (Enabled() and "|cff00ff00on|r" or "|cffff5555off|r")
            .. "."
    )
end
