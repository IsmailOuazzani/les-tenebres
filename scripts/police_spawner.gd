extends Node3D
class_name PoliceSpawner

## Spawns scripts/police.gd enemies at a random point around the player, per
## agents/police-notes.md. Mirrors scripts/npc_spawner.gd's Grabuge-scaled
## trickle spawning (agents/protester-spawning-notes.md) instead of a flat
## timer, per vision.md's "Escalating City Response": a bigger, louder
## protest draws a bigger police response, up to a cap, rather than the same
## cop showing up on the same clock no matter what's happening.
##
## ## Multiplayer
##
## Police spawning is **server-authoritative** and replicated by the
## MultiplayerSpawner whose spawn_path points at this node (see
## scenes/test_map.tscn's PoliceReplicator). Clients run none of this. Like
## the civilian spawner, it stays idle until `begin_spawning()` is called,
## which happens only once every peer has loaded the map.
##
## Each cop is spawned around a randomly chosen living player rather than
## "the" player, so the police response is spread across the whole protest.

@export var police_scene: PackedScene
@export var spawn_radius_min: float = 12.0
@export var spawn_radius_max: float = 18.0

## Spawn rate (cops/sec) scales with Grabuge between these two bounds:
## rate(g) = spawn_rate_min + (spawn_rate_max - spawn_rate_min) * (g / 100)^spawn_rate_exponent
## Same shape as NPCSpawner's trickle formula -- low and slow early on, only
## ramping up hard once Grabuge is high.
@export var spawn_rate_min: float = 0.1
@export var spawn_rate_max: float = 0.6
@export var spawn_rate_exponent: float = 1.8
## Hard ceiling on concurrent live cops -- spawning pauses once this many
## are already out there, regardless of Grabuge.
@export var max_concurrent_police: int = 16

## How far into the camera's forward cone (dot product of normalized
## horizontal vectors, -1..1) a candidate point counts as "in view" and
## gets rejected in favor of another attempt -- see _is_in_view().
@export var in_view_dot_threshold: float = 0.3

var spawned_police: Array[Node3D] = []

var _timer: float = 0.0
## Monotonic counter feeding deterministic replicated node names.
var _next_police_id: int = 0
var _spawning_enabled: bool = false


func _ready() -> void:
	set_process(false)
	if police_scene == null:
		push_warning("PoliceSpawner: no police_scene assigned, nothing will spawn.")


## Called by the match scene once every peer has loaded and players exist.
## Server-only.
func begin_spawning() -> void:
	if not NetworkManager.is_authoritative():
		return
	if police_scene == null:
		return
	_spawning_enabled = true
	set_process(true)


func _process(delta: float) -> void:
	if not _spawning_enabled or not NetworkManager.is_authoritative():
		return
	if police_scene == null:
		return

	if _count_live_police() >= max_concurrent_police:
		return

	_timer -= delta
	if _timer <= 0.0:
		_spawn_police()
		_timer = 1.0 / max(_spawn_rate(GameState.grabuge), 0.001)


func _count_live_police() -> int:
	for i in range(spawned_police.size() - 1, -1, -1):
		if not is_instance_valid(spawned_police[i]):
			spawned_police.remove_at(i)
	return spawned_police.size()


func _spawn_rate(grabuge: float) -> float:
	var t: float = clamp(grabuge / GameState.GRABUGE_MAX, 0.0, 1.0)
	return spawn_rate_min + (spawn_rate_max - spawn_rate_min) * pow(t, spawn_rate_exponent)


## Server-side spawn. Name and position are set before add_child(), which is
## when the MultiplayerSpawner serializes spawn state for clients.
func _spawn_police() -> void:
	var anchor: Node3D = PlayerRegistry.random_alive(self)
	if anchor == null:
		return

	var police: Node3D = police_scene.instantiate()
	police.name = "Cop%d" % _next_police_id
	_next_police_id += 1
	var spawn_point: Vector3 = _find_spawn_point(anchor)
	police.position = spawn_point
	police.net_position = spawn_point
	add_child(police)
	spawned_police.append(police)


## Picks a random point in the [spawn_radius_min, spawn_radius_max] ring
## around `anchor`, preferring one outside the *local* camera's forward view
## cone (per the spec's "preferably outside the camera view") -- falls back to
## just taking the last attempt if every try lands in view.
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
