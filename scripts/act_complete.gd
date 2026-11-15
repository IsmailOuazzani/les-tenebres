extends CanvasLayer

## Act-complete scoreboard. Shown when WaveManager.act_completed fires (the
## player survived every wave of the current Act) -- same shape as
## scripts/game_over.gd, per agents/wave-survival-notes.md. Pauses the tree
## like the upgrade screen/game-over screen do, so needs
## PROCESS_MODE_ALWAYS to keep responding to its own Continue button while
## paused.

@onready var _title_label: Label = %TitleLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _continue_button: Button = %ContinueButton


func _ready() -> void:
	visible = false
	# Lets scripts/pause_menu.gd check "is some other full-screen overlay
	# already up" without a direct node reference to each one.
	add_to_group(&"blocking_screen")
	WaveManager.act_completed.connect(_on_act_completed)
	# The scoreboard is dismissed when the next Act's first wave actually
	# starts, not by the button press itself -- in multiplayer only the
	# server starts it, so every peer's scoreboard closes together. See
	# scripts/upgrade_screen.gd for the same pattern and why the tree isn't
	# paused in a networked session.
	WaveManager.wave_started.connect(_on_wave_started)
	_continue_button.pressed.connect(_on_continue_pressed)


func _on_act_completed(act_number: int) -> void:
	_title_label.text = "ACT %d COMPLETE" % act_number
	_populate_stats()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not NetworkManager.is_multiplayer_session():
		get_tree().paused = true


## All six scoreboard stats per vision.md's "Acts and Progression" --
## waves survived is WaveManager's own count (WAVES_PER_ACT, since you only
## get here by finishing every wave of the Act); the rest live on
## GameState.
func _populate_stats() -> void:
	var duration_sec: float = GameState.get_session_duration()
	var minutes: int = int(duration_sec) / 60
	var seconds: int = int(duration_sec) % 60

	_stats_label.text = (
		"Waves survived: %d\n"
		+ "Peak crowd size: %d\n"
		+ "Total Grabuge earned: %d\n"
		+ "Police defeated: %d\n"
		+ "Total disruptions: %d\n"
		+ "Time survived: %d:%02d"
	) % [
		WaveManager.WAVES_PER_ACT,
		GameState.peak_crowd_count,
		round(GameState.grabuge_total_earned),
		GameState.police_defeated_count,
		GameState.total_disruptions,
		minutes,
		seconds,
	]


func _on_continue_pressed() -> void:
	WaveManager.start_next_act()


func _on_wave_started(_wave_number: int, _police_total: int) -> void:
	if not visible:
		return
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = false
