extends SceneTree

func _init() -> void:
	for path in ["res://scenes/npc.tscn", "res://scenes/police.tscn"]:
		var packed: PackedScene = load(path)
		var a: Node = packed.instantiate()
		a.call("_ready")
		var b: Node = packed.instantiate()
		b.call("_ready")

		var shape_a: CapsuleShape3D = a.get_node("CollisionShape3D").shape
		var shape_b: CapsuleShape3D = b.get_node("CollisionShape3D").shape

		print(path, " attack_range=", a.attack_range, " ratio=", a.collider_to_damage_ratio, \
			" computed_radius_a=", shape_a.radius, " computed_radius_b=", shape_b.radius)

		# Mutate A's shape directly and confirm B is unaffected (sub-resources
		# must be per-instance, not shared, or this ratio feature would be broken).
		shape_a.radius = 999.0
		print("  after mutating A to 999 -- A=", shape_a.radius, " B=", shape_b.radius, \
			" (shared_resource_bug=", shape_b.radius == 999.0, ")")

		a.free()
		b.free()
	quit()
