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

- Nothing placed in `scenes/test_map.tscn` — per explicit instruction, these
  are ready-to-use scenes only.
- Café tables/chairs/kiosks (Kenney City Kit Commercial) and a statue
  destructible were in the original brainstorm but not built this pass —
  only the agreed shortlist (street props, bus, glass) was done.
- The one untextured normal-map surface on Paris Building A
  (`agents/map-dressing-notes.md`) is unrelated and untouched.
