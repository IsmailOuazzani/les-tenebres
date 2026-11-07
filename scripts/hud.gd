extends CanvasLayer

## Live HUD showing crowd count, publicity, and patience, driven entirely by
## the GameState autoload. See agents/publicity-patience-notes.md.

@onready var _crowd_label: Label = %CrowdLabel
@onready var _publicity_label: Label = %PublicityLabel
@onready var _patience_bar: ProgressBar = %PatienceBar
@onready var _patience_label: Label = %PatienceLabel


func _ready() -> void:
	GameState.crowd_count_changed.connect(_on_crowd_count_changed)
	GameState.publicity_changed.connect(_on_publicity_changed)
	GameState.patience_changed.connect(_on_patience_changed)

	_on_crowd_count_changed(GameState.crowd_count)
	_on_publicity_changed(GameState.publicity)
	_on_patience_changed(GameState.patience)


func _on_crowd_count_changed(value: int) -> void:
	_crowd_label.text = "Protesters: %d" % value


func _on_publicity_changed(value: float) -> void:
	_publicity_label.text = "Publicity: %d" % round(value)


func _on_patience_changed(value: float) -> void:
	_patience_bar.value = value
	_patience_label.text = "Patience: %d%%" % round(value)
