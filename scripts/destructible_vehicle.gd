extends DestructibleProp
class_name DestructibleVehicle

## Destructible vehicle variant -- same "destructible" group contract as
## scripts/destructible_prop.gd (take_damage/set_targeted/destroyed), but on
## death detaches a set of debris pieces (wheels, doors, bumper...) as
## physics-driven RigidBody3D instead of just scaling the whole prop to zero.
## Built for the "bus" Send Mob target from vision.md ("some [protesters]
## attempting to climb onto it") -- Kenney's Car Kit ships no bus model (the
## prior research notes claiming one were wrong, see
## agents/prop-character-assets-research.md), so this uses garbage-truck.glb
## as the stand-in large vehicle.
##
## Each entry in debris_paths must point at a RigidBody3D child that starts
## frozen (so it renders attached to the vehicle normally); on death it's
## reparented to the vehicle's parent, unfrozen, and given a random impulse.

@export var debris_paths: Array[NodePath] = []
@export var debris_despawn_time: float = 8.0
@export var debris_impulse_strength: float = 2.5


func _die() -> void:
	_dying = true
	_health_bar.visible = false
	destroyed.emit()
	GameState.record_disruption(1.0)

	var parent := get_parent()
	var my_transform := global_transform
	for path in debris_paths:
		var debris: RigidBody3D = get_node_or_null(path)
		if debris == null:
			continue
		var debris_global_xform := debris.global_transform
		remove_child(debris)
		parent.add_child(debris)
		debris.global_transform = debris_global_xform
		debris.freeze = false
		debris.apply_impulse(
			(debris_global_xform.origin - my_transform.origin).normalized() * debris_impulse_strength
			+ Vector3.UP * debris_impulse_strength * 0.5
		)
		get_tree().create_timer(debris_despawn_time).timeout.connect(debris.queue_free)

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(queue_free)
