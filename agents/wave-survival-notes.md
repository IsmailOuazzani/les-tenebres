# Wave-survival rewrite: integration contract

Per vision.md's wave-survival rewrite. This file is the **contract between
the wave system and the upgrade system**, written up front so the two can be
built independently. Both are autoloads, matching the existing `GameState`
run-state-singleton pattern (`project.godot` `[autoload]`).

## Already done (do not re-do, do not edit `scripts/game_state.gd`)

`GameState` has been migrated off the old decay meter:

- `grabuge_available: float` — spendable balance. Earn via `add_grabuge()`,
  spend via `spend_grabuge(amount) -> bool`.
- `grabuge_total_earned: float` — monotonic lifetime total. **This** is what
  civilian spawn scaling reads, so purchases never shrink the recruit pool.
- `grabuge_changed(new_available, new_total_earned)` — note: **two** args now.
- `GRABUGE_SCALE_REFERENCE: float = 100.0` — soft reference for spawn-curve
  scaling only; replaced the old hard `GRABUGE_MAX`.
- `police_defeated_count: int` — run total, for the Act scoreboard.
- Grabuge no longer decays and no longer ends the run. The only game-over is
  `trigger_player_death()`, already wired from the player's HealthComponent
  in `scenes/test_map.gd`.

## WaveManager (`scripts/wave_manager.gd`, autoload `WaveManager`)

```gdscript
enum State { PREPARING, ACTIVE, INTERMISSION, ACT_COMPLETE }

signal wave_started(wave_number: int, police_total: int)
signal wave_completed(wave_number: int)
## Fired right after wave_completed: the upgrade station should open here.
signal intermission_started(next_wave_number: int, duration: float)
signal intermission_finished
signal act_completed(act_number: int)
## Pre-assault audiovisual warning, per vision.md ("clear audiovisual
## warning signals for incoming police").
signal threat_warning(message: String)

var state: State
var current_act: int        # 1-based
var current_wave: int       # 1-based, within the current Act
var wave_time_left: float
var wave_duration: float

## {wave: int, police: int, assault: bool} -- feeds the between-wave
## "next wave" preview.
func get_next_wave_preview() -> Dictionary

## Called by the upgrade station's Continue button to leave the paused
## shop and begin the live pre-wave countdown.
func begin_intermission_countdown() -> void

func reset() -> void
```

Waves are **time-based**: surviving `wave_duration` completes the wave;
leftover cops despawn during the transition. Police spawning is driven
entirely by WaveManager — **not** by Grabuge.

## UpgradeManager (`scripts/upgrade_manager.gd`, autoload `UpgradeManager`)

```gdscript
signal upgrade_purchased(id: StringName, new_level: int)

## Multipliers, all start at 1.0. Read by whoever owns the stat.
var player_speed_mult: float
var player_jump_mult: float
var crowd_speed_mult: float
var crowd_health_mult: float
var crowd_damage_mult: float
## Flat bonus HP added to the player's max_health (not a multiplier).
var player_bonus_health: float

## One entry per upgrade:
## {id, name, description, price, level, affordable}
func get_upgrades() -> Array[Dictionary]
func purchase(id: StringName) -> bool
func reset() -> void
```

Upgrade ids: `&"player_speed"`, `&"player_jump"`, `&"player_health"`,
`&"crowd_speed"`, `&"crowd_health"`, `&"crowd_damage"`.

**Crowd multipliers must apply to NPCs spawned later**, not just living
ones — `scripts/npc_spawner.gd` trickles in civilians for the whole run, so
`scripts/npc.gd._ready()` reads the multipliers at spawn time. Purchases
also retro-apply to already-recruited NPCs.

## Known gotchas

- `addons/fps_controller/Sprint.gd` caches `normal_speed` from
  `controller.speed` in its `_ready()`. A speed upgrade that only writes
  `controller.speed` gets clobbered the next time the player releases
  sprint. Sprint's cached value has to be updated too.
- Player stats live in the **vendored** addon (`MovementController.gd`
  `speed`/`jump_height`, `Player.tscn` `HealthComponent.max_health = 100`).
  Prefer applying upgrades from outside the addon where practical, the way
  `scenes/test_map.gd` already wires player death without touching
  `Player.tscn`.
