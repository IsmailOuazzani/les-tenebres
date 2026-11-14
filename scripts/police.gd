extends CharacterBody3D
class_name Police

## Minimal police enemy, per agents/police-notes.md (the MVP spec this was
## built from). Three states, pure distance checks -- no behavior trees, no
## pathfinding. Spawned and handed the player reference by
## scripts/police_spawner.gd; everything else it needs (nearby protesters) it
## finds itself each frame via the "protester" group that scripts/npc.gd adds
## its NPCs to on recruit.

enum State { CHASE_PLAYER, FIGHT_PROTESTER, ATTACK_PLAYER }

@export var move_speed: float = 3.5
@export var turn_speed: float = 6.0

## -- Combat tuning --
@export var attack_range: float = 1.5
## How close a recruited protester needs to get before this cop breaks off
## chasing/attacking the player to fight it instead. Also doubles as the
## disengage range (no separate hysteresis value) -- simple distance checks
## only, per the spec.
@export var interception_radius: float = 2.5
@export var damage_per_second: float = 6.0
## Damage lands in discrete chunks on this cooldown rather than every frame
## -- see agents/police-notes.md.
@export var attack_interval: float = 0.5

var state: State = State.CHASE_PLAYER
var player: Node3D = null

var _fight_target: Node3D = null
var _attack_timer: float = 0.0

@onready var mesh_root: Node3D = $MeshRoot
@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
@onready var health: HealthComponent = $HealthComponent
@onready var _health_bar: ProgressBar3D = $HealthBar


func _ready() -> void:
	add_to_group(&"police")
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_health_bar.max_value = health.max_health
	_health_bar.value = health.current_health
	_health_bar.visible = false


## Called once by scripts/police_spawner.gd right after instantiating --
## cops are spawned dynamically so they can't get the player wired up via a
## NodePath set in the editor like CrowdController does.
func setup(player_node: Node3D) -> void:
	player = player_node


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	_update_state()

	match state:
		State.CHASE_PLAYER:
			_process_chase(delta)
		State.FIGHT_PROTESTER:
			_process_fight_protester(delta)
		State.ATTACK_PLAYER:
			_process_attack_player(delta)

	move_and_slide()
	_update_visuals(delta)


## Protester interception always takes priority over whatever else this cop
## was doing (chasing or already attacking the player), per the spec's
## ATTACK_PLAYER behavior: "Prioritize nearby protesters if they intercept."
func _update_state() -> void:
	var nearest_protester: Node3D = _find_nearest_protester()
	if nearest_protester != null:
		state = State.FIGHT_PROTESTER
		_fight_target = nearest_protester
		return

	_fight_target = null
	if player != null and is_instance_valid(player) \
			and global_position.distance_to(player.global_position) <= attack_range:
		state = State.ATTACK_PLAYER
	else:
		state = State.CHASE_PLAYER


func _process_chase(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	_move_toward(to_player.normalized(), delta)


func _process_fight_protester(delta: float) -> void:
	if _fight_target == null or not is_instance_valid(_fight_target):
		return

	var to_target: Vector3 = _fight_target.global_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()

	if distance > attack_range:
		_move_toward(to_target.normalized(), delta)
		return

	velocity.x = 0.0
	velocity.z = 0.0
	_tick_attack(delta, _fight_target)


func _process_attack_player(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_tick_attack(delta, player)


func _tick_attack(delta: float, target: Node3D) -> void:
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_interval

	var target_health: HealthComponent = target.get_node_or_null("HealthComponent")
	if target_health != null:
		target_health.take_damage(damage_per_second * attack_interval)


func _find_nearest_protester() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = interception_radius
	for protester in get_tree().get_nodes_in_group(&"protester"):
		if not is_instance_valid(protester):
			continue
		var dist: float = global_position.distance_to(protester.global_position)
		if dist <= nearest_dist:
			nearest = protester
			nearest_dist = dist
	return nearest


func _move_toward(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	var target_angle: float = atan2(direction.x, direction.z)
	mesh_root.rotation.y = lerp_angle(mesh_root.rotation.y, target_angle, turn_speed * delta)


func _update_visuals(delta: float) -> void:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.05:
		mesh_root.position.y = abs(sin(Time.get_ticks_msec() / 125.0)) * 0.05
	else:
		mesh_root.position.y = lerp(mesh_root.position.y, 0.0, delta * 8.0)


func _on_health_changed(current: float, max_value: float) -> void:
	_health_bar.visible = true
	_health_bar.value = current


func _on_died() -> void:
	queue_free()
