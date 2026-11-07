# NPC Wander — Foundation Notes

Scope of this pass: get civilian NPCs existing and wandering around the map on
their own. No recruitment, no crowd-follow, no click interaction — those come
later and are intentionally not implemented here.

## Character asset: placeholder, not Quaternius

`assets.md` / `agents/prop-character-assets-research.md` point at the
Quaternius "Ultimate Modular Men Pack" (CC0, glTF, skeleton + 24 animations)
as the top pick for crowd NPCs. I looked at pulling it in for this pass:

- The Quaternius site (`quaternius.com/packs/ultimatemodularcharacters.html`)
  has no direct download link in its HTML — downloads are gated behind a
  Google Drive / itch.io flow that isn't scriptable from a headless shell.
- The poly.pizza mirror (`poly.pizza/bundle/Ultimate-Modular-Men-Pack-...`) is
  a JS-rendered React app and requires a logged-in account to download
  models (`/login?from=...` redirect on the download action).

Neither is fetchable with a plain `curl` in a non-interactive environment,
and standing up a browser session just to click through a login/export flow
for a 24-animation modular rig felt like the wrong trade for this pass (per
the task brief: prioritize *something* wandering over a perfect pipeline).

**What's actually in the scene right now:** a primitive placeholder character
— a `CapsuleMesh` body + small `SphereMesh` head, built directly in
`scenes/npc.tscn`, no imported assets. Each NPC gets a random HSV-tinted
material on spawn so a group of them is visually distinguishable. There's a
small cosmetic bob (sine wave on the mesh's local Y) while moving so it
doesn't look like it's gliding — not real animation, just enough visual
feedback to read as "walking" vs "idle" from a distance.

**Next step for whoever picks up the real asset:** swap `scenes/npc.tscn`'s
`MeshRoot` contents for an instanced Quaternius (or Kenney) rigged character,
add an `AnimationPlayer`/`AnimationTree` reference, and in `scripts/npc.gd`
replace `_update_visuals()`'s bob hack with actual `play("Idle")` /
`play("Walk")` calls keyed off the same `state` checks already there (idle
when `State.IDLE`, walk when `State.WANDER` and moving). The state machine
and movement logic don't need to change — only the visual layer does.

## How wander works

`scripts/npc.gd` on a `CharacterBody3D` (`scenes/npc.tscn`):

- Simple state machine: `State { IDLE, WANDER, RECRUITED, FOLLOWING }`.
  Only `IDLE` and `WANDER` are driven right now. `RECRUITED`/`FOLLOWING` exist
  as no-op placeholders (velocity zeroed) so the future recruit system can
  flip `npc.state` without needing to touch this file's movement code.
- `IDLE`: stands still for a random `idle_time_min`..`idle_time_max` seconds,
  then transitions to `WANDER` with a freshly picked target point.
- `WANDER`: picks a random point within `wander_radius` of the NPC's own
  *spawn position* (`home_position`, captured in `_ready()`), walks straight
  toward it at `move_speed` via `move_and_slide()`, and rotates the mesh to
  face the direction of travel. On arrival (within `arrival_distance`) it
  goes back to `IDLE`.
- Gravity is applied manually (`ProjectSettings` default gravity) so NPCs
  settle onto uneven grey-box geometry and don't float if spawned slightly
  above the ground.

**Deliberately no `NavigationRegion3D`/`NavigationAgent3D`.** CLAUDE.md's rule
to prefer Godot's built-in navigation over custom pathfinding was considered,
but the test map's geometry is being actively reworked by another agent in
parallel — a baked navmesh tied to today's grey-box layout would need
re-baking (and might produce broken/invalid regions) the moment that
geometry changes shape. The wander-to-a-straight-line-target approach is
`CharacterBody3D` + `move_and_slide()` doing the collision response, so NPCs
still stop/slide against walls and each other like the player does — they
just won't path *around* obstacles intelligently. This is a reasonable
near-term tradeoff for "NPCs exist and move" and is isolated to the single
`_process_wander()` function in `scripts/npc.gd` — once the map geometry
settles down, swapping in a baked `NavigationRegion3D` + `NavigationAgent3D`
is a contained change there, not a rewrite.

## Spawning

`scripts/npc_spawner.gd` (`class_name NPCSpawner`) is attached directly to a
plain `Node3D` named `NPCSpawner`, added as a single new node in
`scenes/test_map.tscn` at the player spawn transform `(0, 1, 10)` (no changes
to the existing grey-box geometry nodes). On `_ready()` it spawns
`npc_count` (default 7) instances of `scenes/npc.tscn` scattered within
`spawn_radius` (default 10) of its own position, rejecting candidate points
closer than `min_spacing` to an already-placed NPC (up to 20 attempts per
NPC, falling back to an unchecked random point if it can't find a clear
spot — so it never hangs).

This is why it's robust to the map being reworked in parallel: the spawner
only depends on its own transform (set to the player spawn marker's
position) and a radius, not on any specific wall/building node existing.
Each spawned NPC also tracks its own spawn point as its wander home, so even
if NPCs end up near different grey-box obstacles after a map rework, they'll
still wander sensibly around wherever they landed.

## Hook points for next systems

- `npc.state` (enum on `scripts/npc.gd`) is the main hook. The recruit system
  can set `npc.state = NPC.State.RECRUITED` (or `FOLLOWING`) on click and the
  wander/idle logic stops driving movement immediately (both states are
  already handled as movement no-ops in `_physics_process`). Actual
  follow-the-player movement for `FOLLOWING` still needs to be written.
- NPCs are not currently in any dedicated group — the recruit/megaphone
  system will want to either add them to a Godot group (e.g. `"civilians"`)
  for proximity queries, or have the spawner register them with whatever
  crowd-manager singleton gets built.
- `scripts/npc.gd` has no click/area detection of its own by design (another
  agent owns that). Adding an `Area3D` + input handling for "recruit on
  click" is a localized addition to `scenes/npc.tscn`/`scripts/npc.gd` and
  shouldn't require touching the wander logic.
- Visual swap to a rigged character (see above) is independent of all of the
  above and can happen whenever someone has time to push through the
  Quaternius download flow (or picks a different pack from `assets.md`).

## Verification

Ran `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --quit-after 1`
— clean exit, no parse/script errors, after an initial
`--headless --editor --quit` pass to build the project's global script class
cache (needed once for `class_name NPCSpawner`/`MovementController` to
resolve; this is a one-time project state thing, not specific to this
change). No display available in this environment, so wander "feel" (timing,
speed, bob) is unverified visually — only verified structurally (scene loads,
no errors, spawner/NPC logic reads correctly).
