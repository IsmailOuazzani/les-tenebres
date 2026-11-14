extends Control

## Red dots overlaid on the addons/compass CompassBar showing the bearing to
## each tracked enemy. The vendored addon only draws static bearing ticks and
## has no concept of dynamic points of interest, so this adds that on top
## rather than forking the addon. See agents/compass-hud-notes.md.
##
## Marker placement intentionally does NOT reuse the compass shader's "north"
## calibration constant (that only corrects for the bar artwork's authored
## phase). Instead it defines its own independent mapping: the direction the
## player currently faces is always screen-center, matching how the bar
## itself scrolls as "dir" (player yaw) changes, so markers track the bar
## without needing to match its internal tick alignment.

@export var compass_bar_path: NodePath
@export var player: Node3D
@export var enemy_group: StringName = &"police"
@export var marker_color: Color = Color(1.0, 0.15, 0.15)
@export var marker_size: Vector2 = Vector2(6.0, 6.0)

@onready var _compass_bar: TextureRect = get_node(compass_bar_path)

var _markers: Dictionary = {}  ## instance_id -> ColorRect


func _process(_delta: float) -> void:
	if player == null or _compass_bar == null:
		return

	var mat: ShaderMaterial = _compass_bar.material
	var dir: float = mat.get_shader_parameter("dir")
	var width: float = size.x
	var height: float = size.y

	var seen: Dictionary = {}
	for enemy in get_tree().get_nodes_in_group(enemy_group):
		if not (enemy is Node3D):
			continue

		var id: int = enemy.get_instance_id()
		seen[id] = true
		var marker: ColorRect = _markers.get(id)
		if marker == null:
			marker = ColorRect.new()
			marker.color = marker_color
			marker.size = marker_size
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(marker)
			_markers[id] = marker

		var to_enemy: Vector3 = enemy.global_position - player.global_position
		var bearing: float = atan2(-to_enemy.x, -to_enemy.z)
		var uv_x: float = fposmod(0.5 + (bearing - dir) / TAU, 1.0)
		marker.position = Vector2(
			uv_x * width - marker_size.x * 0.5, (height - marker_size.y) * 0.5
		)

	for id in _markers.keys():
		if not seen.has(id):
			_markers[id].queue_free()
			_markers.erase(id)
