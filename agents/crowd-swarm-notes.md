# Crowd Swarm + Megaphone Recruitment Cone — Implementation Notes

Scope of this pass: the smallest slice that makes the game actually
playable per the core loop in `vision.md` — hold left-click to recruit
civilians inside a cone, right-click to charge the recruited mob at a
target, hold right-click to regroup them. **Grabuge is explicitly not
implemented yet** (per direct instruction) — the recruitment cone uses
static default dimensions instead of scaling with a Grabuge value. `vision.md`
itself was deliberately left untouched in this pass (it already specified
this control scheme; this just implements it).

## Architecture

- `scripts/crowd_controller.gd` (`class_name CrowdController`) — one node,
  added to `scenes/test_map.tscn` as a sibling of `Player`/`NPCSpawner`.
  Owns `recruited: Array[Node3D]`, polls the megaphone's cone each physics
  frame to recruit civilians, and reacts to `Megaphone`'s
  `attack_command_triggered`/`regroup_triggered` signals to issue
  CHARGE/REGROUP commands to everyone it has recruited.
- `scripts/npc.gd` — states are now `IDLE, WANDER, FOLLOW, CHARGE, REGROUP`.
  `IDLE`/`WANDER` are the pre-recruitment wander behavior (unchanged, see
  `agents/npc-wander-notes.md`). Once recruited (`recruit()` called by
  `CrowdController`), an NPC never decides *where* to go again on its own —
  `enter_charge(destination, delay)` / `enter_regroup(destination)` are the
  only way its target changes, consistent with vision.md's "avoid individual
  strategic decision-making."
- `addons/fps_controller/Megaphone.gd` — owns the influence cone visual and
  geometry, and the click/hold input handling. Exposes
  `is_recruiting_held()` and `is_point_within_cone(point)` as the entire
  interface `CrowdController` needs; it has zero references to NPCs or the
  crowd, preserving the separation documented in
  `agents/megaphone-notes.md`.

## Steering (per NPC, in `scripts/npc.gd`)

Seek + separation only — **cohesion was deliberately skipped** for this
pass. Reasoning: FOLLOW already seeks a single shared point (the player),
which keeps the crowd grouped on its own; separation then keeps that group
from stacking. Adding cohesion on top mostly matters once individual NPCs
have their own wander/sub-goals again (e.g. during CHARGE's post-arrival
idle) — worth revisiting if the charged mob looks too loose once visually
verified.

- **Seek:** normalized vector toward the current target (leader position
  for FOLLOW, assigned destination for CHARGE/REGROUP).
- **Separation:** `CrowdController.get_neighbors(npc, separation_radius)` —
  a flat O(n) scan over `recruited` (not a spatial grid). Deliberate: at the
  NPC counts this prototype targets (tens, not yet the spec's eventual
  hundreds), O(n²) per frame is trivial. If/when NPC counts grow enough to
  matter, swap the implementation of `get_neighbors` for a spatial grid —
  nothing in `npc.gd` needs to change, it only calls the method.
- **Randomization:** each NPC rolls a `_speed_variance` (0.85–1.15×
  `move_speed`) once at recruit time, and CHARGE assigns a random 0–0.4s
  reaction delay per NPC (`charge_reaction_delay_max`) — both per
  vision.md's "slight random variations in movement speed and reaction
  delays."

## Destinations

`CrowdController._scatter_point(center, radius)` is the single seam that
generates a distributed point around a commanded location (uniform-disc
random, same pattern `scripts/npc_spawner.gd` already used for spawn
placement). Both CHARGE (`charge_spread_radius`, default 3m around the
clicked point) and REGROUP (`regroup_spread_radius`, default 2m around the
player) go through this one function. Per vision.md, this is meant to be
extensible later for bus/plaza/road/barricade-shaped destination areas —
when that's built, give each destination *type* its own point generator and
have whatever triggers the command call the right one; `CrowdController`'s
side (assigning a destination per recruited NPC) doesn't need to change.

## Recruitment cone

