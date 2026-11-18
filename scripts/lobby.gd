extends Control

## Pre-match lobby (spec 3).
##
##   * Lists the connected players, host first.
##   * Shows the host's LAN IPv4 address and port so other players can join.
##   * Only the host gets a Start Match button; clients see a waiting notice.
##   * Starting the match loads the same map on every peer and spawns players
##     only once all of them report loaded -- the handshake lives in
##     NetworkManager, this scene just presses the button.
##
## There is no late joining: NetworkManager drops peers that connect after
## the match has started, so the lobby is the only way in.

@onready var _player_list: VBoxContainer = %PlayerList
@onready var _address_label: Label = %AddressLabel
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _hint_label: Label = %HintLabel
@onready var _class_picker: HBoxContainer = %ClassPicker
@onready var _class_description: Label = %ClassDescription


const CLASS_CARD := preload("res://scenes/class_card.tscn")
var _cards: Dictionary[int, Button] = {}


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false

	_start_button.pressed.connect(_on_start_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)

	var group := ButtonGroup.new()
	for kit: int in PlayerClass.LAN_KITS:
		var card := CLASS_CARD.instantiate() as Button
		card.button_group = group
		card.tooltip_text = PlayerClass.description(kit)
		card.accessibility_name = PlayerClass.display_name(kit)
		_class_picker.add_child(card)
		var caption := card.get_node("Caption") as Label
		caption.text = PlayerClass.display_name(kit)
		var character := PlayerClass.outfit(kit).instantiate() as Node3D
		character.rotation.y = 0.18
		card.get_node("Portrait/Stage").add_child(character)
		var animator := character.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if animator and animator.has_animation(&"Idle"):
			animator.play(&"Idle")
		card.pressed.connect(_on_kit_selected.bind(kit))
		_cards[kit] = card

	NetworkManager.players_changed.connect(_refresh)
	NetworkManager.match_starting.connect(_lock_cards)
	NetworkManager.connection_error.connect(_on_connection_error)

	if NetworkManager.is_host():
		_address_label.text = "Players join at  %s : %d" % [
			NetworkManager.get_lan_address(), NetworkManager.PORT
		]
		_start_button.visible = true
		_hint_label.text = "Waiting for players. Up to %d can join." % NetworkManager.MAX_PLAYERS
	else:
		_address_label.text = "Connected to host on port %d" % NetworkManager.PORT
		_start_button.visible = false
		_hint_label.text = "Waiting for the host to start the match..."

	_refresh()


func _refresh() -> void:
	for child in _player_list.get_children():
		_player_list.remove_child(child)
		child.queue_free()

	var ids: Array = NetworkManager.players.keys()
	ids.sort()
	for id in ids:
		var row := Label.new()
		var tags: Array[String] = []
		if int(id) == 1:
			tags.append("host")
		if int(id) == NetworkManager.get_local_peer_id():
			tags.append("you")
		var suffix: String = "" if tags.is_empty() else "  (%s)" % ", ".join(tags)
		row.text = "%s  |  %s%s" % [
			NetworkManager.get_player_name(int(id)),
			PlayerClass.display_name(NetworkManager.get_player_kit(int(id))),
			suffix,
		]
		_player_list.add_child(row)

	var local_id := NetworkManager.get_local_peer_id()
	var kit := NetworkManager.get_player_kit(local_id)
	for id: int in _cards:
		_cards[id].set_pressed_no_signal(id == kit)
		_cards[id].disabled = NetworkManager.match_in_progress or not NetworkManager.players.has(local_id)
	_class_description.text = PlayerClass.description(kit)

	if NetworkManager.is_host():
		_start_button.disabled = NetworkManager.players.is_empty() or NetworkManager.match_in_progress


func _lock_cards() -> void:
	for card: Button in _cards.values():
		card.disabled = true


func _on_kit_selected(kit: int) -> void:
	_class_description.text = PlayerClass.description(kit)
	NetworkManager.select_kit(kit)


func _on_start_pressed() -> void:
	_start_button.disabled = true
	_hint_label.text = "Loading map on all peers..."
	NetworkManager.start_match()


func _on_leave_pressed() -> void:
	NetworkManager.return_to_menu()


func _on_connection_error(reason: String) -> void:
	_hint_label.text = reason
