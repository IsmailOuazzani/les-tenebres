extends Node

## WaveManager: drives the time-based wave/intermission/Act loop per
## vision.md's "Wave System" and "Acts and Progression" sections. Registered
## as the `WaveManager` autoload (see project.godot [autoload]). This is the
## integration contract with the (separately-built) upgrade system -- see
## agents/wave-survival-notes.md, which this file implements exactly.
##
## Flow: PREPARING -> ACTIVE (timer runs, police spawn) -> wave_completed +
## intermission_started (the upgrade station opens, built by the other
## agent) -> INTERMISSION (live countdown, no police spawning) -> next wave
## ACTIVE. After the last wave of an Act: act_completed instead of another
## intermission.
##
## Police spawning itself is delegated to whatever's in the
## `&"police_spawner"` group (scripts/police_spawner.gd) -- this script only
## decides WHEN and HOW MANY, never touches spawn positions/instancing
## directly, mirroring the existing `&"crowd_controller"` group-lookup
## pattern (see scripts/audio_manager.gd).

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

## -- Tuning constants (all balancing numbers live here, clearly named) --

## Waves per Act. Flat across Acts per vision.md ("multiple waves with
## increasing difficulty") -- difficulty scales via police counts/duration,
## not wave count.
const WAVES_PER_ACT: int = 5

## How long (seconds) a single wave lasts before it's automatically
## completed, regardless of how many cops are still alive (waves are
## time-based survival, not kill-everything, per vision.md).
const BASE_WAVE_DURATION: float = 45.0
## Each Act adds this many seconds to every wave's duration, so later Acts
## are a longer grind as well as a denser one.
const WAVE_DURATION_PER_ACT: float = 10.0

## Live pre-wave countdown length (seconds) once the player leaves the
## upgrade station via begin_intermission_countdown().
const INTERMISSION_DURATION: float = 12.0

## Police-count escalation: base count for wave 1 of Act 1, plus a flat
## increase per wave within an Act and a multiplier per Act.
const BASE_POLICE_COUNT: int = 8
const POLICE_PER_WAVE_INCREMENT: int = 3
const POLICE_PER_ACT_MULTIPLIER: float = 1.4

## Fraction of the wave duration that spawning is compressed into. At 1.0
## the cops are spread across the whole wave, which at low counts reads as a
## thin trickle (wave 1 was one cop every ~11s) and leaves the back half of
## the wave empty once the player clears them. Compressing to the front
## portion means pressure actually builds -- the full wave's worth of police
## is on the field with time left to fight them, rather than dribbling in
## until the timer expires.
const SPAWN_WINDOW_FRACTION: float = 0.6

## Every Nth wave (within an Act) is a bigger "assault" wave -- predictable
## escalation milestones per vision.md ("every third wave introduces a more
## substantial assault").
const ASSAULT_WAVE_INTERVAL: int = 3
## Assault waves multiply the normal police count for that wave.
const ASSAULT_POLICE_MULTIPLIER: float = 1.75

## How many seconds before an assault wave's police spawns land that the
## threat_warning signal fires (fired right as the wave starts, since
## spawning is spread across the wave duration -- see police_spawner.gd).
const ASSAULT_WARNING_LEAD_TIME: float = 3.0

var state: State = State.PREPARING
var current_act: int = 1        # 1-based
var current_wave: int = 1       # 1-based, within the current Act
var wave_time_left: float = 0.0
var wave_duration: float = 0.0

## True once this wave's assault warning has already fired, so it doesn't
## repeat every frame while the lead-time window is open.
var _assault_warning_fired: bool = false

## True once begin_intermission_countdown() has been called -- the live
## countdown only ticks after the (paused) upgrade station is left, not as
## soon as intermission_started fires.
var _intermission_counting: bool = false

## A wave's spawn order that couldn't be delivered yet because the
## PoliceSpawner wasn't in the scene tree at the time -- see
## _begin_spawning() for why this happens on the very first wave.
var _pending_spawn_request: Dictionary = {}


func _ready() -> void:
	GameState.game_over.connect(_on_game_over)
	_start_wave(current_act, current_wave)


