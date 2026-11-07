extends Node

## GameState: global meta-systems singleton (publicity, patience, crowd count).
##
## Registered as the `GameState` autoload (see project.godot [autoload]).
## See agents/publicity-patience-notes.md for the full API reference,
## the temporary debug keybinds, and what here is a stub vs. real.

signal game_over
signal publicity_changed(new_value: float)
signal patience_changed(new_value: float)
signal crowd_count_changed(new_value: int)
signal disruption_recorded(total: int)

const PATIENCE_MAX: float = 100.0

## Stub drain rate: patience lost per second when nothing interesting happens.
## Per vision.md: "decreases when nothing interesting happens for too long."
## Real implementation will likely pause/scale this based on actual activity
## (recent recruits, disruptions, crowd separation) once that gameplay exists.
const PATIENCE_DRAIN_PER_SECOND: float = 0.5

const RECRUIT_PATIENCE_BONUS: float = 2.0
const DISRUPTION_PUBLICITY_BASE: float = 15.0

var crowd_count: int = 1
var publicity: float = 0.0
var patience: float = PATIENCE_MAX

var peak_crowd_count: int = 1
var total_disruptions: int = 0
var total_publicity_generated: float = 0.0

var _session_start_msec: int = 0
var _game_over_fired: bool = false


func _ready() -> void:
	_session_start_msec = Time.get_ticks_msec()


func _process(delta: float) -> void:
	if _game_over_fired:
		return
	_drain_patience(PATIENCE_DRAIN_PER_SECOND * delta)


## Elapsed time since the session started, in seconds.
func get_session_duration() -> float:
	return (Time.get_ticks_msec() - _session_start_msec) / 1000.0


func add_publicity(amount: float) -> void:
	if amount == 0.0:
		return
	publicity = max(0.0, publicity + amount)
	total_publicity_generated += max(0.0, amount)
	publicity_changed.emit(publicity)


func recruit_npc() -> void:
	crowd_count += 1
	peak_crowd_count = max(peak_crowd_count, crowd_count)
	crowd_count_changed.emit(crowd_count)
	_add_patience(RECRUIT_PATIENCE_BONUS)


## Records a successful disruption: bumps the disruption counter and
## generates publicity. `magnitude` is a stub scalar (1.0 = normal-sized
## disruption) for when bigger/more ridiculous disruptions should generate
## proportionally more publicity, per vision.md.
func record_disruption(magnitude: float = 1.0) -> void:
	total_disruptions += 1
	disruption_recorded.emit(total_disruptions)
	add_publicity(DISRUPTION_PUBLICITY_BASE * magnitude)
	_add_patience(5.0)


func _add_patience(amount: float) -> void:
	_drain_patience(-amount)


## Shared implementation for raising/lowering patience, clamped to
## [0, PATIENCE_MAX]. Positive `amount` drains, negative `amount` restores.
func _drain_patience(amount: float) -> void:
	if _game_over_fired:
		return
	patience = clamp(patience - amount, 0.0, PATIENCE_MAX)
	patience_changed.emit(patience)
	if patience <= 0.0:
		_game_over_fired = true
		game_over.emit()


## Resets all state. Not currently wired to anything except a manual restart
## flow (e.g. reloading the main scene recreates the autoload automatically,
## so this is mostly here for completeness / future use, e.g. a "play again
## without reload" button).
func reset() -> void:
	crowd_count = 1
	publicity = 0.0
	patience = PATIENCE_MAX
	peak_crowd_count = 1
	total_disruptions = 0
	total_publicity_generated = 0.0
	_session_start_msec = Time.get_ticks_msec()
	_game_over_fired = false
	crowd_count_changed.emit(crowd_count)
	publicity_changed.emit(publicity)
	patience_changed.emit(patience)
