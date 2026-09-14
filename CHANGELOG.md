# Changelog

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
