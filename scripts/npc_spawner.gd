extends Node3D
class_name NPCSpawner

## Spawns a handful of wandering civilian NPCs around this node's position at
## scene start. Deliberately map-layout-agnostic: it only needs a center point
## (this node's transform, usually placed near the player spawn) and a radius,
## so it keeps working if the grey-box geometry around it changes shape/size.
##
## See agents/npc-wander-notes.md for how this fits into the bigger picture
## (recruitment, crowd-following) that will build on top of these NPCs later.

@export var npc_scene: PackedScene
@export var npc_count: int = 6
@export var spawn_radius: float = 10.0
@export var min_spacing: float = 1.5

## All spawned NPCs, recruited or not. CrowdController reads this to find
## recruitable civilians -- the spawner doesn't know or care what the crowd
## system does with them afterward.
var spawned_npcs: Array[Node3D] = []


func _ready() -> void:
	if npc_scene == null:
		push_warning("NPCSpawner: no npc_scene assigned, nothing to spawn.")
		return

	var placed_points: Array[Vector3] = []
	for i in range(npc_count):
		var spawn_point: Vector3 = _find_spawn_point(placed_points)
		placed_points.append(spawn_point)

		var npc: Node3D = npc_scene.instantiate()
		add_child(npc)
		npc.global_position = spawn_point
		spawned_npcs.append(npc)


func _find_spawn_point(placed_points: Array[Vector3]) -> Vector3:
	var center: Vector3 = global_position
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
