extends Node3D
class_name Megaphone

## First-person megaphone viewmodel + click/hold-command hooks.
##
## This node is purely player-facing: it owns the held prop, the recruitment
## influence cone, raise/shake animation, and the signals below. It does NOT
## know about NPCs or the crowd -- CrowdController (scripts/crowd_controller.gd)
## polls `is_recruiting_held()` / `is_point_within_cone()` itself rather than
## this script reaching into NPCs. See `agents/megaphone-notes.md` for the
## full integration contract.

## Emitted when the player releases right-click after a short hold
## ("À L'ATTAQUE!"). `target_position` is the world-space point the camera
## raycast hit at the moment the click started (or a point at `ray_range`
## along the look direction if nothing was hit).
signal attack_command_triggered(target_position: Vector3)

## Emitted when the player releases right-click after holding it past
## `regroup_hold_threshold_msec` (vision.md: "Hold Right Click = Regroup").
signal regroup_triggered

@export var ray_range := 50.0
## Physics layer mask used for the aim raycast. Defaults to layer 1
## ("Objects" per project.godot's [layer_names]) so the player's own
## collision (layer 2, "Player") never self-intersects the ray.
@export var ray_collision_mask := 1

## How long right-click has to be held (milliseconds) before release counts
## as "Regroup" instead of a normal "À L'ATTAQUE!" click.
@export var regroup_hold_threshold_msec := 350

## -- Recruitment influence cone --
## Driven by GameState.grabuge via piecewise-linear interpolation across
## these three keyframes (0%/50%/100%), per the original spec's balancing
## table. `cone_range`/`cone_angle_degrees` below are the live computed
## values (read by is_point_within_cone() and the visual mesh) -- don't
## edit those directly, tune the keyframes instead.
@export var cone_range_at_0pct := 6.0
@export var cone_range_at_50pct := 18.0
@export var cone_range_at_100pct := 35.0
@export var cone_angle_at_0pct := 25.0
@export var cone_angle_at_50pct := 50.0
@export var cone_angle_at_100pct := 80.0

var cone_range: float = cone_range_at_0pct
var cone_angle_degrees: float = cone_angle_at_0pct

@onready var visual_root: Node3D = $VisualRoot
@onready var muzzle: Marker3D = $VisualRoot/MuzzlePoint
@onready var burst: CPUParticles3D = $VisualRoot/Burst
@onready var flash: ColorRect = $UILayer/Flash
@onready var feedback_label: Label = $UILayer/FeedbackLabel
@onready var influence_cone: MeshInstance3D = $InfluenceCone

var _rest_position: Vector3
var _rest_rotation: Vector3
var _anim_tween: Tween
var _label_tween: Tween
var _flash_tween: Tween

var _recruiting_held: bool = false
var _attack_press_target: Vector3 = Vector3.ZERO
var _attack_press_time_msec: int = 0
var _recruit_burst_timer: float = 0.0
const RECRUIT_BURST_INTERVAL := 0.5


func _ready() -> void:
	_rest_position = visual_root.position
	_rest_rotation = visual_root.rotation
	flash.color = Color(1, 1, 1, 0)
	feedback_label.text = ""
	feedback_label.modulate.a = 0.0
	influence_cone.visible = false
	GameState.grabuge_changed.connect(_on_grabuge_changed)
	_on_grabuge_changed(GameState.grabuge)


## Pulses the recruit particle burst at the horn's mouth every
## RECRUIT_BURST_INTERVAL seconds while the cone is active -- subtle
## "sound-wave" feedback per vision.md's megaphone description, using the
## existing one-shot burst rather than a new effect.
func _process(delta: float) -> void:
	if not _recruiting_held:
		return
	_recruit_burst_timer -= delta
	if _recruit_burst_timer <= 0.0:
		_recruit_burst_timer = RECRUIT_BURST_INTERVAL
		_spawn_recruit_burst()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"recruit"):
		_start_recruit()
	elif event.is_action_released(&"recruit"):
		_stop_recruit()
	elif event.is_action_pressed(&"attack_command"):
		_attack_press_time_msec = Time.get_ticks_msec()
		_attack_press_target = _raycast_target()
	elif event.is_action_released(&"attack_command"):
		var held_msec: int = Time.get_ticks_msec() - _attack_press_time_msec
		if held_msec >= regroup_hold_threshold_msec:
			_do_regroup()
		else:
			_do_attack_command(_attack_press_target)


