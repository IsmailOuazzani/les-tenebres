extends Node3D
class_name Megaphone

## First-person megaphone viewmodel + click/hold-command hooks.
##
## This node is purely player-facing: it owns the held prop, the recruitment
## influence cone, the aim reticle/outline, raise/shake animation, and the
## signal below. It does NOT know about NPCs or the crowd --
## CrowdController (scripts/crowd_controller.gd) polls `is_recruiting_held()`
## / `is_point_within_cone()` and listens for `send_mob_triggered` itself
## rather than this script reaching into NPCs. See `agents/megaphone-notes.md`
## and `agents/mob-selector-notes.md` for the full integration contract.
##
## Checking `is_in_group("destructible")` on the raycast hit below is the one
## exception to "doesn't know about NPCs/crowd" -- it's a visual-only check
## (which object gets the outline reticle), not crowd logic.

## Emitted when the player releases Send Mob (hold Left Click). `percentage`
## (0-1) is how much of the recruited mob to commit, per the hold-to-charge
## ramp. `target` is the destructible object the reticle was outlining at
## release time, or null if the reticle was showing the yellow-ball fallback
## -- per agents/mob-selector-notes.md, attack and regroup are the same
## command; CrowdController decides what null vs. non-null means.
signal send_mob_triggered(percentage: float, target: Node3D)

@export var ray_range := 50.0
## Physics layer mask used for the aim raycast. Defaults to layer 1
## ("Objects" per project.godot's [layer_names]) so the player's own
## collision (layer 2, "Player") never self-intersects the ray.
@export var ray_collision_mask := 1

## -- Send Mob hold-to-charge --
## How long (milliseconds) Send Mob must be held to ramp from the tap floor
## up to committing 100% of the mob.
@export var send_ramp_duration_msec := 1200
## Minimum share of the mob a quick tap still commits, so a tap always does
## something (0-1).
@export var send_tap_floor_percentage := 0.1

## -- Recruitment influence cone --
## Driven by GameState.grabuge (0-100%): linearly interpolated from the
## *_min values at 0% to the *_max values at 100%. `cone_range`/
## `cone_angle_degrees` below are the live computed values (read by
## is_point_within_cone() and the visual mesh) -- don't edit those
## directly, tune the min/max exports instead.
@export var cone_range_min := 6.0
@export var cone_range_max := 35.0
@export var cone_angle_min := 25.0
@export var cone_angle_max := 80.0

var cone_range: float = cone_range_min
var cone_angle_degrees: float = cone_angle_min

@onready var visual_root: Node3D = $VisualRoot
@onready var muzzle: Marker3D = $VisualRoot/MuzzlePoint
@onready var burst: CPUParticles3D = $VisualRoot/Burst
@onready var flash: ColorRect = $UILayer/Flash
@onready var feedback_label: Label = $UILayer/FeedbackLabel
@onready var reticle_dot: Label = $UILayer/ReticleDot
@onready var charge_label: Label = $UILayer/ChargeLabel
@onready var influence_cone: MeshInstance3D = $InfluenceCone

var _rest_position: Vector3
var _rest_rotation: Vector3
var _anim_tween: Tween
var _label_tween: Tween
var _flash_tween: Tween

var _recruiting_held: bool = false
var _recruit_burst_timer: float = 0.0
const RECRUIT_BURST_INTERVAL := 0.5

## -- Aim tracking (reticle/outline) --
## Whatever the camera is currently looking at, re-resolved every frame so
## the reticle always reflects what a Send Mob release would target right
## now -- see agents/mob-selector-notes.md. Non-null only when the hit
## object is in the "destructible" group; everything else (ground, walls,
## empty air, non-interactable props) falls back to null, shown as the
## yellow-ball reticle.
var _aim_target: Node3D = null

## -- Send Mob hold-to-charge --
var _send_held: bool = false
var _send_press_time_msec: int = 0


func _ready() -> void:
	_rest_position = visual_root.position
	_rest_rotation = visual_root.rotation
	flash.color = Color(1, 1, 1, 0)
	feedback_label.text = ""
	feedback_label.modulate.a = 0.0
	charge_label.text = ""
	influence_cone.visible = false
	GameState.grabuge_changed.connect(_on_grabuge_changed)
	_on_grabuge_changed(GameState.grabuge)


