extends CharacterBody3D

## Civilian / crowd NPC.
##
## Unrecruited civilians WANDER/IDLE around their spawn point (unchanged from
## before). Once CrowdController recruits one (see scripts/crowd_controller.gd),
## it switches to FOLLOW and from then on takes its marching orders (FOLLOW /
## CHARGE) from the controller instead of deciding anything itself -- per
## vision.md's crowd design, individual NPCs only do local steering, never
## strategy. See agents/crowd-swarm-notes.md for the full design.

enum State { IDLE, WANDER, FOLLOW, CHARGE }

@export var wander_radius: float = 6.0
@export var move_speed: float = 4.0
@export var idle_time_min: float = 2.0
@export var idle_time_max: float = 5.0
@export var turn_speed: float = 6.0
@export var arrival_distance: float = 0.3

## -- Crowd steering tuning --
@export var charge_arrival_distance: float = 1.0
@export var separation_radius: float = 1.2
@export var separation_weight: float = 1.8

## -- Police combat (only active once recruited, see agents/police-notes.md) --
## How close a cop needs to be before this protester starts hitting it. This
## is the "damage area" referenced by collider_to_damage_ratio below.
@export var attack_range: float = 1.5
@export var damage_per_second: float = 5.0
## Damage is applied in discrete chunks on this interval rather than every
## frame, per the spec's "damage is applied at controlled intervals."
@export var attack_interval: float = 0.5

## -- Physical collider vs. damage area (see agents/crowd-swarm-notes.md) --
## The CollisionShape3D capsule (used for physical separation in
## move_and_slide, not combat) is sized as this fraction of attack_range
## rather than given its own fixed radius. Keeping it well below 1.0 lets
## recruited protesters pack tightly for a dense mob visual without
## shrinking or growing attack_range, which stays the actual gameplay-
## relevant "can I hit/be hit" distance.
@export var collider_to_damage_ratio: float = 0.15

var state: State = State.IDLE
var home_position: Vector3
var target_position: Vector3
var state_timer: float = 0.0

## Set by enter_charge_at_target() when this charge is chasing a moving
## object (e.g. a cop) rather than a fixed point -- null for a plain
## move-to-point Send Mob command. When set, _process_charge() re-reads
## `target_position` from this target's live position every frame instead
## of the one-shot snapshot taken at command time, per direct feedback: a
## cop that moves after being targeted was otherwise never caught because
## protesters charged toward where it *used* to be.
var _charge_target: Node3D = null
var _charge_offset: Vector3 = Vector3.ZERO

## Set once by CrowdController.recruit(). Null while this NPC is still an
## unrecruited wandering civilian.
var crowd_controller: Node = null

## Per-instance speed variance so a recruited crowd doesn't move in lockstep.
## Rolled once at recruit time -- see agents/crowd-swarm-notes.md.
var _speed_variance: float = 1.0

## Pool of Quaternius "Individual Characters" glTF variants a protester can
## randomly wear -- each is a self-contained rig + the same 24 shared
## animations, see agents/prop-character-assets-research.md. Picked once per
## NPC in _ready() so a crowd reads as a mix of civilians rather than clones.
const CHARACTER_VARIANTS: Array[String] = [
	"res://assets/quaternius_men/Punk.gltf",
	"res://assets/quaternius_men/Farmer.gltf",
	"res://assets/quaternius_men/Worker.gltf",
	"res://assets/quaternius_men/Casual_Hoodie.gltf",
	"res://assets/quaternius_men/Casual_2.gltf",
	"res://assets/quaternius_men/Beach.gltf",
]

@onready var mesh_root: Node3D = $MeshRoot
@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
@onready var health: HealthComponent = $HealthComponent
@onready var _health_bar: ProgressBar3D = $HealthBar
var _anim: AnimationPlayer

var _attack_timer: float = 0.0

## The cop currently in melee range, if any -- recomputed every physics
## frame (not just on the attack-interval tick) purely so _update_visuals()
## knows whether to play a punch animation. Null whenever this protester
## isn't actively fighting a cop this frame.
var _melee_target: Node3D = null

## Alternates Punch_Left/Punch_Right each time a hit actually lands, so
## repeated melee doesn't look like the same single-arm swing on a loop.
var _punch_alternate: bool = false


func _ready() -> void:
	home_position = global_position
	_spawn_random_character()
	_apply_collider_ratio()
	_enter_idle()

	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_health_bar.max_value = health.max_health
	_health_bar.value = health.current_health
	_health_bar.visible = false


## Shrinks the physical collision capsule to collider_to_damage_ratio *
## attack_range, decoupling "how tightly bodies can pack" from "how close
## you need to be to deal/take damage" -- see the export var comment above.
## Duplicates the shape first: a CollisionShape3D's sub-resource shape is
## shared by reference across every instance of this scene (confirmed via a
## headless debug check), so mutating it in place would clobber every other
## spawned NPC's collider the moment attack_range/collider_to_damage_ratio
## ever varies per-instance.
func _apply_collider_ratio() -> void:
	var collision_shape: CollisionShape3D = $CollisionShape3D
	var capsule: CapsuleShape3D = collision_shape.shape.duplicate()
	capsule.radius = attack_range * collider_to_damage_ratio
	collision_shape.shape = capsule


