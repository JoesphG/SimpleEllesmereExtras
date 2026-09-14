<!--
Source for the CurseForge project description. There is no API for it, so it
is pasted by hand into the Description editor with the format set to Markdown.
-->

**Extras for EllesmereUI: chat link preview, emoji in chat, a Baganator skin, and a glow on gear missing an enchant or gem.**

Third-party. Not by Ellesmere, and nothing here modifies EllesmereUI. The chat
features work with or without EllesmereUI installed; the Baganator skin and the
gear alert need it, and go through its public skinning API.

## Features

- **Chat link preview.** Hover an item, spell, quest, achievement or currency
  link in chat and its tooltip appears. Hidden again on leave, on scroll, and
  in combat. `/euihover` toggles it.
- **Emoji in chat.** A real Unicode emoji, which the game's fonts draw as an
  empty box, renders as an inline texture. So does a `:shortcode:` and a
  classic ASCII smiley. Every single-codepoint emoji Noto has art for, with
  Unicode names plus about ninety short aliases such as `:smile:`. What you
  send is untouched, so players without the addon read `:smile:` rather than
  nothing.
- **Baganator skin.** Bags, bank and guild bank take the EllesmereUI look.
  Leaves item slots alone when Masque owns them. Follows EllesmereUI's own
  Third-Party Addons switch.
- **Missing enchant or gem alert.** A pulsing border on any character-sheet or
  inspect-sheet slot missing an enchant (red) or a gem (amber), following
  EllesmereUI's own rules for which slots take an enchant in 12.x.

## Commands

| Command | Effect |
| --- | --- |
| `/euihover` | Toggle the chat link preview |
| `/euiemoji` | Toggle emoji rendering |
| `/euiemoji size <8-32>` | Emoji size in chat |
| `/euiemoji list <text>` | Search the emoji names |

## Support

Bugs, questions and ideas all go to Discord: **[discord.gg/zHT3bGEQ52](https://discord.gg/zHT3bGEQ52)**

`#support` for bugs and help, `#ideas` for feature requests, `#announcements`
for release notes. The
[GitHub issue tracker](https://github.com/JoesphG/SimpleEllesmereExtras/issues)
works too. Include your EllesmereUI version in a bug report.

Source: [github.com/JoesphG/SimpleEllesmereExtras](https://github.com/JoesphG/SimpleEllesmereExtras) — MIT licensed. Emoji art from Noto Color Emoji (OFL 1.1).
