extends Node3D
class_name ClassAbilities

const REVEAL_DURATION_MSEC := 15000
const BOOST_DURATION_MSEC := 5000
const TEAM_ABILITY_COOLDOWN_MSEC := 45000
const HEAL_COOLDOWN_MSEC := 15000
const BARRIER_COOLDOWN_MSEC := 45000
const SHOT_COOLDOWN_MSEC := 1000

const HEAL_AMOUNT := 25.0
const HEAL_RADIUS := 6.0
const BARRIER_COUNT := 10
const BARRIER_RADIUS := 6.0
const BARRIER_DURATION := 8.0
const SHOT_DAMAGE := 15.0
const SHOT_SPEED := 36.0
const SHOT_RANGE := 35.0
const CROISSANT_MODEL := preload("res://assets/kenney_food_kit/croissant.glb")
const TEAM_COLOR := Color(0.08, 0.52, 1.0, 0.48)
const COP_COLOR := Color(1.0, 0.08, 0.12, 0.48)

@onready var _crowd: CrowdController = $"../CrowdController"
@onready var _npc_spawner: NPCSpawner = $"../NPCSpawner"

var _reveal_until_msec: int = 0
var _cop_halos: Dictionary[Police, MeshInstance3D] = {}
var _reveal_visible: bool = false
var _projectiles: Dictionary[int, CroissantProjectile] = {}
var _next_projectile_id: int = 0


func _ready() -> void:
	add_to_group(&"class_abilities")
	get_tree().node_added.connect(_on_actor_added)
	get_tree().node_removed.connect(_on_actor_removed)


func activate(caster: NetPlayer, ability: int, direction: Vector3) -> int:
	match ability:
		PlayerClass.Ability.REVEAL:
			_reveal_police.rpc(REVEAL_DURATION_MSEC)
			return TEAM_ABILITY_COOLDOWN_MSEC
		PlayerClass.Ability.SPEED_BOOST:
			_boost_crowd.rpc(BOOST_DURATION_MSEC)
			return TEAM_ABILITY_COOLDOWN_MSEC
		PlayerClass.Ability.HEAL:
			_heal_teammates(caster)
			return HEAL_COOLDOWN_MSEC
		PlayerClass.Ability.BARRIER:
			return BARRIER_COOLDOWN_MSEC if _spawn_barrier(caster.global_position) else 0
		PlayerClass.Ability.CROISSANT_SHOT:
			if not direction.is_finite() or not is_equal_approx(direction.length_squared(), 1.0):
				return 0
			var origin := caster.get_shot_origin()
			_next_projectile_id += 1
			_spawn_projectile.rpc(_next_projectile_id, origin, direction.normalized())
			return SHOT_COOLDOWN_MSEC
	return 0


func _heal_teammates(caster: NetPlayer) -> void:
	for node in PlayerRegistry.alive(self):
		var teammate := node as NetPlayer
		if teammate == null or teammate == caster:
			continue
		if caster.global_position.distance_squared_to(teammate.global_position) <= HEAL_RADIUS * HEAL_RADIUS:
			teammate.health.heal(HEAL_AMOUNT)


func _spawn_barrier(center: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.6
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape = shape
	clearance.collision_mask = 5
	var placed := false
	for i in BARRIER_COUNT:
		var angle := TAU * float(i) / BARRIER_COUNT
		var facing := Vector3(cos(angle), 0.0, sin(angle))
		var foot := center + facing * BARRIER_RADIUS
		var ray := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 0.75, foot - Vector3.UP * 4.0, 1)
		var ground := space.intersect_ray(ray)
		if ground.is_empty() or ground.normal.dot(Vector3.UP) < 0.7 or ground.collider is CharacterBody3D:
			continue
		var position_on_ground: Vector3 = ground.position + Vector3.UP * 0.05
		clearance.transform.origin = position_on_ground + Vector3.UP * 0.83
		if not space.intersect_shape(clearance, 1).is_empty():
			continue
		_npc_spawner.spawn_barrier_supporter(position_on_ground, facing, BARRIER_DURATION)
		placed = true
	return placed


@rpc("authority", "call_local", "reliable")
func _reveal_police(duration_msec: int) -> void:
	_reveal_until_msec = Time.get_ticks_msec() + duration_msec


@rpc("authority", "call_local", "reliable")
func _boost_crowd(duration_msec: int) -> void:
	_crowd.speed_boost_until_msec = Time.get_ticks_msec() + duration_msec


func _process(_delta: float) -> void:
	var revealing := Time.get_ticks_msec() < _reveal_until_msec
	if revealing != _reveal_visible:
		_reveal_visible = revealing
		for halo in _cop_halos.values():
			halo.visible = revealing


func _on_actor_added(node: Node) -> void:
	if node is NetPlayer or node is Police:
		_attach_halo.call_deferred(node)


func _attach_halo(actor: Node3D) -> void:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	if actor is Police:
		var outline := actor.get_node("Outline") as MeshInstance3D
		var capsule := outline.mesh as CapsuleMesh
		var size := Vector2(capsule.radius + 0.06, capsule.height + 0.14)
		var halo := ClassHalo.create(COP_COLOR, true, size)
		halo.position = outline.position
		actor.add_child(halo)
		halo.visible = _reveal_visible
		_cop_halos[actor as Police] = halo
	elif actor is NetPlayer and not actor.is_multiplayer_authority():
		var viewer_kit := NetworkManager.get_player_kit(NetworkManager.get_local_peer_id())
		var halo := ClassHalo.create(TEAM_COLOR, viewer_kit == PlayerClass.Kit.SCOUT)
		var body := actor.get_node("Body") as Node3D
		body.add_child(halo)
		halo.show()


func _on_actor_removed(node: Node) -> void:
	if node is Police:
		_cop_halos.erase(node)


@rpc("authority", "call_local", "reliable")
func _spawn_projectile(projectile_id: int, origin: Vector3, direction: Vector3) -> void:
	var projectile := CroissantProjectile.new()
	projectile.name = "CroissantShot%d" % projectile_id
	projectile.direction = direction
	projectile.speed = SHOT_SPEED
	projectile.range_left = SHOT_RANGE
	projectile.damage = SHOT_DAMAGE

	var model := CROISSANT_MODEL.instantiate() as Node3D
	model.scale = Vector3.ONE * 0.3
	projectile.add_child(model)
	add_child(projectile)
	projectile.global_position = origin
	var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	projectile.look_at(origin + direction, up)
	_projectiles[projectile_id] = projectile
	if NetworkManager.is_host():
		projectile.finished.connect(_finish_projectile.bind(projectile_id))


func _finish_projectile(point: Vector3, projectile_id: int) -> void:
	_remove_projectile.rpc(point, projectile_id)


@rpc("authority", "call_local", "reliable")
func _remove_projectile(point: Vector3, projectile_id: int) -> void:
	var projectile: CroissantProjectile = _projectiles.get(projectile_id)
	if is_instance_valid(projectile):
		projectile.global_position = point
		projectile.queue_free()
	_projectiles.erase(projectile_id)
