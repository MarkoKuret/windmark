# Branding

Where the game's logo and icon live, and what they are made of. The behaviour is specified in
`docs/specs/menus.md` section 1.2.

## Logo

A wordmark only (no symbol, no badge): **WINDMARK** with the tagline bar **REGATTA SAILING SIMULATOR** under it.

- Drawn by the game, not an image: `game/scenes/menu/wordmark.tscn` and `wordmark.gd` (class `Wordmark`).
  The main menu shows it top-left; any other screen can instance the same scene.
- WINDMARK: Barlow Semi Condensed Black Italic (900), all caps, tracking +3 %; cream fill, navy outline 3 % of
  the font size; hard shadows navy at (+3.8 %, +3.8 %) and yellow at (+7.6 %, +7.6 %), each outlined in its own
  colour.
- Tagline: Barlow Semi Condensed ExtraBold Italic (800), tracking +30 %, 22 % of the WINDMARK size, navy on a
  yellow parallelogram slanted 14°, hard navy shadow 5.3 % of the WINDMARK size.
- Size on the main menu: WINDMARK 76 px at 100 % UI scale (lockup 368 x 97 px).

## Colours

| Name | Hex | Use |
| --- | --- | --- |
| Cream | `#F4F1E8` | WINDMARK fill (the menus' cloth) |
| Navy | `#1A2A3A` | outline, first shadow, tagline text and its shadow |
| Yellow | `#FFD23F` | second shadow, tagline bar (the HUD's `mark` yellow, the one accent) |

## Fonts

Barlow Semi Condensed (SIL Open Font License 1.1, `game/fonts/barlow/OFL.txt`; see `docs/THIRD_PARTY.md`):
`BarlowSemiCondensed-BlackItalic.ttf` and `BarlowSemiCondensed-ExtraBoldItalic.ttf` for the logo; Medium,
SemiBold and Bold for the rest of the menus and the HUD.

## App icon

The owner's art: `docs/branding/app_icon_1080.png` (outside `game/` so it does not ship; 1080 x 1080, a rounded square with a transparent outside) is
the master. `python3 tools/branding/make_icons.py` makes the rest from it, in `game/branding/`:

| File | Use |
| --- | --- |
| `app_icon_512.png` | project icon (`application/config/icon`), the window icon |
| `app_icon_256.png` | store pages, launchers, anything that wants a small PNG |
| `app_icon.icns` | macOS (16 to 1024 px): `application/config/macos_native_icon`, the dock icon |
| `app_icon.ico` | Windows (16, 32, 48, 64, 128, 256 px): `application/config/windows_native_icon` |

There are no export presets yet. When they are set up: the macOS preset's `application/icon` is
`res://branding/app_icon.icns`, the Windows preset's `application/icon` is `res://branding/app_icon.ico`, and the
`.icns` and `.ico` go in each preset's non-resource include filter (`branding/*.icns, branding/*.ico`) so the
running game can set them.

Boot splash: `game/branding/boot_splash.png` (1280 x 800, the logo on navy #1A2A3A), set in `project.godot`
(`application/boot_splash/*`).
