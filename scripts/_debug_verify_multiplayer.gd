extends SceneTree

## Debug: headless single-player smoke test of the multiplayer refactor.
##
##   Godot --headless --script res://scripts/_debug_verify_multiplayer.gd
##
## Verifies, in single-player mode (no peer), that:
##   * NetworkManager autoload exists and reports the right session mode
##   * the match scene loads and the player character actually spawns under
##     Players/1 with authority 1 (the CLAUDE.md "verify the live scene tree"
##     rule -- player spawning is now done by a script, not the editor)
##   * the three MultiplayerSpawners resolved their spawn_path and scene list
##   * every MultiplayerSynchronizer parsed a non-empty replication config
##     (a hand-written SceneReplicationConfig in a .tscn fails *silently*, so
##     this is checked explicitly rather than inferred from "no errors")
##   * NPCs and police spawn, and the HUD bound to the local player
##
## Not part of gameplay; safe to delete.

var _phase: int = 0
var _elapsed: float = 0.0
var _failures: Array[String] = []


func _process(delta: float) -> bool:
	_elapsed += delta
	match _phase:
		0:
			_phase = 1
			_start()
		1:
			if _elapsed > 1.0:
				_phase = 2
				_check_spawn()
		2:
			if _elapsed > 4.0:
				_phase = 3
				_check_gameplay()
				_restart()
		3:
			if _elapsed > 7.0:
				_phase = 4
				_check_restart()
				_finish()
	return false


func _start() -> void:
	print("=== single-player smoke test ===")
	var nm: Node = get_root().get_node_or_null("NetworkManager")
	_expect(nm != null, "NetworkManager autoload present")
	if nm == null:
		quit(1)
		return
	_expect(not nm.is_authoritative(), "nothing simulates before a session starts")
	nm.start_single_player()
	_expect(nm.is_authoritative(), "single-player is authoritative")
	_expect(not nm.is_multiplayer_session(), "single-player is not a networked session")


func _check_spawn() -> void:
	var map: Node = current_scene
	_expect(map != null and map.name == "TestMap", "match scene loaded (got %s)" % [
		map.name if map != null else "<null>"
	])
	if map == null:
		return

	print("--- runtime scene tree (top two levels) ---")
	for child in map.get_children():
		print("  ", child.name, " [", child.get_class(), "]")
		for grandchild in child.get_children():
			print("      ", grandchild.name, " [", grandchild.get_class(), "]")

	var players_root: Node = map.get_node_or_null("Players")
	_expect(players_root != null, "Players container exists")
	var player: Node = map.get_node_or_null("Players/1")
	_expect(player != null, "local player spawned at Players/1")
	if player != null:
		_expect(player.get_multiplayer_authority() == 1, "player authority is peer 1")
		_expect(player.is_multiplayer_authority(), "player is locally owned")
		for required in ["Head/Camera", "Head/Camera/Megaphone", "Head/Camera/Croissant",
				"Head/Camera/WeaponSwitcher", "HealthComponent", "Body/Character",
				"InputSync", "ServerSync", "Collision"]:
			_expect(player.get_node_or_null(required) != null,
					"player has %s" % required)
		var cam: Camera3D = player.get_node_or_null("Head/Camera")
		if cam != null:
			_expect(cam.current, "local player camera is current")
		var server_sync: Node = player.get_node_or_null("ServerSync")
		if server_sync != null:
			_expect(server_sync.get_multiplayer_authority() == 1,
					"ServerSync authority pinned to the server")

	# Spawners
	for spawner_info in [
		["PlayerSpawner", "Players"],
		["NPCReplicator", "NPCSpawner"],
		["PoliceReplicator", "PoliceSpawner"],
	]:
		var spawner: MultiplayerSpawner = map.get_node_or_null(String(spawner_info[0]))
		_expect(spawner != null, "%s exists" % spawner_info[0])
		if spawner == null:
			continue
		_expect(spawner.get_node_or_null(spawner.spawn_path) != null,
				"%s spawn_path resolves to %s" % [spawner_info[0], spawner_info[1]])
		_expect(spawner.get_spawnable_scene_count() > 0,
				"%s has a spawnable scene registered" % spawner_info[0])

	_check_replication_configs(map)


