extends SceneTree

## Debug: real headless client for the loopback replication test.
##
##   Godot --headless --script res://scripts/_debug_net_client.gd
##
## Pair with scripts/_debug_net_host.gd (see `task test:lan`). Joins
## 127.0.0.1:7000, rides the synchronized match start, *plays* a little
## (walks into a crowd of civilians, holds the megaphone, issues a Send Mob
## order), then asserts that the authoritative world arrived over the wire:
##
##   * two player characters exist, with authority split between the host
##     (peer 1) and this peer
##   * the remote player is being interpolated toward a replicated snapshot
##   * civilians and police exist on the client *without* the client ever
##     simulating or spawning them (it is not authoritative)
##   * replicated Grabuge/crowd counters move, i.e. GameState's
##     unreliable-ordered state push is landing
##   * the shared wave loop is replicated (WaveManager's state push), and a
##     client's upgrade purchase round-trips: request to the server, shared
##     Grabuge spent there, resulting level broadcast back
##
## The server-side half of the recruitment/command assertions lives in
## _debug_net_host.gd -- between them they cover "a client can recruit into
## the one shared crowd and command it" without a window.
##
## Not part of gameplay; safe to delete.

const JOIN_DELAY_SEC: float = 1.0
const RECRUIT_AT_SEC: float = 3.0
const SEND_MOB_AT_SEC: float = 5.0
## When this client asks the server to buy a shared upgrade out of the shared
## Grabuge wallet. After the recruiting phase, so the wallet has something in
## it (the host also keeps it topped up -- see _debug_net_host.gd).
const UPGRADE_AT_SEC: float = 7.0
## Long enough to see the host kill this character (server-side) and respawn
## it 5 seconds later, both of which arrive over ServerSync.
const OBSERVE_SEC: float = 14.0

var _elapsed: float = 0.0
var _nm: Node
var _joined: bool = false
var _recruited: bool = false
var _commanded: bool = false
var _requested_upgrade: bool = false
var _done: bool = false
var _last_tick: float = 0.0
var _saw_death: bool = false
var _saw_respawn: bool = false
var _saw_live_crowd: bool = false
var _civilian_cursor: int = 0
var _failures: Array[String] = []


func _process(delta: float) -> bool:
	if _done:
		return true
	_elapsed += delta

	if not _joined and _elapsed > JOIN_DELAY_SEC:
		_joined = true
		_nm = get_root().get_node_or_null("NetworkManager")
		if _nm == null:
			print("[client] FAIL: NetworkManager autoload missing")
			_done = true
			quit(1)
			return false
		var err: int = _nm.join_lan("127.0.0.1", "Client")
		print("[client] join_lan() -> ", err)
		if err != OK:
			_done = true
			quit(1)
		return false

	if not _joined:
		return false

	# Hold the megaphone down and walk along the civilian cluster for a
	# couple of seconds, so a handful of protesters join rather than one --
	# a one-protester crowd makes every later assertion hostage to whether a
	# cop happened to kill it.
	if _elapsed > RECRUIT_AT_SEC and _elapsed < SEND_MOB_AT_SEC:
		if not _recruited:
			_recruited = true
			_start_recruiting()
		else:
			_walk_to_next_civilian()

	if not _commanded and _elapsed > SEND_MOB_AT_SEC:
		_commanded = true
		_send_mob()

	if not _requested_upgrade and _elapsed > UPGRADE_AT_SEC:
		_requested_upgrade = true
		var um: Node = get_root().get_node("UpgradeManager")
		# Returns false on a client by design -- the purchase is a request to
		# the server, and the result arrives as a broadcast level change.
		print("[client] requested player_speed upgrade (local return: ",
				um.purchase(&"player_speed"), ")")

	var game_state_node: Node = get_root().get_node_or_null("GameState")
	if game_state_node != null and game_state_node.live_crowd_count > 0:
		_saw_live_crowd = true

	if _elapsed - _last_tick > 1.0:
		_last_tick = _elapsed
		var peer: MultiplayerPeer = get_multiplayer().multiplayer_peer
		var player: Node3D = _local_player()
		# Watch the server-authoritative alive/health state arrive. The host
		# kills this character mid-run and respawns it 5 seconds later; both
		# transitions must show up here purely as replicated state.
		if player != null:
			if not player.net_alive:
				_saw_death = true
			elif _saw_death:
				_saw_respawn = true
		print("[client] t=%.1f status=%s scene=%s alive=%s health=%.0f" % [
			_elapsed,
			str(peer.get_connection_status()) if peer != null else "<no peer>",
			current_scene.name if current_scene != null else "<null>",
			str(player.net_alive) if player != null else "n/a",
			player.net_health if player != null else -1.0,
		])

	if _elapsed > OBSERVE_SEC:
		_report()
	return false


