extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://addons/blood_effect/node_3d.scn")
	var inst := packed.instantiate()
	print(inst.get_name(), " : ", inst.get_class())
	_dump(inst, 0)
	quit()

func _dump(node: Node, depth: int) -> void:
	print("  ".repeat(depth), node.name, " (", node.get_class(), ")")
	if node is GPUParticles3D:
		var p: GPUParticles3D = node
		print("  ".repeat(depth + 1), "amount=", p.amount, " one_shot=", p.one_shot, " lifetime=", p.lifetime, " explosiveness=", p.explosiveness, " draw_pass=", p.draw_pass_1, " process_material=", p.process_material)
	if node is Decal:
		print("  ".repeat(depth + 1), "decal texture_albedo=", node.texture_albedo)
	for child in node.get_children():
		_dump(child, depth + 1)
