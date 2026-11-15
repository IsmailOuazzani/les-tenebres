extends Control

## Main menu: the application's entry scene (project.godot
## `run/main_scene`). Offers the three session options from spec 3:
##
##   * Single Player -- starts the existing offline game, unchanged.
##   * Host LAN      -- starts a listen server and opens the lobby.
##   * Join LAN      -- connects to a listen server by IPv4 address.
##
## Also surfaces connection errors, including ones raised while this scene
## wasn't loaded (a failed join, or the host dropping mid-match sends
## everyone back here) -- NetworkManager keeps the last error so the message
## survives the scene change.

@onready var _name_field: LineEdit = %NameField
@onready var _address_field: LineEdit = %AddressField
@onready var _single_player_button: Button = %SinglePlayerButton
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _quit_button: Button = %QuitButton
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false

	_single_player_button.pressed.connect(_on_single_player_pressed)
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_address_field.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())

	NetworkManager.connection_error.connect(_on_connection_error)

	_name_field.text = NetworkManager.local_player_name
	_status_label.text = NetworkManager.get_last_error()


func _on_single_player_pressed() -> void:
	NetworkManager.local_player_name = _player_name()
	NetworkManager.start_single_player()


func _on_host_pressed() -> void:
	_status_label.text = "Starting listen server on port %d..." % NetworkManager.PORT
	NetworkManager.host_lan(_player_name())


func _on_join_pressed() -> void:
	_status_label.text = "Connecting to %s:%d..." % [_address_field.text, NetworkManager.PORT]
	NetworkManager.join_lan(_address_field.text, _player_name())


func _on_connection_error(reason: String) -> void:
	_status_label.text = reason


func _player_name() -> String:
	var entered: String = _name_field.text.strip_edges()
	if entered == "":
		return "Manifestant"
	return entered
