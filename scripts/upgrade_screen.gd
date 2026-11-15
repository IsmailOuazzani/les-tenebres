extends CanvasLayer

## Between-wave upgrade station -- the TF2 Mann-vs-Machine-style shop opened
## by WaveManager.intermission_started() per agents/wave-survival-notes.md.
## Mirrors scenes/game_over.gd's pause/mouse-mode conventions (process_mode =
## PROCESS_MODE_ALWAYS on this CanvasLayer, see the .tscn), since this screen
## must keep running its own UI while get_tree().paused is true.
##
## Cards are built entirely from UpgradeManager.get_upgrades() rather than
## hand-placed in the scene, so a 7th upgrade later needs zero scene edits --
## same precedent as scripts/hud.gd's _build_hotbar().
##
## ## Multiplayer
##
## The shop is **shared**: one Grabuge wallet, one upgrade set (see
## scripts/upgrade_manager.gd), so every peer opens and closes it together on
## WaveManager's replicated phase transitions, and the first player to press
## Continue starts the countdown for everybody.
##
## Two single-player behaviors deliberately do NOT carry over:
##   * the tree is not paused -- pausing on the listen server would freeze
##     the authoritative simulation for every player, and pausing on a client
##     would only desync its own view.
##   * Continue does not close this screen directly; it asks WaveManager for
##     the countdown and the screen closes when that transition comes back
##     (which in single-player is the same frame, so nothing changes there).

@onready var _next_wave_label: Label = %NextWaveLabel
@onready var _grabuge_label: Label = %GrabugeLabel
@onready var _cards_container: VBoxContainer = %CardsContainer
@onready var _offers_scroll: ScrollContainer = %OffersScroll
@onready var _continue_button: Button = %ContinueButton

var _level_labels: Dictionary[StringName, Label] = {}
var _current_labels: Dictionary[StringName, Label] = {}
var _buy_buttons: Dictionary[StringName, Button] = {}


func _ready() -> void:
	visible = false
	# Lets scripts/pause_menu.gd check "is some other full-screen overlay
	# already up" without a direct node reference to each one.
	add_to_group(&"blocking_screen")
	_build_cards()
	_continue_button.pressed.connect(_on_continue_pressed)
	GameState.grabuge_changed.connect(_on_grabuge_changed)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)

	# WaveManager is being built in parallel (see agents/wave-survival-notes.md);
	# this is the exact contract hookup, but if its autoload somehow doesn't
	# expose the signal yet, don't take the whole screen down with it --
	# open()/close() can still be called directly for standalone testing.
	if WaveManager.has_signal(&"intermission_started"):
		WaveManager.intermission_started.connect(_on_intermission_started)
		WaveManager.intermission_countdown_started.connect(_on_countdown_started)
	else:
		push_warning("UpgradeScreen: WaveManager.intermission_started not found; open() must be called directly.")


func _on_intermission_started(next_wave_number: int, _duration: float) -> void:
	open(next_wave_number)


## Opens the shop: pauses the tree and releases the mouse, same conventions
## as scenes/game_over.gd. Public (not just signal-driven) so this screen can
## be verified standalone -- see the class comment above.
func open(next_wave_number: int) -> void:
	_next_wave_label.text = "Before Wave %d" % next_wave_number
	_offers_scroll.scroll_vertical = 0
	_refresh()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not NetworkManager.is_multiplayer_session():
		get_tree().paused = true


## Closes the shop and hands control back to WaveManager for the live
## pre-wave countdown (where the player can still recruit) -- this exact
## call is the handoff contract with the wave system. The screen itself is
## hidden by _on_countdown_started(), which WaveManager fires back (same
## frame in single-player, over the wire in multiplayer).
func close() -> void:
	WaveManager.begin_intermission_countdown()


## The actual teardown, driven by WaveManager's countdown transition so every
## peer leaves the shop at the same moment.
func _on_countdown_started() -> void:
	if not visible:
		return
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = false


func _on_continue_pressed() -> void:
	close()


## Both signals can arrive for one purchase. Update the existing rows so
## neither refresh resets scrolling or replaces the focused button.
func _on_grabuge_changed(_available: float, _total_earned: float) -> void:
	if visible:
		_refresh()


func _on_upgrade_purchased(_id: StringName, _new_level: int) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	_grabuge_label.text = str(roundi(GameState.grabuge_available))
	for upgrade in UpgradeManager.get_upgrades():
		var id: StringName = upgrade["id"]
		_level_labels[id].text = "Lv. %d" % upgrade["level"]
		_current_labels[id].text = "Current: %s" % upgrade["current_value"]
		_buy_buttons[id].text = "Buy · %d" % roundi(upgrade["price"])
		_buy_buttons[id].disabled = not upgrade["affordable"]


func _build_cards() -> void:
	var upgrades := UpgradeManager.get_upgrades()
	_build_section("Player", "player_", upgrades)
	_build_section("Crowd", "crowd_", upgrades)


func _build_section(title: String, id_prefix: String, upgrades: Array[Dictionary]) -> void:
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"HUDMuted"
	_cards_container.add_child(heading)

	for upgrade in upgrades:
		var id: StringName = upgrade["id"]
		if String(id).begins_with(id_prefix):
			_cards_container.add_child(_build_card(id, upgrade))


func _build_card(id: StringName, upgrade: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"HUDCard"

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.add_theme_constant_override("separation", 0)
	row.add_child(info_box)

	var name_label := Label.new()
	name_label.text = upgrade["name"]
	info_box.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = upgrade["description"]
	desc_label.theme_type_variation = &"HUDMuted"
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(desc_label)

	var current_label := Label.new()
	current_label.theme_type_variation = &"HUDMuted"
	current_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(current_label)
	_current_labels[id] = current_label

	var level_label := Label.new()
	level_label.theme_type_variation = &"HUDMuted"
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.custom_minimum_size.x = 42
	row.add_child(level_label)
	_level_labels[id] = level_label

	var buy_button := Button.new()
	buy_button.custom_minimum_size.x = 100
	buy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy_button.pressed.connect(_on_buy_pressed.bind(id))
	row.add_child(buy_button)
	_buy_buttons[id] = buy_button

	return card


func _on_buy_pressed(id: StringName) -> void:
	UpgradeManager.purchase(id)
