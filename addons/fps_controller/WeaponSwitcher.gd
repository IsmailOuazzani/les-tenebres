extends Node
class_name WeaponSwitcher

## Owns which first-person weapon is equipped. `weapon_paths[0]` is slot 1
## (key "1"), `weapon_paths[1]` is slot 2 (key "2"), and so on.
##
## Doesn't know anything about what a weapon does -- just calls
## activate()/deactivate() on the Megaphone/Croissant-shaped node at the
## selected index and leaves the rest (visuals, input handling) to that
## weapon itself. Add a third weapon by appending to weapon_paths and giving
## it the same two methods; no change needed here.

## Emitted whenever the equipped weapon changes (including once at startup)
## so UI (see scripts/hud.gd's hotbar) can mirror the active slot without
## polling.
signal weapon_switched(index: int)

@export var weapon_paths: Array[NodePath] = []

var _weapons: Array[Node] = []
var _active_index: int = 0


func _ready() -> void:
	for path in weapon_paths:
		_weapons.append(get_node(path))

	for i in _weapons.size():
		_weapons[i].call(&"activate" if i == _active_index else &"deactivate")
	weapon_switched.emit(_active_index)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"weapon_1"):
		_switch_to(0)
	elif event.is_action_pressed(&"weapon_2"):
		_switch_to(1)


## Display names for the hotbar, in slot order -- just the weapon nodes' own
## names (Megaphone, Croissant, ...) so adding a weapon to weapon_paths shows
## up automatically.
func get_weapon_names() -> Array[String]:
	var names: Array[String] = []
	for weapon in _weapons:
		names.append(weapon.name)
	return names


func get_active_index() -> int:
	return _active_index


func _switch_to(index: int) -> void:
	if index == _active_index or index >= _weapons.size():
		return
	_weapons[_active_index].call(&"deactivate")
	_active_index = index
	_weapons[_active_index].call(&"activate")
	weapon_switched.emit(_active_index)
