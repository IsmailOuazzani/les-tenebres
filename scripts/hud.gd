extends CanvasLayer

## Live HUD showing crowd count, Grabuge, and (per agents/police-notes.md)
## player health. Crowd/Grabuge are driven entirely by the GameState
## autoload (see agents/grabuge-notes.md); health instead reads directly off
## the player's own HealthComponent via `player_health_path`, since health
## isn't global state the way Grabuge is.

@export var player_health_path: NodePath

@onready var _crowd_label: Label = %CrowdLabel
@onready var _grabuge_bar: ProgressBar = %GrabugeBar
@onready var _grabuge_label: Label = %GrabugeLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel


func _ready() -> void:
	GameState.crowd_count_changed.connect(_on_crowd_count_changed)
	GameState.grabuge_changed.connect(_on_grabuge_changed)

	_on_crowd_count_changed(GameState.crowd_count)
	_on_grabuge_changed(GameState.grabuge)

	var player_health: Node = get_node_or_null(player_health_path)
	if player_health != null:
		player_health.health_changed.connect(_on_player_health_changed)
		_on_player_health_changed(player_health.current_health, player_health.max_health)


func _on_crowd_count_changed(value: int) -> void:
	_crowd_label.text = "Protesters: %d" % value


func _on_grabuge_changed(value: float) -> void:
	_grabuge_bar.value = value
	_grabuge_label.text = "Grabuge: %d%%" % round(value)


func _on_player_health_changed(current: float, max_value: float) -> void:
	_health_bar.max_value = max_value
	_health_bar.value = current
	_health_label.text = "Health: %d" % round(current)
