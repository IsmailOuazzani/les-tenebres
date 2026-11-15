extends SceneTree

## Debug: real headless listen server for the loopback replication test.
##
##   Godot --headless --script res://scripts/_debug_net_host.gd
##
## Pair with scripts/_debug_net_client.gd (see `task test:lan`). Hosts on
## 127.0.0.1:7000, waits for one client to register, starts the match, then
## checks -- against the live scene tree -- that:
##
##   phase WORLD    both player characters spawned with the right authority,
##                  and civilians/police are being simulated
##   phase COMMANDS the *client's* recruitment and Send Mob command actually
##                  reached the server's shared crowd (spec 4.2 / 4.3)
##   phase CLEANUP  the client's character was despawned when it quit, while
##                  the protesters it recruited stayed in the shared crowd
##                  (spec 3)
##
## This exercises the genuine ENetMultiplayerPeer path -- peer connection,
## the synchronized-load handshake, MultiplayerSpawner spawn packets,
## MultiplayerSynchronizer state and client->server command RPCs -- rather
## than faking peer signals.
##
## Not part of gameplay; safe to delete.

const WAIT_FOR_CLIENT_SEC: float = 15.0
## Seconds after match start at which each phase runs. The client acts
## between +1s and +4s (see _debug_net_client.gd) and quits around +6s.
const WORLD_CHECK_AT: float = 2.0
const COMMAND_CHECK_AT: float = 5.0
const DOWN_CHECK_AT: float = 7.0
const RESPAWN_CHECK_AT: float = 12.0
const CLEANUP_CHECK_AT: float = 18.0

var _elapsed: float = 0.0
var _nm: Node
var _hosting: bool = false
var _match_started_at: float = -1.0
var _phase: int = 0
var _done: bool = false
var _failures: Array[String] = []
## Headcount recorded during the COMMANDS phase, so CLEANUP can prove the
## departed client's protesters were preserved rather than dispersed.
var _recruited_before_disconnect: int = 0


## NOTE: hosting is started from the first `_process` frame, not
## `_initialize()`. At `_initialize()` time the SceneTree has not built its
## MultiplayerAPI yet, so `Node.multiplayer` is still null and assigning the
## peer silently fails -- the symptom is a client stuck in
## CONNECTION_CONNECTING forever.
func _process(delta: float) -> bool:
	if _done:
		return true
	_elapsed += delta

	if not _hosting:
		_hosting = true
		_nm = get_root().get_node_or_null("NetworkManager")
		if _nm == null:
			print("[host] FAIL: NetworkManager autoload missing")
			_done = true
			quit(1)
			return false
		var err: int = _nm.host_lan("Host")
		print("[host] host_lan() -> ", err)
		if err != OK:
			_done = true
			quit(1)
		return false

	if _match_started_at < 0.0:
		# players always contains peer 1 (the host), so >1 means a client
		# finished registering.
		if _nm.players.size() > 1:
			print("[host] peers registered: ", _nm.players.keys())
			_match_started_at = _elapsed
			_nm.start_match()
		elif _elapsed > WAIT_FOR_CLIENT_SEC:
			print("[host] FAIL: no client connected within %.0fs" % WAIT_FOR_CLIENT_SEC)
			_failures.append("no client connected")
			_finish()
		return false

	_keep_grabuge_up()

	var since_start: float = _elapsed - _match_started_at
	if _phase == 0 and since_start > WORLD_CHECK_AT:
		_phase = 1
		_check_world()
	elif _phase == 1 and since_start > COMMAND_CHECK_AT:
		_phase = 2
		_check_commands()
		_kill_client_player()
	elif _phase == 2 and since_start > DOWN_CHECK_AT:
		_phase = 3
		_check_down()
	elif _phase == 3 and since_start > RESPAWN_CHECK_AT:
		_phase = 4
		_check_respawn()
	elif _phase == 4 and since_start > CLEANUP_CHECK_AT:
		_phase = 5
		_check_cleanup()
		_finish()
	return false


func _map() -> Node:
	return current_scene


## Keeps the shared Grabuge wallet funded for the duration of the test, so
## the client's "replicated shared Grabuge arrived" assertion has something
## to see regardless of how much the harness's one recruit earns. Grabuge no
## longer decays (it is the run's currency now, see scripts/game_state.gd),
## so this is only about having a non-trivial number to replicate.
func _keep_grabuge_up() -> void:
	var game_state: Node = get_root().get_node_or_null("GameState")
	if game_state != null and game_state.grabuge_available < 50.0:
		game_state.add_grabuge(50.0)


func _check_world() -> void:
	print("[host] --- phase WORLD ---")
	var map: Node = _map()
	_expect(map != null and map.name == "TestMap", "match scene loaded on the host")
	if map == null or map.name != "TestMap":
		_finish()
		return

	_expect(_nm.is_authoritative(), "host is authoritative")
	_expect(_nm.is_host(), "host reports HOST mode")

	var players_root: Node = map.get_node("Players")
	for child in players_root.get_children():
		print("[host] player %s authority=%d pos=%s" % [
			child.name, child.get_multiplayer_authority(), str(child.global_position.round())
		])
	_expect(players_root.get_child_count() == _nm.players.size(),
			"one character per connected peer (%d chars / %d peers)" % [
				players_root.get_child_count(), _nm.players.size()
			])

	var npc_count: int = map.get_node("NPCSpawner").get_child_count()
	print("[host] civilians=%d police=%d" % [
		npc_count, map.get_node("PoliceSpawner").get_child_count()
	])
	_expect(npc_count > 0, "civilians simulated on the host")

	# A full wave (8 cops in wave 1, see scripts/wave_manager.gd) wipes the
	# small test crowd before the later phases can observe it. Replace the
	# wave's spawn order with a two-cop one, so police replication is still
	# covered without the test's assertions depending on combat outcomes.
	# The wave loop itself is deliberately left running (wave 1 lasts 45s,
	# far longer than this test, so it never issues a second order) -- the
	# client asserts that its ACTIVE state and countdown replicated.
	var police_spawner: Node = map.get_node("PoliceSpawner")
	police_spawner.stop_spawning()
	police_spawner.clear_all_police()
	police_spawner.begin_wave(2, 2.0)


