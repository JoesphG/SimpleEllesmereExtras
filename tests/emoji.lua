local FILE = "Emoji.lua"

-- The addon keeps its settings in its own SavedVariable and registers one
-- message filter per chat event. Nothing else of the client is touched.
local filters = {}
ChatFrame_AddMessageEventFilter = function(event, fn)
    filters[event] = fn
end

issecretvalue = function()
    return false
end

SlashCmdList = {}
local printed = {}
print = function(...)
    local t = {}
    for i = 1, select("#", ...) do
        t[#t + 1] = tostring((select(i, ...)))
    end
    printed[#printed + 1] = table.concat(t, " ")
end

local ns = {}
CreateFrame = CreateFrame
    or function()
        return {
            RegisterEvent = function() end,
            SetScript = function(s, k, f)
                s[k] = f
            end,
        }
    end
assert(loadfile("Core.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile(FILE))("SimpleEllesmereExtras", ns)

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
out("Emoji test\n")

check("a filter per chat event", filters.CHAT_MSG_SAY ~= nil and filters.CHAT_MSG_WHISPER ~= nil)
check("channel chat too", filters.CHAT_MSG_CHANNEL ~= nil)

-- Run a message through the filter the way the client does: a filter that
-- returns only false has asked for no change, so the original message stands.
local function say(msg)
    local blocked, text = filters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", msg, "Someone")
    if text == nil then
        text = msg
    end
    return text, blocked
end

local function tex(hex)
    return ("|TInterface\\AddOns\\SimpleEllesmereExtras\\Media\\emoji\\%s.png:14:14|t"):format(hex)
end
local HEART, SMILE, BROKEN = tex("2764"), tex("1f604"), tex("1f494")

-- The case this file exists for: a real Unicode emoji, which WoW's fonts draw
-- as an empty box.
local GRIN = tex("1f600")
local text, blocked = say("nice \240\159\152\128 pull")
check("never blocks the message", blocked == false)
check("a Unicode emoji becomes a texture", text == "nice " .. GRIN .. " pull", text)

-- U+2764 arrives with or without the VS16 presentation selector.
check("bare U+2764", say("\226\157\164") == HEART, say("\226\157\164"))
check("U+2764 plus VS16", say("\226\157\164\239\184\143") == HEART, say("\226\157\164\239\184\143"))

-- A joined sequence has no single bitmap to point at, so its parts convert
-- individually. Here the family emoji: man + ZWJ + woman + ZWJ + boy.
local FAMILY = "\240\159\145\168\226\128\141\240\159\145\169\226\128\141\240\159\145\166"
check(
    "a joined sequence renders as its parts",
    say(FAMILY) == tex("1f468") .. tex("1f469") .. tex("1f466"),
    say(FAMILY)
)
check("the joiners are dropped, not left to draw as boxes", say(FAMILY):find("\226\128\141", 1, true) == nil)

-- Same for a skin tone: we have no toned bitmap, so the modifier goes.
local TONED = "\240\159\145\141\240\159\143\189"
check("a skin-toned emoji loses only the modifier", say(TONED) == tex("1f44d"), say(TONED))

-- Characters in the set that people type as TEXT must stay text. (c) is in the
-- font, so a naive full-coverage map turns it into a picture.
check("a bare (c) stays text", say("Blizzard \194\169 2026") == "Blizzard \194\169 2026")
check("a bare arrow stays text", say("tank \226\134\146 boss") == "tank \226\134\146 boss")
check("a bare tick stays text", say("done \226\156\148") == "done \226\156\148")

-- ...unless the sender asked for emoji presentation with VS16.
check("(c) plus VS16 converts", say("\194\169\239\184\143") == tex("00a9"), say("\194\169\239\184\143"))

-- An aliased BMP character is one we decided is worth converting bare.
check("a BMP character we aliased converts bare", say("\226\154\161") == tex("26a1"), say("\226\154\161"))

-- Shortcodes and ASCII shorthands.
check("alias shortcode", say(":smile:") == SMILE, say(":smile:"))
check("unicode-name shortcode", say(":grinning_face:") == GRIN, say(":grinning_face:"))
check("a name we only reach the long way", say(":crossed_swords:") == tex("2694"), say(":crossed_swords:"))
check("unknown shortcode left alone", say(":nosuchthing:") == ":nosuchthing:")
check("ascii smiley", say("hey :)") == "hey " .. SMILE, say("hey :)"))
check("the nose is not left behind", say(":-)") == SMILE, say(":-)"))
check("<3", say("<3") == HEART, say("<3"))
check("</3", say("</3") == BROKEN, say("</3"))
check("</3 is not read as < then 3", say("a </3 b") == "a " .. BROKEN .. " b", say("a </3 b"))

-- Escape sequences are structural. Substituting inside them corrupts the
-- message: an emoji in a link's display text breaks the link.
local TONGUE = tex("1f61b")
local LINK = "|cffa335ee|Hitem:12345::::::::::::::|h[Sword :) of Doom]|h|r"
check("nothing is rewritten inside a hyperlink", say(LINK) == LINK, say(LINK))
check("text around a link still is", say(LINK .. " :)") == LINK .. " " .. SMILE)
check("a colour code is copied whole", say("|cff00ff00:)|r") == "|cff00ff00" .. SMILE .. "|r", say("|cff00ff00:)|r"))
check("an existing texture is not re-read", say("|TFoo:12|t :)") == "|TFoo:12|t " .. SMILE)

-- Item links carry Blizzard's NAMED colour form, |cnIQ4:, not just the hex
-- |cAARRGGBB. Slicing a fixed ten characters off that eats the |H marker with
-- it, and everything after is then treated as ordinary text -- which is how
-- the ":P" inside "::Player-3725-0C553989" turned into an emoji and killed a
-- real item link in chat.
local IQLINK = "|cnIQ4:|Hitem:240951:8022:240911:::::90:63::13:8:12245::"
    .. ":Player-3725-0C553989:::|h[Talisman Ring]|h|r"
check("a named-colour item link survives", say(IQLINK) == IQLINK, say(IQLINK))
check(
    "text after a named-colour link still converts",
    say(IQLINK .. " :)") == IQLINK .. " " .. SMILE,
    say(IQLINK .. " :)")
)
check("a named colour is copied whole", say("|cnIQ4::)|r") == "|cnIQ4:" .. SMILE .. "|r", say("|cnIQ4::)|r"))

-- |K...|k is a secret-value placeholder in 12.x. EllesmereUIChat strips them
-- outright, so whatever is inside is structure, not text to rewrite.
check("a secret-value placeholder is left alone", say("|Kq:P123|k") == "|Kq:P123|k", say("|Kq:P123|k"))
check("text after one still converts", say("|Kq123|k :)") == "|Kq123|k " .. SMILE, say("|Kq123|k :)"))

-- An ASCII smiley is two or three characters of punctuation, so it only counts
-- as one when it stands alone. Embedded in a longer run it is part of
-- something else, and converting it corrupts that thing.
check("a URL is not a smiley", say("https://example.com") == "https://example.com", say("https://example.com"))
check(
    "a GUID is not a smiley",
    say("::Player-3725-0C553989:::") == "::Player-3725-0C553989:::",
    say("::Player-3725-0C553989:::")
)
check("a smiley standing alone still converts", say("well :P") == "well " .. TONGUE, say("well :P"))
check("|| survives", say("a||b") == "a||b", say("a||b"))

-- list needs a search term now that there are ~1400 of them.
SlashCmdList.EUIEMOJI("list")
check("list refuses to dump everything", printed[#printed]:find("too many") ~= nil, printed[#printed])
SlashCmdList.EUIEMOJI("list crossed_swords")
check("list searches by name", printed[#printed]:find("crossed_swords", 1, true) ~= nil, printed[#printed])
SlashCmdList.EUIEMOJI("list zzznope")
check("list says when nothing matches", printed[#printed]:find("nothing matching") ~= nil, printed[#printed])

-- Size.
SlashCmdList.EUIEMOJI("size 20")
check("size takes", say(":smile:"):find(":20:20|t", 1, true) ~= nil, say(":smile:"))
SlashCmdList.EUIEMOJI("size 99")
check("out-of-range size refused", say(":smile:"):find(":20:20|t", 1, true) ~= nil)
SimpleEllesmereExtrasDB.emojiSize = nil

-- With no override the size follows the chat font, because a texture taller
-- than the line box overlaps the line above it. There was no chat frame until
-- now, which is why every check above ran at the fallback size.
DEFAULT_CHAT_FRAME = {
    GetFont = function()
        return "Fonts\\ARIALN.TTF", 18, ""
    end,
}
check("size follows the chat font", say(":smile:"):find(":18:18|t", 1, true) ~= nil, say(":smile:"))
DEFAULT_CHAT_FRAME.GetFont = function()
    return "Fonts\\ARIALN.TTF", 400, ""
end
check("an absurd chat font falls back", say(":smile:"):find(":14:14|t", 1, true) ~= nil, say(":smile:"))
DEFAULT_CHAT_FRAME = nil
check("no chat frame falls back", say(":smile:") == SMILE, say(":smile:"))

-- Toggle.
check("defaults on", SimpleEllesmereExtrasDB.emoji == nil)
SlashCmdList.EUIEMOJI("")
check("slash turns it off", SimpleEllesmereExtrasDB.emoji == false)
check("disabled means no substitution", say(":smile:") == ":smile:")
SlashCmdList.EUIEMOJI("")
check("slash turns it back on", say(":smile:") == SMILE)

out(fails == 0 and "\nall checks passed\n" or ("\n" .. fails .. " failed\n"))
os.exit(fails == 0 and 0 or 1)
