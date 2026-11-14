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
##
## ## Multiplayer
##
## Civilian spawning and despawning are **server-authoritative**: only the
## listen server instantiates and frees NPCs, and the MultiplayerSpawner that
## wraps this node (scenes/test_map.tscn's NPCReplicator, whose spawn_path
## points here) mirrors both events to every client. Clients therefore run
## none of the code below -- `_process` returns immediately.
##
## Spawning does not start until the match scene signals
## `begin_spawning()`, which happens only after every peer has finished
## loading the map (spec 3). Spawning during `_ready()` would push spawn
## packets at peers whose MultiplayerSpawner node does not exist yet.
##
## Both the initial batch and the trickle anchor on *a* player rather than
## "the" player, since there can be up to four (see scripts/player_registry.gd).

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
## system does with them afterward. Server-side only.
var spawned_npcs: Array[Node3D] = []

var _spawn_timer: float = 0.0
## Monotonic counter feeding deterministic node names ("Civilian3"). The
## MultiplayerSpawner replicates the name, so it only has to be unique --
## but a stable naming scheme makes replicated NPCs addressable by path
## (which is how client melee hits identify their targets).
var _next_npc_id: int = 0
var _spawning_enabled: bool = false


func _ready() -> void:
	set_process(false)
	if npc_scene == null:
		push_warning("NPCSpawner: no npc_scene assigned, nothing to spawn.")


## Called by the match scene once every peer has loaded and players exist.
## Server-only; on a client this never runs, so no civilian is ever spawned
## locally.
func begin_spawning() -> void:
	if not NetworkManager.is_authoritative():
		return
	if npc_scene == null:
		return
	_spawning_enabled = true
	set_process(true)

	var placed_points: Array[Vector3] = []
	for i in range(npc_count):
		var spawn_point: Vector3 = _find_spawn_point(global_position, placed_points)
		placed_points.append(spawn_point)
		_spawn_npc_at(spawn_point)


func _process(delta: float) -> void:
	if not _spawning_enabled or not NetworkManager.is_authoritative():
		return
	if npc_scene == null:
		return
	_despawn_far_npcs()
	_update_trickle_spawn(delta)


## Frees unrecruited civilians that have wandered (or been left behind by
## the player moving on) past despawn_distance. Recruited NPCs are part of
## the crowd and are never despawned this way.
## Despawn distance is measured against the *nearest* player, so a civilian
## standing next to any one of the four players is kept alive.
func _despawn_far_npcs() -> void:
	for i in range(spawned_npcs.size() - 1, -1, -1):
		var npc: Node3D = spawned_npcs[i]
		if not is_instance_valid(npc):
			spawned_npcs.remove_at(i)
			continue
		if npc.crowd_controller != null:
			continue
		var nearest: Node3D = PlayerRegistry.nearest(self, npc.global_position)
		if nearest == null:
			continue
		if npc.global_position.distance_to(nearest.global_position) > despawn_distance:
			spawned_npcs.remove_at(i)
			# Plain queue_free(): the MultiplayerSpawner turns this into a
			# despawn packet on every client.
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

	# Anchor on a random living player so civilians trickle in around the
	# whole protest rather than always around the host.
	var anchor: Node3D = PlayerRegistry.random_alive(self)
	if anchor == null:
		return
	var spawn_point: Vector3 = _find_spawn_point(anchor.global_position, [])
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


## Server-side spawn. Name, position and outfit are all set *before*
## add_child(), because that is when the MultiplayerSpawner serializes the
## spawn state (the synchronizer's `spawn = true` properties) for clients --
## setting them afterwards would leave every replicated civilian at the
## origin wearing outfit 0.
func _spawn_npc_at(spawn_point: Vector3) -> void:
	var npc: Node3D = npc_scene.instantiate()
	npc.name = "Civilian%d" % _next_npc_id
	_next_npc_id += 1
	npc.position = spawn_point
	npc.net_position = spawn_point
	npc.variant_index = npc.random_variant_index()
	add_child(npc)
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
