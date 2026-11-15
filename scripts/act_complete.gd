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
	WaveManager.act_completed.connect(_on_act_completed)
	_continue_button.pressed.connect(_on_continue_pressed)


func _on_act_completed(act_number: int) -> void:
	_title_label.text = "ACT %d COMPLETE" % act_number
	_populate_stats()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
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
	get_tree().paused = false
	visible = false
	WaveManager.start_next_act()