- There are **two** crowd damage paths: `npc.gd.damage_per_second` (melee vs
  cops) and `crowd_controller.gd.attack_damage_per_second` (Send Mob vs a
  targeted object/cop). `crowd_damage_mult` applies to both.
- Screens that must work while `get_tree().paused` is true need
  `process_mode = PROCESS_MODE_ALWAYS`.
- `scripts/game_over.gd`'s restart handler calls `GameState.reset()`; it
  must also call `WaveManager.reset()` and `UpgradeManager.reset()`, since
  autoloads survive `reload_current_scene()`.

## WaveManager implementation notes (wave-survival agent)

Implemented `scripts/wave_manager.gd`, rewrote `scripts/police_spawner.gd`
to be wave-driven, fixed `scripts/npc_spawner.gd`'s dead Grabuge refs, added
wave/currency HUD elements, and built `scenes/act_complete.tscn` +
`scripts/act_complete.gd`.

**API matches the contract exactly** (enum State, all 6 signals,
`current_act`/`current_wave`/`wave_time_left`/`wave_duration`,
`get_next_wave_preview()`, `begin_intermission_countdown()`, `reset()`).

**One deviation, clearly additive, not a contract change:** added
`WaveManager.start_next_act()`. The contract's public API has no method to
actually begin the next Act after `act_completed` fires -- `reset()`
restarts from Act 1, and nothing else advances `current_act`. The
Act-complete scoreboard's Continue button (vision.md: "clear feedback
before proceeding to a harder Act") needed something to call, so this was
added rather than overloading `begin_intermission_countdown()` (which is
specifically the INTERMISSION -> ACTIVE transition and no-ops outside that
state). Only acts while `state == ACT_COMPLETE`.

**PoliceSpawner's new public surface**, replacing the old Grabuge-rate
`_process` loop: `begin_wave(total_police: int, duration: float)` (spreads
spawns evenly across `duration`), `stop_spawning()` (stops handing out new
spawns, leaves live cops alone), `clear_all_police()` (despawns everyone
immediately -- called by WaveManager on every wave transition, since
waves are time-based and leftover cops should retreat/despawn rather than
carry over). Added `min_player_distance` (export, default 10.0) as a hard
floor independent of `spawn_radius_min`/`max`, per vision.md's "never
unfairly appear directly on top of the player" -- candidates closer than
this re-roll before the existing off-camera preference is even checked.
Spawner now self-registers into group `&"police_spawner"` in `_ready()`,
mirroring `crowd_controller.gd`'s `&"crowd_controller"` pattern; WaveManager
finds it via `get_tree().get_first_node_in_group(...)`.

**npc_spawner.gd fix:** civilian trickle rate now reads
`GameState.grabuge_total_earned` (monotonic), not `grabuge_available`
(spendable, rises/falls with upgrade purchases) -- using the spendable
balance would make buying an upgrade instantly shrink the recruit pool,
which is exactly the bug the total/available split exists to prevent.
`GRABUGE_MAX` -> `GRABUGE_SCALE_REFERENCE` (same soft-cap clamp behavior,
new name).

**HUD:** `GrabugeBar` ProgressBar removed entirely (a bounded bar doesn't
make sense for unbounded currency) -- `GrabugeLabel` now reads
`"⚡ %d  (earned %d)"`. Added `WaveLabel` (top-center, shows `Wave N` during
PREPARING, `Wave N  MM:SS` while ACTIVE), a `WaveBannerAnchor` that flashes
`WAVE N CLEARED` for 2.5s on `wave_completed` then fades, an
`IntermissionAnchor` showing the live `Next: Wave N (assault/normal, ~X
police) in MM:SS` countdown (visible only once
`begin_intermission_countdown()` has actually started counting -- see
gotcha below), and a `ThreatAnchor` that flashes `threat_warning`'s message
in red for 3s. All four are plain Controls under HUD's existing `Root`,
reusing `PanelContainerPrimaryFlat`/`PanelContainerDefaultFlat` theme
variants already in `main_theme.tres` -- no new StyleBoxes.

