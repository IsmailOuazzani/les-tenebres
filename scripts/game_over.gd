extends CanvasLayer

## Game-over screen. Triggered by GameState.game_over, which fires when
## Grabuge decays to zero; displays end-of-run stats plus a randomized
## humorous reason (placeholder per vision.md). See agents/grabuge-notes.md.

## Placeholder "humorous reason" list. Real version should eventually pick a
## reason tied to what actually happened in the run (e.g. mob got separated,
## repeated failed disruptions) once that gameplay exists; for now it's just
## flavor text chosen at random.
const HUMOROUS_REASONS: Array[String] = [
	"Everyone went home for lunch.",
	"The mob got distracted by a mime.",
	"Someone mentioned the metro was about to close.",
	"A food truck selling crepes showed up three streets over.",
	"The protest chant turned into an argument about chant lyrics.",
	"It started drizzling and nobody brought an umbrella.",
	"The police handed out free croissants as a de-escalation tactic.",
	"Everyone remembered they had somewhere else to be.",
	"A pigeon landed on the megaphone and nobody knew what to do.",
	"The crowd got rickrolled by a nearby street performer.",
]

@onready var _reason_label: Label = %ReasonLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _restart_button: Button = %RestartButton


func _ready() -> void:
	visible = false
	GameState.game_over.connect(_on_game_over)
	_restart_button.pressed.connect(_on_restart_pressed)


func _on_game_over() -> void:
	_populate_stats()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true


func _populate_stats() -> void:
	var duration_sec: float = GameState.get_session_duration()
	var minutes: int = int(duration_sec) / 60
	var seconds: int = int(duration_sec) % 60

	_stats_label.text = (
		"Peak protesters: %d\n"
		+ "Total disruptions: %d\n"
		+ "Protest duration: %d:%02d\n"
		+ "Peak Grabuge reached: %d%%"
	) % [
		GameState.peak_crowd_count,
		GameState.total_disruptions,
		minutes,
		seconds,
		round(GameState.peak_grabuge),
	]

	_reason_label.text = HUMOROUS_REASONS[randi() % HUMOROUS_REASONS.size()]


func _on_restart_pressed() -> void:
	get_tree().paused = false
	GameState.reset()
	get_tree().reload_current_scene()