## A hand-written SceneReplicationConfig that Godot failed to parse comes out
## as an empty config and replicates nothing -- with no error. So assert the
## property lists are actually populated.
func _check_replication_configs(root: Node) -> void:
	var synchronizers: Array[Node] = []
	_collect(root, synchronizers)
	_expect(not synchronizers.is_empty(), "found MultiplayerSynchronizers in the live tree")
	for sync in synchronizers:
		var config: SceneReplicationConfig = sync.replication_config
		var path: String = String(root.get_path_to(sync))
		_expect(config != null, "%s has a replication_config" % path)
		if config == null:
			continue
		var props: Array = config.get_properties()
		_expect(not props.is_empty(), "%s replicates %d properties" % [path, props.size()])
		var modes: Array[String] = []
		for prop in props:
			modes.append("%s=%d" % [String(prop), config.property_get_replication_mode(prop)])
		print("    ", path, " -> ", ", ".join(modes))


func _collect(node: Node, out: Array[Node]) -> void:
	if node is MultiplayerSynchronizer:
		out.append(node)
	for child in node.get_children():
		_collect(child, out)


func _check_gameplay() -> void:
	var map: Node = current_scene
	if map == null:
		return
	var npc_spawner: Node = map.get_node_or_null("NPCSpawner")
	_expect(npc_spawner != null and npc_spawner.get_child_count() > 0,
			"civilians spawned (%d)" % [npc_spawner.get_child_count() if npc_spawner else -1])
	var hud: Node = map.get_node_or_null("HUD")
	_expect(hud != null and hud.is_bound(), "HUD bound to the local player")
	var crowd: Node = map.get_node_or_null("CrowdController")
	_expect(crowd != null, "CrowdController present")
	# Autoload globals aren't available as compile-time identifiers inside a
	# `--script` SceneTree, so fetch by node path.
	var game_state: Node = get_root().get_node_or_null("GameState")
	if game_state != null:
		print("    Grabuge available=%.2f earned=%.2f crowd_count=%d live=%d" % [
			game_state.grabuge_available,
			game_state.grabuge_total_earned,
			game_state.crowd_count,
			game_state.live_crowd_count,
		])


## Exercises the single-player game-over restart path, which is still
## `GameState.reset()` + `reload_current_scene()` -- unchanged behavior, but
## now the player is spawned by a script instead of being baked into the
## scene, so a reload has to re-run the whole spawn handshake.
func _restart() -> void:
	print("--- restarting the match (single-player game-over path) ---")
	var game_state: Node = get_root().get_node_or_null("GameState")
	game_state.reset()
	reload_current_scene()


func _check_restart() -> void:
	var map: Node = current_scene
	_expect(map != null and map.name == "TestMap", "match scene reloaded")
	if map == null:
		return
	var player: Node = map.get_node_or_null("Players/1")
	_expect(player != null, "player re-spawned after a restart")
	_expect(map.get_node("NPCSpawner").get_child_count() > 0,
			"civilians re-spawned after a restart")
	var hud: Node = map.get_node_or_null("HUD")
	_expect(hud != null and hud.is_bound(), "HUD re-bound after a restart")
	var game_state: Node = get_root().get_node_or_null("GameState")
	_expect(game_state.crowd_count >= 1, "GameState reset cleanly (crowd_count=%d)" % game_state.crowd_count)


func _expect(condition: bool, label: String) -> void:
	print(("  [ok]   " if condition else "  [FAIL] ") + label)
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("=== ALL CHECKS PASSED ===")
		quit(0)
	else:
		print("=== %d FAILURE(S) ===" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		quit(1)
