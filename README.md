# SimpleEllesmereExtras

Extras for [EllesmereUI](https://www.curseforge.com/wow/addons/ellesmereui):
a chat link preview, emoji in chat, a Baganator skin, and a glow on any gear
slot missing an enchant or a gem.

Third-party. Not by Ellesmere, and nothing here modifies EllesmereUI. The
chat features work with or without EllesmereUI installed; the skin and the gear
alert need it.

## Features

- **Chat link preview.** Hover an item, spell, quest, achievement or currency
  link in any chat frame and its tooltip appears. Hidden again on leave, on
  scroll, and in combat. `/euihover` toggles it.
- **Emoji in chat.** A real Unicode emoji, which the game's fonts draw as an
  empty box, renders as an inline texture. So does a `:shortcode:` and a
  classic ASCII smiley. Every single-codepoint emoji Noto has art for is
  covered, with `:crossed_swords:` style names from Unicode plus about ninety
  short aliases such as `:smile:`. What you send is untouched, so players
  without the addon read `:smile:` rather than nothing. `/euiemoji` toggles,
  `/euiemoji size N` sets the size, `/euiemoji list <text>` searches.
- **Baganator skin.** Bags, bank, guild bank and the rest of Baganator take the
  EllesmereUI look through Baganator's public skin listener and EllesmereUI's
  public skin API. Leaves item slots alone when Masque owns them.
- **Missing enchant or gem alert.** A pulsing border on any character-sheet or
  inspect-sheet slot missing an enchant (red) or a gem (amber). Follows
  EllesmereUI's own rules for which slots take an enchant in 12.x.

## Commands

| Command | Effect |
| --- | --- |
| `/euihover` | Toggle the chat link preview |
| `/euiemoji` | Toggle emoji rendering |
| `/euiemoji size <8-32>` | Emoji size in chat |
| `/euiemoji list <text>` | Search the emoji names |

The Baganator skin follows EllesmereUI's own switch: Blizz UI Enhanced,
Blizzard Window Skins, Third-Party Addons.

## Installation

Download from [CurseForge](https://www.curseforge.com/projects/1695824), or
clone this repository into
`World of Warcraft/_retail_/Interface/AddOns/SimpleEllesmereExtras`. No build
step. EllesmereUI and Baganator are optional dependencies.

## Support

Bugs, questions and ideas all go to Discord: **https://discord.gg/zHT3bGEQ52**

`#support` for bugs and help, `#ideas` for feature requests, `#announcements`
for release notes. The
[GitHub issue tracker](https://github.com/JoesphG/SimpleEllesmereExtras/issues)
works too.

A bug report gets fixed faster with:

```
Addon version:      (Escape -> AddOns, or the CurseForge app)
EllesmereUI version:
Game version:       (bottom of the character select screen)
What I expected:
What happened:
Steps to reproduce:
Lua error (if any):
```

If there is a Lua error, paste the full text from BugSack rather than the
first line.

## Development

```
make check     # luacheck + stylua --check
make test      # every suite in tests/, plain Lua 5.1, no game
make format    # stylua .
make package   # BigWigsMods packager, local zip, uploads nothing
```

`tools/make-emoji.py` rebuilds `Media/emoji/` and the generated table in
`Emoji.lua` from Noto Color Emoji. Run it from the addon folder after touching
the alias table; it fails if an alias names a codepoint it emitted no art for.

## License

MIT, see [LICENSE](LICENSE). The emoji art is Noto Color Emoji under the SIL
Open Font License 1.1, see `Media/emoji/LICENSE.txt`.
