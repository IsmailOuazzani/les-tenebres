extends Node

## GameState: global Grabuge + crowd-count singleton.
##
## Registered as the `GameState` autoload (see project.godot [autoload]).
## Grabuge is the run's upgrade currency per vision.md's wave-survival
## rewrite (see agents/grabuge-notes.md for the earlier decay-meter
## history) -- it no longer decays and no longer ends the run on its own.
## Two numbers are tracked separately so spending never affects spawning:
## `grabuge_total_earned` (monotonic, drives civilian spawn scaling in
## scripts/npc_spawner.gd) and `grabuge_available` (rises on earn, falls on
## spend, used only for upgrade purchases). The sole game-over trigger is
## the player's own health reaching zero (see trigger_player_death()).
##
## ## Multiplayer
##
## Grabuge and the crowd counters are **server-authoritative shared state**
## (spec 4.5: one shared Grabuge score, all players contribute, all players
## see the same value). Every mutator below is a no-op on a client; the
## server pushes the authoritative values out at `_PUSH_INTERVAL` over an
## unreliable-ordered RPC (frequent, lossy-tolerant numeric state), while
## discrete gameplay events (disruption, police defeat, game over) go out
## reliably so the protest feed stays consistent for everyone.
##
## Because this is an autoload, its node path is identical on every peer, so
## it can own RPCs directly. In single-player there is no peer and the RPC
## pushes are skipped entirely -- behavior is unchanged.

signal grabuge_changed(new_available: float, new_total_earned: float)
signal crowd_count_changed(new_value: int)
signal disruption_recorded(total: int)
## Emitted when a cop goes down (scripts/police.gd's _on_died()) -- consumed
## by scripts/snap_feed.gd to inject a "police defeated" message. Carries
## the Grabuge amount just awarded so the feed can display it. See
## agents/snap-feed-notes.md.
signal police_defeated(grabuge_gain: float)
signal game_over

## Soft reference cap used only to scale the civilian spawn trickle curve
## (scripts/npc_spawner.gd) against grabuge_total_earned -- NOT a hard max;
## total_earned is monotonic and can exceed this over a long run.
const GRABUGE_SCALE_REFERENCE: float = 100.0

## Balancing constants -- tweak here.
const RECRUIT_GRABUGE_BONUS: float = 2.0
const DISRUPTION_GRABUGE_BASE: float = 15.0
const POLICE_DEFEAT_GRABUGE_BASE: float = 20.0
## Debug key (see scenes/test_map.gd) bump amount, per the original spec's
## "G: Increase Grabuge by 20."
const DEBUG_GRABUGE_BUMP: float = 20.0

## How often the server pushes Grabuge/crowd counters to clients (10 Hz).
## Grabuge changes almost every frame from decay, so pushing on change would
## flood the channel for no visible benefit.
const _PUSH_INTERVAL: float = 0.1

var crowd_count: int = 1
## Spendable balance -- goes up on earn, down on spend_grabuge().
var grabuge_available: float = 0.0
## Monotonic lifetime total -- never decreases, drives civilian spawn rate.
var grabuge_total_earned: float = 0.0

## Live headcount of currently-recruited protesters, as opposed to
## `crowd_count`'s "ever recruited" tally. Written by CrowdController on the
## server and replicated, because the recruited list itself is server-side
## state -- the megaphone's send-percentage readout needs it on clients too.
var live_crowd_count: int = 0

var peak_crowd_count: int = 1
var total_disruptions: int = 0
## Run-total cops killed -- shown on the end-of-Act scoreboard (vision.md).
var police_defeated_count: int = 0

var _session_start_msec: int = 0
var _game_over_fired: bool = false
var _push_timer: float = 0.0
var _dirty: bool = false


func _ready() -> void:
	_session_start_msec = Time.get_ticks_msec()


func _process(delta: float) -> void:
	# Only the server pushes the authoritative counters; Grabuge itself no
	# longer decays (vision.md's wave-survival rewrite), so there is nothing
	# else to simulate here.
	if not NetworkManager.is_authoritative():
		return

	_push_timer -= delta
	if _push_timer <= 0.0:
		_push_timer = _PUSH_INTERVAL
		_push_core_state()


## Elapsed time since the session started, in seconds.
func get_session_duration() -> float:
	return (Time.get_ticks_msec() - _session_start_msec) / 1000.0


## Public entry point for earning Grabuge: raises both grabuge_available and
## grabuge_total_earned by `amount` (must be >= 0 -- this is an earn, not a
## spend; see spend_grabuge() for the other direction).
## Server-authoritative: a no-op on clients.
func add_grabuge(amount: float) -> void:
	if not NetworkManager.is_authoritative():
		return
	if amount <= 0.0 or _game_over_fired:
		return
	grabuge_available += amount
	grabuge_total_earned += amount
	_dirty = true
	grabuge_changed.emit(grabuge_available, grabuge_total_earned)


## Attempts to spend `amount` from grabuge_available (e.g. an upgrade
## purchase). Returns true and deducts on success, false (no change) if the
## player can't afford it. Never touches grabuge_total_earned, so purchases
## never affect civilian spawn scaling. Server-authoritative: a client's
## purchase request has to reach the server (see scripts/upgrade_manager.gd).
func spend_grabuge(amount: float) -> bool:
	if not NetworkManager.is_authoritative():
		return false
	if amount <= 0.0 or amount > grabuge_available:
		return false
	grabuge_available -= amount
	_dirty = true
	grabuge_changed.emit(grabuge_available, grabuge_total_earned)
	return true


