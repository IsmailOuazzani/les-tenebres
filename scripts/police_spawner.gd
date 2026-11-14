extends Node3D
class_name PoliceSpawner

## Spawns one scripts/police.gd enemy every `spawn_interval` seconds at a
## random point around the player, per agents/police-notes.md. Deliberately
## simple, mirroring scripts/npc_spawner.gd's one-shot scatter but on a
## repeating timer and centered on the (moving) player instead of a fixed
## point.

@export var police_scene: PackedScene
@export var player_path: NodePath
@export var spawn_interval: float = 10.0
@export var spawn_radius_min: float = 12.0
@export var spawn_radius_max: float = 18.0

## How far into the camera's forward cone (dot product of normalized
## horizontal vectors, -1..1) a candidate point counts as "in view" and
## gets rejected in favor of another attempt -- see _is_in_view().
@export var in_view_dot_threshold: float = 0.3

var spawned_police: Array[Node3D] = []

var _player: Node3D
var _timer: float = 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path)
	if _player == null:
		push_warning("PoliceSpawner: player_path did not resolve, nothing will spawn.")
	_timer = spawn_interval


func _process(delta: float) -> void:
	if _player == null or police_scene == null:
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_police()


func _spawn_police() -> void:
	var police: Node3D = police_scene.instantiate()
	add_child(police)
	police.global_position = _find_spawn_point()
	police.setup(_player)
	spawned_police.append(police)


## Picks a random point in the [spawn_radius_min, spawn_radius_max] ring
## around the player, preferring one outside the active camera's forward
## view cone (per the spec's "preferably outside the camera view") -- falls
## back to just taking the last attempt if every try lands in view.
func _find_spawn_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	var candidate: Vector3 = _player.global_position

	for attempt in range(20):
		candidate = _random_ring_point()
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
