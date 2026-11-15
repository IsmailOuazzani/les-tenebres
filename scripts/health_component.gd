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
