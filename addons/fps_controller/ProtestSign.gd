extends MeleeWeapon

@export var shove_range := 2.5
@export var shove_half_angle := 55.0
@export var shove_speed := 12.0
@export var shove_lift := 1.5

var _next_shove_msec: int = 0


func _try_hit() -> void:
	_submit_hit([])


func _apply_hit(_target_paths: Array) -> void:
	var now := Time.get_ticks_msec()
	if now < _next_shove_msec:
		return
	_next_shove_msec = now + int(swing_duration * 1000.0)
	var forward := -_wielder.global_basis.z
	var threshold := cos(deg_to_rad(shove_half_angle))
	for node in get_tree().get_nodes_in_group(&"police"):
		var cop := node as Police
		if cop == null or cop.health.is_dead() or cop.is_queued_for_deletion():
			continue
		var offset := cop.global_position - _wielder.global_position
		if offset.length_squared() > shove_range * shove_range:
			continue
		var direction := Vector3(offset.x, 0.0, offset.z).normalized()
		if forward.dot(direction) < threshold:
			continue
		var query := PhysicsRayQueryParameters3D.create(global_position, cop.body_collider.global_position, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider == cop:
			cop.apply_knockback(direction * shove_speed, shove_lift)