**Gotcha: autoload `_ready()` ordering.** `WaveManager._ready()` starts
wave 1 (and emits `wave_started`) before `scenes/hud.tscn` even exists,
since autoloads are added to the tree before the main scene. HUD can't
catch that first signal -- it connects to all WaveManager signals in its
own `_ready()` for *future* transitions, then calls
`_sync_wave_label_from_current_state()` to read `WaveManager.current_wave`/
`state` directly for the already-in-progress first wave. Any other UI that
needs to reflect WaveManager state on scene load should do the same rather
than assuming it'll see the first signal.

**Gotcha: intermission countdown doesn't start on `intermission_started`.**
`wave_time_left`/`wave_duration` are set to `INTERMISSION_DURATION` the
moment `intermission_started` fires (so `get_next_wave_preview()` and UI
have a value to show immediately), but the actual countdown only ticks
once `begin_intermission_countdown()` is called (an internal
`_intermission_counting` flag gates `_process()`), since the upgrade
station is paused and shouldn't be racing a live timer underneath it.

**Verification performed** (CLAUDE.md rule -- not just "project parses"):
ran `task run-headless`, confirmed no new script errors in
`logs/run-headless.log` (only pre-existing unrelated warnings:
`blood_effect` UID resource path, `CompassBar.parent` not set until HUD
wires it). Wrote and ran two throwaway `_debug_*.gd` `SceneTree` scripts
(deleted after use, per the brief):
- One instantiated `test_map.tscn`, ran `print_tree_pretty()` to confirm
  `PoliceSpawner` and the new `ActComplete` instance actually exist as
  direct children of `TestMap` (not duplicated/misplaced by hand-editing
  the generator-built `test_map.tscn`), confirmed `PoliceSpawner` is in
  `&"police_spawner"` post-`_ready()`, then manually drove
  `WaveManager._process(1.0)` in a loop through wave 1 -> completion ->
  `begin_intermission_countdown()` -> wave 2, then all the way through
  wave 5 -> `act_completed`, then called `ActComplete`'s own
  `_on_continue_pressed()` to verify `start_next_act()` actually begins Act
  2 (`wave_duration` correctly increased from 45.0 to 55.0 via
  `WAVE_DURATION_PER_ACT`), then `reset()` back to Act 1/Wave 1. All
  signals fired in the right order with the right payloads (confirmed
  `threat_warning` fires on wave 3, the first assault wave; police counts
  matched `_police_count_for()`'s escalation math).
- Autoloads aren't resolvable as compile-time global identifiers when a
  script is run directly via `--script` (confirmed:
  `SCRIPT ERROR: Compile Error: Identifier not found: WaveManager`) --
  fetched them via `get_root().get_node_or_null("WaveManager")` instead,
  matching the existing `_debug_verify_audio.gd` pattern. Worth knowing for
  any future headless debug script.
- A second script instantiated `test_map.tscn` and manually ticked
  `PoliceSpawner._process()` directly (the first script only stepped
  WaveManager, so no real spawns happened there) to confirm `begin_wave(6,
  3.0)` actually spawns 6 live `Police` nodes spread over the window,
  every spawn landed >= `min_player_distance` (10.0) from the player
  (observed closest was 14.4), `stop_spawning()` stops new spawns without
  touching the live ones, and `clear_all_police()` frees them all.
- `grep -rnE "GameState\.(grabuge\b|peak_grabuge|GRABUGE_MAX)" scripts
  scenes` returns no matches.

**Still needs wiring (left for integration / the other agent):**
`WaveManager.intermission_started`/`intermission_finished` need a
listener on the upgrade-station side to actually open/close the paused
shop and call `begin_intermission_countdown()` when its Continue button is
pressed -- this file only emits/consumes those signals, it doesn't own the
shop UI. `scenes/upgrade_screen.tscn`/`scripts/upgrade_screen.gd` already
exist (built by the other agent) but weren't touched here since I don't
own them; whoever finishes that screen should confirm it calls
`WaveManager.begin_intermission_countdown()` on Continue.

## UpgradeManager implementation notes (upgrade-system agent)

Implemented `scripts/upgrade_manager.gd` (API matches the contract exactly:
`upgrade_purchased(id, new_level)`, the 5 multipliers + `player_bonus_health`,
`get_upgrades()`, `purchase()`, `reset()`), built
`scenes/upgrade_screen.tscn` + `scripts/upgrade_screen.gd` (new), and wired
player/crowd upgrade application into `scenes/test_map.gd`, `scripts/npc.gd`,
`scripts/crowd_controller.gd`.

**Pricing/tuning (all named consts at the top of upgrade_manager.gd, per
CLAUDE.md's "configurable numbers" rule):** base prices exactly as suggested
in the brief (player_speed 40, player_jump 40, player_health 60, crowd_speed
50, crowd_health 50, crowd_damage 70), `PRICE_GROWTH = 1.5` per level
(`price = base * 1.5^level`). Effect steps match vision.md's table exactly
(+10%/+15%/+20HP/+10%/+20%/+15%). Every multiplier/bonus is *derived* from a
level each purchase (`1.0 + STEP * level`, or `STEP * level` for the flat
health bonus) rather than multiplied in place -- this is what guarantees
repeat purchases never compound onto an already-multiplied value.

**No contract deviations.** `get_upgrades()` entries use exactly the
`{id, name, description, price, level, affordable}` shape; `purchase()`
returns false and changes nothing (confirmed in verification below) when
`GameState.spend_grabuge()` can't afford it.

**Sprint gotcha, solved exactly as flagged in "Known gotchas" above:**
`scenes/test_map.gd` captures `_base_player_speed`/`_base_sprint_speed` once
in `_ready()` (before any upgrade), then on every `player_speed` purchase
sets **both** `MovementController.speed` (roundi'd -- it's a statically
typed `int` on the vendored script) **and** `Sprint.normal_speed` (the
cached copy Sprint's own `_physics_process()` writes back to
`controller.speed` every frame the player isn't holding sprint -- missing
this silently reverts the upgrade on sprint release). Also scaled
`Sprint.sprint_speed` by the same multiplier so sprinting benefits too.
`Sprint.gd` has no `class_name`, so the `_sprint` var in test_map.gd is
deliberately left untyped (not `: Node`) -- typing it would make
`.normal_speed`/`.sprint_speed` a static-analysis error since those
properties don't exist on the `Node` base class; leaving it untyped lets
GDScript resolve them dynamically at runtime instead.

**max_health-signal problem, solved by emitting the signal from outside:**
`health_component.gd` (not ours to edit) only emits `health_changed` from
`take_damage()` -- there's no raise-max/heal method. Both
`scenes/test_map.gd` (`player_health`) and `scripts/npc.gd`
(`_apply_crowd_upgrades()`) mutate `max_health`/`current_health` directly
and then call `health.health_changed.emit(current, max)` themselves.
Emitting a node's own public signal from outside its script is unusual but
is the only path that gets the HUD's (and NPC's own) health bar to redraw
without touching `health_component.gd`. Worth another agent's eyes if a
cleaner convention emerges later (e.g. a `heal()`/`set_max_health()` method
on `HealthComponent` itself), but out of scope here since that file is
owned elsewhere.

**Crowd upgrades, applied without touching `npc_spawner.gd`:** each `npc.gd`
instance captures its own `_base_move_speed`/`_base_damage_per_second`/
`_base_max_health` in `_ready()` (before applying any multiplier), applies
the current crowd multipliers immediately at spawn (so NPCs spawned by the
trickle spawner *after* a purchase arrive already upgraded -- confirmed in
verification), and also connects to `UpgradeManager.upgrade_purchased`
itself so every already-living NPC retroactively rescales on every future
purchase too (no group/loop needed from outside -- each NPC reacts to the
signal on its own). On a health-upgrade retro-apply, current_health is
raised by exactly the max-HP *increase* (not reset to full), so an
already-damaged NPC still gets the benefit without an uncosted full heal.
`crowd_controller.gd`'s `attack_damage_per_second` (the Send Mob damage
path) is handled the same way: base captured once, rescaled on
`crowd_damage` purchases via its own `upgrade_purchased` listener.