func recruit_npc() -> void:
	if not NetworkManager.is_authoritative():
		return
	crowd_count += 1
	peak_crowd_count = max(peak_crowd_count, crowd_count)
	_dirty = true
	crowd_count_changed.emit(crowd_count)
	add_grabuge(RECRUIT_GRABUGE_BONUS)


## Server-side: mirrors CrowdController's live recruited headcount into
## replicated state.
func set_live_crowd_count(value: int) -> void:
	if value == live_crowd_count:
		return
	live_crowd_count = value
	_dirty = true


## Records a successful disruption: bumps the disruption counter and raises
## Grabuge. `magnitude` is a stub scalar (1.0 = normal-sized disruption) for
## when bigger/more ridiculous disruptions should raise Grabuge
## proportionally more, per vision.md.
func record_disruption(magnitude: float = 1.0) -> void:
	if not NetworkManager.is_authoritative():
		return
	total_disruptions += 1
	disruption_recorded.emit(total_disruptions)
	if NetworkManager.is_multiplayer_session():
		_apply_disruption.rpc(total_disruptions)
	add_grabuge(DISRUPTION_GRABUGE_BASE * magnitude)


## Fired by Police._on_died() -- raises Grabuge by POLICE_DEFEAT_GRABUGE_BASE
## and notifies the snap feed with the amount awarded. See
## agents/snap-feed-notes.md.
func record_police_defeat() -> void:
	if not NetworkManager.is_authoritative():
		return
	police_defeated_count += 1
	_dirty = true
	add_grabuge(POLICE_DEFEAT_GRABUGE_BASE)
	police_defeated.emit(POLICE_DEFEAT_GRABUGE_BASE)
	if NetworkManager.is_multiplayer_session():
		_apply_police_defeat.rpc(POLICE_DEFEAT_GRABUGE_BASE)


## The only single-player game-over trigger: the player's own
## HealthComponent.died (wired in scenes/test_map.gd, since that's the one
## non-vendored spot that already does similar debug-key-style wiring without
## touching addons/fps_controller/Player.tscn).
##
## In multiplayer this is NOT a game-over condition -- spec 4.4: "A player's
## death does not reset the protest", dead players respawn after 5 seconds.
## See agents/police-notes.md.
func trigger_player_death() -> void:
	if NetworkManager.is_multiplayer_session():
		return
	if _game_over_fired:
		return
	_fire_game_over()


func _fire_game_over() -> void:
	if _game_over_fired:
		return
	_game_over_fired = true
	game_over.emit()
	if NetworkManager.is_multiplayer_session():
		_apply_game_over.rpc(
			peak_crowd_count, total_disruptions, grabuge_total_earned, get_session_duration()
		)


## Resets all state. Called by game_over.gd's restart handler and by
## NetworkManager when a session ends -- autoloads are NOT recreated by
## get_tree().reload_current_scene() or change_scene_to_file(), so without
## this `_game_over_fired` would stay true forever after a restart.
func reset() -> void:
	crowd_count = 1
	grabuge_available = 0.0
	grabuge_total_earned = 0.0
	live_crowd_count = 0
	peak_crowd_count = 1
	total_disruptions = 0
	police_defeated_count = 0
	_session_start_msec = Time.get_ticks_msec()
	_game_over_fired = false
	_dirty = false
	_push_timer = 0.0
	crowd_count_changed.emit(crowd_count)
	grabuge_changed.emit(grabuge_available, grabuge_total_earned)


# --------------------------------------------------------------------------
# Replication (server -> clients)
# --------------------------------------------------------------------------

func _push_core_state() -> void:
	if not _dirty:
		return
	if not NetworkManager.is_multiplayer_session():
		_dirty = false
		return
	_dirty = false
	_apply_core_state.rpc(
		grabuge_available,
		grabuge_total_earned,
		crowd_count,
		live_crowd_count,
		police_defeated_count
	)


## Unreliable-ordered: this is a frequent numeric state stream, so a dropped
## packet is harmless (the next one supersedes it) but out-of-order delivery
## would make the Grabuge readout jitter backwards.
@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_core_state(
	new_available: float,
	new_total_earned: float,
	new_crowd_count: int,
	new_live_count: int,
	new_police_defeated: int
) -> void:
	live_crowd_count = new_live_count
	police_defeated_count = new_police_defeated
	if (
		not is_equal_approx(grabuge_available, new_available)
		or not is_equal_approx(grabuge_total_earned, new_total_earned)
	):
		grabuge_available = new_available
		grabuge_total_earned = new_total_earned
		grabuge_changed.emit(grabuge_available, grabuge_total_earned)
	if crowd_count != new_crowd_count:
		crowd_count = new_crowd_count
		peak_crowd_count = max(peak_crowd_count, crowd_count)
		crowd_count_changed.emit(crowd_count)


@rpc("authority", "call_remote", "reliable")
func _apply_disruption(total: int) -> void:
	total_disruptions = total
	disruption_recorded.emit(total)


@rpc("authority", "call_remote", "reliable")
func _apply_police_defeat(grabuge_gain: float) -> void:
	police_defeated.emit(grabuge_gain)


@rpc("authority", "call_remote", "reliable")
func _apply_game_over(
	server_peak_crowd: int,
	server_disruptions: int,
	server_total_earned: float,
	server_duration: float
) -> void:
	if _game_over_fired:
		return
	_game_over_fired = true
	# Adopt the server's end-of-run stats so every player's game-over screen
	# shows the same numbers.
	peak_crowd_count = server_peak_crowd
	total_disruptions = server_disruptions
	grabuge_total_earned = server_total_earned
	_session_start_msec = Time.get_ticks_msec() - int(server_duration * 1000.0)
	game_over.emit()
