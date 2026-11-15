extends Node

## WaveManager: drives the kill-gated wave/intermission/Act loop per
## vision.md's "Wave System" and "Acts and Progression" sections. Registered
## as the `WaveManager` autoload (see project.godot [autoload]). This is the
## integration contract with the (separately-built) upgrade system -- see
## agents/wave-survival-notes.md, which this file implements exactly.
##
## Flow: PREPARING -> ACTIVE (police trickle in, capped at police_spawner's
## max_alive; wave completes once every cop for the wave has been both
## spawned and killed) -> wave_completed + intermission_started (the upgrade
## station opens, built by the other agent) -> INTERMISSION (live countdown,
## no police spawning) -> next wave ACTIVE. After the last wave of an Act:
## act_completed instead of another intermission.
##
## Police spawning itself is delegated to whatever's in the
## `&"police_spawner"` group (scripts/police_spawner.gd) -- this script only
## decides WHEN and HOW MANY, never touches spawn positions/instancing
## directly, mirroring the existing `&"crowd_controller"` group-lookup
## pattern (see scripts/audio_manager.gd).
##
## ## Multiplayer
##
## The wave loop is **server-authoritative shared state**, like Grabuge: one
## protest, one wave, one Act for everybody (see agents/multiplayer-notes.md).
## Only the server advances the timers and orders spawns; clients receive
## * a 10 Hz unreliable-ordered push of (state, act, wave, time left, police
##   left) for the HUD, and
## * every phase transition as a reliable RPC, so the upgrade station and the
##   Act scoreboard open and close in lockstep on all peers.
## The two player-driven transitions (leaving the shop, starting the next Act)
## are requests: a client rpc_id(1)s them and the server decides.
##
## The run no longer starts in _ready(): the main scene is the menu, and in
## multiplayer wave 1 must not begin until every peer has loaded the map and
## spawned a character. scenes/test_map.gd calls start_run() at that point.

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
## Fired when the live pre-wave countdown actually starts, i.e. the shop is
## over. The upgrade station closes on this rather than on its own button
## press, so in multiplayer every peer's shop closes together.
signal intermission_countdown_started

## -- Tuning constants (all balancing numbers live here, clearly named) --

## Each Act ends after its third wave.
const WAVES_PER_ACT: int = 3

## Live pre-wave countdown length (seconds) once the player leaves the
## upgrade station via begin_intermission_countdown().
const INTERMISSION_DURATION: float = 12.0

## Police-count escalation: base count for wave 1 of Act 1, plus a flat
## increase per wave within an Act and a multiplier per Act.
const BASE_POLICE_COUNT: int = 8
const POLICE_PER_WAVE_INCREMENT: int = 3
const POLICE_PER_ACT_MULTIPLIER: float = 1.4

## Every Nth wave (within an Act) is a bigger "assault" wave -- predictable
## escalation milestones per vision.md ("every third wave introduces a more
## substantial assault").
const ASSAULT_WAVE_INTERVAL: int = 3
## Assault waves multiply the normal police count for that wave.
const ASSAULT_POLICE_MULTIPLIER: float = 1.75

## Megacops join the regular wave rotation starting in Act 2, with a preview
## in Act 1's finale.
const MEGACOP_UNLOCK_ACT: int = 2
## Fraction of a wave's police total that are megacops once unlocked, and the
## bumped fraction on assault waves (escalation milestone per vision.md gets
## a heavier mega presence too, not just more cops).
const MEGACOP_BASE_FRACTION: float = 0.2
const MEGACOP_ASSAULT_FRACTION: float = 0.35

var state: State = State.PREPARING
var current_act: int = 1        # 1-based
var current_wave: int = 1       # 1-based, within the current Act
## Only meaningful during INTERMISSION now -- the live pre-wave countdown.
## ACTIVE waves have no clock; see police_remaining instead.
var wave_time_left: float = 0.0
var wave_duration: float = 0.0
## How many of this wave's cops are still queued-to-spawn or alive. Drives
## the HUD's "N left" readout during ACTIVE; replicated like the other wave
## state. Set from police_spawner.gd's own count, not derived independently.
var police_remaining: int = 0

## True once begin_intermission_countdown() has been called -- the live
## countdown only ticks after the (paused) upgrade station is left, not as
## soon as intermission_started fires.
var _intermission_counting: bool = false

## A wave's spawn order that couldn't be delivered yet because the
## PoliceSpawner wasn't in the scene tree at the time -- see
## _begin_spawning() for why this happens on the very first wave.
var _pending_spawn_request: Dictionary = {}

