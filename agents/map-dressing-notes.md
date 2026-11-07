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

## Where the assets live

- `assets/kenney_city_kit_roads/` — all 95 GLB models from the Roads pack
  (road tiles, bends, crossroads, sidewalks, ramps/slants, barricades, cones,
  lamps, signs, traffic lights, bridge pieces), plus `Textures/colormap.png`
  (the shared texture atlas the GLBs reference by relative URI) and
  `LICENSE.txt`.
- `assets/kenney_city_kit_commercial/` — all 41 GLB models from the
  Commercial pack (14 full-detail buildings, 14 low-detail/background
  buildings, awnings/overhangs/parasols), plus its own `Textures/colormap.png`
  and `LICENSE.txt`.

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
every model (95 in roads, 41 in commercial) and zero `ERROR`/`WARNING` lines
on the final clean run.

## How the map was rebuilt

Hand-writing ~100 `[node]` blocks with correct `Transform3D` math in the raw
`.tscn` text was going to be slow and error-prone, so instead I wrote a
one-off headless `SceneTree` script (`generate_map.gd`, deleted after use —
not checked in) that:

1. Builds the `TestMap` root, `WorldEnvironment` (same `ProceduralSkyMaterial`
   sky + ambient settings as the old grey-box level), and `DirectionalLight3D`
   exactly as before.
2. Procedurally instances Kenney GLB scenes on a grid and packs the result
   into `scenes/test_map.tscn` via `PackedScene.pack()` + `ResourceSaver.save()`.
3. One important trap: `pack()` silently drops any node whose `owner` isn't
   set to the scene root — my first attempt saved a 6-line file with just the
   root node. Fix was a recursive `child.owner = root` pass over the whole
   tree before packing.

### Scale and grid

Measured a sample of GLBs with a small script (`AABB` of all `MeshInstance3D`
children): every road/sidewalk tile is a 1×~0.02×1 flat quad centered on
origin, and commercial buildings are roughly 0.85–1.6 (width) × 0.9–1.7
(height) × 0.9–1.1 (depth) units. That's Kenney's authored-for-a-4x-scale-up
convention (1 unit model = 4m in-game), which also makes buildings come out
3.5–7m tall — reasonable next to the FPS controller's human-scale capsule.
**Everything in the new map is instanced at `scale = Vector3(4,4,4)` with a
4-world-unit grid pitch.**

### Layout

A "+"-shaped two-street intersection centered on the origin:

- Main street runs north–south along `x=0` (`road-straight`, a
  `road-crossroad` at the intersection), long enough to comfortably cover the
  player spawn at `(0,1,10)`.
- A shorter east–west cross street at `z=0`.
- `road-side` sidewalk tiles flank both streets; a couple of `road-crossing`
  tiles mark pedestrian crossings near the intersection.
- Two rows of commercial buildings (`building-a/c/e/g` west side,
  `building-b/d/f/h` east side) line the main street behind the sidewalks,
  plus two `low-detail-building` pieces further back for a bit of skyline.
- North of the main street (negative Z, away from spawn) is a small plaza
  (`road-square` plain pavement tiles) with a `road-slant-high` ramp up to a
  `tile-high` platform and one more building framing it — this is the
  elevation/collision sanity-check area, replacing the old ramp+stairs
  cluster. I dropped the separate staircase; one ramp was enough to cover
  "walkable with elevation change" per the task's either/or allowance.

### Collision: decoupled from the visuals, deliberately

The Kenney GLBs carry **no collision data** — they're pure visual meshes.
Rather than hand-derive a `ConvexPolygonShape3D`/`ConcavePolygonShape3D` per
tile/building (fragile, and impossible to eyeball-correct without a display),
I used one flat invisible `StaticBody3D` + `BoxShape3D` as a single continuous
walking surface under the entire street/plaza footprint (`GroundCollision`,
world x ±28, z -45..25), plus one invisible box per building
(`BuildingWest_0..3`, `BuildingEast_0..3`, `BuildingLowA/B`, `BuildingPlaza`)
sized from the same AABB measurements used for scale, and a tilted invisible
box + flat invisible box for the ramp/platform. All of these live under
`MapGeometry/Collision/`; the real visuals live under `MapGeometry/Visuals/`
and have zero physics presence. This means the collision guarantees are
correct by construction (simple boxes I control) even though I can't verify
the visual alignment is pixel-perfect.

## Known issues / limitations

- **No display in this environment — none of this has been visually
  confirmed.** I cannot confirm that road/sidewalk/building rotations line up
  correctly (I guessed a consistent rotation convention — default orientation
  assumed east-west, +90° for north-south pieces — documented in
  `generate_map.gd`'s history, now only in this note since the generator
  script was a throwaway tool, not checked in), that textures look right, or
  that the ramp's visual slope actually matches its invisible collision box's
  tilt (off by a few degrees/centimeters by construction — walkability is
  guaranteed, visual-to-collision pixel alignment is not). **Someone with a
  display needs to run `task editor` or `task run` and eyeball it** —
  expect to need to nudge a few rotations/positions once you can actually see
  the result.
- Collision is intentionally decoupled from visuals (see above) — if a later
  pass wants per-piece mesh collision (e.g. for a building you can see
  through a gap in), that's a deliberate simplification to revisit, not an
  oversight.
- Only GLB models were imported; FBX/OBJ copies from the zips were discarded
  (not needed, GLB is sufcient for Godot 4).
- The Roads pack's prop pieces (barricades, cones, lamps, signs, traffic
  lights, construction fences/barriers) are all sitting in
  `assets/kenney_city_kit_roads/` unused — didn't place any in the test map
  to keep scope to "map/environment," but they're a natural next pass for
  "protest barricade" dressing once gameplay agents land their pieces.
  Tracked in `assets.md`.
- KayKit City Builder Bits (optional variety pack) was not downloaded this
  pass — see rationale above.
- The old grey-box `test_map.tscn` is gone (overwritten, not kept as a
  separate file) — if it's needed for comparison it's recoverable from git
  history (this worktree's branch, pre-this-commit).

## Verification done

```
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --quit-after 1
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --quit-after 5
```

Both runs load the project and the main scene with **zero parse errors,
script errors, or missing-resource errors**. There are harmless
`RID allocations ... leaked at exit` / `ObjectDB instances were leaked at
exit` messages on quit — I checked these also appear (in smaller numbers)
when forcibly quitting the engine on *any* non-trivial scene after only a
few frames under the headless dummy renderer; it's Godot's abrupt-quit
cleanup path not finishing, not a defect in this scene. The old grey-box
scene produced zero such messages because it was simple enough to finish
tearing down inside the 1-frame window; this scene has far more
mesh/material/texture resources in flight so the race is visible. Confirmed
there is no actual `ERROR`/`WARNING` text containing "parse", "script error",
"failed to load", "cannot open", "invalid", or "missing" in either run.

I have **no display in this environment**, so movement feel, visual
alignment, lighting, and whether the street actually looks like a Paris block
(versus, say, a parking lot) are all unverified. Playtesting via `task run` is
needed before calling this done-done.
