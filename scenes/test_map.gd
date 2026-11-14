extends Node3D

## Match bootstrap: owns the match lifecycle for both single-player and LAN
## co-op, and is the one place that knows how players get into the world.
##
## Responsibilities:
##   * capture the mouse for FPS look (as before)
##   * register the spawnable scenes on the three MultiplayerSpawners
##   * perform the synchronized-load handshake with NetworkManager and spawn
##     player characters only once every peer has the map loaded (spec 3)
##   * start the civilian/police spawners after that (their spawn packets
##     would otherwise arrive at peers whose spawner nodes don't exist yet)
##   * run the server-side 5-second respawn loop (spec 4.4)
##   * despawn players whose peer disconnected, leaving their recruited
##     protesters in the shared crowd (spec 3)
##
## Single-player goes through the exact same spawn path with no peer
## attached, so there is one code path to keep working rather than two.

const PLAYER_SCENE_PATH: String = "res://scenes/player.tscn"
const NPC_SCENE_PATH: String = "res://scenes/npc.tscn"
const POLICE_SCENE_PATH: String = "res://scenes/police.tscn"

## Seconds a downed player waits before respawning (spec 4.4).
const RESPAWN_DELAY: float = 5.0
## Radius of the ring player spawn points are distributed around PlayerSpawn,
## so four players don't materialize inside each other.
const SPAWN_RING_RADIUS: float = 2.5

@onready var _players_root: Node3D = $Players
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _npc_replicator: MultiplayerSpawner = $NPCReplicator
@onready var _police_replicator: MultiplayerSpawner = $PoliceReplicator
@onready var _npc_spawner: NPCSpawner = $NPCSpawner
@onready var _police_spawner: PoliceSpawner = $PoliceSpawner
@onready var _hud: CanvasLayer = $HUD

var _player_scene: PackedScene
## Spawn-slot index per peer, so a respawning player goes back to the slot
## they started in instead of drifting around the ring.
var _spawn_slots: Dictionary = {}


func _ready() -> void:
	_player_scene = load(PLAYER_SCENE_PATH)

	# Registered in code rather than in the .tscn so the list is guaranteed
	# byte-identical on every peer (the spawner matches scenes by index).
	_player_spawner.add_spawnable_scene(PLAYER_SCENE_PATH)
	_npc_replicator.add_spawnable_scene(NPC_SCENE_PATH)
	_police_replicator.add_spawnable_scene(POLICE_SCENE_PATH)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	NetworkManager.all_peers_loaded.connect(_on_all_peers_loaded)
	# Tell NetworkManager we're in the tree. In single-player this fires
	# `all_peers_loaded` straight back on the same frame.
	NetworkManager.notify_map_loaded()


## Fires on every peer, but only the server spawns -- the MultiplayerSpawner
## mirrors each spawn to the clients.
func _on_all_peers_loaded() -> void:
	if not NetworkManager.is_authoritative():
		return

	var peer_ids: Array = NetworkManager.players.keys()
	if peer_ids.is_empty():
		peer_ids = [1]
	peer_ids.sort()
	for i in peer_ids.size():
		_spawn_slots[peer_ids[i]] = i
		_spawn_player(int(peer_ids[i]), i)

	_npc_spawner.begin_spawning()
	_police_spawner.begin_spawning()


## Server-side player spawn. The node name is the owning peer id, which is
## how scripts/player.gd derives multiplayer authority -- and the
## MultiplayerSpawner replicates the name, so every peer agrees on who owns
## which character. Name, position and `net_position` are all set *before*
## add_child(), because that is when spawn state is serialized for clients.
func _spawn_player(peer_id: int, slot: int) -> void:
	if _players_root.has_node(str(peer_id)):
		return
	var spawn_position: Vector3 = _spawn_position_for(slot)
	var player: Node3D = _player_scene.instantiate()
	player.name = str(peer_id)
	player.position = spawn_position
	player.net_position = spawn_position
	_players_root.add_child(player)

	player.health.died.connect(_on_player_died.bind(player))


## Distributes spawn points evenly around a ring centered on the PlayerSpawn
## marker.
func _spawn_position_for(slot: int) -> Vector3:
	var origin: Vector3 = $PlayerSpawn.global_position
	if slot <= 0:
		return origin
	var angle: float = TAU * float(slot) / float(NetworkManager.MAX_PLAYERS)
	return origin + Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RING_RADIUS


## Called by NetworkManager when a peer drops. Frees that peer's character
## (the spawner turns this into a despawn on the remaining clients) and
## deliberately leaves the protesters they recruited in the shared crowd --
## there are no player-owned squads, so there is nothing to clean up (spec 3:
## "Preserve their recruited protesters").
func despawn_player(peer_id: int) -> void:
	if not NetworkManager.is_authoritative():
		return
	var player: Node = _players_root.get_node_or_null(str(peer_id))
	if player != null:
		player.queue_free()
	_spawn_slots.erase(peer_id)


# --------------------------------------------------------------------------
# Death and respawn (server-authoritative)
# --------------------------------------------------------------------------

## Single-player keeps its original behavior: the player's death is a
## game-over condition alongside Grabuge collapse (see
## agents/police-notes.md). In multiplayer a death is not a game over -- the
## protest carries on and the player respawns after RESPAWN_DELAY (spec 4.4).
func _on_player_died(player: Node3D) -> void:
	if not NetworkManager.is_authoritative():
		return

	if not NetworkManager.is_multiplayer_session():
		GameState.trigger_player_death()
		return

	player.server_set_down()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_instance_valid(player):
		return
	var slot: int = int(_spawn_slots.get(player.name.to_int(), 0))
	player.server_respawn(_spawn_position_for(slot))


func _process(_delta: float) -> void:
	# The HUD binds to the locally owned player, which only exists once the
	# spawn handshake completes -- so bind it on the first frame it shows up
	# rather than assuming a fixed scene path like it used to.
	if _hud.has_method(&"is_bound") and not _hud.is_bound():
		var local_player: Node3D = PlayerRegistry.local(self)
		if local_player != null:
			_hud.bind_player(local_player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		# Leaving a match returns to the main menu (and tears down the
		# session) rather than quitting the application, so another
		# host/join can be started without relaunching (spec 3).
		NetworkManager.return_to_menu()
		return

	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# --- DEBUG HOOKS ---
	# G is the permanent Grabuge debug key per the original spec. O/I are
	# temporary stand-ins for contextual-disruption gameplay that doesn't
	# exist yet. All three go through GameState, whose mutators are
	# server-authoritative -- so on a client they are no-ops rather than a
	# way to desync the shared score.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_G:
				GameState.add_grabuge(GameState.DEBUG_GRABUGE_BUMP)
			KEY_O:
				GameState.recruit_npc()
			KEY_I:
				GameState.record_disruption()
