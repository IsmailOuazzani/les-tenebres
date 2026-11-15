extends Node

## NetworkManager: session lifecycle, peer registry and RPC routing for LAN
## co-op. Registered as the `NetworkManager` autoload (project.godot
## `[autoload]`), so its node path is identical on every peer and it can own
## RPCs directly.
##
## Architecture (see agents/multiplayer-notes.md): **listen server** with a
## server-authoritative game simulation and client-authoritative player
## movement. The hosting player runs the authoritative server *and* a local
## client. Transport is `ENetMultiplayerPeer` over UDP on PORT.
##
## This autoload deliberately stays thin -- it owns:
##   * session lifecycle (host / join / single-player / leave)
##   * the peer/player registry shown in the lobby
##   * synchronized scene loading ("all peers loaded" handshake) before
##     players are spawned
##   * the `is_authoritative()` predicate every gameplay system branches on
##
## It owns no gameplay state. Entity replication is handled by Godot's own
## MultiplayerSpawner / MultiplayerSynchronizer nodes in the scenes, and
## gameplay commands travel as plain RPCs on the nodes that own them -- there
## is intentionally no custom networking framework layered on top.

const PORT: int = 7000
const MAX_PLAYERS: int = 4
## ENet's client cap excludes the listen server's own local client.
const MAX_CLIENTS: int = MAX_PLAYERS - 1
const MATCH_SCENE: String = "res://scenes/test_map.tscn"
const MENU_SCENE: String = "res://scenes/main_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/lobby.tscn"

enum Mode {
	NONE,            ## No session: sitting in the main menu.
	SINGLE_PLAYER,   ## Offline. No peer, but still "authoritative".
	HOST,            ## Listen server (authoritative) + local client.
	CLIENT,          ## Joined a remote listen server.
}

## Peer registry changed (join / leave / name change) -- the lobby redraws.
signal players_changed
## A `join_lan()` attempt failed, or the host dropped us. `reason` is
## human-readable and shown in the main menu.
signal connection_error(reason: String)
## This client finished the ENet handshake and registered with the server.
signal connected_to_session
## The host told every peer to load the match scene. Fired on all peers
## (including the host) right before the scene change.
signal match_starting
## Server-side only: every connected peer has reported its match scene
## loaded, so it is safe to spawn player characters.
signal all_peers_loaded

var mode: Mode = Mode.NONE

## peer_id -> { "name": String, "loaded": bool }. Always contains peer 1
## (the host) while a session is live. Mirrored to clients wholesale by
## `_receive_players()`.
var players: Dictionary = {}

## True between "host pressed Start Match" and returning to the lobby/menu.
var match_in_progress: bool = false

var local_player_name: String = "Manifestant"

var _last_error: String = ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --------------------------------------------------------------------------
# Predicates every gameplay system branches on
# --------------------------------------------------------------------------

## True while a networked session (host or client) is live. False in
## single-player, which is what keeps every `rpc()` call site from firing
## with a null multiplayer peer.
func is_multiplayer_session() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT


## True when this process owns the authoritative game simulation: the listen
## server, or single-player (where "the server" is the only peer there is).
##
## This is THE predicate for server-authoritative systems -- crowd
## simulation, police AI, damage, destruction, Grabuge. Clients run the same
## scripts but skip simulation and only interpolate replicated state.
##
## False in `Mode.NONE` too, so nothing simulates while the main menu or
## lobby is up (GameState's Grabuge decay in particular).
func is_authoritative() -> bool:
	return mode == Mode.SINGLE_PLAYER or mode == Mode.HOST


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


func get_local_peer_id() -> int:
	if not is_multiplayer_session():
		return 1
	return multiplayer.get_unique_id()


func get_last_error() -> String:
	return _last_error


# --------------------------------------------------------------------------
# Session lifecycle
# --------------------------------------------------------------------------

## Offline mode. Uses Godot's `OfflineMultiplayerPeer` rather than leaving the
## peer unset: with no peer at all, every `is_multiplayer_authority()` call in
## the game pushes "No multiplayer peer is assigned" (verified headlessly), so
## the authority guards the player/weapon scripts now rely on would spam the
## log every frame. The offline peer reports unique id 1 and `is_server()`,
## which makes all of those checks trivially true and keeps single-player
## behavior identical while sharing one code path with multiplayer.
func start_single_player() -> void:
	begin_single_player_session()
	get_tree().change_scene_to_file(MATCH_SCENE)


## The session half of start_single_player(), without the scene change: sets
## up the offline peer and the single-player mode for a match scene that is
## already being added to the tree by hand. Used by the headless debug
## harnesses (scripts/_debug_verify_*.gd), which instantiate test_map.tscn
## themselves instead of letting the menu change scenes -- without this they
## would run in Mode.NONE, where nothing is authoritative and so nothing
## spawns or simulates at all.
func begin_single_player_session() -> void:
	leave_session()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.SINGLE_PLAYER
	match_in_progress = true
	players = {1: {"name": local_player_name, "loaded": false}}


## Starts the listen server and moves the host into the lobby.
func host_lan(player_name: String = "") -> Error:
	leave_session()
	if player_name != "":
		local_player_name = player_name

	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		_last_error = "Could not open port %d (error %d). Is another host already running?" % [PORT, err]
		connection_error.emit(_last_error)
		return err

	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	players = {1: {"name": local_player_name, "loaded": false}}
	players_changed.emit()
	get_tree().change_scene_to_file(LOBBY_SCENE)
	return OK


