extends CharacterBody3D

## Civilian / crowd NPC.
##
## Unrecruited civilians WANDER/IDLE around their spawn point (unchanged from
## before). Once CrowdController recruits one (see scripts/crowd_controller.gd),
## it switches to FOLLOW and from then on takes its marching orders (FOLLOW /
## CHARGE / REGROUP) from the controller instead of deciding anything itself --
## per vision.md's crowd design, individual NPCs only do local steering, never
## strategy. See agents/crowd-swarm-notes.md for the full design.

enum State { IDLE, WANDER, FOLLOW, CHARGE, REGROUP }

@export var wander_radius: float = 6.0
@export var move_speed: float = 4.0
@export var idle_time_min: float = 2.0
@export var idle_time_max: float = 5.0
@export var turn_speed: float = 6.0
@export var arrival_distance: float = 0.3

## -- Crowd steering tuning --
@export var follow_stop_distance: float = 2.5
@export var charge_arrival_distance: float = 1.0
@export var separation_radius: float = 1.2
@export var separation_weight: float = 1.8

var state: State = State.IDLE
var home_position: Vector3
var target_position: Vector3
var state_timer: float = 0.0

## Set once by CrowdController.recruit(). Null while this NPC is still an
## unrecruited wandering civilian.
var crowd_controller: Node = null
## The node to FOLLOW / REGROUP toward (the player). Only meaningful once
## recruited.
var leader: Node3D = null

## Per-instance speed variance so a recruited crowd doesn't move in lockstep.
## Rolled once at recruit time -- see agents/crowd-swarm-notes.md.
var _speed_variance: float = 1.0

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
		State.FOLLOW:
			_process_follow(delta)
		State.CHARGE:
			_process_charge(delta)
		State.REGROUP:
			_process_regroup(delta)

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
	_move_toward(direction, delta)


## Loose crowd-follow: seek the leader (unless already close enough) plus
## separation from nearby crowd-mates so NPCs don't stack on top of each
## other or the player. Cohesion is intentionally skipped for this first
## pass -- separation + a shared seek target already keeps the crowd loosely
## grouped around the leader, see agents/crowd-swarm-notes.md.
func _process_follow(delta: float) -> void:
	if leader == null:
		return

	var to_leader: Vector3 = leader.global_position - global_position
	to_leader.y = 0.0
	var distance: float = to_leader.length()

	var seek: Vector3 = Vector3.ZERO
	if distance > follow_stop_distance:
		seek = to_leader.normalized()

	var direction: Vector3 = _combine_with_separation(seek)
	if direction.length_squared() < 0.0001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	_move_toward(direction, delta)


## Charge toward the assigned destination, after a short randomized reaction
## delay (so the mob doesn't move in perfect unison -- vision.md: "NPCs
## should respond with small randomized delays").
func _process_charge(delta: float) -> void:
	if state_timer > 0.0:
		state_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()

	if distance <= charge_arrival_distance:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var seek: Vector3 = to_target.normalized()
	var direction: Vector3 = _combine_with_separation(seek)
	_move_toward(direction, delta)


## Same steering as CHARGE but automatically rejoins FOLLOW on arrival, so
## the crowd "recovers naturally after becoming scattered" (vision.md).
func _process_regroup(delta: float) -> void:
	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()

	if distance <= charge_arrival_distance:
		state = State.FOLLOW
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var seek: Vector3 = to_target.normalized()
	var direction: Vector3 = _combine_with_separation(seek)
	_move_toward(direction, delta)


## Blends a seek direction with a separation force away from nearby
## crowd-mates (queried from CrowdController -- local neighbor search, not a
## full spatial grid, see agents/crowd-swarm-notes.md for why that's fine at
## this NPC count). Returns a normalized-ish direction, or ZERO if there's
## nothing to do.
func _combine_with_separation(seek: Vector3) -> Vector3:
	var separation: Vector3 = Vector3.ZERO
	if crowd_controller != null:
		for neighbor in crowd_controller.get_neighbors(self, separation_radius):
			var away: Vector3 = global_position - neighbor.global_position
			away.y = 0.0
			var dist: float = away.length()
			if dist > 0.001:
				separation += (away / dist) / dist

	var combined: Vector3 = seek + separation * separation_weight
	if combined.length_squared() < 0.0001:
		return Vector3.ZERO
	return combined.normalized()


func _move_toward(direction: Vector3, delta: float) -> void:
	velocity.x = direction.x * move_speed * _speed_variance
	velocity.z = direction.z * move_speed * _speed_variance

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


## Called once by CrowdController when this civilian gets recruited. From
## this point on the NPC never decides WHERE to go on its own again -- all
## further state changes come from enter_charge()/enter_regroup() below.
func recruit(leader_node: Node3D, controller: Node) -> void:
	leader = leader_node
	crowd_controller = controller
	_speed_variance = randf_range(0.85, 1.15)
	state = State.FOLLOW


## Called by CrowdController to send this NPC charging toward a destination
## (one of several scattered points around the commanded target -- the
## scatter itself is the controller's job, not this NPC's).
func enter_charge(destination: Vector3, reaction_delay: float) -> void:
	state = State.CHARGE
	target_position = destination
	state_timer = reaction_delay


## Called by CrowdController to pull this NPC back toward the leader.
func enter_regroup(destination: Vector3) -> void:
	state = State.REGROUP
	target_position = destination


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
