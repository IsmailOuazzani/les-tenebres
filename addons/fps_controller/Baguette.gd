extends MeleeWeapon

const MIN_HIT_INTERVAL_MSEC := 450

@export var launch_speed := 24.0
@export var launch_lift := 6.0

@onready var _attacker: NetPlayer = get_node("../../..") as NetPlayer

var _next_hit_msec: int = 0


func _try_hit() -> void:
	if not _attacker.is_alive():
		return
	var closest: Police = null
	var closest_distance := INF
	for body in hit_area.get_overlapping_bodies():
		var cop := body as Police
		if cop == null or cop.is_queued_for_deletion() or cop.health.is_dead():
			continue
		var distance := global_position.distance_squared_to(cop.global_position)
		if distance < closest_distance and _can_reach(cop):
			closest = cop
			closest_distance = distance
	if closest != null:
		_play_crumb_burst()
		_submit_hit([String(closest.get_path())])


func _apply_hit(target_paths: Array) -> void:
	var now := Time.get_ticks_msec()
	if target_paths.size() != 1 or now < _next_hit_msec or not _attacker.is_alive():
		return
	var cop := get_node_or_null(NodePath(String(target_paths[0]))) as Police
	if cop == null or cop.is_queued_for_deletion() or cop.health.is_dead():
		return
	if global_position.distance_to(cop.global_position) > SERVER_HIT_RANGE:
		return
	if not _can_reach(cop):
		return

	_next_hit_msec = now + MIN_HIT_INTERVAL_MSEC
	var direction := cop.global_position - _attacker.global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		direction = -_attacker.global_basis.z
	cop.take_damage(hit_damage)
	cop.apply_knockback(direction.normalized() * launch_speed, launch_lift)


func _can_reach(cop: Police) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, cop.body_collider.global_position, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == cop
