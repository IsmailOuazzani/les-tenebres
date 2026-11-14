extends Node3D
class_name Megaphone

## First-person megaphone viewmodel + click/hold-command hooks.
##
## This node is purely player-facing: it owns the held prop, the recruitment
## ground-circle indicator, the aim reticle/outline, raise/shake animation,
## and the signal below. It does NOT know about NPCs or the crowd --
## CrowdController (scripts/crowd_controller.gd) polls `is_recruiting_held()`
## / `is_point_within_recruit_range()` and listens for `send_mob_triggered`
## itself rather than this script reaching into NPCs. See `agents/megaphone-notes.md`
## and `agents/mob-selector-notes.md` for the full integration contract.
##
## Checking `is_in_group("destructible")` on the raycast hit below is the one
## exception to "doesn't know about NPCs/crowd" -- it's a visual-only check
## (which object gets the outline reticle), not crowd logic.

## Emitted when the player releases Send Mob (hold Left Click). `percentage`
## (0-1) is how much of the recruited mob to commit, per the hold-to-charge
## ramp. `target` is the destructible object the reticle was outlining at
## release time (attack it), or null if the reticle was showing the
## yellow-ball fallback -- in which case `point` (the aim raycast's hit
## point) is where to send the mob instead.
signal send_mob_triggered(percentage: float, target: Node3D, point: Vector3)

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

## -- Recruitment range --
## Fixed radius (meters) of the ground circle showing the player's area of
## influence while recruiting. Not tied to GameState.grabuge for now.
@export var recruit_radius := 2.0

@onready var visual_root: Node3D = $VisualRoot
@onready var muzzle: Marker3D = $VisualRoot/MuzzlePoint
@onready var burst: CPUParticles3D = $VisualRoot/Burst
@onready var ui_layer: CanvasLayer = $UILayer
@onready var flash: ColorRect = $UILayer/Flash
@onready var feedback_label: Label = $UILayer/FeedbackLabel
@onready var reticle_dot: Label = $UILayer/ReticleDot
@onready var charge_label: Label = $UILayer/ChargeLabel
@onready var recruit_circle: MeshInstance3D = $RecruitCircle

## Whether this weapon is the one currently equipped. Owned by
## WeaponSwitcher.gd (see addons/fps_controller/WeaponSwitcher.gd) via
## activate()/deactivate() below -- Megaphone never decides this itself.
var _is_active: bool = true

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
## yellow-ball reticle -- `_aim_point` below is where the mob goes instead.
var _aim_target: Node3D = null
## The aim raycast's hit point (or a point `ray_range` out along the look
## direction if the ray hits nothing), re-resolved every frame alongside
## `_aim_target`. Used as the Send Mob destination whenever `_aim_target`
## is null -- i.e. aiming at ground/world geometry sends the mob there
## instead of back to the player.
var _aim_point: Vector3 = Vector3.ZERO

## -- Send Mob hold-to-charge --
var _send_held: bool = false
var _send_press_time_msec: int = 0
## Lazily resolved via the &"crowd_controller" group (see
## scripts/crowd_controller.gd's _ready()) rather than an exported NodePath,
## since Megaphone lives nested inside Player.tscn and can't reach a
## sibling-of-Player node through a cross-scene path override. Read only to
## show the live "how many NPCs would this commit" count on charge_label
## while Send Mob is held -- CrowdController itself decides the actual
## commit when send_mob_triggered fires.
var _crowd_controller: Node = null


func _ready() -> void:
	_rest_position = visual_root.position
	_rest_rotation = visual_root.rotation
	flash.color = Color(1, 1, 1, 0)
	feedback_label.text = ""
	feedback_label.modulate.a = 0.0
	charge_label.text = ""
	recruit_circle.visible = false
	_update_recruit_circle_shape()


