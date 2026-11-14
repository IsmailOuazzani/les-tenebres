# Map Dressing: Swapping Grey-Box for Real Kenney Assets

Goal: replace the CSGBox3D grey-box geometry in `scenes/test_map.tscn` with real
low-poly modular assets so the test level reads as a small Paris-ish street
block, per `vision.md`. Scope was map/environment only — no NPCs, UI, or
gameplay logic (other agents own those, in separate worktrees).

## What got downloaded

- **Kenney City Kit (Roads)** — https://kenney.nl/assets/city-kit-roads
- **Kenney City Kit (Commercial)** — https://kenney.nl/assets/city-kit-commercial

Did **not** download KayKit City Builder Bits (the optional "if time allows"
pack) — the two Kenney kits already gave enough variety (95 road/prop pieces,
41 building/detail pieces) to build a convincing block, and mixing in a
differently-styled kit would have meant also solving a second grid/scale
convention. Flagged as still-optional in `assets.md`.

### How the download actually worked (no manual browser needed)

Kenney's asset pages are mostly static HTML but the actual "Download" button
is JS: it reads a `data-download-id` attribute (hex-encoded string, e.g.
`6173736574732f636974792d6b69742d726f616473` decodes to
`assets/city-kit-roads`), hits `https://kenney.nl/download-link/<hex-id>` to
get a short-lived signed URL, then redirects there. Reproduced with plain
curl:

```
curl -A "Mozilla/5.0" -H "Referer: https://kenney.nl/assets/city-kit-roads" \
  "https://kenney.nl/download-link/<hex-id>"
# -> {"url":"https://kenney.nl/download/<hex-id>/<signed-token>?expires=..."}
curl -A "Mozilla/5.0" -o pack.zip "<that url>"
```

A user-agent header is required — plain `curl -sL` with no UA got a 403 from
whatever WAF/CDN fronts kenney.nl. The hex id is just `assets/<slug>` from the
page URL, ASCII-hex-encoded, so this is reproducible for any Kenney asset page
without needing a headless browser.

## Where the assets live (Kenney)

- `assets/kenney_city_kit_roads/` — all 95 GLB models from the Roads pack
  (road tiles, bends, crossroads, sidewalks, ramps/slants, barricades, cones,
  lamps, signs, traffic lights, bridge pieces), plus `Textures/colormap.png`
  (the shared texture atlas the GLBs reference by relative URI) and
  `LICENSE.txt`.
- `assets/kenney_city_kit_commercial/` — all 41 GLB models from the
  Commercial pack. **As of the "Paris-only buildings" pass (see below), none
  of the commercial building GLBs are instanced in `test_map.tscn` anymore**
  — only the road-kit pieces (roads/sidewalks/crossings/square/slant/platform)
  are still placed. The commercial building `.glb` files and their
  `ext_resource`/mesh/material declarations are still present in the repo and
  in the `.tscn` header (harmless, unreferenced by any node) but are no
  longer part of the visible map. Left in place rather than surgically
  stripped out of the `.tscn` header — see "What changed" below for why.

Only the **GLB format** variant was kept (not the FBX/OBJ copies in the
original zips) — GLB is Godot 4's best-supported import path and avoids an
extra material-reassignment step FBX/OBJ usually need.

### Import gotcha: GLBs reference an external texture by URI

I expected the binary `.glb`s to embed their textures (that's the point of
the binary container), but these are Unity-GLTF exports that reference
`Textures/colormap.png` by relative URI string inside the JSON chunk instead
of embedding the image bytes. Importing with only the `Models/GLB format/*.glb`
files copied in (no `Textures/`) throws, per model:

```
ERROR: Can't open file from path 'res://assets/kenney_city_kit_roads/Textures/colormap.png'.
WARNING: glTF: Image index '0' couldn't be loaded as a buffer ... Skipping it.
```

