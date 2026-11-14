# Map generation: the 5x grid, and the scene-corruption incident that forced a rewrite

Supersedes the hand-editing approach in `agents/map-dressing-notes.md` for
everything under `MapGeometry`. That file is still the record of *why* the
individual tile/building conventions are what they are -- read it first.

## The incident (read this before writing any map tooling)

The first attempt at the 5x map was a GDScript generator run as
`godot --headless --script generate_map.gd`, which did:

    load("res://scenes/test_map.tscn").instantiate()
      -> clear and rebuild the MapGeometry subtree
      -> PackedScene.pack(root) -> ResourceSaver.save(..., "test_map.tscn")

This **destroyed the scene**. `test_map.tscn` went from 1.2MB to 2.6KB:
`MapGeometry` ended up empty, and `NPCSpawner`, `PoliceSpawner`,
`CrowdController`, `HUD` and `GameOver` all lost their `script` assignment
*and every exported property on them* (`npc_count`, `spawn_radius`,
`player_path`, `player_health_path`, `weapon_switcher_path`, ...).

Root cause, two compounding mistakes:

1. **Bare `--script` mode does not initialise autoloads.** Every script that
   references the `GameState` autoload (`npc_spawner.gd`, `police_spawner.gd`,
   `crowd_controller.gd`, `hud.gd`, `game_over.gd`, `destructible_prop.gd`)
   fails to compile in that context -- "Compile Error: Identifier not found:
   GameState" -- and Godot silently nulls the `script` property on the nodes
   using them. `agents/destructible-props-notes.md` had **already documented
   this exact trap**; it got ignored.
2. **Repacking the whole root to change one subtree.** Because the save
   serialised the entire scene, the broken null-script state got written for
   nodes the generator never meant to touch. Mistake 1 was the trigger;
   mistake 2 is what made it catastrophic. Even with autoloads working, a
   whole-scene round-trip for a geometry change is one bad frame from eating
   the gameplay wiring.

