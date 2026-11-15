# Megacop

A bigger, harder-hitting `scripts/police.gd` variant. Built as
`scenes/megacop.tscn`, an **inherited scene** of `scenes/police.tscn` (same
script, no subclass) with overrides:

- `attack_range = 3.0` (base 1.5) -- doubling this also doubles the physical
  collision capsule radius for free, since `police.gd._apply_collider_ratio()`
  derives the capsule radius from `attack_range * collider_to_damage_ratio`
  at `_ready()`. Only the capsule *height* needed a direct override (3.2 vs
  1.6), since the script never touches that.
- `damage_per_second = 12.0` (base 6.0).
- `MeshRoot` scaled `(2,2,2)`; `Outline` capsule mesh and position doubled to
  match; `HealthBar` repositioned higher for the taller silhouette.
- Health intentionally **unchanged** (still 40) -- the brief said "twice as
  big and twice as damage," not tankier; a bigger hitbox is also an easier
  target, which keeps it roughly balanced without a separate HP tuning pass.
- Inherits `police.tscn`'s `NetSync` `MultiplayerSynchronizer` and
  `net_position`/`net_yaw`/`net_anim`/`net_health` replication unchanged --
  megacops replicate to clients exactly like regular cops, no extra wiring
  needed.

**Wave integration** (the "use at your discretion" part): `scripts/police_spawner.gd`
gained `@export var megacop_scene` and `begin_wave(total_police, duration,
megacop_count = 0)`. `scripts/wave_manager.gd` decides `megacop_count` via
`_megacop_count_for()`. Starting at `MEGACOP_UNLOCK_ACT = 2`, megacops make
up `MEGACOP_BASE_FRACTION = 0.2` of each regular wave and
`MEGACOP_ASSAULT_FRACTION = 0.35` of each assault wave.
`get_next_wave_preview()` also returns `"megacops"`.

Act 1's first two waves have regular cops only. Its third wave is the assault
finale and previews megacops at the 35% assault fraction. Act 2 adds megacops
to regular waves at the 20% base fraction.

`PoliceSpawner._spawn_police()` converts one regular-cop spawn slot to mega
at a time with probability `_megacop_remaining_to_spawn /
_police_remaining_to_spawn` -- spreads megacops evenly across the wave's
spawn window while still landing on the exact requested count by the last
spawn (same trick as dealing from a shuffled deck). This sits *after* the
`PlayerRegistry.random_alive()` anchor check in `_spawn_police()`, so a
quota-skipped spawn (no living player, multiplayer respawn window) never
burns a megacop slot either.

## Built in a worktree started one commit behind `main`

This worktree was created while `main`/`origin/main` was mid-merge of the
`lan-multiplayer` branch into the wave-survival line -- the shared checkout's
working tree had **unresolved git conflict markers** in `test_map.gd`,
`game_state.gd`, and `police_spawner.gd` at the time (someone else's
in-progress merge resolution, not something to touch or finish). The
worktree was seeded from `main`'s last *clean* commit (`5a9d176`,
pre-multiplayer) rather than that dirty state.

By the time megacop's first implementation pass was verified, `main` had
advanced to `ce4b9b2` (`lan-multiplayer` merged in: server-authoritative
police spawning via `PlayerRegistry`, `NetworkManager.is_authoritative()`
guards, replicated `net_*` state). `git rebase main` was a no-op fast-forward
(nothing had been committed locally yet), so the megacop edits -- still only
in the worktree's dirty working tree / a `git stash` -- were reconciled
against the new `main` by hand: `police_spawner.gd`'s `_spawn_police()` now
returns `bool` and spawns around `PlayerRegistry.random_alive()` instead of a
single `player_path`, so the megacop-vs-regular scene choice was spliced in
*after* that anchor check rather than reintroducing the old single-player
`setup()`/`player_path` pattern, which no longer exists.

## Verification performed (CLAUDE.md rule)

Fresh worktree checkouts have no `.godot/` cache (gitignored) -- an explicit
`godot --headless --import --quit` pass was required before anything else;
skipping it made nearly every custom class (`HealthComponent`,
`MovementController`, etc.) and scene script fail to resolve project-wide,
which looked like a megacop-specific bug at first but reproduced identically
for unrelated pre-existing files too.

`project.godot`'s `run/main_scene` is now `main_menu.tscn` (added by the
lan-multiplayer merge) -- `task run-headless` alone just idles at the menu
with no wave/spawn activity, nothing to observe. Used the project's own
`scripts/_debug_verify_wave_boot.gd` harness instead (kept from the
wave-survival work as a regression check), which already knows the correct
pattern for headless verification post-multiplayer:
`NetworkManager.begin_single_player_session()` then instantiate
`test_map.tscn` by hand, deferred to the first *idle frame* (not `_init()`)
since autoloads aren't on the tree yet when a bare `--script` SceneTree's
`_init()` runs.

(Dead end worth recording: an earlier standalone one-off script that called
`load("res://scenes/police.tscn").instantiate()` directly from `_init()`
failed with `SCRIPT ERROR: Compile Error: Identifier not found: GameState`
and silently produced a node with `get_script() == null` -- *not* because
`--script` mode can't resolve autoloads at all, but because that script ran
before the engine had added autoloads to the tree. Deferring to the first
process-frame tick, exactly like `_debug_verify_wave_boot.gd` already does,
resolves it.)

Temporarily set `MEGACOP_UNLOCK_ACT = 1` and `MEGACOP_BASE_FRACTION = 0.5`
and added a one-line `print()` in `_spawn_police()` (both reverted after),
then ran `_debug_verify_wave_boot.gd`. Confirmed real megacop spawns through
the full multiplayer-aware path (`PlayerRegistry.random_alive()` anchor,
`NetworkManager.is_authoritative()` gate, replicated `Cop%d` naming/
`net_position`): `scene=res://scenes/megacop.tscn attack_range=3.0
damage=12.0`, alongside regular cops at `scene=res://scenes/police.tscn
attack_range=1.5 damage=6.0` from the same wave's mixed spawn order.
Re-ran with real tuning restored (`MEGACOP_UNLOCK_ACT = 2`) and confirmed
Act 1 Wave 1 spawns only regular cops, as intended.

Both runs: zero `SCRIPT ERROR` lines. `task run-headless` boots cleanly to
the main menu with zero new errors/warnings beyond `logs/run-headless.log`'s
pre-existing unrelated ones (`blood_effect` UID, `CompassBar.parent`).

**Not yet exercised**: killing a megacop (`HealthComponent`/`_on_died()`
path) specifically, and the Send Mob direct-attack path (`take_damage()`)
against one, and megacop behavior in an actual multi-client LAN session
(only single-player authority was exercised here) -- all three just delegate
to the same shared `police.gd`/replication code already verified for regular
cops, so no megacop-specific risk was identified, but flagging for whoever
plays it live.
