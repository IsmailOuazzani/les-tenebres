class_name ClassHalo

## Matches the game's existing capsule outline and keeps the material local to the viewer.
static func create(color: Color, through_walls: bool, size := Vector2(0.48, 1.88)) -> MeshInstance3D:
	var halo := MeshInstance3D.new()
	halo.name = "ClassHalo"
	halo.visible = false
	halo.position.y = 0.85
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var capsule := CapsuleMesh.new()
	capsule.radius = size.x
	capsule.height = size.y
	halo.mesh = capsule

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.albedo_color = color
	material.no_depth_test = through_walls
	halo.material_override = material
	return halo
