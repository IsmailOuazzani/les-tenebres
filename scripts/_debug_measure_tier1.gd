extends SceneTree

## One-off measurement script for the Tier 1 destructible batch. Not wired
## into gameplay; deleted after use.

const MODELS: Array[String] = [
	"res://assets/kenney_city_kit_roads/construction-fence.glb",
	"res://assets/kenney_city_kit_roads/electricity-pole.glb",
	"res://assets/kenney_city_kit_roads/light-curved.glb",
	"res://assets/kenney_city_kit_roads/bridge-pillar.glb",
	"res://assets/kenney_city_kit_roads/sign-highway.glb",
	"res://assets/kenney_city_kit_commercial/detail-awning.glb",
	"res://assets/kenney_city_kit_commercial/detail-parasol-a.glb",
	"res://assets/kenney_car_kit/sedan.glb",
	"res://assets/kenney_car_kit/ambulance.glb",
	"res://assets/kenney_car_kit/wheel-default.glb",
]


func _init() -> void:
	for path in MODELS:
		var packed: PackedScene = load(path)
		if packed == null:
			print("FAILED TO LOAD: ", path)
			continue
		var inst: Node3D = packed.instantiate()
		get_root().add_child(inst)
		var aabb := _world_aabb(inst)
		print(path, " -> size=", aabb.size, " min=", aabb.position, " max=", aabb.position + aabb.size)
		inst.queue_free()
	quit()


func _world_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mi in _find_mesh_instances(root):
		var local_aabb: AABB = mi.mesh.get_aabb() if mi.mesh else AABB()
		var xform: Transform3D = mi.global_transform
		var world_aabb := _transform_aabb(local_aabb, xform)
		if first:
			result = world_aabb
			first = false
		else:
			result = result.merge(world_aabb)
	return result


func _find_mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_mesh_instances(child))
	return found


func _transform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var corners: Array[Vector3] = []
	for i in range(8):
		corners.append(aabb.position + Vector3(
			aabb.size.x if i & 1 else 0.0,
			aabb.size.y if i & 2 else 0.0,
			aabb.size.z if i & 4 else 0.0,
		))
	var result := AABB(xform * corners[0], Vector3.ZERO)
	for c in corners:
		result = result.expand(xform * c)
	return result
