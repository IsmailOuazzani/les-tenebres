# More Destructibles: new prop/vehicle/glass scenes (not placed in the map)

Follow-up to `agents/damage-vfx-notes.md` and the existing
`scripts/destructible_prop.gd` / `scenes/destructible_prop.tscn` (dumpster)
PoC. Built several more destructible scenes per the user's request, **none
instanced into `scenes/test_map.tscn`** — these are ready-to-place assets
only, placement is a separate follow-up task.

## Correction to prior research

`agents/prop-character-assets-research.md` claimed Kenney's Car Kit ships a
"confirmed bus model" — **this is wrong**. The actual pack
(https://kenney.nl/assets/car-kit) has no `bus.glb`; the closest large
vehicle is `garbage-truck.glb`, used below as the stand-in for the vision
doc's "bus" Send Mob target.

## What got added

### Generic street-prop destructibles (reuse existing `destructible_prop.gd`)

Same contract as the dumpster PoC (StaticBody3D in the `"destructible"`
group, `ProgressBar3D` health bar, yellow outline on `set_targeted()`,
scale-to-zero-then-`queue_free` on death) applied to four more Kenney City
Kit (Roads) models, already present in `assets/kenney_city_kit_roads/`:

- `scenes/destructible_barricade.tscn` — `construction-barrier.glb`, 80 HP
- `scenes/destructible_cone.tscn` — `construction-cone.glb`, 30 HP (flimsiest)
- `scenes/destructible_traffic_light.tscn` — `traffic-light.glb`, 150 HP
- `scenes/destructible_road_sign.tscn` — `road-sign-stop.glb`, 100 HP

All instanced at the project's established Kenney 4x scale convention
(`agents/map-dressing-notes.md`). Collision/outline box sizes were measured
via a one-off headless AABB-dump script (not checked in, same "deleted after
use" pattern as `generate_map.gd`).

### Vehicle destructible: `scripts/destructible_vehicle.gd` + `scenes/destructible_bus.tscn`

New script, `extends DestructibleProp`, same group/signal contract, but
`_die()` detaches a configurable list of debris `RigidBody3D` children
(reparents them out from under the dying StaticBody3D, unfreezes them,
applies an outward+upward impulse, despawns them after a few seconds)
instead of just scaling the whole prop to zero.

`destructible_bus.tscn` wraps Kenney Car Kit's `garbage-truck.glb` (newly
downloaded to `assets/kenney_car_kit/`, GLB format + `Textures/colormap.png`
+ `LICENSE.txt`, same CC0 Kenney license as every other kit in this repo)
with four `wheel-truck.glb` wheels, a `debris-bumper.glb`, and a
`debris-door.glb` as the detachable debris set — the truck's own mesh has no
separate wheel/door nodes (single merged mesh, same as every other Kenney
vehicle GLB), so these are the kit's own standalone debris/wheel models
layered on top at the chassis's wheel-well/bumper/door positions. 300 HP
(tankiest of the new props, matches "biggest target" framing).

### Glass destructible: `scripts/destructible_glass.gd` + `scenes/destructible_shop_window.tscn`

Vendored `addons/breakable_glass_custom/` from
github.com/Stand43/godot_breakable_glass_custom (MIT, `LICENSE.txt` copied
alongside) — a `CSGPolygon3D`-extending script that procedurally fractures a
drawn polygon into physics shards radiating from an impact point, with its
own despawn timer. Chosen over `github.com/Jummit/godot-destruction-plugin`
(the other asset-library candidate from the brainstorm) because that one
requires pre-fracturing the mesh in Blender's Cell Fracture addon first, and
**this environment has no Blender install** (per the Paris building pack
texture notes) — not viable here.

`destructible_glass.gd` (`extends DestructibleProp`) overrides `_die()` to
call the pane's `break_window(global_position)` instead of scale-tweening.
One subtlety: the addon's `spawn_shards()` reparents shard RigidBody3Ds onto
the glass pane's *current parent* (this wrapper node), so unlike every other
`_die()` override here, this wrapper must **stay alive** until the shards'
own despawn timer fires, not `queue_free()` itself immediately — otherwise
the shards get freed with it. It also zeroes the pane's own
`unbroken_collision_layer`/`_mask` so raycasts/melee resolve to the
wrapper's own `CollisionShape3D` (in the `"destructible"` group) rather than
the CSGPolygon3D's own auto-created collision body, which is not in any
group. `destructible_shop_window.tscn` is a **standalone prop** (a freestanding
window pane), not a retrofit of the Paris building FBXs — swapping real
building glass was out of scope for this pass. 20 HP (shatters fast).

## Verification done

Headless boot (`godot --headless --path . <throwaway debug scene>
--quit-after N`, not a bare `--script` run — `destructible_prop.gd`'s
`_die()` calls the `GameState` autoload, which a pure `--script` SceneTree
invocation can't resolve, per CLAUDE.md's "verify the actual runtime tree"
rule) instantiated all six new scenes, confirmed each is in the
`"destructible"` group, drove `take_damage()` to zero, and confirmed the
`destroyed` signal fires with zero new errors (debris reparenting and glass
shard spawning both run through `call_deferred`/physics callbacks without
throwing). Debug script and throwaway scene deleted after use, not checked
in.

**Not visually confirmed** — no display access in this session. Whether the
bus's bolted-on wheel/bumper/door debris line up convincingly with the
garbage truck's own baked geometry, and whether the glass shard explosion
looks right, need an eyeball pass via `task run`.

## Not done / still open

- ~~Nothing placed in `scenes/test_map.tscn`~~ — **done**, see
  `agents/map-generation-notes.md`. All of these are now placed in
  `scenes/map_geometry.tscn` by `tools/generate_map_geometry.py`. Note they are
  instanced at **scale 1**, since each scene bakes its own 4x model scale.
  (The "`--script` can't resolve the `GameState` autoload" warning in the
  Verification section above turned out to be the exact trap that later
  destroyed `test_map.tscn` — that incident is written up in the new notes.)
- Café tables/chairs/kiosks (Kenney City Kit Commercial) and a statue
  destructible were in the original brainstorm but not built this pass —
  only the agreed shortlist (street props, bus, glass) was done.
- The one untextured normal-map surface on Paris Building A
  (`agents/map-dressing-notes.md`) is unrelated and untouched.

## Update: Tier 1 batch (9 more props, still not placed in the map)

Follow-up brainstorm surfaced a much bigger list of destructible candidates,
split into "Tier 1" (zero new downloads -- models already sitting unused in
`assets/`) and "Tier 2" (would need a new pack, e.g. Kenney Furniture Kit, or
a statue). User asked for Tier 1 only. Nine more scenes, same two patterns
as before (`destructible_prop.gd` for static props, `destructible_vehicle.gd`
for vehicles with debris) -- no new scripts needed this round:

**Static props** (Kenney 4x scale convention, from `kenney_city_kit_roads/`
and `kenney_city_kit_commercial/`, all previously-unused models):
- `scenes/destructible_fence.tscn` -- `construction-fence.glb`, 50 HP
- `scenes/destructible_electricity_pole.tscn` -- `electricity-pole.glb`
  (pole + crossbar, hence the wide bounding box), 200 HP
- `scenes/destructible_lamp_post.tscn` -- `light-curved.glb`, 120 HP
- `scenes/destructible_bridge_pillar.tscn` -- `bridge-pillar.glb`, 400 HP
  (toughest of everything built so far, by design -- a structural pillar
  should outlast a traffic cone)
- `scenes/destructible_highway_sign.tscn` -- `sign-highway.glb`, 180 HP
  (a 4m-wide overhead gantry sign at 4x scale, not a small roadside sign)
- `scenes/destructible_awning.tscn` -- `detail-awning.glb`, 40 HP
- `scenes/destructible_parasol.tscn` -- `detail-parasol-a.glb`, 25 HP
  (flimsiest, same tier as the cone)

**Vehicles** (`destructible_vehicle.gd`, Kenney Car Kit's real-world-ish
scale convention, same 4-wheel + bumper + door debris recipe as the bus):
- `scenes/destructible_sedan.tscn` -- `sedan.glb` + `wheel-default.glb`
  (smaller wheel radius than the truck's `wheel-truck.glb`, same 0.3m
  radius coincidentally), 120 HP
- `scenes/destructible_ambulance.tscn` -- `ambulance.glb`, same wheel/debris
  set, 250 HP

`assets/kenney_car_kit/` gained `sedan.glb`, `ambulance.glb`, and
`wheel-default.glb` (copied from the same already-downloaded Car Kit zip
used for the bus -- no new download needed).

Verified the same way as the first batch: a throwaway main-scene + Node
script booted via `godot --headless --path . <scene> --quit-after 8`
(plain `--script` mode can't resolve the `GameState` autoload), confirming
all nine join the `"destructible"` group and fire `destroyed` on reaching
zero health, zero new errors. Debug script/scene deleted after use.

**Not visually confirmed** -- no display in this session.

### Note on git history

Partway through this session the repo's git log picked up commits (e.g.
`72b39d2`, `f3a0bf2`) that bundle some of this work together with unrelated
NPC/police/spawner changes that weren't made by this session. Per
CLAUDE.md's "multiple agents may be working in this repo" warning, this
looks like another concurrent agent's commit swept up this session's
untracked files rather than anything done here -- this session never ran
`git commit`. Flagging it rather than touching the history.

### Still open (Tier 2, not built)

- Kenney Furniture Kit (https://kenney.nl/assets/furniture-kit, CC0, ~140
  models) -- benches, trash cans, more street furniture in one pull.
- Statue (CC-BY Zsky vs. CC0 Quaternius Fox/Mannequin, per
  `agents/prop-character-assets-research.md`).
- Newsstand/phone booth/market stall -- found via Polyfork/Sketchfab but
  licenses are mixed per-model there, needs individual verification before
  use.