**Upgrade screen:** `scenes/upgrade_screen.tscn` is a `CanvasLayer`
(`process_mode = PROCESS_MODE_ALWAYS`), same pause/mouse-mode conventions as
`scenes/game_over.gd`. Opens on `WaveManager.intermission_started`, closes
via a "Ready" button that calls `WaveManager.begin_intermission_countdown()`
-- the exact handoff call from the contract. Cards are built entirely in
`_rebuild_cards()`/`_build_card()` from `UpgradeManager.get_upgrades()` (no
scene-authored card nodes), using only existing `main_theme.tres`
`theme_type_variation`s (`PanelContainerDefaultFlat`, `ButtonPrimary` when
affordable, `ButtonPlain` + `disabled = true` when not) -- no new
StyleBoxes. Rebuilds live on both `GameState.grabuge_changed` and
`UpgradeManager.upgrade_purchased` (both fire from the same `purchase()`
call) so the whole screen refreshes without closing, letting the player buy
multiple upgrades in a row.

**Node to wire into `scenes/test_map.tscn`** (left for whoever owns that
file, per the brief): instance `res://scenes/upgrade_screen.tscn` as a
direct child of `TestMap`, same sibling level as `HUD`/`GameOver`/
`ActComplete` (e.g. `[node name="UpgradeScreen" parent="." instance=ExtResource("...")]`,
no exported properties need setting -- it resolves `WaveManager`/
`UpgradeManager`/`GameState` as autoloads and finds its own `%`-unique-named
children internally).

