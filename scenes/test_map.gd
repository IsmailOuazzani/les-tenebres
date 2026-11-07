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

	# --- DEBUG HOOKS ---
	# G is the permanent Grabuge debug key per the original spec. O/I are
	# temporary stand-ins for contextual-disruption gameplay that doesn't
	# exist yet -- real megaphone recruitment already calls
	# GameState.recruit_npc() on its own (see scripts/crowd_controller.gd),
	# so KEY_O is now mostly redundant with that; remove it once disruption
	# gameplay (bus/road/plaza interactions) makes KEY_I unnecessary too.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_G:
				GameState.add_grabuge(GameState.DEBUG_GRABUGE_BUMP)
			KEY_O:
				GameState.recruit_npc()
			KEY_I:
				GameState.record_disruption()
