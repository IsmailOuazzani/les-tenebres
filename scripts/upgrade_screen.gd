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
@onready var _continue_button: Button = %ContinueButton

## Kenney UI Pack theme_type_variation names, same source as
## scripts/hud.gd (see agents/hud-theme-notes.md) -- reused here rather than
## inventing new styling.
const _BUY_VARIANT_AFFORDABLE := &"ButtonPrimary"
const _BUY_VARIANT_DISABLED := &"ButtonPlain"
const _CARD_VARIANT := &"PanelContainerDefaultFlat"


func _ready() -> void:
	visible = false
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
	_next_wave_label.text = "Next wave: %d" % next_wave_number
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


## Both of these fire from UpgradeManager.purchase() in the same call
## (spend_grabuge() -> grabuge_changed, then upgrade_purchased) -- guarding
## on `visible` means a purchase made right as the screen closes (shouldn't
## happen, no buttons exist once hidden) can't rebuild a hidden screen.
func _on_grabuge_changed(_available: float, _total_earned: float) -> void:
	if visible:
		_refresh()


func _on_upgrade_purchased(_id: StringName, _new_level: int) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	_grabuge_label.text = "Grabuge available: %d" % round(GameState.grabuge_available)
	_rebuild_cards()


func _rebuild_cards() -> void:
	for child in _cards_container.get_children():
		child.queue_free()

	for upgrade in UpgradeManager.get_upgrades():
		_cards_container.add_child(_build_card(upgrade))


## One row per upgrade: name + current level, effect description, price, and
## a Buy button that's disabled/greyed (per the Kenney "Plain" variant) when
## unaffordable. Built in code rather than as scene children, per the class
## comment above.
func _build_card(upgrade: Dictionary) -> PanelContainer:
	var id: StringName = upgrade["id"]
	var affordable: bool = upgrade["affordable"]

	var card := PanelContainer.new()
	card.theme_type_variation = _CARD_VARIANT

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info_box)

	var name_label := Label.new()
	name_label.text = "%s  (Lv. %d)" % [upgrade["name"], upgrade["level"]]
	info_box.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = upgrade["description"]
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.modulate = Color(1.0, 1.0, 1.0, 0.7)
	info_box.add_child(desc_label)

	var price_label := Label.new()
	price_label.text = "%d" % round(upgrade["price"])
	price_label.custom_minimum_size = Vector2(56, 0)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(price_label)

	var buy_button := Button.new()
	buy_button.text = "Buy"
	buy_button.custom_minimum_size = Vector2(72, 0)
	buy_button.disabled = not affordable
	buy_button.theme_type_variation = _BUY_VARIANT_AFFORDABLE if affordable else _BUY_VARIANT_DISABLED
	buy_button.pressed.connect(_on_buy_pressed.bind(id))
	row.add_child(buy_button)

	return card


func _on_buy_pressed(id: StringName) -> void:
	UpgradeManager.purchase(id)
