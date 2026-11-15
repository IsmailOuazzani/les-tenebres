extends CanvasLayer

## Game-over screen. Triggered by GameState.game_over, which fires when the
## player's health reaches zero (GameState.trigger_player_death()); displays
## end-of-run stats plus a randomized humorous reason (placeholder per
## vision.md). See agents/grabuge-notes.md.

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
	# Lets scripts/pause_menu.gd check "is some other full-screen overlay
	# already up" without a direct node reference to each one.
	add_to_group(&"blocking_screen")
	GameState.game_over.connect(_on_game_over)
	_restart_button.pressed.connect(_on_restart_pressed)


## Game over is a shared, server-decided event in multiplayer (Grabuge is one
## shared score), so every peer shows the same screen with the same stats --
## the server ships its end-of-run numbers along with the event, see
## GameState._apply_game_over(). Only the host can start the next round,
## mirroring the lobby's "only the host can start the match" rule.
func _on_game_over() -> void:
	_populate_stats()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true

	if not NetworkManager.is_multiplayer_session():
		_restart_button.text = "RESTART"
		_restart_button.disabled = false
	elif NetworkManager.is_host():
		_restart_button.text = "BACK TO LOBBY"
		_restart_button.disabled = false
	else:
		_restart_button.text = "WAITING FOR HOST..."
		_restart_button.disabled = true


func _populate_stats() -> void:
	var duration_sec: float = GameState.get_session_duration()
	var minutes: int = int(duration_sec) / 60
	var seconds: int = int(duration_sec) % 60

	_stats_label.text = (
		"Peak protesters: %d\n"
		+ "Total disruptions: %d\n"
		+ "Protest duration: %d:%02d\n"
		+ "Total Grabuge earned: %d\n"
		+ "Police defeated: %d\n"
		+ "Waves survived: %d"
	) % [
		GameState.peak_crowd_count,
		GameState.total_disruptions,
		minutes,
		seconds,
		round(GameState.grabuge_total_earned),
		GameState.police_defeated_count,
		_waves_survived(),
	]

	_reason_label.text = HUMOROUS_REASONS[randi() % HUMOROUS_REASONS.size()]


## Waves fully cleared this run: finished Acts worth WAVES_PER_ACT each,
## plus whatever waves were cleared in the current (incomplete) Act.
func _waves_survived() -> int:
	return (WaveManager.current_act - 1) * WaveManager.WAVES_PER_ACT + (WaveManager.current_wave - 1)


func _on_restart_pressed() -> void:
	if NetworkManager.is_host():
		# Sends every peer back to the lobby, where the host can start
		# another match without relaunching the game (spec 3).
		NetworkManager.return_to_lobby()
		return

	get_tree().paused = false
	GameState.reset()
	# Autoloads survive reload_current_scene(), so without these
	# WaveManager/UpgradeManager would carry the previous run's Act/wave
	# and upgrade levels into the new one -- see
	# agents/wave-survival-notes.md. UpgradeManager.reset() is a stub the
	# other agent is implementing in parallel; calling it is safe either way.
	WaveManager.reset()
	UpgradeManager.reset()
	get_tree().reload_current_scene()