## Pulses the recruit particle burst at the horn's mouth every
## RECRUIT_BURST_INTERVAL seconds while recruiting is active -- subtle
## "sound-wave" feedback per vision.md's megaphone description, using the
## existing one-shot burst rather than a new effect. Also re-resolves the aim
## reticle every frame and, while Send Mob is held, updates the live charge
## percentage readout.
func _process(delta: float) -> void:
	if not _is_active:
		return
	_update_aim_target()

	if _send_held:
		var held_msec: int = Time.get_ticks_msec() - _send_press_time_msec
		var percentage: float = _current_send_percentage(held_msec)
		charge_label.text = "%d%% (%d)" % [roundi(percentage * 100.0), _current_selected_count(percentage)]
		AudioManager.update_send_charge(percentage)

	if not _recruiting_held:
		return
	_update_recruit_circle_transform()
	_recruit_burst_timer -= delta
	if _recruit_burst_timer <= 0.0:
		_recruit_burst_timer = RECRUIT_BURST_INTERVAL
		_spawn_recruit_burst()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_active:
		return
	if event.is_action_pressed(&"recruit"):
		_start_recruit()
	elif event.is_action_released(&"recruit"):
		_stop_recruit()
	elif event.is_action_pressed(&"primary_action"):
		_send_held = true
		_send_press_time_msec = Time.get_ticks_msec()
		AudioManager.start_send_charge()
	elif event.is_action_released(&"primary_action"):
		var held_msec: int = Time.get_ticks_msec() - _send_press_time_msec
		_send_held = false
		charge_label.text = ""
		AudioManager.stop_send_charge()
		_do_send_mob(_current_send_percentage(held_msec), _aim_target, _aim_point)


## True while the player is holding the recruit input and the ground
## recruitment circle is showing. CrowdController polls this each physics frame.
func is_recruiting_held() -> bool:
	return _recruiting_held


## Called by WeaponSwitcher.gd when the player equips this weapon.
func activate() -> void:
	_is_active = true
	visual_root.visible = true
	ui_layer.visible = true


## Called by WeaponSwitcher.gd when the player switches away from this
## weapon. Drops recruiting and clears any outline so neither lingers on an
## object while the megaphone isn't even equipped.
func deactivate() -> void:
	_is_active = false
	_stop_recruit()
	_send_held = false
	charge_label.text = ""
	if _aim_target != null and is_instance_valid(_aim_target) and _aim_target.has_method("set_targeted"):
		_aim_target.set_targeted(false)
	_aim_target = null
	visual_root.visible = false
	ui_layer.visible = false


## Maps a hold duration to a commit percentage (0-1): linear ramp from
## `send_tap_floor_percentage` up to 1.0 over `send_ramp_duration_msec`, per
## agents/mob-selector-notes.md ("start linear ... tune by feel").
func _current_send_percentage(held_msec: int) -> float:
	var ramp_t: float = clamp(float(held_msec) / float(send_ramp_duration_msec), 0.0, 1.0)
	return lerp(send_tap_floor_percentage, 1.0, ramp_t)


## Mirrors CrowdController._on_send_mob()'s count math so the live readout
## while charging matches exactly what releasing Send Mob right now would
## commit.
func _current_selected_count(percentage: float) -> int:
	if _crowd_controller == null:
		_crowd_controller = get_tree().get_first_node_in_group(&"crowd_controller")
	if _crowd_controller == null:
		return 0
	var total: int = _crowd_controller.get_recruited_count()
	return clampi(roundi(percentage * total), 0, total)


