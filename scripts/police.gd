extends CharacterBody3D
class_name Police

## Minimal police enemy, per agents/police-notes.md (the MVP spec this was
## built from). Three states, pure distance checks -- no behavior trees, no
## pathfinding. Spawned and handed the player reference by
## scripts/police_spawner.gd; everything else it needs (nearby protesters) it
## finds itself each frame via the "protester" group that scripts/npc.gd adds
## its NPCs to on recruit.

enum State { CHASE_PLAYER, FIGHT_PROTESTER, ATTACK_PLAYER }

## Emitted on death, mirroring scripts/destructible_prop.gd's contract --
## lets CrowdController clear `_attack_target` (CONNECT_ONE_SHOT) when a
## directly-targeted cop goes down, same as a destroyed prop.
signal destroyed

@export var move_speed: float = 3.5
@export var turn_speed: float = 6.0

## -- Combat tuning --
## How close something needs to be before this cop deals damage to it. This
## is the "damage area" referenced by collider_to_damage_ratio below.
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

## -- Physical collider vs. damage area (see agents/crowd-swarm-notes.md) --
## Same idea as NPC.collider_to_damage_ratio: the CollisionShape3D capsule
## (physical separation only) is sized as this fraction of attack_range so a
## cop can be packed into/surrounded by a dense mob without that mob's
## actual engagement range changing.
@export var collider_to_damage_ratio: float = 0.3

var state: State = State.CHASE_PLAYER
var player: Node3D = null

var _fight_target: Node3D = null
var _attack_timer: float = 0.0

@onready var mesh_root: Node3D = $MeshRoot
@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
@onready var health: HealthComponent = $HealthComponent
@onready var _health_bar: ProgressBar3D = $HealthBar
@onready var _outline: MeshInstance3D = $Outline
@onready var _anim: AnimationPlayer = $MeshRoot/Character/AnimationPlayer


func _ready() -> void:
	add_to_group(&"police")
	# Also a "destructible" -- per vision.md's "Police are a Send Mob target
	# like any destructible object," the aim reticle/outline and Send Mob's
	# direct-attack path (see Megaphone.gd / CrowdController._on_send_mob)
	# both key off this group, same as scripts/destructible_prop.gd.
	add_to_group(&"destructible")
	_apply_collider_ratio()
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_health_bar.max_value = health.max_health
	_health_bar.value = health.current_health
	_health_bar.visible = false
	_outline.visible = false


## Shrinks the physical collision capsule to collider_to_damage_ratio *
## attack_range -- see the export var comment above.
func _apply_collider_ratio() -> void:
	var collision_shape: CollisionShape3D = $CollisionShape3D
	var capsule: CapsuleShape3D = collision_shape.shape
	capsule.radius = attack_range * collider_to_damage_ratio


## Called once by scripts/police_spawner.gd right after instantiating --
## cops are spawned dynamically so they can't get the player wired up via a
## NodePath set in the editor like CrowdController does.
func setup(player_node: Node3D) -> void:
	player = player_node


## Called by Megaphone every frame the player's aim raycast is/isn't hitting
## this cop -- same contract as scripts/destructible_prop.gd's set_targeted().
func set_targeted(active: bool) -> void:
	_outline.visible = active


## Called directly by CrowdController (as the active `_attack_target`) for
## every recruited NPC within its attack_range -- same contract as
## scripts/destructible_prop.gd's take_damage(). Delegates to the same
## HealthComponent a cop's melee damage already goes through, so direct
## Send Mob damage and protester melee share one health pool.
func take_damage(amount: float) -> void:
	health.take_damage(amount)


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


## Interception by a *charging* protester always takes priority over
## whatever else this cop was doing (chasing or already attacking the
## player). Protesters just standing/following near the player don't count
## -- see _find_nearest_protester() -- so cops beeline for the player until
## the player actively sends part of the crowd at them.
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


## Only considers protesters that may engage THIS cop specifically -- see
## NPC.can_engage(). A FOLLOW-state crowd just standing/holding ground near
## the player never counts, so this cop keeps beelining for the player
## instead of engaging by proximity alone; and a protester charging
## straight at a *different* targeted cop doesn't get dragged into fighting
## this one just by passing close, so only the actually-selected cop(s)
## engage. See vision.md.
func _find_nearest_protester() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = interception_radius
	for protester in get_tree().get_nodes_in_group(&"protester"):
		if not is_instance_valid(protester):
			continue
		if not protester.can_engage(self):
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


func _update_visuals(_delta: float) -> void:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var target_anim: StringName
	if state == State.ATTACK_PLAYER or state == State.FIGHT_PROTESTER:
		target_anim = &"Gun_Shoot"
	elif horizontal_speed <= 0.05:
		target_anim = &"Idle"
	else:
		target_anim = &"Run"

	if _anim.current_animation != target_anim:
		_anim.play(target_anim)


func _on_health_changed(current: float, max_value: float) -> void:
	_health_bar.visible = true
	_health_bar.value = current


func _on_died() -> void:
	destroyed.emit()
	GameState.record_police_defeat()
	queue_free()
