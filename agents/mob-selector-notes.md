# Mob Selector + Send-% Spec

Status: **implemented** (first pass). Originally written as spec-only per
direct instruction before any code changes; the "Implementation" section at
the bottom records what actually landed and what's still unverified
visually. Supersedes the click/hold-duration split described in
`agents/crowd-swarm-notes.md` ("Input change: ... Right-click
('attack_command') now distinguishes a short click ... from a hold") and
the `attack_command_triggered`/`regroup_triggered` two-signal contract in
`agents/megaphone-notes.md`. Those files' raycast/animation/feedback
mechanics are still a fine starting point to adapt — only the
click-vs-hold-timer decision logic and the button mapping are being
replaced.

## Why

Current behavior: right-click either fires a single À L'ATTAQUE! at a
raycast point, or (if held past a threshold) Regroups the crowd to the
player — two signals, picked by a hold-duration cutoff, with no visual cue
beforehand about which one you're about to trigger or where it'll land.

New behavior: the reticle always shows what will happen *before* you click,
and attack/regroup collapse into one command because they're the same
thing underneath — "send some share of the mob to a position." The only
branch is what that position is:

- Aiming at an interactable object (currently: anything in the
  `"destructible"` group, e.g. the dumpster/trash-can prop from
  `scripts/destructible_prop.gd`) → reticle draws a contour/outline around
  that object. Sending commits NPCs to attack/interact with it.
- Aiming at anything else (ground, wall, empty air, a non-interactable
  prop) → reticle shows a plain marker (currently speccing it as a small
  yellow ball) instead of an outline. Sending Regroups that same share of
  NPCs to the player — *not* to the aimed-at empty point. This is the
  fallback case, visually distinct so the player always knows up front
  whether their click lands on something or just calls the mob home.

## Button mapping change

- **Recruit moves to hold Right Click** (was hold Left Click).
- **Send Mob (attack/regroup, unified) moves to hold Left Click** (was
  Right Click for attack, hold-Right-Click for regroup).

Swap only the two input actions' bound buttons in `project.godot`
(`recruit`, `attack_command` — consider renaming the latter to something
button-neutral like `send_mob` once it's genuinely one command) and the
corresponding raise/shake/cone-visibility code paths in `Megaphone.gd`;
the recruitment-cone and raycast *logic* itself doesn't need to change,
only which input action drives which behavior.

## Hold-to-charge send percentage

Replace the old binary short-click/hold-threshold with a continuously
ramping commit percentage:

- Press and hold Send Mob: a committed share ramps from 0% toward 100%
  the longer it's held (exact curve/duration TBD during implementation —
  start linear over ~1-1.5s and tune by feel). Surface this ramp on the
  reticle/HUD (e.g. a filling ring or percentage readout) so the player
  can see what they're about to commit.
- A quick tap sends a small floor percentage rather than 0 (so a tap still
  does something useful) — exact floor TBD, e.g. ~10%.
- Release commits `round(percentage * recruited.size())` NPCs to whatever
  the reticle was showing at release time (outline target → attack that
  object; yellow-ball fallback → regroup to player).
- If `recruited` is empty, nothing happens (no crowd to send).

## Rotating selection pointer (which NPCs get picked)

A partial-percentage send must not always draw from the same front slice
of `recruited`, or repeated 50% sends would just ping-pong the same two
halves split at a fixed boundary. Instead, keep one rotating cursor over
the recruited list and advance it by exactly however many NPCs were just
sent:

- `CrowdController` keeps a single `_send_pointer: int` index into
  `recruited` (persists across commands, not reset per-send).
- On send: `count = round(percentage * recruited.size())`, clamped to
  `[0, recruited.size()]`. Select `count` NPCs starting at `_send_pointer`,
  wrapping around the end of the array back to index 0 if the slice runs
  off the end (so the list is treated as a ring, not a bounded array).
- After selecting, advance `_send_pointer = (_send_pointer + count) %
  recruited.size()` (guard the empty-list case) — so the *next* send
  starts exactly where this one left off, never re-including the just-sent
  NPCs unless the pointer has wrapped all the way around again.
- Worked example from the spec conversation: mob of size N, three
  consecutive 50% sends. Send 1 takes indices `[0, N/2)`, pointer moves to
  `N/2`. Send 2 takes `[N/2, N)` (the *other* half — the previously unsent
  one), pointer wraps to `0`. Send 3 takes `[0, N/2)` again — same as send
  1, because the pointer has now cycled all the way around. This holds
  regardless of command type (attack vs. regroup) and regardless of
  whether `recruited`'s membership changed in between (new recruits just
  extend the ring; the pointer still advances by count, so it keeps
  rotating through whoever is currently in the list rather than tracking
  specific NPC identities).
- NPCs not selected by a given send simply keep doing whatever they were
  already doing (stay in FOLLOW if they were following, keep charging/
  regrouping toward their existing destination if a previous send is still
  resolving) — a send only reassigns the NPCs it selects this time.

## Open questions for the implementation pass