func _local_player() -> Node3D:
	var map: Node = current_scene
	if map == null or map.name != "TestMap":
		return null
	return map.get_node_or_null("Players/%d" % _nm.get_local_peer_id())


## Walks this client's character onto a cluster of civilians and holds the
## megaphone's recruit input. Both halves go through the real gameplay path:
## position is client-authoritative (so moving it here is exactly what WASD
## would do), and the recruit input is pushed as a genuine InputEventAction
## so Megaphone's `_unhandled_input` handles it.
func _start_recruiting() -> void:
	var player: Node3D = _local_player()
	if player == null:
		print("[client] cannot recruit: no local player yet")
		return
	var map: Node = current_scene
	var civilians: Array = map.get_node("NPCSpawner").get_children()
	if civilians.is_empty():
		print("[client] cannot recruit: no civilians replicated yet")
		return

	# Stand on top of the first replicated civilian so several fall inside
	# the megaphone's 2 m recruitment circle.
	var target: Node3D = civilians[0]
	player.global_position = target.global_position + Vector3(0.0, 1.0, 0.0)
	print("[client] moved to %s to recruit" % str(player.global_position.round()))

	var event := InputEventAction.new()
	event.action = &"recruit"
	event.pressed = true
	Input.parse_input_event(event)


## Keeps the recruit input held (never released) while hopping to the next
## replicated civilian, sweeping the megaphone circle across the cluster.
func _walk_to_next_civilian() -> void:
	var player: Node3D = _local_player()
	var map: Node = current_scene
	if player == null or map == null:
		return
	var civilians: Array = map.get_node("NPCSpawner").get_children()
	if civilians.is_empty():
		return
	_civilian_cursor += 1
	var target: Node3D = civilians[_civilian_cursor % civilians.size()]
	player.global_position = target.global_position + Vector3(0.0, 1.0, 0.0)


## Issues an "À L'ATTAQUE!" order through the same handler the megaphone's
## `send_mob_triggered` signal calls, which on a client forwards it to the
## server's CrowdController via RPC.
func _send_mob() -> void:
	var player: Node3D = _local_player()
	if player == null:
		return
	var destination: Vector3 = player.global_position + Vector3(8.0, 0.0, 0.0)
	# Half the crowd, so the rest stays in FOLLOW -- charging protesters pick
	# fights with police and a 100% send can wipe the whole crowd before the
	# later phases run.
	player._on_send_mob_triggered(0.5, null, destination)
	print("[client] sent 50%% of the crowd to ", str(destination.round()))