func _spawn_random_character() -> void:
	var variant_path: String = CHARACTER_VARIANTS[randi() % CHARACTER_VARIANTS.size()]
	var character: Node3D = (load(variant_path) as PackedScene).instantiate()
	mesh_root.add_child(character)
	_anim = character.get_node("AnimationPlayer")


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

	move_and_slide()
	_update_visuals(delta)

	# Recruited protesters only fight cops once the player has actively sent
	# them somewhere (CHARGE) -- a FOLLOW-state crowd just standing near the
	# player doesn't engage, so cops beeline for the player instead of
	# getting dragged into combat by proximity alone. See vision.md.
	_melee_target = null
	if crowd_controller != null and state == State.CHARGE:
		_process_police_combat(delta)


## Deals damage to the nearest cop in melee range, on a fixed tick rather
## than every frame -- see agents/police-notes.md for why "controlled
## intervals" is implemented as a per-attacker cooldown instead of a
## continuous rate.
func _process_police_combat(delta: float) -> void:
	_melee_target = _find_nearest_cop()

	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	if _melee_target == null:
		return

	_attack_timer = attack_interval
	_punch_alternate = not _punch_alternate
	var cop_health: HealthComponent = _melee_target.get_node_or_null("HealthComponent")
	if cop_health != null:
		cop_health.take_damage(damage_per_second * attack_interval)


func _find_nearest_cop() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = attack_range
	for cop in get_tree().get_nodes_in_group(&"police"):
		if not is_instance_valid(cop):
			continue
		if not can_engage(cop):
			continue
		var dist: float = global_position.distance_to(cop.global_position)
		if dist <= nearest_dist:
			nearest = cop
			nearest_dist = dist
	return nearest


func _on_health_changed(current: float, max_value: float) -> void:
	_health_bar.visible = true
	_health_bar.value = current


## Removes this protester from the crowd it was part of and frees it. Cops
## damaging each other isn't a thing, so this only ever fires from police
## damage per agents/police-notes.md.
func _on_died() -> void:
	if crowd_controller != null:
		crowd_controller.remove_recruit(self)
	queue_free()


func _process_wander(delta: float) -> void:
	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()

	if distance <= arrival_distance:
		_enter_idle()
		return

	var direction: Vector3 = to_target.normalized()
	_move_toward(direction, delta)


## Recruited NPCs no longer actively chase the player while idle -- they
## just hold their ground (with separation only, so a cluster of them
## doesn't stack on top of each other) until a Send Mob command moves them
## via enter_charge(). Per direct feedback: the old seek-toward-leader pull
## read as the mob "swarming" the player any time they stopped to aim.
func _process_follow(delta: float) -> void:
	var direction: Vector3 = _combine_with_separation(Vector3.ZERO)
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

	if _charge_target != null:
		if is_instance_valid(_charge_target):
			target_position = _charge_target.global_position + _charge_offset
		else:
			_charge_target = null

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
## further state changes come from enter_charge() below.
func recruit(controller: Node) -> void:
	crowd_controller = controller
	_speed_variance = randf_range(0.85, 1.15)
	state = State.FOLLOW
	# Only recruited protesters are valid cop-interception targets -- an
	# unrecruited wandering civilian never joins the fight, per the spec's
	# "Existing recruited protesters should automatically damage nearby cops."
	add_to_group(&"protester")


## True only while this protester may fight `cop` specifically. Two cases
## count as "the player directed this NPC at a fight":
## - A plain move-to-point charge (`_charge_target == null`, e.g. the player
##   sent the mob near a cop without targeting it directly) -- any cop can
##   be engaged, per the original distance-based interception design.
## - A charge aimed at a specific destructible (`_charge_target != null`,
##   e.g. this cop was outlined and Send Mob-ed directly) -- only THAT cop
##   can be engaged, so other cops the charging protester happens to pass
##   near stay ignored. Per direct feedback: targeting one cop was pulling
##   every other nearby cop into fighting the crowd too, even ones the
##   player never selected.
## Either way, a FOLLOW/WANDER/IDLE protester (not charging at all) never
## engages -- see police.gd and the comment in _physics_process() above.
func can_engage(cop: Node3D) -> bool:
	if state != State.CHARGE:
		return false
	return _charge_target == null or _charge_target == cop


## Called by CrowdController to send this NPC charging toward a destination
## (one of several scattered points around the commanded target -- the
## scatter itself is the controller's job, not this NPC's). Used both for
## attacking a destructible target and for a plain move-to-point Send Mob
## command (CrowdController doesn't distinguish the two at this level).
func enter_charge(destination: Vector3, reaction_delay: float) -> void:
	state = State.CHARGE
	_charge_target = null
	target_position = destination
	state_timer = reaction_delay


## Same as enter_charge(), but `target`'s live position (see
## _process_charge()) drives the destination every frame instead of a
## one-shot snapshot -- used for Send Mob commands aimed at a moving
## "destructible" (currently only police). `offset` is the scattered
## position relative to the target, per CrowdController's charge_spread_radius.
func enter_charge_at_target(target: Node3D, offset: Vector3, reaction_delay: float) -> void:
	state = State.CHARGE
	_charge_target = target
	_charge_offset = offset
	target_position = target.global_position + offset
	state_timer = reaction_delay


func _update_visuals(_delta: float) -> void:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var target_anim: StringName
	if _melee_target != null:
		target_anim = &"Punch_Right" if _punch_alternate else &"Punch_Left"
	elif horizontal_speed <= 0.05:
		target_anim = &"Idle"
	elif state == State.CHARGE:
		target_anim = &"Run"
	else:
		target_anim = &"Walk"

	if _anim.current_animation != target_anim:
		_anim.play(target_anim)
