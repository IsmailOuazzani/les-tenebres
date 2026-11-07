extends CanvasLayer

## Live HUD showing crowd count and Grabuge, driven entirely by the
## GameState autoload. See agents/grabuge-notes.md.

@onready var _crowd_label: Label = %CrowdLabel
@onready var _grabuge_bar: ProgressBar = %GrabugeBar
@onready var _grabuge_label: Label = %GrabugeLabel


func _ready() -> void:
	GameState.crowd_count_changed.connect(_on_crowd_count_changed)
	GameState.grabuge_changed.connect(_on_grabuge_changed)

	_on_crowd_count_changed(GameState.crowd_count)
	_on_grabuge_changed(GameState.grabuge)


func _on_crowd_count_changed(value: int) -> void:
	_crowd_label.text = "Protesters: %d" % value


func _on_grabuge_changed(value: float) -> void:
	_grabuge_bar.value = value
	_grabuge_label.text = "Grabuge: %d%%" % round(value)
