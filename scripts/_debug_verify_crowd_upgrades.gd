extends SceneTree

## Verifies crowd upgrades reach BOTH already-living NPCs (retro-apply) and
## NPCs spawned after the purchase. The latter is the one that matters most:
## scripts/npc_spawner.gd trickles in civilians for the whole run, so a
## purchase that only loops over living NPCs would silently dilute as the
## crowd churns -- see agents/wave-survival-notes.md.
##
## Run: godot --path . --headless --script res://scripts/_debug_verify_crowd_upgrades.gd

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

	var um: Node = root.get_node("UpgradeManager")
	var gs: Node = root.get_node("GameState")
	var spawner: Node = root.get_node_or_null("TestMap/NPCSpawner")
	var crowd: Node = get_first_node_in_group(&"crowd_controller")

	match _phase:
		0:
			if spawner == null or spawner.spawned_npcs.is_empty():
				return false
			gs.add_grabuge(2000.0)
			var existing: Node = spawner.spawned_npcs[0]
			var h: Node = existing.get_node("HealthComponent")
			print("=== existing NPC baseline ===")
			print("move_speed: ", existing.move_speed)
			print("damage_per_second: ", existing.damage_per_second)
			print("health max/current: ", h.max_health, "/", h.current_health)
			print("crowd_controller.attack_damage_per_second: ",
					crowd.attack_damage_per_second if crowd else "n/a")

			print("\n=== buy all three crowd upgrades ===")
			print("crowd_speed: ", um.purchase(&"crowd_speed"))
			print("crowd_health: ", um.purchase(&"crowd_health"))
			print("crowd_damage: ", um.purchase(&"crowd_damage"))

			print("\n=== existing NPC retro-applied ===")
			print("move_speed: ", existing.move_speed, "  (expect 4.4 from 4.0 +10%)")
			print("damage_per_second: ", existing.damage_per_second, "  (expect 5.75 from 5.0 +15%)")
			print("health max/current: ", h.max_health, "/", h.current_health,
					"  (expect max 30 from 25 +20%)")
			print("crowd_controller.attack_damage_per_second: ",
					crowd.attack_damage_per_second, "  (expect 1.15 from 1.0 +15%)")
			_phase = 1
		1:
			# Spawn a brand-new NPC the way the trickle spawner does, AFTER
			# the purchases, and confirm it arrives already upgraded.
			var fresh: Node = load("res://scenes/npc.tscn").instantiate()
			spawner.add_child(fresh)
			var fh: Node = fresh.get_node("HealthComponent")
			print("\n=== NPC spawned AFTER the purchases ===")
			print("move_speed: ", fresh.move_speed, "  (must be 4.4, not 4.0)")
			print("damage_per_second: ", fresh.damage_per_second, "  (must be 5.75, not 5.0)")
			print("health max: ", fh.max_health, "  (must be 30, not 25)")

			print("\n=== repeat crowd_speed must not compound ===")
			print("purchase again: ", um.purchase(&"crowd_speed"))
			print("existing NPC move_speed: ", spawner.spawned_npcs[0].move_speed,
					"  (expect 4.8 = 4.0*(1+0.1*2), NOT 4.84)")
			_phase = 2
		2:
			print("\n--- DONE ---")
			return true

	return false
