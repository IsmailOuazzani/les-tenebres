extends Node3D

## Grey-box test map bootstrap.
## Captures the mouse for FPS look and lets you quit/release the mouse,
## mirroring the behavior from the vendored FirstPersonStarter sample scene.
##
## Also applies player-side UpgradeManager purchases (speed/jump/health) from
## OUTSIDE the vendored addons/fps_controller/ scene, the same pattern as the
## player-death wiring below -- see agents/wave-survival-notes.md's
## integration contract. Crowd-side upgrades (crowd_speed/health/damage) are
## applied by scripts/npc.gd and scripts/crowd_controller.gd themselves,
## since those scripts aren't vendored and can just read UpgradeManager
## directly.

## MovementController.speed/jump_height and Sprint's normal_speed/sprint_speed
## are statically typed `int` on the vendored addon scripts -- round rather
## than truncate so a +10%/+15% bump is never silently floored to zero effect
## at low base values.
@onready var _movement_controller: MovementController = get_node_or_null("Player")
## Untyped on purpose: Sprint.gd (addons/fps_controller/Sprint.gd) has no
## class_name, and typing this as plain `Node` would make `.normal_speed` /
## `.sprint_speed` a static-analysis error (those properties don't exist on
## Node). Leaving the var without a declared type makes GDScript resolve
## them dynamically at runtime instead -- see the Sprint gotcha in
## agents/wave-survival-notes.md.
@onready var _sprint = get_node_or_null("Player/Sprint")
@onready var _player_health: HealthComponent = get_node_or_null("Player/HealthComponent")

## Base values captured once at _ready(), before any upgrade is applied, so
## every later re-application derives from the same starting point instead
## of multiplying an already-multiplied live value (which would compound on
## repeat purchases). Captured as floats even though the underlying fields
## are typed `int` on the vendored scripts.
var _base_player_speed: float = 0.0
var _base_player_jump_height: float = 0.0
var _base_sprint_speed: float = 0.0
var _base_player_max_health: float = 0.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Player death (cops) is a second way to reach game-over besides Grabuge
	# decay -- wired here rather than inside addons/fps_controller/Player.tscn
	# so the vendored player scene doesn't need to know about GameState. See
	# agents/police-notes.md.
	var player_health: Node = get_node_or_null("Player/HealthComponent")
	if player_health != null:
		player_health.died.connect(GameState.trigger_player_death)

	_capture_player_upgrade_bases()
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)


func _capture_player_upgrade_bases() -> void:
	if _movement_controller != null:
		_base_player_speed = float(_movement_controller.speed)
		_base_player_jump_height = float(_movement_controller.jump_height)
	if _sprint != null:
		_base_sprint_speed = float(_sprint.sprint_speed)
	if _player_health != null:
		_base_player_max_health = _player_health.max_health


func _on_upgrade_purchased(id: StringName, _new_level: int) -> void:
	match id:
		&"player_speed":
			_apply_player_speed()
		&"player_jump":
			_apply_player_jump()
		&"player_health":
			_apply_player_health()


func _apply_player_speed() -> void:
	if _movement_controller == null:
		return
	var mult: float = UpgradeManager.player_speed_mult
	_movement_controller.speed = roundi(_base_player_speed * mult)
	# The GOTCHA: Sprint.gd caches `normal_speed` from controller.speed in
	# its own _ready() and writes it back to controller.speed every frame the
	# player isn't sprinting (see Sprint._physics_process()). Only updating
	# controller.speed above gets silently clobbered back to the old value
	# the next time the player releases sprint -- so the cached copy has to
	# be bumped too. Also scale sprint_speed by the same multiplier so
	# sprinting itself benefits from the upgrade instead of staying fixed.
	if _sprint != null:
		_sprint.normal_speed = roundi(_base_player_speed * mult)
		_sprint.sprint_speed = roundi(_base_sprint_speed * mult)


func _apply_player_jump() -> void:
	if _movement_controller == null:
		return
	_movement_controller.jump_height = roundi(_base_player_jump_height * UpgradeManager.player_jump_mult)


## Health has no multiplier -- player_bonus_health is a flat sum of every
## player_health level purchased (see upgrade_manager.gd), so max_health is
## recomputed from the captured base rather than incremented in place.
## HealthComponent.health_changed only fires from take_damage() (there's no
## heal/raise-max method, and health_component.gd isn't ours to edit per the
## brief) -- so after mutating max_health/current_health directly, this
## emits health_changed itself. Emitting a node's own public signal from
## outside its script is unusual but is the only path that gets the HUD's
## health bar (scripts/hud.gd, listening to this exact signal) to redraw
## without touching health_component.gd.
func _apply_player_health() -> void:
	if _player_health == null:
		return
	var new_max: float = _base_player_max_health + UpgradeManager.player_bonus_health
	_player_health.max_health = new_max
	_player_health.current_health = min(
		_player_health.current_health + UpgradeManager.PLAYER_HEALTH_STEP, new_max
	)
	_player_health.health_changed.emit(_player_health.current_health, _player_health.max_health)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()

	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# --- DEBUG HOOKS ---
	# G is the permanent Grabuge debug key per the original spec. O/I are
	# temporary stand-ins for contextual-disruption gameplay that doesn't
	# exist yet -- real megaphone recruitment already calls
	# GameState.recruit_npc() on its own (see scripts/crowd_controller.gd),
	# so KEY_O is now mostly redundant with that; remove it once disruption
	# gameplay (bus/road/plaza interactions) makes KEY_I unnecessary too.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_G:
				GameState.add_grabuge(GameState.DEBUG_GRABUGE_BUMP)
			KEY_O:
				GameState.recruit_npc()
			KEY_I:
				GameState.record_disruption()