- Exact outline/contour rendering technique for the interactable highlight
  (shader-based silhouette vs. a simple bounding-box wireframe vs. a
  duplicate-mesh outline pass) — not decided here, pick whatever's cheap
  and reliable in Godot 4.7 given no display access in this dev
  environment to iterate visually.
- Exact yellow-ball reticle visual (3D marker in world space at some fixed
  distance along the look ray, vs. a 2D HUD/crosshair icon) — TBD.
- Ramp curve and timing constants, and the tap-floor percentage — TBD,
  tune by feel once playable.
- Whether "interactable" should be generalized beyond the `"destructible"`
  group (e.g. a future bus/plaza/barricade target per vision.md's
  "Secondary Mechanics") or left as-is for now — out of scope until those
  target types exist.

## Implementation

- **Input rebind** (`project.godot`): `recruit` action moved to right mouse
  button (was left), the old `attack_command` action renamed `send_mob` and
  moved to left mouse button (was right). No new input actions added.
- **`addons/fps_controller/Megaphone.gd`**: the two signals
  (`attack_command_triggered`, `regroup_triggered`) collapsed into one
  `send_mob_triggered(percentage: float, target: Node3D)`. `_process()` now
  re-raycasts every frame (`_raycast_destructible()`, same raycast as the
  existing `_raycast_target()` but returns the hit `Node3D` only if
  `is_in_group("destructible")`) to track `_aim_target`, calling
  `set_targeted(true/false)` on whichever `DestructibleProp` is
  gaining/losing the aim so only one is ever outlined. While `send_mob` is
  held, percentage ramps linearly from `send_tap_floor_percentage` (0.1) to
  1.0 over `send_ramp_duration_msec` (1200ms) — read live by a new
  `ChargeLabel` showing e.g. "45%". Release calls the single
  `_do_send_mob(percentage, target)`, which branches only on cosmetic
  feedback (flash + red marker for an attack, blue label for the
  regroup-fallback) before emitting the one signal.
- **`addons/fps_controller/Megaphone.tscn`**: added `ReticleDot` (small
  centered yellow Label, `"●"`) and `ChargeLabel` (centered percentage
  readout) under `UILayer`. `ReticleDot` is hidden whenever `_aim_target`
  is non-null (the object's own outline is the indicator instead).
- **`scripts/destructible_prop.gd` / `scenes/destructible_prop.tscn`**: new
  `Outline` `MeshInstance3D` sibling of `HealthBar`/`DumpsterModel` — a
  `BoxMesh` ~15% larger than the collision box, translucent additive-yellow
  unshaded material, `cull_mode = DISABLED`. Hidden by default;
  `DestructibleProp.set_targeted(bool)` toggles it. This is the "cheap
  bounding-box outline" option from the open questions above, not a
  shader-based silhouette — swap it later if it doesn't read well.
- **`scripts/crowd_controller.gd`**: single `_on_send_mob(percentage,
  target)` replaces the old `_on_attack_command`/`_on_regroup` pair and the
  proximity-based `_find_destructible_near()` (no longer needed — the
  reticle already identifies the exact target node, so
  `attack_target_pick_radius` was removed as dead config). New
  `_send_pointer: int` + `_take_ring_slice(count)` implement the rotating
  selection: takes `count = round(percentage * recruited.size())` NPCs
  starting at the pointer (wrapping), advances the pointer by `count`.
  `target != null` → selected NPCs `enter_charge()` toward the target's
  position (unchanged scatter/damage logic otherwise); `target == null` →
  selected NPCs `enter_regroup()` toward the player.
- `scripts/npc.gd` untouched — `enter_charge()`/`enter_regroup()` already
  matched this contract.

### Verification

```
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --quit-after 10
```

Clean: no parse/script errors (checked explicitly by grepping the log for
error/parse markers, since the usual leaked-RID/ObjectDB headless-teardown
noise documented elsewhere in `agents/` would otherwise mask a real error).
Also did a one-off `print_tree_pretty()` in `scenes/test_map.gd`'s `_ready()`
(reverted after) to confirm, per CLAUDE.md's rule on verifying live scene
trees: `Outline` is correctly nested as a sibling under each
`DestructibleProp` instance (not duplicated or misplaced), and
`ReticleDot`/`ChargeLabel` are correctly nested under
`Megaphone/UILayer` alongside the existing `Flash`/`FeedbackLabel`.

**Not verified — no display access in this environment:** how the outline
actually looks (whether a 15%-larger unshaded box reads as a "contour" or
just a glowing halo), reticle dot visibility/placement, whether the 1200ms
ramp and 10% tap floor feel right, and whether swapping which mouse button
does what feels natural. **Someone needs to run `task run`**: confirm right
‑click now recruits and left-click is Send Mob, aim at the dumpster and
confirm it outlines (and the yellow dot disappears), hold left-click and
watch the `%` readout climb, release while aiming at the dumpster vs. aiming
at empty space/wall and confirm attack vs. regroup fires correctly, and try
three consecutive ~50% sends to confirm the rotating pointer actually
alternates which half of the mob goes each time.
