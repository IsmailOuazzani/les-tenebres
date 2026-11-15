# Match HUD theme

`res://themes/hud_theme.tres` styles the in-match HUD, upgrade station,
Act Complete screen and Game Over screen using Godot's existing Theme
resource. Charcoal surfaces and warm white text carry persistent information.
Amber marks the selected hotbar slot, spendable Grabuge and primary buttons.
The health bar switches from mint to amber at 60% and red at 30%. Threat
warnings use red.

The Snapchat feed explicitly uses its previous inherited theme,
`res://themes/main_theme.tres`. Its scene and script still own the feed's
colors and notification styling.

The upgrade station groups player and crowd offers, keeps the balance and
countdown action outside the scrolling list, and updates the existing rows
when purchases change the wallet, level, price or affordability.

## Original theme source

`res://themes/main_theme.tres` + `res://themes/ui_pack/` were copied from
[Kingsmai/kenney-ui-pack-starter-kit](https://github.com/Kingsmai/kenney-ui-pack-starter-kit)
(MIT starter-kit code, not needed here since we only took the baked
`.tres` + its SVG textures). The textures themselves are
[Kenney's UI Pack](https://kenney.nl/assets/ui-pack), CC0 — no attribution
required.

We did **not** copy `themes/main_theme.gd` (the `ProgrammaticTheme`
generator script) or install the `ThemeGen` plugin it depends on — the
baked `main_theme.tres` is used as a static resource. If the theme ever
needs new variants/colors, either hand-edit the `.tres` or pull the
generator script + ThemeGen plugin back in.

## Gotcha hit while setting this up

After copying in 414 new SVGs, `task run-headless` failed with "Parse
Error: ext_resource referenced non-existent resource" for the whole
theme — the `.import` caches for the new files didn't exist yet, and
`task run`/`run-headless` (a plain game launch) never triggers an import
pass. Fixed by running the editor headlessly once to force import:

```
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --editor --quit
```

Worth remembering any time new binary/vector assets are added via
scripts/cp rather than through the editor's own import UI.
