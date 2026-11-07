# Grabuge — Implementation Notes

Replaces the earlier Publicity/Patience system (`agents/publicity-patience-notes.md`,
now stale) with the single shared Grabuge resource described in `vision.md`.
Scope of this pass matches the original foundational spec's Stage 2 exactly:
one resource, passive decay, HUD meter, a debug key to bump it, and (new in
this pass) the megaphone recruitment cone scaling with it. **NPC dispersal
and game-over triggered by low Grabuge are explicitly NOT implemented** —
that's a separate, later pass.

## `scripts/game_state.gd`

- `publicity`/`patience` (two separate meters) → single `grabuge: float`
  (0–100), with `GameState.add_grabuge(amount)` as the one public entry
  point (positive raises it, negative lowers it — passive decay just calls
  this with a negative amount every `_process` tick).
- `recruit_npc()` and `record_disruption()` both now feed Grabuge directly
  instead of publicity+patience separately — this is intentional, per
  vision.md's "one resource, not separate meters."
- `game_over` signal is **still declared** (so `scripts/game_over.gd`'s
  existing listener doesn't break) but **nothing emits it anymore** — the
  old trigger was "patience reaches zero," and there's no Grabuge-equivalent
  trigger yet by design. The game-over screen is dormant until a future pass
  wires up dispersal.
- Balancing constants (`GRABUGE_DECAY_PER_SECOND`, `RECRUIT_GRABUGE_BONUS`,
  `DISRUPTION_GRABUGE_BASE`, `DEBUG_GRABUGE_BUMP`) are plain `const`s,
  matching this file's existing convention — not `@export`, since
  `GameState` is a script-only autoload (no backing `.tscn`), so `@export`
  wouldn't get a usable Inspector UI anyway without restructuring it as a
  scene-based autoload (out of scope for this pass).

## HUD (`scenes/hud.tscn` + `scripts/hud.gd`)

`PublicityLabel` + `PatienceLabel` + `PatienceBar` (3 nodes) → `GrabugeLabel`
+ `GrabugeBar` (2 nodes), both driven by one `GameState.grabuge_changed`
signal instead of two separate signals. Shrunk the HUD panel's bounding box
(`Margin` node's `offset_bottom` 120 → 90) to match the shorter content.

## Game-over stats (`scripts/game_over.gd` + `scenes/game_over.tscn`)

"Total publicity generated" → "Peak Grabuge reached: %d%%", backed by a new
`GameState.peak_grabuge` (tracked the same way `peak_crowd_count` already
was). Screen itself is unreachable right now since nothing emits
`game_over` (see above) — stats text is updated for whenever that gets
wired up.

## Debug key (`scenes/test_map.gd`)

`KEY_P` (`add_publicity`) → `KEY_G` (`add_grabuge(GameState.DEBUG_GRABUGE_BUMP)`,
20 per the original spec). `KEY_O`/`KEY_I` (recruit/disruption stand-ins)
kept as-is, but `KEY_O` is now largely redundant since real megaphone
recruitment (`scripts/crowd_controller.gd`'s `_recruit()`) already calls
`GameState.recruit_npc()` on its own — `KEY_O` is only useful now for
recruiting without needing to actually find a civilian in the cone.

## Megaphone recruitment cone (`addons/fps_controller/Megaphone.gd`)

Previously static (`agents/crowd-swarm-notes.md` flagged this as the thing
to fix once Grabuge existed). Now: `cone_range`/`cone_angle_degrees` are
computed, not exported directly — six new `@export`s
(`cone_range_at_0pct/50pct/100pct`, `cone_angle_at_0pct/50pct/100pct`) hold
the original spec's balancing table (6m/25° → 18m/50° → 35m/80°), and
`_on_grabuge_changed()` (connected to `GameState.grabuge_changed` in
`_ready()`) recomputes both via `_piecewise_lerp()` and rebuilds the mesh
every time Grabuge changes. Piecewise (not a single 0–100 lerp) because the
three keyframes aren't collinear — range's slope is steeper in the 50–100%
half than the 0–50% half, same for angle.

Note: right before this pass, someone had manually tuned the (then-static)
`cone_angle_degrees` default from 50° down to 26° in the editor — that's
now superseded by the dynamic 0% keyframe (25°, almost the same value),
which is presumably why that number felt right at low/no Grabuge.

## Verification

```
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --quit-after 10
```

Clean: no parse/script errors. Confirmed via headless log that
`GameState.grabuge` starts at 0, decays, and `add_grabuge` clamps correctly
(spot-checked by temporarily calling `add_grabuge(150)` and confirming it
clamps to 100 — removed after confirming).

**Not verified — no display in this environment:** HUD layout/readability,
whether the cone visibly grows/shrinks as Grabuge changes, and whether the
decay rate (`GRABUGE_DECAY_PER_SECOND = 1.5`) feels right pace-wise. Needs a
`task run` playtest: press `G` a few times, watch the HUD bar and the
megaphone cone (hold left-click) both grow, then watch them shrink as it
decays.