func _check_commands() -> void:
	print("[host] --- phase COMMANDS ---")
	var map: Node = _map()
	if map == null:
		return
	var crowd: Node = map.get_node("CrowdController")
	var game_state: Node = get_root().get_node_or_null("GameState")

	_recruited_before_disconnect = crowd.get_recruited_count()
	print("[host] recruited=%d crowd_count=%d live=%d grabuge=%.2f" % [
		_recruited_before_disconnect, game_state.crowd_count,
		game_state.live_crowd_count, game_state.grabuge_available
	])
	# The *client* did the recruiting -- the host never held its own
	# megaphone -- so a non-zero crowd proves a remote player's replicated
	# recruit flag drove the server's shared-crowd recruitment.
	_expect(_recruited_before_disconnect > 0,
			"client's megaphone recruited into the shared crowd")
	_expect(game_state.crowd_count > 1, "shared crowd_count grew past the starting value")
	_expect(game_state.live_crowd_count == _recruited_before_disconnect,
			"GameState.live_crowd_count mirrors CrowdController")

	# The client also issued a Send Mob command; charging protesters are the
	# observable result of request_send_mob() landing on the server.
	var charging: int = 0
	for npc in map.get_node("NPCSpawner").get_children():
		if npc.state == 3:  # NPC.State.CHARGE
			charging += 1
	print("[host] protesters in CHARGE state: ", charging)
	_expect(charging > 0, "client's Send Mob command put protesters into CHARGE")


## Applies lethal damage to the client's character through the normal
## server-side HealthComponent path, which is what a cop's attack does. Spec
## 4.4: this must take the player out for 5 seconds and respawn them, and
## must NOT end the protest.
func _kill_client_player() -> void:
	var client_player: Node3D = _client_player()
	if client_player == null:
		_failures.append("no client character to damage")
		return
	print("[host] killing the client's character to exercise respawn")
	client_player.get_node("HealthComponent").take_damage(10000.0)


func _client_player() -> Node3D:
	var map: Node = _map()
	if map == null:
		return null
	for child in map.get_node("Players").get_children():
		if String(child.name) != "1":
			return child
	return null


func _check_down() -> void:
	print("[host] --- phase DOWN ---")
	var client_player: Node3D = _client_player()
	_expect(client_player != null, "client character still present while down")
	if client_player == null:
		return
	print("[host] client alive=%s respawning=%s" % [
		str(client_player.is_alive()), str(client_player.is_respawning())
	])
	_expect(not client_player.is_alive(), "killed player is marked down")
	_expect(client_player.is_respawning(), "respawn timer is running")
	var game_state: Node = get_root().get_node_or_null("GameState")
	# Spec 4.4: a player's death does not reset the protest.
	_expect(game_state.crowd_count > 1, "protest survived the player's death")
	_expect(_map().get_node("NPCSpawner").get_child_count() > 0,
			"civilians still simulated after a player death")


func _check_respawn() -> void:
	print("[host] --- phase RESPAWN ---")
	var client_player: Node3D = _client_player()
	_expect(client_player != null, "client character present after respawn")
	if client_player == null:
		return
	var health: Node = client_player.get_node("HealthComponent")
	print("[host] client alive=%s health=%.1f pos=%s" % [
		str(client_player.is_alive()), health.current_health,
		str(client_player.global_position.round())
	])
	_expect(client_player.is_alive(), "player respawned after the 5s delay")
	_expect(not health.is_dead(), "respawned player's HealthComponent was revived")
	# Not "full health": police keep attacking after the respawn, so the
	# invariant is that the death latch cleared and the player is damageable
	# again, not an exact number.
	_expect(health.current_health > 0.0, "respawned player has health again")
	_expect(not client_player.is_respawning(), "respawn timer cleared")


func _check_cleanup() -> void:
	print("[host] --- phase CLEANUP ---")
	var map: Node = _map()
	if map == null:
		return
	var players_root: Node = map.get_node("Players")
	var names: Array[String] = []
	for child in players_root.get_children():
		names.append(String(child.name))
	print("[host] remaining peers=%s remaining characters=%s" % [
		str(_nm.players.keys()), ", ".join(names)
	])
	_expect(_nm.players.size() == 1, "peer registry pruned after the client quit")
	_expect(players_root.get_child_count() == 1,
			"disconnected client's character despawned")
	_expect(names.has("1"), "host's own character survived")

	var crowd: Node = map.get_node("CrowdController")
	var after: int = crowd.get_recruited_count()
	print("[host] recruited before disconnect=%d after=%d" % [
		_recruited_before_disconnect, after
	])
	# Spec 3: a disconnect must not dis-recruit the departed player's
	# protesters. A handful can still die to police in the meantime, so the
	# assertion is "the crowd was not wiped", not an exact match.
	_expect(after > 0 and after * 2 >= _recruited_before_disconnect,
			"recruited protesters preserved after their recruiter left")


func _expect(condition: bool, label: String) -> void:
	print(("[host] [ok]   " if condition else "[host] [FAIL] ") + label)
	if not condition:
		_failures.append(label)


func _finish() -> void:
	_done = true
	if _failures.is_empty():
		print("[host] === OK ===")
		quit(0)
	else:
		print("[host] === %d FAILURE(S) ===" % _failures.size())
		quit(1)
