# Publicity, Patience & Crowd Count: Meta-Systems

Implements the core meta-systems from `vision.md`'s "Publicity and
Recruitment" and "Losing Condition: Protester Patience" sections, plus the
game-over screen spec at the end of that section — as a global singleton,
a live HUD, and a game-over screen. **No real recruit/mob/disruption
gameplay is wired up yet** — this task deliberately stopped short of that
(separate parallel workstreams own recruit-on-click, mob-follow,
À L'ATTAQUE!/disruption resolution). Everything here is built and
demo-able via temporary debug keys (see below) so other systems can be
wired in later by just calling the `GameState` API from real gameplay code.

## GameState autoload (`scripts/game_state.gd`, registered as `GameState`)

Registered in `project.godot`'s `[autoload]` section:
```
[autoload]
GameState="*res://scripts/game_state.gd"
```
`*` = autoload with its own node in the scene tree (needed for `_process`
patience drain). Access anywhere in GDScript as `GameState.<member>`.

### State (read freely from anywhere, e.g. HUD bindings)
- `crowd_count: int` — current protester count, starts at `1` (the player
  counts as the first "protester" per vision.md's crowd framing).
- `publicity: float` — current publicity, starts at `0.0`.
- `patience: float` — current shared patience, starts at `100.0`, clamped to
  `[0, PATIENCE_MAX]` (`PATIENCE_MAX = 100.0`).
- `peak_crowd_count: int` — highest `crowd_count` ever reached this session.
- `total_disruptions: int` — lifetime count of `record_disruption()` calls.
- `total_publicity_generated: float` — lifetime publicity gained (not net of
  any future spending/decay of `publicity` itself, if that's ever added).

### Methods other systems should call
- `add_publicity(amount: float)` — add (or, with a negative amount, remove)
  publicity. Also accumulates into `total_publicity_generated` (positive
  amounts only).
- `recruit_npc()` — call when a civilian successfully joins the crowd.
  Increments `crowd_count` (and `peak_crowd_count` if it's a new high) and
  gives a small patience bump (`RECRUIT_PATIENCE_BONUS = 2.0`). **Does not**
  currently decrement the crowd on loss-of-NPC; that's for whatever system
  handles protesters leaving when patience is low (vision.md: "NPCs
  gradually begin leaving") — it should decrement `GameState.crowd_count`
  directly (no setter exists yet; it's a plain public var).
- `record_disruption(magnitude: float = 1.0)` — call on a successful
  disruption. Increments `total_disruptions`, adds
  `DISRUPTION_PUBLICITY_BASE * magnitude` publicity (`DISRUPTION_PUBLICITY_BASE
  = 15.0`), and gives a patience bump. `magnitude` is a stub scalar for
  "bigger, more ridiculous disruptions generate more publicity" — pass `1.0`
  until there's a real way to size a disruption.
- `get_session_duration() -> float` — seconds elapsed since the GameState
  node entered the tree (session start). Used for the game-over "protest
  duration" stat.
- `reset()` — resets all state back to initial values and re-starts the
  session timer. Not wired to anything yet (reloading the scene already
  recreates the autoload); kept for a possible future "restart without
  reload" flow.

### Signals
- `game_over` — emitted once, the first time `patience` hits `0`. After it
  fires, `_process` stops draining/modifying patience (`_game_over_fired`
  guard) so values freeze for the game-over screen to read.
- `publicity_changed(new_value: float)`, `patience_changed(new_value: float)`,
  `crowd_count_changed(new_value: int)`, `disruption_recorded(total: int)` —
  for UI/VFX to bind to instead of polling every frame.

### Patience drain (stub)
`_process()` drains patience at a hardcoded
`PATIENCE_DRAIN_PER_SECOND = 0.5` per second, unconditionally, any time the
game is running. This is **only a stub** for "decreases when nothing
interesting happens for too long" — it does not yet know whether anything
interesting *is* happening. Real version should likely replace the flat
drain with something like: drain only after N seconds since the last
recruit/disruption, and/or vary the rate based on separation/failed-command
events per vision.md's full patience-loss list. The constant is in one
place (`PATIENCE_DRAIN_PER_SECOND`) and easy to tune or replace.

## HUD (`scenes/hud.tscn` + `scripts/hud.gd`)

A `CanvasLayer` instanced directly inside `scenes/test_map.tscn`. Connects
to `GameState`'s three `_changed` signals on `_ready()` and updates three
`unique_name_in_owner` nodes: `%CrowdLabel`, `%PublicityLabel`,
`%PatienceBar` + `%PatienceLabel`. Purely a GameState consumer — no gameplay
logic, safe to leave in place as real systems land.

## Game-over screen (`scenes/game_over.tscn` + `scripts/game_over.gd`)

Also a `CanvasLayer` instanced in `test_map.tscn`, hidden until
`GameState.game_over` fires. On trigger: populates peak protesters, total
disruptions, formatted `M:SS` duration, and total publicity from
`GameState`, picks one random string from the hardcoded
`HUMOROUS_REASONS` list (placeholder per vision.md's "humorous reason for
the protest ending" — real version should eventually pick a reason tied to
what actually happened in the run), shows the panel, releases the mouse,
and pauses the tree (`get_tree().paused = true`). `process_mode = ALWAYS`
is set on the whole scene (and propagates to children) so the UI and its
Restart button still work while paused. Restart button unpauses and calls
`get_tree().reload_current_scene()`.

## Temporary debug keybinds (REMOVE once real gameplay lands)

Added directly in `scenes/test_map.gd`'s `_unhandled_input`, clearly marked
with a `# --- TEMPORARY DEBUG HOOKS ---` comment block:

| Key | Calls |
|---|---|
| `P` | `GameState.add_publicity(10.0)` |
| `O` | `GameState.recruit_npc()` |
| `I` | `GameState.record_disruption()` |

These exist purely so the HUD and game-over flow can be verified end-to-end
by playing and mashing keys, since no real recruit-on-click or
disruption-on-mob-action systems exist yet. **Delete this block** (and these
three keys are free again for other use) once the real recruit and
disruption systems call `GameState.recruit_npc()` /
`GameState.record_disruption()` themselves from actual gameplay triggers.
No new input actions were added to `project.godot` for these — they check
raw `event.keycode` so as not to pollute the project's input map with
throwaway bindings.

## What's a stub vs. real

- **Real / meant to last:** `GameState` autoload API and signals (`add_publicity`,
  `recruit_npc`, `record_disruption`, state vars, signals), HUD, game-over
  screen and its stats wiring.
- **Stub, expected to be replaced:**
  - Flat-rate patience drain in `_process` (no awareness of real activity).
  - `DISRUPTION_PUBLICITY_BASE`, `RECRUIT_PATIENCE_BONUS`, and the drain rate
    constant — reasonable-guess numbers, not tuned/playtested.
  - `HUMOROUS_REASONS` list — placeholder flavor text, not tied to actual
    run events.
  - The three debug keybinds in `test_map.gd` — delete once real triggers
    exist.
  - `crowd_count` starts at `1` and only ever increments via `recruit_npc()`;
    there's no decrement path yet for protesters leaving on low patience —
    whichever system implements that should just write `GameState.crowd_count`
    directly (and should probably emit `crowd_count_changed` itself, or ask
    for a `GameState.remove_npc()` method to be added if that's cleaner).

## Verification

Ran `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless
--quit-after 1` — project and main scene loaded with no parse errors. No
display available in this environment, so HUD/game-over layout, readability,
and visual polish are **unverified by eye** — please playtest with `task run`
and press `O`/`P`/`I` a bunch of times (holding `I` or `O` a few dozen times
drains... actually raises patience; just wait ~3+ minutes idle, or lower
`PATIENCE_DRAIN_PER_SECOND` temporarily, to see patience actually hit 0 and
confirm the game-over screen appears, pauses the game, shows correct stats,
and the Restart button reloads the scene).
