-------------------------------------------------------------------------------
--  Gate.lua
--
--  One switch for the window packs: `/euilocal off`, then `/reload`.
--
--  WHY IT NEEDS A RELOAD, AND WHY IT IS A GATE RATHER THAN AN UNDO
--
--  The packs are not features that can be turned off; they are skins. Applying
--  one strips Blizzard's textures, parents a new backdrop, re-fonts strings and
--  hooks ScrollBox updates, and none of that has an inverse -- the original
--  texture atlas and font object are gone by then. So the switch is read at
--  FILE SCOPE by Packs.lua, which returns immediately when it is off. Nothing
--  registers, nothing hooks, nothing is touched.
--
--  This file is deliberately NOT gated: it has to keep working while the packs
--  are off, or there would be no way to switch them back on.
--
--  WHY IT SURVIVED THE MOVE OUT OF ELLESMEREUI
--
--  Disabling the whole addon would now do the same job, but it would take the
--  chat and Baganator features with it. This switch covers the packs alone,
--  which is what makes it useful: it is the first thing to try when deciding
--  whether a window bug is EllesmereUI's or ours.
--
--  The setting moved to our own saved variables with the rest of the addon.
--  An existing `off` in EllesmereUIDB is honoured once and copied across, so
--  nobody's switch silently flips back on.
-------------------------------------------------------------------------------
local _, ns = ...

local function Say(...)
    print("|cff0cd29fEUI local|r:", ...)
end

function ns.PacksEnabled()
    local db = ns.DB()
    if db.packs == nil and EllesmereUIDB and EllesmereUIDB.localPatches == false then
        db.packs = false
    end
    return db.packs ~= false
end

-- Each registered pack maps to its own switch, so the font walk can go without
-- taking the rails and the chat bubbles with it. The registry keys the packs
-- already; two of them carry the owning addon after a colon.
ns.PACKS = {
    { key = "localfonts", db = "packFonts", label = "Fonts across windows" },
    { key = "localstock", db = "packStock", label = "Stock Blizzard windows" },
    { key = "localgroupfinder", db = "packGroupFinder", label = "Group Finder rail" },
    { key = "localpvp", db = "packPvp", label = "PVP rail" },
    { key = "localdialogs", db = "packDialogs", label = "Popup dialogs" },
    { key = "localchatbubbles", db = "packBubbles", label = "Chat bubbles" },
}

local byKey = {}
for _, pack in ipairs(ns.PACKS) do
    byKey[pack.key] = pack.db
end

-- Defaults to on, like every switch here: a key nobody has touched is nil.
function ns.PackEnabled(key)
    if not ns.PacksEnabled() then
        return false
    end
    if not key then
        return true
    end
    local field = byKey[key:match("^[^:]+")]
    return not field or ns.DB()[field] ~= false
end

-- The two features that shipped with no switch at all. Both default on.
function ns.GearAlertEnabled()
    return ns.DB().gearAlert ~= false
end

function ns.BaganatorSkinEnabled()
    return ns.DB().baganator ~= false
end

-- Read once the saved variables exist, so `status` can tell a pending change
-- from a live one. NOT at file scope: our own table is replaced when the game
-- loads it, so a read before ADDON_LOADED always answers with the default.
local loadedState
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, name)
    if name == "SimpleEllesmereExtras" then
        loadedState = ns.PacksEnabled()
        boot:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Own addons rather than packs: separate addons, each with its own switch, so
-- this gate does not reach into them.
local SEPARATE = {
    { "RaidMarkerBarLite", "/rmb" },
    { "EasyAutoAcceptRes", "/aar" },
    { "BonusRollGate", "/brg" },
}

_G.SLASH_EUILOCAL1 = "/euilocal"
_G.SlashCmdList.EUILOCAL = function(input)
    local arg = (input or ""):lower():match("^%s*(%S*)")

    if arg == "status" then
        local on = ns.PacksEnabled()
        Say(("window packs are %s"):format(on and "|cff00ff00on|r" or "|cffff5555off|r"))
        if loadedState ~= nil and on ~= loadedState then
            Say("  |cffffff00/reload to apply|r")
        end
        Say("  Packs.lua -- window skins, rails, popups, chat bubbles, font walk")
        Say("Not covered by this switch, and on their own switches:")
        Say("  this addon's chat and Baganator features (/euihover, /euiemoji)")
        for _, a in ipairs(SEPARATE) do
            local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(a[1])
            Say(("  %s (%s) %s"):format(a[1], a[2], loaded and "loaded" or "not loaded"))
        end
        return
    end

    local want
    if arg == "on" then
        want = true
    elseif arg == "off" then
        want = false
    elseif arg == "" then
        want = not ns.PacksEnabled()
    else
        Say("/euilocal on | off | status. Toggles with no argument.")
        return
    end

    ns.DB().packs = want or false
    Say(("window packs %s. |cffffff00/reload to apply.|r"):format(want and "on" or "off"))
end
