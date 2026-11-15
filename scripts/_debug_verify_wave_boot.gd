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

var _booted: bool = false


## Headless harnesses add the match scene by hand instead of going through
## the main menu, so single-player mode has to be set up explicitly: every
## server-authoritative system checks NetworkManager.is_authoritative(),
## which is false in the menu-default Mode.NONE -- nothing would spawn or
## simulate. `Node.multiplayer` is null during _initialize() (see
## agents/multiplayer-notes.md gotcha 1), so this runs on the first idle
## frame instead.
func _boot() -> void:
	root.get_node("NetworkManager").begin_single_player_session()
	root.add_child(load("res://scenes/test_map.tscn").instantiate())


func _process(delta: float) -> bool:
	if not _booted:
		_booted = true
		_boot()
		return false

	_elapsed += delta

	var wm: Node = root.get_node_or_null("WaveManager")
	var spawner: Node = get_first_node_in_group(&"police_spawner")

	if not _reported_boot:
		_reported_boot = true
		print("--- first idle frame (autoload _ready has now run) ---")
		print("WaveManager state: ", wm.state, "  (0=PREPARING 1=ACTIVE 2=INTERMISSION 3=ACT_COMPLETE)")
		print("police_remaining: ", wm.police_remaining)
		print("police_spawner in group: ", spawner != null)
		if spawner != null:
			print("spawner._spawning: ", spawner._spawning)
			print("spawner._police_remaining_to_spawn: ", spawner._police_remaining_to_spawn)

	if _elapsed >= 8.0:
		print("--- after %.1fs of wave 1 ---" % _elapsed)
		print("WaveManager state: ", wm.state, "  police_remaining: ", wm.police_remaining)
		if spawner != null:
			print("spawner._spawning: ", spawner._spawning)
			print("spawner._police_remaining_to_spawn: ", spawner._police_remaining_to_spawn)
			print("spawner.spawned_police.size(): ", spawner.spawned_police.size())
		print("live cops in &\"police\" group: ", get_nodes_in_group(&"police").size())
		return true

	return false
