extends Node3D
class_name PoliceSpawner

## Spawns scripts/police.gd enemies at randomized points around the player,
## per agents/police-notes.md. Spawning is now driven ENTIRELY by
## scripts/wave_manager.gd (see agents/wave-survival-notes.md) -- Grabuge no
## longer has anything to do with police presence, per vision.md's "Police
## spawning itself is driven entirely by the Wave System, not by Grabuge."
## WaveManager calls begin_wave()/stop_spawning()/clear_all_police() via a
## group lookup (`&"police_spawner"`), the same pattern CrowdController uses
## for itself (`&"crowd_controller"`, see scripts/audio_manager.gd).

@export var police_scene: PackedScene
@export var player_path: NodePath
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

var _player: Node3D

## -- Wave-driven spawn state (set by begin_wave(), consumed by _process())--
var _spawning: bool = false
var _police_remaining_to_spawn: int = 0
var _spawn_interval: float = 1.0
var _spawn_timer: float = 0.0


func _ready() -> void:
	add_to_group(&"police_spawner")
	_player = get_node_or_null(player_path)
	if _player == null:
		push_warning("PoliceSpawner: player_path did not resolve, nothing will spawn.")


func _process(delta: float) -> void:
	if not _spawning or _player == null or police_scene == null:
		return
	if _police_remaining_to_spawn <= 0:
		_spawning = false
		return

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_police()
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


func _spawn_police() -> void:
	var police: Node3D = police_scene.instantiate()
	add_child(police)
	police.global_position = _find_spawn_point()
	police.setup(_player)
	spawned_police.append(police)


## Picks a random point in the [spawn_radius_min, spawn_radius_max] ring
## around the player that's also at least min_player_distance away (in case
## spawn_radius_min is ever tuned below that floor), preferring one outside
## the active camera's forward view cone (per the spec's "preferably
## outside the camera view") -- falls back to just taking the last attempt
## if every try fails both checks.
func _find_spawn_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	var candidate: Vector3 = _player.global_position

	for attempt in range(20):
		candidate = _random_ring_point()
		if candidate.distance_to(_player.global_position) < min_player_distance:
			continue
		if cam == null or not _is_in_view(cam, candidate):
			return candidate

	return candidate


func _random_ring_point() -> Vector3:
	var angle: float = randf() * TAU
	var dist: float = randf_range(spawn_radius_min, spawn_radius_max)
	return _player.global_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _is_in_view(cam: Camera3D, point: Vector3) -> bool:
	var to_point: Vector3 = point - cam.global_transform.origin
	to_point.y = 0.0
	var forward: Vector3 = -cam.global_transform.basis.z
	forward.y = 0.0

	if to_point.length_squared() < 0.0001 or forward.length_squared() < 0.0001:
		return false

	return to_point.normalized().dot(forward.normalized()) > in_view_dot_threshold