Note the generator's own output said `Generated: 36 buildings, 12
intersections` and `save err: 0`. **It reported success while writing a
wrecked file.** Recovered from a `cp` backup taken immediately before the run;
take one before any destructive map operation.

## The approach now

`MapGeometry` is its own scene, `scenes/map_geometry.tscn`, containing nothing
but geometry -- no gameplay scripts, nothing that touches an autoload.
`test_map.tscn` references it with a single line:

    [node name="MapGeometry" parent="." instance=ExtResource("42_mapgeo")]

and `tools/generate_map_geometry.py` **emits that scene as text**. No Godot
runtime, no `instantiate()`, no `pack()`, nothing to round-trip. Regenerating
the map now *structurally cannot* reach the gameplay nodes -- it writes a
different file. It is also much faster to iterate (no engine boot per attempt)
and the generator is checked in, unlike the previous delete-after-use scripts,
because re-runnability is the entire point.

    python3 tools/generate_map_geometry.py
    godot --path . --headless --quit-after 200     # confirm it loads

Hand-written `format=4` `.tscn` text works fine and does **not** need the
`unique_id=` fields Godot writes (verified with a throwaway 4-node scene
before generating 2000). Omit the redundant `mesh = SubResource(...)` child
override that the old inline map carried on every tile -- instancing a
PackedScene already brings its meshes, and that duplication is what CLAUDE.md
warns about in generator-built scenes.

## Layout

| | |
|---|---|
| extent | 212 x 212 = 44,944 m2 (**6.2x** the old ~7,200 m2) |
| streets | 4 N-S and 4 E-W, centrelines at -96 / -32 / 32 / 96 |
| intersections | 16 |
| cross-section | 3 road lanes at offset -4/0/+4, sidewalks at +/-8, corridor edge +/-10 |
| buildings | 72 (Paris pack A/B/C at 3x) |
| destructible props | 372, 16 kinds |
| tiles | 1,720 |

**Street spacing is 64 and that number matters.** It was chosen after 48
measurably failed. Spacing must be a multiple of the 4-unit tile pitch so
intersection tiles land on the street grid, which leaves 48 and 64 as the
candidates:

- At 48 the block run is 28 units. The widest building (B, 20.4) consumes
  almost the whole run, so a facade on one block edge collides with the
  perpendicular edge's facade at every corner. Result: **23 buildings** over
  the whole map -- i.e. tightening the grid made it *sparser*, recreating the
  original "huge empty gaps" complaint.
- At 64 the run is 44 units: enough for a facade on all four block edges
  *and* ~3 buildings per edge. 72 buildings.

Two other things were needed to get the count up, both worth keeping:

- **Pack per block run, not from the map edge.** Marching building positions
  globally from `Z_MIN` means almost every candidate straddles a run boundary
  and gets rejected (that alone was 42 -> 23).
- **Slide past obstructions.** When a candidate overlaps something already
  placed -- the normal case at corners, where the perpendicular facade got
  there first -- nudge along by 2 units and retry instead of abandoning the
  slot. Roughly doubled the count (42 -> 72).

Placement order is deliberate: N-S facades go down first and get full runs,
E-W facades then slide around whatever holds the corners.

### Why not Kenney commercial buildings as small infill

Measured their AABBs headlessly to use them for denser corner/infill
placement. At the project's 4x scale they are ~3.5 x 5 x 3.8 units -- a
1.5-storey hut beside a 14-22m Paris building. Scaling them up to a matching
height puts their footprint back at Paris-building size, so they solve
nothing. Any building tall enough to look right has a comparable footprint;
the answer was bigger blocks, not smaller buildings. Left unused.

### Tile orientation

The four cardinal Y-rotations at scale 4, lifted verbatim (float noise
included) from the hand-built map so new tiles match existing ones exactly --
see `R0`/`R90`/`R180`/`R270` in the generator. `road-side` is asymmetric: its
curb sits on **local -Z**, confirmed from two independent data points in the
old map (sidewalks at z=+4 used R0 and at z=-4 used R180, both pointing local
-Z at the road). So the rotation for a sidewalk is whichever one aims local -Z
at the carriageway.

Buildings on E-W streets are rotated 90 degrees (visual basis
`0,0,-3, 0,3,0, 3,0,0`); their collision `StaticBody3D` is rotated the same
way so the existing `BoxShape3D_paris3x_*` boxes can be reused as-is rather
than needing x/z-swapped duplicates.

### Ground plate

One `PlaneMesh` at y=-0.05 spanning the whole extent, flat dark material, with
a single matching `BoxShape3D` for collision. Block interiors are enclosed
courtyards with nothing in them, so without this they read as void. It is the
one mesh in the scene with a deliberately null `albedo_texture` -- don't
"fix" that.

## Destructibles wired in

All 16 destructible scenes from `agents/destructible-props-notes.md` (whose
"nothing placed in test_map" follow-up this closes) are now placed. Each
scene bakes its own model scale internally, so they are instanced at **scale
1**, not 4.

- intersection corners: traffic lights, stop signs (+ plain `light-square` lamps)
- sidewalks: lamp posts, dumpsters, electricity poles, fences, parasols, cones
- gutter lanes: bus, sedans, ambulances
- intersection approaches: barricade lines with flanking cones (riot chokepoints)
- building faces: shop window + awning + parasol
- landmarks: highway signs, bridge pillars

Shopfront glass is deliberately sparse (32, one per block face rather than a
continuous parade): each pane is a `CSGPolygon3D` that rebuilds its mesh to
fracture, making it the most expensive prop in the set.

Props are kept 7 units clear of `PlayerSpawn` at (0, 1, 10).

## Verification done

Via a throwaway debug scene run in a **full project boot** (not `--script`, per
the incident above), deleted after use:

    Visuals=1825  Props=372  Collision=73
    destructible group members: 373   missing take_damage(): 0
    building boxes: 72               overlapping pairs: 0
    buildings intruding into a street corridor: 0
    props buried inside buildings: 0 / 372
    sampled meshes: 50               null albedo_texture: 1  (the ground plate)

Plus a clean `--headless` boot: exit 0, zero script/parse errors, and only the
3 pre-existing warnings (the `blood_effect` UID notice and the two expected
`CompassBar` parent warnings documented in `agents/compass-hud-notes.md`).

**Not visually confirmed** -- no display access. Needs an eyeball pass via
`task run`. Most likely things to be wrong, in order:

1. Sidewalk curb direction. The local--Z reasoning is sound but was never
   seen; if curbs face the buildings instead of the road, swap R90<->R270 for
   N-S sidewalks and R0<->R180 for E-W.
2. Paris building C sits with visual `y=2.16` while its collision box centre
   is at plain `half_height` -- an inconsistency inherited from the old map and
   preserved rather than "fixed" blind. May read as a slight float/sink.
3. Whether 44-unit blocks feel like streets or canyons at player scale.

## Side effects of this pass

- **`test_map.tscn`: 1.17MB -> 3.2KB.** Extracting the geometry orphaned 36
  resources (`ArrayMesh`/`StandardMaterial3D` blocks from the old inline
  tiles, plus unused `ext_resource` declarations), pruned by transitive
  reachability from the node body. A flat "is this id mentioned anywhere"
  check is **not** sufficient -- Godot's `ArrayMesh` blocks cross-reference
  each other via `shadow_mesh`, so unreachable meshes keep each other alive.
  All 11 nodes and every script/exported property verified present afterwards;
  the file is small because the geometry moved out, not because anything was
  lost. (Contrast the 2.6KB corruption above, which was small because content
  *was* lost -- size alone does not distinguish the two, check the properties.)
- **Dropped:** the old ramp + raised platform (`road-slant-high`/`tile-high`
  with `RampCollision`/`PlatformCollision`) that sat around z=-44..-58. The new
  grid occupies that space. Not reinstated -- a block interior would be a
  natural home for it if wanted.
- The old map's `road-crossroad` tile is unused: it is sized for a 1-lane
  street and cannot span a 20-unit intersection. Intersections are 5x5 grids
  of plain `road-square` pavement instead, with `road-crossing` zebra tiles on
  the approaches.

## Perf caveat

~2,250 nodes under `MapGeometry` (1,825 visuals + 372 props), against ~164 in
the old map. Unprofiled, and the props are the concern rather than the tiles:
372 `StaticBody3D`s each carrying a `ProgressBar3D` health bar and an outline
mesh. If frame time is bad, thin the props before the tiles.