## True between start_run() and a game over -- nothing ticks before the match
## actually begins (the main scene is the menu).
var _running: bool = false

## How often the server pushes the wave timers to clients (10 Hz). The
## countdown changes every frame, so pushing on change would flood the
## channel for no visible benefit -- same reasoning as GameState's push.
const _PUSH_INTERVAL: float = 0.1
var _push_timer: float = 0.0


func _ready() -> void:
	GameState.game_over.connect(_on_game_over)


## Called by scenes/test_map.gd once the map is loaded on every peer and the
## player characters exist. Server-authoritative: on a client this only arms
## the local countdown display, the wave itself arrives by replication.
func start_run() -> void:
	_running = true
	if not NetworkManager.is_authoritative():
		return
	_start_wave(1, 1)


func _process(delta: float) -> void:
	if not _running:
		return

	if not NetworkManager.is_authoritative():
		# Clients keep counting the replicated intermission timer down
		# locally between pushes, so that countdown is smooth rather than
		# 10 Hz steppy. ACTIVE has no clock to extrapolate -- police_remaining
		# just waits for the next push.
		if state == State.INTERMISSION and _intermission_counting:
			wave_time_left = max(wave_time_left - delta, 0.0)
		return

	_flush_pending_spawn_request()

	if state == State.ACTIVE:
		_process_active(delta)
	elif state == State.INTERMISSION:
		_process_intermission(delta)

	_push_timer -= delta
	if _push_timer <= 0.0:
		_push_timer = _PUSH_INTERVAL
		_push_wave_state()


## Kill-gated: the wave has no clock of its own. Reads PoliceSpawner's live
## state every frame to keep the HUD's "N left" count current, and completes
## the wave the moment every cop for it has been both spawned and killed.
func _process_active(_delta: float) -> void:
	if not _pending_spawn_request.is_empty():
		# The spawn order hasn't actually landed on the spawner yet (see
		# _begin_spawning()'s retry) -- nothing has been queued, so there's
		# nothing to check for completion against.
		return

	var spawner: Node = _get_police_spawner()
	if spawner == null:
		return

	police_remaining = spawner.get_police_left_count()
	if not spawner.has_any_police_left():
		_complete_wave()


## Only ticks the live countdown once begin_intermission_countdown() has
## actually started it (wave_time_left stays at the full
## INTERMISSION_DURATION, set in _complete_wave(), until then) -- the
## upgrade station is paused during the shop itself, so this would run
## unbounded if it ticked immediately on intermission_started.
func _process_intermission(delta: float) -> void:
	if not _intermission_counting:
		return
	wave_time_left -= delta
	if wave_time_left <= 0.0:
		_on_intermission_elapsed()


## {wave: int, police: int, assault: bool} -- feeds the between-wave "next
## wave" preview. Reports the wave that will start after the CURRENT
## intermission/preparation, within the current Act.
func get_next_wave_preview() -> Dictionary:
	var next_wave: int = current_wave + 1
	var police_total: int = _police_count_for(current_act, next_wave)
	return {
		"wave": next_wave,
		"police": police_total,
		"assault": _is_assault_wave(next_wave),
		"megacops": _megacop_count_for(current_act, next_wave, police_total),
	}


## Called by the upgrade station's Continue button to leave the paused shop
## and begin the live pre-wave countdown. No-op unless we're actually
## waiting in INTERMISSION.
func begin_intermission_countdown() -> void:
	# On a client this is a request -- the server owns the transition and
	# broadcasts it back, which is what actually closes the shop.
	if not NetworkManager.is_authoritative():
		_request_intermission_countdown.rpc_id(1)
		return
	if state != State.INTERMISSION:
		return
	wave_time_left = INTERMISSION_DURATION
	wave_duration = INTERMISSION_DURATION
	_intermission_counting = true
	intermission_countdown_started.emit()
	if NetworkManager.is_multiplayer_session():
		_apply_countdown_started.rpc(INTERMISSION_DURATION)

	# Warn here, during the live countdown, rather than after the assault
	# wave has already begun -- vision.md asks for warnings *before*
	# dangerous attacks, and the player can still act on this one (recruit
	# more, reposition the mob) while the countdown runs.
	if _is_assault_wave(current_wave + 1):
		_emit_threat_warning("ASSAULT WAVE INCOMING")


## Not part of the original contract (agents/wave-survival-notes.md only
## lists reset/get_next_wave_preview/begin_intermission_countdown) -- added
## because the Act-complete scoreboard's Continue button (vision.md) needs
## some way to actually start the next, harder Act. Safe to call only while
## state == ACT_COMPLETE.
func start_next_act() -> void:
	# Same request/authority split as begin_intermission_countdown().
	if not NetworkManager.is_authoritative():
		_request_next_act.rpc_id(1)
		return
	if state != State.ACT_COMPLETE:
		return
	current_act += 1
	current_wave = 1
	_start_wave(current_act, current_wave)