func _report() -> void:
	_done = true
	var map: Node = current_scene
	print("[client] current scene: ", map.name if map != null else "<null>")
	_expect(map != null and map.name == "TestMap", "client loaded the match scene")
	if map == null or map.name != "TestMap":
		_finish()
		return

	var my_id: int = _nm.get_local_peer_id()
	print("[client] peer id=", my_id, " is_client=", _nm.is_client(),
			" is_authoritative=", _nm.is_authoritative())
	_expect(_nm.is_client(), "client reports CLIENT mode")
	_expect(not _nm.is_authoritative(), "client is NOT authoritative")

	var players_root: Node = map.get_node_or_null("Players")
	_expect(players_root != null, "Players container exists on the client")
	if players_root == null:
		_finish()
		return

	var names: Array[String] = []
	for child in players_root.get_children():
		names.append(String(child.name))
		print("[client] player %s authority=%d local_owner=%s pos=%s net_position=%s" % [
			child.name, child.get_multiplayer_authority(),
			str(child.is_multiplayer_authority()),
			str(child.global_position.round()), str(child.net_position.round())
		])
	_expect(players_root.get_child_count() == 2,
			"both player characters replicated to the client (got %d: %s)" % [
				players_root.get_child_count(), ", ".join(names)
			])

	var local_player: Node = players_root.get_node_or_null(str(my_id))
	_expect(local_player != null, "client owns Players/%d" % my_id)
	if local_player != null:
		_expect(local_player.is_multiplayer_authority(),
				"client has authority over its own character")
		var cam: Camera3D = local_player.get_node_or_null("Head/Camera")
		_expect(cam != null and cam.current, "client's own camera is current")
		_expect(local_player.net_recruiting,
				"client's recruit-held flag is set for the server to poll")
		_expect(_saw_death, "server-side death replicated to the owning client")
		_expect(_saw_respawn, "server-side respawn replicated to the owning client")
		_expect(local_player.net_alive, "client is alive again after respawning")
		var local_health: Node = local_player.get_node("HealthComponent")
		print("[client] local HealthComponent current=%.2f max=%.2f dead=%s net_health=%.2f" % [
			local_health.current_health, local_health.max_health,
			str(local_health.is_dead()), local_player.net_health
		])
		# The invariant is "the local HealthComponent tracks the replicated
		# value", NOT "health is full": police keep attacking the respawned
		# player, so asserting full health here is a flaky test, not a
		# stronger one.
		_expect(is_equal_approx(local_health.current_health, local_player.net_health),
				"client's local HealthComponent mirrors the replicated health")
		_expect(local_health.current_health > 0.0 and not local_health.is_dead(),
				"respawned client is back in play")
		_expect(current_scene.get_node("GameOver").visible == false,
				"a player death did not trigger the game-over screen (spec 4.4)")

	var remote_player: Node = players_root.get_node_or_null("1")
	_expect(remote_player != null, "host's character (Players/1) replicated")
	if remote_player != null:
		_expect(not remote_player.is_multiplayer_authority(),
				"client does NOT own the host's character")
		_expect(remote_player.net_position.length() > 0.01,
				"host's snapshot arrived (net_position=%s)" % str(remote_player.net_position))
		_expect(remote_player.global_position.distance_to(remote_player.net_position) < 1.0,
				"remote player interpolated onto its snapshot")
		var remote_cam: Camera3D = remote_player.get_node_or_null("Head/Camera")
		_expect(remote_cam != null and not remote_cam.current,
				"remote player's camera is inactive on this peer")
		# A remote player's third-person body is deliberately hidden while
		# they are down waiting to respawn, so only assert visibility when
		# the replicated alive flag says they are in play.
		var body: Node3D = remote_player.get_node_or_null("Body")
		_expect(body != null, "remote player has a third-person body node")
		if body != null and remote_player.net_alive:
			_expect(body.visible, "living remote player's 3D body is visible")
		else:
			print("[client] host is currently down; body hidden as expected")

	var npc_root: Node = map.get_node("NPCSpawner")
	var npc_count: int = npc_root.get_child_count()
	print("[client] civilians replicated: ", npc_count)
	_expect(npc_count > 0, "civilians replicated to the client")
	if npc_count > 0:
		var sample: Node = npc_root.get_child(0)
		print("[client] sample civilian %s variant=%d pos=%s net_position=%s anim=%d" % [
			sample.name, sample.variant_index,
			str(sample.global_position.round()), str(sample.net_position.round()),
			sample.net_anim
		])
		_expect(sample.net_position.length() > 0.01,
				"civilian transform snapshot arrived (not left at the origin)")

	# Clients must not be simulating the crowd themselves.
	var crowd: Node = map.get_node("CrowdController")
	_expect(crowd.get_recruited_count() == 0,
			"client runs no crowd simulation of its own (local recruited list empty)")

	print("[client] police replicated: ", map.get_node("PoliceSpawner").get_child_count())

	var game_state: Node = get_root().get_node_or_null("GameState")
	print("[client] grabuge=%.3f crowd_count=%d live_crowd_count=%d" % [
		game_state.grabuge_available, game_state.crowd_count, game_state.live_crowd_count
	])
	# Recruiting raises the shared score on the server; seeing it here proves
	# GameState's state push landed.
	_expect(game_state.crowd_count > 1,
			"replicated shared crowd_count reflects this client's recruiting")
	# Latched over the whole run: the live headcount can legitimately fall
	# back to zero if police kill every recruited protester, so assert that
	# a non-zero value *arrived*, not that it is still non-zero now.
	_expect(_saw_live_crowd, "replicated live crowd headcount arrived")
	_expect(game_state.grabuge_available > 0.0, "replicated shared Grabuge arrived")

	var wave_manager: Node = get_root().get_node("WaveManager")
	print("[client] wave state=%d act/wave=%d/%d time_left=%.1f" % [
		wave_manager.state, wave_manager.current_act,
		wave_manager.current_wave, wave_manager.wave_time_left
	])
	# 1 == WaveManager.State.ACTIVE. The client never starts a wave itself,
	# so an ACTIVE wave with a live countdown can only have been replicated.
	_expect(wave_manager.state == 1, "replicated wave state is ACTIVE on the client")
	_expect(wave_manager.wave_time_left > 0.0 and wave_manager.wave_time_left < 45.0,
			"replicated wave countdown is running on the client")

	var upgrade_manager: Node = get_root().get_node("UpgradeManager")
	print("[client] player_speed_mult=%.2f crowd_damage_mult=%.2f" % [
		upgrade_manager.player_speed_mult, upgrade_manager.crowd_damage_mult
	])
	_expect(upgrade_manager.player_speed_mult > 1.0,
			"client's upgrade request was spent and broadcast back by the server")

	var hud: Node = map.get_node_or_null("HUD")
	_expect(hud != null and hud.is_bound(), "client HUD bound to its own player")

	_finish()


func _expect(condition: bool, label: String) -> void:
	print(("[client] [ok]   " if condition else "[client] [FAIL] ") + label)
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("[client] === OK ===")
		quit(0)
	else:
		print("[client] === %d FAILURE(S) ===" % _failures.size())
		quit(1)
