# Damage/hit VFX

Two pieces of hit feedback, both addon-first per the CLAUDE.md "prefer existing
libraries" rule:

## Player damage flash (screen-space)

- `scripts/damage_flash.gdshader` — self-written (not vendored). The only
  addon match found (GitHub `HuLunTunTao/GodotScreenDamageFlashShader`,
  also on godotshaders.com) ships no LICENSE file, so its code couldn't be
  copied in; the square-vignette-fade-on-hit *technique* it documents isn't
  copyrightable, so the shader here is an independent implementation of the
  same idea (radial version, not square) rather than a derivative of theirs.
- Hooked up in `scenes/hud.tscn` (`DamageFlash` ColorRect, last child of the
  `HUD` CanvasLayer so it draws above everything else) and
  `scripts/hud.gd` (`_flash_damage()`), triggered from the existing
  `_on_player_health_changed()` callback by comparing against
  `_last_player_health` — fires only when health actually decreased, not on
  heal or the initial HUD refresh.

## Enemy blood particles (world-space)

- `addons/blood_effect/` — vendored as-is from
  `github.com/newlaptopfor-oss/Godot_Blood_Effect` (MIT, `LICENSE.txt`
  copied alongside). `node_3d.scn`/`node_3d.gd` is their own debug *demo*
  scene (free-fly camera + a keyboard-driven control panel built in
  `_ready()`), not a drop-in gameplay node, so it's never run as-is.
- `scripts/blood_burst.gd` (`BloodBurst.spawn(parent, world_position)`)
  instances `node_3d.scn`, calls `set_script(null)` *before* adding it to
  the tree (cancels their `_ready()`/demo-UI entirely since it never runs),
  then frees every child except `GPUParticles3D` and drives that node
  directly (`restart()` + `emitting = true`), then frees the whole instance
  after `particles.lifetime`.
  - **First version only freed `Camera3D`.** Turns out `node_3d.scn` also
    bakes in the vendor's entire test room (`ground` + 4 `walls`, ~18x8
    units) plus a duplicate `WorldEnvironment`/`DirectionalLight3D` — every
    hit was dropping that whole room next to the player (a visible "huge
    box") and doubling up environment/lighting, which is also what caused
    the frame-rate dip on hit. Fixed by freeing *everything* except
    `GPUParticles3D` instead of allowlisting one node to remove.
  - **Vendor's baseline `amount` is 1.** Their demo's whole control panel
    exists to let the tester crank a live multiplier (up to 150x) on that
    one particle; we don't use the panel, so a hit was emitting exactly one
    near-invisible particle. `spawn()` now sets `amount = _BURST_AMOUNT`
    (24) itself before restarting.
  - **`GPUParticles3D` sits ~4.7 units above (and behind) their scene
    root**, positioned to rain down into their elevated test room for the
    debug camera's view. That local offset survives reparenting onto our
    hit point, so blood was emitting well above the character ("have to
    look up to see it"). Fixed with `particles.position = Vector3.ZERO`
    right after reparenting, before `restart()`.
- Wired into `addons/fps_controller/Croissant.gd`'s `_try_hit()`: whenever a
  hit lands on something with a `HealthComponent` (i.e. a living target, not
  a destructible prop), `BloodBurst.spawn()` fires at
  `body.global_position + Vector3.UP * 0.9`.

## Gotcha: new addon assets need a forced import pass

Freshly copied-in assets (the two blood-decal PNGs) and a freshly added
`class_name` script (`BloodBurst`) aren't picked up by a plain
`--headless --script ...` run — that mode expects everything already
imported/class-cached by the editor. Fix used here:
`godot --headless --import` (no `-e`, exits on its own) once after adding
new binary assets or a new global class, before relying on them from a
debug script or in-game. Bounded to ~60s in the terminal since it doesn't
always exit cleanly on its own.
