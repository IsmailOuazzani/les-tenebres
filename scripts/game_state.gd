extends Node

## GameState: global Grabuge + crowd-count singleton.
##
## Registered as the `GameState` autoload (see project.godot [autoload]).
## Grabuge is the single shared chaos/excitement resource described in
## vision.md -- it replaces the earlier separate Publicity/Patience/Zbeul
## meters (see agents/grabuge-notes.md for the migration). Game-over fires
## when Grabuge decays to zero; NPC dispersal on game-over is still deferred.
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

signal grabuge_changed(new_value: float)
signal crowd_count_changed(new_value: int)
signal disruption_recorded(total: int)
## Emitted when a cop goes down (scripts/police.gd's _on_died()) -- consumed
## by scripts/snap_feed.gd to inject a "police defeated" message. Carries
## the Grabuge amount just awarded so the feed can display it. See
## agents/snap-feed-notes.md.
signal police_defeated(grabuge_gain: float)
signal game_over

const GRABUGE_MAX: float = 100.0

## Balancing constants -- tweak here. Grabuge decays continuously regardless
## of what the player does; recruiting and disruptions push it back up.
const GRABUGE_DECAY_PER_SECOND: float = 0.75
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
var grabuge: float = 0.0

## Live headcount of currently-recruited protesters, as opposed to
## `crowd_count`'s "ever recruited" tally. Written by CrowdController on the
## server and replicated, because the recruited list itself is server-side
## state -- the megaphone's send-percentage readout needs it on clients too.
var live_crowd_count: int = 0

var peak_crowd_count: int = 1
var peak_grabuge: float = 0.0
var total_disruptions: int = 0

var _session_start_msec: int = 0
var _game_over_fired: bool = false
var _push_timer: float = 0.0
var _dirty: bool = false


func _ready() -> void:
	_session_start_msec = Time.get_ticks_msec()


func _process(delta: float) -> void:
	# Grabuge decay is part of the authoritative simulation: a client that
	# ran it locally would drift away from the server between pushes.
	if not NetworkManager.is_authoritative():
		return
	if _game_over_fired:
		return

	var was_positive: bool = grabuge > 0.0
	add_grabuge(-GRABUGE_DECAY_PER_SECOND * delta)
	if was_positive and grabuge <= 0.0:
		_fire_game_over()

	_push_timer -= delta
	if _push_timer <= 0.0:
		_push_timer = _PUSH_INTERVAL
		_push_core_state()


## Elapsed time since the session started, in seconds.
func get_session_duration() -> float:
	return (Time.get_ticks_msec() - _session_start_msec) / 1000.0


## Public entry point for raising/lowering Grabuge, clamped to
## [0, GRABUGE_MAX]. Positive `amount` raises it, negative lowers it (used
## internally for passive decay). Server-authoritative: a no-op on clients.
func add_grabuge(amount: float) -> void:
	if not NetworkManager.is_authoritative():
		return
	if amount == 0.0 or _game_over_fired:
		return
	grabuge = clamp(grabuge + amount, 0.0, GRABUGE_MAX)
	peak_grabuge = max(peak_grabuge, grabuge)
	_dirty = true
	grabuge_changed.emit(grabuge)


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
	add_grabuge(POLICE_DEFEAT_GRABUGE_BASE)
	police_defeated.emit(POLICE_DEFEAT_GRABUGE_BASE)
	if NetworkManager.is_multiplayer_session():
		_apply_police_defeat.rpc(POLICE_DEFEAT_GRABUGE_BASE)


## Single-player alternate game-over trigger alongside Grabuge decay: the
## player's own HealthComponent.died (wired in scenes/test_map.gd).
##
## In multiplayer this is NOT a game-over condition -- spec 4.4: "A player's
## death does not reset the protest", dead players respawn after 5 seconds.
## The branch lives here so the single-player behavior stays byte-for-byte
## identical. See agents/police-notes.md.
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
			peak_crowd_count, total_disruptions, peak_grabuge, get_session_duration()
		)


## Resets all state. Called by game_over.gd's restart handler and by
## NetworkManager when a session ends -- autoloads are NOT recreated by
## get_tree().reload_current_scene() or change_scene_to_file(), so without
## this `_game_over_fired` would stay true forever after a restart.
func reset() -> void:
	crowd_count = 1
	grabuge = 0.0
	live_crowd_count = 0
	peak_crowd_count = 1
	peak_grabuge = 0.0
	total_disruptions = 0
	_session_start_msec = Time.get_ticks_msec()
	_game_over_fired = false
	_dirty = false
	_push_timer = 0.0
	crowd_count_changed.emit(crowd_count)
	grabuge_changed.emit(grabuge)


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
	_apply_core_state.rpc(grabuge, crowd_count, live_crowd_count)


## Unreliable-ordered: this is a frequent numeric state stream, so a dropped
## packet is harmless (the next one supersedes it) but out-of-order delivery
## would make the Grabuge bar jitter backwards.
@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_core_state(new_grabuge: float, new_crowd_count: int, new_live_count: int) -> void:
	live_crowd_count = new_live_count
	if not is_equal_approx(grabuge, new_grabuge):
		grabuge = new_grabuge
		peak_grabuge = max(peak_grabuge, grabuge)
		grabuge_changed.emit(grabuge)
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
	server_peak_grabuge: float,
	server_duration: float
) -> void:
	if _game_over_fired:
		return
	_game_over_fired = true
	# Adopt the server's end-of-run stats so every player's game-over screen
	# shows the same numbers.
	peak_crowd_count = server_peak_crowd
	total_disruptions = server_disruptions
	peak_grabuge = server_peak_grabuge
	_session_start_msec = Time.get_ticks_msec() - int(server_duration * 1000.0)
	game_over.emit()
