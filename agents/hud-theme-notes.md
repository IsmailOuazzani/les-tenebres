# HUD theme (Kenney UI Pack)

The HUD was upgraded from plain default-theme Labels/ProgressBars (no
background, no outline, flat gray bars) to a themed look using an existing
asset pack rather than hand-rolled StyleBoxFlats, per the repo's
addon-first rule.

## Source

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

## How it's wired

- `scenes/hud.tscn`'s `Root` Control has `theme = main_theme.tres`, so it
  cascades to every HUD child.
- The stats block (`Crowd`/`Grabuge`/`Health`) is now wrapped in a
  `StatsPanel` (`PanelContainer`, variant `PanelContainerDefaultFlat`)
  instead of floating bare text over the 3D scene.
- `scripts/hud.gd` switches `theme_type_variation` at runtime instead of
  building custom `StyleBoxFlat`s:
  - Health bar: `ProgressBarSuccess` / `Warning` / `Danger` by HP ratio
    thresholds (>60% / 30-60% / <30%).
  - Grabuge bar: `ProgressBarPrimary` (calm) → `Warning` → `Danger` as it
    climbs past 35% / 70%.
  - Hotbar slot chips: `PanelContainerDefaultFlat` (inactive) /
    `PanelContainerPrimaryFlat` (active weapon), replacing the old
    hand-drawn border/background swap.

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
