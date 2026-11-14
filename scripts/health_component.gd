extends Node
class_name HealthComponent

## Reusable health tracker, per agents/police-notes.md. Owns max/current
## health and nothing else -- damage sources call take_damage() directly
## (there's no separate "damage at controlled intervals" logic here; callers
## are expected to already be ticking on their own cooldown, same pattern as
## the existing scripts/destructible_prop.gd). Attached as a child node named
## "HealthComponent" on the player, police, and protester (NPC) scenes.

signal health_changed(current_health: float, max_health: float)
signal died

@export var max_health: float = 100.0

var current_health: float

var _dead: bool = false


func _ready() -> void:
	current_health = max_health


## Applies `amount` of damage (already pre-scaled by whatever interval/delta
## the caller uses), clamped to zero, and emits died() once on reaching it.
func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return

	current_health = max(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)

	if current_health <= 0.0:
		_dead = true
		died.emit()


func is_dead() -> bool:
	return _dead