Fix: copy each pack's `Models/GLB format/Textures/colormap.png` alongside the
models at `assets/<pack>/Textures/colormap.png` (same relative path the GLB
expects), then force a reimport. I had already imported once without the
textures present, so Godot had cached a "no texture" result — I had to delete
the generated `*.glb.import` sidecar files and `.godot/imported/` before
re-running the headless editor scan for it to actually pick the textures up;
simply adding the files and rescanning wasn't enough.

### Forcing the import (same trick as the FPS prototype notes)

Per `agents/fps-prototype-notes.md`, there's no display here, so the normal
"open the project in the editor once" step has to happen headlessly:

```
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --editor --quit-after 25
```

This triggers Godot's filesystem scan + importer, same as opening `task
editor` would. Confirmed via `*.glb.import` sidecar files appearing next to
every model and zero `ERROR`/`WARNING` lines on the final clean run.

## How the map was rebuilt (original pass)

Hand-writing ~100 `[node]` blocks with correct `Transform3D` math in the raw
`.tscn` text was going to be slow and error-prone, so instead a one-off
headless `SceneTree` script (`generate_map.gd`, deleted after use — not
checked in) built the `TestMap` root, `WorldEnvironment`,
`DirectionalLight3D`, procedurally instanced GLB scenes on a grid, and packed
the result into `scenes/test_map.tscn` via `PackedScene.pack()` +
`ResourceSaver.save()`.

### Scale and grid

Every road/sidewalk tile is a 1×~0.02×1 flat quad centered on origin, and
Kenney commercial buildings were roughly 0.85–1.6 (width) × 0.9–1.7 (height) ×
0.9–1.1 (depth) units — Kenney's authored-for-a-4x-scale-up convention (1 unit
model = 4m in-game). **Everything Kenney-sourced in the map is instanced at
`scale = Vector3(4,4,4)` on a 4-world-unit grid pitch — this convention is
unchanged by every later pass, including the map-doubling pass below, per an
explicit "roads can stay the same size" instruction.**

### Layout (original)

A "+"-shaped two-street intersection centered on the origin: main N–S street
along `x=0` (`road-straight` + `road-crossroad` at the intersection), a
shorter E–W cross street at `z=0`, `road-side` sidewalks flanking both,
`road-crossing` tiles at the intersection, two rows of commercial buildings
flanking the main street, and a small plaza (`road-square` + `road-slant-high`
ramp + `tile-high` platform) north of the intersection (negative Z).

### Collision: decoupled from the visuals, deliberately

The Kenney GLBs carry **no collision data**. Rather than hand-derive
per-tile collision shapes, the map uses one flat invisible `StaticBody3D` +
`BoxShape3D` as a single continuous walking surface under the whole
street/plaza footprint (`GroundCollision`), plus one invisible box per
building sized from measured AABBs. All collision lives under
`MapGeometry/Collision/`; visuals live under `MapGeometry/Visuals/` with zero
physics presence. **This decoupling is what made every later pass (building
swaps, 3x rescale, map doubling) tractable without touching any visual mesh
data — only the box positions/sizes in `MapGeometry/Collision` need to track
building moves.**

## Update: Paris Building Pack swap + street props

Swapped three of the generic Kenney commercial buildings for the **Free
Paris 3 Building Pack** (CGTrader, https://www.cgtrader.com/free-3d-models/architectural/decoration/paris-3-building-pack,
by designer `ponpadolen` — free, Royalty Free License, "free for personal
and commercial use"). CGTrader requires an account login even for free
downloads — the user downloaded the zip manually and handed it off.

### Where it lives / what's in it

- `assets/paris_building_pack/BuildingA/`, `BuildingB/`, `BuildingC/` — one
  FBX per building. The pack's **OBJ+MTL export is broken** (black
  materials, no texture refs) — a classic Maya `aiStandardSurface` → OBJ
  export that didn't translate PBR shader textures. Used the FBX files
  instead, which carry texture-path references. Did **not** convert to
  GLB — no Blender install in this environment; Godot 4.7's native FBX
  importer loads these directly.

### Geometry note: huge flat node hierarchy, but only one real mesh per building

Each FBX imports as ~100-450 near-empty `Node3D` placeholder nodes (Maya's
original per-object names) plus exactly **one** `MeshInstance3D` holding the
entire building as a multi-surface merged mesh (Godot's FBX importer's
default "merge meshes" behavior). Harmless but node-count-heavy; fine for a
prototype.

### Scale — already real-world/game scale, no 4x multiplier needed (at the time)

Unlike the Kenney kit, this pack's FBX files already bake real-world-ish
scale into their node transforms. Measured world-space bounding boxes:

- Building A: ~2.29m (w) × 4.76m (h) × 4.47m (d)
- Building B: ~6.80m (w) × 7.35m (h) × 6.81m (d)
- Building C: ~3.03m (w) × 5.92m (h) × 4.37m (d)

All in the same 3.5-7m height range as the Kenney commercial buildings they
replaced, so at the time no extra scaling was applied — each was instanced
at `scale = Vector3(1,1,1)`. **This changed in the "3x scale + Paris-only"
pass below.**

### Street props

Placed Kenney Roads props near the main intersection
(`MapGeometry/Visuals/StreetProps`): two `construction-barrier` + three
`construction-cone` (loose "protest barricade" dressing), and four
`light-square` lamp posts. Unaffected by the later passes below (they sit
near the original intersection, far from the relocated building rows).

## Update: Paris-only buildings, 3x scale, texture fix, map doubling

Follow-up pass addressing four asks together: (1) remove every non-Paris
building from the map, (2) fix the Paris buildings' textures (they were
rendering as flat white/grey geometry), (3) scale the Paris buildings 3x,
(4) roughly double the map's overall footprint by adding more road and
building coverage, while leaving the Kenney road-kit tile *scale* ("roads
can stay the same size") untouched.

### Texture fix: FBX texture paths resolve relative to a baked absolute folder, not next to the FBX

The previous pass's "best-effort" texture matching (copying texture files
into `assets/paris_building_pack/Building<X>/TradeBuilding<X>1texs/`) turned
out to fail **completely**, not just partially — inspecting the imported
materials headlessly (`node.mesh.surface_get_material(i).albedo_texture`)
showed every single surface across all three buildings was `null`
(flat-white `StandardMaterial3D`). The reimport log confirmed why, once the
stale `.import` caches were cleared and a fresh reimport forced:

```
ERROR: Can't open file from path 'res://Documents/再販売可能テクスチャ/TradeBuildingB1texs/Dormerwindow1.png'.
WARNING: FBX: Image index '0' couldn't be loaded from path: ... because there was no data to load. Skipping it.
```

Godot's FBX importer does **not** reinterpret the FBX's absolute texture
path as simply `res://<folder-name>/<file>` relative to the FBX's own
location (that assumption, made in the previous pass, was wrong). Instead it
preserves the *entire* captured path tail from the original author's machine
— in this case a Mac path
`/Users/eijimatsumoto/Documents/再販売可能テクスチャ/TradeBuilding<X>1texs/<file>`
(Japanese: "resellable texture[s]" folder) — and tries to resolve it as
`res://Documents/再販売可能テクスチャ/TradeBuilding<X>1texs/<file>`, i.e.
relative to the **project root**, with that exact multi-segment prefix.

