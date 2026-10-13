# Changelog

## 1.2.3

- No longer throws "calling 'IsForbidden' on bad self" when a window's text is released before it is re-fonted.

## 1.2.2

- The gear alert flags an off-hand weapon with no enchant again; 12.1.5 removed the call it used.
- Interface 120105, for patch 12.1.5.

## 1.2.1

- The options window no longer lays the reload button on top of the text above
  it, and the world no longer shows through the window.
- A row no longer stays highlighted after the cursor has left it.
- The Diagnostics page lists what each command does, not just its name.

## 1.2.0

- An options window. `/see` opens it, and Blizzard's AddOns list has a button.
- The window packs split into six switches, so the font walk can go without
  taking the rails and the chat bubbles with it.
- The gear alert and the Baganator skin have switches of their own. The gear
  alert applies without a reload; the skins do not, and the window says so.

## 1.1.0

The window packs moved here from EllesmereUI's own .toc, so nothing in the
EllesmereUI folder is edited any more.

- Skins the stock Blizzard windows EllesmereUI has no pack for, flattens the
  Group Finder and PVP category rails, skins three popup dialogs and the chat
  bubbles, and walks fonts over 31 windows.
- Button labels no longer lose their last character: "Start a Grou" and
  "Sign U" are whole again.
- `/euilocal` switches the window packs off; `/euidiag` dumps a window's text.

## 1.0.1

- Baganator category labels and section headers are recoloured, not re-fonted,
  so long names no longer truncate.
- Baganator slot corner widgets are left alone, so counts no longer spill into
  the neighbouring slot.
- Baganator edit box text is inset clear of the border.
- Chat emoji are sized from the chat font, so they no longer overlap the line
  above.
- Added `/seediag`, which reports text that is truncated or spilling its frame.

## 1.0.0

First public release, for Midnight 12.1 (Interface 120100). These began as
local patches loaded from EllesmereUI's own toc; they now ride EllesmereUI's
public skinning API and load as an addon of their own.

- Hover an item, spell, quest or achievement link in chat to preview it.
- Emoji in chat: real Unicode emoji, `:shortcodes:` and ASCII smileys render as
  inline textures.
- Baganator skinned to match EllesmereUI.
- Character and inspect sheets glow on any slot missing an enchant or a gem.