**Verification performed** (CLAUDE.md rule): ran `task run-headless`,
confirmed no new script errors (only the same pre-existing unrelated
warnings the WaveManager notes above already call out). Wrote and ran a
throwaway `scripts/_debug_upgrade_verify.gd` `SceneTree` script (instantiated
`test_map.tscn`, awaited frames, deleted after use) that:
- Dumped `print_tree_pretty()` and read `Player`, `Player/Sprint`,
  `Player/HealthComponent`, `NPCSpawner`, `CrowdController` off the real
  runtime tree (not assumed paths).
- Confirmed `purchase()` with 0 Grabuge returns `false` and changes neither
  `_levels` nor `grabuge_available`.
- Purchased all 6 upgrades once and confirmed every live value matched the
  expected math exactly: `controller.speed` 10->11, `jump_height` 10->12,
  `sprint.normal_speed` 10->11 (**the gotcha, confirmed fixed** --
  explicitly re-simulated by calling `Sprint._physics_process()` directly
  after clobbering `controller.speed` to a junk value, and it correctly
  reset to the upgraded `normal_speed`, not the junk value or the
  pre-upgrade value), `sprint.sprint_speed` 16->18, player
  `max_health` 100->120 with `current_health` healed +20, NPC `move_speed`
  4.0->4.4, `damage_per_second` 5.0->5.75, `max_health` 25.0->30.0 (with
  `current_health` gaining the +5 delta, not reset to full), and
  `crowd_controller.attack_damage_per_second` 1.0->1.15.
- Bought `player_speed` a second time and confirmed `controller.speed`
  landed at exactly 12 (`10 * (1 + 2*0.10)`), not a compounded
  11 * 1.10 = 12.1 or worse -- confirms multipliers derive from base, not
  from the live value.
- Spawned a fresh NPC *after* all the crowd purchases above and confirmed it
  arrived already at move_speed 4.4 / damage 5.75 / max_health 30.0 (full
  health), proving future spawns inherit current multipliers rather than
  diluting the crowd average.
- Called `UpgradeManager.reset()` and confirmed all 5 multipliers returned
  to 1.0 and `player_bonus_health` to 0.0.
