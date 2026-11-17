extends StaticBody3D
class_name DestructibleProp

## Destructible street prop (PoC) -- per vision.md's "Cause chaos: Protesters
## interact with the target, creating funny, physics-driven disruptions."
##
## Pure data + visuals: has no idea who's attacking it or why. CrowdController
## (scripts/crowd_controller.gd) finds props in the "destructible" group near
## an attack-command point and ticks take_damage() on them each physics frame
## for every recruited NPC within attack range -- this script only tracks
## health, shows a floating billboard health bar once damaged, and destroys
## itself at zero.

## ## Multiplayer
##
## Gameplay physics and destruction are **server-authoritative** (spec 2).
## Props are part of the statically loaded map scene, so they exist at the
## same node path on every peer and need no spawner -- they replicate their
## own state with two RPCs instead:
##
##   * `_net_health()` -- unreliable-ordered, throttled to ~10 Hz. A frequent
##     numeric stream feeding the floating health bar; dropping one is
##     invisible because the next supersedes it.
##   * `_net_destroy()` -- reliable, call_local. The significant world
##     interaction event (spec 5). Every peer then runs its own `_die()`, so
##     debris/shatter physics and the knock-over tween are simulated locally
##     from one replicated trigger rather than streamed piece by piece.
##
## Scoring (`GameState.record_disruption`) happens only on the server, in
## `_trigger_destruction()`, so one destroyed prop counts as one disruption no
## matter how many players are watching it fall over.

signal destroyed

@export var max_health: float = 100.0
## Optional subject for the protest chat. Empty leaves routine props quiet.
@export var snap_feed_topic: StringName = &""

## How often a damaged prop's health is pushed to clients, in milliseconds.
const _HEALTH_PUSH_INTERVAL_MSEC: int = 100

var current_health: float

var _last_health_push_msec: int = 0

@onready var _health_bar: ProgressBar3D = $HealthBar
@onready var _outline: MeshInstance3D = $Outline

var _dying: bool = false


func _ready() -> void:
	current_health = max_health
	add_to_group(&"destructible")
	_health_bar.max_value = max_health
	_health_bar.value = max_health
	_health_bar.visible = false
	_outline.visible = false


## Called by Megaphone every frame the player's aim raycast is/isn't hitting
## this prop -- per agents/mob-selector-notes.md, the reticle outlines
## whatever interactable is in view. Purely visual, no gameplay effect.
func set_targeted(active: bool) -> void:
	_outline.visible = active


## Called by CrowdController each physics frame for every attacking NPC in
## range -- `amount` is already pre-multiplied by delta, so this is just a
## clamped subtraction + visual update. Server-authoritative: a no-op on
## clients, whose health value arrives via `_net_health()` instead.
func take_damage(amount: float) -> void:
	if not NetworkManager.is_authoritative():
		return
	if _dying or amount <= 0.0:
		return

	_show_health(max(current_health - amount, 0.0))

	if current_health <= 0.0:
		_trigger_destruction()
		return

	var now: int = Time.get_ticks_msec()
	if NetworkManager.is_multiplayer_session() \
			and now - _last_health_push_msec >= _HEALTH_PUSH_INTERVAL_MSEC:
		_last_health_push_msec = now
		_net_health.rpc(current_health)


func _show_health(value: float) -> void:
	current_health = value
	_health_bar.visible = true
	_health_bar.value = current_health


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_health(value: float) -> void:
	_show_health(value)


## Server-side: scores the disruption once, then fans the destruction event
## out to every peer so each runs its own `_die()` locally.
func _trigger_destruction() -> void:
	if _dying:
		return
	GameState.record_disruption(1.0, snap_feed_topic)
	if NetworkManager.is_multiplayer_session():
		_net_destroy.rpc()
	else:
		_net_destroy()


@rpc("authority", "call_local", "reliable")
func _net_destroy() -> void:
	if _dying:
		return
	AudioManager.play_prop_break(global_position, _break_sound_key())
	_die()


func _break_sound_key() -> String:
	return "break_prop"


## Local destruction routine, run on every peer. Subclasses override this to
## add debris (scripts/destructible_vehicle.gd) or shatter
## (scripts/destructible_glass.gd); none of them do scoring or networking --
## that is `_trigger_destruction()`'s job.
func _die() -> void:
	_dying = true
	_health_bar.visible = false
	destroyed.emit()

	# Quick "knocked over" sell -- scale to zero rather than just vanishing,
	# so destruction reads as an event rather than a pop. Tip-over physics is
	# a stretch goal, not needed for the PoC.
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(queue_free)