## Pulses the recruit particle burst at the horn's mouth every
## RECRUIT_BURST_INTERVAL seconds while the cone is active -- subtle
## "sound-wave" feedback per vision.md's megaphone description, using the
## existing one-shot burst rather than a new effect. Also re-resolves the aim
## reticle every frame and, while Send Mob is held, updates the live charge
## percentage readout.
func _process(delta: float) -> void:
	_update_aim_target()

	if _send_held:
		var held_msec: int = Time.get_ticks_msec() - _send_press_time_msec
		var percentage: float = _current_send_percentage(held_msec)
		charge_label.text = "%d%%" % roundi(percentage * 100.0)

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
	elif event.is_action_pressed(&"send_mob"):
		_send_held = true
		_send_press_time_msec = Time.get_ticks_msec()
	elif event.is_action_released(&"send_mob"):
		var held_msec: int = Time.get_ticks_msec() - _send_press_time_msec
		_send_held = false
		charge_label.text = ""
		_do_send_mob(_current_send_percentage(held_msec), _aim_target)


## True while the player is holding the recruit input and the influence cone
## is showing. CrowdController polls this each physics frame.
func is_recruiting_held() -> bool:
	return _recruiting_held


## Maps a hold duration to a commit percentage (0-1): linear ramp from
## `send_tap_floor_percentage` up to 1.0 over `send_ramp_duration_msec`, per
## agents/mob-selector-notes.md ("start linear ... tune by feel").
func _current_send_percentage(held_msec: int) -> float:
	var ramp_t: float = clamp(float(held_msec) / float(send_ramp_duration_msec), 0.0, 1.0)
	return lerp(send_tap_floor_percentage, 1.0, ramp_t)


## Re-raycasts along the camera's look direction every frame and updates
## `_aim_target` + the reticle visuals. Clears the outline on whatever was
## previously targeted before (possibly) placing it on something new, since
## only one object should ever be outlined at a time.
func _update_aim_target() -> void:
	var hit_target: Node3D = _raycast_destructible()

	if hit_target == _aim_target:
		return

	if _aim_target != null and is_instance_valid(_aim_target) and _aim_target.has_method("set_targeted"):
		_aim_target.set_targeted(false)

	_aim_target = hit_target

	if _aim_target != null and _aim_target.has_method("set_targeted"):
		_aim_target.set_targeted(true)

	reticle_dot.visible = _aim_target == null


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


## Fires the one unified Send Mob command. `target` non-null means the
## reticle was outlining an interactable at release time (À L'ATTAQUE! on
## that object); null means the yellow-ball fallback (Regroup to player) --
## per agents/mob-selector-notes.md, both are "send this % of the mob to a
## position," so this is the single place that decides the cosmetic
## feedback, not two separate code paths.
func _do_send_mob(percentage: float, target: Node3D) -> void:
	_play_raise_shake()
	var percent_text: String = "%d%%" % roundi(percentage * 100.0)
	if target != null:
		_flash_screen()
		_spawn_attack_marker(target.global_position)
		_show_feedback("A L'ATTAQUE ! (%s)" % percent_text, Color(0.95, 0.2, 0.2))
	else:
		_show_feedback("REGROUPEZ-VOUS ! (%s)" % percent_text, Color(0.3, 0.6, 0.95))
	send_mob_triggered.emit(percentage, target)


## Recomputes cone_range/cone_angle_degrees from the current Grabuge value
## (0-100%, linearly interpolated from *_min to *_max) and rebuilds the mesh.
func _on_grabuge_changed(value: float) -> void:
	var t: float = clamp(value, 0.0, 100.0) / 100.0
	cone_range = lerp(cone_range_min, cone_range_max, t)
	cone_angle_degrees = lerp(cone_angle_min, cone_angle_max, t)
	_update_cone_shape()


## Builds the cone mesh from the current `cone_range`/`cone_angle_degrees`.
func _update_cone_shape() -> void:
	var mesh: CylinderMesh = influence_cone.mesh as CylinderMesh
	if mesh == null:
		return
	var half_angle_rad: float = deg_to_rad(cone_angle_degrees * 0.5)
	mesh.height = cone_range
	mesh.top_radius = cone_range * tan(half_angle_rad)
	mesh.bottom_radius = 0.0
	# Cylinder is centered on its own origin; rotation_degrees=(-90,0,0) on
	# the node (set in Megaphone.tscn) maps its -Y (bottom, now the apex
	# since bottom_radius=0) to local -Z (forward). Shifting the node
	# forward by half the height puts the apex at the camera (z=0) and the
	# wide top out at cone_range.
	influence_cone.position = Vector3(0, 0, -cone_range * 0.5)


## Raycasts from the active camera along its look direction, returning the
## hit collider itself (not just a point) when it's a "destructible"-group
## interactable, or null otherwise -- the reticle only ever outlines
## something interactable, never bare geometry.
func _raycast_destructible() -> Node3D:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null

	var origin: Vector3 = cam.global_transform.origin
	var direction: Vector3 = -cam.global_transform.basis.z

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			origin, origin + direction * ray_range, ray_collision_mask)
	var result := space_state.intersect_ray(query)
	if not result:
		return null

	var collider: Object = result.collider
	if collider is Node3D and collider.is_in_group(&"destructible"):
		return collider
	return null


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
