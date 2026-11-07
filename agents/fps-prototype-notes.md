# FPS Prototype: Grey-Box Test Level

Goal: get a playable first-person prototype running immediately, per `vision.md`'s
MVP scope ("first-person character... small environment"). This is throwaway
grey-box geometry, not the Paris art direction other research agents are working on.

## Controller used: godot-FirstPersonStarter (Whimfoome)

- Source: https://github.com/Whimfoome/godot-FirstPersonStarter
- License: MIT (copyright Dimitar "Whimfoome" Dimitrov, 2019-present). Copied
  verbatim to `addons/fps_controller/LICENSE-godot-FirstPersonStarter.txt`.
- Why this one: CharacterBody3D-based (current Godot API, not the deprecated
  KinematicBody), ~1000+ GitHub stars, actively maintained, explicitly built for
  Godot 4.x, and the code is small/modular/readable enough to extend later
  (e.g. for megaphone aiming, sprint-while-recruiting, etc.) rather than being a
  black-box plugin. Compared against a few other MIT options found via search
  (expressobits/character-controller, clarkgreenrepos/Godot-Character-Movement-Plugin,
  GarbajYT/godot_updated_fps_controller) — this one had the best size/clarity
  tradeoff for a quick prototype.
- Integration method: vendored manually. Cloned the repo to a scratch dir and
  copied just the `Player/` scripts+scenes into this repo under
  `addons/fps_controller/`, rewriting internal `res://Player/...` paths to
  `res://addons/fps_controller/...`. Did NOT use the in-editor AssetLib because
  this repo isn't published there under that exact name/version, and headless
  AssetLib installs aren't scriptable — manual vendoring was the more reliable
  path for a non-interactive agent.

### What got vendored (`addons/fps_controller/`)

- `MovementController.gd` / `.tscn` — `CharacterBody3D` with WASD movement,
  accel/decel, slope handling, jump, gravity from project physics settings.
- `Head.gd` / `.tscn` — mouse-look (`Node3D` + `Camera3D`), also supports
  joypad look axes.
- `Sprint.gd` — optional sprint-while-moving-forward with a small FOV kick.
  Wired to the `sprint` action (Shift).
- `Player.tscn` — composes the three above into the actual player scene.

### Input actions added to `project.godot`

Copied from the source project's input map so the controller works out of the
box: `move_forward/back/left/right`, `jump`, `sprint`, `change_mouse_input`
(Shift+F1 toggles mouse capture), `look_up/down/left/right` (joypad camera).
`ui_cancel` (Esc) was already a Godot default and is used to quit.

Also added `[layer_names]` `3d_physics/layer_1="Objects"`, `layer_2="Player"`
matching the source project, since `MovementController.tscn` sets
`collision_layer = 2` / `collision_mask = 3`.

## Test map (`scenes/test_map.tscn` + `test_map.gd`)

Pure grey-box, primitives only, no art:

- `CSGBox3D` ground plane (60x1x60), four `CSGBox3D` perimeter walls so you
  can't walk off into the void.
- Three blocky "buildings" (`BuildingA/B/C`) of varying size to walk around
  and break sightlines.
- A rotated `CSGBox3D` ramp up to a small raised platform, and a separate
  staircase made of four stacked `CSGBox3D` steps leading to another small
  platform — both there to sanity-check slope handling and stepping up terrain.
- `WorldEnvironment` with a default `ProceduralSkyMaterial` sky and ambient
  light so the grey boxes are actually visible, plus one shadow-casting
  `DirectionalLight3D`.
- `test_map.gd` just captures the mouse on `_ready()` and handles Esc-to-quit /
  click-to-recapture-mouse, same minimal behavior as the source template's
  example scene.
- Player is instanced from `addons/fps_controller/Player.tscn` and placed at
  `(0, 1, 10)`, facing the buildings/ramp/stairs cluster.

`project.godot` → `run/main_scene` now points at `res://scenes/test_map.tscn`,
so `task run` drops straight into the test level.

## How to play

```
task run
```

- WASD to move, mouse to look (mouse is auto-captured on start).
- Space to jump, Shift to sprint.
- Shift+F1 to release the mouse cursor, Esc to quit.

## Verification done

- `Godot --path . --headless --quit-after 1` loads the project and parses the
  main scene with zero errors/warnings (confirmed after first populating
  `.godot/global_script_class_cache.cfg` — see "Known issues" below).
- I have **no display in this environment**, so I could not visually confirm
  movement/jump/look feel, lighting, or collision correctness interactively.
  The user should run `task run` themselves to playtest feel; geometry sizes
  (wall height 5, ramp rise ~1.75 over 9 units, 4 steps of 0.5 rise each) were
  chosen to be reasonable for a human-scale CharacterBody3D (capsule shape,
  ~1.6-1.8 units tall by default) but are unverified by eye.

## Known issues / follow-ups

- **First run after cloning/pulling must populate the GDScript global class
  cache.** `Sprint.gd` references the `MovementController` class_name type
  hint; if `.godot/global_script_class_cache.cfg` is empty (fresh checkout,
  `.godot/` is gitignored), headless `task run-headless` will throw a parse
  error on `Sprint.gd`. Fix: open the project once in the editor (`task
  editor`) or run `Godot --path . --headless --editor --quit-after 3`, which
  forces a filesystem scan and populates the cache. After that it's fine. This
  is a one-time-per-checkout Godot quirk, not a bug in the controller.
- Grey-box geometry is a placeholder. Swap in the real Paris-inspired street
  assets once the map/prop research agents (see `agents/map-assets-research.md`,
  `agents/prop-character-assets-research.md`) land their findings — the test
  map's layout (ground + a few buildings + ramp + stairs) is meant to be
  replaced wholesale, not iterated on.
- No megaphone, no NPCs, no recruit/attack mechanics yet — this task was
  scoped to movement/look/jump feel only, per the MVP-first instruction.
- `Player.tscn`'s internal scenes (`MovementController.tscn`, `Head.tscn`)
  originally carried `uid://...` references copied from the source repo; I
  stripped the `uid=` attributes from the `ext_resource` lines in
  `Player.tscn` (keeping plain `path=`) to avoid "invalid UID" warnings, since
  those UIDs were registered against the old `Player/` location, not
  `addons/fps_controller/`. Pure path-based resolution works fine.
- Collision layers: player is on layer 2 ("Player"), everything else
  (ground/walls/buildings/ramp/stairs) defaults to layer 1 ("Objects"), masks
  are already compatible out of the box (`MovementController` collision_mask
  = 3 = layers 1+2).
