extends SceneTree

## End-to-end integration check for the wave-survival loop: boots the real
## test_map, drives wave 1 to completion, confirms the upgrade station opens
## and pauses, buys an upgrade, hands back via the Continue path, and
## confirms wave 2 actually starts and spawns police.
##
## Exists because the individual systems were built independently (see
## agents/wave-survival-notes.md) and each was verified in isolation -- this
## is the only check that the *handoff* between them works on the real boot
## path, which is where the first-wave spawn bug hid.
##
## Run: godot --path . --headless --script res://scripts/_debug_verify_wave_loop.gd

var _phase: int = 0
var _wm: Node
var _spawner: Node
var _screen: Node
## Wall-clock guard so a stalled phase aborts loudly instead of hanging the
## run forever (a paused tree stops WaveManager from advancing at all).
var _elapsed: float = 0.0

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
	if _elapsed > 60.0:
		print("\n!!! ABORT: stalled in phase ", _phase, " after 60s (tree paused: ", paused, ")")
		return true

	if _wm == null:
		_wm = root.get_node_or_null("WaveManager")
		_spawner = get_first_node_in_group(&"police_spawner")
		_screen = root.get_node_or_null("TestMap/UpgradeScreen")
		print("UpgradeScreen node present: ", _screen != null)
		print("UpgradeScreen process_mode (3=ALWAYS): ", _screen.process_mode if _screen else "n/a")

	match _phase:
		0:
			# Let wave 1 run a moment, then confirm it is really spawning.
			if _wm.wave_time_left < _wm.wave_duration - 5.0:
				print("\n--- wave 1 active ---")
				print("state: ", _wm.state, "  cops alive: ", get_nodes_in_group(&"police").size())
				print("spawner._spawning: ", _spawner._spawning)
				# Give the player money to shop with.
				GameStateRef().add_grabuge(500.0)
				# Skip to the end of the wave instead of waiting 45s.
				_wm.wave_time_left = 0.05
				_phase = 1
		1:
			if _wm.state == 2:  # INTERMISSION
				print("\n--- wave 1 completed -> intermission ---")
				print("tree paused (shop should pause it): ", paused)
				print("screen visible: ", _screen.visible if _screen else "n/a")
				print("cops cleared on transition: ", get_nodes_in_group(&"police").size())
				print("next wave preview: ", _wm.get_next_wave_preview())
				_phase = 2
		2:
			print("\n--- buying upgrades from the shop ---")
			var mc: Node = root.get_node_or_null("TestMap/Players/1")
			var before_speed = mc.speed if mc else null
			print("available grabuge: ", GameStateRef().grabuge_available)
			print("player speed before: ", before_speed)
			print("purchase(player_speed): ", UpgradeManagerRef().purchase(&"player_speed"))
			print("purchase(crowd_damage): ", UpgradeManagerRef().purchase(&"crowd_damage"))
			print("player speed after: ", mc.speed if mc else null)
			print("crowd_damage_mult: ", UpgradeManagerRef().crowd_damage_mult)
			print("grabuge after spend: ", GameStateRef().grabuge_available)
			print("total earned (must be unchanged by spending): ", GameStateRef().grabuge_total_earned)
			# Leave the shop the way the Continue button does -- close() is
			# what unpauses AND calls begin_intermission_countdown(), so
			# calling the WaveManager method directly would leave the tree
			# paused forever and hang this script.
			_screen.close()
			print("unpaused after continue: ", not paused)
			print("screen hidden after continue: ", not _screen.visible)
			print("intermission counting: ", _wm._intermission_counting)
			_wm.wave_time_left = 0.05
			_phase = 3
		3:
			if _wm.state == 1 and _wm.current_wave == 2:
				print("\n--- wave 2 started ---")
				print("current_act/wave: ", _wm.current_act, "/", _wm.current_wave)
				print("wave_duration: ", _wm.wave_duration)
				print("spawner._spawning: ", _spawner._spawning)
				print("police queued for wave 2: ", _spawner._police_remaining_to_spawn)
				_phase = 4
		4:
			print("\n--- DONE ---")
			return true

	return false


func GameStateRef() -> Node:
	return root.get_node("GameState")


func UpgradeManagerRef() -> Node:
	return root.get_node("UpgradeManager")
