extends Node

# Runs inside a FULL project boot (so the GameState autoload exists and every
# prop script compiles). Never saves anything.

const HALF_CORR := 10.0
const NS := [-96.0, -32.0, 32.0, 96.0]
const EW := [-96.0, -32.0, 32.0, 96.0]


func _ready() -> void:
	var ps: PackedScene = load("res://scenes/test_map.tscn")
	if ps == null:
		print("VERIFY: test_map failed to load")
		get_tree().quit(1)
		return
	var root: Node = ps.instantiate()
	add_child(root)
	await get_tree().process_frame
	await get_tree().process_frame

	var mg: Node = root.get_node_or_null("MapGeometry")
	if mg == null:
		print("VERIFY: no MapGeometry node")
		get_tree().quit(1)
		return

	var vis: Node = mg.get_node_or_null("Visuals")
	var prp: Node = mg.get_node_or_null("Props")
	var col: Node = mg.get_node_or_null("Collision")
	print("VERIFY tree: Visuals=%d Props=%d Collision=%d" % [
		vis.get_child_count() if vis else -1,
		prp.get_child_count() if prp else -1,
		col.get_child_count() if col else -1])

	# --- destructibles actually registered ---
	var destr: Array = get_tree().get_nodes_in_group("destructible")
	print("VERIFY destructible group members: %d" % destr.size())
	var no_hp := 0
	for d in destr:
		if not (d.has_method("take_damage")):
			no_hp += 1
	print("VERIFY destructibles missing take_damage(): %d" % no_hp)

	# --- building boxes: overlap + street intrusion ---
	var boxes: Array = []
	for c in col.get_children():
		if not (c is StaticBody3D):
			continue
		if c.name == "GroundCollision":
			continue
		var shape_node: CollisionShape3D = null
		for sc in c.get_children():
			if sc is CollisionShape3D:
				shape_node = sc
				break
		if shape_node == null or not (shape_node.shape is BoxShape3D):
			continue
		var sz: Vector3 = (shape_node.shape as BoxShape3D).size
		var b: AABB = AABB(-sz * 0.5, sz)
		boxes.append([String(c.name), (c as Node3D).global_transform * b])

	var overlaps := 0
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var a: AABB = boxes[i][1]
			var bb: AABB = boxes[j][1]
			if a.intersects(bb):
				var ov: AABB = a.intersection(bb)
				if ov.size.x > 0.05 and ov.size.z > 0.05:
					overlaps += 1
					if overlaps <= 5:
						print("  OVERLAP %s <-> %s  %.2f x %.2f" % [
							boxes[i][0], boxes[j][0], ov.size.x, ov.size.z])
	print("VERIFY building boxes: %d, overlapping pairs: %d" % [boxes.size(), overlaps])

	var intrusions := 0
	for e in boxes:
		var a: AABB = e[1]
		var x0: float = a.position.x
		var x1: float = a.position.x + a.size.x
		var z0: float = a.position.z
		var z1: float = a.position.z + a.size.z
		var bad := false
		for sx in NS:
			if x0 < sx + HALF_CORR - 0.05 and x1 > sx - HALF_CORR + 0.05:
				bad = true
		for ez in EW:
			if z0 < ez + HALF_CORR - 0.05 and z1 > ez - HALF_CORR + 0.05:
				bad = true
		# Only a real intrusion if it blocks BOTH axes of some corridor cell.
		if bad:
			var blocks := false
			for sx in NS:
				if x0 < sx + HALF_CORR - 0.05 and x1 > sx - HALF_CORR + 0.05:
					blocks = true
			for ez in EW:
				if z0 < ez + HALF_CORR - 0.05 and z1 > ez - HALF_CORR + 0.05:
					blocks = true
			if blocks:
				intrusions += 1
				if intrusions <= 5:
					print("  INTRUDES %s x[%.1f,%.1f] z[%.1f,%.1f]" % [e[0], x0, x1, z0, z1])
	print("VERIFY buildings intruding into a street corridor: %d" % intrusions)

	# --- props buried inside buildings ---
	var buried := 0
	for p in prp.get_children():
		var pos: Vector3 = (p as Node3D).global_position
		for e in boxes:
			var a: AABB = e[1]
			if pos.x > a.position.x + 0.6 and pos.x < a.position.x + a.size.x - 0.6 \
					and pos.z > a.position.z + 0.6 and pos.z < a.position.z + a.size.z - 0.6:
				buried += 1
				if buried <= 5:
					print("  BURIED %s at (%.1f, %.1f) inside %s" % [p.name, pos.x, pos.z, e[0]])
				break
	print("VERIFY props buried inside buildings: %d / %d" % [buried, prp.get_child_count()])

	# --- textures linked on a sample of tiles and buildings ---
	var untextured := 0
	var checked := 0
	for i in range(0, vis.get_child_count(), 37):
		var n: Node = vis.get_child(i)
		for m in _meshes(n):
			checked += 1
			var mat: Material = m.get_active_material(0)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture == null:
				untextured += 1
	print("VERIFY sampled meshes: %d, with null albedo_texture: %d" % [checked, untextured])

	get_tree().quit(0)


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