## Re-raycasts along the camera's look direction every frame and updates
## `_aim_target`/`_aim_point` + the reticle visuals. Clears the outline on
## whatever was previously targeted before (possibly) placing it on
## something new, since only one object should ever be outlined at a time.
func _update_aim_target() -> void:
	var hit_target: Node3D = null
	var hit_point: Vector3 = global_position - global_transform.basis.z * ray_range

	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var origin: Vector3 = cam.global_transform.origin
		var direction: Vector3 = -cam.global_transform.basis.z
		var space_state := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
				origin, origin + direction * ray_range, ray_collision_mask)
		var result := space_state.intersect_ray(query)
		if result:
			hit_point = result.position
			var collider: Object = result.collider
			if collider is Node3D and collider.is_in_group(&"destructible"):
				hit_target = collider
		else:
			hit_point = origin + direction * ray_range

	_aim_point = hit_point

	if hit_target == _aim_target:
		return

	if _aim_target != null and is_instance_valid(_aim_target) and _aim_target.has_method("set_targeted"):
		_aim_target.set_targeted(false)

	_aim_target = hit_target

	if _aim_target != null and _aim_target.has_method("set_targeted"):
		_aim_target.set_targeted(true)

	reticle_dot.visible = _aim_target == null


## True if `point` (world space) falls inside the recruitment radius right
## now -- a flat, omnidirectional horizontal-distance check centered on the
## player (ignores height), decoupled from the ground-circle visual mesh so
## recruitment logic doesn't depend on the mesh being pixel-perfect.
func is_point_within_recruit_range(point: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false

	var origin: Vector3 = cam.global_transform.origin
	var horizontal_delta := Vector2(point.x - origin.x, point.z - origin.z)
	return horizontal_delta.length() <= recruit_radius


func _start_recruit() -> void:
	_recruiting_held = true
	recruit_circle.visible = true
	_update_recruit_circle_transform()
	_recruit_burst_timer = 0.0
	_show_feedback("RECRUITING...", Color(0.35, 0.9, 0.45))
	AudioManager.start_megaphone_recruit()


func _stop_recruit() -> void:
	_recruiting_held = false
	recruit_circle.visible = false
	AudioManager.stop_megaphone_recruit()


## Fires the one unified Send Mob command. `target` non-null means the
## reticle was outlining an interactable at release time (À L'ATTAQUE! on
## that object); null means the yellow-ball fallback, in which case `point`
## (ground/world geometry under the reticle) is where the mob marches to
## instead -- so this is the single place that decides the cosmetic
## feedback, not two separate code paths.
func _do_send_mob(percentage: float, target: Node3D, point: Vector3) -> void:
	_play_raise_shake()
	AudioManager.play_attack_command()
	var percent_text: String = "%d%%" % roundi(percentage * 100.0)
	if target != null:
		_flash_screen()
		_spawn_marker(target.global_position)
		_show_feedback("A L'ATTAQUE ! (%s)" % percent_text, Color(0.95, 0.2, 0.2))
	else:
		_spawn_marker(point)
		_show_feedback("ALLEZ-Y ! (%s)" % percent_text, Color(0.3, 0.6, 0.95))
	send_mob_triggered.emit(percentage, target, point)


## Resizes the ground-ring mesh to the current `recruit_radius`.
func _update_recruit_circle_shape() -> void:
	var mesh: TorusMesh = recruit_circle.mesh as TorusMesh
	if mesh == null:
		return
	const RING_THICKNESS := 0.3
	mesh.outer_radius = recruit_radius
	mesh.inner_radius = max(recruit_radius - RING_THICKNESS, 0.05)


## Keeps the ground ring centered under the player and flat on the floor,
## independent of camera pitch/roll (Megaphone lives under Head/Camera, so
## its own transform tilts with the player's look direction). Raycasts
## straight down from the camera to find the floor; falls back to the
## camera's own height if nothing is hit (e.g. mid-air).
func _update_recruit_circle_transform() -> void:
	var ground_point: Vector3 = global_position
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + Vector3.DOWN * 10.0, ray_collision_mask)
	var result := space_state.intersect_ray(query)
	if result:
		ground_point = result.position
	recruit_circle.global_position = ground_point + Vector3(0, 0.02, 0)
	recruit_circle.global_rotation = Vector3.ZERO


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


## Drops a small, self-removing marker mesh at the given point as a stand-in
## for a future decal/VFX, for both attack and move-to-point Send Mob
## commands. Purely cosmetic — no gameplay meaning.
func _spawn_marker(target_position: Vector3) -> void:
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
