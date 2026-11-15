extends Node3D
class_name CroissantProjectile

signal finished(point: Vector3)

var direction: Vector3
var speed: float
var range_left: float
var damage: float


func _physics_process(delta: float) -> void:
	var distance := minf(speed * delta, range_left)
	var destination := global_position + direction * distance
	if NetworkManager.is_host():
		var query := PhysicsRayQueryParameters3D.create(global_position, destination, 5)
		query.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var target: Object = hit.collider
			if target.has_method(&"take_damage"):
				target.take_damage(damage)
			finished.emit(hit.position)
			return

	global_position = destination
	range_left -= distance
	if range_left <= 0.0:
		set_physics_process(false)
		if NetworkManager.is_host():
			finished.emit(destination)
