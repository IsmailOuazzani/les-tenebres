extends Node3D

## Grey-box test map bootstrap.
## Captures the mouse for FPS look and lets you quit/release the mouse,
## mirroring the behavior from the vendored FirstPersonStarter sample scene.

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()

	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# --- TEMPORARY DEBUG HOOKS ---
	# No real recruit/disruption gameplay exists yet (separate parallel
	# workstreams). These keys let the HUD/game-over flow be exercised
	# end-to-end by hand. Remove once real recruit-on-click and
	# disruption-on-mob-action systems call GameState directly.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_P:
				GameState.add_publicity(10.0)
			KEY_O:
				GameState.recruit_npc()
			KEY_I:
				GameState.record_disruption()