func reset() -> void:
	current_act = 1
	current_wave = 1
	state = State.PREPARING
	_intermission_counting = false
	_pending_spawn_request = {}
	_push_timer = 0.0
	police_remaining = 0
	_clear_police()
	# A reset without a running match (returning to the menu/lobby) must not
	# start wave 1 -- start_run() does that when the next match boots.
	if _running and NetworkManager.is_authoritative():
		_start_wave(current_act, current_wave)


func _on_game_over() -> void:
	state = State.PREPARING
	_running = false
	if NetworkManager.is_authoritative():
		_stop_spawning()


## -- Internal wave flow --

func _start_wave(act: int, wave: int) -> void:
	state = State.ACTIVE
	current_act = act
	current_wave = wave
	_intermission_counting = false

	var police_total: int = _police_count_for(act, wave)
	var megacop_total: int = _megacop_count_for(act, wave, police_total)
	police_remaining = police_total
	_clear_police()
	_begin_spawning(police_total, megacop_total)

	wave_started.emit(wave, police_total)
	if NetworkManager.is_multiplayer_session():
		_apply_wave_started.rpc(act, wave, police_total)


func _complete_wave() -> void:
	state = State.PREPARING
	_stop_spawning()
	_clear_police()
	wave_completed.emit(current_wave)
	if NetworkManager.is_multiplayer_session():
		_apply_wave_completed.rpc(current_wave)

	if current_wave >= WAVES_PER_ACT:
		state = State.ACT_COMPLETE
		act_completed.emit(current_act)
		if NetworkManager.is_multiplayer_session():
			_apply_act_completed.rpc(current_act)
		return

	state = State.INTERMISSION
	wave_time_left = INTERMISSION_DURATION
	wave_duration = INTERMISSION_DURATION
	intermission_started.emit(current_wave + 1, INTERMISSION_DURATION)
	if NetworkManager.is_multiplayer_session():
		_apply_intermission_started.rpc(current_wave + 1, INTERMISSION_DURATION)


## _process() ticks wave_time_left down during INTERMISSION the same way it
## does during ACTIVE (both just count down a shared timer), so the live
## pre-wave countdown advances automatically once begin_intermission_countdown()
## is called. When it reaches zero here, start the next wave instead of
## completing one.
func _on_intermission_elapsed() -> void:
	_intermission_counting = false
	intermission_finished.emit()
	if NetworkManager.is_multiplayer_session():
		_apply_intermission_finished.rpc()
	_start_wave(current_act, current_wave + 1)


## -- Escalation math --

func _police_count_for(act: int, wave: int) -> int:
	var base: float = float(BASE_POLICE_COUNT + POLICE_PER_WAVE_INCREMENT * (wave - 1))
	base *= pow(POLICE_PER_ACT_MULTIPLIER, float(act - 1))
	if _is_assault_wave(wave):
		base *= ASSAULT_POLICE_MULTIPLIER
	return int(round(base))


func _is_assault_wave(wave: int) -> bool:
	return wave % ASSAULT_WAVE_INTERVAL == 0


func _megacop_count_for(act: int, wave: int, police_total: int) -> int:
	# Act 1's final wave gets a preview taste of megacops even though the
	# Act is otherwise below MEGACOP_UNLOCK_ACT -- a last-wave escalation
	# before Act 2 properly unlocks them.
	var is_act1_finale: bool = act == 1 and wave == WAVES_PER_ACT
	if act < MEGACOP_UNLOCK_ACT and not is_act1_finale:
		return 0
	var fraction: float = MEGACOP_ASSAULT_FRACTION if _is_assault_wave(wave) else MEGACOP_BASE_FRACTION
	return int(round(float(police_total) * fraction))


## -- Spawner integration (via group lookup, per the crowd_controller
## pattern -- see scripts/audio_manager.gd) --

func _get_police_spawner() -> Node:
	return get_tree().get_first_node_in_group(&"police_spawner")


