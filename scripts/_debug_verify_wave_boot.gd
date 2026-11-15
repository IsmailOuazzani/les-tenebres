extends SceneTree

## Verifies the autoload-ready-vs-scene-ready ordering hazard flagged in
## CLAUDE.md: WaveManager is an autoload, so its _ready() runs BEFORE the
## main scene (and therefore before PoliceSpawner joins the
## `&"police_spawner"` group). If _start_wave() runs at that moment, the
## group lookup silently no-ops and wave 1 spawns zero police.
##
## Uses the MainLoop _process() hook (not just _initialize()) so real frames
## actually tick -- _initialize() runs before the first idle frame, so
## autoload _ready() has not fired yet at that point and inspecting there
## reports nothing useful.
##
## Run: godot --path . --headless --script res://scripts/_debug_verify_wave_boot.gd

var _elapsed: float = 0.0
var _reported_boot: bool = false


func _initialize() -> void:
	var map: Node = load("res://scenes/test_map.tscn").instantiate()
	root.add_child(map)


func _process(delta: float) -> bool:
	_elapsed += delta

	var wm: Node = root.get_node_or_null("WaveManager")
	var spawner: Node = get_first_node_in_group(&"police_spawner")

	if not _reported_boot:
		_reported_boot = true
		print("--- first idle frame (autoload _ready has now run) ---")
		print("WaveManager state: ", wm.state, "  (0=PREPARING 1=ACTIVE 2=INTERMISSION 3=ACT_COMPLETE)")
		print("wave_time_left: ", wm.wave_time_left, "  wave_duration: ", wm.wave_duration)
		print("police_spawner in group: ", spawner != null)
		if spawner != null:
			print("spawner._spawning: ", spawner._spawning)
			print("spawner._police_remaining_to_spawn: ", spawner._police_remaining_to_spawn)

	if _elapsed >= 8.0:
		print("--- after %.1fs of wave 1 ---" % _elapsed)
		print("WaveManager state: ", wm.state, "  wave_time_left: ", wm.wave_time_left)
		if spawner != null:
			print("spawner._spawning: ", spawner._spawning)
			print("spawner._police_remaining_to_spawn: ", spawner._police_remaining_to_spawn)
			print("spawner.spawned_police.size(): ", spawner.spawned_police.size())
		print("live cops in &\"police\" group: ", get_nodes_in_group(&"police").size())
		return true

	return false