## Connects to a listen server by IPv4 address. Success is asynchronous --
## `connected_to_session` or `connection_error` fires later.
func join_lan(address: String, player_name: String = "") -> Error:
	leave_session()
	if player_name != "":
		local_player_name = player_name

	var ip := address.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	if not ip.is_valid_ip_address():
		_last_error = "\"%s\" is not a valid IPv4 address." % ip
		connection_error.emit(_last_error)
		return ERR_INVALID_PARAMETER

	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, PORT)
	if err != OK:
		_last_error = "Could not reach %s:%d (error %d)." % [ip, PORT, err]
		connection_error.emit(_last_error)
		return err

	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	players = {}
	return OK


## Tears the session down and makes a fresh host/join possible without
## restarting the application (spec 3: "Allow sessions to be restarted
## without restarting the application").
func leave_session() -> void:
	# `multiplayer` can still be null very early in startup (before the
	# SceneTree has built its MultiplayerAPI), which a headless
	# `--script` harness can hit -- see scripts/_debug_net_host.gd.
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	mode = Mode.NONE
	players.clear()
	match_in_progress = false


## Drops the session and returns to the main menu, optionally surfacing an
## error for the menu to display.
func return_to_menu(reason: String = "") -> void:
	if reason != "":
		_last_error = reason
	leave_session()
	GameState.reset()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(MENU_SCENE)


# --------------------------------------------------------------------------
# Peer registry
# --------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	# Only the server tracks peers authoritatively; clients learn about each
	# other from `_receive_players()` below.
	if not is_host():
		return
	# No late joining (spec 9): a peer that connects after the match started
	# is dropped immediately rather than left half-joined.
	if match_in_progress:
		print("[NetworkManager] Rejecting peer %d: match already in progress (no late joining)." % id)
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = {"name": "Peer %d" % id, "loaded": false}
	players_changed.emit()
	_broadcast_players()


func _on_peer_disconnected(id: int) -> void:
	if is_host():
		players.erase(id)
		players_changed.emit()
		_broadcast_players()
		# Despawning the player character (and leaving their recruited
		# protesters in the shared crowd) is the match scene's job -- it owns
		# the MultiplayerSpawner. See scenes/test_map.gd.
		var map := get_tree().current_scene
		if map != null and map.has_method("despawn_player"):
			map.despawn_player(id)
	else:
		players.erase(id)
		players_changed.emit()


func _on_connected_to_server() -> void:
	rpc_id(1, "_register_player", local_player_name)
	connected_to_session.emit()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_connection_failed() -> void:
	_last_error = "Connection failed. Check the host's IP and that it is hosting on port %d." % PORT
	leave_session()
	connection_error.emit(_last_error)


## Host dropped. Spec 3: end the session and return clients to the main menu.
func _on_server_disconnected() -> void:
	return_to_menu("The host left the session.")
	connection_error.emit(_last_error)


@rpc("any_peer", "call_remote", "reliable")
func _register_player(player_name: String) -> void:
	if not is_host():
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	players[id]["name"] = player_name
	players_changed.emit()
	_broadcast_players()


func _broadcast_players() -> void:
	if not is_multiplayer_session():
		return
	rpc("_receive_players", players)


@rpc("authority", "call_remote", "reliable")
func _receive_players(remote_players: Dictionary) -> void:
	players = remote_players
	players_changed.emit()


## Display name for a peer, falling back to the raw id.
func get_player_name(id: int) -> String:
	if players.has(id) and players[id].has("name"):
		return str(players[id]["name"])
	return "Peer %d" % id


## Best-guess LAN IPv4 address to read out in the lobby. Skips loopback and
## link-local (169.254.x.x) addresses, which are useless to a joining peer.
func get_lan_address() -> String:
	for address in IP.get_local_addresses():
		if not address.is_valid_ip_address():
			continue
		if address.contains(":"):
			continue  # IPv6
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		return address
	return "127.0.0.1"


# --------------------------------------------------------------------------
# Match start + synchronized scene loading
# --------------------------------------------------------------------------

## Host-only. Tells every peer to load the match scene. Players are not
## spawned until every peer has reported back via `notify_map_loaded()`
## (spec 3: "Wait for connected peers to finish loading before spawning
## players").
func start_match() -> void:
	if not is_host():
		return
	match_in_progress = true
	for id in players:
		players[id]["loaded"] = false
	rpc("_begin_match")


@rpc("authority", "call_local", "reliable")
func _begin_match() -> void:
	match_in_progress = true
	match_starting.emit()
	# Deferred: changing scenes from inside an RPC callback would free the
	# node tree the multiplayer layer is mid-way through iterating.
	get_tree().call_deferred("change_scene_to_file", MATCH_SCENE)


## Called by the match scene (scenes/test_map.gd) once it is fully in the
## tree. In single-player this short-circuits straight to `all_peers_loaded`.
func notify_map_loaded() -> void:
	if not is_multiplayer_session():
		all_peers_loaded.emit()
		return
	if is_host():
		_report_loaded_on_server(1)
	else:
		rpc_id(1, "_peer_map_loaded")


@rpc("any_peer", "call_remote", "reliable")
func _peer_map_loaded() -> void:
	if not is_host():
		return
	_report_loaded_on_server(multiplayer.get_remote_sender_id())


func _report_loaded_on_server(id: int) -> void:
	if not players.has(id):
		return
	players[id]["loaded"] = true
	players_changed.emit()
	for peer_id in players:
		if not players[peer_id].get("loaded", false):
			return
	all_peers_loaded.emit()


## Host-only. Ends the current match and sends every peer back to the lobby
## so another round can be started without relaunching the game.
func return_to_lobby() -> void:
	if not is_host():
		return
	match_in_progress = false
	rpc("_back_to_lobby")


@rpc("authority", "call_local", "reliable")
func _back_to_lobby() -> void:
	match_in_progress = false
	GameState.reset()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().call_deferred("change_scene_to_file", LOBBY_SCENE)
