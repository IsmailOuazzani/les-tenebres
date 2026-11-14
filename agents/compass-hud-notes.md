# Compass HUD (top-of-screen bar + red enemy markers)

## What

A compass bar at the top-center of the HUD showing the player's current
heading, with a red dot per tracked enemy (default: the `police` group)
showing their bearing relative to the player.

## Why this addon

Per CLAUDE.md's "prefer existing libraries" rule, searched for an existing
Godot addon rather than hand-rolling a compass widget. Found
[vi4hu/godot_compass](https://github.com/vi4hu/godot_compass) (MIT), which
adds `CompassBar`/`Compass2D`/`Compass3D` nodes. Only `CompassBar` is
vendored here (`addons/compass/`) -- `Compass2D`/`Compass3D` were dropped
since this project only needs the HUD bar, and keeping unused scripts around
just invites bitrot.

The addon is installed the same way as `addons/progress_bar_3d`: copied in
as plain scripts/scenes, **not** registered via `[editor_plugins]` in
`project.godot`. `addon.gd`/`plugin.cfg` are kept only so the `CompassBar`
node shows up in the editor's "Create Node" dialog if someone wants it; they
are never executed at runtime.

## What the addon does NOT do

`CompassBar` only draws scrolling bearing ticks via a shader
(`compassbar.gdshader`) driven by a `dir` shader param (lerped from the
assigned `parent` node's `rotation.y` each physics frame). It has **no**
concept of points of interest, markers, or enemies -- that's `godot_compass`
upstream behavior, not a bug introduced here.

## How enemy markers were added on top

`scripts/compass_markers.gd` is a plain `Control` overlaid on the
`CompassBar` (same rect, `Root/CompassAnchor/CompassMarkers` next to
`Root/CompassAnchor/CompassBar` in `scenes/hud.tscn`). Each frame it:

1. Reads the bar's current (already-lerped) `dir` value straight off its
   `ShaderMaterial` (`get_shader_parameter("dir")`) -- reusing the bar's own
   smoothed value instead of recomputing from the player's raw rotation, so
   the dots never desync/jitter against the bar's scroll.
2. For every `Node3D` in `enemy_group` (default `&"police"`), computes
   world bearing `atan2(-dx, -dz)` where `(dx, dz)` is `enemy.global_position
   - player.global_position` in the XZ plane. This convention is chosen so
   that `bearing == player.rotation.y` exactly when the enemy is dead ahead
   (see Godot's rotation-Y forward-vector derivation).
3. Maps bearing to screen-space X via `uv_x = frac(0.5 + (bearing - dir) /
   TAU)`, i.e. "whatever direction the player currently faces is always
   screen-center" -- independent of the bar texture's own `north` baked
   calibration constant. The bar's own ticks and these markers both move in
   lockstep as the player turns because they share the same `dir`-driven
   scroll, even though the two mappings aren't phase-matched against the
   bar's artwork. Good enough for "which side is the enemy on," not meant to
   align pixel-perfectly with the bar's N/E/S/W art.
4. Pools one `ColorRect` per enemy instance ID, created lazily and
   `queue_free()`'d when the enemy leaves the group/dies.

## Wiring gotcha: child `_ready()` runs before parent `_ready()`

`CompassBar.parent` is set programmatically from `scripts/hud.gd`'s
`_ready()` (via the new `player_path` export, same pattern as
`player_health_path`/`weapon_switcher_path`) rather than wired in the
`.tscn`, because `CompassBar`'s exported `parent: Node` property can't be
pointed at a sibling-of-HUD node (`../Player`) from inside `hud.tscn` in
isolation -- that cross-scene-boundary reference only resolves once
instanced under `test_map.tscn`, same reason `player_health_path` is an
exported `NodePath` resolved at runtime instead of a hardcoded `.tscn`
reference.

Because Godot calls `_ready()` bottom-up (children before ancestors),
`CompassBar._ready()` always runs *before* `HUD._ready()` sets its `parent`.
The addon's own `_ready()` sees `parent == null` at that point, logs a
warning, and permanently calls `set_physics_process(false)`. `hud.gd`
re-enables it explicitly right after assigning `parent` -- see the comment
in `hud.gd`. Don't remove that `set_physics_process(true)` call or the bar
silently stops updating (the one-time startup warning in the log is
expected and harmless; it's that "normal" early warning, not a sign
something's broken).

## Texture import gotcha

The vendored `compassbar.png` needs its `.import` cache regenerated once per
machine/checkout (`.godot/imported/*.ctex` doesn't ship in git). If you see
`Failed loading resource: res://addons/compass/resources/compassbar.png`,
run `godot --headless --path . --import` once, then re-run normally.

## Verifying scene-tree wiring (per CLAUDE.md's live-tree rule)

Verified via a temporary debug print in `hud.gd` under `task run-headless`
(removed before commit) that: `player_path` resolves to the real `Player`
node, `CompassBar.parent` and `CompassMarkers.player` get assigned, the
bar's `dir` shader param reads back without error, and a `ColorRect` marker
gets created once `PoliceSpawner` spawns its first cop (~10s in, per its
default `spawn_interval`). No errors in the log beyond the expected one-time
startup warning described above.
