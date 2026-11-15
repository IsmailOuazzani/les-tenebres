extends Node
class_name WeaponSwitcher

## Owns which first-person weapon is equipped. `weapon_paths[0]` is slot 1
## (key "1"), `weapon_paths[1]` is slot 2 (key "2"), and so on.
##
## Calls activate()/deactivate() on each weapon, which handles its own
## visuals and gameplay input.

## Emitted whenever the equipped weapon changes (including once at startup)
## so UI (see scripts/hud.gd's hotbar) can mirror the active slot without
## polling.
signal weapon_switched(index: int)

@export var weapon_paths: Array[NodePath] = []

var _weapons: Array[Node] = []
var _active_index: int = 0

@onready var _player := get_parent().get_parent().get_parent() as NetPlayer


func _ready() -> void:
	var kit: int = _player.kit if _player != null else PlayerClass.Kit.SOLO
	for path in weapon_paths:
		var weapon := get_node(path)
		weapon.call(&"deactivate")
		if kit == PlayerClass.Kit.SOLO and weapon.name != &"ProtestSign":
			_weapons.append(weapon)
		elif kit != PlayerClass.Kit.SOLO and weapon.name in [&"Megaphone", _class_weapon_name(kit)]:
			_weapons.append(weapon)

	for i in _weapons.size():
		var equipped := is_multiplayer_authority() and i == _active_index
		_weapons[i].call(&"activate" if equipped else &"deactivate")
	weapon_switched.emit(_active_index)


func _unhandled_input(event: InputEvent) -> void:
	# Local player only -- remote players' equipped weapon is cosmetic and
	# their viewmodels are hidden entirely (see scripts/player.gd).
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed(&"weapon_1"):
		_switch_to(0)
	elif event.is_action_pressed(&"weapon_2"):
		_switch_to(1)
	elif event.is_action_pressed(&"weapon_3"):
		_switch_to(2)
	elif _active_index == 1 and _player != null and _player.kit == PlayerClass.Kit.MENEUR:
		if event.is_action_pressed(&"recruit"):
			_player.use_class_ability(PlayerClass.Ability.CROISSANT_SHOT)


func _class_weapon_name(kit: int) -> StringName:
	match kit:
		PlayerClass.Kit.SCOUT: return &"Baguette"
		PlayerClass.Kit.MENEUR: return &"Croissant"
		PlayerClass.Kit.MEDIC: return &"ProtestSign"
	return &""


## Display names for the hotbar, in slot order -- just the weapon nodes' own
## names (Megaphone, Croissant, ...) so adding a weapon to weapon_paths shows
## up automatically.
func get_weapon_names() -> Array[String]:
	var names: Array[String] = []
	for weapon in _weapons:
		names.append("Protest Sign" if weapon.name == &"ProtestSign" else String(weapon.name))
	return names


func get_active_index() -> int:
	return _active_index


func _switch_to(index: int) -> void:
	if index == _active_index or index >= _weapons.size():
		return
	_weapons[_active_index].call(&"deactivate")
	_active_index = index
	if _player != null:
		_player.publish_weapon_slot(index)
	_weapons[_active_index].call(&"activate")
	weapon_switched.emit(_active_index)
