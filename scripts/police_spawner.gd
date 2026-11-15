extends Node3D
class_name PoliceSpawner

## Spawns scripts/police.gd enemies at randomized points around the players,
## per agents/police-notes.md. Spawning is now driven ENTIRELY by
## scripts/wave_manager.gd (see agents/wave-survival-notes.md) -- Grabuge no
## longer has anything to do with police presence, per vision.md's "Police
## spawning itself is driven entirely by the Wave System, not by Grabuge."
## WaveManager calls begin_wave()/stop_spawning()/clear_all_police() via a
## group lookup (`&"police_spawner"`), the same pattern CrowdController uses
## for itself (`&"crowd_controller"`, see scripts/audio_manager.gd).
##
## ## Multiplayer
##
## Police spawning is **server-authoritative** and replicated by the
## MultiplayerSpawner whose spawn_path points at this node (see
## scenes/test_map.tscn's PoliceReplicator). Clients run none of this, and
## only the server's WaveManager issues spawn orders (see
## scripts/wave_manager.gd).
##
## Each cop is spawned around a randomly chosen living player rather than
## "the" player, so the police response is spread across the whole protest.

@export var police_scene: PackedScene
@export var spawn_radius_min: float = 12.0
@export var spawn_radius_max: float = 18.0

## Hard floor on spawn distance from the player -- a candidate point this
## close gets rejected and re-rolled, regardless of spawn_radius_min, so
## cops never pop in on top of the player even if the ring radii are later
## tuned small (vision.md: "enemies should never unfairly appear directly
## on top of the player").
@export var min_player_distance: float = 10.0

## How far into the camera's forward cone (dot product of normalized
## horizontal vectors, -1..1) a candidate point counts as "in view" and
## gets rejected in favor of another attempt -- see _is_in_view().
@export var in_view_dot_threshold: float = 0.3

var spawned_police: Array[Node3D] = []

## -- Wave-driven spawn state (set by begin_wave(), consumed by _process())--
var _spawning: bool = false
var _police_remaining_to_spawn: int = 0
var _spawn_interval: float = 1.0
var _spawn_timer: float = 0.0

## Monotonic counter feeding deterministic replicated node names.
var _next_police_id: int = 0


func _ready() -> void:
	add_to_group(&"police_spawner")
	if police_scene == null:
		push_warning("PoliceSpawner: no police_scene assigned, nothing will spawn.")


func _process(delta: float) -> void:
	if not _spawning or not NetworkManager.is_authoritative():
		return
	if police_scene == null:
		return
	if _police_remaining_to_spawn <= 0:
		_spawning = false
		return

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		# Only count the cop against the wave's quota if it actually spawned;
		# with every player down (multiplayer respawn window) there is no
		# anchor to spawn around, and burning the quota would quietly empty
		# the wave.
		if _spawn_police():
			_police_remaining_to_spawn -= 1
		_spawn_timer = _spawn_interval


## Called by WaveManager at the start of a wave: spawn `total_police` cops,
## spread evenly across `duration` seconds (so they trickle in across the
## whole wave rather than all landing at once).
func begin_wave(total_police: int, duration: float) -> void:
	_police_remaining_to_spawn = max(total_police, 0)
	_spawn_interval = duration / max(total_police, 1)
	_spawn_timer = 0.0
	_spawning = _police_remaining_to_spawn > 0


## Called by WaveManager when a wave ends (time-based completion, not
## kill-everything) -- stops handing out new spawns without touching
## already-live cops. See clear_all_police() for despawning those.
func stop_spawning() -> void:
	_spawning = false
	_police_remaining_to_spawn = 0


## Called by WaveManager on wave transitions to retreat/despawn leftover
## cops from the wave that just ended, per vision.md: "any remaining police
## can retreat or despawn during the transition."
func clear_all_police() -> void:
	for police in spawned_police:
		if is_instance_valid(police):
			police.queue_free()
	spawned_police.clear()


func _count_live_police() -> int:
	for i in range(spawned_police.size() - 1, -1, -1):
		if not is_instance_valid(spawned_police[i]):
			spawned_police.remove_at(i)
	return spawned_police.size()


## Server-side spawn. Name and position are set before add_child(), which is
## when the MultiplayerSpawner serializes spawn state for clients. Returns
## false if there was no living player to spawn around, so the caller can
## retry this cop later instead of silently burning it from the wave's quota.
func _spawn_police() -> bool:
	var anchor: Node3D = PlayerRegistry.random_alive(self)
	if anchor == null:
		return false

	var police: Node3D = police_scene.instantiate()
	police.name = "Cop%d" % _next_police_id
	_next_police_id += 1
	var spawn_point: Vector3 = _find_spawn_point(anchor)
	police.position = spawn_point
	police.net_position = spawn_point
	add_child(police)
	spawned_police.append(police)
	return true


## Picks a random point in the [spawn_radius_min, spawn_radius_max] ring
## around `anchor` that's also at least min_player_distance away (in case
## spawn_radius_min is ever tuned below that floor), preferring one outside
## the *local* camera's forward view cone (per the spec's "preferably
## outside the camera view") -- falls back to just taking the last attempt
## if every try fails both checks.
##
## Multiplayer caveat: the camera check can only ever use the listen server's
## own camera, since that is the only one this process has. A cop can
## therefore pop into a remote player's view. Accepted for now -- making it
## exact would mean replicating all four view frustums to the server purely to
## pick a spawn point. Noted in agents/multiplayer-notes.md.
func _find_spawn_point(anchor: Node3D) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	var candidate: Vector3 = anchor.global_position

	for attempt in range(20):
		candidate = _random_ring_point(anchor)
		if candidate.distance_to(anchor.global_position) < min_player_distance:
			continue
		if cam == null or not _is_in_view(cam, candidate):
			return candidate

	return candidate


func _random_ring_point(anchor: Node3D) -> Vector3:
	var angle: float = randf() * TAU
	var dist: float = randf_range(spawn_radius_min, spawn_radius_max)
	return anchor.global_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _is_in_view(cam: Camera3D, point: Vector3) -> bool:
	var to_point: Vector3 = point - cam.global_transform.origin
	to_point.y = 0.0
	var forward: Vector3 = -cam.global_transform.basis.z
	forward.y = 0.0

	if to_point.length_squared() < 0.0001 or forward.length_squared() < 0.0001:
		return false

	return to_point.normalized().dot(forward.normalized()) > in_view_dot_threshold
