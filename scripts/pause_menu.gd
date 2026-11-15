extends CanvasLayer

## Escape-triggered pause menu. Replaces the old behavior of Escape
## immediately tearing down the session (NetworkManager.return_to_menu())
## with an actual pause screen that has to be explicitly confirmed via the
## "Leave Match" button.
##
## Mirrors scenes/game_over.gd's pause/mouse-mode conventions in
## single-player (process_mode = PROCESS_MODE_ALWAYS on this CanvasLayer, see
## the .tscn, so it keeps responding to its own buttons while
## get_tree().paused is true).
##
## ## Multiplayer
##
## Per agents/multiplayer-notes.md's "nothing pauses the tree in a networked
## session" rule (pausing on the listen server would freeze the authoritative
## simulation for every player), opening this menu in a networked session
## does NOT set get_tree().paused. It's local-only: it freezes just the
## opening player's own character (NetPlayer.set_input_locked(), see
## scripts/player.gd) and shows the mouse, while every other player and the
## simulation keep running untouched. "Leave Match" still routes through
## NetworkManager.return_to_menu(), same as before -- that's an explicit,
## confirmed action now rather than an accidental Escape tap.

@onready var _resume_button: Button = %ResumeButton
@onready var _leave_button: Button = %LeaveButton

var _is_open: bool = false


func _ready() -> void:
	visible = false
	_resume_button.pressed.connect(_on_resume_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _is_open:
		close()
	else:
		_try_open()


## Doesn't open over another full-screen overlay (game over, Act scoreboard,
## upgrade shop) -- those already own Escape-era mouse/pause state and
## closing this menu on top of them would fight over it.
func _try_open() -> void:
	for screen in get_tree().get_nodes_in_group(&"blocking_screen"):
		if screen.visible:
			return
	_is_open = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if NetworkManager.is_multiplayer_session():
		_set_local_player_locked(true)
	else:
		get_tree().paused = true


func close() -> void:
	_is_open = false
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if NetworkManager.is_multiplayer_session():
		_set_local_player_locked(false)
	else:
		get_tree().paused = false


func _set_local_player_locked(locked: bool) -> void:
	var local_player: Node3D = PlayerRegistry.local(self)
	if local_player != null and local_player.has_method(&"set_input_locked"):
		local_player.set_input_locked(locked)


func _on_resume_pressed() -> void:
	close()


func _on_leave_pressed() -> void:
	NetworkManager.return_to_menu()
