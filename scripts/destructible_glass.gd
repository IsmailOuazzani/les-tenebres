extends DestructibleProp
class_name DestructibleGlass

## Destructible glass pane -- same "destructible" group contract as
## scripts/destructible_prop.gd, but on death shatters a child
## BreakableGlassCustom pane (addons/breakable_glass_custom, vendored from
## github.com/Stand43/godot_breakable_glass_custom, MIT) instead of scaling
## the whole prop to zero. Standalone storefront-window-style prop; not a
## retrofit of the Paris building FBXs.

@onready var _pane: Node = $GlassPane


func _die() -> void:
	_dying = true
	_health_bar.visible = false
	destroyed.emit()
	GameState.record_disruption(1.0)
	remove_from_group(&"destructible")

	# break_window() reparents its shard RigidBody3Ds onto the pane's
	# *current* parent, which is this node -- so unlike the base class this
	# node must stay alive (not scale-tween-then-queue_free) until the
	# shards' own despawn timer (addon-owned) has had a chance to fire,
	# otherwise queue_free() here would take the shards down with it.
	_pane.break_window(_pane.global_position)
	get_tree().create_timer(_pane.despawn_time + 0.5).timeout.connect(queue_free)
