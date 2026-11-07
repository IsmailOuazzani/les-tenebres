extends Node3D
class_name Megaphone

## First-person megaphone viewmodel + click-command hooks.
##
## This node is purely player-facing: it owns the held prop, its raise/shake
## animation, and the two signals below. It does NOT know about NPCs or the
## crowd. The future crowd/NPC system should connect to the signals emitted
## here. See `agents/megaphone-notes.md` for the integration contract.

## Emitted when the player left-clicks ("Recruit"). `target_position` is the
## world-space point the camera raycast hit (or a point at `ray_range` along
## the look direction if nothing was hit).
signal recruit_triggered(target_position: Vector3)

## Emitted when the player right-clicks ("À L'ATTAQUE!"). `target_position`
## is the world-space point the camera raycast hit (or a point at
## `ray_range` along the look direction if nothing was hit).
signal attack_command_triggered(target_position: Vector3)

@export var ray_range := 50.0
## Physics layer mask used for the aim raycast. Defaults to layer 1
## ("Objects" per project.godot's [layer_names]) so the player's own
## collision (layer 2, "Player") never self-intersects the ray.
@export var ray_collision_mask := 1

@onready var visual_root: Node3D = $VisualRoot
@onready var muzzle: Marker3D = $VisualRoot/MuzzlePoint
@onready var burst: CPUParticles3D = $VisualRoot/Burst
@onready var flash: ColorRect = $UILayer/Flash
@onready var feedback_label: Label = $UILayer/FeedbackLabel

var _rest_position: Vector3
var _rest_rotation: Vector3
var _anim_tween: Tween
var _label_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	_rest_position = visual_root.position
	_rest_rotation = visual_root.rotation
	flash.color = Color(1, 1, 1, 0)
	feedback_label.text = ""
	feedback_label.modulate.a = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"recruit"):
		_do_recruit()
	elif event.is_action_pressed(&"attack_command"):
		_do_attack_command()


func _do_recruit() -> void:
	var target := _raycast_target()
	_play_raise_shake()
	_spawn_recruit_burst()
	_show_feedback("RECRUITING...", Color(0.35, 0.9, 0.45))
	recruit_triggered.emit(target)


func _do_attack_command() -> void:
	var target := _raycast_target()
	_play_raise_shake()
	_flash_screen()
	_spawn_attack_marker(target)
	_show_feedback("A L'ATTAQUE !", Color(0.95, 0.2, 0.2))
	attack_command_triggered.emit(target)


## Raycasts from the active camera along its look direction. Returns the hit
## point, or a point `ray_range` meters out along the look direction if the
## ray hits nothing (or there is no active camera), so callers always get a
## usable Vector3.
func _raycast_target() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position - global_transform.basis.z * ray_range

	var origin: Vector3 = cam.global_transform.origin
	var direction: Vector3 = -cam.global_transform.basis.z

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			origin, origin + direction * ray_range, ray_collision_mask)
	var result := space_state.intersect_ray(query)
	if result:
		return result.position
	return origin + direction * ray_range


func _play_raise_shake() -> void:
	if _anim_tween:
		_anim_tween.kill()

	_anim_tween = create_tween()
	var raised_pos := _rest_position + Vector3(0.0, 0.05, -0.04)
	var raised_rot := _rest_rotation + Vector3(deg_to_rad(-8), 0.0, deg_to_rad(4))

	# Quick raise.
	_anim_tween.tween_property(visual_root, "position", raised_pos, 0.08)
	_anim_tween.parallel().tween_property(visual_root, "rotation", raised_rot, 0.08)

	# Shake (a couple of small rotation wobbles while raised).
	for i in range(3):
		var shake_rot := raised_rot + Vector3(0.0, 0.0, deg_to_rad(9 if i % 2 == 0 else -9))
		_anim_tween.tween_property(visual_root, "rotation", shake_rot, 0.05)

	# Settle back to rest.
	_anim_tween.tween_property(visual_root, "position", _rest_position, 0.15)
	_anim_tween.parallel().tween_property(visual_root, "rotation", _rest_rotation, 0.15)


func _spawn_recruit_burst() -> void:
	burst.restart()
	burst.emitting = true


func _flash_screen() -> void:
	if _flash_tween:
		_flash_tween.kill()

	flash.color = Color(0.95, 0.25, 0.2, 0.35)
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash, "color:a", 0.0, 0.3)


## Drops a small, self-removing marker mesh at the hit point as a stand-in
## for a future decal/VFX. Purely cosmetic — no gameplay meaning.
func _spawn_attack_marker(target_position: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	marker.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.2, 0.2)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material

	get_tree().current_scene.add_child(marker)
	marker.global_position = target_position

	var tween := marker.create_tween()
	tween.tween_property(marker, "scale", Vector3.ZERO, 0.8).set_delay(0.1)
	tween.tween_callback(marker.queue_free)


func _show_feedback(text: String, color: Color) -> void:
	if _label_tween:
		_label_tween.kill()

	feedback_label.text = text
	feedback_label.modulate = Color(color.r, color.g, color.b, 0.0)

	_label_tween = create_tween()
	_label_tween.tween_property(feedback_label, "modulate:a", 1.0, 0.05)
	_label_tween.tween_interval(0.4)
	_label_tween.tween_property(feedback_label, "modulate:a", 0.0, 0.3)