## Hands a wave's spawn order to the PoliceSpawner, retrying on later frames
## if the spawner isn't reachable yet.
##
## This retry is NOT defensive padding -- it's load-order-critical.
## WaveManager is an autoload, so its _ready() (which starts wave 1) runs
## BEFORE the main scene is instanced, meaning nothing has joined the
## `&"police_spawner"` group yet. Without the retry the first
## _begin_spawning() silently no-ops on the null check and wave 1 contains
## zero police while its timer happily counts down -- verified by a headless
## boot dump before this was added. Mirrors the lazy-resolve pattern in
## scripts/crowd_controller.gd's _find_megaphone(), which exists for exactly
## the same autoload/scene ordering reason.
func _begin_spawning(total_police: int, megacop_count: int = 0) -> void:
	var spawner: Node = _get_police_spawner()
	if spawner != null:
		spawner.begin_wave(total_police, megacop_count)
		return
	_pending_spawn_request = {"police": total_police, "megacops": megacop_count}


## Retries a spawn order that arrived before the PoliceSpawner existed. Called
## every frame from _process() until it lands.
func _flush_pending_spawn_request() -> void:
	if _pending_spawn_request.is_empty():
		return
	var spawner: Node = _get_police_spawner()
	if spawner == null:
		return
	spawner.begin_wave(_pending_spawn_request["police"], _pending_spawn_request["megacops"])
	_pending_spawn_request = {}


func _stop_spawning() -> void:
	# Drop any undelivered spawn order too, so a wave that ended (or a game
	# over) can't have its spawns land retroactively on the next frame.
	_pending_spawn_request = {}
	var spawner: Node = _get_police_spawner()
	if spawner != null:
		spawner.stop_spawning()


func _clear_police() -> void:
	var spawner: Node = _get_police_spawner()
	if spawner != null:
		spawner.clear_all_police()


func _emit_threat_warning(message: String) -> void:
	threat_warning.emit(message)
	if NetworkManager.is_multiplayer_session():
		_apply_threat_warning.rpc(message)


# --------------------------------------------------------------------------
# Replication (server -> clients)
# --------------------------------------------------------------------------

func _push_wave_state() -> void:
	if not NetworkManager.is_multiplayer_session():
		return
	_apply_wave_state.rpc(int(state), current_act, current_wave, wave_time_left, wave_duration, police_remaining)


## Unreliable-ordered for the same reason as GameState's counter push: a lost
## packet is superseded by the next one, but out-of-order delivery would make
## the HUD countdown/police-left count jump backwards.
@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_wave_state(
	new_state: int,
	new_act: int,
	new_wave: int,
	new_time_left: float,
	new_duration: float,
	new_police_remaining: int
) -> void:
	state = new_state as State
	current_act = new_act
	current_wave = new_wave
	wave_time_left = new_time_left
	wave_duration = new_duration
	police_remaining = new_police_remaining


@rpc("authority", "call_remote", "reliable")
func _apply_wave_started(act: int, wave: int, police_total: int) -> void:
	state = State.ACTIVE
	current_act = act
	current_wave = wave
	police_remaining = police_total
	_intermission_counting = false
	wave_started.emit(wave, police_total)


@rpc("authority", "call_remote", "reliable")
func _apply_wave_completed(wave: int) -> void:
	state = State.PREPARING
	current_wave = wave
	wave_completed.emit(wave)


@rpc("authority", "call_remote", "reliable")
func _apply_intermission_started(next_wave_number: int, duration: float) -> void:
	state = State.INTERMISSION
	_intermission_counting = false
	wave_time_left = duration
	wave_duration = duration
	intermission_started.emit(next_wave_number, duration)


@rpc("authority", "call_remote", "reliable")
func _apply_countdown_started(duration: float) -> void:
	wave_time_left = duration
	wave_duration = duration
	_intermission_counting = true
	intermission_countdown_started.emit()


@rpc("authority", "call_remote", "reliable")
func _apply_intermission_finished() -> void:
	_intermission_counting = false
	intermission_finished.emit()


@rpc("authority", "call_remote", "reliable")
func _apply_act_completed(act: int) -> void:
	state = State.ACT_COMPLETE
	current_act = act
	act_completed.emit(act)


@rpc("authority", "call_remote", "reliable")
func _apply_threat_warning(message: String) -> void:
	threat_warning.emit(message)


# --------------------------------------------------------------------------
# Client requests (client -> server)
# --------------------------------------------------------------------------

## Any player can close the shared shop and start the countdown -- first one
## to press Continue starts it for everybody, which is simpler than waiting
## on a ready-check and keeps the protest from stalling on an idle player.
@rpc("any_peer", "call_remote", "reliable")
func _request_intermission_countdown() -> void:
	if not NetworkManager.is_authoritative():
		return
	begin_intermission_countdown()


@rpc("any_peer", "call_remote", "reliable")
func _request_next_act() -> void:
	if not NetworkManager.is_authoritative():
		return
	start_next_act()
