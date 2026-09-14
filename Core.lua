-- SimpleEllesmereExtras
--
-- Shared plumbing for the feature files: the saved-variable table, and the
-- EllesmereUI skin facade, which EUI hands out once per session at
-- PLAYER_LOGIN through its public RegisterSkin API. Feature files that only
-- need the facade wait for it with ns.OnSkin; the chat features never need it
-- and run with or without EllesmereUI installed.

local ADDON_NAME, ns = ...

ns.issecret = issecretvalue or function()
    return false
end

-- Read at call time: the saved table replaces whatever exists at file scope
-- when SavedVariables load, so nothing may cache it before ADDON_LOADED.
function ns.DB()
    SimpleEllesmereExtrasDB = SimpleEllesmereExtrasDB or {}
    return SimpleEllesmereExtrasDB
end

-- EllesmereUI's per-frame data table, which the skin primitives use as their
-- idempotence guard. Underscore-prefixed but a global, and the only piece of
-- the engine reachable from outside it. Falls back to a table of our own so
-- the packs still load with EllesmereUI absent.
local ffd = setmetatable({}, { __mode = "k" })

function ns.FFD(frame)
    local get = EllesmereUI and EllesmereUI._GetFFD
    if get then
        return get(frame)
    end
    ffd[frame] = ffd[frame] or {}
    return ffd[frame]
end

local waiting = {}

function ns.OnSkin(fn)
    if ns.S then
        fn(ns.S)
    else
        waiting[#waiting + 1] = fn
    end
end

if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin(ADDON_NAME, function(S)
        ns.S = S
        local queued = waiting
        waiting = {}
        for _, fn in ipairs(queued) do
            fn(S)
        end
    end)
end

-- EUI dispatches skins from its own PLAYER_LOGIN handler, registered before
-- this one, so by the time this fires a facade that was coming has come.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    ns.loginDone = true
end)
