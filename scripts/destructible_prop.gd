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

signal destroyed

@export var max_health: float = 100.0

var current_health: float

@onready var _health_bar: Node3D = $HealthBar
@onready var _fill: MeshInstance3D = $HealthBar/Fill

var _dying: bool = false


func _ready() -> void:
	current_health = max_health
	add_to_group(&"destructible")
	_health_bar.visible = false


## Called by CrowdController each physics frame for every attacking NPC in
## range -- `amount` is already pre-multiplied by delta, so this is just a
## clamped subtraction + visual update.
func take_damage(amount: float) -> void:
	if _dying or amount <= 0.0:
		return

	current_health = max(current_health - amount, 0.0)
	_health_bar.visible = true
	_fill.scale.x = current_health / max_health

	if current_health <= 0.0:
		_die()


func _die() -> void:
	_dying = true
	_health_bar.visible = false
	destroyed.emit()
	GameState.record_disruption(1.0)

	# Quick "knocked over" sell -- scale to zero rather than just vanishing,
	# so destruction reads as an event rather than a pop. Tip-over physics is
	# a stretch goal, not needed for the PoC.
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(queue_free)
