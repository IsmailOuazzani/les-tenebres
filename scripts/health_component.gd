extends Node
class_name HealthComponent

## Tracks health and optional armor. Damage sources handle their own timing
## and call take_damage() directly. The shop grants armor to player
## characters through this component.

signal health_changed(current_health: float, max_health: float)
signal armor_changed(current_armor: float)
signal died

const MAX_ARMOR: float = 25.0

@export var max_health: float = 100.0

var current_health: float
var armor: float = 0.0:
	set(value):
		var clamped: float = clampf(value, 0.0, MAX_ARMOR)
		if clamped == armor:
			return
		armor = clamped
		armor_changed.emit(armor)

var _dead: bool = false


func _ready() -> void:
	current_health = max_health


## Applies `amount` of damage (already pre-scaled by whatever interval/delta
## the caller uses), clamped to zero, and emits died() once on reaching it.
##
## Damage is **server-authoritative** (see agents/multiplayer-notes.md): on a
## client this is a no-op, and the resulting health value arrives back as
## replicated state instead. Clients therefore never need to be trusted about
## who died, and a client mispredicting a kill is impossible by construction.
func take_damage(amount: float) -> void:
	if not NetworkManager.is_authoritative():
		return
	if _dead or amount <= 0.0:
		return

	if armor > 0.0:
		var absorbed: float = minf(armor, amount)
		armor -= absorbed
		amount -= absorbed
		if amount <= 0.0:
			return

	current_health = max(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)

	if current_health <= 0.0:
		_dead = true
		died.emit()


func is_dead() -> bool:
	return _dead


## Client-side mirror of a replicated health value. Updates `current_health`
## and re-emits `health_changed` (so HUDs/health bars behave identically on
## host and client) *without* running the death path -- death is the server's
## call and arrives as its own replicated state.
func set_replicated_health(value: float) -> void:
	current_health = clamp(value, 0.0, max_health)
	health_changed.emit(current_health, max_health)


## Server-side: restores full health and clears the death latch. Used by the
## 5-second player respawn (see scripts/player.gd / scenes/test_map.gd);
## NPCs and police are despawned on death instead of revived.
func revive() -> void:
	_dead = false
	current_health = max_health
	health_changed.emit(current_health, max_health)
