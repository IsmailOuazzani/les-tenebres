extends Node3D
class_name Croissant

## First-person croissant melee weapon.
##
## Click swings it and checks a short raycast straight ahead for a hit on
## anything in the "destructible" group, dealing a flat chunk of damage --
## no hold-to-charge, no recruiting, just bonk. Switching between this and
## Megaphone is owned by WeaponSwitcher.gd (see WeaponSwitcher.gd), which
## calls activate()/deactivate() below; Croissant never decides when it's
## equipped on its own.
##
## The model here is a placeholder (bent primitive meshes, same spirit as
## npc.gd's capsule+sphere civilians) -- swap VisualRoot/CroissantModel for a
## real asset (e.g. Kenney's CC0 Food Kit) whenever one's on hand.

@export var ray_range := 2.2
## Physics layer mask used for the hit raycast. Matches Megaphone's aim ray
## (layer 1, "Objects") so the same destructible props are hittable.
@export var ray_collision_mask := 1
@export var hit_damage := 15.0
@export var swing_duration := 0.22

@onready var visual_root: Node3D = $VisualRoot
@onready var crumb_burst: CPUParticles3D = $VisualRoot/CrumbBurst

var _is_active: bool = false
var _rest_rotation: Vector3
var _swing_tween: Tween


func _ready() -> void:
	_rest_rotation = visual_root.rotation
	visual_root.visible = _is_active


func _unhandled_input(event: InputEvent) -> void:
	if not _is_active:
		return
	if event.is_action_pressed(&"send_mob"):
		_swing_and_hit()


## Called by WeaponSwitcher.gd when the player equips this weapon.
func activate() -> void:
	_is_active = true
	visual_root.visible = true


## Called by WeaponSwitcher.gd when the player switches away from this
## weapon.
func deactivate() -> void:
	_is_active = false
	if _swing_tween:
		_swing_tween.kill()
	visual_root.rotation = _rest_rotation
	visual_root.visible = false


func _swing_and_hit() -> void:
	_play_swing()
	_try_hit()


## Quick downward-forward chop and back, mirroring the raise/shake shape
## Megaphone._play_raise_shake() uses for its own click feedback.
func _play_swing() -> void:
	if _swing_tween:
		_swing_tween.kill()

	_swing_tween = create_tween()
	var swing_rot := _rest_rotation + Vector3(deg_to_rad(-40), deg_to_rad(-12), deg_to_rad(18))
	_swing_tween.tween_property(visual_root, "rotation", swing_rot, swing_duration * 0.4)
	_swing_tween.tween_property(visual_root, "rotation", _rest_rotation, swing_duration * 0.6)


## Straight-ahead raycast from the camera, same shape as Megaphone's aim
## ray -- an instant hit rather than a per-frame tick, since this is a single
## click, not a held command.
func _try_hit() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var origin: Vector3 = cam.global_transform.origin
	var direction: Vector3 = -cam.global_transform.basis.z
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			origin, origin + direction * ray_range, ray_collision_mask)
	var result := space_state.intersect_ray(query)
	if not result:
		return

	var collider: Object = result.collider
	if collider is Node3D and collider.is_in_group(&"destructible") and collider.has_method("take_damage"):
		collider.take_damage(hit_damage)
		crumb_burst.restart()
		crumb_burst.emitting = true