- Instantiated `upgrade_screen.tscn` directly (not via the WaveManager
  signal, per the brief's fallback guidance) and called `open(3)`/`close()`
  itself: confirmed `visible`/`get_tree().paused`/`Input.get_mouse_mode()`
  flip correctly on both ends, card count is 6, clicking a card's Buy button
  (found by walking the tree for the first `Button`, since cards are built
  in code with auto-generated node names) spends Grabuge and the screen
  stays open with the same 6-card count after rebuilding, and `close()`
  calls `WaveManager.begin_intermission_countdown()` (observed as a correct
  no-op here since `WaveManager.state` was still `ACTIVE`, not
  `INTERMISSION`, this early in a fresh run -- confirms the call signature
  is right without needing to drive a full wave to completion in this
  script, since the WaveManager agent's own verification above already
  covers that transition in depth).
- Also hit the same `--script` SceneTree autoload-resolution gotcha the
  WaveManager notes call out (`Identifier "GameState" not declared`) --
  fetched `GameState`/`UpgradeManager`/`WaveManager` via
  `get_root().get_node("...")` instead.

## Integration findings (orchestrator)

Both systems were built in parallel and each verified in isolation. The
integration pass found two bugs that isolated verification could not catch,
plus one rounding limitation worth knowing about.

**1. Wave 1 spawned zero police (game-breaking, fixed).**
`WaveManager` is an autoload, so its `_ready()` -- which starts wave 1 --
runs BEFORE the main scene is instanced. At that moment nothing has joined
the `&"police_spawner"` group, so `_begin_spawning()`'s `if spawner != null`
guard silently swallowed the very first wave's spawn order. The wave timer
counted down normally, so nothing looked wrong: wave 1 was just a free
45-second wave with no enemies. The wave agent's own test called
`PoliceSpawner.begin_wave()` directly and therefore never exercised the real
boot path. Fixed with `_pending_spawn_request` + `_flush_pending_spawn_request()`
retried from `_process()`, mirroring `crowd_controller.gd`'s lazy
`_find_megaphone()` resolve, which exists for the identical reason. This is
exactly the failure mode CLAUDE.md's scene-tree rule warns about -- "no
errors" proved nothing here.

**2. Assault warning fired after the ambush started (fixed).**
`threat_warning` was emitted `ASSAULT_WARNING_LEAD_TIME` seconds *into* the
assault wave, i.e. a warning received mid-ambush. Moved into
`begin_intermission_countdown()` so it lands during the live pre-wave
countdown, while the player can still recruit and reposition in response --
per vision.md's "warnings appear before dangerous attacks."

**3. Player stat upgrades are quantized by the vendored addon's int typing.**
`MovementController.speed` and `jump_height` and `Sprint.sprint_speed` are
all `int`. Jump +15% on a base of 10 computes 11.5 and rounds to 12, so the
first jump purchase is effectively +20%; sprint 16 -> 17.6 rounds to 18.
Values stay correct and non-compounding at higher levels (speed level 2 is
exactly 12), but small percentages on small int bases will keep rounding
visibly. Fixing properly means floats in the vendored addon -- deliberately
not done, since addons/ is vendored.

**Verified end to end on the real boot path** (`scripts/_debug_verify_wave_boot.gd`,
`_debug_verify_wave_loop.gd`, `_debug_verify_player_upgrades.gd`,
`_debug_verify_crowd_upgrades.gd`, all kept as regression checks):
wave 1 spawns -> timer completes -> cops cleared on transition -> shop opens
and pauses -> purchases spend available Grabuge while `grabuge_total_earned`
stays put -> `close()` unpauses and hands back -> wave 2 starts and spawns 6.
Player speed survives repeated `Sprint._physics_process()` frames (the
`normal_speed` clobber is handled). Crowd buffs retro-apply to living NPCs
AND are inherited by NPCs spawned afterward. No compounding on repeats,
insufficient funds rejected, `reset()` clears everything.

**Known gap, not addressed:** there is no prepare phase before wave 1 --
`WaveManager._ready()` goes straight to ACTIVE, so the player never gets
vision.md loop step 1 ("Prepare: recruit civilians, position your mob") on
the first wave. `State.PREPARING` exists but is only a transient bookkeeping
value. Adding a pre-wave grace countdown is a small change to `_ready()` and
the HUD's PREPARING display.

---

## Multiplayer integration (merge of the `lan-multiplayer` branch, 2026-11-14)

The LAN co-op branch was cut before this rewrite existed, so the merge put
the wave loop on top of a server-authoritative networking layer. Only the
seams that touch this feature are listed here; the full account is in
`agents/multiplayer-notes.md` § 11.

* **WaveManager is now server-authoritative shared state** (one wave, one Act
  for everybody). It no longer starts the run in `_ready()`; `test_map.gd`
  calls `WaveManager.start_run()` once every peer has loaded and spawned.
  Clients get a 10 Hz state push plus one reliable RPC per phase transition.
* **UpgradeManager is shared and server-authoritative.** A client's
  `purchase()` is a request and returns `false` even when it will succeed —
  refresh off `upgrade_purchased` / `grabuge_changed`, not the return value.
  Per-player upgrade sets were rejected because the crowd is simulated only
  on the server, so a client's crowd upgrades would do nothing.
* **The shop and the Act scoreboard do not pause the tree in multiplayer**
  (pausing the listen server freezes everyone's simulation), and neither
  closes itself on its button press any more: they close on the WaveManager
  transition that comes back. In single-player that is the same frame, so the
  behavior described above is unchanged.
* **Player upgrades are applied to the locally owned character**, resolved
  when it spawns (`test_map.gd::_bind_local_player()`), not via an `@onready`
  path to a `Player` node — characters are spawned at runtime now. Upgrades
  bought before a (re)spawn are re-applied on bind.
* `PoliceSpawner._spawn_police()` returns a bool and the wave quota is only
  decremented on success, since in the multiplayer respawn window there may
  be no living player to spawn a cop around.

---

## Kill-gated waves rewrite (2026-11-14)

Per vision.md's "Call of Duty Zombies" inspiration and Design Pillar 5
("escalating tension, not a ticking clock"), waves are no longer time-based.
**This supersedes the "Waves are time-based" line in the contract above and
every `wave_duration`-based claim in the WaveManager implementation notes
above it** -- those sections are left as a historical record of the original
build, not current behavior.

**New contract:**

- `WaveManager.wave_time_left`/`wave_duration` now mean the live
  **intermission** countdown only. They are meaningless during `ACTIVE` --
  don't read them for wave progress.
- `WaveManager.police_remaining: int` (new) -- queued-to-spawn plus
  currently-alive cops for the current wave. This is what the HUD and
  replication now use for ACTIVE-state feedback. Pushed via the same 10 Hz
  `_apply_wave_state` RPC and set on `wave_started`/`_apply_wave_started`.
- A wave completes when `police_remaining` hits 0, i.e. every cop for the
  wave has been both spawned and killed (`PoliceSpawner.has_any_police_left()
  == false`), checked every `ACTIVE` frame in `_process_active()`. No clock
  drives this any more.
- `PoliceSpawner.begin_wave(total_police: int, megacop_count: int = 0)` --
  dropped the `duration` parameter. Spawns now trickle in capped at
  `max_alive` (new `@export`, default 10) live cops at once, refilling one
  at a time (`SPAWN_COOLDOWN = 0.6s` between attempts) as the cap frees up,
  rather than being spread across a wave duration. This is the actual
  Zombies-style pressure mechanism: the player always has *something* to
  fight, and stalling doesn't thin the field.
- `PoliceSpawner.has_any_police_left() -> bool` and
  `get_police_left_count() -> int` (new) -- what WaveManager polls.
- Dropped entirely: `BASE_WAVE_DURATION`, `WAVE_DURATION_PER_ACT`,
  `SPAWN_WINDOW_FRACTION`, `ASSAULT_WARNING_LEAD_TIME`,
  `_assault_warning_fired`. The assault-wave warning now fires only from
  `begin_intermission_countdown()` (the pre-wave warning already in the
  contract) -- there is no more mid-wave second warning, since there's no
  duration-relative point in the wave left to time it against.

**HUD:** `scripts/hud.gd`'s `WaveLabel` now reads `Wave N  X left` during
`ACTIVE` (was `Wave N  MM:SS`), driven by `WaveManager.police_remaining`.
`INTERMISSION`'s countdown display is unchanged.

**Debug/regression scripts updated to match:**
`scripts/_debug_verify_wave_boot.gd`, `scripts/_debug_verify_wave_loop.gd`
(the wave-1-skip trick is now "drain the spawner's queue and clear live
police directly" instead of forcing `wave_time_left` to near-zero -- there's
no timer to force anymore), `scripts/_debug_net_client.gd` (asserts
`police_remaining` replicated instead of a countdown range).

**Why max_alive + cooldown instead of just "spawn everything, kill-gate the
wave":** without a cap, a 20-cop wave would still dump most of its cops in
the first second or two the way the old duration-compressed spawner did,
just without a timer backstop -- it would read as one burst fight rather
than a sustained siege. The cap is what actually produces the "they keep
coming" Zombies feel; the kill-gate alone only changes *when* the wave ends,
not how the police arrive.
