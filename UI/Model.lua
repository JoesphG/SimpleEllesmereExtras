-- The options panel described as data: pages, sections, rows.
--
-- No frames are created here, so this file runs under plain Lua and the test
-- suite asserts against it directly. Panel.lua turns it into widgets and knows
-- nothing about what the addon does. Same split as BonusRollGate's panel, for
-- the same reason: the interesting half stays testable without a client.
--
-- Rebuilt each time the window opens, because the rows read live state --
-- whether EllesmereUI is actually there, and whether a switch is waiting on a
-- reload.

local _, ns = ...

local Model = {}
ns.Model = Model

--------------------------------------------------------------------------------
-- Row constructors
--------------------------------------------------------------------------------

local function Check(label, desc, get, set, disabled)
    return { kind = "check", label = label, desc = desc, get = get, set = set, disabled = disabled }
end

local function Slider(label, desc, min, max, step, get, set)
    return { kind = "slider", label = label, desc = desc, min = min, max = max, step = step, get = get, set = set }
end

local function Text(get, color)
    return { kind = "text", get = get, color = color }
end

local function Buttons(specs)
    return { kind = "buttons", buttons = specs }
end

--------------------------------------------------------------------------------
-- Shared state the rows read
--------------------------------------------------------------------------------

-- Without EllesmereUI there is no facade, so every skinning feature is inert
-- however its switch is set. Saying so is kinder than showing live controls
-- that do nothing.
function ns.SkinsAvailable()
    return ns.S ~= nil
end

local function SkinNote()
    if ns.SkinsAvailable() then
        return nil
    end
    return "EllesmereUI is not loaded, so nothing here is applied."
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

local function GeneralPage()
    local db = ns.DB

    return {
        key = "general",
        title = "General",
        sections = {
            {
                title = "At a glance",
                rows = {
                    Text(function()
                        return ns.StatusText()
                    end),
                },
            },
            {
                title = "Chat",
                rows = {
                    Check(
                        "Link preview on hover",
                        "Hover an item or spell link in chat to see its tooltip.",
                        function()
                            return db().hyperlinkHover ~= false
                        end,
                        function(value)
                            db().hyperlinkHover = value
                        end
                    ),
                    Check(
                        "Emoji in chat",
                        "Render Unicode emoji, :shortcodes: and ASCII smileys as pictures.",
                        function()
                            return db().emoji ~= false
                        end,
                        function(value)
                            db().emoji = value
                        end
                    ),
                    Slider(
                        "Emoji size",
                        "Pixels. Left unset it follows your chat font, which is what keeps emoji off the line above.",
                        8,
                        32,
                        1,
                        function()
                            return db().emojiSize or ns.ChatFontSize()
                        end,
                        function(value)
                            db().emojiSize = value
                        end
                    ),
                },
            },
            {
                title = "Elsewhere",
                rows = {
                    Check(
                        "Missing enchant or gem alert",
                        "A pulsing border on any character or inspect slot missing an enchant or a gem.",
                        function()
                            return db().gearAlert ~= false
                        end,
                        function(value)
                            db().gearAlert = value
                        end,
                        function()
                            return not ns.SkinsAvailable() and SkinNote()
                        end
                    ),
                    Check("Baganator skin", "Give the bags, bank and guild bank the EllesmereUI look.", function()
                        return db().baganator ~= false
                    end, function(value)
                        db().baganator = value
                    end, function()
                        if not ns.SkinsAvailable() then
                            return SkinNote()
                        end
                        if not ns.BaganatorLoaded() then
                            return "Baganator is not loaded."
                        end
                    end),
                },
            },
        },
    }
end

local function WindowsPage()
    local db = ns.DB

    local rows = {
        Check("Window packs", "The master switch. Off, none of the packs below are applied.", function()
            return db().packs ~= false
        end, function(value)
            db().packs = value
        end, function()
            return not ns.SkinsAvailable() and SkinNote()
        end),
    }

    for _, pack in ipairs(ns.PACKS) do
        rows[#rows + 1] = Check(pack.label, pack.desc, function()
            return db()[pack.db] ~= false
        end, function(value)
            db()[pack.db] = value
        end, function()
            if not ns.SkinsAvailable() then
                return SkinNote()
            end
            if db().packs == false then
                return "The master switch above is off."
            end
        end)
    end

    return {
        key = "windows",
        title = "Windows",
        sections = {
            {
                -- Said once, at the top, rather than on all seven rows.
                title = "Skins need a reload",
                rows = {
                    Text(function()
                        return "A skin has no undo: applying one strips Blizzard's textures and re-fonts its"
                            .. " strings, and the originals are gone by then. So these switches are read at"
                            .. " login. Change one, then reload."
                    end, "dim"),
                    Buttons({
                        {
                            label = "Reload UI",
                            desc = "Apply the changes below.",
                            act = function()
                                ns.Reload()
                            end,
                        },
                    }),
                },
            },
            {
                title = "Packs",
                rows = rows,
            },
        },
    }
end

local function DiagnosticsPage()
    return {
        key = "diagnostics",
        title = "Diagnostics",
        sections = {
            {
                title = "For a bug report",
                rows = {
                    Text(function()
                        return "Both print into chat. Paste the output into the report."
                    end, "dim"),
                    Buttons({
                        {
                            label = "Scan for clipped text",
                            desc = "Lists text that is truncated or spilling out of its frame. /seediag",
                            act = function()
                                ns.RunSlash("seediag")
                            end,
                        },
                        {
                            label = "Dump this window",
                            desc = "Every string in a window with its font, size and box widths. /euidiag",
                            act = function()
                                ns.RunSlash("euidiag")
                            end,
                        },
                    }),
                },
            },
            {
                title = "Commands",
                rows = {
                    Text(function()
                        return "/euihover, /euiemoji, /euilocal, /euidiag, /seediag"
                    end, "dim"),
                },
            },
        },
    }
end

--- Every page, rebuilt from live state.
function Model.Pages()
    return { GeneralPage(), WindowsPage(), DiagnosticsPage() }
end