- `Megaphone.gd` exports `cone_range` (default 18m) and `cone_angle_degrees`
  (default 50°) — these are a direct lift of the spec's "50% Grabuge" row,
  used as a fixed default since Grabuge doesn't exist yet. **When Grabuge
  lands, these two should be driven by it (interpolated per the 0/50/100%
  table in the original spec) instead of being static exports** — call
  `_update_cone_shape()` whenever Grabuge changes rather than only once at
  `_ready()`.
- Visual: `InfluenceCone` (a `MeshInstance3D` using a `CylinderMesh` with
  `top_radius = 0`, built in `addons/fps_controller/Megaphone.tscn`),
  parented directly under `Megaphone` (not `VisualRoot`, so the raise/shake
  tween on the held prop doesn't also shake the cone). Translucent additive
  unshaded material, `cull_mode = DISABLED` so it's visible from inside the
  cone too (the player's own viewpoint is inside it). Only toggled
  visible/invisible on hold-start/hold-stop; `_update_cone_shape()` only
  needs to run once right now since the dimensions are static.
- Recruitment check: `is_point_within_cone()` does its own range + half-angle
  dot-product check directly against the active camera's transform — it
  does **not** depend on the visual mesh being positioned/oriented
  correctly, so recruitment logic is correct even if the mesh placement
  needs visual tuning later (no display in this dev environment to confirm
  that against).
- Input change: left-click ("recruit") is now **hold**, not a single click —
  `_start_recruit()`/`_stop_recruit()` on press/release toggle the cone and
  `_recruiting_held`. Right-click ("attack_command") now distinguishes a
  short click (À L'ATTAQUE!, uses the raycast target captured at press-time)
  from a hold ≥ `regroup_hold_threshold_msec` (350ms default) released as
  Regroup — this replaces the old click-only `recruit_triggered` signal
  entirely and implements vision.md's existing "Hold Right Click = Regroup"
  control that a prior pass had left unimplemented (see the "Not
  implemented" note at the bottom of `agents/megaphone-notes.md`, now
  stale).

## Scene wiring

`scenes/test_map.tscn`: added `CrowdController` as a plain `Node` sibling of
`Player`/`NPCSpawner`, with `player_path`/`npc_spawner_path` NodePaths set
to `../Player` / `../NPCSpawner`. Bumped `NPCSpawner.npc_count` from 7 to 30
(closer to "feels like a crowd" without yet attempting the spec's eventual
100+ target, which needs a perf pass this slice doesn't do) and
`spawn_radius` from 10 to 14 to keep density reasonable at the higher count.

**Gotcha hit and fixed:** `CrowdController` originally looked up the
Megaphone via `get_viewport().get_camera_3d()` once in `_ready()` and gave
up (logged a warning) if it came back null. In practice it reliably *does*
come back null at that point headless — `Camera3D.current = true` isn't
guaranteed to be registered with the viewport by the time sibling nodes run
`_ready()` in the same frame. Fixed by resolving the Megaphone lazily inside
`_physics_process` (retry every frame until found, then cache it) instead of
a one-shot lookup.

## Verification

```
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --editor --quit-after 25
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --quit-after 10
```

Both clean: no parse/script errors, no missing-resource errors, and (after
the lazy-lookup fix) no more "couldn't find Megaphone" warning. The usual
abrupt-quit RID/leak noise on exit is present and is the same
display-less-headless-teardown artifact documented in
`agents/map-dressing-notes.md` and `agents/fps-prototype-notes.md` — not a
defect introduced here.

**Not verified — no display in this environment:** actual steering *feel*
(does separation look right, does the charge read as "energetic," is the
cone's visual cone actually aligned with the geometric check used for
recruitment), exact cone mesh alignment, and whether 30 NPCs at the tuned
speeds/radii actually reads as "one large, slightly chaotic group" per
vision.md's Stage 1 success criterion. **Someone needs to run `task run` and
actually hold left-click near civilians, then right-click/hold-right-click,
before calling this stage done.**

## Explicitly not done in this pass (by instruction)

- Grabuge (separate system, separate pass).
- Scaling the cone dynamically — it's static for now, see above.
- Spatial-grid neighbor search / any perf work toward the spec's 100+ NPC
  target.
- Per-destination-type point generators (bus/plaza/road/barricade) — only
  the generic uniform-disc scatter exists.
- `vision.md` was intentionally not edited this pass (explicit instruction —
  "vision stays the vision").