## True while the player is holding the recruit input and the influence cone
## is showing. CrowdController polls this each physics frame.
func is_recruiting_held() -> bool:
	return _recruiting_held


## True if `point` (world space) falls inside the recruitment cone right now
## -- a simple range + half-angle check against the active camera, decoupled
## from the cone's visual mesh so recruitment logic doesn't depend on the
## mesh being pixel-perfect.
func is_point_within_cone(point: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false

	var origin: Vector3 = cam.global_transform.origin
	var to_point: Vector3 = point - origin
	var distance: float = to_point.length()
	if distance < 0.001 or distance > cone_range:
		return false

	var forward: Vector3 = -cam.global_transform.basis.z
	var cos_angle: float = forward.normalized().dot(to_point / distance)
	var half_angle_rad: float = deg_to_rad(cone_angle_degrees * 0.5)
	return cos_angle >= cos(half_angle_rad)


func _start_recruit() -> void:
	_recruiting_held = true
	influence_cone.visible = true
	_recruit_burst_timer = 0.0
	_show_feedback("RECRUITING...", Color(0.35, 0.9, 0.45))


func _stop_recruit() -> void:
	_recruiting_held = false
	influence_cone.visible = false


func _do_attack_command(target: Vector3) -> void:
	_play_raise_shake()
	_flash_screen()
	_spawn_attack_marker(target)
	_show_feedback("A L'ATTAQUE !", Color(0.95, 0.2, 0.2))
	attack_command_triggered.emit(target)


func _do_regroup() -> void:
	_play_raise_shake()
	_show_feedback("REGROUPEZ-VOUS !", Color(0.3, 0.6, 0.95))
	regroup_triggered.emit()


## Recomputes cone_range/cone_angle_degrees from the current Grabuge value
## (piecewise-linear across the 0/50/100% keyframes) and rebuilds the mesh.
func _on_grabuge_changed(value: float) -> void:
	cone_range = _piecewise_lerp(value, cone_range_at_0pct, cone_range_at_50pct, cone_range_at_100pct)
	cone_angle_degrees = _piecewise_lerp(value, cone_angle_at_0pct, cone_angle_at_50pct, cone_angle_at_100pct)
	_update_cone_shape()


## Linear interpolation across two segments (0-50, 50-100) instead of one
## straight 0-100 lerp, since the balancing table's three keyframes aren't
## collinear (e.g. range goes 6 -> 18 -> 35, a steeper slope in the second
## half).
func _piecewise_lerp(value: float, at_0: float, at_50: float, at_100: float) -> float:
	var clamped: float = clamp(value, 0.0, 100.0)
	if clamped <= 50.0:
		return lerp(at_0, at_50, clamped / 50.0)
	return lerp(at_50, at_100, (clamped - 50.0) / 50.0)


## Builds the cone mesh from the current `cone_range`/`cone_angle_degrees`.
func _update_cone_shape() -> void:
	var mesh: CylinderMesh = influence_cone.mesh as CylinderMesh
	if mesh == null:
		return
	var half_angle_rad: float = deg_to_rad(cone_angle_degrees * 0.5)
	mesh.height = cone_range
	mesh.top_radius = 0.0
	mesh.bottom_radius = cone_range * tan(half_angle_rad)
	# Cylinder is centered on its own origin; rotation_degrees=(-90,0,0) on
	# the node (set in Megaphone.tscn) maps its +Y (apex, top_radius=0) to
	# local -Z (forward). Shifting the node forward by half the height moves
	# the apex to the camera (z=0) and the wide base out to cone_range.
	influence_cone.position = Vector3(0, 0, -cone_range * 0.5)


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
