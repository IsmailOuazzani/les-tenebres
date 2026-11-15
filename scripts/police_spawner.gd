extends Node3D
class_name PoliceSpawner

## Spawns police at generated street entrances on the host. The existing
## MultiplayerSpawner replicates the cops and each peer renders the rings.
const WARNING_LEAD_TIME: float = 0.4
const RING_SCALE := Vector3(1.0, 0.12, 1.0)

@export var police_scene: PackedScene
## Bigger, harder-hitting cop variant (res://scenes/megacop.tscn) -- same
## Police script/scene, just scaled up. How many of a wave are megacops is
## decided entirely by WaveManager (see begin_wave()'s megacop_count); this
## spawner just picks which scene to instantiate for each spawn slot.
@export var megacop_scene: PackedScene
@export var entrances_path: NodePath

var _entrances: Array[Marker3D] = []
var _rings: Array[MeshInstance3D] = []
var _active_entrance_indices: Array[int] = []
var _pending_entrance_index: int = -1

var spawned_police: Array[Node3D] = []

## -- Wave-driven spawn state (set by begin_wave(), consumed by _process())--
var _spawning: bool = false
var _police_remaining_to_spawn: int = 0
## Of _police_remaining_to_spawn, how many of the REMAINING spawns should be
## megacops. _spawn_police() converts one slot at a time with probability
## _megacop_remaining_to_spawn / _police_remaining_to_spawn, which spreads
## them evenly through the wave (same trick as dealing special cards from a
## shuffled deck) while still landing on the exact count by the last spawn.
var _megacop_remaining_to_spawn: int = 0
var _spawn_interval: float = 1.0
var _spawn_timer: float = 0.0

## Monotonic counter feeding deterministic replicated node names.
var _next_police_id: int = 0


func _ready() -> void:
	add_to_group(&"police_spawner")
	if police_scene == null:
		push_warning("PoliceSpawner: no police_scene assigned, nothing will spawn.")

	var entrance_root := get_node_or_null(entrances_path)
	if entrance_root == null:
		push_error("PoliceSpawner: generated police entrances are missing.")
		return

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.05, 0.03)
	var mesh := TorusMesh.new()
	mesh.inner_radius = 1.15
	mesh.outer_radius = 1.45
	mesh.material = material
	for child in entrance_root.get_children():
		var marker := child as Marker3D
		if marker == null:
			continue
		var ring := MeshInstance3D.new()
		ring.mesh = mesh
		ring.scale = RING_SCALE
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(ring)
		_entrances.append(marker)
		_rings.append(ring)

	WaveManager.wave_started.connect(_on_wave_started)
	_update_active_entrances(1)


func _on_wave_started(_wave: int, _police_total: int) -> void:
	_update_active_entrances(WaveManager.current_act)


func _update_active_entrances(act: int) -> void:
	_active_entrance_indices.clear()
	for index in _entrances.size():
		var active: bool = act >= int(_entrances[index].get_meta(&"unlock_act", 1))
		_rings[index].visible = active
		if active:
			_active_entrance_indices.append(index)


func _process(delta: float) -> void:
	if not _spawning or not NetworkManager.is_authoritative():
		return
	if police_scene == null:
		return
	if _police_remaining_to_spawn <= 0:
		_spawning = false
		return

	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return

	var lead_time := minf(WARNING_LEAD_TIME, _spawn_interval * 0.5)
	if _pending_entrance_index >= 0:
		if not PlayerRegistry.alive(self).is_empty():
			_spawn_police(_entrances[_pending_entrance_index])
			_police_remaining_to_spawn -= 1
		_pending_entrance_index = -1
		_spawn_timer = _spawn_interval - lead_time
	elif not _active_entrance_indices.is_empty() and not PlayerRegistry.alive(self).is_empty():
		_pending_entrance_index = _active_entrance_indices.pick_random()
		_spawn_timer = lead_time
		_pulse_entrance(_pending_entrance_index, lead_time)
		if NetworkManager.is_multiplayer_session():
			_pulse_entrance.rpc(_pending_entrance_index, lead_time)
	else:
		_spawn_timer = _spawn_interval


@rpc("authority", "call_remote", "reliable")
func _pulse_entrance(index: int, duration: float) -> void:
	var ring := _rings[index]
	ring.scale = RING_SCALE * 1.35
	ring.create_tween().tween_property(ring, "scale", RING_SCALE, duration)


## Called by WaveManager at the start of a wave: spawn `total_police` cops,
## spread evenly across `duration` seconds (so they trickle in across the
## whole wave rather than all landing at once). `megacop_count` of those
## (clamped to total_police) are megacops rather than regular cops.
func begin_wave(total_police: int, duration: float, megacop_count: int = 0) -> void:
	_police_remaining_to_spawn = max(total_police, 0)
	_megacop_remaining_to_spawn = clamp(megacop_count, 0, _police_remaining_to_spawn)
	_spawn_interval = duration / max(total_police, 1)
	_spawn_timer = 0.0
	_pending_entrance_index = -1
	_spawning = _police_remaining_to_spawn > 0


## Called by WaveManager when a wave ends (time-based completion, not
## kill-everything) -- stops handing out new spawns without touching
## already-live cops. See clear_all_police() for despawning those.
func stop_spawning() -> void:
	_pending_entrance_index = -1
	_spawning = false
	_police_remaining_to_spawn = 0
	_megacop_remaining_to_spawn = 0


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


## Set position before add_child() so MultiplayerSpawner serializes it.
func _spawn_police(entrance: Marker3D) -> void:
	var scene_to_spawn: PackedScene = police_scene
	if megacop_scene != null and _megacop_remaining_to_spawn > 0:
		var mega_chance: float = float(_megacop_remaining_to_spawn) / float(_police_remaining_to_spawn)
		if randf() < mega_chance:
			scene_to_spawn = megacop_scene
			_megacop_remaining_to_spawn -= 1

	var police: Node3D = scene_to_spawn.instantiate()
	police.name = "Cop%d" % _next_police_id
	_next_police_id += 1
	police.position = to_local(entrance.global_position)
	police.net_position = entrance.global_position
	add_child(police)
	spawned_police.append(police)
