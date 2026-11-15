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

var crowd_count: int = 1
## Spendable balance -- goes up on earn, down on spend_grabuge().
var grabuge_available: float = 0.0
## Monotonic lifetime total -- never decreases, drives civilian spawn rate.
var grabuge_total_earned: float = 0.0

var peak_crowd_count: int = 1
var total_disruptions: int = 0
## Run-total cops killed -- shown on the end-of-Act scoreboard (vision.md).
var police_defeated_count: int = 0

var _session_start_msec: int = 0
var _game_over_fired: bool = false


func _ready() -> void:
	_session_start_msec = Time.get_ticks_msec()


## Elapsed time since the session started, in seconds.
func get_session_duration() -> float:
	return (Time.get_ticks_msec() - _session_start_msec) / 1000.0


## Public entry point for earning Grabuge: raises both grabuge_available and
## grabuge_total_earned by `amount` (must be >= 0 -- this is an earn, not a
## spend; see spend_grabuge() for the other direction).
func add_grabuge(amount: float) -> void:
	if amount <= 0.0 or _game_over_fired:
		return
	grabuge_available += amount
	grabuge_total_earned += amount
	grabuge_changed.emit(grabuge_available, grabuge_total_earned)


## Attempts to spend `amount` from grabuge_available (e.g. an upgrade
## purchase). Returns true and deducts on success, false (no change) if the
## player can't afford it. Never touches grabuge_total_earned, so purchases
## never affect civilian spawn scaling.
func spend_grabuge(amount: float) -> bool:
	if amount <= 0.0 or amount > grabuge_available:
		return false
	grabuge_available -= amount
	grabuge_changed.emit(grabuge_available, grabuge_total_earned)
	return true


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


## Fired by Police._on_died() -- raises Grabuge by POLICE_DEFEAT_GRABUGE_BASE
## and notifies the snap feed with the amount awarded. See
## agents/snap-feed-notes.md.
func record_police_defeat() -> void:
	police_defeated_count += 1
	add_grabuge(POLICE_DEFEAT_GRABUGE_BASE)
	police_defeated.emit(POLICE_DEFEAT_GRABUGE_BASE)


## The only game-over trigger: the player's own HealthComponent.died (wired
## in scenes/test_map.gd, since that's the one non-vendored spot that
## already does similar debug-key-style wiring without touching
## addons/fps_controller/Player.tscn). See agents/police-notes.md.
func trigger_player_death() -> void:
	if _game_over_fired:
		return
	_game_over_fired = true
	game_over.emit()


## Resets all state. Called by game_over.gd's restart handler -- autoloads
## are NOT recreated by get_tree().reload_current_scene(), so without this
## _game_over_fired would stay true forever after a restart.
func reset() -> void:
	crowd_count = 1
	grabuge_available = 0.0
	grabuge_total_earned = 0.0
	peak_crowd_count = 1
	total_disruptions = 0
	police_defeated_count = 0
	_session_start_msec = Time.get_ticks_msec()
	_game_over_fired = false
	crowd_count_changed.emit(crowd_count)
	grabuge_changed.emit(grabuge_available, grabuge_total_earned)
