extends Node

## GameState: global Grabuge + crowd-count singleton.
##
## Registered as the `GameState` autoload (see project.godot [autoload]).
## Grabuge is the single shared chaos/excitement resource described in
## vision.md -- it replaces the earlier separate Publicity/Patience/Zbeul
## meters (see agents/grabuge-notes.md for the migration). Game-over fires
## when Grabuge decays to zero; NPC dispersal on game-over is still deferred.

signal grabuge_changed(new_value: float)
signal crowd_count_changed(new_value: int)
signal disruption_recorded(total: int)
signal game_over

const GRABUGE_MAX: float = 100.0

## Balancing constants -- tweak here. Grabuge decays continuously regardless
## of what the player does; recruiting and disruptions push it back up.
const GRABUGE_DECAY_PER_SECOND: float = 1.5
const RECRUIT_GRABUGE_BONUS: float = 2.0
const DISRUPTION_GRABUGE_BASE: float = 15.0
## Debug key (see scenes/test_map.gd) bump amount, per the original spec's
## "G: Increase Grabuge by 20."
const DEBUG_GRABUGE_BUMP: float = 20.0

var crowd_count: int = 1
var grabuge: float = 0.0

var peak_crowd_count: int = 1
var peak_grabuge: float = 0.0
var total_disruptions: int = 0

var _session_start_msec: int = 0
var _game_over_fired: bool = false


func _ready() -> void:
	_session_start_msec = Time.get_ticks_msec()


func _process(delta: float) -> void:
	if _game_over_fired:
		return
	var was_positive: bool = grabuge > 0.0
	add_grabuge(-GRABUGE_DECAY_PER_SECOND * delta)
	if was_positive and grabuge <= 0.0:
		_game_over_fired = true
		game_over.emit()


## Elapsed time since the session started, in seconds.
func get_session_duration() -> float:
	return (Time.get_ticks_msec() - _session_start_msec) / 1000.0


## Public entry point for raising/lowering Grabuge, clamped to
## [0, GRABUGE_MAX]. Positive `amount` raises it, negative lowers it (used
## internally for passive decay).
func add_grabuge(amount: float) -> void:
	if amount == 0.0 or _game_over_fired:
		return
	grabuge = clamp(grabuge + amount, 0.0, GRABUGE_MAX)
	peak_grabuge = max(peak_grabuge, grabuge)
	grabuge_changed.emit(grabuge)


func recruit_npc() -> void:
	crowd_count += 1
	peak_crowd_count = max(peak_crowd_count, crowd_count)
	crowd_count_changed.emit(crowd_count)
	add_grabuge(RECRUIT_GRABUGE_BONUS)


## Records a successful disruption: bumps the disruption counter and raises
## Grabuge. `magnitude` is a stub scalar (1.0 = normal-sized disruption) for
## when bigger/more ridiculous disruptions should raise Grabuge
## proportionally more, per vision.md.
func record_disruption(magnitude: float = 1.0) -> void:
	total_disruptions += 1
	disruption_recorded.emit(total_disruptions)
	add_grabuge(DISRUPTION_GRABUGE_BASE * magnitude)


## Resets all state. Called by game_over.gd's restart handler -- autoloads
## are NOT recreated by get_tree().reload_current_scene(), so without this
## _game_over_fired would stay true forever after a restart.
func reset() -> void:
	crowd_count = 1
	grabuge = 0.0
	peak_crowd_count = 1
	peak_grabuge = 0.0
	total_disruptions = 0
	_session_start_msec = Time.get_ticks_msec()
	_game_over_fired = false
	crowd_count_changed.emit(crowd_count)
	grabuge_changed.emit(grabuge)
