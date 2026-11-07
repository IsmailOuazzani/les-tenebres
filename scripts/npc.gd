extends CharacterBody3D

## Civilian NPC: wanders a small radius around its spawn point, pausing to idle
## between moves. This is the foundation for recruitment/crowd-follow systems
## that will be wired up later -- see agents/npc-wander-notes.md for the plan.
##
## State machine is deliberately small right now: only WANDER/IDLE are driven.
## RECRUITED and FOLLOWING exist as placeholders so the recruitment system can
## flip `state` without needing to touch this script's movement logic much.

enum State { IDLE, WANDER, RECRUITED, FOLLOWING }

@export var wander_radius: float = 6.0
@export var move_speed: float = 2.0
@export var idle_time_min: float = 2.0
@export var idle_time_max: float = 5.0
@export var turn_speed: float = 6.0
@export var arrival_distance: float = 0.3

var state: State = State.IDLE
var home_position: Vector3
var target_position: Vector3
var state_timer: float = 0.0

@onready var mesh_root: Node3D = $MeshRoot
@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

var _bob_time: float = 0.0


func _ready() -> void:
	home_position = global_position
	_tint_random()
	_enter_idle()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	match state:
		State.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			state_timer -= delta
			if state_timer <= 0.0:
				_enter_wander()
		State.WANDER:
			_process_wander(delta)
		State.RECRUITED, State.FOLLOWING:
			# Not implemented yet -- the recruit/crowd system will drive these.
			velocity.x = 0.0
			velocity.z = 0.0

	move_and_slide()
	_update_visuals(delta)


func _process_wander(delta: float) -> void:
	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()

	if distance <= arrival_distance:
		_enter_idle()
		return

	var direction: Vector3 = to_target.normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	var target_angle: float = atan2(direction.x, direction.z)
	mesh_root.rotation.y = lerp_angle(mesh_root.rotation.y, target_angle, turn_speed * delta)


func _enter_idle() -> void:
	state = State.IDLE
	state_timer = randf_range(idle_time_min, idle_time_max)


func _enter_wander() -> void:
	state = State.WANDER
	target_position = _pick_wander_point()


func _pick_wander_point() -> Vector3:
	var angle: float = randf() * TAU
	var dist: float = sqrt(randf()) * wander_radius
	var offset: Vector3 = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	return home_position + offset


func _update_visuals(delta: float) -> void:
	# Small bob while walking so the placeholder mesh doesn't look like it's
	# gliding. Purely cosmetic -- replace with real animation playback if/when
	# a rigged character asset is swapped in (see agents/npc-wander-notes.md).
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.05:
		_bob_time += delta * 8.0
		mesh_root.position.y = abs(sin(_bob_time)) * 0.05
	else:
		_bob_time = 0.0
		mesh_root.position.y = lerp(mesh_root.position.y, 0.0, delta * 8.0)


func _tint_random() -> void:
	var body_mesh: MeshInstance3D = get_node_or_null("MeshRoot/Body")
	if body_mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(randf(), 0.55, 0.85)
	body_mesh.material_override = material