Fix: created `Documents/再販売可能テクスチャ/TradeBuildingA1texs/`,
`TradeBuildingB1texs/`, `TradeBuildingC1texs/` **at the project root** (not
under `assets/`), and copied the already-correctly-named texture files there
(moved them out of the old, wrong, per-building `assets/paris_building_pack/
Building<X>/TradeBuilding<X>1texs/` locations). One cross-reference
complication: Building C's FBX references textures from **both**
`TradeBuildingC1texs/` (its own) and `TradeBuildingB1texs/` (reused from
Building B's shared material set) — confirmed via `strings
BuildingC.fbx | grep texs/`, and merged both buildings' contributions into
the shared root `TradeBuildingB1texs/` folder.

After moving the folders and forcing a clean reimport (deleted
`Building{A,B,C}.fbx.import` + the corresponding `.godot/imported/*.scn`
caches first — same "stale import cache" trap as the Kenney pass), a
headless material inspection script confirmed every surface across all three
buildings now has a non-null `albedo_texture` pointing at a real file, except
one surface on Building A (`StandardMaterial3D_o3wlj`, a normal-map-only
surface whose best-effort-matched source file was itself unresolvable in the
original zip per the previous pass's notes) — that one remains a flat grey
fallback. Not investigated further; minor and pre-existing.

**Not visually confirmed** — no display in this environment. The texture
*files* are now loading (verified via `albedo_texture` no longer `null`),
but whether they look visually correct (UV mapping, orientation, the one
untextured surface) needs an eyeball pass via `task run`.

### Removing non-Paris buildings

Removed these node pairs (instance + `MeshInstance3D` child) from
`MapGeometry/Visuals`: `building-c2/-c`, `building-g2/-g`, `building-d2/-d`,
`building-f2/-f`, `building-h2/-h`, `low-detail-building-a2/-a`,
`low-detail-building-wide-a2/-wide-a`, and `@Node3D@84/building-a` (a
duplicate Kenney `building-a` instance that was sitting out near the plaza).
Removed the matching collision `StaticBody3D`s: `BuildingWest_1`,
`BuildingWest_3`, `BuildingEast_1`, `BuildingEast_2`, `BuildingEast_3`,
`BuildingLowA`, `BuildingLowB`, `BuildingPlaza`.

**Did not** touch the `.tscn` header's `ext_resource`/`sub_resource`
declarations for the removed Kenney commercial buildings (their GLB
references, baked `ArrayMesh`/`StandardMaterial3D` sub-resources) — only the
node instances placing them in the tree were removed. Godot does not error on
declared-but-unreferenced resources; surgically stripping them out of a
1.1MB generated file carried real risk (shared `StandardMaterial3D` /
texture `ext_resource` IDs between still-used and now-unused mesh
sub-resources) for no runtime benefit beyond file size. If someone wants the
dead weight gone later, it's a mechanical cleanup, not a design decision.

### 3x scale + repositioning

Each Paris building's `Transform3D` basis went from identity (scale 1) to
`scale 3` (diagonal 3,3,3). Building C's node-origin y-offset (0.72, a
pre-existing compensation for its mesh's local origin sitting below its own
ground plane) was rescaled to `0.72 * 3 = 2.16` to keep it sitting on the
ground post-scale — basis scaling multiplies local offsets, but a node's own
translation is in world units and has to be rescaled by hand to match.

At 3x, footprints are large: Building B (the biggest) is ~20.4m × 22m × 20.4m.
The original building rows (8 world units off the street centerline, 8 units
apart along the street) could not fit buildings this size without
overlapping each other or the sidewalks, so the whole row layout was
redesigned:

- Row centerline moved from `x=±8` to **`x=±36`** — far enough that even
  Building B's 10.2m half-width clears the cross-street's farthest sidewalk
  tile (at `x=20`, edge `x=22`) by ~3.8m, confirmed by direct calculation
  (not visually).
- Buildings per row went from 4 (mixed Paris/Kenney) to **4 Paris-only
  slots**, spaced **24 units apart** along Z (`z = 36, 12, -12, -36`) instead
  of the original 8. 24 units is enough gap for any adjacent pairing of the
  three building types at 3x scale — confirmed by computing
  `spacing - half_depth_1 - half_depth_2` for every adjacent pair on both
  rows; the tightest was ~7.1m, most were 7-11m.
- Building type assignment per slot (to avoid two identical huge buildings
  sitting next to each other): west row z=36/12/-12/-36 → A/B/C/A; east row
  z=36/12/-12/-36 → B/C/A/B. 8 building instances total (3 reused the
  original `paris-building-a/-b/-c` node names and got repositioned in
  place; 5 new instances added: `paris-building-w2`, `-w4`, `-e2`, `-e3`,
  `-e4`).
- Each building's collision `BoxShape3D` was resized to 3x its native
  measured AABB and recentered at `height*3/2` above ground (same pattern as
  the original pass, just with new box sub-resources
  `BoxShape3D_paris3x_{A,B,C}` since the dimensions changed).

**Not visually confirmed** — the 24-unit spacing and x=36 row offset are
derived from measured AABBs and arithmetic, not from looking at the result.
Someone with a display needs to run `task run` and confirm the buildings
don't look absurdly far from the street, and that the spacing reads as a
street block rather than scattered monoliths.

### Map doubling (more road, no new intersections)

To roughly double the map's footprint while leaving Kenney road-tile *scale*
untouched ("roads can stay the same size" — tiles are still `scale 4,4,4` on
the same 4-unit grid), extended the **main N–S street only**, in both
directions, rather than also widening the E–W cross street — extending the
cross street too would have pushed its own sidewalks out to intersect the
relocated building rows at `x=±36` (confirmed by calculation: a cross-street
extension reaching `x=36` would sit directly inside a building's footprint).
Keeping the cross street at its original length (`x=-20..20`) avoids that
conflict entirely.

- **South arm**: added 5 more `road-straight` segments (`z = 24, 28, 32, 36,
  40`) continuing south from the original street's `z=20` end, each flanked
  by a pair of `road-side` sidewalk tiles (`x=±4`) — same tile types,
  meshes, and rotation convention as the existing street, just more of them.
- **North arm**: added 5 more `road-straight` segments (`z = -24, -28, -32,
  -36, -40`) filling the gap between the original street's `z=-20` end and
  the plaza, which was **relocated 20 units further north** (`z -24..-40` →
  `z -44..-60` for the `road-square`/`road-slant-high`/`tile-high` plaza
  cluster, and `RampCollision`/`PlatformCollision` shifted to match) to make
  room. The new street segments and the relocated plaza are still exactly
  4-unit-pitch adjacent (no gap, no overlap) — same spacing the original
  layout used between its last straight tile and the plaza's first tile.
- `GroundCollision` (the single invisible walking-surface box under
  everything) was resized from `(56,1,70)` centered at `(0,-0.5,-10)` to
  `(112,1,132)` centered at `(0,-0.5,-8)` — large enough to cover every new
  road segment and every relocated/new building's footprint with margin,
  confirmed by checking each feature's extreme X/Z against the new box
  bounds.
- Street props, dumpsters, smoke FX, lamps, and the player/NPC spawn points
  were **not** moved — they all sit near the original intersection
  (`z` roughly `-4..12`), far from the relocated building rows and street
  extensions, so nothing new to overlap.

**Not visually confirmed.** All of the above (no overlaps, correct ground
coverage, correct tile adjacency) was checked by direct arithmetic on the
transform values (AABB half-extents, tile pitch, box bounds) and by dumping
positions from a headless script — not by looking at the rendered result.
Someone with a display needs to run `task run` and eyeball: whether the much
larger building setback (`x=36` vs the sidewalk's `x=8` edge) looks
intentional ("plaza frontage") rather than like empty wasteland (there is no
visible ground/pavement mesh filling that gap — only the invisible
`GroundCollision` box holds the player up there, same as every other
off-road patch in this map, pre-existing behavior not introduced by this
pass), whether the doubled street still feels walkable/paced correctly, and
whether the relocated plaza's ramp/platform still reads correctly at its new
position.

### Verification done / not done

Ran the full headless pipeline: forced FBX reimport
(`--headless --editor --quit-after 30`), then full game loads
(`--headless --quit-after 5-8`), comparing error output against an unmodified
backup of `test_map.tscn` to separate pre-existing issues (an unrelated
`Array[Node]` type-assignment warning in `addons/fps_controller/
WeaponSwitcher.gd`, untouched by this work) from anything new. **Zero new
errors or warnings.** A headless script instantiated the scene and dumped
every Paris building's and building-collision's position/scale, confirming
they match the intended layout exactly, and a separate arithmetic check
confirmed no building-to-building or building-to-sidewalk overlaps.

**Not verified — no display access in this session.** Visual appearance,
texture orientation/UV correctness, whether building "fronts" face the
street, and whether the new layout reads well in person are all unconfirmed.
Run `task run` and nudge as needed.
