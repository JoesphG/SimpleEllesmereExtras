-- Frame stub for the options window, used by tests/panel.lua.
--
-- Taken from BonusRollGate, whose panel this one is modelled on.
--
-- Only the client methods the widgets actually call, each a no-op returning a
-- plausible number where one is needed. Anything else raises, so a typo in one
-- of our own method names fails the run instead of silently doing nothing --
-- which is the whole point, since none of this code can be exercised in game
-- from a test.
local S = {}

local NOOP = {
    "SetSize",
    "SetWidth",
    "SetHeight",
    "SetPoint",
    "SetAllPoints",
    "ClearAllPoints",
    "Show",
    "Hide",
    "SetShown",
    "SetScript",
    "HookScript",
    "EnableMouse",
    "EnableMouseWheel",
    "RegisterForDrag",
    "SetMovable",
    "SetClampedToScreen",
    "SetFrameStrata",
    "SetToplevel",
    "SetScrollChild",
    "SetVerticalScroll",
    "SetMinMaxValues",
    "SetValue",
    "SetValueStep",
    "SetObeyStepOnDrag",
    "SetOrientation",
    "SetThumbTexture",
    "Enable",
    "Disable",
    "StartMoving",
    "StopMovingOrSizing",
    "SetColorTexture",
    "SetVertexColor",
    "SetTexture",
    "SetText",
    "SetJustifyH",
    "SetJustifyV",
    "SetWordWrap",
    "SetSpacing",
    "SetTextColor",
    "SetTexCoord",
    "SetAlpha",
    "SetFrameLevel",
    "SetHitRectInsets",
    "RegisterForClicks",
    -- This addon boots from events, unlike BonusRollGate's panel.
    "RegisterEvent",
    "UnregisterEvent",
}

local RETURNS = {
    GetHeight = 400,
    GetWidth = 500,
    GetEffectiveScale = 1,
    GetValue = 10,
    GetStringHeight = 12,
    GetStringWidth = 60,
    GetVerticalScroll = 0,
    GetTop = 0,
    GetAlpha = 1,
}

local scripts = setmetatable({}, { __mode = "k" })

local function new(kind)
    local o = { kind = kind, shown = false }

    for _, name in ipairs(NOOP) do
        o[name] = function() end
    end
    for name, value in pairs(RETURNS) do
        o[name] = function()
            return value
        end
    end

    o.GetMinMaxValues = function()
        return 0, 100
    end
    o.IsShown = function(self)
        return self.shown
    end
    o.Show = function(self)
        self.shown = true
    end
    o.Hide = function(self)
        self.shown = false
    end
    o.SetShown = function(self, v)
        self.shown = v and true or false
    end
    o.SetScript = function(self, name, fn)
        scripts[self] = scripts[self] or {}
        scripts[self][name] = fn
    end
    o.HookScript = o.SetScript
    o.GetScript = function(self, name)
        return scripts[self] and scripts[self][name]
    end
    o.CreateTexture = function()
        return new("Texture")
    end
    o.CreateFontString = function()
        return new("FontString")
    end

    return setmetatable(o, {
        __index = function(_, key)
            error("stub: unknown method '" .. tostring(key) .. "' on " .. kind, 2)
        end,
    })
end

S.new = new

function S.install()
    _G.CreateFrame = function(kind)
        return new(kind or "Frame")
    end
    _G.UIParent = new("Frame")
    _G.GameTooltip = new("GameTooltip")
    _G.GameTooltip.IsForbidden = function()
        return false
    end
    _G.GameTooltip.SetOwner = function() end
    _G.GameTooltip.AddLine = function() end
    _G.GetCursorPosition = function()
        return 0, 0
    end
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which)
        S.lastPopup = which
    end
    _G.UISpecialFrames = {}
    _G.tinsert = table.insert
    _G.SetText = nil
    _G.GameTooltip.SetText = function() end
    _G.GameTooltip.Show = function() end
    _G.GameTooltip.Hide = function() end
    _G.HideUIPanel = function() end
    _G.SettingsPanel = nil
    _G.YES, _G.NO, _G.ACCEPT, _G.CANCEL = "Yes", "No", "Accept", "Cancel"
    _G.Settings = {
        RegisterCanvasLayoutCategory = function()
            return { ID = nil }
        end,
        RegisterAddOnCategory = function()
            S.categoryRegistered = true
        end,
    }
end

--- Fire a script handler the way the client would.
function S.fire(frame, name, ...)
    local fn = frame:GetScript(name)
    assert(fn, "no " .. name .. " handler")
    return fn(frame, ...)
end

return S