func _process(delta: float) -> void:
	_flush_pending_spawn_request()

	if state == State.ACTIVE:
		_process_active(delta)
	elif state == State.INTERMISSION:
		_process_intermission(delta)


func _process_active(delta: float) -> void:
	wave_time_left -= delta

	if not _assault_warning_fired and _is_assault_wave(current_wave) \
			and wave_time_left <= wave_duration - ASSAULT_WARNING_LEAD_TIME:
		_assault_warning_fired = true
		threat_warning.emit("ASSAULT WAVE INCOMING")

	if wave_time_left <= 0.0:
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
	return {
		"wave": next_wave,
		"police": _police_count_for(current_act, next_wave),
		"assault": _is_assault_wave(next_wave),
	}


## Called by the upgrade station's Continue button to leave the paused shop
## and begin the live pre-wave countdown. No-op unless we're actually
## waiting in INTERMISSION.
func begin_intermission_countdown() -> void:
	if state != State.INTERMISSION:
		return
	wave_time_left = INTERMISSION_DURATION
	wave_duration = INTERMISSION_DURATION
	_intermission_counting = true

	# Warn here, during the live countdown, rather than after the assault
	# wave has already begun -- vision.md asks for warnings *before*
	# dangerous attacks, and the player can still act on this one (recruit
	# more, reposition the mob) while the countdown runs.
	if _is_assault_wave(current_wave + 1):
		threat_warning.emit("ASSAULT WAVE INCOMING")


## Not part of the original contract (agents/wave-survival-notes.md only
## lists reset/get_next_wave_preview/begin_intermission_countdown) -- added
## because the Act-complete scoreboard's Continue button (vision.md) needs
## some way to actually start the next, harder Act. Safe to call only while
## state == ACT_COMPLETE.
func start_next_act() -> void:
	if state != State.ACT_COMPLETE:
		return
	current_act += 1
	current_wave = 1
	_start_wave(current_act, current_wave)


func reset() -> void:
	current_act = 1
	current_wave = 1
	state = State.PREPARING
	_assault_warning_fired = false
	_intermission_counting = false
	_clear_police()
	_start_wave(current_act, current_wave)


func _on_game_over() -> void:
	state = State.PREPARING
	_stop_spawning()


## -- Internal wave flow --

func _start_wave(act: int, wave: int) -> void:
	state = State.ACTIVE
	current_act = act
	current_wave = wave
	_assault_warning_fired = false
	_intermission_counting = false

	wave_duration = BASE_WAVE_DURATION + WAVE_DURATION_PER_ACT * float(act - 1)
	wave_time_left = wave_duration

	var police_total: int = _police_count_for(act, wave)
	_clear_police()
	_begin_spawning(police_total, wave_duration)

	wave_started.emit(wave, police_total)


func _complete_wave() -> void:
	state = State.PREPARING
	_stop_spawning()
	_clear_police()
	wave_completed.emit(current_wave)

	if current_wave >= WAVES_PER_ACT:
		state = State.ACT_COMPLETE
		act_completed.emit(current_act)
		return

	state = State.INTERMISSION
	wave_time_left = INTERMISSION_DURATION
	wave_duration = INTERMISSION_DURATION
	intermission_started.emit(current_wave + 1, INTERMISSION_DURATION)


## _process() ticks wave_time_left down during INTERMISSION the same way it
## does during ACTIVE (both just count down a shared timer), so the live
## pre-wave countdown advances automatically once begin_intermission_countdown()
## is called. When it reaches zero here, start the next wave instead of
## completing one.
func _on_intermission_elapsed() -> void:
	_intermission_counting = false
	intermission_finished.emit()
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
func _begin_spawning(total_police: int, duration: float) -> void:
	var spawner: Node = _get_police_spawner()
	if spawner != null:
		spawner.begin_wave(total_police, duration)
		return
	_pending_spawn_request = {"police": total_police, "duration": duration}


## Retries a spawn order that arrived before the PoliceSpawner existed. Called
## every frame from _process() until it lands.
func _flush_pending_spawn_request() -> void:
	if _pending_spawn_request.is_empty():
		return
	var spawner: Node = _get_police_spawner()
	if spawner == null:
		return
	spawner.begin_wave(_pending_spawn_request["police"], _pending_spawn_request["duration"])
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
