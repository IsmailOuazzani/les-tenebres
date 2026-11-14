extends Node3D
class_name NPCSpawner

## Spawns a handful of wandering civilian NPCs around this node's position at
## scene start, then keeps trickling in fresh unrecruited civilians near the
## player over time so recruiting doesn't dry up once the initial batch is
## gone -- per agents/protester-spawning-notes.md. Deliberately
## map-layout-agnostic: the initial batch only needs a center point (this
## node's transform, usually placed near the player spawn) and a radius, so
## it keeps working if the grey-box geometry around it changes shape/size.
##
## See agents/npc-wander-notes.md for how this fits into the bigger picture
## (recruitment, crowd-following) that will build on top of these NPCs later.

@export var npc_scene: PackedScene
@export var npc_count: int = 6
@export var spawn_radius: float = 10.0
@export var min_spacing: float = 1.5

## -- Continuous trickle spawning (agents/protester-spawning-notes.md) --
## Spawn rate (civilians/sec) scales with Grabuge between these two bounds:
## rate(g) = spawn_rate_min + (spawn_rate_max - spawn_rate_min) * (g / 100)^spawn_rate_exponent
## An exponent > 1 keeps the rate low through early/mid Grabuge and only
## ramps up hard near max Grabuge -- a bigger, louder protest draws more
## bystanders out, but small protests don't get instantly flooded.
@export var player_path: NodePath
@export var spawn_rate_min: float = 0.1
@export var spawn_rate_max: float = 1.5
@export var spawn_rate_exponent: float = 1.8
## Hard ceiling on unrecruited civilians near the player at once -- trickle
## spawning pauses once this many are already out there, regardless of
## Grabuge, so the street never floods and perf stays bounded.
@export var unrecruited_cap: int = 100
## Unrecruited civilians this far from the player despawn -- keeps the pool
## near the player instead of accumulating forever across the map as the
## player (and the trickle spawn point, which follows them) moves on.
@export var despawn_distance: float = 50.0

## All spawned NPCs, recruited or not. CrowdController reads this to find
## recruitable civilians -- the spawner doesn't know or care what the crowd
## system does with them afterward.
var spawned_npcs: Array[Node3D] = []

var _player: Node3D
var _spawn_timer: float = 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path)
	if player_path != NodePath() and _player == null:
		push_warning("NPCSpawner: player_path did not resolve, trickle spawning/despawn will do nothing.")

	if npc_scene == null:
		push_warning("NPCSpawner: no npc_scene assigned, nothing to spawn.")
		return

	var placed_points: Array[Vector3] = []
	for i in range(npc_count):
		var spawn_point: Vector3 = _find_spawn_point(global_position, placed_points)
		placed_points.append(spawn_point)
		_spawn_npc_at(spawn_point)


func _process(delta: float) -> void:
	if _player == null or npc_scene == null:
		return
	_despawn_far_npcs()
	_update_trickle_spawn(delta)


## Frees unrecruited civilians that have wandered (or been left behind by
## the player moving on) past despawn_distance. Recruited NPCs are part of
## the crowd and are never despawned this way.
func _despawn_far_npcs() -> void:
	for i in range(spawned_npcs.size() - 1, -1, -1):
		var npc: Node3D = spawned_npcs[i]
		if not is_instance_valid(npc):
			spawned_npcs.remove_at(i)
			continue
		if npc.crowd_controller != null:
			continue
		if npc.global_position.distance_to(_player.global_position) > despawn_distance:
			spawned_npcs.remove_at(i)
			npc.queue_free()


## Ticks the trickle-spawn timer and spawns one civilian near the player
## once it elapses, provided unrecruited_cap hasn't been hit. Interval is
## re-rolled from the current Grabuge-driven rate after each spawn, so the
## cadence tracks Grabuge as it rises and falls over a run.
func _update_trickle_spawn(delta: float) -> void:
	if _count_unrecruited() >= unrecruited_cap:
		return

	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return

	var spawn_point: Vector3 = _find_spawn_point(_player.global_position, [])
	_spawn_npc_at(spawn_point)

	var rate: float = _spawn_rate(GameState.grabuge)
	_spawn_timer = 1.0 / max(rate, 0.001)


func _count_unrecruited() -> int:
	var count: int = 0
	for npc in spawned_npcs:
		if is_instance_valid(npc) and npc.crowd_controller == null:
			count += 1
	return count


func _spawn_rate(grabuge: float) -> float:
	var t: float = clamp(grabuge / GameState.GRABUGE_MAX, 0.0, 1.0)
	return spawn_rate_min + (spawn_rate_max - spawn_rate_min) * pow(t, spawn_rate_exponent)


func _spawn_npc_at(spawn_point: Vector3) -> void:
	var npc: Node3D = npc_scene.instantiate()
	add_child(npc)
	npc.global_position = spawn_point
	spawned_npcs.append(npc)


func _find_spawn_point(center: Vector3, placed_points: Array[Vector3]) -> Vector3:
	for attempt in range(20):
		var angle: float = randf() * TAU
		var dist: float = sqrt(randf()) * spawn_radius
		var candidate: Vector3 = center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var far_enough: bool = true
		for point in placed_points:
			if candidate.distance_to(point) < min_spacing:
				far_enough = false
				break

		if far_enough:
			return candidate

	# Fallback: couldn't find a spaced-out point after enough attempts
	# (e.g. radius too small for the count); just scatter randomly.
	return center + Vector3(
		randf_range(-spawn_radius, spawn_radius),
		0.0,
		randf_range(-spawn_radius, spawn_radius)
	)
