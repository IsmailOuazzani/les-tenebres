extends SceneTree

## Verifies the player-stat upgrades actually survive, with emphasis on the
## addons/fps_controller/Sprint.gd hazard: Sprint._physics_process() writes
## `controller.speed = normal_speed` EVERY frame it isn't sprinting, so an
## upgrade that sets only MovementController.speed is erased within one
## physics frame. MovementController is the Player node itself (Sprint's
## controller_path is "../").
##
## Run: godot --path . --headless --script res://scripts/_debug_verify_player_upgrades.gd

var _phase: int = 0
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
	if _elapsed > 30.0:
		print("!!! ABORT: stalled in phase ", _phase)
		return true

	var player: Node = root.get_node_or_null("TestMap/Players/1")
	var sprint: Node = root.get_node_or_null("TestMap/Players/1/Sprint")
	var health: Node = root.get_node_or_null("TestMap/Players/1/HealthComponent")
	var um: Node = root.get_node("UpgradeManager")
	var gs: Node = root.get_node("GameState")

	match _phase:
		0:
			gs.add_grabuge(2000.0)
			print("=== baseline ===")
			print("player.speed: ", player.speed)
			print("player.jump_height: ", player.jump_height)
			print("sprint.normal_speed: ", sprint.normal_speed)
			print("sprint.sprint_speed: ", sprint.sprint_speed)
			print("health max/current: ", health.max_health, "/", health.current_health)

			print("\n=== buy player_speed, player_jump, player_health ===")
			print("purchase(player_speed): ", um.purchase(&"player_speed"))
			print("purchase(player_jump): ", um.purchase(&"player_jump"))
			# Take damage first so the +20 heal is observable.
			health.take_damage(50.0)
			print("health after 50 damage: ", health.current_health)
			print("purchase(player_health): ", um.purchase(&"player_health"))

			print("immediately after purchase:")
			print("  player.speed: ", player.speed, "  (expect ~11 from 10 +10%)")
			print("  player.jump_height: ", player.jump_height, "  (expect ~11.5 from 10 +15%)")
			print("  sprint.normal_speed: ", sprint.normal_speed, "  (MUST track player.speed)")
			print("  sprint.sprint_speed: ", sprint.sprint_speed, "  (expect ~17.6 from 16 +10%)")
			print("  health max/current: ", health.max_health, "/", health.current_health,
					"  (expect max 120, current 70)")
			_phase = 1
		1:
			# Let real physics frames run -- this is where a missed
			# normal_speed would silently revert the speed upgrade.
			if _elapsed > 2.0:
				print("\n=== after ~2s of real physics frames (Sprint has run many times) ===")
				print("player.speed: ", player.speed, "  <-- reverted to 10 means the Sprint bug is live")
				print("sprint.normal_speed: ", sprint.normal_speed)

				print("\n=== repeat purchase must not compound ===")
				print("purchase(player_speed) again: ", um.purchase(&"player_speed"))
				print("player.speed: ", player.speed, "  (expect 12 = 10*(1+0.1*2), NOT 12.1)")

				print("\n=== insufficient funds ===")
				gs.grabuge_available = 0.0
				var speed_before = player.speed
				print("purchase with 0 grabuge: ", um.purchase(&"player_speed"))
				print("speed unchanged: ", player.speed == speed_before, " (", player.speed, ")")

				print("\n=== reset ===")
				um.reset()
				print("after reset -> speed_mult: ", um.player_speed_mult,
						"  crowd_damage_mult: ", um.crowd_damage_mult)
				_phase = 2
		2:
			print("\n--- DONE ---")
			return true

	return false
